package cn.workpanel.module.attachment.controller;

import cn.workpanel.module.attachment.application.AssetCatalog;
import org.springframework.http.*;
import org.springframework.web.bind.annotation.*;
import java.util.Map;

/** v1公共产品素材，不提供任何业务文件入口；仅允许部署发布的白名单。 */
@RestController
@RequestMapping("/api/assets")
public class AssetController {
    private final AssetCatalog catalog;
    public AssetController(AssetCatalog catalog){this.catalog=catalog;}
    /** 当前完整发布清单。公开只读、无参数/幂等/业务版本；ETag支持304，无发布404。 */
    @GetMapping("/manifest")public ResponseEntity<Map<String,Object>> manifest(@RequestHeader(value="If-None-Match",required=false)String match){var m=catalog.current();String tag="\""+m.hash()+"\"";return ResponseEntity.status(tag.equals(match)?304:200).eTag(tag).cacheControl(CacheControl.noCache()).body(tag.equals(match)?null:m.body());}
    /** 指定release和逻辑path的静态对象。公开只读，禁止任意Key/URL；404非法或未发布路径、502完整性错、503存储失败；按不可变发布版本缓存。 */
    @GetMapping("/{release}/{*path}")public ResponseEntity<byte[]> file(@PathVariable String release,@PathVariable String path){
        var file=catalog.file(release,path.startsWith("/")?path.substring(1):path);
        return ResponseEntity.ok().contentType(MediaType.parseMediaType(file.mime())).eTag("\""+file.hash()+"\"").cacheControl(CacheControl.maxAge(java.time.Duration.ofDays(365)).cachePublic().immutable()).header("X-Content-Type-Options","nosniff").header("Content-Security-Policy","default-src 'none'; sandbox").body(file.bytes());
    }
}
