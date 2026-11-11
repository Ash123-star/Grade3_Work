package cn.workpanel.storage;

import cn.workpanel.ApiError;
import cn.workpanel.module.attachment.application.*;
import cn.workpanel.module.attachment.infrastructure.*;
import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;

class StoragePolicyTest {
    @Test void privateKeysCannotEscapeConfiguredPrefix(){try(var storage=new AliyunObjectStorage(new OssSettings(null,null,null,null,null,null,null,null))){
        assertEquals("workpanel/business/company/id",storage.key("business/company/id"));
        for(String path:new String[]{"../x","a/../x","a//x","/x","a\\x","a/%2e/x"})assertThrows(IllegalArgumentException.class,()->storage.key(path));
    }}
    @Test void endpointAndSettingsNeverExposeCredentials(){var settings=new OssSettings(null,null,null,null,"secret-id","secret-value",null,null);assertFalse(settings.toString().contains("secret"));assertThrows(IllegalArgumentException.class,()->new OssSettings(null,null,"http://example.org",null,null,null,null,null));}
    @Test void integrityAndPublicPathRulesRejectInvalidInput(){assertThrows(ApiError.class,()->BinaryFiles.verify(new byte[]{1},2,"bad"));for(String path:new String[]{"business/x","assets/../business/x","assets/%2e%2e/x","assets//x","/assets/x"})assertThrows(ApiError.class,()->AssetCatalog.validPath(path));assertDoesNotThrow(()->AssetCatalog.validPath("assets/icons/a.png"));}
}
