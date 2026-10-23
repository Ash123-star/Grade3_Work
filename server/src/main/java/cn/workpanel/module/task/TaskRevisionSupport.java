package cn.workpanel.module.task;

import cn.workpanel.Actor;
import cn.workpanel.Db;
import java.util.*;

/** 任务通用修订（候选内容）的校验与生效，供现有 Reviews/Tasks 委托；复核流程本身不在本模块。 */
public final class TaskRevisionSupport {
    private TaskRevisionSupport() {}

    /** 申请阶段：规范化、参与人、附件（已绑定到本任务的保留）。返回规范化后的候选内容。 */
    public static Map<String,Object> validate(Db db,Actor a,String taskId,Map<String,Object> candidate) {
        a.requireDispatch(); TaskDraft d=TaskDraftNormalizer.normalize(candidate);
        TaskParticipants.validate(db,a,d); TaskLabels.validate(db,a,d);
        for(String id:d.attachments()) TaskAttachments.check(db,a,taskId,id,false);
        return new LinkedHashMap<>(d.body());
    }

    /** 生效阶段：替换参与人，绑定新附件。调用方负责更新 tasks 行与事件。 */
    public static TaskDraft apply(Db db,Actor applicant,String taskId,Map<String,Object> candidate) {
        applicant.requireDispatch(); TaskDraft d=TaskDraftNormalizer.normalize(candidate);
        TaskParticipants.validate(db,applicant,d); TaskLabels.validate(db,applicant,d);
        TaskParticipants.replace(db,applicant,taskId,d);
        TaskLabels.replace(db,applicant,taskId,d);
        TaskAttachments.bind(db,applicant,taskId,d.attachments(),true);
        return d;
    }
}
