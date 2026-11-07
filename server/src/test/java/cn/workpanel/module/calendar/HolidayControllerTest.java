package cn.workpanel.module.calendar;
import cn.workpanel.Actor;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.time.Clock;
import org.junit.jupiter.api.Test;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;
class HolidayControllerTest {
 @Test void httpMappingUsesValidatedServiceAndReturnsSource() throws Exception {
  var service=new HolidayService(new ObjectMapper(),Clock.systemUTC(),year->HolidayServiceTest.valid);
  var mvc=MockMvcBuilders.standaloneSetup(new HolidayController(service)).build();
  mvc.perform(get("/api/calendar/holidays").param("year","2026").requestAttr("actor",new Actor("u","c","EMPLOYEE","d","t",false,false,false,"ACTIVE")))
    .andExpect(status().isOk()).andExpect(jsonPath("$.days[0].isOffDay").value(true)).andExpect(jsonPath("$.days[1].isOffDay").value(false)).andExpect(jsonPath("$.status").value("FRESH"));
 }
 @Test @org.junit.jupiter.api.condition.EnabledIfSystemProperty(named="calendar.live",matches="true")
 void realPublicSourceFlowsThroughHttpMapping() throws Exception {
  var mvc=MockMvcBuilders.standaloneSetup(new HolidayController(new HolidayService(new ObjectMapper()))).build();
  mvc.perform(get("/api/calendar/holidays").param("year","2026").requestAttr("actor",new Actor("u","c","EMPLOYEE","d","t",false,false,false,"ACTIVE")))
    .andExpect(status().isOk()).andExpect(jsonPath("$.status").value("FRESH"))
    .andExpect(jsonPath("$.papers[0]").isNotEmpty()).andExpect(jsonPath("$.days").isNotEmpty());
 }
}
