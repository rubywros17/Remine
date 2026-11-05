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
// 파일이 없으면 릴리스 빌드를 실패시킨다. debug 키로 서명하면 폰의 릴리스 앱과 서명이 달라, 설치할 때 앱이 지워지고 데이터가 날아간다.
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
        manifestPlaceholders["appLabel"] = "remine"
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
        debug {
            // 패키지를 나눠 릴리스 앱과 같이 설치한다. google-services.json에 이 패키지도 등록되어 있어야 빌드된다.
            applicationIdSuffix = ".debug"
            manifestPlaceholders["appLabel"] = "re:mine Dev"
        }
        release {
            if (keyPropertiesFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
            }
            // R8(코드 축소) 규칙: ML Kit 다른 문자 체계 클래스 경고 무시
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}

// 디버그 빌드는 키 없이도 되어야 하므로, 설정 단계가 아니라 릴리스 태스크를 실행할 때만 검사한다.
gradle.taskGraph.whenReady {
    val releasing = allTasks.any { it.path in listOf(":app:assembleRelease", ":app:bundleRelease") }
    if (releasing && !keyPropertiesFile.exists()) {
        throw GradleException(
            "릴리스 서명 키 설정이 없습니다. REMINE_KEY_PROPERTIES를 key.properties 경로로 설정하세요. (찾은 경로: $keyPropertiesFile)",
        )
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
