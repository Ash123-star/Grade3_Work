package cn.workpanel.module.task;

import cn.workpanel.Actor;
import cn.workpanel.ApiError;
import cn.workpanel.Db;
import java.util.*;

/** 附件引用：只能引用本人上传且未绑定的附件；修订时已绑定到同一任务的附件保留。 */
public final class TaskAttachments {
    private TaskAttachments() {}

    /** 只校验不写入；修订申请阶段使用。taskId 为 null 表示新派发。 */
    public static void verify(Db db,Actor a,String taskId,List<String> ids) { for(String id:ids) check(db,a,taskId,id,false); }

    /** 锁定、校验并绑定；sameTaskAllowed 时已绑定到 taskId 的附件原样保留。 */
    public static void bind(Db db,Actor a,String taskId,List<String> ids,boolean sameTaskAllowed) {
        for(String id:ids) if(check(db,a,sameTaskAllowed?taskId:null,id,true)) db.update("UPDATE attachments SET task_id=? WHERE id=? AND task_id IS NULL",taskId,id);
    }

    /** 返回 true 表示需要绑定，false 表示已绑定到同一任务。 */
    static boolean check(Db db,Actor a,String sameTask,String id,boolean lock) {
        var rows=db.rows("SELECT owner_id,task_id FROM attachments WHERE id=? AND company_id=?"+(lock?" FOR UPDATE":""),id,a.company());
        if(rows.isEmpty()) throw ApiError.notFound();
        var f=rows.getFirst(); String bound=Db.str(f,"task_id");
        if(sameTask!=null&&sameTask.equals(bound)) return false;
        if(!a.id().equals(Db.str(f,"owner_id"))) throw ApiError.forbidden();
        if(!bound.isEmpty()) throw new ApiError(409,"ATTACHMENT_BOUND","附件已关联其他任务");
        return true;
    }
}
