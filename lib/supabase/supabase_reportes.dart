import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/constants/versiones.dart';
import 'supabase_admin_constants.dart';

/// Servicio centralizado para enviar reportes de servidores caídos o
/// solicitudes de contenido sin servidores al proyecto ADMIN de Supabase.
///
/// No requiere que el usuario configure nada ni inicie sesión.
class SupabaseReportesService {
  SupabaseReportesService._();

  static SupabaseClient? _adminClient;
  static final Set<String> _sentSessionKeys = <String>{};

  static SupabaseClient? _getClient() {
    if (_adminClient != null) return _adminClient;
    if (kAdminSupabaseUrl.isEmpty ||
        kAdminSupabaseAnonKey.isEmpty ||
        kAdminSupabaseUrl.contains('TU_PROYECTO')) {
      return null;
    }
    _adminClient = SupabaseClient(kAdminSupabaseUrl, kAdminSupabaseAnonKey);
    return _adminClient;
  }

  /// Envía un reporte a la tabla `reportes_servidores`.
  ///
  /// [tipoReporte]: `'sin_servidores'` | `'servidor_caido'` | `'audio_mal'`
  /// [plataforma]: `'mobile'` | `'tv'`
  static Future<bool> enviarReporte({
    required int tmdbId,
    required String titulo,
    required String mediaType,
    required String tipoReporte,
    required String plataforma,
    int? temporada,
    int? episodio,
    String? servidorNombre,
    String? servidorUrl,
    String? fuente,
    String? detalle,
  }) async {
    final dedupKey =
        '$tmdbId|$mediaType|${temporada ?? 0}|${episodio ?? 0}|$tipoReporte|${servidorNombre ?? ''}';
    if (_sentSessionKeys.contains(dedupKey)) {
      return true;
    }

    final client = _getClient();
    if (client == null) return false;

    try {
      await client.from('reportes_servidores').insert({
        'tmdb_id': tmdbId,
        'titulo': titulo.trim(),
        'media_type': mediaType.toLowerCase() == 'tv' ? 'tv' : 'movie',
        'temporada': temporada,
        'episodio': episodio,
        'tipo_reporte': tipoReporte,
        'servidor_nombre': servidorNombre,
        'servidor_url': servidorUrl,
        'fuente': fuente,
        'detalle': detalle,
        'app_version': VersionService.currentVersionName,
        'plataforma': plataforma,
      });
      _sentSessionKeys.add(dedupKey);
      return true;
    } catch (e) {
      debugPrint('[SupabaseReportes] Error enviando reporte: $e');
      return false;
    }
  }
}

