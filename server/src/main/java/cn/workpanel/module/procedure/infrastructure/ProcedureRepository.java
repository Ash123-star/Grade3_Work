package cn.workpanel.module.procedure.infrastructure;

import cn.workpanel.*;
import cn.workpanel.module.procedure.domain.ProcedureSearch;
import org.springframework.stereotype.Repository;
import java.util.*;

@Repository
public class ProcedureRepository {
    private final Db db;
    public ProcedureRepository(Db db) { this.db=db; }
    public Map<String,Object> document(Actor a,String id,boolean lock) { return db.one("SELECT * FROM procedure_documents WHERE company_id=? AND id=?"+(lock?" FOR UPDATE":""),a.company(),id); }
    public void lockSources(Actor a,List<Map<String,Object>> sources){if(sources.isEmpty())return;db.one("SELECT true AS locked FROM pg_advisory_xact_lock_shared(hashtextextended(?,0))","procedure-publication:"+a.company());for(String id:sources.stream().map(s->Db.str(s,"id")).distinct().sorted().toList())db.one("SELECT id FROM procedure_documents WHERE company_id=? AND id=? FOR SHARE",a.company(),id);}
    public void lockPublication(Actor a){db.one("SELECT true AS locked FROM pg_advisory_xact_lock(hashtextextended(?,0))","procedure-publication:"+a.company());}
    public Map<String,Object> user(Actor a){return db.one("SELECT name FROM users WHERE company_id=? AND id=?",a.company(),a.id());}
    public Map<String,Object> department(Actor a){return db.one("SELECT name FROM departments WHERE company_id=? AND id=?",a.company(),a.department());}
    public Map<String,Object> revision(Actor a,String id,int version) { return db.one("SELECT * FROM procedure_versions WHERE company_id=? AND document_id=? AND version=?",a.company(),id,version); }
    public List<Map<String,Object>> published(Actor a,String search) {
        return published(a,search,0,50);
    }
    public List<Map<String,Object>> published(Actor a,String query,int cursor,int limit){
        String normalized=ProcedureSearch.normalize(query);var terms=ProcedureSearch.terms(query);
        return db.rows("WITH visible AS MATERIALIZED (SELECT d.*,v.body,v.effective_from,v.effective_to FROM procedure_documents d JOIN procedure_versions v ON v.company_id=d.company_id AND v.document_id=d.id AND v.version=d.active_version WHERE d.company_id=? AND d.state='PUBLISHED' AND v.effective_from<=now() AND (v.effective_to IS NULL OR v.effective_to>now()) AND (d.scope_kind='COMPANY' OR d.scope_kind='DEPARTMENT' AND d.scope_id=? OR d.scope_kind='TEAM' AND d.scope_id=?)), ranked AS (SELECT visible.*, CASE WHEN ?='' THEN 1 ELSE (CASE WHEN strpos(lower(title),?)>0 THEN 20 ELSE 0 END)+(CASE WHEN strpos(lower(body->>'content'),?)>0 THEN 5 ELSE 0 END)+coalesce((SELECT sum(CASE WHEN strpos(lower(title),term)>0 THEN 3 ELSE 0 END + CASE WHEN strpos(lower(body->>'content'),term)>0 THEN 1 ELSE 0 END) FROM jsonb_array_elements_text(?::jsonb) term),0) END AS relevance FROM visible) SELECT *,count(*) OVER() AS total_count FROM ranked WHERE relevance>0 ORDER BY relevance DESC,title,id LIMIT ? OFFSET ?",a.company(),a.department(),a.team(),normalized,normalized,normalized,db.write(terms),limit,cursor);
    }
    public List<Map<String,Object>> peers(Actor a,Map<String,Object> source){
        return db.rows("SELECT d.*,v.body FROM procedure_documents d JOIN procedure_versions v ON v.company_id=d.company_id AND v.document_id=d.id AND v.version=d.active_version WHERE d.company_id=? AND d.state='PUBLISHED' AND v.effective_from<=now() AND (v.effective_to IS NULL OR v.effective_to>now()) AND d.scope_kind=? AND d.scope_id IS NOT DISTINCT FROM ? AND (d.scope_kind='COMPANY' OR d.scope_kind='DEPARTMENT' AND d.scope_id=? OR d.scope_kind='TEAM' AND d.scope_id=?)",a.company(),source.get("scopeKind"),source.get("scopeId"),a.department(),a.team());
    }
    public List<Map<String,Object>> drafts(Actor a) { return db.rows("SELECT * FROM procedure_documents WHERE company_id=? ORDER BY created_at DESC LIMIT 100",a.company()); }
    public List<Map<String,Object>> drafts(Actor a,String query,int cursor,int limit){return db.rows("SELECT d.*,coalesce(v.body->>'title',d.title) AS title,r.id AS pending_review_id,r.status AS review_status,count(*) OVER() AS total_count FROM procedure_documents d JOIN procedure_versions v ON v.company_id=d.company_id AND v.document_id=d.id AND v.version=d.version LEFT JOIN LATERAL(SELECT id,status FROM review_requests WHERE company_id=d.company_id AND target_id=d.id AND kind='PROCEDURE' AND expected_version=d.version AND status='PENDING' ORDER BY created_at DESC,id LIMIT 1) r ON true WHERE d.company_id=? AND coalesce(v.body->>'title',d.title) ILIKE ? ORDER BY d.created_at DESC,d.id LIMIT ? OFFSET ?",a.company(),"%"+query+"%",limit,cursor);}
    public Map<String,Object> visible(Actor a,String id) {
        return db.one("SELECT d.*,v.body FROM procedure_documents d JOIN procedure_versions v ON v.company_id=d.company_id AND v.document_id=d.id AND v.version=d.active_version WHERE d.company_id=? AND d.id=? AND d.state='PUBLISHED' AND v.effective_from<=now() AND (v.effective_to IS NULL OR v.effective_to>now()) AND (d.scope_kind='COMPANY' OR d.scope_kind='DEPARTMENT' AND d.scope_id=? OR d.scope_kind='TEAM' AND d.scope_id=?)",a.company(),id,a.department(),a.team());
    }
    public void validateScope(Actor a,Map<String,Object> b) {
        String scope=Db.str(b,"scopeKind");
        if(!scope.equals("COMPANY")) db.one("SELECT id FROM "+(scope.equals("TEAM")?"teams":"departments")+" WHERE company_id=? AND id=?",a.company(),b.get("scopeId"));
    }
    public void create(Actor a,String id,Map<String,Object> body) {
        db.update("INSERT INTO procedure_documents(id,company_id,owner_id,type,title,scope_kind,scope_id) VALUES (?,?,?,?,?,?,?)",id,a.company(),a.id(),body.get("type"),body.get("title"),body.get("scopeKind"),body.get("scopeId"));
        version(a,id,1,body);
    }
    public void version(Actor a,String id,int v,Map<String,Object> body) {
        db.update("INSERT INTO procedure_versions(company_id,document_id,version,body,effective_from,effective_to) VALUES (?,?,?,?::jsonb,?::timestamptz,?::timestamptz)",a.company(),id,v,db.write(body),body.get("effectiveFrom"),body.get("effectiveTo"));
    }
    public void advance(Actor a,String id,int expected,int next) { Db.conflict(db.update("UPDATE procedure_documents SET version=? WHERE company_id=? AND id=? AND version=?",next,a.company(),id,expected)); }
    public void publish(Actor a,String id,int expected,Map<String,Object> body,boolean withdraw) {
        version(a,id,expected+1,body);
        Db.conflict(db.update("UPDATE procedure_documents SET active_version=?,state=?,title=?,type=?,scope_kind=?,scope_id=?,version=version+1 WHERE company_id=? AND id=? AND version=?",expected,withdraw?"WITHDRAWN":"PUBLISHED",body.get("title"),body.get("type"),body.get("scopeKind"),body.get("scopeId"),a.company(),id,expected));
        if(!withdraw)for(var chunk:ProcedureSearch.chunks(Db.str(body,"content")))db.update("INSERT INTO procedure_chunks(company_id,document_id,version,locator,content) VALUES (?,?,?,?,?) ON CONFLICT DO NOTHING",a.company(),id,expected,chunk.get("locator"),chunk.get("content"));
    }
    public void audit(Actor a,String type,String id,Object body) { db.audit(a,type,id,Map.of(),body,"维护公司资料"); }
    public Map<String,Object> json(Object body) { return db.read(body); }
    public void bind(Actor a,String id,String attachment) {
        var f=db.one("SELECT owner_id FROM attachments WHERE company_id=? AND id=?",a.company(),attachment);
        if(!a.id().equals(f.get("owner_id"))) throw ApiError.forbidden();
        db.update("INSERT INTO attachment_bindings(company_id,attachment_id,resource_type,resource_id) VALUES (?,?,'PROCEDURE',?) ON CONFLICT DO NOTHING",a.company(),attachment,id);
    }
}
