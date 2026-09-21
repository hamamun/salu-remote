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
    // Versions pinned to the Flutter 3.47 stable Android template (see
    // flutter_tools/lib/src/android/gradle_utils.dart): Gradle 9.3.1 + AGP 9.1.0 +
    // Kotlin 2.4.0. Those three move together - do not downgrade one of them alone.
    //
    // Why this set:
    //  * Flutter 3.47 hard-errors below Gradle 8.14, AGP 8.11.1 and KGP 2.2.20, so the
    //    old "8.10.2 / 8.7.3 / 2.1.0 to silence a warning" combo is out of support.
    //  * AGP 9.1.x requires Gradle >= 9.3.1, and Gradle >= 9.1.0 is what makes the build
    //    run on Java 24/25 (Java 23 was the ceiling for Gradle 8.10.x).
    //  * Gradle 9.3.1 runs on Java 17-25; Java 26 needs Gradle 9.4+, which Flutter does
    //    not know about yet - when that day comes, upgrade Flutter, not just Gradle.
    // The harmless "restricted method in java.lang.System has been called" warning on
    // JDK 24+ is the price of that support; see README -> Troubleshooting.
    id("com.android.application") version "9.1.0" apply false
    id("org.jetbrains.kotlin.android") version "2.4.0" apply false
}

include(":app")
