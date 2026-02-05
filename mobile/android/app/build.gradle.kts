plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.debt_tracker_mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.debt_tracker_mobile"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

// Workaround: Flutter generates SharedPreferencesPlugin (Kotlin) but the Java compiler
// sometimes can't resolve it. Use LegacySharedPreferencesPlugin (Java) from the same plugin.
tasks.register("patchPluginRegistrant") {
    doLast {
        val file = file("src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java")
        if (file.exists()) {
            var text = file.readText()
            if (text.contains("SharedPreferencesPlugin()") && text.contains("sharedpreferences")) {
                text = text.replace("new io.flutter.plugins.sharedpreferences.SharedPreferencesPlugin()",
                    "new io.flutter.plugins.sharedpreferences.LegacySharedPreferencesPlugin()")
                file.writeText(text)
            }
        }
    }
}
// Ensure the patch runs before any Java compilation task (variant/task names can vary by AGP).
tasks.withType<org.gradle.api.tasks.compile.JavaCompile>().configureEach {
    dependsOn("patchPluginRegistrant")
}

dependencies {
    implementation(project(":shared_preferences_android"))
}
