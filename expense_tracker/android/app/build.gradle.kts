import java.io.File
import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    // Kotlin itself is provided by Flutter's built-in Kotlin support - do not add
    // `id("kotlin-android")` here, it deprecates the build (see the Flutter
    // "migrate to built-in Kotlin" breaking change).
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing material lives in android/key.properties (git-ignored) next to
// android/upload-keystore.p12. When either is missing - for example on a fresh
// clone - the release build falls back to the debug key so
// `flutter build apk --release` still produces a working app-release.apk.
val keystorePropertiesFile: File = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use(keystoreProperties::load)
}
val hasReleaseKeystore = keystorePropertiesFile.exists() &&
    keystoreProperties.getProperty("storeFile") != null

android {
    namespace = "com.sandeep.expense_tracker"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Unique application id; also the Kotlin/Java namespace above.
        applicationId = "com.sandeep.expense_tracker"
        // Values come from pubspec.yaml (version: 1.0.0+1).
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = File(
                    keystorePropertiesFile.parentFile,
                    keystoreProperties.getProperty("storeFile"),
                )
                storePassword = keystoreProperties.getProperty("storePassword")
                keystoreProperties.getProperty("storeType")?.let { storeType = it }
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
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
