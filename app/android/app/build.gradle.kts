import java.util.Properties

plugins {
    id("com.android.application")
    id("com.google.gms.google-services")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 릴리스 서명 키 설정. 키(keystore)와 비밀번호는 레포 밖에 둔다.
// 환경변수 REMINE_KEY_PROPERTIES(예: E:/dev/secrets/remine/key.properties)가 가리키는 파일, 없으면 android/key.properties(.gitignore).
// 파일 내용: storeFile=키 경로, storePassword=, keyAlias=, keyPassword=
// 파일이 없으면 지금처럼 debug 키로 서명한다(로컬 `flutter run --release`용, 배포용 APK로 쓰지 말 것).
val keyPropertiesFile = System.getenv("REMINE_KEY_PROPERTIES")?.let { file(it) } ?: rootProject.file("key.properties")
val keyProperties = Properties().apply {
    if (keyPropertiesFile.exists()) keyPropertiesFile.inputStream().use { load(it) }
}

android {
    namespace = "com.remine.remine"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.remine.remine"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (keyPropertiesFile.exists()) {
            create("release") {
                storeFile = file(keyProperties.getProperty("storeFile"))
                storePassword = keyProperties.getProperty("storePassword")
                keyAlias = keyProperties.getProperty("keyAlias")
                keyPassword = keyProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keyPropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                logger.warn("릴리스 서명 키 설정이 없어 debug 키로 서명합니다(REMINE_KEY_PROPERTIES).")
                signingConfigs.getByName("debug")
            }
            // R8(코드 축소) 규칙: ML Kit 다른 문자 체계 클래스 경고 무시
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
    // 한국어 OCR 모델을 앱에 포함(번들)한다. play-services 방식(첫 실행 다운로드)이 아니라 오프라인으로 동작한다.
    implementation("com.google.mlkit:text-recognition-korean:16.0.1")
}

flutter {
    source = "../.."
}
