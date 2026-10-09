package cn.workpanel;

import jakarta.servlet.http.HttpServletRequest;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.method.annotation.MethodArgumentTypeMismatchException;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.web.bind.ServletRequestBindingException;
import org.springframework.web.multipart.MaxUploadSizeExceededException;
import java.util.Map;

public class ApiError extends RuntimeException {
    final int status; final String code;
    public ApiError(int status,String code,String message) { super(message); this.status=status; this.code=code; }
    static ApiError bad(String code,String message) { return new ApiError(400,code,message); }
    static ApiError forbidden() { return new ApiError(403,"FORBIDDEN","不在授权范围内"); }
    static ApiError notFound() { return new ApiError(404,"NOT_FOUND","记录不存在"); }
    static ApiError conflict() { return new ApiError(409,"VERSION_CONFLICT","版本已变化，请刷新后重试"); }
}

@RestControllerAdvice
class Errors {
    @ExceptionHandler(org.springframework.web.context.request.async.AsyncRequestNotUsableException.class)
    void disconnected() { /* 客户端断开 SSE 后响应已不可写，不尝试再写 JSON 错误。 */ }
    @ExceptionHandler(ApiError.class)
    ResponseEntity<?> business(ApiError e,HttpServletRequest r) { return ResponseEntity.status(e.status).body(body(e.code,e.getMessage(),r)); }
    @ExceptionHandler(DataIntegrityViolationException.class)
    ResponseEntity<?> integrity(Exception e,HttpServletRequest r) { return ResponseEntity.status(409).body(body("DATA_CONFLICT","唯一性或关联约束冲突",r)); }
    @ExceptionHandler({HttpMessageNotReadableException.class,MethodArgumentTypeMismatchException.class,IllegalArgumentException.class,ServletRequestBindingException.class})
    ResponseEntity<?> malformed(Exception e,HttpServletRequest r) { return ResponseEntity.badRequest().body(body("INVALID_REQUEST","请求格式无效",r)); }
    @ExceptionHandler(MaxUploadSizeExceededException.class)
    ResponseEntity<?> tooLarge(Exception e,HttpServletRequest r) { return ResponseEntity.status(413).body(body("FILE_TOO_LARGE","文件超过 10MB 限制",r)); }
    @ExceptionHandler(Exception.class)
    ResponseEntity<?> other(Exception e,HttpServletRequest r) {
        org.slf4j.LoggerFactory.getLogger(Errors.class).error("请求失败 traceId={} exception={}",r.getAttribute("traceId"),e.getClass().getSimpleName());
        return ResponseEntity.status(500).body(body("INTERNAL_ERROR","服务暂时不可用",r));
    }
    static Map<String,Object> body(String code,String message,HttpServletRequest r) { return Map.of("code",code,"message",message,"traceId",String.valueOf(r.getAttribute("traceId"))); }
}
