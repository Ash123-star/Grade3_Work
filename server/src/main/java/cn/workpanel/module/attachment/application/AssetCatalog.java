package cn.workpanel.module.attachment.application;

import cn.workpanel.*;
import cn.workpanel.module.attachment.infrastructure.ObjectStorage;
import org.springframework.stereotype.Service;
import java.util.*;

/** 产品静态白名单；路径只能来自已完成发布的manifest，不接受任意OSS Key。 */
@Service
public class AssetCatalog {
    private final Db db;private final ObjectStorage storage;
    public AssetCatalog(Db db,ObjectStorage storage){this.db=db;this.storage=storage;}
    public record Manifest(Map<String,Object> body,String hash){}
    public record File(byte[] bytes,String mime,String hash){}
    public Manifest current(){var row=db.one("SELECT r.* FROM asset_current c JOIN asset_releases r ON r.id=c.release_id WHERE c.id=1");return new Manifest(db.read(row.get("manifest")),Db.str(row,"manifest_hash"));}
    public File file(String release,String path){
        validPath(path);if(!release.matches("[a-zA-Z0-9_-]{1,80}"))throw ApiError.notFound();
        var row=db.one("SELECT manifest FROM asset_releases WHERE id=?",release);var manifest=db.read(row.get("manifest"));
        for(var item:items(manifest)){if(!path.equals(item.get("path")))continue;
            String hash=Db.str(item,"hash"),mime=Db.str(item,"mime");long size=((Number)item.get("size")).longValue();
            byte[] bytes=storage.get(storage.key("static/"+release+"/"+hash+"/"+path),size);BinaryFiles.verify(bytes,size,hash);return new File(bytes,mime,hash);
        }throw ApiError.notFound();
    }
    public static void validPath(String path){if(path==null||path.length()>500||path.contains("\\")||path.contains("%")||path.startsWith("/")||Arrays.stream(path.split("/",-1)).anyMatch(p->p.isBlank()||p.equals(".")||p.equals(".."))||!(path.startsWith("assets/")||path.startsWith("native/")||path.startsWith("web/")||path.startsWith("fonts/")||path.startsWith("packages/")))throw ApiError.notFound();}
    public static List<Map<String,Object>> items(Map<String,Object> manifest){if(!(manifest.get("items") instanceof List<?> entries))throw ApiError.notFound();return entries.stream().map(o->{@SuppressWarnings("unchecked")var item=(Map<String,Object>)o;return item;}).toList();}
}
