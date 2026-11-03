package cn.workpanel.module.calendar;

import cn.workpanel.Actor;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/calendar/holidays")
public class HolidayController {
    private final HolidayService service;
    public HolidayController(HolidayService service) { this.service=service; }
    /** 中国大陆年度法定假日及调休。已确认登录用户可读；year为2007..2100，越界400 INVALID_YEAR。只读幂等，无分页/版本写入；源失败200返回STALE或UNAVAILABLE，不推算假期。 */
    @GetMapping public HolidayService.Snapshot get(HttpServletRequest request,@RequestParam int year) {
        Actor.current(request); return service.year(year);
    }
}
