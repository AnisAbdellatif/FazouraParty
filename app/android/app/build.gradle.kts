import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing. The key itself is never in this repository: on a developer
// machine it comes from android/key.properties (git-ignored), in CI from the
// environment. See README.md, "Releasing the Android app".
//
// Every release APK has to be signed with the *same* key, or Android refuses to
// install one over another — which would break updating, since the app hands
// its own updates out (app/lib/core/update/).
val keyProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}

fun signingValue(property: String, variable: String): String? =
    (System.getenv(variable) ?: keyProperties.getProperty(property))?.takeIf { it.isNotBlank() }

val keystorePath = signingValue("storeFile", "ANDROID_KEYSTORE_PATH")

android {
    namespace = "com.fazouraparty.fazoura_party"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.fazouraparty.fazoura_party"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. `scripts/ci.sh apk` reads the same
        // line and passes it to Dart as APP_VERSION_CODE, so what the app believes it
        // is and what Android installs it as cannot drift apart.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (keystorePath != null) {
                storeFile = file(keystorePath)
                storePassword = signingValue("storePassword", "ANDROID_KEYSTORE_PASSWORD")
                keyAlias = signingValue("keyAlias", "ANDROID_KEY_ALIAS")
                // keytool has produced PKCS12 keystores since Java 9, and PKCS12 has no
                // per-entry password: it encrypts the key with the store password and
                // ignores `-keypass` with a warning that is easy to miss. So the key
                // password falls back to the store password rather than being required —
                // the alternative is an UnrecoverableKeyException at release time for
                // someone who typed two different passwords at the keytool prompts.
                keyPassword = signingValue("keyPassword", "ANDROID_KEY_PASSWORD")
                    ?: storePassword
            }
        }
    }

    buildTypes {
        release {
            // Falling back to the debug key keeps `flutter run --release` working for
            // someone who has no keystore. It is deliberately not an error here:
            // `scripts/ci.sh apk`, the only supported way to build an APK for other
            // people, refuses to run without the real key.
            signingConfig = if (keystorePath != null) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
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
