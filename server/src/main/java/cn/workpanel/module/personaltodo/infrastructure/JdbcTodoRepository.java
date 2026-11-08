package cn.workpanel.module.personaltodo.infrastructure;

import cn.workpanel.*;
import cn.workpanel.module.personaltodo.api.TodoContracts.*;
import cn.workpanel.module.personaltodo.domain.*;
import org.springframework.stereotype.Repository;
import java.sql.Timestamp;
import java.time.*;
import java.util.*;

@Repository
public class JdbcTodoRepository implements TodoRepository {
    private final Db db;
    public JdbcTodoRepository(Db db) { this.db=db; }
    private static final String OWN="company_id=? AND owner_id=? AND deleted_at IS NULL";
    @Override public Todo find(Actor a,String id) {
        return todo(db.one("SELECT * FROM personal_todos WHERE "+OWN+" AND id=?",a.company(),a.id(),id));
    }
    @Override public Page page(Actor a,LocalDate date,int cursor,int limit) {
        long total=db.count("SELECT count(*) FROM personal_todos WHERE "+OWN+" AND business_date<=? AND end_date>=?",a.company(),a.id(),date,date);
        var items=db.rows("SELECT * FROM personal_todos WHERE "+OWN+" AND business_date<=? AND end_date>=? ORDER BY completed,business_date,created_at,id LIMIT ? OFFSET ?",a.company(),a.id(),date,date,limit,cursor).stream().map(JdbcTodoRepository::todo).toList();
        return new Page(items,total,cursor+items.size()<total?String.valueOf(cursor+items.size()):null);
    }
    @Override public List<DayCount> counts(Actor a,LocalDate from,LocalDate to) {
        return db.rows("SELECT d::date AS business_date,count(t.id) AS total,count(t.id) FILTER (WHERE t.completed) AS completed FROM generate_series(?::timestamp,?::timestamp - interval '1 day',interval '1 day') AS d LEFT JOIN personal_todos t ON t.company_id=? AND t.owner_id=? AND t.deleted_at IS NULL AND t.business_date<=d::date AND t.end_date>=d::date GROUP BY d ORDER BY d",from,to,a.company(),a.id())
            .stream().map(r->new DayCount(LocalDate.parse(r.get("business_date").toString()),((Number)r.get("total")).longValue(),((Number)r.get("completed")).longValue())).toList();
    }
    @Override public Todo create(Actor a,TodoDraft d) {
        String id=Db.id();
        db.update("INSERT INTO personal_todos(id,company_id,owner_id,business_date,end_date,title,note,color) VALUES (?,?,?,?,?,?,?,?)",id,a.company(),a.id(),d.date(),d.endDate(),d.title(),d.note(),d.color());
        return find(a,id);
    }
    @Override public Todo update(Actor a,String id,TodoDraft d) {
        find(a,id); // An unauthorized id must be 404, never a version oracle.
        Db.conflict(db.update("UPDATE personal_todos SET title=?,note=?,business_date=?,end_date=?,color=?,completed=?,completed_at=CASE WHEN ? THEN COALESCE(completed_at,now()) ELSE NULL END,version=version+1,updated_at=now() WHERE "+OWN+" AND id=? AND version=?",
            d.title(),d.note(),d.date(),d.endDate(),d.color(),d.completed(),d.completed(),a.company(),a.id(),id,d.version()));
        return find(a,id);
    }
    @Override public Deleted delete(Actor a,String id,int version) {
        find(a,id);
        // Remove private content from the tombstone; retain identity/version for concurrency.
        Db.conflict(db.update("UPDATE personal_todos SET title='已删除',note='',deleted_at=now(),updated_at=now(),version=version+1 WHERE "+OWN+" AND id=? AND version=?",a.company(),a.id(),id,version));
        return new Deleted(id,true,version+1);
    }
    @Override public void lockCommand(Actor a,String key) {
        db.one("SELECT pg_advisory_xact_lock(hashtextextended(?,0))",db.write(List.of(a.company(),a.id(),key)));
        db.update("DELETE FROM personal_todo_commands WHERE company_id=? AND owner_id=? AND expires_at<=now()",a.company(),a.id());
    }
    @Override public Optional<Receipt> receipt(Actor a,String key) {
        var rows=db.rows("SELECT request_hash,response FROM personal_todo_commands WHERE company_id=? AND owner_id=? AND command_key=?",a.company(),a.id(),key);
        return rows.isEmpty()?Optional.empty():Optional.of(new Receipt(Db.str(rows.getFirst(),"request_hash"),db.read(rows.getFirst().get("response"))));
    }
    @Override public void saveReceipt(Actor a,String key,String hash,Object response) {
        db.update("INSERT INTO personal_todo_commands(company_id,owner_id,command_key,request_hash,response) VALUES (?,?,?,?,?::jsonb)",a.company(),a.id(),key,hash,db.write(response));
    }
    private static Instant instant(Object v) { return v==null?null:((Timestamp)v).toInstant(); }
    private static Todo todo(Map<String,Object> r) {
        return new Todo(Db.str(r,"id"),Db.str(r,"title"),Db.str(r,"note"),LocalDate.parse(r.get("business_date").toString()),LocalDate.parse(r.get("end_date").toString()),Db.str(r,"color"),(boolean)r.get("completed"),instant(r.get("completed_at")),((Number)r.get("version")).intValue(),instant(r.get("created_at")),instant(r.get("updated_at")));
    }
}
