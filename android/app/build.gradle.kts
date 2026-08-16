plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

import java.util.Properties
import java.io.FileInputStream

// Play upload signing — see docs/play_store/SIGNING.md and key.properties.example.
// Absent key.properties → release assemble/bundle tasks fail (no silent debug signing).
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
val hasReleaseKeystore = keystorePropertiesFile.exists().also { exists ->
    if (exists) {
        keystoreProperties.load(FileInputStream(keystorePropertiesFile))
    }
}

android {
    namespace = "com.allinonepos.app"
    // Bumped to 36: newer plugins (flutter_plugin_android_lifecycle via
    // file_picker 8.x) require compiling against Android API 36+.
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Required by flutter_local_notifications (uses java.time backport).
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Rebranded to All In One POS 2026-08-16 — was com.mmpos.mm_pos.
        // Do not change again without a real reason (sideload + Play installs).
        applicationId = "com.allinonepos.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            if (hasReleaseKeystore) {
                signingConfig = signingConfigs.getByName("release")
            }
            // If key.properties is missing, leave unsigned and fail in the
            // release task hook below — debug builds stay unaffected.
        }
    }
}

tasks.configureEach {
    val isReleaseArtifact =
        name.startsWith("assembleRelease") ||
            name.startsWith("bundleRelease") ||
            name.startsWith("signRelease")
    if (isReleaseArtifact) {
        doFirst {
            if (!hasReleaseKeystore) {
                throw GradleException(
                    "Missing android/key.properties — copy key.properties.example, " +
                        "create an upload keystore, then rebuild. " +
                        "See docs/play_store/SIGNING.md",
                )
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
