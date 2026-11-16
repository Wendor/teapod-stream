plugins {
    id("com.android.library") version "8.7.3"
    id("org.jetbrains.kotlin.android") version "2.1.0"
}

android {
    namespace = "com.teapodstream.tun2socks"
    compileSdk = 29

    defaultConfig {
        minSdk = 29

        // ProGuard rules for library consumers
        consumerProguardFiles("proguard-rules.pro")
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            consumerProguardFiles("proguard-rules.pro")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }

    kotlinOptions {
        jvmTarget = "1.8"
    }
}

dependencies {
    // The generated Go AAR — built by ./build.sh from the project root.
    // compileOnly is used for compilation (the Kotlin code uses Go classes)
    compileOnly(files("../output/teapod-tun2socks.aar"))

    implementation("androidx.annotation:annotation:1.9.1")
}

// Directory for JNI libraries from the Go AAR
val jniLibsDir = layout.buildDirectory.dir("generated/jniLibs")

// Task that extracts .so files from the Go AAR
tasks.register<Copy>("extractGoNativeLibs") {
    val goAarFile = file("../output/teapod-tun2socks.aar")
    val targetArch = project.findProperty("targetArch") as? String
    
    // A closure defers evaluating zipTree
    from(provider { zipTree(goAarFile) }) {
        if (!targetArch.isNullOrBlank()) {
            include("jni/$targetArch/**/*.so")
        } else {
            include("jni/**/*.so")
        }
    }
    into(jniLibsDir)
    
    onlyIf { goAarFile.exists() }
}

// Configure JNI source sets so the .so files end up in the AAR
android.sourceSets.getByName("main") {
    jniLibs.srcDir(jniLibsDir)
}

// Make sure JNI libraries are extracted before the build
tasks.configureEach {
    if (name.startsWith("merge") && name.contains("JniLibFolders")) {
        dependsOn("extractGoNativeLibs")
    }
}

// Task that creates the final fat AAR
tasks.register("assembleFatAar") {
    dependsOn("assembleRelease")
    
    doLast {
        // Read the target architecture from the parameters (if any)
        val targetArch = project.findProperty("targetArch") as? String
        
        // Look for the AAR file in outputs/aar/
        val aarDir = layout.buildDirectory.dir("outputs/aar").get().asFile
        val kotlinAarFile = aarDir.listFiles()?.find { it.name.endsWith("-release.aar") }
            ?: throw GradleException("Kotlin AAR file not found in ${aarDir.absolutePath}")
            
        val goAarFile = file("../output/teapod-tun2socks.aar")
        if (!goAarFile.exists()) {
            throw GradleException("Go AAR file not found at ${goAarFile.absolutePath}")
        }
        
        val outputDir = layout.buildDirectory.dir("outputs/fat-aar").get().asFile
        
        // Read the library version
        val libVersion = project.findProperty("libraryVersion") as? String ?: "1.0.0"
        
        // The output file name depends on the version and architecture
        val baseName = "teapod-tun2socks"
        val outputFileName = if (targetArch.isNullOrBlank()) "$baseName-$libVersion.aar" else "$baseName-$targetArch-$libVersion.aar"
        val fatAarFile = file("${outputDir}/$outputFileName")
        val tempDir = file("${outputDir}/temp-${targetArch ?: "universal"}")
        
        // Clean the temporary directory
        tempDir.deleteRecursively()
        tempDir.mkdirs()
        
        println("📦 Building AAR v$libVersion for ${targetArch ?: "all architectures"}...")
        println("   Kotlin AAR: ${kotlinAarFile.name}")
        println("   Go AAR: ${goAarFile.name}")
        
        // 1. Unpack the Kotlin AAR
        copy {
            from(zipTree(kotlinAarFile))
            into(tempDir)
        }
        
        // 2. Merge the Go classes
        val goClassesJar = zipTree(goAarFile).matching { include("classes.jar") }.singleFile
        val kotlinClassesJar = zipTree(kotlinAarFile).matching { include("classes.jar") }.singleFile
        
        // Unpack the Go classes
        val goClassesDir = file("${tempDir}/go-classes")
        goClassesDir.mkdirs()
        copy {
            from(zipTree(goClassesJar))
            into(goClassesDir)
        }
        
        // Unpack the Kotlin classes
        val kotlinClassesDir = file("${tempDir}/kotlin-classes")
        kotlinClassesDir.mkdirs()
        copy {
            from(zipTree(kotlinClassesJar))
            into(kotlinClassesDir)
        }
        
        // Delete the old classes.jar
        file("${tempDir}/classes.jar").delete()
        
        // Create the merged classes.jar
        val mergedClassesDir = file("${tempDir}/merged-classes")
        mergedClassesDir.mkdirs()
        
        // Copy all classes (Go + Kotlin)
        copy {
            from(goClassesDir, kotlinClassesDir)
            into(mergedClassesDir)
        }
        
        // Create the JAR with the jar command (must be on PATH)
        exec {
            workingDir(mergedClassesDir)
            commandLine("jar", "cf", "${tempDir}/classes.jar", ".")
        }
        
        // Copy JNI libraries from the Go AAR (filtering by architecture if needed)
        copy {
            from(zipTree(goAarFile)) {
                if (!targetArch.isNullOrBlank()) {
                    include("jni/$targetArch/**/*")
                } else {
                    include("jni/**/*")
                }
            }
            into(tempDir)
        }
        
        // Delete the temporary class folders before packing the AAR
        goClassesDir.deleteRecursively()
        kotlinClassesDir.deleteRecursively()
        mergedClassesDir.deleteRecursively()
        
        // 3. Pack the final AAR
        ant.withGroovyBuilder {
            "zip"("destfile" to fatAarFile, "basedir" to tempDir)
        }
        
        // 4. Clean up the temporary directory
        tempDir.deleteRecursively()
        
        println("AAR created: ${fatAarFile.absolutePath}")
        println("Size: ${String.format("%.2f", fatAarFile.length() / (1024.0 * 1024.0))} MB")
    }
}

