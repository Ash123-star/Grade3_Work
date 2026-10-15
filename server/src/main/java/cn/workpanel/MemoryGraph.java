package cn.workpanel;

import org.neo4j.driver.*;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import java.time.Duration;
import java.util.*;

@Service
public class MemoryGraph {
    final Db db; final Driver driver; final boolean enabled; volatile boolean healthy=false;
    MemoryGraph(Db db,@Value("${app.neo4j-uri}") String uri,@Value("${app.neo4j-username}") String username,@Value("${app.neo4j-password}") String password,@Value("${app.jobs-enabled}") boolean enabled) {
        this.db=db; this.enabled=enabled;
        driver=uri.isBlank()?null:GraphDatabase.driver(uri,AuthTokens.basic(username,password),Config.builder().withConnectionTimeout(3,java.util.concurrent.TimeUnit.SECONDS).withMaxConnectionPoolSize(4).build());
    }
    boolean available() { return healthy; }
    @Scheduled(fixedDelay=5000) void scheduled() { if(enabled) project(); }
    synchronized void project() {
        if(driver==null) return;
        try(var session=driver.session()) {
            session.run("CREATE CONSTRAINT memory_identity IF NOT EXISTS FOR (m:Memory) REQUIRE (m.company,m.id) IS UNIQUE").consume();
            for(var company:db.rows("SELECT id FROM companies ORDER BY id")) {
                String cid=Db.str(company,"id");
                var nodes=db.rows("SELECT company_id,id,domain,scope_type,scope_id,owner_id,category,version,status,source_type,source_id,source_version FROM memory_items WHERE company_id=? ORDER BY id",cid);
                var relations=db.rows("SELECT r.* FROM memory_relations r JOIN memory_items f ON f.id=r.from_id JOIN memory_items t ON t.id=r.to_id WHERE r.company_id=? AND f.domain=t.domain AND f.scope_id=t.scope_id ORDER BY r.id",cid);
                String revision=Db.hash(nodes.toString()+relations.toString());
                var projection=db.rows("SELECT projected_revision,state FROM memory_projection_state WHERE company_id=?",cid);
                if(!projection.isEmpty()&&"READY".equals(projection.getFirst().get("state"))&&revision.equals(projection.getFirst().get("projected_revision"))&&healthy) continue;
                // 全量快照按公司原子写入；墓碑保留最高版本，乱序旧事件不能复活内容。
                session.executeWrite(tx->{
                    for(var m:nodes) upsertNode(tx,m);
                    tx.run("MATCH (f:Memory {company:$company})-[r:EVIDENCE]->() WHERE NOT r.id IN $ids SET r.status='DELETED',r.version=coalesce(r.version,0)+1",Map.of("company",cid,"ids",relations.stream().map(r->Db.str(r,"id")).toList())).consume();
                    for(var r:relations) upsertRelation(tx,r);
                    return null;
                });
                db.update("INSERT INTO memory_projection_state(company_id,projected_revision,state,updated_at) VALUES (?,?,'READY',now()) ON CONFLICT(company_id) DO UPDATE SET projected_revision=excluded.projected_revision,state='READY',last_error=NULL,updated_at=now()",cid,revision);
                db.update("UPDATE memory_forget_jobs SET state='SUCCEEDED' WHERE company_id=? AND state='PENDING' AND NOT EXISTS (SELECT 1 FROM knowledge_chunks c JOIN memory_items m ON m.id=c.memory_id WHERE m.company_id=? AND m.status='DELETED')",cid,cid);
            } healthy=true;
        } catch(Exception e) { healthy=false; db.update("UPDATE memory_projection_state SET state='FAILED',last_error='图投影暂时不可用'"); }
    }
    void upsertNode(TransactionContext tx,Map<String,Object> m) {
        tx.run("MERGE (n:Memory {company:$company,id:$id}) WITH n WHERE n.version IS NULL OR n.version <= $version SET n.domain=$domain,n.scope=$scope,n.owner=$owner,n.category=$category,n.status=$status,n.version=$version",Map.of("company",m.get("company_id"),"id",m.get("id"),"domain",m.get("domain"),"scope",m.get("scope_id"),"owner",m.get("owner_id"),"category",m.get("category"),"status",m.get("status"),"version",m.get("version"))).consume();
    }
    void upsertRelation(TransactionContext tx,Map<String,Object> r) {
        tx.run("MATCH (f:Memory {company:$company,id:$from}),(t:Memory {company:$company,id:$to}) MERGE (f)-[e:EVIDENCE {id:$id}]->(t) WITH e WHERE e.version IS NULL OR e.version <= $version SET e.status=$status,e.version=$version",Map.of("company",r.get("company_id"),"from",r.get("from_id"),"to",r.get("to_id"),"id",r.get("id"),"status",r.get("status"),"version",r.get("version"))).consume();
    }
    void applyNodeEvent(Map<String,Object> event) {
        try(var session=driver.session()) { session.executeWrite(tx->{upsertNode(tx,event);return null;}); }
    }
    void applyRelationEvent(Map<String,Object> event) {
        try(var session=driver.session()) { session.executeWrite(tx->{upsertRelation(tx,event);return null;}); }
    }
    List<Map<String,Object>> paths(String company,Set<String> allowed,List<String> seeds) {
        if(driver==null||!healthy||allowed.isEmpty()||seeds.isEmpty()) return List.of();
        try(var session=driver.session()) {
            Map<String,Object> versions=new HashMap<>(); for(var m:db.rows("SELECT id,version FROM memory_items WHERE company_id=? AND status='ACTIVE'",company)) if(allowed.contains(Db.str(m,"id"))) versions.put(Db.str(m,"id"),m.get("version"));
            Map<String,Object> edges=new HashMap<>(); for(var r:db.rows("SELECT id,from_id,to_id,version FROM memory_relations WHERE company_id=? AND status='ACTIVE'",company)) if(allowed.contains(r.get("from_id"))&&allowed.contains(r.get("to_id"))) edges.put(Db.str(r,"id"),r.get("version"));
            var rows=session.executeRead(tx->tx.run("MATCH p=(f:Memory)-[:EVIDENCE*1..3]->(t:Memory) WHERE f.company=$company AND f.id IN $seeds AND ALL(n IN nodes(p) WHERE n.company=$company AND n.status='ACTIVE' AND n.id IN $allowed AND n.version=$versions[n.id]) AND ALL(r IN relationships(p) WHERE r.status='ACTIVE' AND r.version=$edges[r.id]) RETURN f.id AS from,t.id AS to,length(p) AS hops LIMIT 20",Map.of("company",company,"seeds",seeds,"allowed",new ArrayList<>(allowed),"versions",versions,"edges",edges)).list(org.neo4j.driver.Record::asMap),TransactionConfig.builder().withTimeout(Duration.ofSeconds(3)).build());
            return rows;
        } catch(Exception e) { healthy=false; return List.of(); }
    }
    @jakarta.annotation.PreDestroy void stop() { if(driver!=null) driver.close(); }
}
