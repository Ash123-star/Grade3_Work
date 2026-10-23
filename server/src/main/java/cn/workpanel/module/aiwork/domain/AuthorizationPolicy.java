package cn.workpanel.module.aiwork.domain;

import cn.workpanel.*;
import java.util.*;

/** 公司只能缩小个人授权的动作、期限、对象和每批数量，不能代替个人开启授权。 */
public record AuthorizationPolicy(boolean create,boolean submit,int days,int objects,int actions) {
    public static final List<String> FIELDS=List.of("aiWorkCreateAuthorization","aiWorkSubmitAuthorization","aiWorkAuthorizationMaxDays","aiWorkAuthorizationMaxObjects","aiWorkAuthorizationMaxActions");
    public static AuthorizationPolicy from(Map<String,Object> body){return new AuthorizationPolicy(flag(body,FIELDS.get(0)),flag(body,FIELDS.get(1)),number(body,FIELDS.get(2),30,30),number(body,FIELDS.get(3),100,100),number(body,FIELDS.get(4),5,5));}
    private static boolean flag(Map<String,Object> b,String key){if(!b.containsKey(key))return true;if(!(b.get(key) instanceof Boolean value))throw ApiError.bad("INVALID_POLICY","自动授权开关需要选择开启或关闭");return value;}
    private static int number(Map<String,Object> b,String key,int fallback,int max){Object value=b.getOrDefault(key,fallback);if(!(value instanceof Number n)||n.doubleValue()!=n.intValue()||n.intValue()<1||n.intValue()>max)throw ApiError.bad("INVALID_POLICY","自动授权限制超出允许范围");return n.intValue();}
    public boolean allows(String action){return action.equals("CREATE_TASK")?create:action.equals("SUBMIT_DELIVERY")&&submit;}
    public Map<String,Object> values(){return Map.of(FIELDS.get(0),create,FIELDS.get(1),submit,FIELDS.get(2),days,FIELDS.get(3),objects,FIELDS.get(4),actions);}
}
