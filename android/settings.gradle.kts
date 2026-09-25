pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.0.1" apply false
    id("org.jetbrains.kotlin.android") version "2.3.20" apply false
}

// Parche automático de compatibilidad AGP 9+ para plugins de Flutter (flutter_inappwebview_android)
run {
    try {
        val pubCache = System.getenv("PUB_CACHE") ?: "${System.getProperty("user.home")}/.pub-cache"
        val hostedDir = file("$pubCache/hosted/pub.dev")
        if (hostedDir.exists()) {
            hostedDir.listFiles()?.filter { it.name.startsWith("flutter_inappwebview_android") }?.forEach { pluginDir ->
                val bg = file("${pluginDir.absolutePath}/android/build.gradle")
                if (bg.exists()) {
                    val content = bg.readText()
                    if (content.contains("proguard-android.txt")) {
                        bg.writeText(content.replace("proguard-android.txt", "proguard-android-optimize.txt"))
                    }
                }
            }
        }
    } catch (_: Exception) {}
}

include(":app")
