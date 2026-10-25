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
        // google() 走 maven.google.com（本机被墙），改用同一仓库的 dl.google.com 直链
        maven { url = uri("https://dl.google.com/dl/android/maven2/") }
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.0.1" apply false
    id("org.jetbrains.kotlin.android") version "2.3.20" apply false
}

include(":app")

// 依赖仓库：插件子项目自带 google()（maven.google.com）。
// 国内网络下由 ~/.gradle/init.d/cn-maven-mirror.gradle 统一重写为
// dl.google.com 直链（同源仓库）；mavenCentral 直连可用。
