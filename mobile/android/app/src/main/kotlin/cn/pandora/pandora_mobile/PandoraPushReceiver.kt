package cn.pandora.pandora_mobile

import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import com.alibaba.sdk.android.push.MessageReceiver
import com.alibaba.sdk.android.push.AndroidPopupActivity
import com.alibaba.sdk.android.push.notification.CPushMessage

// No singleton Flutter plugin callback: a click may start a completely cold process.
class PandoraPushReceiver : MessageReceiver() {
    override fun onNotification(context: Context, title: String?, summary: String?, extraMap: MutableMap<String, String>?) {}
    override fun onMessage(context: Context, message: CPushMessage?) {}
    override fun onNotificationRemoved(context: Context, messageId: String?) {}
    override fun onNotificationReceivedInApp(context: Context, title: String?, summary: String?, extraMap: MutableMap<String, String>?, openType: Int, openActivity: String?, openUrl: String?) {}
    override fun onNotificationOpened(context: Context, title: String?, summary: String?, extras: String?) { parseOpen(context, extras) }
    override fun onNotificationClickedWithNoAction(context: Context, title: String?, summary: String?, extras: String?) {
        parseOpen(context, extras)
    }
    private fun parseOpen(context: Context, extras: String?) {
        try {
            val json = org.json.JSONObject(extras ?: "{}")
            PushOpens.open(context, mutableMapOf("notificationId" to json.optString("notificationId"), "binding" to json.optString("binding")))
        } catch (_: Exception) { }
    }
}
class PushPopupActivity : AndroidPopupActivity() {
    override fun onSysNoticeOpened(title: String?, summary: String?, extraMap: MutableMap<String, String>?) { PushOpens.open(this, extraMap); finish() }
}
object PushOpens {
    fun open(context: Context, extras: Map<String, String>?) {
        val id = extras?.get("notificationId") ?: return
        val binding = extras["binding"] ?: return
        val uuid = Regex("[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}")
        if (!uuid.matches(id) || !uuid.matches(binding)) return
        context.getSharedPreferences("push_open", Context.MODE_PRIVATE).edit().putString("notificationId", id).putString("binding", binding).apply()
        context.startActivity(Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP))
        Handler(Looper.getMainLooper()).post { MainActivity.pushChannel?.invokeMethod("opened", null) }
    }
}
