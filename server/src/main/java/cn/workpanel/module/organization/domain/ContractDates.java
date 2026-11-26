package cn.workpanel.module.organization.domain;
import cn.workpanel.*;import java.time.*;import java.util.*;
public final class ContractDates {
 private ContractDates(){}
 public static LocalDate date(Map<String,Object> body,String field){try {String s=Db.required(body,field);if(!s.matches("[0-9]{4}-[0-9]{2}-[0-9]{2}"))throw new IllegalArgumentException();LocalDate d=LocalDate.parse(s);if(d.getYear()<1)throw new IllegalArgumentException();return d;}catch(Exception e){throw ApiError.bad("INVALID_CONTRACT_DATE","请输入有效合同日期");}}
 public static LocalDate today(){return LocalDate.now(ZoneId.of("Asia/Shanghai"));}
 public static boolean due(LocalDate end,LocalDate today,int days){return end.minusDays(days).equals(today);}
}
