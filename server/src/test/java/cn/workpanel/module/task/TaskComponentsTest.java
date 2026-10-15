package cn.workpanel.module.task;

import cn.workpanel.Actor;
import cn.workpanel.ApiError;
import cn.workpanel.Db;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import java.util.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

/** TaskParticipants / TaskAttachments / TaskAccess 的分支，数据库以 Mockito 替身表示。 */
class TaskComponentsTest {
    static final Actor LEADER=new Actor("u-leader","c1","LEADER","d1","t1",true,false,false,"ACTIVE");
    static final Actor DIRECTOR=new Actor("u-dir","c1","DIRECTOR","d1","",true,false,false,"ACTIVE");
    static final Actor EMPLOYEE=new Actor("u-emp","c1","EMPLOYEE","d1","t1",false,false,false,"ACTIVE");
    static final Actor ADMIN=new Actor("u-admin","c1","ADMIN","","",true,false,false,"ACTIVE");

    static Map<String,Object> user(String id,String company,String dept,String team) { return new HashMap<>(Map.of("id",id,"company_id",company,"department_id",dept,"team_id",team)); }
    static TaskDraft draft(String owner,List<String> collaborators) { return new TaskDraft("t",owner,"2026-10-20T18:00+08:00","NORMAL",null,null,null,collaborators,List.of()); }
    static String code(Runnable r) { return assertThrows(ApiError.class,r::run).code; }

    // ---- 参与人 ----
    @Test void participantsInScopePass() {
        Db db=mock(Db.class);
        when(db.rows(startsWith("SELECT * FROM users"),eq("u-a"),eq("c1"))).thenReturn(List.of(user("u-a","c1","d1","t1")));
        when(db.rows(startsWith("SELECT * FROM users"),eq("u-b"),eq("c1"))).thenReturn(List.of(user("u-b","c1","d1","t1")));
        assertDoesNotThrow(()->TaskParticipants.validate(db,LEADER,draft("u-a",List.of("u-b"))));
    }

    @Test void participantOutsideTeamForbidden() {
        Db db=mock(Db.class);
        when(db.rows(startsWith("SELECT * FROM users"),eq("u-a"),eq("c1"))).thenReturn(List.of(user("u-a","c1","d1","t1")));
        when(db.rows(startsWith("SELECT * FROM users"),eq("u-x"),eq("c1"))).thenReturn(List.of(user("u-x","c1","d1","t2")));
        assertEquals("FORBIDDEN",code(()->TaskParticipants.validate(db,LEADER,draft("u-a",List.of("u-x")))));
    }

    @Test void inactiveOrOtherCompanyNotFound() {
        // 查询条件要求 company_id=? AND status='ACTIVE'，非在职或其他公司用户查不到
        Db db=mock(Db.class); when(db.rows(anyString(),any(Object[].class))).thenReturn(List.of());
        assertEquals("NOT_FOUND",code(()->TaskParticipants.validate(db,LEADER,draft("u-pending",List.of()))));
        verify(db).rows(contains("status='ACTIVE'"),eq("u-pending"),eq("c1"));
    }

    @Test void assignWritesPrimaryThenCollaborators() {
        Db db=mock(Db.class); when(db.write(any())).thenReturn("{}");
        TaskParticipants.assign(db,LEADER,"task1",draft("u-a",List.of("u-b","u-c")));
        verify(db).update(contains("'PRIMARY'"),eq("task1"),eq("u-a"),eq("c1"));
        verify(db).update(contains("'COLLABORATOR'"),eq("task1"),eq("u-b"),eq("c1"));
        verify(db).update(contains("'COLLABORATOR'"),eq("task1"),eq("u-c"),eq("c1"));
        verify(db,times(3)).notify(eq(LEADER),anyString(),eq("TASK_ASSIGNED"),eq("task1"),anyString());
    }

    // ---- 附件 ----
    static Db attachment(String owner,String task) {
        Db db=mock(Db.class); var row=new HashMap<String,Object>(); row.put("owner_id",owner); row.put("task_id",task);
        when(db.rows(startsWith("SELECT owner_id,task_id FROM attachments"),eq("f1"),eq("c1"))).thenReturn(List.of(row)); return db;
    }

