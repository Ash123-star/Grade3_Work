package cn.workpanel.module.aiwork.infrastructure;

import cn.workpanel.*;
import cn.workpanel.module.attachment.application.AttachmentApplicationService;
import cn.workpanel.module.aiwork.application.DeliveryService;
import cn.workpanel.shared.application.AiFilePolicy;
import org.springframework.stereotype.Component;
import org.springframework.beans.factory.annotation.Value;
import javax.imageio.ImageIO;
import java.io.*;
import java.net.URI;
import java.net.http.*;
import java.time.Duration;
import java.util.*;

/** 本人用途鉴权后提取；文档在独立受限 JVM，图片由内网本地 OCR 处理，缓存按用户隔离。 */
@Component
public class FileExtractor {
    public static final String VERSION="pdfbox-3.0.6_poi-5.4.1_paddle-3.0.3_v3";
    private final Db db;private final AttachmentApplicationService attachments;private final ParserProcess parser;private final String ocrUrl;private final boolean ocrEnabled;
    private final HttpClient http=HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(3)).build();
    public FileExtractor(Db db,AttachmentApplicationService attachments,ParserProcess parser,@Value("${app.ai-ocr-url:}")String ocrUrl,@Value("${app.ai-ocr-enabled:false}")boolean ocrEnabled){this.db=db;this.attachments=attachments;this.parser=parser;this.ocrUrl=ocrUrl;this.ocrEnabled=ocrEnabled;}
    public boolean imagesAvailable(){return ocrEnabled&&!ocrUrl.isBlank();}
    public void validateIntake(Actor actor,List<String> ids){attachments.intake(actor,ids);}
    public Map<String,Object> extract(Actor a,String id){
        var file=attachments.owned(a,id);byte[] bytes=(byte[])file.get("data");String type=AiFilePolicy.validate(Db.str(file,"filename"),bytes),hash=AttachmentApplicationService.hash(bytes);
        var cached=db.rows("SELECT body FROM ai_file_extractions WHERE company_id=? AND owner_id=? AND attachment_id=? AND file_hash=? AND parser_version=? AND expires_at>now()",a.company(),a.id(),id,hash,VERSION);if(!cached.isEmpty())return db.read(cached.getFirst().get("body"));
        Map<String,Object> parsed;
        if(Set.of("PNG","JPEG").contains(type)){parsed=new LinkedHashMap<>(ocr(bytes));parsed.put("type","IMAGE");}
        else {parsed=parser.parse(bytes,this::ocr);if(!type.equals(parsed.get("type")))throw AiFilePolicy.error("FILE_TYPE_MISMATCH");}
        var result=new LinkedHashMap<String,Object>(parsed);result.put("id",id);result.put("filename",file.get("filename"));result.put("hash",hash);result.put("parserVersion",VERSION);
        db.update("INSERT INTO ai_file_extractions(id,company_id,owner_id,attachment_id,file_hash,parser_version,body) VALUES (?,?,?,?,?,?,?::jsonb) ON CONFLICT(company_id,owner_id,attachment_id,file_hash,parser_version) DO UPDATE SET body=EXCLUDED.body,expires_at=now()+interval '7 days'",Db.id(),a.company(),a.id(),id,hash,VERSION,db.write(result));
        db.update("UPDATE attachments SET file_hash=?,detected_type=? WHERE company_id=? AND id=?",hash,result.get("type"),a.company(),id);return result;
    }
    private Map<String,Object> ocr(byte[] bytes){
        try{
            AiFilePolicy.size(bytes.length);
            try(var input=ImageIO.createImageInputStream(new ByteArrayInputStream(bytes))){var readers=ImageIO.getImageReaders(input);if(!readers.hasNext())throw new IOException();var reader=readers.next();try{reader.setInput(input);if((long)reader.getWidth(0)*reader.getHeight(0)>AiFilePolicy.IMAGE_PIXELS)throw ApiError.bad("FILE_LIMIT","图片尺寸过大，请裁剪后重试");}finally{reader.dispose();}}
            if(!imagesAvailable())throw new ApiError(503,"OCR_UNAVAILABLE","图片识别暂时不可用，可以补充文字");
            var request=HttpRequest.newBuilder(URI.create(ocrUrl+"/extract")).timeout(Duration.ofSeconds(30)).header("Content-Type","application/octet-stream").POST(HttpRequest.BodyPublishers.ofByteArray(bytes)).build();
            // 流式限额，避免错误服务返回无界响应导致主服务内存增长。
            var response=http.send(request,HttpResponse.BodyHandlers.ofInputStream());byte[] content;try(var stream=response.body()){content=stream.readNBytes(1000001);}
            if(response.statusCode()==429||response.statusCode()>=500)throw new ApiError(503,"OCR_UNAVAILABLE","图片识别暂时不可用，材料已保留");
            if(response.statusCode()!=200||content.length>1000000)throw new ApiError(422,"OCR_FAILED","这张图暂时无法识别，请换一张清晰的图片");
            var body=db.read(new String(content,java.nio.charset.StandardCharsets.UTF_8));if(!(body.get("parts") instanceof List<?> list)||list.size()>10000)throw new IOException();
            boolean uncertain=Boolean.TRUE.equals(body.get("unverifiable"))||list.isEmpty();
            for(var p:DeliveryService.maps(body,"parts")){if(!(p.get("text") instanceof String text)||text.length()>10000)throw new IOException();if(p.get("confidence") instanceof Number n&&n.doubleValue()<.92)uncertain=true;}
            return Map.of("parts",body.get("parts"),"unverifiable",uncertain);
        }catch(ApiError e){throw e;}catch(java.net.http.HttpTimeoutException|java.net.ConnectException e){throw new ApiError(503,"OCR_UNAVAILABLE","图片识别暂时不可用，材料已保留");}catch(Exception e){if(e instanceof InterruptedException)Thread.currentThread().interrupt();throw new ApiError(422,"OCR_FAILED","图片暂时无法识别，请换一张清晰的，或补充文字");}
    }
}
