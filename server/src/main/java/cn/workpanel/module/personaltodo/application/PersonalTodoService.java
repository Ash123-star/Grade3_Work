package cn.workpanel.module.personaltodo.application;

import cn.workpanel.*;
import cn.workpanel.module.personaltodo.api.TodoContracts.*;
import cn.workpanel.module.personaltodo.domain.*;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.*;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.time.*;
import java.time.temporal.TemporalAdjusters;
import java.util.*;
import java.util.function.Supplier;

/** Private use cases: scoped reads, transactional commands, bounded replay and version checks. */
@Service
public class PersonalTodoService {
    private final TodoRepository repo;
    private final ObjectMapper json;
    public PersonalTodoService(TodoRepository repo,ObjectMapper json) { this.repo=repo;this.json=json; }
    private void allowed(Actor a) { if(!a.status().equals("ACTIVE")||a.mustChange()) throw ApiError.forbidden(); }
    @Transactional(readOnly=true,isolation=Isolation.REPEATABLE_READ)
    public Page list(Actor a,String date,int cursor,int limit) {
        allowed(a);Business.page(cursor,limit);return repo.page(a,TodoDraft.date(date),cursor,limit);
    }
    @Transactional(readOnly=true)
    public Todo detail(Actor a,String id) { allowed(a);return repo.find(a,id); }
    @Transactional(readOnly=true)
    public cn.workpanel.module.personaltodo.api.TodoContracts.Calendar calendar(Actor a,String month) {
        allowed(a);YearMonth m=TodoDraft.month(month);
        LocalDate from=m.atDay(1).with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY));
        LocalDate to=m.atEndOfMonth().with(TemporalAdjusters.nextOrSame(DayOfWeek.SUNDAY)).plusDays(1);
        var found=new HashMap<LocalDate,DayCount>();repo.counts(a,from,to).forEach(d->found.put(d.date(),d));
        var days=from.datesUntil(to).map(d->found.getOrDefault(d,new DayCount(d,0,0))).toList();
        return new cn.workpanel.module.personaltodo.api.TodoContracts.Calendar(m.toString(),from,to,days);
    }
    @Transactional public Todo create(Actor a,TodoDraft d,String key) {
        return command(a,key,List.of("POST",d),Todo.class,()->repo.create(a,d));
    }
    @Transactional public Todo update(Actor a,String id,TodoDraft d,String key) {
        return command(a,key,List.of("PUT",id,d),Todo.class,()->repo.update(a,id,d));
    }
    @Transactional public Deleted delete(Actor a,String id,int version,String key) {
        if(version<1) throw ApiError.bad("INVALID_VERSION","version 必须为正整数");
        return command(a,key,List.of("DELETE",id,version),Deleted.class,()->repo.delete(a,id,version));
    }
    private <T> T command(Actor a,String key,Object payload,Class<T> type,Supplier<T> operation) {
        allowed(a);
        if(key==null||!key.matches("[A-Za-z0-9:_.-]{1,128}")) throw ApiError.bad("INVALID_IDEMPOTENCY_KEY","需要1–128位Idempotency-Key");
        String hash;
        try { hash=Db.hash(json.writeValueAsString(payload)); } catch(Exception e) { throw new IllegalStateException(e); }
        repo.lockCommand(a,key);
        var receipt=repo.receipt(a,key);
        if(receipt.isPresent()) {
            if(!receipt.get().hash().equals(hash)) throw new ApiError(409,"IDEMPOTENCY_CONFLICT","此幂等键已用于不同内容");
            return json.convertValue(receipt.get().response(),type);
        }
        T result=operation.get();repo.saveReceipt(a,key,hash,result);return result;
    }
}
