package cn.workpanel.module.push.infrastructure;

import cn.workpanel.module.push.application.PushGateway;
import com.aliyuncs.DefaultAcsClient;
import com.aliyuncs.profile.DefaultProfile;
import com.aliyuncs.push.model.v20160801.PushRequest;
import com.aliyuncs.exceptions.ClientException;
import com.aliyuncs.http.ProtocolType;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import java.time.Instant;
import java.util.*;

/** Official RPC client signs requests. RAM/STS stays server-side; no raw provider errors escape. */
@Component
public class AliyunPushGateway implements PushGateway {
    final DefaultAcsClient client; final long appKey; final ObjectMapper json;
    final String huawei,huaweiCategory,xiaomi,oppo,vivo,honor;
    public AliyunPushGateway(ObjectMapper json,
            @Value("${app.push.app-key:0}") long appKey,
            @Value("${app.push.access-key-id:}") String id,
            @Value("${app.push.access-key-secret:}") String secret,
            @Value("${app.push.security-token:}") String token,
            @Value("${app.push.huawei-channel:NORMAL}") String huawei,
            @Value("${app.push.huawei-category:WORK}") String huaweiCategory,
            @Value("${app.push.xiaomi-channel:}") String xiaomi,
            @Value("${app.push.oppo-category:}") String oppo,
            @Value("${app.push.vivo-channel:}") String vivo,
            @Value("${app.push.honor-channel:}") String honor) {
        this.json=json;this.appKey=appKey;this.huawei=huawei;this.huaweiCategory=huaweiCategory;this.xiaomi=xiaomi;this.oppo=oppo;this.vivo=vivo;this.honor=honor;
        this.client=appKey>0&&!id.isBlank()&&!secret.isBlank()?new DefaultAcsClient(token.isBlank()?DefaultProfile.getProfile("cn-hangzhou",id,secret):DefaultProfile.getProfile("cn-hangzhou",id,secret,token)):null;
        if(client!=null) {client.setAutoRetry(false);client.setMaxRetryNumber(0);}
    }
    @Override public boolean configured() { return client!=null; }
    public PushRequest request(String device,String notification,String binding,String category,String title,Instant expires) throws Exception {
        var r=new PushRequest();r.setSysProductDomain(new com.aliyuncs.regions.ProductDomain("Push","cloudpush.aliyuncs.com"));r.setSysProtocol(ProtocolType.HTTPS);
        r.setSysConnectTimeout(3000);r.setSysReadTimeout(5000);
        r.setAppKey(appKey);r.setTarget("DEVICE");r.setTargetValue(device);r.setDeviceType("ANDROID");r.setPushType("NOTICE");
        r.setTitle("潘多拉工作台");r.setBody(title);r.setStoreOffline(true);r.setExpireTime(expires.truncatedTo(java.time.temporal.ChronoUnit.SECONDS).toString());
        r.setAndroidNotificationChannel("pandora_"+category);r.setAndroidNotificationGroup("pandora_"+category);
        r.setAndroidNotificationNotifyId(Objects.hash(notification,binding)&0x7fffffff);
        r.setAndroidOpenType("APPLICATION");r.setAndroidRemind(true);
        r.setAndroidPopupActivity("cn.pandora.pandora_mobile.PushPopupActivity");r.setAndroidPopupTitle("潘多拉工作台");r.setAndroidPopupBody(title);
        r.setAndroidExtParameters(json.writeValueAsString(Map.of("notificationId",notification,"binding",binding)));
        if(!huawei.isBlank()) r.setAndroidNotificationHuaweiChannel(huawei);
        // Huawei classification and message importance are independent provider fields.
        if(!huaweiCategory.isBlank()) r.setAndroidMessageHuaweiCategory(huaweiCategory);
        if(!xiaomi.isBlank()) r.setAndroidNotificationXiaomiChannel(xiaomi);
        if(!vivo.isBlank()) r.setAndroidNotificationVivoChannel(vivo);
        if(!oppo.isBlank()) r.setAndroidMessageOppoCategory(oppo);
        if(!honor.isBlank()) r.setAndroidNotificationHonorChannel(honor);
        return r;
    }
    @Override public String send(String device,String notification,String binding,String category,String title,Instant expires) throws Failure {
        if(client==null) throw new Failure("NOT_CONFIGURED",false);
        try {
            String id=client.getAcsResponse(request(device,notification,binding,category,title,expires)).getMessageId();
            if(id==null||id.isBlank()) throw new Failure("INVALID_RESPONSE",true);
            return id;
        } catch(Failure e) { throw e; }
        catch(ClientException e) {
            String code=e.getErrCode()==null?"PROVIDER_ERROR":e.getErrCode().replaceAll("[^A-Za-z0-9_.-]","");
            if(code.length()>80) code="PROVIDER_ERROR";
            boolean retry=code.startsWith("Throttl")||Set.of("SDK.ServerUnreachable","SDK.ReadTimeout","SDK.ConnectTimeout","InternalError","ServiceUnavailable").contains(code);
            throw new Failure(code,retry);
        } catch(Exception e) { throw new Failure("PROVIDER_FAILURE",true); }
    }
    @jakarta.annotation.PreDestroy public void close() { if(client!=null) client.shutdown(); }
}
