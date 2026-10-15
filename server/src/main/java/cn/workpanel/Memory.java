package cn.workpanel;

import jakarta.servlet.http.HttpServletRequest;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.web.bind.annotation.*;
import java.util.*;

/** 权威记忆在 PostgreSQL；任何衍生索引都不替代当前权限与原始来源。 */
@Service
public class Memory {
    final Db db; final Business business; final Reviews reviews; final boolean enabled; final TransactionTemplate indexTransaction;
    Memory(Db db,Business business,Reviews reviews,PlatformTransactionManager manager,@Value("${app.jobs-enabled}") boolean enabled) {
        this.db=db; this.business=business; this.reviews=reviews; this.enabled=enabled;
        indexTransaction=manager==null?null:new TransactionTemplate(manager);
        if(indexTransaction!=null) indexTransaction.setPropagationBehavior(TransactionDefinition.PROPAGATION_NESTED);
    }
    record Scope(String domain,String type,String id) {}
    public boolean jobsEnabled() { return enabled; }
    public Db database() { return db; }
    public Business sourceBusiness() { return business; }
    Actor fresh(Actor a) {
        Actor current=Actor.from(db.one("SELECT * FROM users WHERE company_id=? AND id=?",a.company(),a.id()));
        if(!current.status().equals("ACTIVE")||current.mustChange()) throw ApiError.forbidden(); return current;
    }
    Scope scope(Actor actor,String domain,String type,String id) {
        Actor a=fresh(actor); if(domain.equals("PERSONAL")) {
            if(!type.isBlank()&&!type.equals("SELF")||!id.isBlank()&&!id.equals(a.id())) throw ApiError.forbidden();
            return new Scope(domain,"SELF",a.id());
        }
        if(!domain.equals("ORGANIZATION")||!a.manager()) throw ApiError.forbidden();
        if(type.isBlank()) type=a.global()?"COMPANY":a.role().equals("DIRECTOR")?"DEPARTMENT":"TEAM";
        if(id.isBlank()) id=type.equals("COMPANY")?a.company():type.equals("DEPARTMENT")?a.department():a.team();
        boolean permitted=switch(type) {
            case "COMPANY" -> a.global()&&id.equals(a.company());
            case "DEPARTMENT" -> !id.isBlank()&&(a.global()||a.role().equals("DIRECTOR")&&id.equals(a.department()));
            case "TEAM" -> !id.isBlank()&&(a.global()||a.role().equals("LEADER")&&id.equals(a.team())||a.role().equals("DIRECTOR")&&db.count("SELECT count(*) FROM teams WHERE company_id=? AND id=? AND department_id=?",a.company(),id,a.department())==1);
            default -> false;
        };
        if(!permitted) throw ApiError.forbidden();
        if(type.equals("TEAM")) db.one("SELECT id FROM teams WHERE company_id=? AND id=?",a.company(),id);
        if(type.equals("DEPARTMENT")) db.one("SELECT id FROM departments WHERE company_id=? AND id=?",a.company(),id);
        return new Scope(domain,type,id);
    }
    List<Map<String,Object>> scopes(Actor actor) {
        Actor a=fresh(actor); var out=new ArrayList<Map<String,Object>>();
        out.add(Map.of("domain","PERSONAL","scopeType","SELF","scopeId",a.id(),"label","个人"));
        if(a.manager()) {
            if(a.global()) out.add(Map.of("domain","ORGANIZATION","scopeType","COMPANY","scopeId",a.company(),"label","全公司"));
            if(!a.department().isBlank()&&(a.global()||a.role().equals("DIRECTOR"))) out.add(Map.of("domain","ORGANIZATION","scopeType","DEPARTMENT","scopeId",a.department(),"label","本部门"));
            if(!a.team().isBlank()) out.add(Map.of("domain","ORGANIZATION","scopeType","TEAM","scopeId",a.team(),"label","本团队"));
        } return out;
    }
    boolean visible(Actor a,Map<String,Object> m,Scope s) {
        if(!a.company().equals(m.get("company_id"))||!s.domain.equals(m.get("domain"))) return false;
        if(s.domain.equals("PERSONAL")) return a.id().equals(m.get("owner_id"));
        if(!a.manager()) return false;
        if(Db.str(m,"source_type").equals("MANUAL")) {
            String type=Db.str(m,"scope_type"), id=Db.str(m,"scope_id");
            if(s.type.equals("COMPANY")) return true;
            if(type.equals(s.type)&&id.equals(s.id)) return true;
            return s.type.equals("DEPARTMENT")&&type.equals("TEAM")&&db.count("SELECT count(*) FROM teams WHERE company_id=? AND id=? AND department_id=?",a.company(),id,s.id)==1;
        }
        var owner=db.one("SELECT * FROM users WHERE company_id=? AND id=?",a.company(),m.get("owner_id"));
        return a.canSeeUser(owner)&&(s.type.equals("COMPANY")||s.type.equals("TEAM")&&s.id.equals(owner.get("team_id"))||s.type.equals("DEPARTMENT")&&s.id.equals(owner.get("department_id")));
    }
    boolean sourceValid(Actor a,Map<String,Object> m) {
        try {
            if(db.count("SELECT count(*) FROM memory_exclusions WHERE company_id=? AND domain=? AND scope_id=? AND source_type=? AND source_id=?",a.company(),m.get("domain"),m.get("scope_id"),m.get("source_type"),m.get("source_id"))>0) return false;
            String type=Db.str(m,"source_type"); if(type.equals("MANUAL")) return true;
            Map<String,Object> source=switch(type) {
                case "LOG" -> business.log(a,Db.str(m,"source_id"),false);
                case "TASK" -> business.task(a,Db.str(m,"source_id"),false);
                case "ITEM" -> db.one("SELECT * FROM dashboard_items WHERE company_id=? AND id=? AND NOT archived AND (kind='COMPANY' OR owner_id=?)",a.company(),m.get("source_id"),a.id());
                default -> throw ApiError.forbidden();
            };
            if(type.equals("LOG")&&(!(boolean)source.get("submitted")||!a.id().equals(source.get("owner_id")))) return false;
            return source.get("version").equals(m.get("source_version"))&&(!type.equals("TASK")||!source.get("phase").equals("WITHDRAWN"));
        } catch(ApiError e) { return false; }
    }
    List<Map<String,Object>> eligible(Actor actor,Scope s,boolean candidates) {
        Actor a=fresh(actor); String where="company_id=? AND domain=? AND status IN ('ACTIVE'"+(candidates?",'CANDIDATE'":"")+")";
        var args=new ArrayList<Object>(List.of(a.company(),s.domain));
        if(s.domain.equals("PERSONAL")) { where+=" AND owner_id=?"; args.add(a.id()); }
        return db.rows("SELECT * FROM memory_items WHERE "+where+" ORDER BY updated_at DESC,id",args.toArray()).stream().filter(m->visible(a,m,s)&&sourceValid(a,m)).toList();
    }
    Map<String,Object> item(Actor actor,String id) {
        Actor a=fresh(actor); var m=db.one("SELECT * FROM memory_items WHERE company_id=? AND id=?",a.company(),id);
        Scope s=scope(a,Db.str(m,"domain"),Db.str(m,"domain").equals("PERSONAL")?"SELF":"","");
        if(!visible(a,m,s)) throw ApiError.forbidden();
        if(!Db.str(m,"status").equals("DELETED")&&!sourceValid(a,m)) throw new ApiError(409,"MEMORY_SOURCE_STALE","来源已变化，请等待重新提取");
        return m;
    }
    Map<String,Object> preferences(Actor actor) {
        Actor a=fresh(actor); var rows=db.rows("SELECT explicit_goals,response_preferences,version FROM memory_preferences WHERE company_id=? AND owner_id=?",a.company(),a.id());
        return rows.isEmpty()?Map.of("explicit_goals","","response_preferences","","version",0):rows.getFirst();
    }
    @Transactional public Map<String,Object> preferences(Actor actor,Map<String,Object> b) {
        Db.fields(b,"version","explicitGoals","responsePreferences"); Actor a=fresh(actor); int v=Db.version(b);
        String goals=Ai.sanitize(Db.str(b,"explicitGoals")), pref=Ai.sanitize(Db.str(b,"responsePreferences"));
        if(goals.length()>2000||pref.length()>2000) throw ApiError.bad("MEMORY_LENGTH","目标和偏好最多 2000 字");
        if(v==0) db.update("INSERT INTO memory_preferences(company_id,owner_id,explicit_goals,response_preferences) VALUES (?,?,?,?)",a.company(),a.id(),goals,pref);
        else Db.conflict(db.update("UPDATE memory_preferences SET explicit_goals=?,response_preferences=?,version=version+1 WHERE company_id=? AND owner_id=? AND version=?",goals,pref,a.company(),a.id(),v));
        db.update("UPDATE development_analyses SET state='STALE',output=NULL,input_manifest='{}',error='目标与偏好更新' WHERE company_id=? AND owner_id=? AND domain='PERSONAL' AND state IN ('QUEUED','RUNNING','SUCCEEDED')",a.company(),a.id());
        return preferences(a);
    }
    @Transactional public Map<String,Object> create(Actor actor,Map<String,Object> b) {
        Db.fields(b,"domain","scopeType","scopeId","category","claimType","content","reason"); Actor a=fresh(actor);
        Scope s=scope(a,Db.str(b,"domain").isBlank()?"PERSONAL":Db.str(b,"domain"),Db.str(b,"scopeType"),Db.str(b,"scopeId"));
        String category=Db.str(b,"category").isBlank()?"EXPERIENCE":Db.str(b,"category"), claim=Db.str(b,"claimType").isBlank()?"FACT":Db.str(b,"claimType"); validate(category,claim);
        String content=Ai.sanitize(Db.required(b,"content")); if(content.length()>4000) throw ApiError.bad("MEMORY_LENGTH","记忆最多 4000 字");
        String id=Db.id(); insert(a.company(),s,a.id(),id,category,claim,s.domain.equals("PERSONAL")&&claim.equals("FACT")?"ACTIVE":"CANDIDATE",content,"MANUAL",id,1,"self","SELF_REPORTED","本人或组织人员补充");
        if(s.domain.equals("ORGANIZATION")) return reviews.create(a,"MEMORY",id,1,Map.of(),Map.of("content",content,"category",category,"claimType",claim,"domain",s.domain,"scopeType",s.type,"scopeId",s.id),Db.required(b,"reason"));
        return item(a,id);
    }
    static void validate(String category,String claim) {
        if(!Set.of("EXPERIENCE","OUTCOME","GOAL","PREFERENCE","LESSON","SKILL").contains(category)||!Set.of("FACT","OBSERVATION","HYPOTHESIS").contains(claim)) throw ApiError.bad("MEMORY_TYPE","记忆类型无效");
    }
    void insert(String company,Scope s,String owner,String id,String category,String claim,String state,String content,String source,String sourceId,int sourceV,String locator,String provenance,String reason) {
        if(db.count("SELECT count(*) FROM memory_exclusions WHERE company_id=? AND domain=? AND scope_id=? AND source_type=? AND source_id=?",company,s.domain,s.id,source,sourceId)>0) return;
        int n=db.update("INSERT INTO memory_items(id,company_id,domain,owner_id,scope_type,scope_id,category,claim_type,status,content,source_type,source_id,source_version,locator,provenance,selection_reason) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(company_id,domain,scope_type,scope_id,source_type,source_id,source_version,locator) DO NOTHING",id,company,s.domain,owner,s.type,s.id,category,claim,state,content,source,sourceId,sourceV,locator,provenance,reason);
        if(n==1) snapshot(company,id);
    }
    void snapshot(String company,String id) {
        var m=db.one("SELECT * FROM memory_items WHERE company_id=? AND id=?",company,id);
        db.update("INSERT INTO memory_versions(company_id,memory_id,version,content,claim_type,provenance,status) VALUES (?,?,?,?,?,?,?) ON CONFLICT DO NOTHING",company,id,m.get("version"),m.get("content"),m.get("claim_type"),m.get("provenance"),m.get("status"));
        db.update("INSERT INTO memory_sources VALUES (?,?,?,?,?,?,?) ON CONFLICT DO NOTHING",company,id,m.get("version"),m.get("source_type"),m.get("source_id"),m.get("source_version"),m.get("locator"));
        db.update("INSERT INTO knowledge_index_state(company_id) VALUES (?) ON CONFLICT DO NOTHING",company);
        var state=db.one("SELECT active_version,building_version FROM knowledge_index_state WHERE company_id=? FOR SHARE",company);
        queueIndex(company,id,m.get("version"),Db.str(state,"active_version"));
        if(!Db.str(state,"building_version").isBlank()) queueIndex(company,id,m.get("version"),Db.str(state,"building_version"));
        invalidate(company,"记忆发生变化");
    }
    void queueIndex(String company,String id,Object version,String chunker) {
        db.update("INSERT INTO knowledge_index_jobs(id,company_id,memory_id,memory_version,chunker_version) VALUES (?,?,?,?,?) ON CONFLICT(company_id,memory_id,memory_version,chunker_version) DO NOTHING",Db.id(),company,id,version,chunker);
    }
    void invalidate(String company,String reason) {
        db.update("UPDATE development_analyses SET state='STALE',output=NULL,input_manifest='{}',error=? WHERE company_id=? AND state IN ('QUEUED','RUNNING','SUCCEEDED')",reason,company);
        db.update("DELETE FROM rag_retrieval_runs WHERE company_id=?",company);
        db.update("INSERT INTO memory_projection_state(company_id) VALUES (?) ON CONFLICT(company_id) DO UPDATE SET state='PENDING'",company);
    }
    @Transactional public Map<String,Object> revise(Actor actor,String id,Map<String,Object> b,boolean confirm) {
        Db.fields(b,"version","reason","candidate"); Actor a=fresh(actor); var m=item(a,id); int v=Db.version(b); if(v!=((Number)m.get("version")).intValue()) throw ApiError.conflict();
        var c=b.containsKey("candidate")?db.read(b.get("candidate")):Map.<String,Object>of(); Db.fields(c,"content");
        String content=Ai.sanitize(c.isEmpty()?Db.str(m,"content"):Db.required(c,"content")); if(content.length()>4000) throw ApiError.bad("MEMORY_LENGTH","记忆最多 4000 字");
        if(m.get("domain").equals("ORGANIZATION")) return reviews.create(a,"MEMORY",id,v,Map.of("id",id,"version",v),Map.of("content",content,"category",m.get("category"),"claimType",m.get("claim_type"),"domain",m.get("domain"),"scopeType",m.get("scope_type"),"scopeId",m.get("scope_id")),Db.required(b,"reason"));
        if(!a.id().equals(m.get("owner_id"))) throw ApiError.forbidden();
        if(!Db.str(m,"source_type").equals("MANUAL")&&Db.str(m,"claim_type").equals("FACT")&&!confirm) {
            Db.conflict(db.update("UPDATE memory_items SET status='DISPUTED',version=version+1,updated_at=now() WHERE id=? AND version=?",id,v)); snapshot(a.company(),id);
            return Map.of("id",id,"status","DISPUTED","message","已停止引用，请到原业务记录提交正式修订");
        }
        if(confirm&&!Db.str(m,"status").equals("CANDIDATE")) throw ApiError.conflict();
        Db.conflict(db.update("UPDATE memory_items SET content=?,status='ACTIVE',version=version+1,updated_at=now() WHERE id=? AND version=? AND status IN ('ACTIVE','CANDIDATE')",content,id,v));
        if(confirm) db.update("UPDATE memory_relations SET status='ACTIVE',version=version+1 WHERE company_id=? AND to_id=? AND status='CANDIDATE'",a.company(),id);
        snapshot(a.company(),id); return item(a,id);
    }
    @Transactional public Map<String,Object> forget(Actor actor,String id,int v) {
        Actor a=fresh(actor); var m=item(a,id); if(m.get("domain").equals("ORGANIZATION")&&!a.global()) throw ApiError.forbidden();
        Db.conflict(db.update("UPDATE memory_items SET status='DELETED',content='',version=version+1,updated_at=now() WHERE company_id=? AND id=? AND version=? AND status<>'DELETED'",a.company(),id,v));
        db.update("INSERT INTO memory_exclusions(company_id,actor_id,domain,scope_id,source_type,source_id) VALUES (?,?,?,?,?,?) ON CONFLICT DO NOTHING",a.company(),a.id(),m.get("domain"),m.get("scope_id"),m.get("source_type"),m.get("source_id"));
        db.update("UPDATE memory_items SET status='DELETED',content='',version=version+1,updated_at=now() WHERE company_id=? AND domain=? AND scope_id=? AND source_type=? AND source_id=? AND status<>'DELETED'",a.company(),m.get("domain"),m.get("scope_id"),m.get("source_type"),m.get("source_id"));
        invalidate(a.company(),"记忆已遗忘"); String job=Db.id(); db.update("INSERT INTO memory_forget_jobs(id,company_id,owner_id,memory_id) VALUES (?,?,?,?)",job,a.company(),a.id(),id);
        return Map.of("id",job,"state","PENDING","message","已停止使用，正在清理");
    }
    @Scheduled(fixedDelay=1500) @Transactional public void work() {
        if(!enabled) return; process();
    }
    @Transactional public void process() {
        for(var e:db.rows("SELECT * FROM outbox_events WHERE type='MEMORY_SOURCE' AND delivered_at IS NULL ORDER BY created_at LIMIT 25 FOR UPDATE SKIP LOCKED")) {
            var b=db.read(e.get("body")); ingest(Db.str(e,"company_id"),Db.str(b,"sourceType"),Db.str(e,"object_id"));
            db.update("UPDATE outbox_events SET delivered_at=now() WHERE id=?",e.get("id"));
        }
        for(var j:db.rows("SELECT * FROM knowledge_index_jobs WHERE state='QUEUED' ORDER BY created_at LIMIT 50 FOR UPDATE SKIP LOCKED")) {
            try { indexTransaction.executeWithoutResult(status->processIndexJob(j)); }
            catch(Exception e) { db.update("UPDATE knowledge_index_jobs SET state='FAILED',error='索引构建失败，请重试' WHERE id=?",j.get("id")); }
        }
        backfillIndexPage(50);
        for(var j:db.rows("SELECT * FROM memory_forget_jobs WHERE state='PENDING' ORDER BY created_at LIMIT 25 FOR UPDATE SKIP LOCKED")) {
            String company=Db.str(j,"company_id");
            db.update("DELETE FROM knowledge_chunks c USING memory_items m WHERE c.memory_id=m.id AND m.company_id=? AND m.status='DELETED'",company);
            db.update("UPDATE memory_versions v SET content='' FROM memory_items m WHERE v.memory_id=m.id AND m.company_id=? AND m.status='DELETED'",company);
            db.update("UPDATE memory_relations r SET status='DELETED',version=r.version+1 FROM memory_items m WHERE m.company_id=? AND m.status='DELETED' AND r.company_id=m.company_id AND (r.from_id=m.id OR r.to_id=m.id) AND r.status<>'DELETED'",company);
            db.update("UPDATE memory_extraction_jobs x SET state='FAILED',error='来源记忆已删除' FROM memory_items m WHERE x.company_id=? AND m.id=? AND x.company_id=m.company_id AND x.source_type=m.source_type AND x.source_id=m.source_id AND x.state IN ('QUEUED','RUNNING')",company,j.get("memory_id"));
            // 图清理确认后再标完成；Neo4j 不可用时停用仍立即生效。
        }
    }
    void processIndexJob(Map<String,Object> j) {
            var m=db.one("SELECT * FROM memory_items WHERE company_id=? AND id=?",j.get("company_id"),j.get("memory_id"));
            var state=db.one("SELECT active_version,building_version FROM knowledge_index_state WHERE company_id=? FOR SHARE",j.get("company_id"));
            String chunker=Db.str(j,"chunker_version");
            boolean current=chunker.equals(state.get("active_version"))||chunker.equals(state.get("building_version"));
            if(!m.get("status").equals("ACTIVE")||!m.get("version").equals(j.get("memory_version"))||!current) {
                db.update("DELETE FROM knowledge_chunks WHERE company_id=? AND memory_id=? AND (memory_version<>? OR chunker_version=?)",j.get("company_id"),j.get("memory_id"),m.get("version"),chunker);
                db.update("UPDATE knowledge_index_jobs SET state='SUCCEEDED',error=NULL WHERE id=?",j.get("id"));
                return;
            }
            db.update("DELETE FROM knowledge_chunks WHERE company_id=? AND memory_id=? AND (memory_version<>? OR chunker_version=?)",j.get("company_id"),j.get("memory_id"),m.get("version"),chunker);
            index(m,chunker);
            db.update("UPDATE knowledge_index_jobs SET state='SUCCEEDED',error=NULL WHERE id=?",j.get("id"));
    }
    void index(Map<String,Object> m,String chunker) {
        int step=chunker.startsWith("v2:")?360:420, width=chunker.startsWith("v2:")?420:500;
        String text=Db.str(m,"content"); for(int start=0;start<text.length();start+=step) {
            String part=text.substring(start,Math.min(start+width,text.length())), locator=Db.str(m,"locator")+":"+start;
            db.update("INSERT INTO knowledge_chunks(id,company_id,memory_id,memory_version,source_type,source_id,source_version,locator,chunk_text,content_hash,chunker_version,search_text) VALUES (?,?,?,?,?,?,?,?,?,?,?,to_tsvector('simple',?)) ON CONFLICT DO NOTHING",Db.hash(m.get("id")+":"+m.get("version")+":"+chunker+":"+start),m.get("company_id"),m.get("id"),m.get("version"),m.get("source_type"),m.get("source_id"),m.get("source_version"),locator,part,Db.hash(part),chunker,Rag.terms(part));
        }
    }
    @Transactional public Map<String,Object> rebuildIndex(Actor actor,String key) {
        Actor a=fresh(actor); a.requireAdmin();
        if(key.isBlank()||key.length()>128) throw ApiError.bad("IDEMPOTENCY_REQUIRED","需要 Idempotency-Key");
        db.update("INSERT INTO knowledge_index_state(company_id) VALUES (?) ON CONFLICT DO NOTHING",a.company());
        var state=db.one("SELECT * FROM knowledge_index_state WHERE company_id=? FOR UPDATE",a.company());
        var old=db.rows("SELECT id FROM knowledge_rebuild_jobs WHERE company_id=? AND request_key=?",a.company(),key);
        if(!old.isEmpty()) return indexJob(a,Db.str(old.getFirst(),"id"));
        if(!Db.str(state,"building_version").isBlank()) throw new ApiError(409,"INDEX_REBUILD_RUNNING","索引重建正在运行");
        String id=Db.id(), target="v2:"+id;
        db.update("INSERT INTO knowledge_rebuild_jobs(id,company_id,request_key,target_version,state) VALUES (?,?,?,?,'BUILDING')",id,a.company(),key,target);
        db.update("UPDATE knowledge_index_state SET building_version=?,rebuild_id=?,cursor_id='',scan_done=false,state='BUILDING',updated_at=now() WHERE company_id=?",target,id,a.company());
        return indexJob(a,id);
    }
    Map<String,Object> indexJob(Actor actor,String id) {
        Actor a=fresh(actor); a.requireAdmin();
        var j=db.one("SELECT id,state,target_version,cursor_id,processed,error FROM knowledge_rebuild_jobs WHERE company_id=? AND id=?",a.company(),id);
        var out=new LinkedHashMap<String,Object>();
        for(String field:List.of("id","state","target_version","cursor_id","processed","error")) out.put(field,j.get(field));
        out.put("failedJobs",db.rows("SELECT id,memory_id,error FROM knowledge_index_jobs WHERE company_id=? AND chunker_version=? AND state='FAILED' ORDER BY created_at LIMIT 20",a.company(),j.get("target_version")));
        out.put("type","KNOWLEDGE_INDEX");return out;
    }
    @Transactional public Map<String,Object> retryIndexJob(Actor actor,String id) {
        Actor a=fresh(actor); a.requireAdmin();
        var job=db.one("SELECT * FROM knowledge_index_jobs WHERE company_id=? AND id=? FOR UPDATE",a.company(),id);
        if(!"FAILED".equals(job.get("state"))) throw ApiError.conflict();
        var state=db.one("SELECT active_version,building_version FROM knowledge_index_state WHERE company_id=?",a.company());
        String version=Db.str(job,"chunker_version");
        if(!version.equals(state.get("active_version"))&&!version.equals(state.get("building_version"))) throw ApiError.conflict();
        db.update("UPDATE knowledge_index_jobs SET state='QUEUED',error=NULL WHERE id=?",id);
        return Map.of("id",id,"type","KNOWLEDGE_INDEX","state","QUEUED");
    }
    void backfillIndexPage(int limit) {
        for(var state:db.rows("SELECT * FROM knowledge_index_state WHERE state='BUILDING' ORDER BY company_id FOR UPDATE SKIP LOCKED")) {
            String company=Db.str(state,"company_id"), target=Db.str(state,"building_version"), id=Db.str(state,"rebuild_id");
            if(!Boolean.TRUE.equals(state.get("scan_done"))) {
                var page=db.rows("SELECT id,version FROM memory_items WHERE company_id=? AND status='ACTIVE' AND id>? ORDER BY id LIMIT ?",company,state.get("cursor_id"),limit);
                for(var m:page) queueIndex(company,Db.str(m,"id"),m.get("version"),target);
                String cursor=page.isEmpty()?Db.str(state,"cursor_id"):Db.str(page.getLast(),"id");
                db.update("UPDATE knowledge_index_state SET cursor_id=?,scan_done=?,updated_at=now() WHERE company_id=?",cursor,page.size()<limit,company);
                db.update("UPDATE knowledge_rebuild_jobs SET cursor_id=?,processed=processed+? WHERE id=?",cursor,page.size(),id);
            }
            if(db.count("SELECT count(*) FROM knowledge_index_jobs WHERE company_id=? AND chunker_version=? AND state<>'SUCCEEDED'",company,target)>0) continue;
            if(db.count("SELECT count(*) FROM knowledge_index_state WHERE company_id=? AND scan_done",company)==0) continue;
            db.update("UPDATE knowledge_index_state SET active_version=?,building_version=NULL,rebuild_id=NULL,state='READY',cursor_id='',scan_done=false,updated_at=now() WHERE company_id=?",target,company);
            db.update("UPDATE knowledge_rebuild_jobs SET state='SUCCEEDED',finished_at=now() WHERE id=?",id);
            db.update("DELETE FROM knowledge_chunks WHERE company_id=? AND chunker_version<>?",company,target);
            invalidate(company,"知识库索引版本已切换");
        }
    }
    void ingest(String company,String type,String id) {
        String table=switch(type) { case "LOG"->"daily_logs";case "TASK"->"tasks";case "ITEM"->"dashboard_items";default->throw ApiError.bad("SOURCE_TYPE","来源类型无效"); };
        var rows=db.rows("SELECT * FROM "+table+" WHERE company_id=? AND id=?",company,id); if(rows.isEmpty()) return; var src=rows.getFirst();
        if(type.equals("LOG")&&!Boolean.TRUE.equals(src.get("submitted"))) return;
        if(type.equals("TASK")&&src.get("phase").equals("WITHDRAWN")||type.equals("ITEM")&&Boolean.TRUE.equals(src.get("archived"))) {
            db.update("UPDATE memory_items SET status='INVALIDATED',updated_at=now() WHERE company_id=? AND source_type=? AND source_id=? AND status NOT IN ('DELETED','SUPERSEDED','INVALIDATED')",company,type,id);
            invalidate(company,"来源已撤回"); return;
        }
        String owner=Db.str(src,"owner_id"); int version=((Number)src.get("version")).intValue();
        String text=type.equals("LOG")?Ai.sanitize(Db.str(db.read(src.get("body")),"work")):Ai.sanitize(Db.str(src,"title"));
        if(text.isBlank()) return;
        insert(company,new Scope("PERSONAL","SELF",owner),owner,Db.id(),type.equals("TASK")&&Set.of("ACCEPTED","ARCHIVED").contains(src.get("phase"))?"OUTCOME":"EXPERIENCE","FACT","ACTIVE",type.equals("TASK")?"任务："+text+"；角色：主负责人；流转事件："+src.get("phase"):text,type,id,version,type.equals("LOG")?"work":"title","LOG".equals(type)?"SELF_REPORTED":"BUSINESS_EVENT","有效业务记录");
        if(type.equals("TASK")||type.equals("ITEM")&&src.get("kind").equals("COMPANY")) insert(company,new Scope("ORGANIZATION","COMPANY",company),owner,Db.id(),"EXPERIENCE","FACT","ACTIVE",text,type,id,version,"title","BUSINESS_EVENT","公司业务事实");
        db.update("INSERT INTO memory_extraction_jobs(company_id,source_type,source_id,source_version,owner_id) VALUES (?,?,?,?,?) ON CONFLICT(company_id,source_type,source_id,source_version) DO UPDATE SET state='QUEUED',error=NULL WHERE memory_extraction_jobs.state='FAILED'",company,type,id,version,owner);
    }
    @Transactional public Map<String,Object> backfill(Actor actor,int cursor,int limit) {
        Actor a=fresh(actor); a.requireAdmin(); Business.page(cursor,limit);
        var rows=db.rows("SELECT 'LOG' type,id,created_at FROM daily_logs WHERE company_id=? AND submitted UNION ALL SELECT 'TASK',id,created_at FROM tasks WHERE company_id=? UNION ALL SELECT 'ITEM',id,created_at FROM dashboard_items WHERE company_id=? AND NOT archived ORDER BY created_at,id,type LIMIT ? OFFSET ?",a.company(),a.company(),a.company(),limit,cursor);
        for(var r:rows) ingest(a.company(),Db.str(r,"type"),Db.str(r,"id"));
        return Map.of("processed",rows.size(),"nextCursor",cursor+rows.size(),"done",rows.size()<limit);
    }
    Map<String,Object> list(Actor a,Scope s,int cursor,int limit) { Business.page(cursor,limit); var rows=eligible(a,s,true); return Map.of("items",rows.stream().skip(cursor).limit(limit).toList(),"total",rows.size(),"nextCursor",cursor+Math.min(limit,Math.max(0,rows.size()-cursor))); }
}

