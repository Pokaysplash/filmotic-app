import 'dart:async';

/// Helper para diagnosticar compatibilidad DLNA / UPnP
/// Con la migración a `dart_cast`, el proxy HTTP local inyecta automáticamente
/// las cabeceras requeridas (Referer y User-Agent) y transmuxea HLS a MPEG-TS
/// para dispositivos DLNA como Xbox y Smart TVs.
class DlnaHelper {
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

  /// Con `dart_cast` el proxy HTTP local maneja la compatibilidad de todos los streams
  /// (HLS m3u8, MPEG-TS y MP4) inyectando cabeceras al servidor upstream.
  static Future<bool> isDlnaCompatible(String url, {String? serverName}) async {
    final cleanUrl = url.trim();
    if (cleanUrl.isEmpty) return false;
    return true;
  }

  /// Limpia la caché de compatibilidad
  static void clearCache() {}
}
