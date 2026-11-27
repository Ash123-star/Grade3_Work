package cn.workpanel.module.organization;
import cn.workpanel.*;import cn.workpanel.module.organization.domain.ContractDates;import org.junit.jupiter.api.Test;import java.time.*;import java.util.*;import static org.junit.jupiter.api.Assertions.*;
class ContractDatesTest {
 @Test void exactReminderDates(){LocalDate end=LocalDate.of(2028,3,1);assertTrue(ContractDates.due(end,end.minusDays(30),30));assertTrue(ContractDates.due(end,end.minusDays(7),7));assertTrue(ContractDates.due(end,end,0));assertFalse(ContractDates.due(end,end.minusDays(1),0));}
 @Test void rejectsInvalidDate(){assertThrows(ApiError.class,()->ContractDates.date(Map.of("date","2026-02-30"),"date"));assertEquals(LocalDate.of(2028,2,29),ContractDates.date(Map.of("date","2028-02-29"),"date"));}
}
