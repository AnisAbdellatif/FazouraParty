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

// Only the two release paths — `scripts/ci.sh apk` and `scripts/ci.sh aab` — build the
// app people install, and they say so with FAZOURA_RELEASE_BUILD=1. Everything else
// (`flutter run`, a hand-built `flutter build apk`) is a development build: a different
// application id and name, so it installs beside the Play or GitHub release instead of
// colliding with it. A collision is not an upgrade either way — the signatures differ,
// so Android would refuse it, or make you uninstall the real app and its quizzes first.
val releaseBuild = System.getenv("FAZOURA_RELEASE_BUILD") == "1"

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

        if (!releaseBuild) applicationIdSuffix = ".dev"
        manifestPlaceholders["appLabel"] = if (releaseBuild) "Fazoura Party" else "Fazoura Dev"

        // `--target-platform` in `scripts/ci.sh apk` picks which ABIs Flutter's own
        // engine and snapshot are built for. This says the same thing to everything
        // else — see the packaging block below for why both are needed.
        ndk { abiFilters += listOf("armeabi-v7a", "arm64-v8a") }
    }

    // Native libraries that arrive inside a plugin's AAR are already built, so
    // `abiFilters` does not reach them: an x86_64 `libdartjni.so` was still being
    // packaged with no `libflutter.so` beside it. An x86_64 device reads that
    // directory as "this APK supports me", installs, and then crashes on launch for
    // want of the engine. Dropping the directory is what makes the APK say arm-only,
    // so such a device declines it cleanly instead.
    packaging {
        jniLibs {
            excludes += setOf("**/x86/**", "**/x86_64/**", "**/mips*/**")
        }
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
