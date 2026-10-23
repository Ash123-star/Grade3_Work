package cn.workpanel.module.aiwork.application;

import cn.workpanel.*;
import org.springframework.stereotype.Component;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.transaction.annotation.Transactional;

/** 按用途清理私有材料；正式任务、制度和交付引用始终保留，删除标记优先于后台工作。 */
@Component
public class WorkRetention {
    private final Db db;
    public WorkRetention(Db db){this.db=db;}
    @Scheduled(fixedDelay=3600000,initialDelay=3600000)@Transactional public void clean(){
        // 与执行提交同样先锁事项、再锁步骤，避免清理和在途执行互相覆盖。
        db.rows("SELECT id FROM ai_work_items WHERE deleted_at IS NOT NULL OR updated_at<now()-interval '90 days' ORDER BY id FOR UPDATE");
        db.update("DELETE FROM ai_file_extractions WHERE expires_at<now() OR EXISTS(SELECT 1 FROM attachments f WHERE f.id=ai_file_extractions.attachment_id AND octet_length(f.data)=0)");
        db.update("UPDATE ai_work_steps s SET state='CANCELLED',fence=fence+1,lease_until=NULL FROM ai_work_items w WHERE s.company_id=w.company_id AND s.work_id=w.id AND (w.deleted_at IS NOT NULL OR w.updated_at<now()-interval '90 days') AND s.state IN ('PENDING','WAITING','RUNNING','FAILED')");
        db.update("UPDATE ai_work_items SET deleted_at=coalesce(deleted_at,now()),state='CANCELLED' WHERE updated_at<now()-interval '90 days' AND deleted_at IS NULL");
        db.update("UPDATE ai_work_items SET title='已删除事项',result='{}'::jsonb,error_code=NULL WHERE deleted_at IS NOT NULL AND (title<>'已删除事项' OR result<>'{}'::jsonb OR error_code IS NOT NULL)");
        db.update("DELETE FROM ai_work_messages m USING ai_work_items w WHERE m.company_id=w.company_id AND m.work_id=w.id AND w.deleted_at IS NOT NULL");
        db.update("DELETE FROM ai_work_confirmations c USING ai_work_items w WHERE c.company_id=w.company_id AND c.work_id=w.id AND w.deleted_at IS NOT NULL");
        db.update("DELETE FROM ai_work_plans p USING ai_work_items w WHERE p.company_id=w.company_id AND p.work_id=w.id AND w.deleted_at IS NOT NULL");
        db.update("UPDATE ai_work_steps s SET payload='{}',result='{}' FROM ai_work_items w WHERE s.company_id=w.company_id AND s.work_id=w.id AND w.deleted_at IS NOT NULL");
        db.update("DELETE FROM ai_file_extractions x USING attachment_bindings b,ai_work_items w WHERE x.company_id=b.company_id AND x.attachment_id=b.attachment_id AND b.resource_type='WORK' AND w.company_id=b.company_id AND w.id=b.resource_id AND w.deleted_at IS NOT NULL");
        db.update("UPDATE attachments f SET data=''::bytea,expires_at=now() WHERE octet_length(f.data)>0 AND f.task_id IS NULL AND EXISTS(SELECT 1 FROM attachment_bindings b JOIN ai_work_items w ON w.company_id=b.company_id AND w.id=b.resource_id WHERE b.attachment_id=f.id AND b.company_id=f.company_id AND b.resource_type='WORK' AND (w.deleted_at IS NOT NULL OR w.state IN ('SUCCEEDED','CANCELLED') AND w.updated_at<now()-interval '30 days')) AND NOT EXISTS(SELECT 1 FROM attachment_bindings b WHERE b.attachment_id=f.id AND b.company_id=f.company_id AND b.resource_type IN ('DELIVERY','PROCEDURE')) AND NOT EXISTS(SELECT 1 FROM users u WHERE u.company_id=f.company_id AND u.profile->>'avatarAttachmentId'=f.id) AND NOT EXISTS(SELECT 1 FROM attachment_bindings b JOIN ai_work_items w ON w.company_id=b.company_id AND w.id=b.resource_id WHERE b.attachment_id=f.id AND b.company_id=f.company_id AND b.resource_type='WORK' AND w.deleted_at IS NULL AND (w.state NOT IN ('SUCCEEDED','CANCELLED') OR w.updated_at>=now()-interval '30 days'))");
        // 只清理未用于正式交付的私人报告；正式交付证据与幂等回执继续保留。
        db.update("DELETE FROM task_delivery_check_jobs j WHERE j.created_at<now()-interval '90 days' AND (j.report_id IS NULL OR NOT EXISTS(SELECT 1 FROM task_deliveries d WHERE d.company_id=j.company_id AND d.check_id=j.report_id))");
        db.update("DELETE FROM task_delivery_findings f USING task_delivery_checks c WHERE f.company_id=c.company_id AND f.check_id=c.id AND c.created_at<now()-interval '90 days' AND NOT EXISTS(SELECT 1 FROM task_deliveries d WHERE d.company_id=c.company_id AND d.check_id=c.id) AND NOT EXISTS(SELECT 1 FROM task_delivery_check_jobs j WHERE j.company_id=c.company_id AND j.report_id=c.id)");
        db.update("DELETE FROM task_delivery_checks c WHERE c.created_at<now()-interval '90 days' AND NOT EXISTS(SELECT 1 FROM task_deliveries d WHERE d.company_id=c.company_id AND d.check_id=c.id) AND NOT EXISTS(SELECT 1 FROM task_delivery_check_jobs j WHERE j.company_id=c.company_id AND j.report_id=c.id)");
        db.update("UPDATE ai_action_receipts SET result=result-'report' WHERE created_at<now()-interval '90 days' AND jsonb_exists(result,'report')");
        // 保留谁在何时对哪个对象做了什么，不无限保留授权范围/操作原因原文。
        db.update("UPDATE audit_records SET before_value='{}'::jsonb,after_value='{}'::jsonb,reason='已按保留策略清理详情' WHERE type IN ('AI_WORK_ACTION','AI_WORK_AUTHORIZATION','AI_WORK_AUTHORIZATION_REVOKED') AND created_at<now()-interval '365 days' AND (before_value<>'{}'::jsonb OR after_value<>'{}'::jsonb OR reason<>'已按保留策略清理详情')");
    }
}
