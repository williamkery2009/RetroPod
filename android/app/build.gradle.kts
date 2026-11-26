import java.util.Properties
import java.io.FileInputStream
import java.io.FileNotFoundException

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
try {
    val keystorePropertiesFile = rootProject.file("key.properties")
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
} catch (e: FileNotFoundException) {
    println("Warning: key.properties file not found. Ensure the file is present before building the release version.")
}

android {
    namespace = "com.rchrdariza.retropod"
    compileSdk = 37
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // NewPipeExtractor uses java.time and Java 9+ collection factories.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.rchrdariza.retropod"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        ndk.abiFilters.addAll(arrayOf("armeabi-v7a", "arm64-v8a", "x86_64"))
    }

    buildFeatures {
        resValues = true
    }

    // NewPipeExtractor, Rhino and protobuf ship overlapping META-INF files.
    packaging {
        resources {
            excludes += setOf(
                "/META-INF/{AL2.0,LGPL2.1}",
                "META-INF/DEPENDENCIES",
                "META-INF/INDEX.LIST",
                "META-INF/LICENSE*",
                "META-INF/NOTICE*",
            )
        }
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as? String
            keyPassword = keystoreProperties["keyPassword"] as? String
            storePassword = keystoreProperties["storePassword"] as? String
            val storeFilePath = keystoreProperties["storeFile"] as? String
            if (storeFilePath != null) {
                storeFile = file(keystoreProperties["storeFile"] as String)
            }
        }
    }

    buildTypes {
        getByName("debug") {
            signingConfig = signingConfigs.getByName("debug")
        }
        getByName("release") {
            // Fallback to debug signing if the release keystore isn't configured
            val storeFilePath = keystoreProperties["storeFile"] as? String
            signingConfig = if (storeFilePath != null) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    flavorDimensions += "default"
    productFlavors {
        create("production") {
            dimension = "default"
            resValue("string", "app_name", "RetroPod")
            applicationIdSuffix = ""
        }
        create("dev") {
            dimension = "default"
            resValue("string", "app_name", "RetroPod Dev")
            applicationIdSuffix = ".dev"
            versionNameSuffix = "-dev"
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

dependencies {
    // Media3 pinned to the version just_audio already resolves (1.4.1), so the
    // streaming session and the local library player share one ExoPlayer
    // implementation. Bump both together after checking
    // `./gradlew :app:dependencies --configuration releaseRuntimeClasspath`.
    val media3Version = "1.4.1"
    implementation("androidx.media3:media3-exoplayer:$media3Version")
    implementation("androidx.media3:media3-session:$media3Version")

    // YouTube Music extraction (Innertube). GPL-3.0, see
    // docs/youtube-music-integration.md before shipping.
    implementation("com.github.teamnewpipe:NewPipeExtractor:v0.27.1")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")

    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")

    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
