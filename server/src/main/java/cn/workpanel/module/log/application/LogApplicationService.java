package cn.workpanel.module.log.application;

import cn.workpanel.module.log.api.LogApi;
import cn.workpanel.shared.application.UseCase;

/** 日志用例服务边界；修订、审核、通知通过应用层端口协作。 */
public interface LogApplicationService extends LogApi, UseCase { }
