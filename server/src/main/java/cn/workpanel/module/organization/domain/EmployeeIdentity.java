package cn.workpanel.module.organization.domain;

import cn.workpanel.ApiError;
import java.time.LocalDate;
import java.time.Period;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.time.format.DateTimeParseException;
import java.time.format.ResolverStyle;

/** 管理员录入身份证号的格式、出生日期和校验位检查；不在日志中输出原值。 */
public final class EmployeeIdentity {
    private EmployeeIdentity() {}
    public static String gender(Object value) {
        if(!(value instanceof String gender) || !(gender.equals("男") || gender.equals("女")))
            throw ApiError.bad("INVALID_GENDER","性别只能选择男或女");
        return gender;
    }
    public static String idCard(Object value) {
        if(!(value instanceof String raw)) throw ApiError.bad("INVALID_ID_CARD","身份证号须为有效的18位号码");
        String card=raw.trim().toUpperCase(java.util.Locale.ROOT);
        if(!card.matches("[0-9]{17}[0-9X]")) throw ApiError.bad("INVALID_ID_CARD","身份证号须为有效的18位号码");
        try {
            LocalDate birth=LocalDate.parse(card.substring(6,14),DateTimeFormatter.ofPattern("uuuuMMdd").withResolverStyle(ResolverStyle.STRICT));
            if(birth.isAfter(LocalDate.now(ZoneId.of("Asia/Shanghai"))) || birth.isBefore(LocalDate.of(1900,1,1))) throw new DateTimeParseException("birth",card,6);
        } catch(DateTimeParseException e) { throw ApiError.bad("INVALID_ID_CARD","身份证号出生日期无效"); }
        int[] weight={7,9,10,5,8,4,2,1,6,3,7,9,10,5,8,4,2};
        String check="10X98765432";int sum=0;
        for(int i=0;i<17;i++) sum+=(card.charAt(i)-'0')*weight[i];
        if(card.charAt(17)!=check.charAt(sum%11)) throw ApiError.bad("INVALID_ID_CARD","身份证号校验位无效");
        return card;
    }
    public static Integer age(Object value) {
        if(value==null) return null;
        try {
            String card=idCard(value);
            LocalDate birth=LocalDate.parse(card.substring(6,14),DateTimeFormatter.ofPattern("uuuuMMdd"));
            return Period.between(birth,LocalDate.now(ZoneId.of("Asia/Shanghai"))).getYears();
        } catch(RuntimeException ignored) { return null; }
    }
}
