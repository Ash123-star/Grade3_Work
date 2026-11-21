package cn.workpanel.module.organization;

import cn.workpanel.ApiError;
import cn.workpanel.module.organization.domain.EmployeeProvisioning;
import cn.workpanel.module.organization.domain.EmployeeInput;
import cn.workpanel.module.organization.domain.EmployeeIdentity;
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
    @Test void checksNameBoundary() { var b=valid();b.put("name","字".repeat(50));assertEquals(50,EmployeeProvisioning.parse(b).name().length());b.put("name","字".repeat(51));assertThrows(ApiError.class,()->EmployeeProvisioning.parse(b)); }
    @Test void checksIdentityCardAndGender() {
        var invalidCheck=valid();invalidCheck.put("idCardNumber","110105194912310021");assertThrows(ApiError.class,()->EmployeeProvisioning.parse(invalidCheck));
        var invalidDate=valid();invalidDate.put("idCardNumber","11010519900230002X");assertThrows(ApiError.class,()->EmployeeProvisioning.parse(invalidDate));
        var invalidGender=valid();invalidGender.put("gender","未知");assertThrows(ApiError.class,()->EmployeeProvisioning.parse(invalidGender));
    }

    @Test void acceptsNamesWithExtendedHanAndSeparators() {
        for(String name:List.of("张三","阿依古丽·买买提","O’Connor","Jean-Luc","John Smith","𠮷野家","字".repeat(50))) { var b=valid();b.put("name",name);assertEquals(name,EmployeeProvisioning.parse(b).name()); }
        assertEquals("张三",EmployeeInput.name("  张三  "));
        var invalid=valid();invalid.put("name","\n张三");assertThrows(ApiError.class,()->EmployeeProvisioning.parse(invalid));
        invalid.put("name",false);assertThrows(ApiError.class,()->EmployeeProvisioning.parse(invalid));
        assertEquals(50,EmployeeInput.name("𠮷".repeat(50)).codePointCount(0,100));
    }
    @Test void rejectsInvalidNameCharactersAndLengths() {
        for(String name:List.of("张","张三123","张😀","·张三","张三·","张··三","John  Smith","张\n三","\n张三","张\u200b三","字".repeat(51))) assertThrows(ApiError.class,()->EmployeeInput.name(name),name);
    }
    @Test void validatesPublicPhonePrefixes() {
        for(String phone:List.of("13812345678","19212345678","19612345678","19712345678","16512345678","17112345678","16101234567")) assertDoesNotThrow(()->EmployeeInput.phone(phone));
        for(String phone:List.of("11112345678","12012345678","15412345678","19412345678","123","1381234567a")) assertThrows(ApiError.class,()->EmployeeInput.phone(phone));
    }
    @Test void validatesAddressAndGender() {
        assertDoesNotThrow(()->EmployeeInput.address("11010519491231002X"));
        assertDoesNotThrow(()->EmployeeInput.address("44052419491231002X"));
        assertThrows(ApiError.class,()->EmployeeInput.address("99999919491231002X"));
        assertThrows(ApiError.class,()->EmployeeInput.address("11000019491231002X"));
        var b=valid();b.put("gender","男");assertEquals("IDENTITY_GENDER_MISMATCH",assertThrows(ApiError.class,()->EmployeeProvisioning.parse(b)).code);
    }
}
