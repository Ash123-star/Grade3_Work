package cn.workpanel.module.aiwork.infrastructure;

import cn.workpanel.*;
import cn.workpanel.module.procedure.domain.ProcedureSearch;
import org.springframework.stereotype.Repository;
import java.util.*;

/** 只读取当前任务可见集合；语义候选只提醒，不参与技术幂等或自动合并。 */
@Repository
public class SimilarTasks {
    private final Db db;
    public SimilarTasks(Db db){this.db=db;}
    public List<Map<String,Object>> find(Actor actor,Map<String,Object> payload){
        String title=Db.str(payload,"title");var terms=ProcedureSearch.terms(title);if(terms.isEmpty())return List.of();
        var scope=Business.taskScope(actor);var args=new ArrayList<Object>(scope.args());args.add(Db.str(payload,"ownerId"));args.add(db.write(terms));
        return db.rows("SELECT t.id,t.title,t.version,t.deadline FROM tasks t WHERE "+scope.sql()+" AND t.owner_id=? AND EXISTS(SELECT 1 FROM jsonb_array_elements_text(?::jsonb) term WHERE strpos(lower(t.title),term)>0) ORDER BY t.created_at DESC,t.id LIMIT 100",args.toArray()).stream().filter(t->similarity(title,Db.str(t,"title"))>=0.65).limit(3).toList();
    }
    public static double similarity(String left,String right){
        String a=ProcedureSearch.normalize(left).replaceAll("[\\p{Punct}\\s]", ""),b=ProcedureSearch.normalize(right).replaceAll("[\\p{Punct}\\s]", "");if(a.equals(b)&&!a.isBlank())return 1;
        var x=new HashSet<>(ProcedureSearch.terms(a));var y=new HashSet<>(ProcedureSearch.terms(b));if(x.isEmpty()||y.isEmpty())return 0;var common=new HashSet<>(x);common.retainAll(y);return 2d*common.size()/(x.size()+y.size());
    }
}
