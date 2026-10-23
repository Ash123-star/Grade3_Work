package cn.workpanel.shared.application;

import cn.workpanel.*;
import org.springframework.stereotype.Component;
import org.springframework.transaction.support.TransactionSynchronizationManager;
import java.util.*;
import java.util.function.Supplier;

/** 调用者须开启业务事务：请求结果和业务副作用原子提交，统一防止同键不同内容。 */
@Component
public class CommandKeys {
    private final Db db;
    public CommandKeys(Db db) { this.db=db; }
    public Map<String,Object> execute(Actor a,String operation,String key,Object payload,Supplier<Map<String,Object>> action) {
        if(!TransactionSynchronizationManager.isActualTransactionActive()) throw new IllegalStateException("CommandKeys requires transaction");
        if(key==null||key.isBlank()||key.length()>128) throw ApiError.bad("IDEMPOTENCY_REQUIRED","需要有效的请求标识");
        db.one("SELECT pg_advisory_xact_lock(hashtextextended(?,0))",a.company()+":"+a.id()+":"+operation+":"+key);
        String hash=Db.hash(db.write(canonical(payload)));
        var previous=db.rows("SELECT request_hash,result FROM ai_request_keys WHERE company_id=? AND actor_id=? AND operation=? AND key=?",a.company(),a.id(),operation,key);
        if(!previous.isEmpty()) {
            if(!hash.equals(previous.getFirst().get("request_hash"))) throw new ApiError(409,"IDEMPOTENCY_CONFLICT","同一次请求内容已改变");
            return db.read(previous.getFirst().get("result"));
        }
        var result=action.get();
        db.update("INSERT INTO ai_request_keys(company_id,actor_id,operation,key,request_hash,result) VALUES (?,?,?,?,?,?::jsonb)",a.company(),a.id(),operation,key,hash,db.write(result));
        return result;
    }
    public static Object canonical(Object value) {
        if(value instanceof Map<?,?> map) { var result=new TreeMap<String,Object>();map.forEach((k,v)->result.put(k.toString(),canonical(v)));return result; }
        if(value instanceof List<?> list) return list.stream().map(CommandKeys::canonical).toList();
        return value;
    }
}
