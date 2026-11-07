package cn.workpanel.module.dashboard.domain;

import cn.workpanel.ApiError;
import org.junit.jupiter.api.Test;
import java.util.Map;
import static org.junit.jupiter.api.Assertions.*;

class CompanyItemPolicyTest {
    @Test void validTextAndPositionBoundaries(){for(int p:new int[]{0,10000})assertDoesNotThrow(()->CompanyItemPolicy.validate(Map.of("title","年度目标","text","说明","position",p,"pinned",true,"archived",false)));}
    @Test void invalidInputCannotBecomePublished(){for(Map<String,Object> value:java.util.List.<Map<String,Object>>of(Map.of("title"," "),Map.of("title","x".repeat(201)),Map.of("title","事项","text","x".repeat(20001)),Map.of("title","事项","position",0.5),Map.of("title","事项","position",-1),Map.of("title","事项","position",10001),Map.of("title","事项","pinned","true")))assertThrows(ApiError.class,()->CompanyItemPolicy.validate(value));}
    @Test void reasonMustBeNonblankAndBounded(){assertThrows(ApiError.class,()->CompanyItemPolicy.reason(Map.of("reason"," ")));assertThrows(ApiError.class,()->CompanyItemPolicy.reason(Map.of("reason","x".repeat(2001))));assertEquals("调整年度目标",CompanyItemPolicy.reason(Map.of("reason"," 调整年度目标 ")));}
}
