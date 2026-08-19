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
        subproject.extensions.configure<com.android.build.api.dsl.LibraryExtension> {
            compileSdk = 36
        }
    }
    subproject.plugins.withId("com.android.application") {
        subproject.extensions.configure<com.android.build.api.dsl.ApplicationExtension> {
            compileSdk = 36
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
