allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

subprojects {
    project.plugins.whenPluginAdded {
        if (this is com.android.build.gradle.AppPlugin) {
            project.extensions.getByType(com.android.build.gradle.AppExtension::class.java).compileSdkVersion(36)
        }
        if (this is com.android.build.gradle.LibraryPlugin) {
            project.extensions.getByType(com.android.build.gradle.LibraryExtension::class.java).compileSdkVersion(36)
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
