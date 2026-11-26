package cn.workpanel.module.customer.domain;

import cn.workpanel.ApiError;
import cn.workpanel.Db;
import java.time.LocalDate;
import java.util.Map;

/** Mall membership is separate from a benefit grant; the mall ID is the external link used by E. */
public record MembershipDraft(String mallMemberId,String level,LocalDate joinedAt,LocalDate expiresAt,String status,Integer version) {
    public static MembershipDraft parse(Map<String,Object> body) {
        Db.fields(body,"mallMemberId","level","joinedAt","expiresAt","status","version");
        String mallMemberId=Db.required(body,"mallMemberId");
        if(mallMemberId.length()>200) throw ApiError.bad("INVALID_MALL_MEMBER","商城会员ID最多200字");
        String level=body.get("level")==null?"":Db.str(body,"level");
        if(level.length()>100) throw ApiError.bad("INVALID_LEVEL","会员等级最多100字");
        LocalDate joinedAt=body.get("joinedAt")==null?null:CustomerDraft.date(body.get("joinedAt"),"joinedAt");
        LocalDate expiresAt=body.get("expiresAt")==null?null:CustomerDraft.date(body.get("expiresAt"),"expiresAt");
        if(joinedAt!=null&&expiresAt!=null&&expiresAt.isBefore(joinedAt)) throw ApiError.bad("INVALID_DATE_RANGE","会员到期不能早于加入日期");
        String status=body.get("status")==null?"ACTIVE":Db.required(body,"status").toUpperCase();
        if(!status.equals("ACTIVE")&&!status.equals("EXPIRED")&&!status.equals("DISABLED")) throw ApiError.bad("INVALID_STATUS","会员状态无效");
        int version=0;
        if(body.get("version")!=null) {
            Object raw=body.get("version");
            if(!(raw instanceof Integer n)||n<0) throw ApiError.bad("INVALID_VERSION","version 必须为非负整数");
            version=(Integer)raw;
        }
        return new MembershipDraft(mallMemberId,level,joinedAt,expiresAt,status,version);
    }
}
