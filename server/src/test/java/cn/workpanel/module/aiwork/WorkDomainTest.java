package cn.workpanel.module.aiwork;

import cn.workpanel.*;
import cn.workpanel.module.aiwork.domain.*;
import cn.workpanel.module.task.AcceptanceChecklist;
import cn.workpanel.module.procedure.domain.ProcedureDocument;
import org.junit.jupiter.api.Test;
import java.util.*;
import static org.junit.jupiter.api.Assertions.*;

class WorkDomainTest {
    @Test void intakeRejectsEmptyOversizedAndForgedFields(){
        assertThrows(ApiError.class,()->WorkInput.parse(Map.of("text"," "),false));
        assertThrows(ApiError.class,()->WorkInput.parse(Map.of("text","x".repeat(10001)),false));
        assertThrows(ApiError.class,()->WorkInput.parse(Map.of("text","建任务","actorId","forged"),false));
        assertThrows(ApiError.class,()->WorkInput.parse(Map.of("text","检查","taskId","t"),false));
        assertEquals(List.of("f"),WorkInput.parse(Map.of("attachmentIds",List.of("f")),false).attachments());
        assertEquals("owner",WorkInput.parse(Map.of("text","已选负责人","version",1,"answers",Map.of("ownerId","owner")),true).answers().get("ownerId"));
        assertThrows(ApiError.class,()->WorkInput.parse(Map.of("text","已选负责人","answers",Map.of("role","ADMIN")),true));
    }
    @Test void explicitUserCommandAndRoleAreIndependent(){
        assertTrue(WorkPolicy.explicit("请帮我创建任务","CREATE_TASK"));
        assertTrue(WorkPolicy.explicit("请帮我创建任务，小李和小王分别交付材料","CREATE_TASK"));
        assertFalse(WorkPolicy.denies("请分别创建任务","CREATE_TASK"));
        assertTrue(WorkPolicy.denies("别创建任务","CREATE_TASK"));
        assertFalse(WorkPolicy.explicit("截图里提到了派发","CREATE_TASK"));
        assertFalse(WorkPolicy.canDispatch(new Actor("a","c","EMPLOYEE","","",true,false,false,"ACTIVE")));
        assertFalse(WorkPolicy.explicit("自动验收任务","ACCEPTED"));
    }
    @Test void checkOnlyIntentNeverBecomesSubmission(){
        for(String text:List.of("帮我检查交付材料","只检查这份材料","核对材料，不要提交","看看成本，不用自动提交","帮我检查反馈内容"))assertTrue(WorkPolicy.checkOnly(text),text);
        assertFalse(WorkPolicy.checkOnly("帮我检查后提交"));assertTrue(WorkPolicy.explicit("检查后提交","SUBMIT_DELIVERY"));assertFalse(WorkPolicy.explicit("检查后提交，不要自动验收","SUBMIT_DELIVERY"));
        assertTrue(WorkPolicy.readOnly("CHECK_DELIVERY"));assertFalse(WorkPolicy.readOnly("SUBMIT_DELIVERY"));
        assertThrows(ApiError.class,()->WorkInput.parse(Map.of("text","检查","taskId","t","taskVersion",1.5),false));
    }
    @Test void currentProhibitionOverridesStandingAuthorization(){
        for(String text:List.of("先不要提交这份材料","暂时不用这份文件提交","取消提交","仅整理材料"))assertTrue(WorkPolicy.denies(text,"SUBMIT_DELIVERY"),text);
        assertTrue(WorkPolicy.denies("不要创建任务","CREATE_TASK"));assertFalse(WorkPolicy.denies("检查后提交，不要验收","SUBMIT_DELIVERY"));assertFalse(WorkPolicy.denies("检查材料","CHECK_DELIVERY"));
    }
    @Test void deadlineMustMatchEvidenceAndCannotInventClock(){
        assertTrue(WorkPolicy.validDeadline("2099-10-23T17:00:00+08:00","2099年10月23日17:00","截止2099年10月23日17:00"));
        assertFalse(WorkPolicy.validDeadline("2099-10-24T17:00:00+08:00","2099年10月23日17:00","截止2099年10月23日17:00"));
        assertFalse(WorkPolicy.validDeadline("2099-10-23T17:00:00+08:00","下周交付","下周交付"));
        assertTrue(WorkPolicy.validDeadline("2099-10-23T20:05:00+08:00","2099年10月23日晚上8点5分","2099年10月23日晚上8点5分"));
        assertFalse(WorkPolicy.validDeadline("2099-10-23T20:00:00+08:00","2099年10月23日晚上8点5分","2099年10月23日晚上8点5分"));
    }
    @Test void relativeDatesUseReceiptTimezoneAndQuotedHistoryNeverAnchors(){
        var receipt=java.time.Instant.parse("2099-10-23T17:00:00Z");
        assertEquals("请明示2099年10月25日17:30交付",WorkPolicy.absoluteLatestDates("请明示明天下午5点30分交付",receipt));
        assertEquals("旧聊天：明天17:00交付",WorkPolicy.absoluteLatestDates("旧聊天：明天17:00交付",receipt));
        assertEquals("明天下班前交付",WorkPolicy.absoluteLatestDates("明天下班前交付",receipt));
        assertFalse(WorkPolicy.explicit("原文：请帮我创建任务","CREATE_TASK"));
    }
    @Test void deliveryLabelsIgnoreTitleMentionsAndDuplicateLabelsRemainUnverifiable(){
        var rule=Map.<String,Object>of("id","cost","title","核对成本","category","CONFIRMED","required",true,"field","成本","expected","1200","unit","元");
        var base=new HashMap<>(file("成本：1200元",false));
        base.put("parts",List.of(Map.of("text","项目：成本明细","locator","段落1"),Map.of("text","成本：1200元","locator","段落2")));
        assertEquals("PASS",DeliveryRules.check(List.of(rule),List.of(base)).get("state"));
        base.put("parts",List.of(Map.of("text","成本：1200元","locator","段落1"),Map.of("text","成本：1300元","locator","段落2")));
        assertEquals("UNVERIFIABLE",DeliveryRules.check(List.of(rule),List.of(base)).get("state"));
        assertEquals("UNVERIFIABLE",DeliveryRules.check(List.of(rule),List.of(file("成本：1200元；成本：1300元",false))).get("state"));
        assertEquals("UNVERIFIABLE",DeliveryRules.check(List.of(rule),List.of(file("项目：成本1200元",false))).get("state"));
    }
    @Test void inferenceCannotBecomeMandatory(){
        var item=AcceptanceChecklist.normalize(List.of(Map.of("title","可能需要报价表","required",true,"category","INFERRED"))).getFirst();assertEquals(false,item.get("required"));
        assertThrows(ApiError.class,()->AcceptanceChecklist.normalize(List.of(Map.of("id","x","title","a"),Map.of("id","x","title","b"))));
    }
    @Test void sensitiveCredentialsBlockAndNumbersAreRedacted(){
        assertThrows(ApiError.class,()->WorkPolicy.redact("密码：secret"));assertFalse(WorkPolicy.redact("电话13800138000").contains("13800138000"));
    }
    @Test void numericRulesUseDecimalAndRequireUnit(){
        var requirement=Map.<String,Object>of("id","amount","title","金额一致","field","金额","expected","10.00","unit","元","category","CONFIRMED","required",true);
        assertEquals("PASS",DeliveryRules.check(List.of(requirement),List.of(file("金额：10.0元",false))).get("state"));
        assertEquals("NEEDS_FIX",DeliveryRules.check(List.of(requirement),List.of(file("金额：100元",false))).get("state"));
        assertEquals("UNVERIFIABLE",DeliveryRules.check(List.of(requirement),List.of(file("金额：10",false))).get("state"));
        assertEquals("UNVERIFIABLE",DeliveryRules.check(List.of(requirement),List.of(file("金额：10元",true))).get("state"));
        assertEquals("UNVERIFIABLE",DeliveryRules.check(List.of(),List.of(file("内容",false))).get("state"));
    }
    @Test void actionFingerprintIgnoresAuthorizationMarkersButPreservesBusinessPayload(){
        var db=new Db(null,new com.fasterxml.jackson.databind.ObjectMapper());
        var first=new LinkedHashMap<String,Object>(Map.of("taskId","task-1","text","submit"));first.put("explicit",true);first.put("preauthorized",false);first.put("confirmed",false);
        var second=new LinkedHashMap<String,Object>(Map.of("taskId","task-1","text","submit"));second.put("explicit",false);second.put("preauthorized",true);second.put("confirmed",true);
        assertEquals(WorkActions.fingerprint(db,"SUBMIT_DELIVERY",first),WorkActions.fingerprint(db,"SUBMIT_DELIVERY",second));
        assertNotEquals(WorkActions.fingerprint(db,"SUBMIT_DELIVERY",first),WorkActions.fingerprint(db,"CHECK_DELIVERY",second));
        second.put("text","different request");assertNotEquals(WorkActions.fingerprint(db,"SUBMIT_DELIVERY",first),WorkActions.fingerprint(db,"SUBMIT_DELIVERY",second));
    }
    @Test void dependenciesOnlyReferenceEarlierActionsAndRejectCyclesOrFutureSteps(){
        assertEquals(List.of(),WorkActions.dependencies(null,1));
        assertEquals(List.of("action-1","action-2"),WorkActions.dependencies(List.of(1,2,1),3));
        assertThrows(ApiError.class,()->WorkActions.dependencies(List.of(1),1));
        assertThrows(ApiError.class,()->WorkActions.dependencies(List.of(3),3));
        assertThrows(ApiError.class,()->WorkActions.dependencies(List.of("action-1"),2));
        assertEquals(9,WorkActions.dependencies(List.of(1,2,3,4,5,6,7,8,9),10).size());
        assertThrows(ApiError.class,()->WorkActions.dependencies(List.of(1,2,3,4,5,6,7,8,9,10),11));
    }
    @Test void procedureRejectsExpiredRangeAndArbitraryTools(){
        var b=new LinkedHashMap<String,Object>(Map.of("title","流程","type","PROCEDURE","content","交付要求","effectiveFrom","2099-01-01T00:00:00Z","effectiveTo","2098-01-01T00:00:00Z"));assertThrows(ApiError.class,()->ProcedureDocument.validate(b));
        b.remove("effectiveTo");b.put("workflow","RUN_SQL");assertThrows(ApiError.class,()->ProcedureDocument.validate(b));
    }
    private Map<String,Object> file(String text,boolean uncertain){return Map.of("filename","成本.docx","unverifiable",uncertain,"parts",List.of(Map.of("text",text,"locator","段落1","unverifiable",uncertain)));}
}
