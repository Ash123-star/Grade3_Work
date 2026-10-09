package cn.workpanel;

import jakarta.servlet.http.HttpServletRequest;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;
import java.util.*;

@Service
public class Reviews {
    final Db db;
    Reviews(Db db) { this.db=db; }
    @Transactional
    public Map<String,Object> create(Actor a,String kind,String target,int version,Object before,Map<String,Object> candidate,String reason) {
        if(reason.isBlank()) throw ApiError.bad("REASON_REQUIRED","关键变更需填写理由");
        String id=Db.id(); db.update("INSERT INTO review_requests(id,company_id,applicant_id,kind,target_id,expected_version,before_value,candidate,reason) VALUES (?,?,?,?,?,?,?::jsonb,?::jsonb,?)",id,a.company(),a.id(),kind,target,version,db.write(before),db.write(candidate),reason);
        route(a,id,kind); db.audit(a,"REVIEW_REQUESTED",id,before,candidate,reason);
        return db.one("SELECT * FROM review_requests WHERE id=?",id);
    }
    void route(Actor a,String id,String kind) {
        var reviewers=new LinkedHashSet<String>();
        var policy=db.read(db.one("SELECT review_policy FROM companies WHERE id=?",a.company()).get("review_policy"));
        if(!Set.of("MEMBERSHIP","REVIEWER").contains(kind)) {
            if(!a.team().isBlank()&&(!kind.equals("TASK")||Boolean.TRUE.equals(policy.get("taskTeamReview")))) first(reviewers,a,"role='LEADER' AND team_id=?",a.team());
            if(!a.department().isBlank()&&(!kind.equals("TASK")||Boolean.TRUE.equals(policy.get("taskDepartmentReview")))) first(reviewers,a,"role='DIRECTOR' AND department_id=?",a.department());
        }
        var company=db.rows("SELECT id FROM users WHERE company_id=? AND status='ACTIVE' AND company_reviewer=true AND id<>?"+(Set.of("MEMBERSHIP","REVIEWER").contains(kind)?" AND role='ADMIN'":"")+" ORDER BY id LIMIT 1",a.company(),a.id());
        if(!company.isEmpty()) reviewers.add(Db.str(company.getFirst(),"id"));
        else { // 没有最终公司复核人不能让下级审核导致生效。
            reviewers.clear();
        }
        int pos=0; for(String reviewer:reviewers) { db.update("INSERT INTO review_steps(request_id,reviewer_id,position,company_id) VALUES (?,?,?,?)",id,reviewer,++pos,a.company()); db.notify(a,reviewer,"REVIEW_PENDING",id,"review:"+id+":"+reviewer); }
    }
    void first(Set<String> ids,Actor a,String clause,String value) {
        var rows=db.rows("SELECT id FROM users WHERE company_id=? AND status='ACTIVE' AND id<>? AND "+clause+" ORDER BY id LIMIT 1",a.company(),a.id(),value); if(!rows.isEmpty()) ids.add(Db.str(rows.getFirst(),"id"));
    }
    Map<String,Object> get(Actor a,String id) {
        var row=db.one("SELECT * FROM review_requests WHERE id=? AND company_id=?",id,a.company());
        if(!a.id().equals(row.get("applicant_id"))&&db.count("SELECT count(*) FROM review_steps WHERE request_id=? AND reviewer_id=?",id,a.id())==0) throw ApiError.forbidden();
        var result=new LinkedHashMap<>(row); result.put("candidate",db.read(row.get("candidate"))); result.put("before_value",db.read(row.get("before_value"))); result.put("steps",db.rows("SELECT * FROM review_steps WHERE request_id=? ORDER BY position",id)); return result;
    }
    @Transactional
    public Map<String,Object> decide(Actor a,String id,boolean approve,String reason) {
        var row=db.one("SELECT * FROM review_requests WHERE id=? AND company_id=? FOR UPDATE",id,a.company());
        if(a.id().equals(row.get("applicant_id"))) throw new ApiError(403,"SELF_REVIEW","禁止审核自己的申请");
        if(!row.get("status").equals("PENDING")) throw ApiError.conflict();
        var steps=db.rows("SELECT * FROM review_steps WHERE request_id=? AND state='PENDING' ORDER BY position LIMIT 1",id);
        if(steps.isEmpty()||!steps.getFirst().get("reviewer_id").equals(a.id())) throw ApiError.forbidden();
        String kind=Db.str(row,"kind");
        // 每一步检查当前职责，调岗/撤销权限后不沿用旧审批资格。
        Actor applicant=Actor.from(db.one("SELECT * FROM users WHERE id=?",row.get("applicant_id")));
        int position=((Number)steps.getFirst().get("position")).intValue();
        long last=db.count("SELECT max(position) FROM review_steps WHERE request_id=?",id);
        if(position==last ? !a.reviewer() : !(a.role().equals("LEADER")&&!a.team().isEmpty()&&a.team().equals(applicant.team())||a.role().equals("DIRECTOR")&&!a.department().isEmpty()&&a.department().equals(applicant.department()))) throw ApiError.forbidden();
        if(Set.of("MEMBERSHIP","REVIEWER").contains(kind)&&!a.admin()) throw ApiError.forbidden();
        if(!approve&&reason.isBlank()) throw ApiError.bad("REASON_REQUIRED","驳回需填写原因");
        db.update("UPDATE review_steps SET state=?,reason=?,decided_at=now() WHERE id=?",approve?"APPROVED":"REJECTED",reason,steps.getFirst().get("id"));
        if(!approve) db.update("UPDATE review_requests SET status='REJECTED' WHERE id=?",id);
        else if(position==last) { apply(a,row); db.update("UPDATE review_requests SET status='APPROVED' WHERE id=?",id); }
        db.audit(a,approve?"REVIEW_APPROVED":"REVIEW_REJECTED",id,Map.of("status","PENDING"),Map.of("position",position,"decision",approve),reason);
        db.notify(a,applicant.id(),approve?"REVIEW_APPROVED":"REVIEW_REJECTED",id,"review-result:"+id+":"+position);
        return get(a,id);
    }
    @Transactional
    public Map<String,Object> reroute(Actor a,String id) {
        var row=db.one("SELECT * FROM review_requests WHERE id=? AND company_id=? FOR UPDATE",id,a.company());
        if(!a.id().equals(row.get("applicant_id"))||!row.get("status").equals("PENDING")) throw ApiError.forbidden();
        if(db.count("SELECT count(*) FROM review_steps WHERE request_id=? AND state<>'PENDING'",id)>0) throw ApiError.conflict();
        db.update("DELETE FROM review_steps WHERE request_id=?",id); route(a,id,Db.str(row,"kind")); return get(a,id);
    }
    void apply(Actor approver,Map<String,Object> row) {
        String kind=Db.str(row,"kind"),target=Db.str(row,"target_id"); int v=((Number)row.get("expected_version")).intValue(); var c=db.read(row.get("candidate"));
        Actor applicant=Actor.from(db.one("SELECT * FROM users WHERE id=?",row.get("applicant_id")));
        if(!applicant.status().equals("ACTIVE")&&!kind.equals("MEMBERSHIP")) throw ApiError.forbidden();
        switch(kind) {
            case "POLICY" -> {
                applicant.requireAdmin(); Db.conflict(db.update("UPDATE companies SET review_policy=?::jsonb,version=version+1 WHERE id=? AND version=?",db.write(c),approver.company(),v));
            }
            case "MEMBERSHIP" -> {
                db.one("SELECT id FROM departments WHERE id=? AND company_id=?",Db.required(c,"departmentId"),approver.company());
                Db.conflict(db.update("UPDATE users SET status='ACTIVE',department_id=?,version=version+1 WHERE id=? AND company_id=? AND status='PENDING' AND version=?",c.get("departmentId"),target,approver.company(),v));
            }
            case "REVIEWER" -> Db.conflict(db.update("UPDATE users SET company_reviewer=true,version=version+1 WHERE id=? AND company_id=? AND status='ACTIVE' AND version=?",target,approver.company(),v));
            case "USER" -> {
                applicant.requireAdmin(); Organization.validateUser(db,approver.company(),target,c);
                Db.conflict(db.update("UPDATE users SET name=?,department_id=?,team_id=?,role=?,status=?,dispatch_enabled=?,company_reviewer=?,version=version+1 WHERE id=? AND company_id=? AND version=?",Db.required(c,"name"),nullable(c,"departmentId"),nullable(c,"teamId"),Db.required(c,"role"),Db.required(c,"status"),c.get("dispatchEnabled"),c.get("companyReviewer"),target,approver.company(),v));
                db.update("UPDATE user_roles SET role_id=? WHERE user_id=?",c.get("role"),target);
                db.update("DELETE FROM reporting_relations WHERE employee_id=?",target); if(!Db.str(c,"managerId").isBlank()) db.update("INSERT INTO reporting_relations VALUES (?,?,?)",target,c.get("managerId"),approver.company());
                if(c.get("status").equals("DISABLED")) db.update("DELETE FROM sessions WHERE user_id=?",target);
            }
            case "DEPARTMENT","TEAM" -> {
                applicant.requireAdmin(); String table=kind.equals("TEAM")?"teams":"departments";
                if(kind.equals("TEAM")) db.one("SELECT id FROM departments WHERE id=? AND company_id=?",Db.required(c,"departmentId"),approver.company());
                if(v==0) {
                    if(kind.equals("TEAM")) db.update("INSERT INTO teams(id,company_id,department_id,name) VALUES (?,?,?,?)",target,approver.company(),c.get("departmentId"),c.get("name"));
                    else db.update("INSERT INTO departments(id,company_id,name) VALUES (?,?,?)",target,approver.company(),c.get("name"));
                } else {
                    // 已有人团队不能直接改部门，避免人员归属不同步。
                    if(kind.equals("TEAM")) { var team=db.one("SELECT * FROM teams WHERE id=? AND company_id=?",target,approver.company()); if(!team.get("department_id").equals(c.get("departmentId"))&&db.count("SELECT count(*) FROM users WHERE team_id=?",target)>0) throw ApiError.bad("TEAM_HAS_MEMBERS","先通过人员调岗移出团队"); }
                    Db.conflict(db.update("UPDATE "+table+" SET name=?,version=version+1 WHERE id=? AND company_id=? AND version=?",c.get("name"),target,approver.company(),v));
                    if(kind.equals("TEAM")) db.update("UPDATE teams SET department_id=? WHERE id=?",c.get("departmentId"),target);
                }
            }
            case "COMPANY_ITEM" -> {
                if(!applicant.global()) throw ApiError.forbidden(); db.one("SELECT id FROM companies WHERE id=? FOR UPDATE",approver.company());
                boolean pinned=Boolean.TRUE.equals(c.get("pinned")),archived=Boolean.TRUE.equals(c.get("archived"));
                if(pinned&&!archived&&db.count("SELECT count(*) FROM dashboard_items WHERE company_id=? AND kind='COMPANY' AND pinned AND NOT archived AND id<>?",approver.company(),target)>=10) throw ApiError.bad("PIN_LIMIT","最多置顶十项");
                if(v==0) db.update("INSERT INTO dashboard_items(id,company_id,owner_id,kind,title,body,pinned,archived,position) VALUES (?,?,?,'COMPANY',?,?::jsonb,?,?,?)",target,approver.company(),applicant.id(),c.get("title"),db.write(c),pinned,archived,c.getOrDefault("position",0));
                else Db.conflict(db.update("UPDATE dashboard_items SET title=?,body=?::jsonb,pinned=?,archived=?,position=?,version=version+1 WHERE id=? AND company_id=? AND version=?",c.get("title"),db.write(c),pinned,archived,c.getOrDefault("position",0),target,approver.company(),v));
            }
            case "LOG" -> {
                var log=db.one("SELECT * FROM daily_logs WHERE id=? AND company_id=? FOR UPDATE",target,approver.company()); if(!applicant.id().equals(log.get("owner_id"))&&!applicant.admin()) throw ApiError.forbidden();
                Business.validateLog(db,applicant,c);
                Db.conflict(db.update("UPDATE daily_logs SET body=?::jsonb,version=version+1 WHERE id=? AND submitted AND version=?",db.write(c),target,v));
                db.update("INSERT INTO log_versions(company_id,log_id,version,body) VALUES (?,?,?,?::jsonb)",approver.company(),target,v+1,db.write(c));
            }
            case "TASK" -> {
                var task=db.one("SELECT * FROM tasks WHERE id=? AND company_id=? FOR UPDATE",target,approver.company()); applicant.requireDispatch(); if(!applicant.id().equals(task.get("issuer_id"))&&!applicant.admin()) throw ApiError.forbidden(); if(Set.of("ARCHIVED","WITHDRAWN").contains(task.get("phase"))) throw ApiError.conflict();
                Business.validateTask(db,applicant,c);
                var former=db.rows("SELECT user_id FROM task_assignees WHERE task_id=?",target);
                Db.conflict(db.update("UPDATE tasks SET title=?,owner_id=?,deadline=?::timestamptz,body=?::jsonb,phase='DISPATCHED',version=version+1 WHERE id=? AND version=?",c.get("title"),c.get("ownerId"),c.get("deadline"),db.write(c),target,v));
                db.update("DELETE FROM task_assignees WHERE task_id=?",target); Business.assign(db,applicant,target,c);
                db.update("INSERT INTO task_events(company_id,task_id,actor_id,type,body) VALUES (?,?,?,'REVISED',?::jsonb)",approver.company(),target,applicant.id(),db.write(c));
                for(var recipient:former) db.notify(applicant,Db.str(recipient,"user_id"),"TASK_REVISED",target,"task-revised:"+target+":"+v+":"+recipient.get("user_id"));
            }
            default -> throw ApiError.bad("REVIEW_KIND","不支持的复核类型");
        }
        db.audit(approver,"REVISION_APPLIED",target,db.read(row.get("before_value")),c,Db.str(row,"reason"));
    }
    static Object nullable(Map<String,Object> c,String key) { String s=Db.str(c,key); return s.isBlank()?null:s; }
}

