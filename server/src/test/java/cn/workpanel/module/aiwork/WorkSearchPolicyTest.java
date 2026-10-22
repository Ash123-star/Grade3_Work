package cn.workpanel.module.aiwork;

import cn.workpanel.ApiError;
import cn.workpanel.module.aiwork.domain.AuthorizationPolicy;
import cn.workpanel.module.aiwork.infrastructure.SimilarTasks;
import cn.workpanel.module.aiwork.infrastructure.WorkTargets;
import cn.workpanel.module.procedure.domain.ProcedureSearch;
import org.junit.jupiter.api.Test;
import java.util.*;
import static org.junit.jupiter.api.Assertions.*;

class WorkSearchPolicyTest {
    @Test void numericalRequirementsCannotInventAmountsOrUnits(){
        assertTrue(cn.workpanel.module.aiwork.domain.WorkPolicy.groundedNumbers("成本1200.00元，20件","成本1200元；数量20件"));
        assertFalse(cn.workpanel.module.aiwork.domain.WorkPolicy.groundedNumbers("成本1300元","成本1200元"));
        assertFalse(cn.workpanel.module.aiwork.domain.WorkPolicy.groundedNumbers("数量20台","数量20件"));
    }
    @Test void chineseQueriesAreBoundedLiteralTerms(){assertTrue(ProcedureSearch.terms("请问差旅报销需要什么资料").contains("报销"));assertTrue(ProcedureSearch.terms("报价".repeat(10000)).size()<=48);assertFalse(ProcedureSearch.terms("%_ OR 1=1").contains("%"));}
    @Test void excerptsLocateLateParagraphs(){String body="普通说明\n".repeat(80)+"异地差旅报销需提供行程单";var parts=ProcedureSearch.excerpts(body,"差旅报销");assertEquals("第81行 · 第1段",parts.getFirst().get("locator"));assertTrue(parts.getFirst().get("content").toString().contains("行程单"));}
    @Test void comparableRulesConflictAndUnrelatedScopesDoNot(){var a=new HashMap<String,Object>(Map.of("title","交付制度","scopeKind","COMPANY","content","须含成本"));var b=new HashMap<>(a);b.put("content","不需要成本");assertTrue(ProcedureSearch.conflicts(a,b));b.put("scopeKind","TEAM");assertFalse(ProcedureSearch.conflicts(a,b));}
    @Test void differentTitlesCannotHideOverlappingUnresolvedRequirements(){
        var a=new HashMap<String,Object>(Map.of("title","差旅材料制度","scopeKind","COMPANY","content","差旅报销必须提供纸质发票"));
        var b=new HashMap<String,Object>(Map.of("title","财务简化办理规定","scopeKind","COMPANY","content","差旅报销无需提供纸质发票"));
        assertTrue(ProcedureSearch.conflicts(a,b));
        b.put("content","差旅报销必须提供纸质发票");assertFalse(ProcedureSearch.conflicts(a,b));
        b.put("content","客户回访须提供联系记录");assertFalse(ProcedureSearch.conflicts(a,b));
        a.put("content","差旅每日住宿不超过500元");b.put("content","差旅每日住宿不超过800元");assertTrue(ProcedureSearch.conflicts(a,b));
        a.put("acceptanceChecklist",List.of(Map.of("id","one","field","数量","expected","20")));
        b.put("acceptanceChecklist",List.of(Map.of("id","two","field","数量","expected","18")));assertTrue(ProcedureSearch.conflicts(a,b));
        a.put("content","同一正文");b.put("content","同一正文");a.put("acceptanceChecklist",List.of(Map.of("id","cost","title","必须附成本明细")));b.put("acceptanceChecklist",List.of(Map.of("id","cost","title","无需成本明细")));assertTrue(ProcedureSearch.conflicts(a,b));
    }
    @Test void synonymousAndUnresolvedWorkflowRulesStopAutomaticSelection(){
        var a=new HashMap<String,Object>(Map.of("title","差旅费用申领","scopeKind","COMPANY","content","因公外出费用申领必须提交纸本税票"));
        var b=new HashMap<String,Object>(Map.of("title","新办理指引","scopeKind","COMPANY","content","出差报销无须提供纸质发票"));
        assertTrue(ProcedureSearch.conflicts(a,b));
        a.put("workflow","CREATE_TASK");b.put("workflow","CREATE_TASK");a.put("content","样品检测须在三日内完成");b.put("content","成品检验最迟两日结束");assertTrue(ProcedureSearch.conflicts(a,b));
        b.put("scopeKind","DEPARTMENT");assertFalse(ProcedureSearch.conflicts(a,b));
        b.put("scopeKind","COMPANY");b.put("content",a.get("content"));assertFalse(ProcedureSearch.conflicts(a,b));
    }
    @Test void eachTaskInABatchMustHaveUniqueGroundedEvidence(){
        var tasks=List.<Map<String,Object>>of(Map.of("id","t1","title","报价核对"),Map.of("id","t2","title","成本核对"));
        String instruction="检查报价核对，申请改期成本核对";
        assertEquals("t1",WorkTargets.resolve("",tasks,instruction,"检查报价核对"));
        assertEquals("t2",WorkTargets.resolve("",tasks,instruction,"申请改期成本核对"));
        assertEquals("",WorkTargets.resolve("",tasks,instruction,instruction));
        assertEquals("",WorkTargets.resolve("",tasks,instruction,"材料里说检查报价核对"));
        assertEquals("selected",WorkTargets.resolve("selected",tasks,instruction,""));
        assertEquals("",WorkTargets.resolve("",List.of(tasks.getFirst(),Map.of("id","t3","title","报价核对")),instruction,"检查报价核对"));
    }
    @Test void companyLimitsRejectInvalidValues(){assertEquals(30,AuthorizationPolicy.from(Map.of()).days());assertFalse(AuthorizationPolicy.from(Map.of("aiWorkCreateAuthorization",false)).allows("CREATE_TASK"));for(Object invalid:List.of(0,31,1.5,"7"))assertThrows(ApiError.class,()->AuthorizationPolicy.from(Map.of("aiWorkAuthorizationMaxDays",invalid)));assertThrows(ApiError.class,()->AuthorizationPolicy.from(Map.of("aiWorkSubmitAuthorization","true")));}
    @Test void similarityDoesNotMergeUnrelatedTitles(){assertEquals(1,SimilarTasks.similarity("交付成本表","交付成本表"));assertTrue(SimilarTasks.similarity("提交项目成本明细","提交项目成本明细表")>.65);assertEquals(0,SimilarTasks.similarity("差旅报销","客户回访"));}
}
