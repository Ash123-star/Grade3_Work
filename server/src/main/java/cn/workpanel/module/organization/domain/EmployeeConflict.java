package cn.workpanel.module.organization.domain;

import cn.workpanel.ApiError;
import java.util.*;

/** 只返回冲突字段，不携带已存在员工的身份或原号码。 */
public final class EmployeeConflict extends ApiError {
    public final Map<String,String> fieldErrors;
    public EmployeeConflict(Map<String,String> errors) {
        super(409,errors.size()==1?switch(errors.keySet().iterator().next()) {
            case "account"->"ACCOUNT_EXISTS"; case "phone"->"PHONE_EXISTS"; default->"ID_CARD_EXISTS";
        }:"EMPLOYEE_FIELDS_EXIST",String.join("；",errors.values()));
        fieldErrors=Collections.unmodifiableMap(new LinkedHashMap<>(errors));
    }
    public static String message(String field) {
        return switch(field) {
            case "account"->"该登录账号已被使用，请更换账号";
            case "phone"->"该手机号已被使用，请核对号码";
            default->"该身份证号已关联员工，请核对是否重复录入";
        };
    }
}
