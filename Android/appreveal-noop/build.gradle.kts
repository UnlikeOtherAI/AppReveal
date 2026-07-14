plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
    id("org.jlleitschuh.gradle.ktlint")
}

android {
    namespace = "com.appreveal"
    compileSdk = 35
    buildToolsVersion = "36.0.0"

    defaultConfig {
        minSdk = 26
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }
}

dependencies {
    // Release builds expose no diagnostics server. OkHttp is compile-only so apps can share
    // debug/release networking setup without pulling AppReveal into release artifacts.
    compileOnly("com.squareup.okhttp3:okhttp:4.12.0")
}
