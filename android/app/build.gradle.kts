plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.accessory_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Java 17 + desugaring ON
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true   // ✅ 여기!
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.example.accessory_app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

// ⬇️ ⬇️ ⬇️ 반드시 android{} 밖, 최상위의 dependencies 블록에 작성 ⬇️ ⬇️ ⬇️
dependencies {
    // ✅ desugaring 런타임 추가 (여기가 정확한 자리)
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")

    // (다른 implementation 등 기존 의존성은 플러터가 자동으로 추가합니다)
}

apply(plugin = "com.google.gms.google-services")
