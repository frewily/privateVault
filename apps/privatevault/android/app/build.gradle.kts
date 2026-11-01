plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
}
val pvRoot = rootProject.projectDir.resolve("../../..").canonicalFile
android {
    namespace = "dev.privatevault.w01"
    compileSdk = 36
    buildToolsVersion = "36.0.0"
    ndkVersion = "28.2.13676358"
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    defaultConfig {
        applicationId = "dev.privatevault.w01"
        minSdk = 24
        targetSdk = 36
        versionCode = 2
        versionName = "0.1.0-w01a.2"
        ndk { abiFilters += "arm64-v8a" }
    }
    signingConfigs {
        getByName("debug") {
            storeFile = pvRoot.resolve(".local/w01-a/debug.keystore")
            storePassword = "android"
            keyAlias = "privatevault-w01"
            keyPassword = "android"
        }
    }
    buildTypes {
        getByName("debug") { signingConfig = signingConfigs.getByName("debug") }
        getByName("release") {
            // Owner's local update: reuse the installed W01 certificate.
            // This is a development delivery, not a production signing setup.
            signingConfig = signingConfigs.getByName("debug")
            isDebuggable = false
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles("proguard-rules.pro")
        }
    }
    // A compressed owner APK saves transfer bytes. Android extracts these
    // libraries at install time; ELF 16KB alignment remains mandatory.
    packaging { jniLibs { useLegacyPackaging = providers.gradleProperty("build-mode").orNull == "release" } }
    sourceSets.getByName("test").java.srcDir(pvRoot.resolve("tools/kotlin"))
}
kotlin { compilerOptions { jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17 } }
flutter { source = "../.." }
dependencies {
    implementation(files(pvRoot.resolve(".local/w01-a/openlist.aar")))
    testImplementation("junit:junit:4.13.2")
}
