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
    // Downgraded from 9.1.0/2.4.0 to stable versions supported by Flutter 3.24+ / 3.35
    // to avoid "restricted method in java.lang.System" warning with Gradle 9 + Java 24.
    // Note: Gradle 8.10.2 (see gradle/wrapper/gradle-wrapper.properties) runs on Java
    // 17-23 only. Java 24 needs Gradle 8.14, Java 25 needs 9.1.0+, and AGP 8.x breaks on
    // Gradle 9.6+ (it uses Gradle internals removed there). So build with a JDK 17/21
    // (flutter config --jdk-dir) instead of bumping this pair until Gradle 9 + AGP 9 is
    // done deliberately. See README -> "Build fails: Gradle build failed due to
    // Java/Gradle incompatibility".
    id("com.android.application") version "8.7.3" apply false
    id("org.jetbrains.kotlin.android") version "2.1.0" apply false
}

include(":app")
