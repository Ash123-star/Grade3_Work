package cn.workpanel.module.task;

import cn.workpanel.ApiError;
import cn.workpanel.Db;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import java.util.*;
import static org.junit.jupiter.api.Assertions.*;

class TaskDraftNormalizerTest {
    static final Db DB=new Db(null,new ObjectMapper());
    static final String DEADLINE="2026-10-20T18:00+08:00";

    static Map<String,Object> base() {
        var m=new LinkedHashMap<String,Object>(); m.put("title","整理周报"); m.put("ownerId","u-owner"); m.put("deadline",DEADLINE); return m;
    }
    static Map<String,Object> with(String k,Object v) { var m=base(); m.put(k,v); return m; }
    static String code(Map<String,Object> raw) { return assertThrows(ApiError.class,()->TaskDraftNormalizer.normalize(raw)).code; }

    @Test void defaultsAndDedup() {
        var raw=base(); raw.put("collaborators",List.of("u-b","u-a","u-owner","u-b")); raw.put("attachments",List.of("f2","f1","f2"));
        var d=TaskDraftNormalizer.normalize(raw);
        assertEquals("NORMAL",d.urgency()); assertEquals(List.of("u-a","u-b"),d.collaborators()); assertEquals(List.of("f1","f2"),d.attachments());
        assertNull(d.group()); assertFalse(d.body().containsKey("group"));
    }

    @Test void titleTrimmed() { assertEquals("整理周报",TaskDraftNormalizer.normalize(with("title","  整理周报 ")).title()); }

    @Test void serverManagedFieldsRejected() {
        for(String k:List.of("phase","version","status","completion","completed","progress","issuerId","id")) assertEquals("SERVER_MANAGED_FIELD",code(with(k,"ACCEPTED")),k);
    }

    @Test void unknownFieldRejected() { assertEquals("UNKNOWN_FIELD",code(with("color","red"))); }

    @Test void requiredFields() {
        for(String k:List.of("title","ownerId","deadline")) { var m=base(); m.remove(k); assertEquals("INVALID_FIELD",code(m),k); }
        assertEquals("INVALID_FIELD",code(with("title","   ")));
    }

    @Test void lengthsAndDates() {
        assertEquals("TITLE_LENGTH",code(with("title","x".repeat(201))));
        assertEquals("INVALID_FIELD",code(with("content","x".repeat(20001))));
        assertEquals("INVALID_FIELD",code(with("group",3)));
        assertEquals("INVALID_DATE",code(with("deadline","2026-10-20T18:00")));
        assertEquals("INVALID_DATE",code(with("deadline","明天")));
        assertEquals("INVALID_URGENCY",code(with("urgency","HIGH")));
        assertEquals("INVALID_URGENCY",code(with("urgency",1)));
    }

    @Test void referenceLists() {
        assertEquals("INVALID_LIST",code(with("collaborators","u-a")));
        assertEquals("INVALID_LIST",code(with("attachments",List.of(1))));
        assertEquals("INVALID_LIST",code(with("attachments",List.of(" "))));
        var many=new ArrayList<String>(); for(int i=0;i<101;i++) many.add("f"+i);
        assertEquals("INVALID_LIST",code(with("attachments",many)));
        many.removeLast(); assertEquals(100,TaskDraftNormalizer.normalize(with("attachments",many)).attachments().size());
    }

    @Test void hashIgnoresOrderAndDuplicates() {
        var a=base(); a.put("collaborators",List.of("u-a","u-b")); a.put("attachments",List.of("f1","f2"));
        var b=base(); b.put("collaborators",List.of("u-b","u-owner","u-a","u-a")); b.put("attachments",List.of("f2","f1")); b.put("urgency","NORMAL");
        assertEquals(TaskDraftNormalizer.hash(DB,TaskDraftNormalizer.normalize(a)),TaskDraftNormalizer.hash(DB,TaskDraftNormalizer.normalize(b)));
    }

    @Test void hashChangesWithContent() {
        String h=TaskDraftNormalizer.hash(DB,TaskDraftNormalizer.normalize(base()));
        assertNotEquals(h,TaskDraftNormalizer.hash(DB,TaskDraftNormalizer.normalize(with("title","另一个任务"))));
        assertNotEquals(h,TaskDraftNormalizer.hash(DB,TaskDraftNormalizer.normalize(with("ownerId","u-other"))));
        assertNotEquals(h,TaskDraftNormalizer.hash(DB,TaskDraftNormalizer.normalize(with("collaborators",List.of("u-a")))));
    }

    @Test void legacyHashMatchesPreV4Algorithm() {
        // V4 之前 Tasks.create：putIfAbsent urgency 后 Db.hash(write(new TreeMap<>(c)))
        var raw=base(); raw.put("collaborators",List.of("u-b","u-a"));
        var c=new LinkedHashMap<>(raw); c.putIfAbsent("urgency","NORMAL");
        assertEquals(Db.hash(DB.write(new TreeMap<>(c))),TaskDraftNormalizer.legacyHash(DB,raw));
        var reordered=base(); reordered.put("collaborators",List.of("u-a","u-b"));
        assertNotEquals(TaskDraftNormalizer.legacyHash(DB,raw),TaskDraftNormalizer.legacyHash(DB,reordered));
    }
}
