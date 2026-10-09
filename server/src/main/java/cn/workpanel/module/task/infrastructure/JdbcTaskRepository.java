package cn.workpanel.module.task.infrastructure;

import cn.workpanel.module.task.domain.TaskRepository;
import org.springframework.stereotype.Repository;

/** 任务仓储适配器。当前任务查询由任务应用服务复用统一 Business 范围策略。 */
@Repository
public class JdbcTaskRepository implements TaskRepository {
    /** 未接入聚合读取时返回明确错误，禁止将空结果误报为成功。 */
    @Override public Object findById(String companyId, String taskId) {
        throw new UnsupportedOperationException("Task repository migration is not wired yet");
    }
}
