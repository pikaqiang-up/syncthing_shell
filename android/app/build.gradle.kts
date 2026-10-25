plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("kotlin-android")
}

android {
    namespace = "ai.pikaqiang.syncthing"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    // 目标 ABI（单一事实源，defaultConfig 与 packaging 共用）：
    // 发布仅 arm64-v8a；模拟器调试用 -PtargetAbi=arm64-v8a,x86_64
    val targetAbiList = ((project.findProperty("targetAbi") as? String) ?: "arm64-v8a")
        .split(",").map { it.trim() }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "ai.pikaqiang.syncthing"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        ndk {
            abiFilters += targetAbiList
        }
    }

    packaging {
        jniLibs {
            // 必须解压（传统打包）：安装时把 libsyncthing.so 释放到 nativeLibraryDir，
            // 变成真实可执行文件（APK 内嵌的 .so 无法被 exec）。
            useLegacyPackaging = true
            // 最小化：插件 AAR（ML Kit 扫码/camera-x 等）自带多 ABI .so，
            // ndk.abiFilters 不传导到 AAR，需在此按 ABI 精确剔除非目标架构。
            val keep = targetAbiList
            val all = listOf("armeabi-v7a", "arm64-v8a", "x86", "x86_64")
            excludes += all.filter { it !in keep }.flatMap { abi ->
                listOf("**/lib/$abi/**", "**/$abi/**")
            }
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.17.0")
}

flutter {
    source = "../.."
}
