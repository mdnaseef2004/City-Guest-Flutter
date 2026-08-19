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
    val subproject = this
    subproject.plugins.withId("com.android.library") {
        val android = subproject.extensions.getByType(com.android.build.gradle.LibraryExtension::class.java)
        android.compileSdkVersion(36)
    }
    subproject.plugins.withId("com.android.application") {
        val android = subproject.extensions.getByType(com.android.build.gradle.AppExtension::class.java)
        android.compileSdkVersion(36)
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
