package cn.workpanel.module.attachment.api;

import cn.workpanel.contract.ActorContext;
import java.util.Map;

/** 附件端口；不向客户端暴露公开静态文件路径。 */
public interface AttachmentApi {
    /** 保存受控附件并返回附件标识；实现负责大小和文件名校验。 */
    Map<String, Object> upload(ActorContext actor, Object file);

    /** 下载附件前重新检查所有者、头像或任务参与范围。 */
    byte[] download(ActorContext actor, String attachmentId);
}
