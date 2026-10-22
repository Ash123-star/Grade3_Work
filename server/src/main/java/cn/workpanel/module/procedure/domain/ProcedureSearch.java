package cn.workpanel.module.procedure.domain;

import java.text.Normalizer;
import java.util.*;
import java.util.regex.Pattern;

/** 有界中文二元词/英文词检索，不将用户输入解释为SQL或检索表达式。 */
public final class ProcedureSearch {
    private ProcedureSearch() {}
    private static final Pattern WORDS=Pattern.compile("[\\p{IsHan}]+|[a-z0-9]{2,}");
    private static final Set<String> STOP=Set.of("帮我","请问","一下","什么","怎么","如何","需要","可以","这个","那个","我们","公司","制度","流程","模板","任务","创建","提交","办理","根据","按照","要求","资料","哪些");
    public static String normalize(String value){return Normalizer.normalize(value,Normalizer.Form.NFKC).toLowerCase(Locale.ROOT).strip();}
    public static List<String> terms(String value){
        var terms=new LinkedHashSet<String>();var matcher=WORDS.matcher(normalize(value));
        while(matcher.find()&&terms.size()<48){String word=matcher.group();if(word.matches("[a-z0-9]+")){terms.add(word);continue;}
            for(int i=0;i<word.length()-1&&terms.size()<48;i++){String part=word.substring(i,i+2);if(!STOP.contains(part))terms.add(part);}}
        return List.copyOf(terms);
    }
    /** 行号与分段位置始终指向已发布原文；正文再长也能定位到后半段。 */
    public static List<Map<String,Object>> chunks(String content){
        var chunks=new ArrayList<Map<String,Object>>();var lines=content.split("\\R",-1);
        for(int line=0;line<lines.length;line++)for(int start=0;start<lines[line].length();start+=600){String text=lines[line].substring(start,Math.min(start+600,lines[line].length()));if(!text.isBlank())chunks.add(Map.of("locator","第"+(line+1)+"行 · 第"+(start/600+1)+"段","content",text));}
        return chunks;
    }
    public static List<Map<String,Object>> excerpts(String content,String query){
        var terms=terms(query);return chunks(content).stream().sorted(Comparator.<Map<String,Object>>comparingLong(c->terms.stream().filter(t->normalize(c.get("content").toString()).contains(t)).count()).reversed()).limit(3).toList();
    }
    public static boolean conflicts(Map<String,Object> left,Map<String,Object> right){
        if(!Objects.equals(left.get("scopeKind"),right.get("scopeKind"))||!Objects.equals(left.get("scopeId"),right.get("scopeId")))return false;
        if(normalize(Objects.toString(left.get("title"),"")).equals(normalize(Objects.toString(right.get("title"),"")))&&!Objects.equals(left.get("content"),right.get("content")))return true;
        for(var a:items(left))for(var b:items(right))if(sameRequirement(a,b)&&!ruleValue(a).equals(ruleValue(b)))return true;
        String a=normalize(Objects.toString(left.get("content"),"")),b=normalize(Objects.toString(right.get("content"),""));
        if(a.equals(b))return false;
        // 不同标题的正文也可能约束同一对象。无法证明这些约束一致时暂停办理，不能交给模型任选其一。
        for(String first:a.split("[。！？!?；;\\r\\n]+"))for(String second:b.split("[。！？!?；;\\r\\n]+"))
            if(!first.equals(second)&&normative(first)&&normative(second)&&overlap(first,second)>=2)return true;
        String workflow=Objects.toString(left.get("workflow"),"");
        if(!workflow.isBlank()&&workflow.equals(right.get("workflow"))&&normative(a)&&normative(b))return true;
        // 同义术语归一只用于发现需人工核对的重叠，不推断哪条规定有效。
        String ca=concepts(a),cb=concepts(b);
        if(!ca.equals(cb)&&normative(ca)&&normative(cb)&&overlap(ca,cb)>=2)return true;
        return false;
    }
    private static String concepts(String text){
        for(var group:List.of(
            List.of("差旅","出差","因公外出"),List.of("报销","费用申领","费用报支","费用报账"),
            List.of("发票","税票","开票凭证"),List.of("纸质","纸本","纸张版"),List.of("电子","数码"),
            List.of("住宿","酒店","旅馆"),List.of("交通","车费","路费"),List.of("机票","航空票据","航班票据"),
            List.of("成本明细","费用清单","成本清单"),List.of("截止","最迟","期限"),
            List.of("无需","免交","不必","无须"),List.of("必须","务必","强制","需要")))
            for(String alias:group.subList(1,group.size()))text=text.replace(alias,group.getFirst());
        return text;
    }
    private static boolean normative(String value){return value.matches("(?s).*(必须|应当|需要|无需|无须|免交|不必|须|应|不得|禁止|严禁|可以|至少|至多|最迟|截止|上限|下限|不超过|不少于|[0-9]+[元天日份%]).*");}
    private static long overlap(String a,String b){var terms=new HashSet<>(terms(a));terms.retainAll(terms(b));return terms.stream().filter(t->!Set.of("必须","应当","不得","禁止","需要","提供","提交","包含","填写","可以","至少","至多").contains(t)).count();}
    private static boolean sameRequirement(Map<String,Object> a,Map<String,Object> b){return nonemptyEqual(a,b,"id")||nonemptyEqual(a,b,"field")||nonemptyEqual(a,b,"title");}
    private static boolean nonemptyEqual(Map<String,Object> a,Map<String,Object> b,String key){String value=normalize(Objects.toString(a.get(key),""));return !value.isBlank()&&value.equals(normalize(Objects.toString(b.get(key),"")));}
    private static Map<String,Object> ruleValue(Map<String,Object> item){var value=new LinkedHashMap<>(item);value.keySet().removeAll(Set.of("id","source"));return value;}
    @SuppressWarnings("unchecked")private static List<Map<String,Object>> items(Map<String,Object> body){return body.get("acceptanceChecklist") instanceof List<?> list?(List<Map<String,Object>>)list:List.of();}
}
