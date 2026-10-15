package cn.workpanel.module.log.application;

import cn.workpanel.*;
import org.springframework.stereotype.Service;
import java.util.*;

/** 日报列表应用服务：组织范围和草稿私密性只在服务端决定。 */
@Service
public class LogQueryService {
    final Db db;
    public LogQueryService(Db db) { this.db=db; }
    public record Query(int cursor,int limit,String ownerId,String date,String period) {}

    /** 普通列表允许本人草稿；下属模式只返回组织范围内他人的已提交日报。 */
    public Map<String,Object> list(Actor actor,Query query,boolean subordinate) {
        Business.page(query.cursor(),query.limit());
        if(subordinate&&!actor.manager()) throw ApiError.forbidden();
        Business.Range range=query.date()==null?null:Business.range(query.date(),query.period());
        var scope=Business.ownerScope(actor,"l"); var args=new ArrayList<Object>(scope.args());
        String where=scope.sql()+" AND (l.submitted OR l.owner_id=?)"; args.add(actor.id());
        if(subordinate) { where+=" AND l.owner_id<>? AND l.submitted"; args.add(actor.id()); }
        if(query.ownerId()!=null) {
            var owner=db.one("SELECT * FROM users WHERE id=? AND company_id=?",query.ownerId(),actor.company());
            if(!actor.canSeeUser(owner)) throw ApiError.forbidden(); where+=" AND l.owner_id=?"; args.add(query.ownerId());
        }
        if(range!=null) { where+=" AND l.business_date>=?::date AND l.business_date<?::date"; args.add(range.first().toString()); args.add(range.end().toString()); }
        long total=db.count("SELECT count(*) FROM daily_logs l WHERE "+where,args.toArray()); args.add(query.limit()); args.add(query.cursor());
        var items=db.rows("SELECT l.* FROM daily_logs l WHERE "+where+" ORDER BY l.business_date DESC,l.id LIMIT ? OFFSET ?",args.toArray()).stream().map(log->Business.logDto(db,log)).toList();
        return Map.of("items",items,"total",total,"nextCursor",String.valueOf(query.cursor()+query.limit()));
    }
}
