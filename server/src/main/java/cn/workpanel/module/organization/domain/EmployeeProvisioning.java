package cn.workpanel.module.organization.domain;

import cn.workpanel.*;
import cn.workpanel.module.auth.domain.AuthPolicy;
import java.util.Map;

/** 管理员录入字段白名单；角色和公司只取服务端身份。 */
public record EmployeeProvisioning(String account, String password, String phone, String name, String department) {
    public static EmployeeProvisioning parse(Map<String,Object> body) {
        Db.fields(body,"account","password","phone","name","departmentId");
        String account=Db.required(body,"account"),phone=Db.required(body,"phone"),name=Db.required(body,"name");
        AuthPolicy.registration(account,phone);
        if(name.length()>100) throw ApiError.bad("INVALID_NAME","姓名最多100字");
        return new EmployeeProvisioning(account,AuthPolicy.password(body,"password"),phone,name,Db.required(body,"departmentId"));
    }
}
