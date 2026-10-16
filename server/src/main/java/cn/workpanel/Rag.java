package cn.workpanel;

import org.springframework.stereotype.Service;
import java.util.*;
import java.util.regex.Pattern;

/** 中文词与二元字词保证没有外部分词/向量服务也可检索。 */
@Service
public class Rag {
    final Db db; final Memory memory; final MemoryGraph graph;
    Rag(Db db,Memory memory,MemoryGraph graph) { this.db=db; this.memory=memory; this.graph=graph; }
    static List<String> tokens(String text) {
        var out=new LinkedHashSet<String>(); var matcher=Pattern.compile("[\\p{IsHan}]+|[a-zA-Z0-9_]+",Pattern.UNICODE_CASE).matcher(text.toLowerCase(Locale.ROOT));
        while(matcher.find()) { String t=matcher.group();
            if(t.matches("[\\p{IsHan}]+")) { if(t.length()==1) out.add(t); for(int i=0;i<t.length()-1;i++) out.add(t.substring(i,i+2)); }
            else out.add(t);
        } return out.stream().limit(200).toList();
    }
    static String terms(String text) { return String.join(" ",tokens(text)); }
    record Evidence(List<Map<String,Object>> memories,List<Map<String,Object>> chunks,List<Map<String,Object>> paths,String revision,String indexRevision,String chunkerVersion,String degraded) {}
    String revision(Actor a,Memory.Scope scope,List<Map<String,Object>> memories) {
        var refs=new ArrayList<String>(); for(var m:memories) refs.add(m.get("id")+":"+m.get("version")+":"+m.get("source_version")); Collections.sort(refs);
        return Db.hash(String.join("|",refs)+":"+(scope.domain().equals("PERSONAL")?db.write(memory.preferences(a)):"")+":"+a.role()+":"+a.department()+":"+a.team());
    }
    Evidence retrieve(Actor actor,Memory.Scope scope,String goal) {
        Actor a=memory.fresh(actor); var allowed=memory.eligible(a,scope,false); var ids=new LinkedHashSet<String>(); allowed.forEach(m->ids.add(Db.str(m,"id")));
        Map<String,Map<String,Object>> items=new HashMap<>(); allowed.forEach(m->items.put(Db.str(m,"id"),m));
        var chunks=new ArrayList<Map<String,Object>>(); var indexed=new HashSet<String>();
        var query=tokens(goal); String tsquery=String.join(" | ",query.stream().map(t->"'"+t.replace("'","")+"'").toList());
        String activeVersion=Db.str(db.one("SELECT active_version FROM knowledge_index_state WHERE company_id=?",a.company()),"active_version");
        // 排名开始前限定授权 ID；SQL 不在全公司未授权文档上计算匹配分数。
        if(!ids.isEmpty()&&!query.isEmpty()) {
            String sql="SELECT c.*,ts_rank_cd(c.search_text,to_tsquery('simple',?)) AS fulltext_rank FROM knowledge_chunks c JOIN memory_items m ON m.company_id=c.company_id AND m.id=c.memory_id AND m.version=c.memory_version WHERE c.company_id=? AND c.chunker_version=? AND c.memory_id IN ("+String.join(",",Collections.nCopies(ids.size(),"?"))+") AND c.index_state='READY'";
            var args=new ArrayList<Object>(); args.add(tsquery); args.add(a.company()); args.add(activeVersion); args.addAll(ids); chunks.addAll(db.rows(sql,args.toArray())); chunks.forEach(c->indexed.add(Db.str(c,"memory_id")));
        }
        boolean pending=false;
        for(var m:allowed) if(!indexed.contains(Db.str(m,"id"))) { pending=true; if(chunks.size()<100) chunks.add(Map.of("id","direct:"+m.get("id")+":"+m.get("version"),"memory_id",m.get("id"),"memory_version",m.get("version"),"source_type",m.get("source_type"),"source_id",m.get("source_id"),"source_version",m.get("source_version"),"locator",m.get("locator"),"chunk_text",m.get("content"))); }
        var ranked=new ArrayList<>(chunks); ranked.sort(Comparator.<Map<String,Object>>comparingDouble(c->score(Db.str(c,"chunk_text"),query)).reversed().thenComparing(c->Db.str(c,"id")));
        if(!goal.isBlank()) ranked.removeIf(c->score(Db.str(c,"chunk_text"),query)<=0);
        ranked=new ArrayList<>(ranked.stream().limit(50).toList());
        var seeds=ranked.stream().limit(12).map(c->Db.str(c,"memory_id")).distinct().toList();
        var paths=graph.paths(a.company(),ids,seeds); var graphOrder=new LinkedHashSet<String>(); paths.forEach(p->{ graphOrder.add(Db.str(p,"from")); graphOrder.add(Db.str(p,"to")); });
        for(String id:graphOrder) if(chunks.stream().noneMatch(c->id.equals(c.get("memory_id")))) {
            var m=items.get(id); if(m!=null) chunks.add(Map.of("id","direct:"+m.get("id")+":"+m.get("version"),"memory_id",m.get("id"),"memory_version",m.get("version"),"source_type",m.get("source_type"),"source_id",m.get("source_id"),"source_version",m.get("source_version"),"locator",m.get("locator"),"chunk_text",m.get("content")));
        }
        Map<String,Double> ranks=new HashMap<>(); int rank=0; for(var c:ranked) ranks.merge(Db.str(c,"memory_id"),1.0/(60+(++rank)),Double::sum);
        var fulltext=chunks.stream().filter(c->c.get("fulltext_rank") instanceof Number n&&n.doubleValue()>0).sorted(Comparator.<Map<String,Object>>comparingDouble(c->((Number)c.get("fulltext_rank")).doubleValue()).reversed()).limit(50).toList();
        rank=0; for(var c:fulltext) ranks.merge(Db.str(c,"memory_id"),1.0/(60+(++rank)),Double::sum);
        rank=0; for(String id:graphOrder) ranks.merge(id,1.0/(60+(++rank)),Double::sum);
        chunks.sort(Comparator.<Map<String,Object>>comparingDouble(c->ranks.getOrDefault(Db.str(c,"memory_id"),0.0)).reversed().thenComparing(Comparator.<Map<String,Object>>comparingDouble(c->score(Db.str(c,"chunk_text"),query)).reversed()).thenComparing(c->Db.str(c,"id")));
        var chosen=new ArrayList<Map<String,Object>>(); var events=new HashSet<String>(); int chars=0;
        for(var c:chunks) {
            String mid=Db.str(c,"memory_id"); if(!ranks.containsKey(mid)) continue;
            String event=c.get("source_type")+":"+c.get("source_id")+":"+c.get("source_version");
            if(events.contains(event)) continue; String body=Db.str(c,"chunk_text"); if(chars+body.length()>6000) continue;
            chosen.add(c); events.add(event); chars+=body.length(); if(chosen.size()==12) break;
        }
        var selected=chosen.stream().map(c->items.get(Db.str(c,"memory_id"))).filter(Objects::nonNull).distinct().toList();
        Set<String> selectedIds=new HashSet<>(); selected.forEach(m->selectedIds.add(Db.str(m,"id")));
        paths=paths.stream().filter(p->selectedIds.contains(Db.str(p,"from"))&&selectedIds.contains(Db.str(p,"to"))).toList();
        String degraded=(graph.available()?"":"图谱暂不可用，使用文本证据")+(pending?"；部分索引更新中，使用当前有效记忆":"");
        return new Evidence(selected,chosen,paths,revision(a,scope,allowed),Db.hash(activeVersion+":"+chosen.stream().map(c->Db.str(c,"id")).sorted().toList()),activeVersion,degraded);
    }
    boolean validSnapshot(Actor actor,Evidence evidence) {
        Actor a=memory.fresh(actor);
        String active=Db.str(db.one("SELECT active_version FROM knowledge_index_state WHERE company_id=? FOR SHARE",a.company()),"active_version");
        if(!active.equals(evidence.chunkerVersion())) return false;
        for(var c:evidence.chunks()) {
            if(Db.str(c,"id").startsWith("direct:")) continue;
            if(db.count("SELECT count(*) FROM knowledge_chunks WHERE company_id=? AND id=? AND memory_id=? AND memory_version=? AND source_version=? AND chunker_version=? AND index_state='READY'",a.company(),c.get("id"),c.get("memory_id"),c.get("memory_version"),c.get("source_version"),active)!=1) return false;
        }
        return true;
    }
    static double score(String text,List<String> query) { var words=new HashSet<>(tokens(text)); return query.stream().filter(words::contains).count(); }
}
