package cn.workpanel.module.organization.domain;

import cn.workpanel.ApiError;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.text.Normalizer;
import java.util.*;

/** Web 员工输入规则；资源字典随版本发布，不向外部服务发送身份资料。 */
public final class EmployeeInput {
    private EmployeeInput() {}
    public static String name(Object input) {
        if(!(input instanceof String raw)) throw ApiError.bad("INVALID_NAME","姓名须为文本");
        String value=Normalizer.normalize(raw.strip(),Normalizer.Form.NFC);
        int length=value.codePointCount(0,value.length());
        if(raw.codePoints().anyMatch(c->Character.isISOControl(c)||Character.getType(c)==Character.FORMAT)||length<2||length>50||!value.matches("[\\p{L}][\\p{L}\\p{M}]*(?:[ ·'’-][\\p{L}][\\p{L}\\p{M}]*)*"))
            throw ApiError.bad("INVALID_NAME","姓名须为2–50个字符，可用汉字、字母及姓名内部的空格、·、连字符或撇号，不能包含数字、表情或连续分隔符");
        return value;
    }
    public static void account(String value) {
        if(!value.matches("[a-zA-Z0-9_.-]{3,64}")) throw ApiError.bad("INVALID_ACCOUNT","登录账号须为3–64位字母、数字或 _ . -");
    }
    public static void phone(String value) {
        if(!value.matches("[0-9]{11}")) throw ApiError.bad("INVALID_PHONE","手机号须为11位数字");
        // 公众移动号段，保留转售号段；1610 为四位网号。来源及维护办法见 input-data.md。
        if(!value.matches("1(?:3[0-9]|4[57]|5[0-35-9]|6[2567]|7[0135-8]|8[0-9]|9[0-35-9])[0-9]{8}|1610[0-9]{7}"))
            throw ApiError.bad("INVALID_PHONE_PREFIX","手机号号段无效，请填写大陆公众移动手机号码");
    }
    public static String position(Object value) {
        String result=value==null?"NONE":value.toString();
        if(!Set.of("NONE","GENERAL_MANAGER","DEPUTY_GENERAL_MANAGER").contains(result)) throw ApiError.bad("INVALID_BUSINESS_POSITION","业务职位无效");
        return result;
    }
    private static final Set<String> ADDRESS_CODES=loadCodes();
    private static Set<String> loadCodes() {
        try(var stream=EmployeeInput.class.getResourceAsStream("/identity/county-codes.txt")) {
            if(stream==null) throw new IllegalStateException("Missing county code dictionary");
            try(var reader=new BufferedReader(new InputStreamReader(stream,StandardCharsets.UTF_8))) {
                return Set.copyOf(reader.lines().filter(s->s.matches("[0-9]{6}")).toList());
            }
        } catch(IOException e) { throw new ExceptionInInitializerError(e); }
    }
    public static void address(String card) {
        if(!ADDRESS_CODES.contains(card.substring(0,6))) throw ApiError.bad("INVALID_ID_ADDRESS","身份证号地址码无效，请核对前6位");
    }
    public static void genderMatches(String gender,String card) {
        if(card!=null&&gender!=null&&!gender.equals((card.charAt(16)-'0')%2==0?"女":"男"))
            throw ApiError.bad("IDENTITY_GENDER_MISMATCH","所选性别与身份证号不一致");
    }
}
