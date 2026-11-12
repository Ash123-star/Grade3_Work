package cn.workpanel.module.push.controller;

import cn.workpanel.*;
import cn.workpanel.module.push.application.PushService;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.web.bind.annotation.*;
import java.util.Map;

@RestController @RequestMapping("/api/push")
public class PushController {
    private final PushService service;
    public PushController(PushService service) { this.service=service; }
    /** v1本人偏好及配置状态；PENDING可用但无公司业务数据。无版本/幂等要求，401/403鉴权失败。 */
    @GetMapping("/preferences") public Map<String,Object> getPushPreferences(HttpServletRequest r) { return service.preferences(Actor.current(r)); }
    /** v1本人全量偏好，version乐观锁；重复旧版本409，非法字段400，不接受收件人/公司参数。 */
    @PutMapping("/preferences") public Map<String,Object> updatePushPreferences(HttpServletRequest r,@RequestBody Map<String,Object> body) { return service.preferences(Actor.current(r),body); }
    /** v1当前会话绑定SDK deviceId，幂等续租；换账号生成新binding，取消旧投递。非法400、未配置409。 */
    @PutMapping("/device") public Map<String,Object> bindPushDevice(HttpServletRequest r,@RequestBody Map<String,Object> body) { return service.bind(Actor.current(r),r.getHeader("Authorization"),body); }
    /** v1本人当前会话设备解绑；body含deviceId，幂等，不影响其他账号或会话。 */
    @DeleteMapping("/device") public Map<String,Object> unbindPushDevice(HttpServletRequest r,@RequestBody Map<String,Object> body) { return service.unbind(Actor.current(r),r.getHeader("Authorization"),body); }
    /** v1通知点击解析；binding和deviceId必须匹配当前会话；重新校验当前对象及任务/审批有效性。不存在/越权/失效404；不接受任意URL，不会扩大权限。 */
    @GetMapping("/open/{id}") public Map<String,Object> openPushNotification(HttpServletRequest r,@PathVariable String id,@RequestParam String deviceId,@RequestParam String binding) { return service.open(Actor.current(r),r.getHeader("Authorization"),id,deviceId,binding); }
}
