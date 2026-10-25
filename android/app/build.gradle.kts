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

        // Syncthing 二进制以 jniLibs 形式打包（libsyncthing.so），运行时直接从
        // nativeLibraryDir 执行（Android 10+ W^X 限制下唯一可靠的执行路径）。
        // 目标平台 arm64-v8a。如需模拟器 x86_64 调试包：
        //   flutter build apk -PtargetAbi=arm64-v8a,x86_64 --release
        val targetAbi = (project.findProperty("targetAbi") as? String) ?: "arm64-v8a"
        ndk {
            abiFilters += targetAbi.split(",").map { it.trim() }
        }
    }

    packaging {
        jniLibs {
            // 必须解压（传统打包）：安装时把 libsyncthing.so 释放到 nativeLibraryDir，
            // 变成真实可执行文件（APK 内嵌的 .so 无法被 exec）。
            useLegacyPackaging = true
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
