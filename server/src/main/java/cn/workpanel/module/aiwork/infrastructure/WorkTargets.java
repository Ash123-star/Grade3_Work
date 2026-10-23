package cn.workpanel.module.aiwork.infrastructure;

import cn.workpanel.*;
import org.springframework.stereotype.Repository;
import java.util.*;

/** 只有用户本次文字中的完整任务名/ID才能成为候选；材料和模型输出不构成选定对象。 */
@Repository
public class WorkTargets {
    private final Db db;
    public WorkTargets(Db db){this.db=db;}
    public List<Map<String,Object>> candidates(Actor actor,String instruction){
        var scope=Business.taskScope(actor);var args=new ArrayList<Object>(scope.args());args.add(instruction);args.add(instruction);
        return db.rows("SELECT t.id,t.title,t.version FROM tasks t WHERE "+scope.sql()+" AND ((length(t.title)>=2 AND strpos(lower(?),lower(t.title))>0) OR strpos(?,t.id)>0) ORDER BY length(t.title) DESC,t.id LIMIT 6",args.toArray());
    }
    /** 多对象操作必须逐项引用用户原句且只命中一个候选；模型返回ID不能充当来源。 */
    public static String resolve(String selected,List<Map<String,Object>> candidates,String instruction,String evidence){
        if(!selected.isBlank())return selected;
        if(candidates.size()==1)return Db.str(candidates.getFirst(),"id");
        if(evidence.isBlank()||!instruction.contains(evidence))return "";
        var matches=candidates.stream().filter(t->mentions(evidence,Db.str(t,"id"))||mentions(evidence,Db.str(t,"title"))).toList();
        return matches.size()==1?Db.str(matches.getFirst(),"id"):"";
    }
    private static boolean mentions(String text,String value){return value.length()>=2&&text.toLowerCase(Locale.ROOT).contains(value.toLowerCase(Locale.ROOT));}
}
