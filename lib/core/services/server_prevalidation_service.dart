import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:sembast/sembast.dart';
import '../storage/app_database.dart';
import 'remote_config_service.dart';

/// Resultado de la validación de un servidor
class ServerValidationResult {
  final bool isValid;
  final int statusCode;
  final DateTime timestamp;

  const ServerValidationResult({
    required this.isValid,
    required this.statusCode,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() => {
        'valid': isValid,
        'status_code': statusCode,
        'timestamp': timestamp.toIso8601String(),
      };

  factory ServerValidationResult.fromMap(Map<String, dynamic> map) {
    return ServerValidationResult(
      isValid: map['valid'] == true,
      statusCode: (map['status_code'] as num?)?.toInt() ?? 0,
      timestamp: DateTime.tryParse(map['timestamp']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}

/// Servicio de pre-validación de servidores en background (Bloque D.7)
/// Valida servidores mediante HEAD request o GET parcial con timeout de 5s,
/// pool de concurrencia máxima 5 y caché Sembast `server_validation_cache` (TTL 15 min).
class ServerPreValidationService {
  static final ServerPreValidationService instance = ServerPreValidationService._internal();
  ServerPreValidationService._internal();

  final StoreRef<String, dynamic> _store = stringMapStoreFactory.store('server_validation_cache');

  /// Notificador del estado de validación en background (para spinner en audífonos)
  final ValueNotifier<bool> isValidatingNotifier = ValueNotifier<bool>(false);
  final StreamController<void> _validationCompletedController = StreamController<void>.broadcast();
  Stream<void> get onValidationBatchCompleted => _validationCompletedController.stream;

  String _hashUrl(String url) {
    return md5.convert(utf8.encode(url.trim().toLowerCase())).toString();
  }

  /// Consulta la caché Sembast con TTL de 15 minutos (o según config)
  Future<ServerValidationResult?> getCachedResult(String url) async {
    if (url.trim().isEmpty) return null;
    try {
      final db = await AppDatabase.instance.database;
      final key = _hashUrl(url);
      final record = await _store.record(key).get(db);
      if (record == null) return null;

      final ttlMinutes = RemoteConfigService.instance.config.player.preValidationCacheTtlMinutes;
      final result = ServerValidationResult.fromMap(Map<String, dynamic>.from(record));
      if (DateTime.now().difference(result.timestamp).inMinutes >= ttlMinutes) {
        // Expirado
        return null;
      }
      return result;
    } catch (_) {
      return null;
    }
  }

  /// Guarda en la caché Sembast el resultado de validación
  Future<void> saveCachedResult(String url, ServerValidationResult result) async {
    if (url.trim().isEmpty) return;
    try {
      final db = await AppDatabase.instance.database;
      final key = _hashUrl(url);
      await _store.record(key).put(db, result.toMap());
    } catch (_) {}
  }

  /// Valida una sola URL haciendo GET parcial (Range: bytes=0-1024) con timeout de 15s
  Future<ServerValidationResult> validateUrl(
    String url, {
    String? referer,
    Map<String, String>? extraHeaders,
  }) async {
    final cleanUrl = url.trim();
    if (cleanUrl.isEmpty) {
      return ServerValidationResult(isValid: false, statusCode: 0, timestamp: DateTime.now());
    }

    final cached = await getCachedResult(cleanUrl);
    if (cached != null) {
      return cached;
    }

    final timeoutSec = RemoteConfigService.instance.config.player.preValidationTimeoutSeconds;
    final uri = Uri.tryParse(cleanUrl);
    if (uri == null || !uri.hasScheme) {
      final res = ServerValidationResult(isValid: false, statusCode: 0, timestamp: DateTime.now());
      await saveCachedResult(cleanUrl, res);
      return res;
    }

    int statusCode = 0;
    bool isValid = false;

    final headers = <String, String>{
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
      'Accept': '*/*',
      'Range': 'bytes=0-1024',
    };
    if (referer != null && referer.isNotEmpty) {
      headers['Referer'] = referer;
    } else {
      headers['Referer'] = '${uri.scheme}://${uri.host}/';
    }
    if (extraHeaders != null) {
      headers.addAll(extraHeaders);
    }

    final client = http.Client();
    try {
      final request = http.Request('GET', uri);
      request.headers.addAll(headers);
      request.followRedirects = true;
      request.maxRedirects = 5;

      final streamedResponse = await client.send(request).timeout(Duration(seconds: timeoutSec));
      statusCode = streamedResponse.statusCode;

      // WAVE 12.6: Códigos considerados "probablemente válidos"
      // 200-399 (éxito y redirecciones seguidas)
      // 206 (Partial Content)
      // 401 y 403 (pueden funcionar con Referer/cookies específicas al reproducir en ExoPlayer)
      if ((statusCode >= 200 && statusCode < 400) ||
          statusCode == 206 ||
          statusCode == 401 ||
          statusCode == 403) {
        isValid = true;
      }
    } catch (_) {
      // Errores de red o timeout: no descartar fatalmente, se marcan como no verificados
      statusCode = 0;
      isValid = false;
    } finally {
      client.close();
    }

    final result = ServerValidationResult(
      isValid: isValid,
      statusCode: statusCode,
      timestamp: DateTime.now(),
    );

    await saveCachedResult(cleanUrl, result);
    return result;
  }

  /// Ejecuta validaciones en paralelo con límite de concurrencia (máximo 5)
  /// NUNCA elimina servidores: los que pasan van al inicio (verificados),
  /// y los que no se pudieron verificar se colocan al final pero siguen disponibles.
  Future<List<Map<String, dynamic>>> filterValidServers(
    List<Map<String, dynamic>> servers, {
    void Function(double progress)? onProgress,
  }) async {
    if (servers.isEmpty) return [];

    final concurrency = RemoteConfigService.instance.config.player.preValidationConcurrency;
    final verified = <Map<String, dynamic>>[];
    final unverified = <Map<String, dynamic>>[];
    int completed = 0;

    isValidatingNotifier.value = true;
    try {
      // Procesar en chunks de concurrencia
      for (int i = 0; i < servers.length; i += concurrency) {
        final end = (i + concurrency < servers.length) ? i + concurrency : servers.length;
        final chunk = servers.sublist(i, end);

        final results = await Future.wait(chunk.map((srv) async {
          final url = (srv['resolved_m3u8'] ?? srv['servidor_url'] ?? srv['url'] ?? '').toString();
          if (url.isEmpty) return false;

          String? ref = srv['referer']?.toString();
          Map<String, String>? hdrs;
          if (srv['headers'] is Map) {
            hdrs = (srv['headers'] as Map).map((k, v) => MapEntry(k.toString(), v.toString()));
            ref ??= hdrs['Referer'] ?? hdrs['referer'];
          }
          final res = await validateUrl(url, referer: ref, extraHeaders: hdrs);
          return res.isValid;
        }));

        for (int j = 0; j < chunk.length; j++) {
          final srvCopy = Map<String, dynamic>.from(chunk[j]);
          srvCopy['_is_verified'] = results[j];
          if (results[j]) {
            verified.add(srvCopy);
          } else {
            unverified.add(srvCopy);
          }
        }

        completed += chunk.length;
        onProgress?.call(completed / servers.length);
        _validationCompletedController.add(null);
      }
    } finally {
      isValidatingNotifier.value = false;
      _validationCompletedController.add(null);
    }

    // Regla estricta: NUNCA ocultar servidores. Retornamos todos (verificados primero)
    return [...verified, ...unverified];
  }
}
