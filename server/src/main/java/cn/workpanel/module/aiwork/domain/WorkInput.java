package cn.workpanel.module.aiwork.domain;

import cn.workpanel.*;
import java.util.*;

/** 用户请求与材料分离，材料内指令不能成为执行授权。 */
public record WorkInput(String text,List<String> attachments,String taskId,Integer taskVersion,Map<String,Object> answers) {
    public static WorkInput parse(Map<String,Object> b,boolean message){
        if(message)Db.fields(b,"text","attachmentIds","taskId","taskVersion","version","answers");
        else Db.fields(b,"text","attachmentIds","taskId","taskVersion");
        if(b.containsKey("text")&&!(b.get("text") instanceof String))throw ApiError.bad("INVALID_TEXT","请填写文字内容");
        String text=Db.str(b,"text").trim();var files=Business.strings(b,"attachmentIds");
        if(text.length()>cn.workpanel.shared.application.AiFilePolicy.TEXT||text.isEmpty()&&files.isEmpty())throw ApiError.bad("INVALID_TEXT","请说说要办什么，或添加材料");
        if(files.size()>cn.workpanel.shared.application.AiFilePolicy.FILES)throw ApiError.bad("FILE_LIMIT","一次最多添加 5 份材料");
        String task=Db.str(b,"taskId");Integer v=null;
        if(!task.isBlank()){if(!(b.get("taskVersion") instanceof Number n)||n.doubleValue()!=n.intValue()||n.intValue()<1)throw ApiError.bad("INVALID_VERSION","请刷新任务后重试");v=n.intValue();}
        var answers=new LinkedHashMap<String,Object>();if(b.get("answers") instanceof Map<?,?> raw){for(var entry:raw.entrySet()){if(!"ownerId".equals(entry.getKey())||!(entry.getValue() instanceof String value)||value.isBlank())throw ApiError.bad("INVALID_ANSWER","请选择有效人员");answers.put("ownerId",entry.getValue());}}else if(b.containsKey("answers"))throw ApiError.bad("INVALID_ANSWER","补充信息无效");
        return new WorkInput(text,files,task,v,answers);
    }
    public Map<String,Object> body(){var b=new LinkedHashMap<String,Object>();b.put("text",text);b.put("attachmentIds",attachments);if(!answers.isEmpty())b.put("answers",answers);if(!taskId.isBlank()){b.put("taskId",taskId);b.put("taskVersion",taskVersion);}return b;}
}
