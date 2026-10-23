package cn.workpanel.module.aiwork.infrastructure;

import cn.workpanel.*;
import org.springframework.stereotype.Component;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.TimeUnit;
import java.util.function.Function;

/** 每文件独立进程，硬内存/时限、无凭据环境，结束后删除临时目录；只接受本次材料文件。 */
@Component
public class ParserProcess {
    private final Db db;
    @org.springframework.beans.factory.annotation.Value("${app.ai-parser-sandbox:/usr/local/bin/workpanel-parser-sandbox}") private String sandbox;
    @org.springframework.beans.factory.annotation.Value("${app.ai-parser-sandbox-required:false}") private boolean sandboxRequired;
    public ParserProcess(Db db){this.db=db;}
    public Map<String,Object> parse(byte[] bytes,Function<byte[],Map<String,Object>> ocr){
        Path folder=null;Process child=null;long deadline=System.nanoTime()+TimeUnit.SECONDS.toNanos(90);
        try{
            folder=Files.createTempDirectory("workpanel-parse-");Path input=folder.resolve("input"),output=folder.resolve("result.json");Files.write(input,bytes);
            child=start(folder,DocumentParser.class,List.of(input.toString(),output.toString()));
            if(!child.waitFor(30,TimeUnit.SECONDS)){child.destroyForcibly();throw new ApiError(422,"FILE_TIMEOUT","这份材料处理时间过长，请拆分后重试");}
            if(!Files.isRegularFile(output)||Files.size(output)>8*1024*1024)throw cn.workpanel.shared.application.AiFilePolicy.error("FILE_UNREADABLE");
            var result=db.read(Files.readString(output));if(child.exitValue()!=0||result.containsKey("errorCode"))throw cn.workpanel.shared.application.AiFilePolicy.error(Db.str(result,"errorCode"));
            var parts=new ArrayList<>(cn.workpanel.module.aiwork.application.DeliveryService.maps(result,"parts"));boolean uncertain=Boolean.TRUE.equals(result.get("unverifiable"));
            if(result.get("scanned") instanceof List<?> pages)for(Object page:pages){if(System.nanoTime()>deadline)throw new ApiError(422,"FILE_TIMEOUT","这份材料处理时间过长，请拆分后重试");String name=page.toString();if(!name.matches("page-[0-9]+\\.png"))throw new IllegalArgumentException();var recognized=ocr.apply(Files.readAllBytes(folder.resolve(name)));if(System.nanoTime()>deadline)throw new ApiError(422,"FILE_TIMEOUT","这份材料处理时间过长，请拆分后重试");for(var p:cn.workpanel.module.aiwork.application.DeliveryService.maps(recognized,"parts")){var item=new LinkedHashMap<>(p);item.put("locator","第"+name.replaceAll("\\D","")+"页");parts.add(item);}uncertain|=Boolean.TRUE.equals(recognized.get("unverifiable"));}
            if(parts.size()>cn.workpanel.shared.application.AiFilePolicy.PARTS||parts.stream().mapToLong(p->Db.str(p,"text").length()).sum()>cn.workpanel.shared.application.AiFilePolicy.TEXT_CHARS)throw cn.workpanel.shared.application.AiFilePolicy.error("FILE_LIMIT");
            return Map.of("type",result.get("type"),"parts",parts,"unverifiable",uncertain);
        }catch(ApiError e){throw e;}catch(Exception e){if(e instanceof InterruptedException)Thread.currentThread().interrupt();throw new ApiError(422,"FILE_UNREADABLE","材料暂时无法读取，请换一份完整文件");}
        finally{terminate(child);if(folder!=null)try(var paths=Files.walk(folder)){for(var path:paths.sorted(Comparator.reverseOrder()).toList())Files.deleteIfExists(path);}catch(Exception ignored){}}
    }
    /** 与提取共用无凭据、禁网、有限资源的子进程；不将模板内容加载进服务端 JVM。 */
    public byte[] renderTemplate(byte[] bytes,Map<String,String> fields){
        Path folder=null;Process child=null;
        try{
            folder=Files.createTempDirectory("workpanel-template-");Path input=folder.resolve("input"),output=folder.resolve("prepared"),values=folder.resolve("fields.json");
            Files.write(input,bytes);Files.writeString(values,db.write(fields));
            child=start(folder,TemplateRenderer.class,List.of(input.toString(),output.toString(),values.toString()));
            if(!child.waitFor(30,TimeUnit.SECONDS)){child.destroyForcibly();throw cn.workpanel.shared.application.AiFilePolicy.error("FILE_TIMEOUT");}
            if(child.exitValue()!=0||!Files.isRegularFile(output)||Files.size(output)>cn.workpanel.shared.application.AiFilePolicy.FILE_BYTES)throw cn.workpanel.shared.application.AiFilePolicy.error("FILE_UNREADABLE");
            return Files.readAllBytes(output);
        }catch(ApiError e){throw e;}catch(Exception e){if(e instanceof InterruptedException)Thread.currentThread().interrupt();throw cn.workpanel.shared.application.AiFilePolicy.error("FILE_UNREADABLE");}
        finally{terminate(child);if(folder!=null)try(var paths=Files.walk(folder)){for(var path:paths.sorted(Comparator.reverseOrder()).toList())Files.deleteIfExists(path);}catch(Exception ignored){}}
    }
    private static void terminate(Process child){if(child==null||!child.isAlive())return;child.destroyForcibly();try{child.waitFor(2,TimeUnit.SECONDS);}catch(InterruptedException e){Thread.currentThread().interrupt();}}
    private Process start(Path folder,Class<?> entry,List<String> args)throws java.io.IOException{
        String executable=Path.of(System.getProperty("java.home"),"bin",System.getProperty("os.name").startsWith("Windows")?"java.exe":"java").toString();
        String classpath=System.getProperty("surefire.test.class.path",System.getProperty("java.class.path"));var command=new ArrayList<String>();
        if(sandbox!=null&&Files.isExecutable(Path.of(sandbox)))command.add(sandbox);
        else if(sandboxRequired)throw new ApiError(503,"PARSER_UNAVAILABLE","文件处理暂时不可用，材料已保留");
        command.addAll(List.of(executable,"-Xmx256m","-Xss512k","-XX:ReservedCodeCacheSize=64m","-XX:CompressedClassSpaceSize=64m","-XX:MaxMetaspaceSize=128m","-XX:+UseSerialGC","-XX:ActiveProcessorCount=1","-Djava.awt.headless=true","-Djava.io.tmpdir="+folder));
        if(classpath.endsWith(".jar")&&!classpath.contains(java.io.File.pathSeparator)){command.add("-Dloader.main="+entry.getName());command.addAll(List.of("-cp",classpath,"org.springframework.boot.loader.launch.PropertiesLauncher"));}
        else command.addAll(List.of("-cp",classpath,entry.getName()));command.addAll(args);
        var builder=new ProcessBuilder(command);builder.environment().entrySet().removeIf(e->!Set.of("SystemRoot","WINDIR","TEMP","TMP","PATH","Path").contains(e.getKey()));
        return builder.redirectError(ProcessBuilder.Redirect.DISCARD).redirectOutput(ProcessBuilder.Redirect.DISCARD).start();
    }
}
