group = "dev.bifold.bifold"
version = "1.0-SNAPSHOT"

buildscript {
    val kotlinVersion = "2.3.20"
    repositories {
        google()
        mavenCentral()
    }

    dependencies {
        classpath("com.android.tools.build:gradle:9.0.1")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlinVersion")
    }
}

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

    defaultConfig {
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
    implementation("androidx.window:window:1.2.0")
    implementation("androidx.window:window-java:1.2.0")
}
