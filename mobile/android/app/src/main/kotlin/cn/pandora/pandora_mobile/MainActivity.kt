package cn.pandora.pandora_mobile

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Notification
import android.content.pm.PackageManager
import android.os.Build
import com.alibaba.sdk.android.push.CommonCallback
import com.aliyun.ams.push.AliyunThirdPushUtils
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var permissionResult: MethodChannel.Result? = null
    companion object { var pushChannel: MethodChannel? = null; private var pushInitialized = false }
    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        val channel = MethodChannel(engine.dartExecutor.binaryMessenger, "pandora/push")
        pushChannel = channel
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "configured" -> result.success(getString(R.string.pandora_push_app_key).isNotBlank() && getString(R.string.pandora_push_app_secret).isNotBlank())
                "initialize" -> initializePush(result)
                "channels" -> {
                    if (Build.VERSION.SDK_INT >= 26) {
                        val manager = getSystemService(NotificationManager::class.java)
                        for ((key, name) in mapOf("tasks" to "任务动态", "deadlines" to "截止提醒", "reviews" to "审批与入职结果")) {
                            val c = NotificationChannel("pandora_$key", name, NotificationManager.IMPORTANCE_DEFAULT)
                            c.lockscreenVisibility = Notification.VISIBILITY_PRIVATE
                            manager.createNotificationChannel(c)
                        }
                    }
                    result.success(null)
                }
                "status" -> result.success(Build.VERSION.SDK_INT < 24 || getSystemService(NotificationManager::class.java).areNotificationsEnabled())
                "settings" -> {
                    val intent = if (Build.VERSION.SDK_INT >= 26) android.content.Intent(android.provider.Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(android.provider.Settings.EXTRA_APP_PACKAGE, packageName)
                        else android.content.Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS, android.net.Uri.parse("package:$packageName"))
                    startActivity(intent); result.success(null)
                }
                "requestPermission" -> {
                    if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                        if (permissionResult != null) result.error("BUSY", "通知权限请求处理中", null)
                        else { permissionResult = result; requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 6401) }
                    } else result.success(Build.VERSION.SDK_INT < 24 || getSystemService(NotificationManager::class.java).areNotificationsEnabled())
                }
                "drainOpen" -> {
                    val prefs = getSharedPreferences("push_open", MODE_PRIVATE)
                    val id = prefs.getString("notificationId", null)
                    val binding = prefs.getString("binding", null)
                    prefs.edit().clear().apply()
                    result.success(if (id != null && binding != null) mapOf("notificationId" to id, "binding" to binding) else null)
                }
                "clear" -> {
                    getSystemService(NotificationManager::class.java).cancelAll()
                    if (call.argument<Boolean>("discardOpen") == true) {
                        getSharedPreferences("push_open", MODE_PRIVATE).edit().clear().apply()
                        (application as PandoraApplication).revokePushConsent()
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
    // Flutter only invokes this after its enabled/configured/system-permission checks.
    // Application owns SDK initialization in both the app and the cold channel process.
    private fun initializePush(result: MethodChannel.Result) {
        val key = getString(R.string.pandora_push_app_key)
        val secret = getString(R.string.pandora_push_app_secret)
        if (key.isBlank() || secret.isBlank()) { result.error("NOT_CONFIGURED", "移动推送尚未配置", null); return }
        try {
            val service = (application as PandoraApplication).initializePushAfterConsent()
            if (pushInitialized) { result.success(service.deviceId); return }
            service.register(applicationContext, object : CommonCallback {
                override fun onSuccess(response: String?) {
                    runOnUiThread {
                        try {
                            AliyunThirdPushUtils.registerHuaweiPush(application)
                            AliyunThirdPushUtils.registerXiaoMiPush(application)
                            AliyunThirdPushUtils.registerVivoPush(application)
                            AliyunThirdPushUtils.registerOppoPush(application)
                            AliyunThirdPushUtils.registerMeizuPush(application)
                            AliyunThirdPushUtils.registerHonorPush(application)
                            pushInitialized = true
                            result.success(service.deviceId)
                        } catch (_: Exception) { result.error("INITIALIZE_FAILED", "推送服务连接失败，请稍后重试", null) }
                    }
                }
                override fun onFailed(code: String?, message: String?) { runOnUiThread { result.error("REGISTER_FAILED", "推送服务连接失败，请稍后重试", null) } }
            })
        } catch (_: Exception) { result.error("INITIALIZE_FAILED", "推送服务连接失败，请稍后重试", null) }
    }
    override fun onRequestPermissionsResult(code: Int, permissions: Array<out String>, grants: IntArray) {
        super.onRequestPermissionsResult(code, permissions, grants)
        if (code == 6401) { permissionResult?.success(grants.isNotEmpty() && grants[0] == PackageManager.PERMISSION_GRANTED); permissionResult = null }
    }
    override fun cleanUpFlutterEngine(engine: FlutterEngine) { pushChannel = null; super.cleanUpFlutterEngine(engine) }
}