@RestController
@RequestMapping("/api/ai-memories")
class MemoryApi {
    final Memory m; MemoryApi(Memory m) { this.m=m; }
    @GetMapping Map<String,Object> list(HttpServletRequest r,@RequestParam(defaultValue="PERSONAL") String domain,@RequestParam(defaultValue="") String scopeType,@RequestParam(defaultValue="") String scopeId,@RequestParam(defaultValue="0") int cursor,@RequestParam(defaultValue="30") int limit) { Actor a=Actor.current(r); return m.list(a,m.scope(a,domain,scopeType,scopeId),cursor,limit); }
    @GetMapping("/preferences/me") Map<String,Object> preferences(HttpServletRequest r) { return m.preferences(Actor.current(r)); }
    @PutMapping("/preferences/me") Map<String,Object> preferences(HttpServletRequest r,@RequestBody Map<String,Object> b) { return m.preferences(Actor.current(r),b); }
    @PostMapping Map<String,Object> create(HttpServletRequest r,@RequestBody Map<String,Object> b) { return m.create(Actor.current(r),b); }
    @PostMapping("/{id}/revisions") Map<String,Object> revise(HttpServletRequest r,@PathVariable String id,@RequestBody Map<String,Object> b) { return m.revise(Actor.current(r),id,b,false); }
    @PostMapping("/{id}/confirm") Map<String,Object> confirm(HttpServletRequest r,@PathVariable String id,@RequestBody Map<String,Object> b) { return m.revise(Actor.current(r),id,b,true); }
    @DeleteMapping("/{id}") @ResponseStatus(org.springframework.http.HttpStatus.ACCEPTED) Map<String,Object> forget(HttpServletRequest r,@PathVariable String id,@RequestHeader("If-Match") String v) { return m.forget(Actor.current(r),id,Db.version(Map.of("version",v.replace("\"","")))); }
    @GetMapping("/forget-jobs/{id}") Map<String,Object> forgetJob(HttpServletRequest r,@PathVariable String id) { Actor a=m.fresh(Actor.current(r)); return m.database().one("SELECT id,state,error FROM memory_forget_jobs WHERE company_id=? AND owner_id=? AND id=?",a.company(),a.id(),id); }
    @PostMapping("/backfill") Map<String,Object> backfill(HttpServletRequest r,@RequestParam(defaultValue="0") int cursor,@RequestParam(defaultValue="50") int limit) { return m.backfill(Actor.current(r),cursor,limit); }
    @PostMapping("/index-rebuild") @ResponseStatus(org.springframework.http.HttpStatus.ACCEPTED) Map<String,Object> rebuildIndex(HttpServletRequest r,@RequestHeader("Idempotency-Key") String key) { return m.rebuildIndex(Actor.current(r),key); }
    @GetMapping("/index-rebuild/{id}") Map<String,Object> indexJob(HttpServletRequest r,@PathVariable String id) { return m.indexJob(Actor.current(r),id); }
    @PostMapping("/index-jobs/{id}/retry") @ResponseStatus(org.springframework.http.HttpStatus.ACCEPTED) Map<String,Object> retryIndexJob(HttpServletRequest r,@PathVariable String id) { return m.retryIndexJob(Actor.current(r),id); }
    @GetMapping("/knowledge-status") Map<String,Object> status(HttpServletRequest r,@RequestParam(defaultValue="PERSONAL") String domain,@RequestParam(defaultValue="") String scopeType,@RequestParam(defaultValue="") String scopeId) {
        Actor a=Actor.current(r); var rows=m.eligible(a,m.scope(a,domain,scopeType,scopeId),true);
        var active=rows.stream().filter(x->x.get("status").equals("ACTIVE")).toList(); Set<String> ids=new HashSet<>(); active.forEach(x->ids.add(Db.str(x,"id")));
        String version=Db.str(m.database().one("SELECT active_version FROM knowledge_index_state WHERE company_id=?",a.company()),"active_version");
        long ready=m.database().rows("SELECT DISTINCT c.memory_id FROM knowledge_chunks c JOIN memory_items m ON m.company_id=c.company_id AND m.id=c.memory_id AND m.version=c.memory_version WHERE c.company_id=? AND c.chunker_version=? AND c.index_state='READY'",a.company(),version).stream().filter(x->ids.contains(x.get("memory_id"))).count();
        return Map.of("memories",active.size(),"indexedMemories",ready,"indexingMemories",active.size()-ready,"candidates",rows.stream().filter(x->x.get("status").equals("CANDIDATE")).count());
    }
}
