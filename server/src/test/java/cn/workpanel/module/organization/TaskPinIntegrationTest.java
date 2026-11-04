package cn.workpanel.module.organization;

import com.fasterxml.jackson.databind.JsonNode;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import java.time.*;
import java.util.*;
import static org.junit.jupiter.api.Assertions.*;

/** 个人任务置顶：权限、上限、幂等、个人隔离、排序跨页一致且不改变任务版本。 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = {
    "app.admin-account=integration-admin", "app.admin-password=Initial-test-password-2026", "app.admin-phone=13900000001"
})
class TaskPinIntegrationTest extends MemberBHttpSupport {
    /** 以 leader 为派发人、employee 和 colleague 为参与人；截止时间按序号递增。 */
    String task(int order) {
        String id = cn.workpanel.Db.id();
        var deadline = java.sql.Timestamp.from(Instant.parse("2026-12-01T00:00:00Z").plus(Duration.ofHours(order)));
        db.update("INSERT INTO tasks(id,company_id,owner_id,issuer_id,title,deadline,body) VALUES (?,?,?,?,?,?,'{}'::jsonb)", id, company, employee, leader, "置顶任务" + order, deadline);
        db.update("INSERT INTO task_participants(task_id,user_id,company_id) VALUES (?,?,?),(?,?,?)", id, employee, company, id, colleague, company);
        return id;
    }
    List<String> ids(JsonNode page) { var out = new ArrayList<String>(); for (var item : page.get("items")) out.add(item.get("id").asText()); return out; }

    @Test void pinIsPersonalOrderedIdempotentAndKeepsVersion() throws Exception {
        String first = task(1), second = task(2), third = task(3);
        int version = ((Number) db.one("SELECT version FROM tasks WHERE id=?", third).get("version")).intValue();
        assertEquals(List.of(first, second, third), ids(call(200, "GET", "/tasks?limit=10", employee, null)));

        var pinned = call(200, "PUT", "/tasks/" + third + "/pin", employee, null);
        assertTrue(pinned.get("pinned").asBoolean());
        String pinnedAt = pinned.get("pinnedAt").asText();
        assertEquals(pinnedAt, call(200, "PUT", "/tasks/" + third + "/pin", employee, null).get("pinnedAt").asText());
        Thread.sleep(5);
        call(200, "PUT", "/tasks/" + second + "/pin", employee, null);

        var page = call(200, "GET", "/tasks?limit=10", employee, null);
        assertEquals(List.of(second, third, first), ids(page));
        assertTrue(page.get("items").get(0).get("pinned").asBoolean());
        assertFalse(page.get("items").get(2).get("pinned").asBoolean());
        // 分页：置顶排序跨页一致。
        assertEquals(List.of(second), ids(call(200, "GET", "/tasks?limit=1&cursor=0", employee, null)));
        assertEquals(List.of(third), ids(call(200, "GET", "/tasks?limit=1&cursor=1", employee, null)));
        // 个人隔离：同样可见的 colleague 排序不变。
        assertEquals(List.of(first, second, third), ids(call(200, "GET", "/tasks?limit=10", colleague, null)));
        assertEquals(version, ((Number) db.one("SELECT version FROM tasks WHERE id=?", third).get("version")).intValue());
        assertEquals(0, db.count("SELECT count(*) FROM review_requests WHERE target_id=?", third));
        assertTrue(call(200, "GET", "/tasks/" + third, employee, null).get("pinned").asBoolean());
        assertFalse(call(200, "GET", "/tasks/" + third, colleague, null).get("pinned").asBoolean());

        assertFalse(call(200, "DELETE", "/tasks/" + third + "/pin", employee, null).get("pinned").asBoolean());
        call(200, "DELETE", "/tasks/" + third + "/pin", employee, null);
        assertEquals(List.of(second, first, third), ids(call(200, "GET", "/tasks?limit=10", employee, null)));
    }

    @Test void invisibleTaskCannotBePinnedAndLimitIsEnforced() throws Exception {
        String visible = task(0);
        call(404, "PUT", "/tasks/" + visible + "/pin", outside, null);
        call(404, "PUT", "/tasks/" + visible + "/pin", foreign, null);
        call(404, "PUT", "/tasks/missing/pin", employee, null);
        assertEquals(0, db.count("SELECT count(*) FROM task_pins WHERE task_id=?", visible));

        for (int i = 1; i <= 10; i++) call(200, "PUT", "/tasks/" + task(i) + "/pin", employee, null);
        String extra = task(11);
        assertEquals("PIN_LIMIT", call(409, "PUT", "/tasks/" + extra + "/pin", employee, null).get("code").asText());
        assertEquals(10, db.count("SELECT count(*) FROM task_pins WHERE user_id=?", employee));
    }
}
