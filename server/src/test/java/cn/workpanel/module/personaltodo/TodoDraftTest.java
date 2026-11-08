package cn.workpanel.module.personaltodo;

import cn.workpanel.ApiError;
import cn.workpanel.module.personaltodo.domain.TodoDraft;
import org.junit.jupiter.api.Test;
import java.util.*;
import static org.junit.jupiter.api.Assertions.*;

class TodoDraftTest {
    Map<String,Object> body() {return new HashMap<>(Map.of("title","  私人安排  ","date","2028-02-29"));}
    @Test void normalizesOnlyTextAndPreservesCivilDate() {
        var d=TodoDraft.parse(body(),false);assertEquals("私人安排",d.title());assertEquals("2028-02-29",d.date().toString());assertEquals("2028-02-29",d.endDate().toString());assertEquals(TodoDraft.DEFAULT_COLOR,d.color());assertEquals("",d.note());assertFalse(d.completed());
    }
    @Test void acceptsBoundedRangeAndHexColor() {
        var b=body();b.put("endDate","2028-03-02");b.put("color","#8fc7b0");
        var d=TodoDraft.parse(b,false);assertEquals("2028-03-02",d.endDate().toString());assertEquals("#8FC7B0",d.color());
        b.put("endDate","2028-02-29");assertEquals("2028-02-29",TodoDraft.parse(b,false).endDate().toString());
    }
    @Test void rejectsInvalidRangeAndColor() {
        var b=body();b.put("endDate","2028-02-28");
        assertEquals("INVALID_DATE_RANGE",assertThrows(ApiError.class,()->TodoDraft.parse(b,false)).code);
        b=body();b.put("endDate","2030-03-02");
        assertEquals("INVALID_DATE_RANGE",assertThrows(ApiError.class,()->TodoDraft.parse(b,false)).code);
        for(Object color:List.of("red","#FFF","#GGGGGG",42)) {
            var c=body();c.put("color",color);
            assertEquals("INVALID_COLOR",assertThrows(ApiError.class,()->TodoDraft.parse(c,false)).code);
        }
    }
    @Test void rejectsInvalidDatesAndCoercion() {
        for(Object date:List.of("2026-02-29","2026-11-31","2026-1-01","1899-12-31","2101-01-01",42)) {
            var b=body();b.put("date",date);assertEquals("INVALID_DATE",assertThrows(ApiError.class,()->TodoDraft.parse(b,false)).code);
        }
        for(String month:List.of("2026-13","2026-2","2101-01","invalid"))assertThrows(ApiError.class,()->TodoDraft.month(month));
    }
    @Test void rejectsBlankOversizedAndPrivateScopeInjection() {
        for(String title:List.of(" ","x".repeat(121))) {var b=body();b.put("title",title);assertThrows(ApiError.class,()->TodoDraft.parse(b,false));}
        var b=body();b.put("title","😀".repeat(120));assertEquals(120,TodoDraft.parse(b,false).title().codePointCount(0,240));
        for(String key:List.of("ownerId","companyId","taskId","completed","version")){var c=body();c.put(key,"bad");assertEquals("UNKNOWN_FIELD",assertThrows(ApiError.class,()->TodoDraft.parse(c,false)).code);}
        var c=body();c.put("note","x".repeat(2001));assertThrows(ApiError.class,()->TodoDraft.parse(c,false));
    }
    @Test void updateRequiresStrictBooleanAndPositiveInteger() {
        var b=body();b.put("completed",true);b.put("version",1);assertTrue(TodoDraft.parse(b,true).completed());
        for(Object version:List.of(0,-1,1.0,"1",true)){b.put("version",version);assertThrows(ApiError.class,()->TodoDraft.parse(b,true));}
        b.put("version",1);b.put("completed","true");assertThrows(ApiError.class,()->TodoDraft.parse(b,true));
    }
}
