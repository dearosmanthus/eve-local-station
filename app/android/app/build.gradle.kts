plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
}
android {
    namespace = "org.evelocalstation.app"
    compileSdk = 36
    ndkVersion = "27.0.12077973"
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = JavaVersion.VERSION_17.toString() }
    defaultConfig {
        applicationId = "org.evelocalstation.app"
        minSdk = 24
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        ndk { abiFilters += listOf("arm64-v8a") }
    }
    buildTypes {
        release {
            // Locally installable preview. Supply a private release key before distribution.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
    packaging { jniLibs { useLegacyPackaging = false } }
}
flutter { source = "../.." }

tasks.register("verifyNativeCore") {
    doLast {
        check(file("src/main/jniLibs/arm64-v8a/libeve_local_core.so").isFile) {
            "Rust library missing. Run python tools/build_android.py from project root."
        }
    }
}
tasks.named("preBuild") { dependsOn("verifyNativeCore") }
