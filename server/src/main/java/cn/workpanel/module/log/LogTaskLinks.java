package cn.workpanel.module.log;

import cn.workpanel.*;
import java.util.Map;

/** 日报与任务关系的内部持久化工具；关联资格校验由工作流调用方负责。 */
public final class LogTaskLinks {
    private LogTaskLinks() {}
    /** 确认日报作者当前可读取全部引用任务；范围外资源统一按任务读取语义隐藏。 */
    public static void validate(Db db,Actor actor,Map<String,Object> body) {
        Business business=new Business(db);
        for(String taskId:Business.strings(body,"taskIds")) business.task(actor,taskId,false);
    }
    /** 校验成功后同步结构化关系；调用方须处于保存或审核事务内。 */
    public static void validateAndSync(Db db,Actor actor,String logId,Map<String,Object> body) {
        validate(db,actor,body); sync(db,actor.company(),logId,body);
    }
    public static void sync(Db db,String company,String logId,Map<String,Object> body) {
        db.update("DELETE FROM log_tasks WHERE company_id=? AND log_id=?",company,logId);
        for(String taskId:Business.strings(body,"taskIds")) db.update("INSERT INTO log_tasks(company_id,log_id,task_id) VALUES (?,?,?)",company,logId,taskId);
    }
}
