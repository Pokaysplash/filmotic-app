import 'dart:async';
import 'package:http/http.dart' as http;

/// Helper para diagnosticar y validar compatibilidad DLNA / UPnP
/// La mayoría de dispositivos DLNA (Xbox, Smart TV, TV Box) no soportan
/// cabeceras HTTP personalizadas (como Referer o User-Agent).
class DlnaHelper {
  static final Map<String, bool> _cache = {};

  /// Determina si la URL o servidor parece un MP4 directo
  static bool isLikelyMp4(String url, {String? serverName}) {
    final lowerUrl = url.toLowerCase();
    final lowerName = (serverName ?? '').toLowerCase();

    if (lowerUrl.contains('.mp4') ||
        lowerUrl.contains('/mp4') ||
        lowerUrl.contains('format=mp4') ||
        lowerUrl.contains('type=mp4') ||
        lowerUrl.contains('yourupload') ||
        lowerUrl.contains('mediafire') ||
        lowerUrl.contains('mega.nz')) {
      return true;
    }

    if (lowerName.contains('mp4') ||
        lowerName.contains('yourupload') ||
        lowerName.contains('mediafire')) {
      return true;
    }

    return false;
  }

  /// Verifica si el stream puede ser reproducido por un cliente DLNA
  /// haciendo una petición de prueba sin cabeceras Referer/User-Agent
  static Future<bool> isDlnaCompatible(String url, {String? serverName}) async {
    final cleanUrl = url.trim();
    if (cleanUrl.isEmpty) return false;

    if (_cache.containsKey(cleanUrl)) {
      return _cache[cleanUrl]!;
    }

    // Los MP4 directos casi siempre son compatibles con DLNA
    if (isLikelyMp4(cleanUrl, serverName: serverName)) {
      _cache[cleanUrl] = true;
      return true;
    }

    try {
      final uri = Uri.parse(cleanUrl);
      final client = http.Client();
      try {
        // Enviar HEAD sin cabeceras adicionales (como lo haría una Xbox o TV)
        final headRes = await client.head(uri).timeout(
          const Duration(milliseconds: 3500),
        );

        if (headRes.statusCode >= 200 && headRes.statusCode < 400) {
          _cache[cleanUrl] = true;
          return true;
        }

        // Si HEAD da 405 (Method Not Allowed), intentar GET con Range pequeño
        if (headRes.statusCode == 405) {
          final getRes = await client.get(
            uri,
            headers: {'Range': 'bytes=0-100'},
          ).timeout(const Duration(milliseconds: 3500));

          if (getRes.statusCode >= 200 && getRes.statusCode < 400) {
            _cache[cleanUrl] = true;
            return true;
          }
        }

        // Si devuelve 403, 401, 404 => Requiere autenticación/referer, incompatible con DLNA
        _cache[cleanUrl] = false;
        return false;
      } finally {
        client.close();
      }
    } catch (_) {
      // Si falla la conexión directa desnuda, DLNA no podrá reproducirlo
      _cache[cleanUrl] = false;
      return false;
    }
  }

  /// Limpia la caché de compatibilidad
  static void clearCache() {
    _cache.clear();
  }
}
