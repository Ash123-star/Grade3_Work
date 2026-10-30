package cn.workpanel.module.review.infrastructure;

import cn.workpanel.Db;
import java.util.*;

/** Only resolves names already referenced by an authorized review; never returns account data. */
public class ReviewDisplayReferences {
    private final Db db;
    public ReviewDisplayReferences(Db db) { this.db=db; }

    public Map<String,Object> resolve(String company,Object before,Object candidate) {
        var ids=new LinkedHashMap<String,Set<String>>();
        collect(before,ids); collect(candidate,ids);
        var result=new LinkedHashMap<String,Object>();
        for(var entry:ids.entrySet()) {
            String table=switch(entry.getKey()) {
                case "people" -> "users";
                case "labels" -> "task_labels";
                case "departments" -> "departments";
                case "teams" -> "teams";
                default -> throw new IllegalArgumentException("reference category");
            };
            var names=new LinkedHashMap<String,String>();
            // Batch long historical snapshots to bound SQL parameter count.
            var values=new ArrayList<>(entry.getValue());
            for(int start=0;start<values.size();start+=100) {
                var batch=values.subList(start,Math.min(start+100,values.size()));
                var args=new ArrayList<Object>(); args.add(company); args.addAll(batch);
                String placeholders=String.join(",",Collections.nCopies(batch.size(),"?"));
                for(var row:db.rows("SELECT id,name FROM "+table+" WHERE company_id=? AND id IN ("+placeholders+")",args.toArray()))
                    names.put(Db.str(row,"id"),Db.str(row,"name"));
            }
            result.put(entry.getKey(),names);
        }
        return result;
    }

    private void collect(Object value,Map<String,Set<String>> ids) {
        if(value instanceof Map<?,?> map) {
            for(var entry:map.entrySet()) {
                String category=switch(String.valueOf(entry.getKey())) {
                    case "participants","participantIds","participant_ids","ownerId","owner_id","managerId","manager_id","collaborators" -> "people";
                    case "labelId","label_id","tagId","tag_id" -> "labels";
                    case "departmentId","department_id" -> "departments";
                    case "teamId","team_id" -> "teams";
                    default -> null;
                };
                if(category!=null) {
                    var entries=entry.getValue() instanceof List<?> list?list:Collections.singletonList(entry.getValue());
                    for(Object id:entries) if(id instanceof String text&&!text.isBlank())
                        ids.computeIfAbsent(category,key->new LinkedHashSet<>()).add(text);
                } else collect(entry.getValue(),ids);
            }
        } else if(value instanceof List<?> list) for(Object item:list) collect(item,ids);
    }
}
