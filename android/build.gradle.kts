group = "dev.bifold.bifold"
version = "1.0.0"

// Declared once and surfaced through BuildConfig, so the diagnostic report
// cannot drift from what is actually on the classpath.
val windowVersion = "1.2.0"

// No buildscript block. One used to sit here declaring AGP and
// kotlin-gradle-plugin classpaths that nothing applied -- there is no
// `apply plugin` anywhere in this file, and the plugins block below applies
// only com.android.library. Kotlin compiles because AGP 9 has built-in
// Kotlin support, not because a Kotlin plugin is applied here. That is worth
// stating: anyone downgrading AGP will find the Kotlin sources silently stop
// compiling with nothing in this file to explain why.

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

plugins {
    id("com.android.library")
}

android {
    namespace = "dev.bifold.bifold"

    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    sourceSets {
        getByName("main") {
            java.srcDirs("src/main/kotlin")
        }
        getByName("test") {
            java.srcDirs("src/test/kotlin")
        }
    }

    buildFeatures {
        // Needed for WINDOW_VERSION below. Off by default in AGP 8+.
        buildConfig = true
    }

    defaultConfig {
        buildConfigField(
            "String",
            "WINDOW_VERSION",
            "\"$windowVersion\"",
        )
        // Flutter's own floor. The hinge sensor arrived in 30 and the window
        // layout APIs work below it, so both are guarded rather than raising
        // this and dropping older devices that bifold still degrades on.
        minSdk = 24
    }

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

    testOptions {
        unitTests {
            isIncludeAndroidResources = true
            all { it.useJUnitPlatform() }
        }
    }
}

dependencies {
    testImplementation(kotlin("test"))
    testImplementation("org.junit.jupiter:junit-jupiter:5.10.2")
    testRuntimeOnly("org.junit.platform:junit-platform-launcher")

    // Pinned to the version Flutter's own Android embedding already resolves
    // (androidx.window:window-java:1.2.0, read from flutter_embedding's pom),
    // so the plugin cannot drag the app into a version conflict with the
    // engine. Raising either of these needs that check repeating.
    implementation("androidx.window:window:$windowVersion")
    implementation("androidx.window:window-java:$windowVersion")
}
