package com.example.lol

import android.content.ClipData
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.webkit.WebView
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.lol/intent"
    private val CLICK_CHANNEL = "tv_webview/click"
    private var methodChannel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)

        // ── Click nativo de la mira (WebView TV) ─────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CLICK_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "injectClick") {
                    val x = (call.argument<Double>("x") ?: 0.0).toFloat()
                    val y = (call.argument<Double>("y") ?: 0.0).toFloat()
                    injectNativeClick(x, y)
                    result.success(true)
                } else {
                    result.notImplemented()
                }
            }

        // ── Control y refuerzo de volumen de medios (Audio Boost) ─────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.example.lol/audio")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "boostVolume" -> {
                        // Filmotic nunca modifica el volumen del sistema,
                        // solo permite que el reproductor interno use el 100% del audio disponible.
                        result.success(true)
                    }
                    "setVolumePercent" -> {
                        try {
                            val pct = call.argument<Double>("percent") ?: 1.0
                            val audioManager = getSystemService(android.content.Context.AUDIO_SERVICE) as android.media.AudioManager
                            val maxVol = audioManager.getStreamMaxVolume(android.media.AudioManager.STREAM_MUSIC)
                            val targetVol = (maxVol * pct.coerceIn(0.0, 1.0)).toInt()
                            audioManager.setStreamVolume(android.media.AudioManager.STREAM_MUSIC, targetVol, android.media.AudioManager.FLAG_SHOW_UI)
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                    "getVolumePercent" -> {
                        try {
                            val audioManager = getSystemService(android.content.Context.AUDIO_SERVICE) as android.media.AudioManager
                            val maxVol = audioManager.getStreamMaxVolume(android.media.AudioManager.STREAM_MUSIC)
                            val currentVol = audioManager.getStreamVolume(android.media.AudioManager.STREAM_MUSIC)
                            val pct = if (maxVol > 0) currentVol.toDouble() / maxVol else 0.0
                            result.success(pct)
                        } catch (e: Exception) {
                            result.success(1.0)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        // ── Verificación e instalación nativa de APK (Actualizaciones) ───
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.example.lol/installer")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "verifyApkFile" -> {
                        val filePath = call.argument<String>("filePath") ?: ""
                        result.success(verifyApkFile(filePath))
                    }
                    "installApkNative" -> {
                        val filePath = call.argument<String>("filePath") ?: ""
                        result.success(installApkNative(filePath))
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun verifyApkFile(filePath: String): Map<String, Any?> {
        return try {
            val file = File(filePath)
            if (!file.exists() || file.length() <= 0L) {
                return mapOf("valid" to false, "reason" to "File does not exist or is empty")
            }
            val info = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                packageManager.getPackageArchiveInfo(
                    filePath,
                    PackageManager.PackageInfoFlags.of(0)
                )
            } else {
                @Suppress("DEPRECATION")
                packageManager.getPackageArchiveInfo(filePath, 0)
            }
            if (info == null) {
                mapOf("valid" to false, "reason" to "PackageManager returned null (corrupt or incompatible APK)")
            } else {
                val verCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    info.longVersionCode
                } else {
                    @Suppress("DEPRECATION")
                    info.versionCode.toLong()
                }
                mapOf(
                    "valid" to true,
                    "packageName" to info.packageName,
                    "versionName" to (info.versionName ?: ""),
                    "versionCode" to verCode
                )
            }
        } catch (e: Exception) {
            mapOf("valid" to false, "reason" to (e.message ?: "Exception parsing APK"))
        }
    }

    private fun installApkNative(filePath: String): Boolean {
        return try {
            val file = File(filePath)
            if (!file.exists()) return false
            file.setReadable(true, false)

            val intent = Intent(Intent.ACTION_VIEW)
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            intent.addCategory(Intent.CATEGORY_DEFAULT)

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                val authority = "$packageName.fileProvider"
                val contentUri = FileProvider.getUriForFile(applicationContext, authority, file)
                intent.setDataAndType(contentUri, "application/vnd.android.package-archive")
                intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                intent.clipData = ClipData.newRawUri("", contentUri)

                // Otorgar permiso explícito de lectura URI a todas las actividades del PackageInstaller
                val resInfoList = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    packageManager.queryIntentActivities(
                        intent,
                        PackageManager.ResolveInfoFlags.of(PackageManager.MATCH_DEFAULT_ONLY.toLong())
                    )
                } else {
                    @Suppress("DEPRECATION")
                    packageManager.queryIntentActivities(intent, PackageManager.MATCH_DEFAULT_ONLY)
                }
                for (resolveInfo in resInfoList) {
                    val targetPkg = resolveInfo.activityInfo?.packageName
                    if (!targetPkg.isNullOrEmpty()) {
                        grantUriPermission(
                            targetPkg,
                            contentUri,
                            Intent.FLAG_GRANT_READ_URI_PERMISSION
                        )
                    }
                }
            } else {
                intent.setDataAndType(Uri.fromFile(file), "application/vnd.android.package-archive")
            }

            startActivity(intent)
            true
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }

    private fun injectNativeClick(flutterX: Float, flutterY: Float) {
        val root = window?.decorView ?: return
        val webView = findWebView(root) ?: return

        val density = resources.displayMetrics.density
        val localX = flutterX * density
        val localY = flutterY * density

        Handler(Looper.getMainLooper()).post {
            val downTime = SystemClock.uptimeMillis()
            val down = MotionEvent.obtain(
                downTime, downTime,
                MotionEvent.ACTION_DOWN,
                localX, localY, 0
            )
            val up = MotionEvent.obtain(
                downTime, downTime + 60,
                MotionEvent.ACTION_UP,
                localX, localY, 0
            )
            webView.dispatchTouchEvent(down)
            webView.dispatchTouchEvent(up)
            down.recycle()
            up.recycle()
        }
    }

    private fun findWebView(view: View): WebView? {
        if (view is WebView) return view
        if (view is ViewGroup) {
            for (i in 0 until view.childCount) {
                findWebView(view.getChildAt(i))?.let { return it }
            }
        }
        return null
    }

    private fun handleIntent(intent: Intent) {
        val data = intent.data

        data?.let { uri ->
            when {
                // ============ USUARIO: lol://user/123 ============
                uri.scheme == "lol" && uri.host == "user" -> {
                    val userId = uri.path?.replaceFirst("/", "") ?: ""
                    if (userId.isNotEmpty()) {
                        sendToFlutter("user", userId)
                    }
                }

                // ============ CONTENIDO: lol://content/11 ============
                // 🔥 AHORA SOLO IDCONTENIDO (sin tipo)
                // Ejemplo: lol://content/11
                uri.scheme == "lol" && uri.host == "content" -> {
                    val idcontenido = uri.path?.replaceFirst("/", "") ?: ""
                    // Verificar que sea un número
                    if (idcontenido.isNotEmpty() && idcontenido.all { it.isDigit() }) {
                        sendToFlutter("content", idcontenido)
                    } else {
                        println("❌ ID de contenido inválido: $idcontenido")
                    }
                }

                // ============ LISTA: lol://list/5 ============
                // O: lol://list/recientes
                uri.scheme == "lol" && uri.host == "list" -> {
                    val filter = uri.path?.replaceFirst("/", "") ?: ""
                    if (filter.isNotEmpty()) {
                        sendToFlutter("list", filter)
                    }
                }

                // ============ URL GENÉRICA ============
                else -> {
                    val url = uri.toString()
                    if (url.isNotEmpty()) {
                        sendToFlutter("url", url)
                    }
                }
            }
        }
    }

    private fun sendToFlutter(type: String, value: String) {
        try {
            val data = mapOf(
                "type" to type,
                "value" to value
            )
            methodChannel?.invokeMethod("openDeepLink", data)
            println("📱 Enviando a Flutter: type=$type, value=$value")
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }
}