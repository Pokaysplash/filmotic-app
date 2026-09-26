import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;
import '../extractors/hls/hls_extractor.dart';

class FallbackStreamResult {
  final bool success;
  final String? streamUrl;
  final String? serverName;
  final String? idioma;
  final Map<String, String> headers;
  final String? error;
  final List<String> attemptedServers;

  FallbackStreamResult({
    required this.success,
    this.streamUrl,
    this.serverName,
    this.idioma,
    this.headers = const {},
    this.error,
    this.attemptedServers = const [],
  });
}

class ServerFallbackService {
  ServerFallbackService._();
  static final ServerFallbackService instance = ServerFallbackService._();

  static const Duration kServerTimeout = Duration(seconds: 5);

  /// Detección de idioma por palabras clave
  static String detectIdioma(String text) {
    final lower = text.toLowerCase();
    if (lower.contains('latino') || lower.contains('es-la') || lower.contains('lat')) {
      return 'latino';
    }
    if (lower.contains('castellano') || lower.contains('es-es') || lower.contains('españa')) {
      return 'castellano';
    }
    if (lower.contains('subtitulado') || lower.contains('sub') || lower.contains('vose')) {
      return 'subtitulado';
    }
    if (lower.contains('ingles') || lower.contains('inglés') || lower.contains('english')) {
      return 'inglés';
    }
    return 'latino';
  }

  /// Ejecuta fallback secuencial sobre la lista de servidores:
  /// - Prueba cada servidor con timeout estricto de 5 segundos.
  /// - Si detecta captcha, lo salta de inmediato.
  /// - Al encontrar el primer stream reproducible, detiene el bucle y lo retorna.
  Future<FallbackStreamResult> resolveStreamWithFallback({
    required List<Map<String, dynamic>> servers,
    void Function(String currentServer, int index, int total)? onProgress,
  }) async {
    if (servers.isEmpty) {
      return FallbackStreamResult(
        success: false,
        error: 'No hay servidores disponibles para este contenido.',
      );
    }

    final attempted = <String>[];

    for (int i = 0; i < servers.length; i++) {
      final s = servers[i];
      final name = s['servidor_nombre']?.toString() ??
          s['nombre']?.toString() ??
          s['server']?.toString() ??
          'Servidor ${i + 1}';
      final url = s['servidor_url']?.toString() ??
          s['url']?.toString() ??
          '';

      if (url.isEmpty) continue;
      attempted.add(name);
      onProgress?.call(name, i + 1, servers.length);

      debugPrint('FallbackService: Probando servidor [$name] -> $url (timeout: 5s)');

      try {
        final stream = await _extractSingleServer(url: url, serverName: name)
            .timeout(kServerTimeout);

        if (stream != null && stream.isNotEmpty) {
          final serverLang = s['idioma']?.toString() ?? detectIdioma('$name $url $stream');
          debugPrint('FallbackService: ¡Stream extraído con éxito en $name!');

          return FallbackStreamResult(
            success: true,
            streamUrl: stream,
            serverName: name,
            idioma: serverLang,
            headers: {
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
              'Referer': url,
            },
            attemptedServers: attempted,
          );
        }
      } on TimeoutException {
        debugPrint('FallbackService: Timeout de 5s agotado para $name. Pasando al siguiente...');
      } catch (e) {
        debugPrint('FallbackService: Falló servidor $name ($e). Pasando al siguiente...');
      }
    }

    return FallbackStreamResult(
      success: false,
      error: 'Ninguno de los ${servers.length} servidores devolvió un stream reproducible.',
      attemptedServers: attempted,
    );
  }

  /// Intenta resolver el stream de un servidor individual
  Future<String?> _extractSingleServer({
    required String url,
    required String serverName,
  }) async {
    // 1. Si la URL ya es un m3u8 o mp4 directo
    if (url.contains('.m3u8') || url.contains('.mp4')) {
      return url;
    }

    // 2. Comprobación rápida por HTTP si no requiere navegador
    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Referer': url,
        },
      ).timeout(const Duration(seconds: 3));

      final body = response.body;

      // Restricción: No resolver captchas. Si aparece uno, abortar para pasar al siguiente
      if (_hasCaptcha(body)) {
        debugPrint('Captcha detectado en $url. Descartando servidor.');
        return null;
      }

      // Buscar m3u8 o mp4 en HTML o JavaScript
      final m3u8Match = RegExp(r'''https?://[^\s"'<>]+\.m3u8[^\s"'<>]*''').firstMatch(body);
      if (m3u8Match != null) {
        return m3u8Match.group(0);
      }

      final mp4Match = RegExp(r'''https?://[^\s"'<>]+\.mp4[^\s"'<>]*''').firstMatch(body);
      if (mp4Match != null) {
        return mp4Match.group(0);
      }
    } catch (_) {}

    // 3. Extracción mediante HeadlessInAppWebView interceptando peticiones de red
    return _extractWithHeadlessWebView(url);
  }

  /// Detecta si hay captchas conocidos para no perder tiempo
  static bool _hasCaptcha(String html) {
    final lower = html.toLowerCase();
    return lower.contains('g-recaptcha') ||
        lower.contains('cf-turnstile') ||
        lower.contains('hcaptcha') ||
        lower.contains('challenge-form') ||
        lower.contains('cf_chl_prog') ||
        lower.contains('just a moment...');
  }

  /// Carga la URL en un InAppWebView invisible interceptando las solicitudes a .m3u8 o .mp4
  Future<String?> _extractWithHeadlessWebView(String url) async {
    final completer = Completer<String?>();
    HeadlessInAppWebView? headless;

    headless = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(url)),
      initialSettings: InAppWebViewSettings(
        isInspectable: false,
        mediaPlaybackRequiresUserGesture: false,
        javaScriptEnabled: true,
        userAgent:
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      ),
      shouldInterceptRequest: (controller, request) async {
        final reqUrl = request.url.toString();

        if (reqUrl.contains('.m3u8') || reqUrl.contains('.mp4')) {
          if (!completer.isCompleted) {
            completer.complete(reqUrl);
          }
        }
        return null;
      },
      onLoadStop: (controller, url) async {
        // Verificar si la página contiene captchas
        final html = await controller.getHtml() ?? '';
        if (_hasCaptcha(html)) {
          if (!completer.isCompleted) completer.complete(null);
          return;
        }

        // Ejecutar extractor JS rápido por si ya cargó el video en el DOM
        final videoSrc = await controller.evaluateJavascript(source: '''
          (() => {
            const video = document.querySelector('video');
            if (video && video.src && (video.src.includes('.m3u8') || video.src.includes('.mp4'))) {
              return video.src;
            }
            return null;
          })();
        ''');

        if (videoSrc is String && videoSrc.isNotEmpty && !completer.isCompleted) {
          completer.complete(videoSrc);
        }
      },
    );

    try {
      await headless.run();
      final result = await completer.future.timeout(const Duration(seconds: 4));
      return result;
    } catch (_) {
      return null;
    } finally {
      headless.dispose();
    }
  }
}
