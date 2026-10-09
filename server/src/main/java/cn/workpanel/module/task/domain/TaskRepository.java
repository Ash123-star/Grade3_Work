package cn.workpanel.module.task.domain;

import cn.workpanel.shared.infrastructure.RepositoryPort;

/** 任务领域仓储端口；领域层只依赖该抽象，不依赖 JDBC、SQL 或 Spring。 */
public interface TaskRepository extends RepositoryPort {
    /** 按任务标识读取聚合；实现必须再次校验 companyId。 */
    Object findById(String companyId, String taskId);
}
