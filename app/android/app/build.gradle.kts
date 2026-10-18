import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing: the keystore + its password live OUTSIDE the repo at
// %USERPROFILE%\.android\star-codex-key.properties (v1.0.0 baseline —
// BACK THAT FILE UP; losing it means no update-over-install ever again).
// If the properties file is absent, release falls back to debug signing
// so dev machines without the keystore keep building.
val releaseKeystore = Properties().apply {
    val userHome = System.getenv("USERPROFILE") ?: System.getProperty("user.home") ?: "."
    val f = File(userHome, ".android").resolve("star-codex-key.properties")
    if (f.isFile) f.inputStream().use { load(it) }
}
val hasReleaseKeystore = releaseKeystore.getProperty("storeFile") != null

android {
    namespace = "com.jamej.starcodex"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.jamej.starcodex"
        // Plan/01 §4: raise minSdk to 23 (flutter_image_compress WebP + modern TLS).
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-apk-splits)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                storeFile = File(releaseKeystore.getProperty("storeFile"))
                storePassword = releaseKeystore.getProperty("storePassword")
                keyAlias = releaseKeystore.getProperty("keyAlias")
                keyPassword = releaseKeystore.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKeystore)
                signingConfigs.getByName("release")
            else
                signingConfigs.getByName("debug")
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
