package cn.workpanel;

import jakarta.servlet.*;
import jakarta.servlet.http.*;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.*;
import org.springframework.boot.web.servlet.FilterRegistrationBean;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.web.cors.*;
import org.springframework.web.filter.OncePerRequestFilter;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.script.DefaultRedisScript;
import java.io.IOException;
import java.util.*;

@Configuration
public class Security {
    @Bean BCryptPasswordEncoder passwords() { return new BCryptPasswordEncoder(12); }
    @Bean SecurityFilterChain apiSecurityChain(HttpSecurity http) throws Exception { return http.csrf(c->c.disable()).cors(c->{}).authorizeHttpRequests(a->a.anyRequest().permitAll()).sessionManagement(s->s.sessionCreationPolicy(org.springframework.security.config.http.SessionCreationPolicy.STATELESS)).build(); }
    @Bean CorsConfigurationSource cors(@Value("${app.cors-origins}") String origins) {
        CorsConfiguration c=new CorsConfiguration(); c.setAllowedOrigins(Arrays.asList(origins.split(","))); c.setAllowedMethods(List.of("GET","POST","PUT","DELETE","OPTIONS")); c.setAllowedHeaders(List.of("Authorization","Content-Type","Idempotency-Key","Last-Event-ID")); c.setExposedHeaders(List.of("X-Trace-Id","Content-Disposition"));
        UrlBasedCorsConfigurationSource source=new UrlBasedCorsConfigurationSource(); source.registerCorsConfiguration("/**",c); return source;
    }
    @Bean FilterRegistrationBean<OncePerRequestFilter> authentication(Db db,Limiter limiter) {
        var filter=new OncePerRequestFilter() {
            @Override protected void doFilterInternal(HttpServletRequest r,HttpServletResponse s,FilterChain chain) throws IOException,ServletException {
                String trace=Db.id(); r.setAttribute("traceId",trace); s.setHeader("X-Trace-Id",trace);
                try {
                    String path=r.getRequestURI();
                    if(path.startsWith("/api/")&&!path.equals("/api/health")&&!path.startsWith("/api/openapi")&&!path.startsWith("/api/docs")&&!path.equals("/api/auth/departments")&&!path.equals("/api/auth/register")&&!path.equals("/api/auth/login")&&!r.getMethod().equals("OPTIONS")) {
                        Actor a=authenticate(db,r.getHeader("Authorization")); r.setAttribute("actor",a);
                        if(a.mustChange()&&!Set.of("/api/auth/password","/api/auth/me","/api/auth/logout").contains(path)) throw new ApiError(403,"PASSWORD_CHANGE_REQUIRED","首次登录请修改密码");
                        boolean ownReviewRead=r.getMethod().equals("GET")&&(path.equals("/api/reviews")||path.matches("/api/reviews/[^/]+"));
                        if(!a.status().equals("ACTIVE")&&!Set.of("/api/auth/password","/api/auth/me","/api/auth/logout","/api/organization/membership-application").contains(path)&&!ownReviewRead) throw new ApiError(403,"MEMBERSHIP_PENDING","部门归属尚未确认");
                        limiter.check("api:"+a.id(),120,60);
                    }
                    chain.doFilter(r,s);
                } catch(ApiError e) { s.setStatus(e.status); s.setContentType("application/json;charset=UTF-8"); s.getWriter().write(db.write(Errors.body(e.code,e.getMessage(),r))); }
            }
        };
        var registration=new FilterRegistrationBean<OncePerRequestFilter>(filter); registration.setOrder(-90); return registration;
    }
    public static Actor authenticate(Db db,String authorization) {
        if(authorization==null||!authorization.startsWith("Bearer ")) throw new ApiError(401,"UNAUTHENTICATED","请登录");
        var users=db.rows("SELECT u.* FROM sessions s JOIN users u ON u.id=s.user_id WHERE s.token_hash=? AND s.expires_at>now() AND u.status<>'DISABLED'",Db.hash(authorization.substring(7)));
        if(users.isEmpty()) throw new ApiError(401,"SESSION_EXPIRED","会话失效"); return Actor.from(users.getFirst());
    }
}