    @Test void ownUnboundAttachmentBinds() {
        Db db=attachment("u-leader",null);
        TaskAttachments.bind(db,LEADER,"task1",List.of("f1"),false);
        verify(db).update(contains("UPDATE attachments SET task_id=?"),eq("task1"),eq("f1"));
    }

    @Test void othersAttachmentForbidden() {
        Db db=attachment("u-other",null);
        assertEquals("FORBIDDEN",code(()->TaskAttachments.bind(db,LEADER,"task1",List.of("f1"),false)));
        verify(db,never()).update(contains("UPDATE attachments"),any(Object[].class));
    }

    @Test void othersBoundAttachmentStillForbidden() {
        // 他人附件即使已绑定到当前读者可见的任务，也不能再引用
        assertEquals("FORBIDDEN",code(()->TaskAttachments.bind(attachment("u-other","task0"),LEADER,"task1",List.of("f1"),false)));
    }

    @Test void missingAttachmentNotFound() {
        Db db=mock(Db.class); when(db.rows(anyString(),any(Object[].class))).thenReturn(List.of());
        assertEquals("NOT_FOUND",code(()->TaskAttachments.bind(db,LEADER,"task1",List.of("f1"),false)));
    }

    @Test void boundElsewhereConflict() {
        assertEquals("ATTACHMENT_BOUND",code(()->TaskAttachments.bind(attachment("u-leader","task0"),LEADER,"task1",List.of("f1"),false)));
    }

    @Test void sameTaskKeptOnRevision() {
        Db db=attachment("u-leader","task1");
        TaskAttachments.bind(db,ADMIN,"task1",List.of("f1"),true);
        verify(db,never()).update(anyString(),any(Object[].class));
        assertEquals("ATTACHMENT_BOUND",code(()->TaskAttachments.bind(attachment("u-admin","task1"),ADMIN,"task1",List.of("f1"),false)));
    }

    // ---- 读取范围 ----
    @Test void scopeArgsPerRole() {
        assertEquals(List.of("c1","u-leader","t1","u-leader","u-leader"),TaskAccess.scope(LEADER).args());
        assertTrue(TaskAccess.scope(LEADER).sql().contains("u.team_id = ?"));
        assertEquals(List.of("c1","u-dir","d1","u-dir","u-dir"),TaskAccess.scope(DIRECTOR).args());
        assertTrue(TaskAccess.scope(DIRECTOR).sql().contains("u.department_id = ?"));
        assertEquals(List.of("c1","u-emp","u-emp","u-emp"),TaskAccess.scope(EMPLOYEE).args());
        assertEquals(List.of("c1","u-admin","u-admin"),TaskAccess.scope(ADMIN).args());
        for(Actor a:List.of(LEADER,DIRECTOR,EMPLOYEE,ADMIN)) {
            String sql=TaskAccess.scope(a).sql(); assertEquals(a.scopeArgs().length+3,sql.chars().filter(c->c=='?').count(),a.role());
            assertTrue(sql.startsWith("t.company_id=? AND ("),a.role());
        }
    }

    @Test void readableOutsideScopeNotFound() {
        Db db=mock(Db.class); when(db.rows(anyString(),any(Object[].class))).thenReturn(List.of());
        assertEquals("NOT_FOUND",code(()->TaskAccess.readable(db,EMPLOYEE,"task1",false)));
        var sql=ArgumentCaptor.forClass(String.class); verify(db).rows(sql.capture(),any(Object[].class));
        assertTrue(sql.getValue().endsWith("AND t.id=?")); assertFalse(sql.getValue().contains("FOR UPDATE"));
    }

    @Test void readableLocksWhenRequested() {
        Db db=mock(Db.class); when(db.rows(anyString(),any(Object[].class))).thenReturn(List.of(Map.of("id","task1")));
        assertEquals("task1",TaskAccess.readable(db,EMPLOYEE,"task1",true).get("id"));
        verify(db).rows(endsWith("FOR UPDATE"),any(Object[].class));
    }

    @Test void timelineOrderedBySequence() {
        Db db=mock(Db.class); TaskTimeline.list(db,"task1");
        verify(db).rows(endsWith("ORDER BY sequence"),eq("task1"));
    }
}
