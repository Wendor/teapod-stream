plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.teapodstream.teapodstream"
    // permission_handler 13 needs 37; Flutter defaults to 36
    compileSdk = 37
    ndkVersion = "30.0.16248370"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    defaultConfig {
        applicationId = "com.teapodstream.teapodstream"
        minSdk = 29  // Required by teapod-tun2socks AAR (getConnectionOwnerUid)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // TEAPOD_ITEST=1 (./build.sh itest): a separate package for on-device integration
        // tests — installed next to the main one, doesn't touch its data.
        val itest = providers.environmentVariable("TEAPOD_ITEST").orNull == "1"
        if (itest) applicationIdSuffix = ".itest"
        manifestPlaceholders["appLabel"] = if (itest) "teapod itest" else "TeapodStream"
        buildConfigField("boolean", "ITEST", itest.toString())
    }

    packaging {
        jniLibs {
            // Native libraries are extracted on install (AGP 9 refuses android:extractNativeLibs in the manifest)
            useLegacyPackaging = true
            // teapod-core ships only arm64-v8a and x86_64
            excludes.add("lib/x86/**")
            excludes.add("lib/armeabi-v7a/**")
        }
    }

    buildFeatures {
        buildConfig = true
    }

    // JVM tests: android.* stubs (Log etc.) return default values.
    testOptions {
        unitTests.isReturnDefaultValues = true
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

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    implementation(files("libs/teapod-core.aar"))
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20240303")
}

flutter {
    source = "../.."
}
