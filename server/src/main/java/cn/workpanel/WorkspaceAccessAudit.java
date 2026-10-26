package cn.workpanel;

import jakarta.servlet.http.HttpServletRequest;
import org.springframework.stereotype.Service;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/** 管理入口拒绝审计：匿名可记录，不保存凭据、查询参数、任意URL或正文。 */
@Service
public class WorkspaceAccessAudit {
    private static final Logger LOG=LoggerFactory.getLogger(WorkspaceAccessAudit.class);
    private final Db db;
    public WorkspaceAccessAudit(Db db) { this.db=db; }
    public void denied(HttpServletRequest request,int status) {
        if(!request.getRequestURI().startsWith("/api/admin/workspace/")||(status!=401&&status!=403)) return;
        Actor actor=(Actor)request.getAttribute("actor");
        String method=request.getMethod();
        if(!java.util.Set.of("GET","POST","PUT","DELETE","PATCH","HEAD","OPTIONS").contains(method)) method="OTHER";
        try {
            db.update("INSERT INTO workspace_access_audit(company_id,actor_id,method,endpoint,status,trace_id) VALUES (?,?,?,?,?,?)",
                actor==null?null:actor.company(),actor==null?null:actor.id(),method,"ADMIN_WORKSPACE",status,request.getAttribute("traceId"));
        } catch(RuntimeException failure) {
            // 不记录异常文本（驱动错误可能携带参数），原拒绝响应仍返回。
            LOG.error("管理入口拒绝审计写入失败 traceId={}",request.getAttribute("traceId"));
        }
    }
}
