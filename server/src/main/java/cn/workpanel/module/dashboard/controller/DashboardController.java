package cn.workpanel.module.dashboard.controller;

import cn.workpanel.*;
import cn.workpanel.module.review.application.ReviewApplicationService;
import cn.workpanel.module.auth.controller.AuthController;

import jakarta.servlet.http.HttpServletRequest;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;
import java.util.*;

@RestController
@RequestMapping("/api")
/** 导图、个人资料和私人备注接口；所有聚合查询复用当前用户数据范围。 */
public class DashboardController {
    final Db db; final Business business; final ReviewApplicationService reviews;
    public DashboardController(Db db,Business business,ReviewApplicationService reviews) { this.db=db; this.business=business; this.reviews=reviews; }
    /** 获取导图首页四象限及当前用户派发资格。需要登录；公司重点只读。 */
    @GetMapping("/dashboard") public Map<String,Object> home(HttpServletRequest r) {
        Actor a=Actor.current(r); var t=Business.taskScope(a);
        return Map.of("companyItems",db.rows("SELECT id,title,body,version,position FROM dashboard_items WHERE company_id=? AND kind='COMPANY' AND NOT archived ORDER BY pinned DESC,position,id LIMIT 10",a.company()),"companyTasks",db.rows("SELECT t.* FROM tasks t WHERE "+t.sql()+" ORDER BY deadline,id LIMIT 10",t.parameters()).stream().map(x->Business.taskDto(db,x,false)).toList(),"personalItems",db.rows("SELECT * FROM dashboard_items WHERE company_id=? AND owner_id=? AND kind='PERSONAL' AND NOT archived ORDER BY pinned DESC,position,id LIMIT 10",a.company(),a.id()),"logs",db.rows("SELECT * FROM daily_logs WHERE company_id=? AND owner_id=? ORDER BY business_date DESC LIMIT 3",a.company(),a.id()).stream().map(x->Business.logDto(db,x)).toList(),"canDispatch",a.manager()&&a.dispatch());
    }
    /** 分页读取公司重点。需要登录；只返回授权范围内已发布内容。 */
    @GetMapping("/dashboard/company") public Map<String,Object> company(HttpServletRequest r,@RequestParam(defaultValue="0") int cursor,@RequestParam(defaultValue="30") int limit) {
        Actor a=Actor.current(r); Business.page(cursor,limit); return Map.of("items",db.rows("SELECT id,title,body,version,pinned,position FROM dashboard_items WHERE company_id=? AND kind='COMPANY' AND NOT archived ORDER BY pinned DESC,position,id LIMIT ? OFFSET ?",a.company(),limit,cursor),"total",db.count("SELECT count(*) FROM dashboard_items WHERE company_id=? AND kind='COMPANY' AND NOT archived",a.company()),"nextCursor",String.valueOf(cursor+limit));
    }
    /** 提交公司重点候选版本。需要全局管理权限；需 reason/version，审核通过后生效。 */
    @PostMapping("/dashboard/company/revisions") @Transactional
    public Map<String,Object> companyRevision(HttpServletRequest r,@RequestBody Map<String,Object> b) {
        Actor a=Actor.current(r); if(!a.global()) throw ApiError.forbidden(); Db.fields(b,"id","version","reason","title","text","pinned","archived","position"); String id=Db.str(b,"id"); int version=Db.version(b); Object before=Map.of();
        if(id.isBlank()) { if(version!=0) throw ApiError.conflict(); id=Db.id(); } else before=db.one("SELECT * FROM dashboard_items WHERE id=? AND company_id=? AND kind='COMPANY'",id,a.company());
        var candidate=new LinkedHashMap<String,Object>(); for(String k:List.of("title","text","pinned","archived","position")) if(b.containsKey(k)) candidate.put(k,b.get(k)); Db.required(candidate,"title"); validate(candidate);
        return reviews.create(a,"COMPANY_ITEM",id,version,before,candidate,Db.required(b,"reason"));
    }
    /** 分页读取个人重点。本人可读本人内容；上级只读授权范围内已发布重点。 */
    @GetMapping("/dashboard/personal") public Map<String,Object> personal(HttpServletRequest r,@RequestParam(required=false) String ownerId,@RequestParam(defaultValue="0") int cursor,@RequestParam(defaultValue="30") int limit) {
        Actor a=Actor.current(r); Business.page(cursor,limit); String owner=ownerId==null?a.id():ownerId; if(!a.canSeeUser(db.one("SELECT * FROM users WHERE id=? AND company_id=?",owner,a.company()))) throw ApiError.forbidden();
        return Map.of("items",db.rows("SELECT * FROM dashboard_items WHERE company_id=? AND owner_id=? AND kind='PERSONAL' AND NOT archived ORDER BY pinned DESC,position,id LIMIT ? OFFSET ?",a.company(),owner,limit,cursor),"total",db.count("SELECT count(*) FROM dashboard_items WHERE company_id=? AND owner_id=? AND kind='PERSONAL' AND NOT archived",a.company(),owner),"nextCursor",String.valueOf(cursor+limit));
    }
    /** 新增、修改或归档个人重点。请求携带 action、version；私人内容不进入上级和 AI 范围。 */
    @PostMapping("/dashboard/personal") @Transactional
    public Map<String,Object> save(HttpServletRequest r,@RequestBody Map<String,Object> b) {
        Db.fields(b,"id","version","title","text","pinned","archived","position"); Actor a=Actor.current(r); db.one("SELECT id FROM users WHERE id=? FOR UPDATE",a.id()); validate(b); String id=Db.str(b,"id"); int v=Db.version(b); boolean pinned=Boolean.TRUE.equals(b.get("pinned")),archived=Boolean.TRUE.equals(b.get("archived"));
        if(pinned&&!archived&&db.count("SELECT count(*) FROM dashboard_items WHERE owner_id=? AND kind='PERSONAL' AND pinned AND NOT archived AND id<>?",a.id(),id)>=10) throw ApiError.bad("PIN_LIMIT","最多置顶十项");
        var content=new LinkedHashMap<>(b); content.remove("id"); content.remove("version");
        if(id.isBlank()) { if(v!=0) throw ApiError.conflict(); id=Db.id(); db.update("INSERT INTO dashboard_items(id,company_id,owner_id,kind,title,body,pinned,archived,position) VALUES (?,?,?,'PERSONAL',?,?::jsonb,?,?,?)",id,a.company(),a.id(),Db.required(b,"title"),db.write(content),pinned,archived,b.getOrDefault("position",0)); }
        else { db.one("SELECT id FROM dashboard_items WHERE id=? AND company_id=? AND owner_id=? AND kind='PERSONAL'",id,a.company(),a.id()); Db.conflict(db.update("UPDATE dashboard_items SET title=?,body=?::jsonb,pinned=?,archived=?,position=?,version=version+1 WHERE id=? AND version=?",Db.required(b,"title"),db.write(content),pinned,archived,b.getOrDefault("position",0),id,v)); }
        return db.one("SELECT * FROM dashboard_items WHERE id=?",id);
    }
    static void validate(Map<String,Object> b) { for(String k:List.of("pinned","archived")) if(b.containsKey(k)&&!(b.get(k) instanceof Boolean)) throw ApiError.bad("INVALID_BOOLEAN",k+" 必须是布尔值"); if(b.containsKey("position")&&(!(b.get("position") instanceof Number n)||n.intValue()<0||n.intValue()>10000)) throw ApiError.bad("INVALID_POSITION","排序位置无效"); }
    /** 获取范围内用户公开资料。私人备注不返回；越权返回 403。 */
    @GetMapping("/profiles/{id}") public Map<String,Object> profile(HttpServletRequest r,@PathVariable String id) { Actor a=Actor.current(r); var u=db.one("SELECT * FROM users WHERE id=? AND company_id=?",id,a.company()); if(!a.canSeeUser(u)) throw ApiError.forbidden(); var result=new LinkedHashMap<>(AuthController.publicUser(u)); result.put("profile",db.read(u.get("profile"))); result.put("viewingSelf",a.id().equals(id)); return result; }
    /** 修改本人头像和介绍。需要 version；头像必须由本人上传；并发冲突返回 409。 */
    @PutMapping("/profiles/me") @Transactional public Map<String,Object> profile(HttpServletRequest r,@RequestBody Map<String,Object> b) { Db.fields(b,"avatarAttachmentId","introduction","version"); Actor a=Actor.current(r); if(!Db.str(b,"avatarAttachmentId").isBlank()) db.one("SELECT id FROM attachments WHERE id=? AND owner_id=? AND company_id=?",b.get("avatarAttachmentId"),a.id(),a.company()); var c=new LinkedHashMap<>(b); c.remove("version"); Db.conflict(db.update("UPDATE users SET profile=?::jsonb,version=version+1 WHERE id=? AND version=?",db.write(c),a.id(),Db.version(b))); return profile(r,a.id()); }
    /** 获取本人私人备注。仅本人可见；不接受 ownerId 代查。 */
    @GetMapping("/private-notes") public List<Map<String,Object>> notes(HttpServletRequest r) { Actor a=Actor.current(r); return db.rows("SELECT * FROM private_notes WHERE company_id=? AND owner_id=?",a.company(),a.id()); }
    /** 保存本人私人备注。请求含 resource、objectId、text、version；备注不进入导出和 AI 输入。 */
    @PutMapping("/private-notes") @Transactional public Map<String,Object> note(HttpServletRequest r,@RequestBody Map<String,Object> b) {
        Db.fields(b,"resource","objectId","text","version"); Actor a=Actor.current(r); String resource=Db.required(b,"resource"),object=Db.required(b,"objectId");
        if(resource.equals("tasks")) business.task(a,object,false); else if(resource.equals("dashboard/company")) db.one("SELECT id FROM dashboard_items WHERE id=? AND company_id=? AND kind='COMPANY' AND NOT archived",object,a.company()); else throw ApiError.bad("INVALID_RESOURCE","备注仅支持公司重点和任务");
        String text=Db.str(b,"text"); if(text.length()>20000) throw ApiError.bad("NOTE_TOO_LONG","备注过长"); db.one("SELECT pg_advisory_xact_lock(hashtextextended(?,0))",a.id()+":"+resource+":"+object);
        var old=db.rows("SELECT * FROM private_notes WHERE owner_id=? AND resource=? AND object_id=?",a.id(),resource,object); String id;
        if(old.isEmpty()) { if(Db.version(b)!=0) throw ApiError.conflict(); id=Db.id(); db.update("INSERT INTO private_notes(id,company_id,owner_id,resource,object_id,text) VALUES (?,?,?,?,?,?)",id,a.company(),a.id(),resource,object,text); }
        else { id=Db.str(old.getFirst(),"id"); Db.conflict(db.update("UPDATE private_notes SET text=?,version=version+1 WHERE id=? AND version=?",text,id,Db.version(b))); }
        return db.one("SELECT * FROM private_notes WHERE id=?",id);
    }
}
