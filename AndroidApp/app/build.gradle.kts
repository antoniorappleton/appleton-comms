@file:Suppress("RedundantLambdaOrAnonymousFunction")

import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.serialization)

    id("androidx.navigation.safeargs.kotlin")
}

val sourceVersion = providers.exec {
    commandLine("git", "describe", "--match", "736fd2e"/* unmatchable */, "--dirty", "--always")
}.standardOutput.asText.get().trim().replace("-dirty", "*")

project.file("version.properties").inputStream().use {
    val props = Properties()
    props.load(it)
    props.forEach { (k, v) ->
        project.extensions.extraProperties[k.toString()] = v
    }
}

android {
    namespace = "com.gentin.connectiq.handsfree"
    compileSdk = 37

    defaultConfig {
        // Own application ID: Appleton Comms installs alongside (and is not mistaken for) Handsfree.
        applicationId = "com.appleton.comms"

        minSdk = 28
        //noinspection OldTargetApi
        targetSdk = 36

        versionCode = {
            val versionCode: String by project
            versionCode.toInt()
        }()

        versionName = {
            val versionName: String by project
            versionName
        }()

        buildConfigField("String", "SOURCE_VERSION", "\"$sourceVersion\"")
    }

    androidResources {
        @Suppress("UnstableApiUsage")
        localeFilters += listOf("en", "ru")
    }

    // Release signing with the owner's key, read from keystore.properties (never committed).
    val keystoreProperties = Properties()
    val keystorePropertiesFile = rootProject.file("keystore.properties")
    if (keystorePropertiesFile.exists()) {
        keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
    }
    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        getByName("release") {
            signingConfig = signingConfigs.findByName("release")
            isDebuggable = false
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro"
            )
        }
    }

    buildFeatures {
        buildConfig = true
        viewBinding = true
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }
    flavorDimensions += listOf("distribution")
    productFlavors {
        create("googlePlay") {
            dimension = "distribution"
        }
        create("selfHosted") {
            dimension = "distribution"
        }
    }
}

fun DependencyHandlerScope.implementationAar(
    notation: Provider<MinimalExternalModuleDependency>,
    configure: ModuleDependency.() -> Unit = {}
) {
    val dep = notation.get()
    val group = dep.module.group
    val name = dep.module.name
    val version = dep.versionConstraint.requiredVersion
    val dependencyNotation = "$group:$name:$version@aar"
    add("implementation", dependencyNotation, configure)
}

dependencies {
    implementation(libs.androidx.appcompat)
    implementation(libs.androidx.constraintlayout)
    implementation(libs.androidx.lifecycle.livedata.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.lifecycle.service)
    implementation(libs.androidx.navigation.fragment.ktx)
    implementation(libs.androidx.navigation.ui.ktx)
    implementation(libs.androidx.preference.ktx)

    implementation(libs.gson)
    implementation(libs.jackson.module.kotlin)

    implementationAar(libs.ciq.companion.app.sdk)

    implementation(libs.kotlinx.serialization.json)
    implementation(libs.kotlinx.coroutines.android)

    implementationAar(libs.doki) {
        isTransitive = true
    }

    implementation(libs.material)

    implementation(libs.markwon.core)
    implementation(libs.markwon.image)
    implementation(libs.markwon.html)

    implementation(libs.androidsvg.aar)

    testImplementation(libs.junit)
    testImplementation(libs.mockk)
    testImplementation(libs.androidx.core.testing)
}
java {
    toolchain {
        languageVersion = JavaLanguageVersion.of(17)
    }
}
