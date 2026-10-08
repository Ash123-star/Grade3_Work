package cn.workpanel;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;
import org.postgresql.util.PGobject;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.*;

@Component
public class Db {
    final JdbcTemplate jdbc;
    final ObjectMapper json;
    public Db(JdbcTemplate jdbc, ObjectMapper json) { this.jdbc=jdbc; this.json=json; }
    public int update(String sql, Object... args) { return jdbc.update(sql,args); }
    public List<Map<String,Object>> rows(String sql, Object... args) {
        var rows=jdbc.queryForList(sql,args);
        for(var row:rows) for(var entry:row.entrySet()) if(entry.getValue() instanceof PGobject pg) entry.setValue(Set.of("json","jsonb").contains(pg.getType())?read(pg):pg.getValue());
        return rows;
    }
    public Map<String,Object> one(String sql, Object... args) {
        var rows=rows(sql,args); if(rows.isEmpty()) throw ApiError.notFound(); return rows.getFirst();
    }
    public long count(String sql, Object... args) { return jdbc.queryForObject(sql,Long.class,args); }
    public String write(Object o) { try { return json.writeValueAsString(o); } catch(Exception e) { throw new IllegalArgumentException("JSON",e); } }
    public Map<String,Object> read(Object o) { try { if(o instanceof Map<?,?>) return json.convertValue(o,new TypeReference<>(){}); return json.readValue(o.toString(),new TypeReference<>(){}); } catch(Exception e) { throw new IllegalArgumentException("JSON",e); } }
    public static String id() { return UUID.randomUUID().toString(); }
    public static String hash(String s) { try { return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(s.getBytes(StandardCharsets.UTF_8))); } catch(Exception e) { throw new IllegalStateException(e); } }
    public static String str(Map<String,?> m,String key) { Object o=m.get(key); return o==null?"":o.toString(); }
    public static String required(Map<String,?> m,String key) { if(!(m.get(key) instanceof String value)) throw ApiError.bad("INVALID_FIELD","需要文本字段: "+key); String s=value.trim(); if(s.isEmpty()||s.length()>20000) throw ApiError.bad("INVALID_FIELD","字段无效: "+key); return s; }
    public static int version(Map<String,?> m) { try { String value=str(m,"version"); if(!value.matches("[0-9]+")) throw new NumberFormatException(); return Integer.parseInt(value); } catch(NumberFormatException e) { throw ApiError.bad("INVALID_VERSION","需要有效 version"); } }
    public static void fields(Map<String,?> m,String... allowed) { var set=Set.of(allowed); for(String key:m.keySet()) if(!set.contains(key)) throw ApiError.bad("UNKNOWN_FIELD","未知字段: "+key); }
    public static void conflict(int affected) { if(affected!=1) throw ApiError.conflict(); }
    public void audit(Actor a,String type,String id,Object before,Object after,String reason) { update("INSERT INTO audit_records(company_id,actor_id,type,object_id,before_value,after_value,reason) VALUES (?,?,?,?,?::jsonb,?::jsonb,?)",a.company(),a.id(),type,id,write(before),write(after),reason); }
    public void notify(Actor a,String recipient,String type,String object,String key) { update("INSERT INTO outbox_events(id,company_id,recipient_id,type,object_id,body,dedup_key) VALUES (?,?,?,?,?,'{}',?) ON CONFLICT(dedup_key) DO NOTHING",id(),a.company(),recipient,type,object,key); }
}
