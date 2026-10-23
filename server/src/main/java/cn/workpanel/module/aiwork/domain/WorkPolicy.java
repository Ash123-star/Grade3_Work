package cn.workpanel.module.aiwork.domain;

import cn.workpanel.*;
import java.time.*;
import java.util.*;

/** 确定性授权及日期边界，模型只建议内容，不能授予角色或审批能力。 */
public final class WorkPolicy {
    private WorkPolicy(){}
    public static final Set<String> ACTIONS=Set.of("CREATE_TASK","CHECK_DELIVERY","SUBMIT_DELIVERY","REQUEST_RESCHEDULE","REQUEST_REASSIGNMENT");
    public static boolean canDispatch(Actor a){return a.manager()&&a.dispatch();}
    /** 这些独立申请系统尚未接入；模型答复不能伪装其办理回执。 */
    public static boolean externalApplication(String text){return text.matches("(?s).*(报销|采购|付款|支付|请假|用印|合同审批).*")&&text.matches("(?s).*(提交|发起|办理|支付|付款|批准|同意|审批).*");}
    /** 本次只检查的指令优先于模型建议和长期提交授权。 */
    public static boolean checkOnly(String text){
        if(!text.matches("(?s).*(检查|核对|看看).*"))return false;
        if(text.matches("(?s).*(只|仅|光)(帮我|需要|要)?(检查|核对|看看).*"))return true;
        if(text.matches("(?s).*(不要|不用|不必|暂不|别|禁止)(自动)?(提交|反馈).*"))return true;
        return !text.contains("提交")&&!text.matches("(?s).*(检查|核对)(通过|完成|完)?后.*反馈.*");
    }
    /** 长期授权不能覆盖用户本次明确的停止/禁止指令。 */
    public static boolean denies(String text,String action){
        if(readOnly(action))return false;
        String target=switch(action){case "CREATE_TASK"->"(创建|建任务|派发|分配任务)";case "SUBMIT_DELIVERY"->"(提交|反馈)";case "REQUEST_RESCHEDULE"->"(改期|调整截止|变更时间)";case "REQUEST_REASSIGNMENT"->"(转派|更换负责人)";default->"(?!)";};
        return text.matches("(?s).*(不要|不用|不必|暂不|暂时不|(?<!分)别|禁止|取消|停止|先不).{0,16}"+target+".*")||text.matches("(?s).*(不要办理|不用办理|停止办理|取消办理|只整理|仅整理|只保留|仅保留).*");
    }
    public static boolean readOnly(String action){return Set.of("PREPARE","CHECK_DELIVERY").contains(action);}
    public static boolean explicit(String text,String action){
        if(text.matches("(?s).*(不要|(?<!分)别|不必|不用|禁止|取消|暂不|不创建|不提交|是否|能否|如果|假如).*"))return false;
        if(text.matches("(?s).*(聊天记录|转述|原文|他说|她说|引用).*"))return false;
        return switch(action){case "CREATE_TASK"->text.matches("(?s).*(请|帮我|直接|现在|立即).*(创建任务|建任务|派发|分配任务).* ".trim());case "SUBMIT_DELIVERY"->text.matches("(?s).*(检查后提交|检查通过后提交|核对后提交|提交反馈).* ".trim());case "REQUEST_RESCHEDULE"->text.contains("申请改期");case "REQUEST_REASSIGNMENT"->text.contains("申请转派");default->false;};
    }
    /** Only the latest user instruction may anchor a relative date; screenshots/history never call this. */
    public static String absoluteLatestDates(String text,Instant received){
        if(text.matches("(?s).*(聊天记录|旧聊天|转述|原文|他说|她说|引用).*"))return text;
        var pattern=java.util.regex.Pattern.compile("(今天|明天|后天)(上午|早上|下午|晚上)?(\\d{1,2})(?:[:：]([0-5]\\d)|点(?:(\\d{1,2})分?)?)");
        var matcher=pattern.matcher(text);var result=new StringBuffer();var day=received.atZone(ZoneId.of("Asia/Shanghai")).toLocalDate();
        while(matcher.find()){int hour=Integer.parseInt(matcher.group(3)),minute=matcher.group(4)!=null?Integer.parseInt(matcher.group(4)):matcher.group(5)!=null?Integer.parseInt(matcher.group(5)):0;
            if(Set.of("下午","晚上").contains(Objects.toString(matcher.group(2),""))&&hour<12)hour+=12;
            if(hour>23||minute>59)continue;var target=day.plusDays(matcher.group(1).equals("明天")?1:matcher.group(1).equals("后天")?2:0);
            matcher.appendReplacement(result,java.util.regex.Matcher.quoteReplacement(target.getYear()+"年"+target.getMonthValue()+"月"+target.getDayOfMonth()+"日"+String.format(java.util.Locale.ROOT,"%02d:%02d",hour,minute)));
        }matcher.appendTail(result);return result.toString();
    }
    public static boolean validDeadline(String deadline,String evidence,String trustedText){
        try{var date=OffsetDateTime.parse(deadline);if(!date.toInstant().isAfter(Instant.now()))return false;
            if(evidence.isBlank()||!trustedText.contains(evidence))return false;
            // 相对时间只能来自本次文字。绝对日期必须明确到日期与时刻；“下周”“尽快”不能猜。
            boolean explicitDate=evidence.matches("(?s).*(\\d{4}[-年/]\\d{1,2}[-月/]\\d{1,2}).*");
            boolean clock=evidence.matches("(?s).*(\\d{1,2}[:：]\\d{2}|\\d{1,2}点).* ".trim());
            if(!explicitDate||!clock)return false;
            var d=java.util.regex.Pattern.compile("(\\d{4})[-年/](\\d{1,2})[-月/](\\d{1,2})").matcher(evidence);
            var t=java.util.regex.Pattern.compile("(\\d{1,2})(?:[:：]([0-5]\\d)|点(?:(\\d{1,2})分?)?)").matcher(evidence);
            if(!d.find()||!t.find())return false;
            int hour=Integer.parseInt(t.group(1));if((evidence.contains("下午")||evidence.contains("晚上"))&&hour<12)hour+=12;
            int minute=t.group(2)!=null?Integer.parseInt(t.group(2)):t.group(3)!=null?Integer.parseInt(t.group(3)):0;
            var expected=LocalDate.of(Integer.parseInt(d.group(1)),Integer.parseInt(d.group(2)),Integer.parseInt(d.group(3))).atTime(hour,minute).atZone(ZoneId.of("Asia/Shanghai")).toInstant();
            return expected.equals(date.toInstant());
        }catch(Exception e){return false;}
    }
    /** 数量和金额必须能回到输入中的同值同单位；不替模型猜换算或计算。 */
    public static boolean groundedNumbers(String candidate,String evidence){
        return quantities(evidence).containsAll(quantities(candidate));
    }
    private static Set<String> quantities(String text){
        var values=new HashSet<String>();
        var matcher=java.util.regex.Pattern.compile("(?<![\\d.])([+-]?\\d+(?:\\.\\d+)?)\\s*(万元|元|%|件|台|个|套|公斤|千克|吨|米|小时)").matcher(text);
        while(matcher.find())values.add(new java.math.BigDecimal(matcher.group(1)).stripTrailingZeros().toPlainString()+matcher.group(2));
        return values;
    }
    public static String redact(String input){
        if(input.matches("(?is).*(私钥|API[_ -]?KEY|BEGIN.*PRIVATE KEY|密码\\s*[:：=]|口令\\s*[:：=]).*"))throw ApiError.bad("SENSITIVE_MATERIAL","材料含有敏感凭据，请移除后重试");
        return input.replaceAll("(?<!\\d)1[3-9]\\d{9}(?!\\d)","[手机号已隐藏]").replaceAll("(?<!\\d)\\d{17}[\\dXx](?!\\d)","[证件号已隐藏]").replaceAll("(?<!\\d)\\d{16,19}(?!\\d)","[账号已隐藏]");
    }
    public static void version(Map<String,Object> row,Map<String,Object> body){if(((Number)row.get("version")).intValue()!=Db.version(body))throw ApiError.conflict();}
}
