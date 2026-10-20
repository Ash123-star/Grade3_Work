package cn.workpanel.module.task;

import java.util.*;

/** 规范化后的任务候选：参与人是无角色的去重集合。 */
public record TaskDraft(String title,List<String> participants,String startAt,String deadline,String urgency,
                        String group,String content,String labelId,List<String> attachments) {
    public TaskDraft { participants=List.copyOf(participants); attachments=List.copyOf(attachments); }

    /** 仅供仍在编译的历史模块和迁移测试读取；新接口不得使用负责人/协作人语义。 */
    @Deprecated public TaskDraft(String title,String ownerId,String deadline,String urgency,String group,String content,
                                 String ignoredProgressNote,List<String> collaborators,List<String> attachments) {
        this(title, legacyParticipants(ownerId,collaborators), null, deadline, urgency, group, content, null, attachments);
    }
    @Deprecated public String ownerId() { return participants.isEmpty()?"":participants.getFirst(); }
    @Deprecated public List<String> collaborators() { return participants.size()<2?List.of():participants.subList(1,participants.size()); }
    @Deprecated public String progressNote() { return null; }
    private static List<String> legacyParticipants(String ownerId,List<String> collaborators) {
        var ids=new TreeSet<String>(); if(ownerId!=null&&!ownerId.isBlank()) ids.add(ownerId);
        if(collaborators!=null) ids.addAll(collaborators); return List.copyOf(ids);
    }

    /** 存入 tasks.body 及计算摘要的形式；键有序，缺省的可选文本不写入。 */
    public Map<String,Object> body() {
        var m=new TreeMap<String,Object>();
        m.put("title",title); m.put("participants",participants); m.put("deadline",deadline); m.put("urgency",urgency);
        if(startAt!=null) m.put("startAt",startAt); if(group!=null) m.put("group",group); if(content!=null) m.put("content",content); if(labelId!=null) m.put("labelId",labelId);
        m.put("attachments",attachments);
        return m;
    }
}
