package cn.pandora.pandora_mobile

import android.app.Application
import android.os.Looper
import com.alibaba.sdk.android.push.CloudPushService
import com.alibaba.sdk.android.push.noonesdk.PushInitConfig
import com.alibaba.sdk.android.push.noonesdk.PushServiceFactory

/** Initializes every SDK process without registering a device before the user's opt-in. */
class PandoraApplication : Application() {
    private var pushSdkInitialized = false

    override fun onCreate() {
        super.onCreate()
        // The SDK's channel service can cold-start its own process without an Activity.
        if (getSharedPreferences(PUSH_CONSENT, MODE_PRIVATE).getBoolean(AGREED, false)) {
            try {
                initializePushSdk()
            } catch (_: Exception) {
                // A later explicit registration can retry; never log application identifiers.
            }
        }
    }

    fun initializePushAfterConsent(): CloudPushService {
        check(Looper.myLooper() == Looper.getMainLooper())
        check(pushConfigured())
        // Persist before init can start the channel process, whose Application reads this gate.
        check(getSharedPreferences(PUSH_CONSENT, MODE_PRIVATE).edit().putBoolean(AGREED, true).commit())
        initializePushSdk()
        return PushServiceFactory.getCloudPushService()
    }

    fun revokePushConsent() {
        getSharedPreferences(PUSH_CONSENT, MODE_PRIVATE).edit().putBoolean(AGREED, false).apply()
    }

    private fun pushConfigured() =
        getString(R.string.pandora_push_app_key).isNotBlank() &&
            getString(R.string.pandora_push_app_secret).isNotBlank()

    private fun initializePushSdk() {
        check(Looper.myLooper() == Looper.getMainLooper())
        if (pushSdkInitialized || !pushConfigured()) return
        PushServiceFactory.init(
            PushInitConfig.Builder()
                .application(this)
                .appKey(getString(R.string.pandora_push_app_key))
                .appSecret(getString(R.string.pandora_push_app_secret))
                .build()
        )
        PushServiceFactory.getCloudPushService().setLogLevel(CloudPushService.LOG_OFF)
        pushSdkInitialized = true
    }

    private companion object {
        const val PUSH_CONSENT = "push_sdk_consent"
        const val AGREED = "agreed"
    }
}
