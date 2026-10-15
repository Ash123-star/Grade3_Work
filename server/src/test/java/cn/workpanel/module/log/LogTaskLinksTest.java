package cn.workpanel.module.log;

import cn.workpanel.*;
import org.junit.jupiter.api.*;
import java.util.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

/** 任务关联写入必须以日报作者的任务读取范围为前提。 */
class LogTaskLinksTest {
    static final Actor ALICE=new Actor("alice","c1","EMPLOYEE","d1","t1",false,false,false,"ACTIVE");
    Db db;
    @BeforeEach void setUp() { db=mock(Db.class); }

    @Test void visibleDuplicateTaskIdsProduceOneLink() {
        when(db.rows(startsWith("SELECT t.* FROM tasks t"),any(Object[].class))).thenReturn(List.of(Map.of("id","task-1")));
        LogTaskLinks.validateAndSync(db,ALICE,"log-1",Map.of("taskIds",List.of("task-1","task-1")));
        verify(db).update(startsWith("DELETE FROM log_tasks"),eq("c1"),eq("log-1"));
        verify(db,times(1)).update(startsWith("INSERT INTO log_tasks"),eq("c1"),eq("log-1"),eq("task-1"));
    }

    @Test void hiddenTaskRejectsBeforeDeletingExistingLinks() {
        when(db.rows(startsWith("SELECT t.* FROM tasks t"),any(Object[].class))).thenReturn(List.of());
        assertThrows(ApiError.class,()->LogTaskLinks.validateAndSync(db,ALICE,"log-1",Map.of("taskIds",List.of("outside-task"))));
        verify(db,never()).update(startsWith("DELETE FROM log_tasks"),any(Object[].class));
        verify(db,never()).update(startsWith("INSERT INTO log_tasks"),any(Object[].class));
    }
}
