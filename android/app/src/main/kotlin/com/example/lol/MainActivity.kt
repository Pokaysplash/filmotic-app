package com.example.lol

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.webkit.WebView
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

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