package cn.workpanel.module.organization.domain;

import cn.workpanel.*;
import cn.workpanel.module.auth.domain.AuthPolicy;
import java.util.Map;

/** 管理员录入字段白名单；角色和公司只取服务端身份。 */
public record EmployeeProvisioning(String account, String password, String phone, String name, String department, String team, String manager, String gender, String idCardNumber, String businessPosition) {
    public static EmployeeProvisioning parse(Map<String,Object> body) {
        Db.fields(body,"account","password","phone","name","departmentId","teamId","managerId","gender","idCardNumber","businessPosition");
        String account=Db.required(body,"account"),phone=Db.required(body,"phone"),name=Db.required(body,"name");
        EmployeeInput.account(account);EmployeeInput.phone(phone);name=EmployeeInput.name(body.get("name"));
        String gender=EmployeeIdentity.gender(body.get("gender")),card=EmployeeIdentity.idCard(body.get("idCardNumber"));
        EmployeeInput.genderMatches(gender,card);
        return new EmployeeProvisioning(account,AuthPolicy.password(body,"password"),phone,name,Db.required(body,"departmentId"),Db.required(body,"teamId"),Db.required(body,"managerId"),gender,card,EmployeeInput.position(body.get("businessPosition")));
    }
}
