pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            val localPropertiesFile = file("local.properties")
            if (localPropertiesFile.exists()) {
                localPropertiesFile.inputStream().use { properties.load(it) }
            }
            var path = properties.getProperty("flutter.sdk")
            if (path.isNullOrBlank()) {
                path = System.getenv("FLUTTER_ROOT")
                    ?: System.getenv("FLUTTER_HOME")
                    ?: System.getenv("FLUTTER_PATH")
            }
            require(!path.isNullOrBlank()) { "flutter.sdk not set in local.properties nor FLUTTER_ROOT" }
            path
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        gradlePluginPortal()
        mavenCentral()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.9.1" apply false
    id("org.jetbrains.kotlin.android") version "2.1.0" apply false
}

include(":app")
