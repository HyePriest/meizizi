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
    // Keep plugins on the already installed SDK instead of fetching API 35.
    plugins.withId("com.android.library") {
        extensions.getByType<com.android.build.api.variant.LibraryAndroidComponentsExtension>()
            .finalizeDsl {
                it.compileSdk = 36
                it.externalNativeBuild.cmake.version = "3.22.1"
            }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
