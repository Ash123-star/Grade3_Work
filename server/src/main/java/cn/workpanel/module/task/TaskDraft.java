package cn.workpanel.module.task;

import java.util.*;

/** 规范化后的派发内容：协作人与附件已去重排序，主负责人不在协作人中。 */
public record TaskDraft(String title,String ownerId,String deadline,String urgency,String group,String content,String progressNote,List<String> collaborators,List<String> attachments,List<Map<String,Object>> acceptanceChecklist) {
    public TaskDraft { collaborators=List.copyOf(collaborators); attachments=List.copyOf(attachments); acceptanceChecklist=List.copyOf(acceptanceChecklist); }
    public TaskDraft(String title,String ownerId,String deadline,String urgency,String group,String content,String progressNote,List<String> collaborators,List<String> attachments) {
        this(title,ownerId,deadline,urgency,group,content,progressNote,collaborators,attachments,List.of());
    }

    /** 存入 tasks.body 及计算摘要的形式；键有序，缺省的可选文本不写入。 */
    public Map<String,Object> body() {
        var m=new TreeMap<String,Object>();
        m.put("title",title); m.put("ownerId",ownerId); m.put("deadline",deadline); m.put("urgency",urgency);
        if(group!=null) m.put("group",group); if(content!=null) m.put("content",content); if(progressNote!=null) m.put("progressNote",progressNote);
        m.put("collaborators",collaborators); m.put("attachments",attachments);
        if(!acceptanceChecklist.isEmpty()) m.put("acceptanceChecklist",acceptanceChecklist);
        return m;
    }
}
