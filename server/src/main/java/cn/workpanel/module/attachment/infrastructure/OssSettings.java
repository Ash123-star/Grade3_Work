package cn.workpanel.module.attachment.infrastructure;

import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties("app.oss")
public record OssSettings(String bucket, String region, String endpoint, String prefix,
                          String accessKeyId, String accessKeySecret, String securityToken, String roleName) {
    public OssSettings {
        bucket = value(bucket,"panduola-work"); region = value(region,"cn-beijing");
        endpoint = value(endpoint,"https://oss-cn-beijing.aliyuncs.com"); prefix = value(prefix,"workpanel");
        if (!endpoint.matches("https://oss-[a-z0-9-]+(?:-internal)?\\.aliyuncs\\.com"))
            throw new IllegalArgumentException("OSS endpoint must be an HTTPS Alibaba Cloud endpoint");
        if (!bucket.matches("[a-z0-9][a-z0-9-]{1,61}[a-z0-9]") || !prefix.matches("[a-zA-Z0-9_-]+(?:/[a-zA-Z0-9_-]+)*"))
            throw new IllegalArgumentException("Invalid OSS bucket or prefix");
    }
    private static String value(String s,String fallback){return s==null||s.isBlank()?fallback:s;}
    @Override public String toString(){return "OssSettings[bucket="+bucket+",region="+region+",credentials=REDACTED]";}
}
