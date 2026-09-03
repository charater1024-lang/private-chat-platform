plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseSigningInputs =
    linkedMapOf(
        "SECURE_COLLAB_ANDROID_KEYSTORE_PATH" to
            providers.environmentVariable("SECURE_COLLAB_ANDROID_KEYSTORE_PATH"),
        "SECURE_COLLAB_ANDROID_KEYSTORE_PASSWORD" to
            providers.environmentVariable("SECURE_COLLAB_ANDROID_KEYSTORE_PASSWORD"),
        "SECURE_COLLAB_ANDROID_KEY_ALIAS" to
            providers.environmentVariable("SECURE_COLLAB_ANDROID_KEY_ALIAS"),
        "SECURE_COLLAB_ANDROID_KEY_PASSWORD" to
            providers.environmentVariable("SECURE_COLLAB_ANDROID_KEY_PASSWORD"),
    )
val releaseTaskRequested =
    gradle.startParameter.taskNames.any { task ->
        task.contains("release", ignoreCase = true)
    }
if (releaseTaskRequested) {
    val missingInputs =
        releaseSigningInputs
            .filterValues { input -> !input.isPresent || input.get().isBlank() }
            .keys
    require(missingInputs.isEmpty()) {
        "Missing protected Secure Collab release signing inputs: ${missingInputs.joinToString()}"
    }
}

android {
    namespace = "com.example.chatplatform.secure_collab"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.chatplatform.secure_collab"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // API 24 keeps the client installable on many 2016-era Android devices.
        // Raise only through an explicit compatibility decision and device test.
        minSdk = 24
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
            if (releaseTaskRequested) {
                val keystore =
                    file(releaseSigningInputs.getValue("SECURE_COLLAB_ANDROID_KEYSTORE_PATH").get())
                require(keystore.isFile) {
                    "SECURE_COLLAB_ANDROID_KEYSTORE_PATH must identify a readable file."
                }
                storeFile = keystore
                storePassword =
                    releaseSigningInputs.getValue("SECURE_COLLAB_ANDROID_KEYSTORE_PASSWORD").get()
                keyAlias = releaseSigningInputs.getValue("SECURE_COLLAB_ANDROID_KEY_ALIAS").get()
                keyPassword =
                    releaseSigningInputs.getValue("SECURE_COLLAB_ANDROID_KEY_PASSWORD").get()
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
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
