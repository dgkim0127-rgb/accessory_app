import org.gradle.kotlin.dsl.coreLibraryDesugaring
import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("com.google.gms.google-services")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

/**
 * ✅ signing key는 android/key.properties 에서 읽는다.
 */
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")

if (keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}

fun prop(key: String): String? =
    keystoreProperties.getProperty(key)?.trim()?.takeIf { it.isNotEmpty() }

val storeFileRaw = prop("storeFile")

/**
 * ✅ 핵심:
 * storeFile 경로가 "upload.jks" / "app/upload.jks" / "../app/upload.jks" 등으로 들어와도
 * 실제 파일을 확실히 찾아내도록 3가지 기준을 순서대로 시도한다.
 *
 * 1) android/ 기준(rootProject)
 * 2) android/app/ 기준(project)
 * 3) 절대경로로 들어온 경우 그대로
 */
fun resolveKeystorePath(raw: String?): File? {
    if (raw.isNullOrBlank()) return null

    val p = raw.replace("\\", "/")

    // 절대 경로면 그대로
    val abs = File(p)
    if (abs.isAbsolute && abs.exists()) return abs

    // 1) android/ 기준
    val fromAndroid = rootProject.file(p)
    if (fromAndroid.exists()) return fromAndroid

    // 2) android/app 기준
    val fromApp = project.file(p)
    if (fromApp.exists()) return fromApp

    return null
}

val resolvedStoreFile: File? = resolveKeystorePath(storeFileRaw)

val hasReleaseKey =
    keystorePropertiesFile.exists() &&
            resolvedStoreFile != null &&
            resolvedStoreFile.exists() &&
            prop("storePassword") != null &&
            prop("keyAlias") != null &&
            prop("keyPassword") != null

android {
    namespace = "kr.co.catalog"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        applicationId = "kr.co.catalog"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                storeFile = resolvedStoreFile
                storePassword = prop("storePassword")
                keyAlias = prop("keyAlias")
                keyPassword = prop("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // ✅ 키가 없으면 debug로 떨어지지 말고 "빌드 실패"
            if (!hasReleaseKey) {
                throw GradleException(
                    "Release signing key not found.\n" +
                            "Check android/key.properties and JKS path.\n" +
                            "storeFile(raw): $storeFileRaw\n" +
                            "resolved: ${resolvedStoreFile?.absolutePath ?: "null"}\n"
                )
            }

            signingConfig = signingConfigs.getByName("release")

            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }

        debug {
            // 기본 debug signing 사용
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}
