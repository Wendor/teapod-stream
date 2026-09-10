plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val rustCore = gradle.extensions.extraProperties.get("teapodRust") as Boolean

android {
    namespace = "com.teapodstream.teapodstream"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    defaultConfig {
        applicationId = if (rustCore) "com.teapodstream.rustprobe" else "com.teapodstream.teapodstream"
        minSdk = 29
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["appLabel"] = if (rustCore) "Teapod Rust Probe" else "TeapodStream"

    }

    sourceSets.getByName("main").java.srcDir(if (rustCore) "src/rust/kotlin" else "src/go/kotlin")

    packaging {
        jniLibs {
            // Flutter builds target arm64, armv7 and x86_64.
            excludes.add("lib/x86/**")
        }
    }

    buildFeatures {
        buildConfig = true
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}

dependencies {
    if (rustCore) implementation(project(":xraymobile"))
    else implementation(files("libs/teapod-core.aar"))
}

flutter {
    source = "../.."
}
