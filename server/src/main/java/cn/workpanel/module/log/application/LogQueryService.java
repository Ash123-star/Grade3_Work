package cn.workpanel.module.log.application;

import cn.workpanel.*;
import org.springframework.stereotype.Service;
import java.util.*;

/** 日报列表应用服务：组织范围和草稿私密性只在服务端决定。 */
@Service
public class LogQueryService {
    final Db db; final LogQueryRepository repository;
    public LogQueryService(Db db) { this.db=db; this.repository=new LogQueryRepository(db); }
    public record Query(int cursor,int limit,String ownerId,String date,String period,String departmentId,String search) {
        public Query(int cursor,int limit,String ownerId,String date,String period) { this(cursor,limit,ownerId,date,period,null,null); }
    }

    /** 普通列表允许本人草稿；下属模式只返回组织范围内他人的已提交日报。 */
    public Map<String,Object> list(Actor actor,Query query,boolean subordinate) {
        Business.page(query.cursor(),query.limit());
        if(subordinate&&!actor.manager()) throw ApiError.forbidden();
        Business.Range range=query.date()==null?null:Business.range(query.date(),query.period());
        if(query.search()!=null&&query.search().length()>100) throw ApiError.bad("INVALID_SEARCH","关键词最多100字");
        if(query.departmentId()!=null&&query.departmentId().length()>100) throw ApiError.bad("INVALID_DEPARTMENT","部门参数无效");
        if(query.ownerId()!=null) {
            var owner=repository.owner(actor,query.ownerId());
            if(!actor.canSeeUser(owner)) throw ApiError.forbidden();
        }
        var page=repository.find(actor,query,subordinate,range);
        var now=java.time.Instant.now();
        var items=page.items().stream().map(log->{
            var dto=LogEditWindow.view(db,actor,log,now);
            dto.put("author",Map.of("id",Db.str(log,"owner_id"),"name",Db.str(log,"author_name")));
            dto.put("department",Map.of("id",Db.str(log,"department_id"),"name",Db.str(log,"department_name")));
            return dto;
        }).toList();
        var result=new LinkedHashMap<String,Object>();
        result.put("items",items); result.put("total",page.total()); result.put("nextCursor",String.valueOf(query.cursor()+query.limit()));
        if(subordinate) {
            var groups=new LinkedHashMap<String,Map<String,Object>>();
            for(var item:items) {
                var group=groups.computeIfAbsent(Db.str(item,"department_id"),key->{
                    var value=new LinkedHashMap<String,Object>(); value.put("department",item.get("department")); value.put("items",new ArrayList<Map<String,Object>>()); return value;
                });
                @SuppressWarnings("unchecked") var records=(List<Map<String,Object>>)group.get("items"); records.add(item);
            }
            result.put("groups",new ArrayList<>(groups.values()));
        }
        return result;
    }
}
