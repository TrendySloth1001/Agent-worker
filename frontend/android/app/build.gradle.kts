import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing: android/key.properties (git-ignored) points at the upload
// keystore android/app/upload-keystore.jks (git-ignored). Without it a release
// build FAILS (see the guard below): a debug-signed APK is rejected by the in-app
// installer as a signature mismatch, so it must never be produced silently.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.sparky.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // flutter_local_notifications uses java.time APIs on older Android.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.sparky.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Never fall back to the debug key; the guard below fails release tasks
            // when key.properties is missing. (Debug builds are unaffected.)
            if (keystorePropertiesFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

flutter {
    source = "../.."
}

// Signing guard: refuse to build a release without the real key.
if (!keystorePropertiesFile.exists()) {
    gradle.taskGraph.whenReady {
        val releaseTask = allTasks.firstOrNull { t ->
            t.project == project && t.name.contains("Release") &&
                (t.name.startsWith("assemble") || t.name.startsWith("bundle") ||
                    t.name.startsWith("package") || t.name.startsWith("validateSigning"))
        }
        if (releaseTask != null) {
            throw GradleException(
                "android/key.properties is missing: refusing to build a release APK signed with " +
                    "the debug key (the in-app updater would reject it). Restore key.properties " +
                    "and upload-keystore.jks, or build a debug APK instead.",
            )
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // "Continue with Google": Credential Manager + Sign in with Google
    // (MainActivity, channel app/auth). No google-services.json needed.
    implementation("androidx.credentials:credentials:1.6.0")
    implementation("androidx.credentials:credentials-play-services-auth:1.6.0")
    // 1.2.1+ is built with Kotlin 2.4 metadata; this project compiles with Kotlin 2.2.
    implementation("com.google.android.libraries.identity.googleid:googleid:1.2.0")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.10.0")
}
