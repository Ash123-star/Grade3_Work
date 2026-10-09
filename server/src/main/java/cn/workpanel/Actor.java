package cn.workpanel;

import jakarta.servlet.http.HttpServletRequest;
import java.util.Map;

public record Actor(String id,String company,String role,String department,String team,boolean dispatch,boolean reviewer,boolean mustChange,String status) {
    public static Actor from(Map<String,Object> u) { return new Actor(Db.str(u,"id"),Db.str(u,"company_id"),Db.str(u,"role"),Db.str(u,"department_id"),Db.str(u,"team_id"),(boolean)u.get("dispatch_enabled"),(boolean)u.get("company_reviewer"),(boolean)u.get("must_change_password"),Db.str(u,"status")); }
    public static Actor current(HttpServletRequest r) { Actor a=(Actor)r.getAttribute("actor"); if(a==null) throw new ApiError(401,"UNAUTHENTICATED","请登录"); return a; }
    public boolean admin() { return role.equals("ADMIN"); }
    public boolean global() { return admin()||role.equals("FOUNDER"); }
    public boolean manager() { return !role.equals("EMPLOYEE"); }
    public void requireAdmin() { if(!admin()) throw ApiError.forbidden(); }
    public void requireDispatch() { if(!manager()||!dispatch) throw ApiError.forbidden(); }
    public boolean canSeeUser(Map<String,Object> u) {
        if(!company.equals(Db.str(u,"company_id"))) return false;
        return id.equals(Db.str(u,"id"))||global()||role.equals("DIRECTOR")&&!department.isEmpty()&&department.equals(Db.str(u,"department_id"))||role.equals("LEADER")&&!team.isEmpty()&&team.equals(Db.str(u,"team_id"));
    }
    public String userScope(String alias) {
        // 值均来自数据库，但仍仅使用参数查询：本表达式没有用户输入。
        return switch(role) {
            case "ADMIN","FOUNDER" -> "true";
            case "DIRECTOR" -> alias+".id = ? OR "+alias+".department_id = ?";
            case "LEADER" -> alias+".id = ? OR "+alias+".team_id = ?";
            default -> alias+".id = ?";
        };
    }
    public Object[] scopeArgs() { return switch(role) { case "ADMIN","FOUNDER" -> new Object[0]; case "DIRECTOR" -> new Object[]{id,department.isEmpty()?null:department}; case "LEADER" -> new Object[]{id,team.isEmpty()?null:team}; default -> new Object[]{id}; }; }
}
