import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

android {
    namespace = "com.noguwo.apps.caverno"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    val keystoreProperties = Properties()
    val keystorePropertiesFile = rootProject.projectDir.resolve("key.properties")
    if (keystorePropertiesFile.exists()) {
        keystorePropertiesFile.inputStream().use(keystoreProperties::load)
    }

    val releaseArtifactTaskPrefixes = listOf(
        "assemble",
        "bundle",
        "package",
        "publish",
    )
    val releaseBuildRequested = gradle.startParameter.taskNames.any { taskPath ->
        val taskName = taskPath.substringAfterLast(':')
        taskName in setOf("assemble", "build", "bundle") ||
            (releaseArtifactTaskPrefixes.any(taskName::startsWith) &&
                taskName.contains("Release", ignoreCase = true))
    }
    val requiredSigningProperties = listOf(
        "keyAlias",
        "keyPassword",
        "storeFile",
        "storePassword",
    )
    val missingSigningProperties = requiredSigningProperties.filter { propertyName ->
        keystoreProperties.getProperty(propertyName).isNullOrBlank()
    }
    val releaseStoreFile = keystoreProperties.getProperty("storeFile")
        ?.takeIf(String::isNotBlank)
        ?.let(::file)
    val releaseSigningReady = keystorePropertiesFile.exists() &&
        missingSigningProperties.isEmpty() &&
        releaseStoreFile?.isFile == true

    if (releaseBuildRequested && !releaseSigningReady) {
        val reason = when {
            !keystorePropertiesFile.exists() -> "android/key.properties is missing"
            missingSigningProperties.isNotEmpty() ->
                "android/key.properties is missing: ${missingSigningProperties.joinToString()}"
            else -> "the configured release keystore does not exist"
        }
        throw GradleException(
            "Release signing is not configured: $reason. " +
                "Provide complete release signing material before building an Android release.",
        )
    }

    signingConfigs {
        if (releaseSigningReady) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = releaseStoreFile
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    defaultConfig {
        applicationId = "com.noguwo.apps.caverno"
        // serious_python (embedded Python) requires Android 7.0+ (API 24).
        minSdk = maxOf(flutter.minSdkVersion, 24)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release")

            // Enable R8 for code shrinking, obfuscation, and optimization.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
