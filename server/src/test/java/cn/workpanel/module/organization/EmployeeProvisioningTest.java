package cn.workpanel.module.organization;

import cn.workpanel.ApiError;
import cn.workpanel.module.organization.domain.EmployeeProvisioning;
import org.junit.jupiter.api.Test;
import java.util.*;
import static org.junit.jupiter.api.Assertions.*;

class EmployeeProvisioningTest {
    Map<String,Object> valid() { var data=new HashMap<String,Object>(Map.of("account","new.employee","password","Initial-password-2026","phone","13912345678","name","新同事","departmentId","product","teamId","product-a","managerId","boss"));data.put("gender","女");data.put("idCardNumber","11010519491231002X");return data; }
    @Test void acceptsValidEmployee() { var c=EmployeeProvisioning.parse(valid());assertEquals("new.employee",c.account());assertEquals("新同事",c.name()); }
    @Test void rejectsPrivilegeAndCompanyInjection() {
        for(String key:List.of("role","companyId","status","mustChangePassword")) { var b=valid();b.put(key,"ADMIN");assertThrows(ApiError.class,()->EmployeeProvisioning.parse(b)); }
    }
    @Test void rejectsInvalidIdentityAndPassword() {
        for(var entry:Map.of("account","x","phone","123","password","too-short","name"," ","departmentId","","teamId","","managerId","").entrySet()) {
            var b=valid();b.put(entry.getKey(),entry.getValue());assertThrows(ApiError.class,()->EmployeeProvisioning.parse(b));
        }
        var b=valid();b.put("password","密".repeat(25));assertThrows(ApiError.class,()->EmployeeProvisioning.parse(b));
    }
    @Test void checksNameBoundary() { var b=valid();b.put("name","字".repeat(100));assertEquals(100,EmployeeProvisioning.parse(b).name().length());b.put("name","字".repeat(101));assertThrows(ApiError.class,()->EmployeeProvisioning.parse(b)); }
    @Test void checksIdentityCardAndGender() {
        var invalidCheck=valid();invalidCheck.put("idCardNumber","110105194912310021");assertThrows(ApiError.class,()->EmployeeProvisioning.parse(invalidCheck));
        var invalidDate=valid();invalidDate.put("idCardNumber","11010519900230002X");assertThrows(ApiError.class,()->EmployeeProvisioning.parse(invalidDate));
        var invalidGender=valid();invalidGender.put("gender","未知");assertThrows(ApiError.class,()->EmployeeProvisioning.parse(invalidGender));
    }
}
