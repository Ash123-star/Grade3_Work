package cn.workpanel.module.customer.domain;

import cn.workpanel.ApiError;
import cn.workpanel.Db;
import java.time.LocalDate;
import java.util.Map;

/** Benefit grant rules: annual cards/mall benefits have a validity window and optional use cap. */
public record BenefitDraft(String kind,String name,LocalDate validFrom,LocalDate validTo,Integer maxUses) {
    public static BenefitDraft parse(Map<String,Object> body) {
        Db.fields(body,"kind","name","validFrom","validTo","maxUses");
        String kind=Db.required(body,"kind").toUpperCase();
        if(!kind.equals("ANNUAL_CARD")&&!kind.equals("MALL_MEMBER")&&!kind.equals("OTHER")) throw ApiError.bad("INVALID_KIND","权益类型无效");
        String name=Db.required(body,"name");
        if(name.length()>200) throw ApiError.bad("INVALID_NAME","权益名称最多200字");
        LocalDate from=CustomerDraft.date(body.get("validFrom"),"validFrom");
        LocalDate to=CustomerDraft.date(body.get("validTo"),"validTo");
        if(to.isBefore(from)) throw ApiError.bad("INVALID_DATE_RANGE","有效期结束不能早于开始");
        Integer maxUses=null;
        if(body.get("maxUses")!=null) {
            Object raw=body.get("maxUses");
            if(!(raw instanceof Integer n)||n<1||n>100000) throw ApiError.bad("INVALID_MAX_USES","maxUses 必须为1–100000整数");
            maxUses=(Integer)raw;
        }
        return new BenefitDraft(kind,name,from,to,maxUses);
    }
}
