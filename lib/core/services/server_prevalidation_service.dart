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

  /// Valida una sola URL haciendo HEAD request o GET parcial (Range: bytes=0-512)
  Future<ServerValidationResult> validateUrl(String url) async {
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

    try {
      // 1. Intentar HEAD request
      final headRes = await http.head(
        uri,
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
          'Accept': '*/*',
        },
      ).timeout(Duration(seconds: timeoutSec));

      statusCode = headRes.statusCode;
      if ((statusCode >= 200 && statusCode < 400) || statusCode == 206) {
        isValid = true;
      }
    } catch (_) {
      // Si HEAD falla o es rechazado (ej. 405 Method Not Allowed), intentar GET parcial
    }

    if (!isValid) {
      try {
        final getRes = await http.get(
          uri,
          headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
            'Accept': '*/*',
            'Range': 'bytes=0-512',
          },
        ).timeout(Duration(seconds: timeoutSec));

        statusCode = getRes.statusCode;
        if ((statusCode >= 200 && statusCode < 400) || statusCode == 206) {
          isValid = true;
        }
      } catch (_) {
        statusCode = 0;
        isValid = false;
      }
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
  Future<List<Map<String, dynamic>>> filterValidServers(
    List<Map<String, dynamic>> servers, {
    void Function(double progress)? onProgress,
  }) async {
    if (servers.isEmpty) return [];

    final concurrency = RemoteConfigService.instance.config.player.preValidationConcurrency;
    final validServers = <Map<String, dynamic>>[];
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
          final res = await validateUrl(url);
          return res.isValid;
        }));

        for (int j = 0; j < chunk.length; j++) {
          if (results[j]) {
            validServers.add(chunk[j]);
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

    return validServers;
  }
}
