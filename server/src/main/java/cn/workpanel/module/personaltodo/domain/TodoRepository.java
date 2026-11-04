package cn.workpanel.module.personaltodo.domain;

import cn.workpanel.Actor;
import cn.workpanel.module.personaltodo.api.TodoContracts.*;
import java.time.LocalDate;
import java.util.*;

/** Every operation is scoped to the current company AND owner, including receipts. */
public interface TodoRepository {
    Todo find(Actor actor,String id);
    Page page(Actor actor,LocalDate day,int cursor,int limit);
    List<DayCount> counts(Actor actor,LocalDate from,LocalDate to);
    Todo create(Actor actor,TodoDraft draft);
    Todo update(Actor actor,String id,TodoDraft draft);
    Deleted delete(Actor actor,String id,int version);
    void lockCommand(Actor actor,String key);
    Optional<Receipt> receipt(Actor actor,String key);
    void saveReceipt(Actor actor,String key,String hash,Object response);
    record Receipt(String hash,Map<String,Object> response) {}
}
