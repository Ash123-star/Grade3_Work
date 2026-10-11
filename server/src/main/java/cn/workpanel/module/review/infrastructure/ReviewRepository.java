package cn.workpanel.module.review.infrastructure;

import cn.workpanel.Actor;
import cn.workpanel.Db;
import org.springframework.stereotype.Repository;
import java.util.Map;

/** 审核列表数据库范围：仅本公司本人申请或分配给本人的复核。 */
@Repository
public class ReviewRepository {
    private final Db db;
    public ReviewRepository(Db db) { this.db = db; }
    public Map<String, Object> list(Actor actor, int cursor, int limit) {
        String where = "company_id=? AND (applicant_id=? OR id IN (SELECT request_id FROM review_steps WHERE reviewer_id=?))";
        return Map.of("items", db.rows("SELECT id,kind,target_id,applicant_id,status,reason,created_at FROM review_requests WHERE " + where + " ORDER BY created_at DESC,id LIMIT ? OFFSET ?", actor.company(), actor.id(), actor.id(), limit, cursor),
            "total", db.count("SELECT count(*) FROM review_requests WHERE " + where, actor.company(), actor.id(), actor.id()), "nextCursor", String.valueOf((long) cursor + limit));
    }
}