@RestController
@RequestMapping("/api/reviews")
class ReviewApi {
    final Reviews service; final Db db;
    ReviewApi(Reviews service,Db db) { this.service=service; this.db=db; }
    @GetMapping public Map<String,Object> list(HttpServletRequest r,@RequestParam(defaultValue="0") int cursor,@RequestParam(defaultValue="30") int limit) {
        Actor a=Actor.current(r); Business.page(cursor,limit);
        String where="company_id=? AND (applicant_id=? OR id IN (SELECT request_id FROM review_steps WHERE reviewer_id=?))";
        return Map.of("items",db.rows("SELECT id,kind,target_id,applicant_id,status,reason,created_at FROM review_requests WHERE "+where+" ORDER BY created_at DESC,id LIMIT ? OFFSET ?",a.company(),a.id(),a.id(),limit,cursor),"total",db.count("SELECT count(*) FROM review_requests WHERE "+where,a.company(),a.id(),a.id()),"nextCursor",String.valueOf(cursor+limit));
    }
    @GetMapping("/{id}") public Map<String,Object> get(HttpServletRequest r,@PathVariable String id) { return service.get(Actor.current(r),id); }
    @PostMapping("/{id}/decision") public Map<String,Object> decide(HttpServletRequest r,@PathVariable String id,@RequestBody Map<String,Object> b) { Db.fields(b,"approve","reason"); if(!(b.get("approve") instanceof Boolean)) throw ApiError.bad("INVALID_DECISION","approve 必须为布尔值"); return service.decide(Actor.current(r),id,(boolean)b.get("approve"),Db.str(b,"reason")); }
    @PostMapping("/{id}/reroute") public Map<String,Object> reroute(HttpServletRequest r,@PathVariable String id) { return service.reroute(Actor.current(r),id); }
}
