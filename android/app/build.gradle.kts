import java.io.FileInputStream
import java.util.Properties

val keystoreProperties = Properties()
val keyPropertiesFile = file("key.properties").takeIf { it.exists() }
    ?: rootProject.file("key.properties").takeIf { it.exists() }
    ?: file("../key.properties").takeIf { it.exists() }

if (keyPropertiesFile != null && keyPropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keyPropertiesFile))
}

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {
    namespace = "com.markazknowledgecity.cityguest"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.markazknowledgecity.cityguest"
        minSdk = 21
        targetSdk = 35
        multiDexEnabled = true
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties.getProperty("keyAlias") ?: "upload"
            keyPassword = keystoreProperties.getProperty("keyPassword") ?: "cityguest123"
            storePassword = keystoreProperties.getProperty("storePassword") ?: "cityguest123"
            storeFile = file("upload-keystore.jks").takeIf { it.exists() }
                ?: file("../upload-keystore.jks").takeIf { it.exists() }
                ?: rootProject.file("upload-keystore.jks").takeIf { it.exists() }
                ?: rootProject.file("android/app/upload-keystore.jks").takeIf { it.exists() }
        }
    }

    buildTypes {
        release {
            val relConfig = signingConfigs.getByName("release")
            if (relConfig.storeFile?.exists() == true) {
                signingConfig = relConfig
            } else {
                signingConfig = signingConfigs.getByName("debug")
            }
            isMinifyEnabled = false
            isShrinkResources = false
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
