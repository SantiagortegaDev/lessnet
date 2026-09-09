import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and
    // Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing.
//
// Reads android/key.properties for local builds, or the KEYSTORE_*
// environment variables injected by CI. With neither present the build
// still succeeds using the debug key and logs a warning — but such an
// APK must never be published: it has no stable upgrade path and
// anyone can produce one Android accepts as the same app.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

fun signingValue(key: String, env: String): String? =
    keystoreProperties.getProperty(key) ?: System.getenv(env)

val releaseStorePath: String? = signingValue("storeFile", "KEYSTORE_PATH")
val hasReleaseKeystore = !releaseStorePath.isNullOrBlank() && file(releaseStorePath).exists()

android {
    namespace = "com.lessnet.app"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Required by flutter_local_notifications for time-zone handling
        // on API levels below 26.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.lessnet.app"

        // Flutter 3.47's own baseline (24 / Android 7.0), raised from the
        // 21 this project used to pin. The Flutter tool rewrites a lower
        // value automatically because the plugin set requires it, so the
        // floor is tracked here rather than fought.
        //
        // This does drop Android 5.x and 6.0 devices. Wallpaper-based
        // dynamic colour was deliberately dropped to avoid pushing it
        // higher still; see the comment in lib/main.dart.
        minSdk = flutter.minSdkVersion
        targetSdk = 34

        // Both come from pubspec.yaml, so the version lives in exactly
        // one place instead of the three it used to.
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        multiDexEnabled = true
    }

    signingConfigs {
        create("release") {
            if (hasReleaseKeystore) {
                storeFile = file(releaseStorePath!!)
                storePassword = signingValue("storePassword", "KEYSTORE_PASSWORD")
                keyAlias = signingValue("keyAlias", "KEY_ALIAS")
                keyPassword = signingValue("keyPassword", "KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            if (hasReleaseKeystore) {
                signingConfig = signingConfigs.getByName("release")
            } else {
                logger.warn(
                    "LessNet: no release keystore found — signing with the DEBUG key. " +
                        "Do not publish this APK."
                )
                signingConfig = signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
