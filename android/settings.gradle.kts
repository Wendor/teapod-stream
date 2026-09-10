pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.library") version "8.11.1" apply false
    id("com.android.application") version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
}

// Flutter forwards --dart-define to Gradle as base64-encoded dart-defines.
val coreValues = providers.gradleProperty("dart-defines").orNull.orEmpty().split(',')
    .filter { it.isNotEmpty() }
    .map { String(java.util.Base64.getDecoder().decode(it), Charsets.UTF_8) }
    .filter { it.startsWith("TEAPOD_CORE=") }
require(coreValues.size <= 1) { "TEAPOD_CORE must be specified at most once" }
val selectedCore = coreValues.singleOrNull()?.substringAfter('=') ?: "go"
require(selectedCore in listOf("go", "rust")) { "TEAPOD_CORE must be go or rust" }
gradle.extensions.extraProperties.set("teapodRust", selectedCore == "rust")
include(":app")
if (selectedCore == "rust") include(":xraymobile")
