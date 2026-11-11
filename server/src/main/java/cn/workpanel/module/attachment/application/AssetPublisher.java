package cn.workpanel.module.attachment.application;

import cn.workpanel.*;
import cn.workpanel.module.attachment.infrastructure.ObjectStorage;
import org.springframework.transaction.support.TransactionTemplate;
import java.nio.file.*;
import java.io.IOException;
import java.util.*;

/** 仅由部署工具调用；完整上传并逐字节核对后才激活，普通业务接口无法发布。 */
public final class AssetPublisher {
    private final Db db;private final ObjectStorage storage;private final TransactionTemplate tx;
    public AssetPublisher(Db db,ObjectStorage storage,TransactionTemplate tx){this.db=db;this.storage=storage;this.tx=tx;}
    public static Map<String,Object> inventory(Path root,String release)throws IOException{
        if(!release.matches("[a-zA-Z0-9_-]{1,80}"))throw new IllegalArgumentException("Invalid release");
        root=root.toRealPath();var entries=new ArrayList<Map<String,Object>>();
        collect(root,root.resolve("mobile/assets"),"assets/",false,entries);
        collect(root,root.resolve("mobile/android/app/src/main/res"),"native/",true,entries);
        collect(root,root.resolve("web/public"),"web/",false,entries);
        collect(root,root.resolve("web/src/assets"),"web/src/assets/",false,entries);
        Path prepared=root.resolve("output/oss/flutter-assets");
        if(Files.exists(root.resolve("mobile/pubspec.yaml"))&&!Files.isRegularFile(prepared.resolve("fonts/FontManifest.json")))throw new IllegalArgumentException("Prepare the complete Flutter runtime assets with scripts/prepare-oss-assets.ps1 first");
        collect(root,prepared.resolve("fonts"),"fonts/",false,entries);
        collect(root,prepared.resolve("packages"),"packages/",false,entries);
        entries.sort(Comparator.comparing(e->Db.str(e,"path")));
        if(entries.isEmpty())throw new IllegalArgumentException("No assets found");
        var manifest=new LinkedHashMap<String,Object>();manifest.put("release",release);manifest.put("items",entries);manifest.put("count",entries.size());manifest.put("bytes",entries.stream().mapToLong(e->((Number)e.get("size")).longValue()).sum());return manifest;
    }
    private static void collect(Path root,Path directory,String prefix,boolean nativeOnly,List<Map<String,Object>> entries)throws IOException{
        if(!Files.isDirectory(directory))return;
        try(var walk=Files.walk(directory)){
            for(Path file:walk.sorted().toList()){
                if(Files.isSymbolicLink(file)||!file.toRealPath().startsWith(root))throw new IllegalArgumentException("Asset path escapes source root");
                if(!Files.isRegularFile(file))continue;
                String name=file.getFileName().toString().toLowerCase(Locale.ROOT),mime=mime(name);
                if(mime==null){if(!nativeOnly)throw new IllegalArgumentException("Unsupported asset type: "+name);continue;}
                if(nativeOnly&&!mime.startsWith("image/"))continue;
                long size=Files.size(file);if(size==0||size>100L*1024*1024)throw new IllegalArgumentException("Invalid asset size: "+name);
                String logical=prefix+directory.relativize(file).toString().replace('\\','/');AssetCatalog.validPath(logical);
                var item=new LinkedHashMap<String,Object>();item.put("path",logical);item.put("size",size);item.put("hash",AttachmentApplicationService.hash(Files.readAllBytes(file)));item.put("mime",mime);
                item.put("mode",nativeOnly?"native-copy":"runtime");item.put("source","Repository resource; copyright and attribution: assets/licenses");entries.add(item);
            }
        }
    }
    private static String mime(String name){if(Set.of("license","ofl","notice","copying").contains(name))return "text/plain;charset=UTF-8";int dot=name.lastIndexOf('.');return switch(dot<0?"":name.substring(dot+1)){
        case "png"->"image/png";case "jpg","jpeg"->"image/jpeg";case "webp"->"image/webp";case "gif"->"image/gif";case "svg"->"image/svg+xml";
        case "ttf"->"font/ttf";case "ttc"->"font/collection";case "otf"->"font/otf";case "woff"->"font/woff";case "woff2"->"font/woff2";case "txt","md"->"text/plain;charset=UTF-8";case "json"->"application/json";default->null;};}
    public void publish(Path root,Map<String,Object> manifest){
        String release=Db.str(manifest,"release"),hash=Db.hash(db.write(manifest));long version=((Number)db.one("SELECT version FROM asset_current WHERE id=1").get("version")).longValue();
        var old=db.rows("SELECT manifest_hash FROM asset_releases WHERE id=?",release);if(!old.isEmpty()&&!hash.equals(old.getFirst().get("manifest_hash")))throw ApiError.conflict();
        for(var item:AssetCatalog.items(manifest)){
            String logical=Db.str(item,"path");AssetCatalog.validPath(logical);Path file=source(root,logical);
            try{byte[] bytes=Files.readAllBytes(file);BinaryFiles.verify(bytes,((Number)item.get("size")).longValue(),Db.str(item,"hash"));
                String key=storage.key("static/"+release+"/"+item.get("hash")+"/"+logical);storage.put(key,bytes,Db.str(item,"mime"));BinaryFiles.verify(storage.get(key,bytes.length),bytes.length,Db.str(item,"hash"));
            }catch(IOException e){throw new IllegalArgumentException("Asset could not be read");}
        }
        tx.executeWithoutResult(s->{db.update("INSERT INTO asset_releases(id,manifest,manifest_hash) VALUES (?,?::jsonb,?) ON CONFLICT DO NOTHING",release,db.write(manifest),hash);
            if(!hash.equals(db.one("SELECT manifest_hash FROM asset_releases WHERE id=?",release).get("manifest_hash")))throw ApiError.conflict();
            Db.conflict(db.update("UPDATE asset_current SET release_id=?,version=version+1 WHERE id=1 AND version=?",release,version));});
    }
    private static Path source(Path root,String path){
        Path candidate=path.startsWith("assets/")?root.resolve("mobile").resolve(path):path.startsWith("native/")?root.resolve("mobile/android/app/src/main/res").resolve(path.substring(7)):path.startsWith("fonts/")||path.startsWith("packages/")?root.resolve("output/oss/flutter-assets").resolve(path):path.startsWith("web/src/assets/")?root.resolve(path):root.resolve("web/public").resolve(path.substring(4));
        try{Path real=candidate.toRealPath();if(!real.startsWith(root.toRealPath())||Files.isSymbolicLink(candidate))throw new IllegalArgumentException("Invalid asset source");return real;}catch(IOException e){throw new IllegalArgumentException("Invalid asset source");}
    }
}
