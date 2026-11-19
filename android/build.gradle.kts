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
    
    afterEvaluate {
        if (project.hasProperty("android")) {
            val android = project.extensions.getByName("android") as? com.android.build.gradle.BaseExtension
            android?.apply {
                compileOptions {
                    sourceCompatibility = JavaVersion.VERSION_17
                    targetCompatibility = JavaVersion.VERSION_17
                }
                // Plugins with native code (jni) ask for Flutter's default NDK and AGP's default CMake: build them
                // with the app's ones, so the build needs a single NDK and CMake (the ones CI's runner image ships,
                // wiki/components/ci.md)
                if (project.path != ":app") {
                    val app = project(":app").extensions.getByName("android") as com.android.build.gradle.BaseExtension
                    ndkVersion = app.ndkVersion
                    if (externalNativeBuild.cmake.path != null) {
                        externalNativeBuild.cmake.version = app.externalNativeBuild.cmake.version
                    }
                }
            }
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
