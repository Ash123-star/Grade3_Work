package cn.workpanel.module.customer;

import cn.workpanel.ApiError;
import cn.workpanel.module.customer.domain.*;
import org.junit.jupiter.api.Test;
import java.util.*;
import static org.junit.jupiter.api.Assertions.*;

class CustomerDraftTest {
    Map<String,Object> body() { return new HashMap<>(Map.of("kind","individual","name","  张三  ")); }
    @Test void normalizesCustomerAndRejectsUnknownFields() {
        var d=CustomerDraft.parse(body(),false);
        assertEquals("INDIVIDUAL",d.kind()); assertEquals("张三",d.name()); assertNull(d.externalId()); assertEquals("ACTIVE",d.status());
        for(String key:List.of("ownerId","companyId","taskId","version")) {
            var b=body();b.put(key,"x");
            assertEquals("UNKNOWN_FIELD",assertThrows(ApiError.class,()->CustomerDraft.parse(b,false)).code);
        }
    }
    @Test void rejectsInvalidKindEmailAndOversized() {
        var badKind=body();badKind.put("kind","TEAM");assertThrows(ApiError.class,()->CustomerDraft.parse(badKind,false));
        var badEmail=body();badEmail.put("email","bad");assertEquals("INVALID_EMAIL",assertThrows(ApiError.class,()->CustomerDraft.parse(badEmail,false)).code);
        var longName=body();longName.put("name","x".repeat(201));assertThrows(ApiError.class,()->CustomerDraft.parse(longName,false));
        var longNote=body();longNote.put("note","x".repeat(2001));assertThrows(ApiError.class,()->CustomerDraft.parse(longNote,false));
    }
    @Test void updateRequiresPositiveVersionAndStatus() {
        var b=body();b.put("version",1);b.put("status","ARCHIVED");
        assertEquals(1,CustomerDraft.parse(b,true).version());
        for(Object version:List.of(0,-1,1.0,"1",true)) {
            b.put("version",version);
            assertEquals("INVALID_VERSION",assertThrows(ApiError.class,()->CustomerDraft.parse(b,true)).code);
        }
        b.put("version",1);b.put("status","DELETED");
        assertEquals("INVALID_STATUS",assertThrows(ApiError.class,()->CustomerDraft.parse(b,true)).code);
    }
    @Test void benefitRequiresValidWindowAndPositiveCap() {
        var b=new HashMap<String,Object>(Map.of("kind","annual_card","name","2026演出年卡","validFrom","2026-01-01","validTo","2026-12-31","maxUses",10));
        var d=BenefitDraft.parse(b);assertEquals("ANNUAL_CARD",d.kind());assertEquals(10,d.maxUses());
        b.put("validTo","2025-12-31");assertEquals("INVALID_DATE_RANGE",assertThrows(ApiError.class,()->BenefitDraft.parse(b)).code);
        b.put("validTo","2026-12-31");b.put("maxUses",0);assertEquals("INVALID_MAX_USES",assertThrows(ApiError.class,()->BenefitDraft.parse(b)).code);
    }
    @Test void membershipVersionZeroMeansCreate() {
        var b=new HashMap<String,Object>(Map.of("mallMemberId","mall-1","level","金卡"));
        var d=MembershipDraft.parse(b);assertEquals("ACTIVE",d.status());assertEquals(0,d.version());
        b.put("version",3);assertEquals(3,MembershipDraft.parse(b).version());
        b.put("version",-1);assertEquals("INVALID_VERSION",assertThrows(ApiError.class,()->MembershipDraft.parse(b)).code);
    }
}
