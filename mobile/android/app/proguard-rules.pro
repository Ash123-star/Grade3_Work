# Official aliyun_push 1.2.0 example rules, without its global -ignorewarnings.
# SDK/vendor entry points are also reached through reflection, broadcasts and JNI.
-keepattributes Signature,*Annotation*,Exceptions,InnerClasses,SourceFile,LineNumberTable
-keepclasseswithmembernames class ** { native <methods>; }
-keep class com.alibaba.** { *; }
-keep class com.aliyun.** { *; }
-keep class com.taobao.** { *; }
-keep class com.ut.** { *; }
-keep class com.ta.** { *; }
-keep class anet.** { *; }
-keep class anetwork.** { *; }
-keep class org.android.spdy.** { *; }
-keep class org.android.agoo.** { *; }
-keep class com.xiaomi.** { *; }
-keep class com.huawei.** { *; }
-keep class com.hihonor.** { *; }
-keep class com.vivo.** { *; }
-keep class com.heytap.** { *; }
-keep class com.coloros.** { *; }
-keep class com.meizu.cloud.** { *; }
-keep class com.google.firebase.** { *; }
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}
-keepclassmembers class * implements java.io.Serializable {
    static final long serialVersionUID;
    private static final java.io.ObjectStreamField[] serialPersistentFields;
    private void writeObject(java.io.ObjectOutputStream);
    private void readObject(java.io.ObjectInputStream);
    java.lang.Object writeReplace();
    java.lang.Object readResolve();
}

# Optional Huawei system extensions / analytics and updater integrations. HMS checks
# availability at runtime; these classes are not distributed in a normal Android SDK.
-dontwarn com.huawei.android.os.BuildEx$VERSION
-dontwarn com.huawei.hianalytics.process.HiAnalyticsConfig$Builder
-dontwarn com.huawei.hianalytics.process.HiAnalyticsConfig
-dontwarn com.huawei.hianalytics.process.HiAnalyticsInstance$Builder
-dontwarn com.huawei.hianalytics.process.HiAnalyticsInstance
-dontwarn com.huawei.hianalytics.process.HiAnalyticsManager
-dontwarn com.huawei.hianalytics.util.HiAnalyticTools
-dontwarn com.huawei.hms.availableupdate.UpdateAdapterMgr
-dontwarn com.huawei.libcore.io.ExternalStorageFile
-dontwarn com.huawei.libcore.io.ExternalStorageFileInputStream
-dontwarn com.huawei.libcore.io.ExternalStorageFileOutputStream
-dontwarn com.huawei.libcore.io.ExternalStorageRandomAccessFile

# Optional anet ping diagnostics; the push transport does not require netutil.
-dontwarn org.android.netutil.PingEntry
-dontwarn org.android.netutil.PingResponse
-dontwarn org.android.netutil.PingTask
-dontwarn org.android.netutil.NetUtils

# networksdk 3.6.0-open probes these optional Taobao integrations with Class.forName
# and availability flags; retain its stock transport, logging and cache fallbacks.
-dontwarn com.alibaba.mtl.appmonitor.AppMonitor$Alarm
-dontwarn com.alibaba.mtl.appmonitor.AppMonitor$Counter
-dontwarn com.alibaba.mtl.appmonitor.AppMonitor$Stat
-dontwarn com.alibaba.mtl.appmonitor.AppMonitor
-dontwarn com.alibaba.mtl.appmonitor.model.DimensionSet
-dontwarn com.alibaba.mtl.appmonitor.model.DimensionValueSet
-dontwarn com.alibaba.mtl.appmonitor.model.Measure
-dontwarn com.alibaba.mtl.appmonitor.model.MeasureSet
-dontwarn com.alibaba.mtl.appmonitor.model.MeasureValueSet
-dontwarn com.alibaba.wireless.security.open.SecurityGuardManager
-dontwarn com.alibaba.wireless.security.open.SecurityGuardParamContext
-dontwarn com.alibaba.wireless.security.open.dynamicdatastore.IDynamicDataStoreComponent
-dontwarn com.alibaba.wireless.security.open.securesignature.ISecureSignatureComponent
-dontwarn com.alibaba.wireless.security.open.staticdataencrypt.IStaticDataEncryptComponent
-dontwarn com.taobao.alivfssdk.cache.AVFSCache
-dontwarn com.taobao.alivfssdk.cache.AVFSCacheConfig
-dontwarn com.taobao.alivfssdk.cache.AVFSCacheManager
-dontwarn com.taobao.alivfssdk.cache.IAVFSCache$OnAllObjectRemoveCallback
-dontwarn com.taobao.alivfssdk.cache.IAVFSCache$OnObjectRemoveCallback
-dontwarn com.taobao.alivfssdk.cache.IAVFSCache$OnObjectSetCallback
-dontwarn com.taobao.alivfssdk.cache.IAVFSCache
-dontwarn com.taobao.analysis.FlowCenter
-dontwarn com.taobao.analysis.abtest.ABTestCenter
-dontwarn com.taobao.analysis.fulltrace.FullTraceAnalysis
-dontwarn com.taobao.analysis.fulltrace.RequestInfo
-dontwarn com.taobao.analysis.scene.SceneIdentifier
-dontwarn com.taobao.orange.OrangeConfig
-dontwarn com.taobao.orange.OrangeConfigListenerV1

# The optional Taobao adapter is invoked through Method.invoke. NetworkSdkSetting
# catches InvocationTargetException; missing Tlog preserves the default logger
# and allows Monitor/SessionCenter initialization to continue.
-dontwarn com.taobao.tlog.adapter.AdapterForTLog

# Huawei security-encrypt 1.3.0.301 defaults to java.security.SecureRandom and
# catches a missing BC provider before returning that platform implementation.
-dontwarn org.bouncycastle.crypto.BlockCipher
-dontwarn org.bouncycastle.crypto.engines.AESEngine
-dontwarn org.bouncycastle.crypto.prng.SP800SecureRandom
-dontwarn org.bouncycastle.crypto.prng.SP800SecureRandomBuilder
