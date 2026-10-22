package cn.workpanel.module.aiwork.domain;

import cn.workpanel.*;
import java.math.BigDecimal;
import java.util.*;

/** 可核实项目用确定规则；语义推断、公式及签章永远不伪装成通过。 */
public final class DeliveryRules {
    public static final String VERSION="delivery-rules-2";
    private DeliveryRules(){}
    public static Map<String,Object> check(List<Map<String,Object>> items,List<Map<String,Object>> files){
        var findings=new ArrayList<Map<String,Object>>();
        if(items.isEmpty())findings.add(finding("initial","尚未约定交付清单","UNVERIFIABLE","请由任务派发人确认交付要求",""));
        else if(items.stream().noneMatch(i->!"INFERRED".equals(i.get("category"))&&Boolean.TRUE.equals(i.get("required"))))findings.add(finding("no-confirmed","交付要求需要确认","UNVERIFIABLE","建议项不能替代正式验收要求",""));
        for(var item:items){
            String id=Db.str(item,"id"),title=Db.str(item,"title");
            if("INFERRED".equals(item.get("category"))){findings.add(finding(id,title,"NOT_APPLICABLE","这是建议项",""));continue;}
            String name=Db.str(item,"fileName"),field=Db.str(item,"field"),expected=Db.str(item,"expected");
            var matching=files.stream().filter(f->name.isBlank()||Db.str(f,"filename").equalsIgnoreCase(name)).toList();
            if(matching.isEmpty()){findings.add(finding(id,title,Boolean.FALSE.equals(item.get("required"))?"NOT_APPLICABLE":"NEEDS_FIX","缺少"+(name.isBlank()?"材料":name),""));continue;}
            if(field.isBlank()){findings.add(finding(id,title,name.isBlank()?"UNVERIFIABLE":"PASS",name.isBlank()?"这项要求需要人工核对":"已找到要求的文件",name));continue;}
            var hits=new ArrayList<Map<String,Object>>();for(var file:matching)for(var p:parts(file))if(fieldValue(Db.str(p,"text"),field)!=null)hits.add(p);
            if(hits.size()!=1||Boolean.TRUE.equals(hits.getFirst().get("unverifiable"))||expected.isBlank()){findings.add(finding(id,title,"UNVERIFIABLE","未找到唯一且可核实的字段",field));continue;}
            var hit=hits.getFirst();String value=Db.str(hit,"text");boolean same=false;
            if(expected.matches("[+-]?\\d+(\\.\\d+)?")){
                String unit=Db.str(item,"unit"),currency=Db.str(item,"currency");
                if(!unit.isBlank()&&!value.contains(unit)||!currency.isBlank()&&!value.contains(currency)){findings.add(finding(id,title,"UNVERIFIABLE","单位或币种需要核对",Db.str(hit,"locator")));continue;}
                String tail=fieldValue(value,field);var matcher=java.util.regex.Pattern.compile("^([+-]?\\d+(?:\\.\\d+)?)(?![\\d,.])").matcher(tail);
                if(!matcher.find()){findings.add(finding(id,title,"UNVERIFIABLE","数值不能可靠读取",Db.str(hit,"locator")));continue;}
                same=new BigDecimal(expected).compareTo(new BigDecimal(matcher.group(1)))==0;
            }else same=fieldValue(value,field).trim().equals(expected);
            findings.add(finding(id,title,same?"PASS":"NEEDS_FIX",same?"内容一致":"内容与交付要求不一致",Db.str(hit,"locator")));
        }
        if(files.stream().anyMatch(f->Boolean.TRUE.equals(f.get("unverifiable"))))findings.add(finding("unreadable","部分材料需要人工核对","UNVERIFIABLE","扫描页、公式或不清晰内容尚未核实",""));
        if(files.isEmpty())findings.add(finding("missing","请添加交付材料","NEEDS_FIX","尚未添加文件",""));
        String state=findings.stream().anyMatch(f->f.get("state").equals("NEEDS_FIX"))?"NEEDS_FIX":findings.stream().anyMatch(f->f.get("state").equals("UNVERIFIABLE"))?"UNVERIFIABLE":"PASS";
        return Map.of("state",state,"findings",findings,"ruleVersion",VERSION,"summary",switch(state){case "PASS"->"材料已核对";case "NEEDS_FIX"->"有几处材料需要补充";default->"有些内容需要人工核对";});
    }
    @SuppressWarnings("unchecked")private static List<Map<String,Object>> parts(Map<String,Object> f){return (List<Map<String,Object>>)f.get("parts");}
    // 只接受独立字段标签；“项目：成本明细”中的成本不是字段，重复标签仍需核对。
    private static String fieldValue(String text,String field){
        var matcher=java.util.regex.Pattern.compile("(?:^|[\\r\\n;；])\\s*"+java.util.regex.Pattern.quote(field)+"\\s*[:：=]\\s*([^\\r\\n;；]*)").matcher(text);
        if(!matcher.find())return null;String value=matcher.group(1);return matcher.find()?"":value;
    }
    private static Map<String,Object> finding(String id,String title,String state,String message,String locator){return Map.of("id",id,"title",title,"state",state,"message",message,"locator",locator);}
}
