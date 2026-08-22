import java.io.FileInputStream
import java.util.Properties

val keystoreProperties = Properties()
val keyPropertiesFile = file("key.properties").takeIf { it.exists() }
    ?: rootProject.file("key.properties").takeIf { it.exists() }
    ?: file("../key.properties").takeIf { it.exists() }

if (keyPropertiesFile != null) {
    keystoreProperties.load(FileInputStream(keyPropertiesFile))
}

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.markazknowledgecity.cityguest"
    compileSdk = 35
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.markazknowledgecity.cityguest"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        multiDexEnabled = true
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            val alias = keystoreProperties.getProperty("keyAlias") ?: "upload"
            val pass = keystoreProperties.getProperty("keyPassword") ?: "cityguest123"
            val storePass = keystoreProperties.getProperty("storePassword") ?: "cityguest123"
            val storeFilePath = keystoreProperties.getProperty("storeFile") ?: "upload-keystore.jks"

            val ksFile = file(storeFilePath).takeIf { it.exists() }
                ?: file("upload-keystore.jks").takeIf { it.exists() }
                ?: rootProject.file("upload-keystore.jks").takeIf { it.exists() }
                ?: file("../upload-keystore.jks").takeIf { it.exists() }
                ?: file("app/upload-keystore.jks").takeIf { it.exists() }

            keyAlias = alias
            keyPassword = pass
            storePassword = storePass
            storeFile = ksFile ?: file("upload-keystore.jks")
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
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
