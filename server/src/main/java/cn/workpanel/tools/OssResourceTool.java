package cn.workpanel.tools;

import cn.workpanel.*;
import cn.workpanel.module.attachment.application.*;
import cn.workpanel.module.attachment.infrastructure.*;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.*;
import org.springframework.transaction.support.TransactionTemplate;
import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.net.*;
import java.net.http.*;
import java.util.*;

/** 仅本机/部署运维执行，凭据取环境变量；不启动业务服务器和定时任务。 */
public final class OssResourceTool {
    public static void main(String[] args)throws Exception{
        if(args.length<2)throw new IllegalArgumentException("command root [release] [apply] [backup-file]");
        String command=args[0],release=args.length>2?args[2]:"local";Path root=Path.of(args[1]).toRealPath();boolean apply=args.length>3&&args[3].equals("apply");
        var mapper=new ObjectMapper();
        if(command.equals("inventory")){System.out.println(mapper.writeValueAsString(AssetPublisher.inventory(root,release)));return;}
        var settings=new OssSettings(env("OSS_BUCKET","panduola-work"),env("OSS_REGION","cn-beijing"),env("OSS_ENDPOINT","https://oss-cn-beijing.aliyuncs.com"),env("OSS_PREFIX","workpanel"),env("OSS_ACCESS_KEY_ID",""),env("OSS_ACCESS_KEY_SECRET",""),env("OSS_SECURITY_TOKEN",""),env("OSS_ROLE_NAME",""));
        // SDK默认WARN包含供应商诊断；此工具只报告白名单错误码。
        java.util.logging.Logger.getLogger("com.aliyun.oss").setLevel(java.util.logging.Level.OFF);
        try(var storage=new AliyunObjectStorage(settings)){
            if(command.equals("probe")){probe(storage,settings);return;}
            var source=new DriverManagerDataSource(env("DB_URL","jdbc:postgresql://127.0.0.1:55435/workpanel"),env("DB_USER","workpanel"),env("DB_PASSWORD",""));
            var db=new Db(new JdbcTemplate(source),mapper);var tx=new TransactionTemplate(new DataSourceTransactionManager(source));
            Object result;
            if(command.equals("publish")){var manifest=AssetPublisher.inventory(root,release);if(apply)new AssetPublisher(db,storage,tx).publish(root,manifest);result=Map.of("command",command,"apply",apply,"release",release,"count",manifest.get("count"),"bytes",manifest.get("bytes"));}
            else if(Set.of("migrate","restore","purge").contains(command)){
                if(apply&&(command.equals("purge")||command.equals("restore"))&&(args.length<5||!Files.isRegularFile(Path.of(args[4]))||Files.size(Path.of(args[4]))<1))throw new IllegalArgumentException("A verified database backup file is required for purge/restore");
                result=new AttachmentMigration(db,storage,tx).run(command,apply);
            }else throw new IllegalArgumentException("Unknown resource command");
            Path report=root.resolve("output/oss/"+command+"-"+release+".json");Files.createDirectories(report.getParent());Files.writeString(report,mapper.writerWithDefaultPrettyPrinter().writeValueAsString(result));System.out.println(mapper.writeValueAsString(result));
            if(result instanceof Map<?,?> map&&map.get("failed") instanceof Number count&&count.longValue()>0)throw new IllegalStateException("Migration failed; inspect the report");
        }catch(ApiError e){throw new IllegalStateException("OSS operation failed: "+e.code);}
    }
    private static void probe(ObjectStorage storage,OssSettings settings)throws Exception{
        String key=storage.key("verification/"+Db.id());byte[] bytes="workpanel-private-oss-verification".getBytes(StandardCharsets.UTF_8);
        try{storage.put(key,bytes,"text/plain");BinaryFiles.verify(storage.get(key,bytes.length),bytes.length,AttachmentApplicationService.hash(bytes));
            var response=HttpClient.newBuilder().connectTimeout(java.time.Duration.ofSeconds(5)).build().send(HttpRequest.newBuilder(URI.create("https://"+settings.bucket()+"."+URI.create(settings.endpoint()).getHost()+"/"+key)).timeout(java.time.Duration.ofSeconds(10)).GET().build(),HttpResponse.BodyHandlers.discarding());
            if(response.statusCode()!=403)throw new IllegalStateException("Anonymous read was not denied; check bucket access");
            System.out.println("OSS_PRIVATE_ROUND_TRIP_OK");
        }finally{storage.delete(key);}
    }
    private static String env(String name,String fallback){String value=System.getenv(name);return value==null||value.isBlank()?fallback:value;}
}
