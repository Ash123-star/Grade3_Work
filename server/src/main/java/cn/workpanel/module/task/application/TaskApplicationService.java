package cn.workpanel.module.task.application;

import cn.workpanel.module.task.api.TaskApi;
import cn.workpanel.shared.application.UseCase;

/** 任务用例服务边界；事务、幂等和跨模块事件编排应集中在实现中。 */
public interface TaskApplicationService extends TaskApi, UseCase { }
