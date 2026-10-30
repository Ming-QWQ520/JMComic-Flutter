import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 发布签名配置（可选）：android/key.properties 由 CI 在构建前生成
// （签名材料全部存于 GitHub Actions Secrets，仓库不保留任何密钥文件）。
// 本地开发无 key.properties 时自动回退 debug 签名，`flutter run --release` 不受影响。
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.ming.jmcomic"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.ming.jmcomic"
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
        create("release") {
            // key.properties 存在时才填充（CI 注入）；字段缺失时保持
            // 未配置状态，由 buildTypes 回退 debug 签名。
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // 有 key.properties（CI 注入的发布签名）时用 release 签名，
            // 否则回退 debug 签名（本地开发场景，保证能出可运行的包）。
            // 修复需求：此前恒用 debug 签名，与用户已安装包签名不一致
            // 导致无法覆盖安装。
            signingConfig = if (keystorePropertiesFile.exists() &&
                keystoreProperties["storeFile"] != null
            ) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

// 检测更新安装 APK 需要 androidx.core.content.FileProvider
// （Flutter embedding 会传递引入，这里显式声明保证版本稳定）。
dependencies {
    implementation("androidx.core:core-ktx:1.13.1")
}
