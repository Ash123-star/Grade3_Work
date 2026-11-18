plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "cn.pandora.pandora_mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "cn.pandora.pandora_mobile"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // EMAS application identifiers only; never put RAM AccessKey credentials in this APK.
        val pushConfig = listOf("app_key", "app_secret", "huawei_id", "honor_id", "vivo_id", "vivo_key", "oppo_key", "oppo_secret", "xiaomi_id", "xiaomi_key", "meizu_id", "meizu_key")
        for (key in pushConfig) {
            val raw = providers.gradleProperty("pandora.push.$key").orElse(providers.environmentVariable("PANDORA_PUSH_${key.uppercase()}" )).getOrElse("")
            // HMS manifest metadata requires appid=<id>; accept the numeric console value too.
            val value = if (key == "huawei_id" && raw.matches(Regex("[0-9]+"))) "appid=$raw" else raw
            if (key == "huawei_id" && value.isNotBlank()) {
                require(value.matches(Regex("appid=[0-9]+"))) { "Huawei App ID must be numeric or appid=<numeric ID>" }
            }
            resValue("string", "pandora_push_$key", value)
        }

    }

    buildTypes {
        release {
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Keep the SDK's WebView certificate checker and Tika XML error types available.
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("javax.xml.stream:stax-api:1.0-2")
}
