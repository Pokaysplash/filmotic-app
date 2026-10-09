import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'remote_config_service.dart';
import 'source_health_service.dart';

enum BackendStatus { disabled, checking, online, offline }

class BackendHealthMetrics {
  final BackendStatus status;
  final int? pingMs;
  final DateTime? lastCheck;
  final int activeProviders;
  final int successfulResolutions;
  final int failedResolutions;
  final String? lastError;
  final String baseUrl;

  const BackendHealthMetrics({
    this.status = BackendStatus.disabled,
    this.pingMs,
    this.lastCheck,
    this.activeProviders = 0,
    this.successfulResolutions = 0,
    this.failedResolutions = 0,
    this.lastError,
    this.baseUrl = '',
  });

  BackendHealthMetrics copyWith({
    BackendStatus? status,
    int? pingMs,
    DateTime? lastCheck,
    int? activeProviders,
    int? successfulResolutions,
    int? failedResolutions,
    String? lastError,
    String? baseUrl,
  }) {
    return BackendHealthMetrics(
      status: status ?? this.status,
      pingMs: pingMs ?? this.pingMs,
      lastCheck: lastCheck ?? this.lastCheck,
      activeProviders: activeProviders ?? this.activeProviders,
      successfulResolutions: successfulResolutions ?? this.successfulResolutions,
      failedResolutions: failedResolutions ?? this.failedResolutions,
      lastError: lastError ?? this.lastError,
      baseUrl: baseUrl ?? this.baseUrl,
    );
  }
}

/// Cliente unificado para backends de scraping centralizados (CinePro Core, TMDB-Embed-API, OMSS).
/// Permite resolver 13 a 50+ proveedores en la nube y hace fallback transparente a los scrapers locales.
class BackendScraperService {
  BackendScraperService._();
  static final BackendScraperService instance = BackendScraperService._();

  final ValueNotifier<BackendHealthMetrics> metricsNotifier =
      ValueNotifier<BackendHealthMetrics>(const BackendHealthMetrics());

  BackendHealthMetrics get metrics => metricsNotifier.value;

  FilmoticBackendConfig get config {
    try {
      return RemoteConfigService.instance.config.backend;
    } catch (_) {
      return const FilmoticBackendConfig();
    }
  }

  bool get isEnabled => config.enabled;
  String get baseUrl => config.baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
  Duration get timeout => Duration(seconds: config.timeoutSeconds);

  DateTime? _lastHealthCheck;
  bool _isCheckingHealth = false;

  /// Verifica la disponibilidad del backend mediante `/api/health`, `/health` o `/api/status`.
  Future<bool> checkHealth({bool force = false}) async {
    if (!isEnabled) {
      metricsNotifier.value = metrics.copyWith(
        status: BackendStatus.disabled,
        baseUrl: baseUrl,
      );
      return false;
    }

    if (!force &&
        _lastHealthCheck != null &&
        DateTime.now().difference(_lastHealthCheck!) < const Duration(seconds: 30)) {
      return metrics.status == BackendStatus.online;
    }

    if (_isCheckingHealth) return metrics.status == BackendStatus.online;
    _isCheckingHealth = true;

    metricsNotifier.value = metrics.copyWith(
      status: BackendStatus.checking,
      baseUrl: baseUrl,
    );

    final stopwatch = Stopwatch()..start();
    try {
      // 1. Probar endpoints típicos de liveness
      final endpoints = ['/api/health', '/health', '/api/status', '/'];
      http.Response? okResponse;
      int detectedProviders = metrics.activeProviders;

      for (final ep in endpoints) {
        try {
          final uri = Uri.parse('$baseUrl$ep');
          final res = await http.get(uri).timeout(const Duration(seconds: 4));
          if (res.statusCode >= 200 && res.statusCode < 400) {
            okResponse = res;
            // Intentar detectar cantidad de proveedores si devuelve json
            try {
              final body = jsonDecode(res.body);
              if (body is Map && body['providers'] is List) {
                detectedProviders = (body['providers'] as List).length;
              } else if (body is Map && body['providers'] is Map) {
                detectedProviders = (body['providers'] as Map).length;
              }
            } catch (_) {}
            break;
          }
        } catch (_) {}
      }

      stopwatch.stop();
      _lastHealthCheck = DateTime.now();

      if (okResponse != null) {
        final ping = stopwatch.elapsedMilliseconds;
        metricsNotifier.value = metrics.copyWith(
          status: BackendStatus.online,
          pingMs: ping,
          lastCheck: _lastHealthCheck,
          activeProviders: detectedProviders > 0 ? detectedProviders : 13,
          lastError: null,
          baseUrl: baseUrl,
        );
        unawaited(SourceHealthService.instance.recordSuccess('backend', ping));
        _isCheckingHealth = false;
        return true;
      } else {
        metricsNotifier.value = metrics.copyWith(
          status: BackendStatus.offline,
          lastCheck: _lastHealthCheck,
          lastError: 'HTTP endpoints no respondieron con éxito',
          baseUrl: baseUrl,
        );
        unawaited(SourceHealthService.instance.recordFailure('backend', 'Endpoints no respondieron'));
        _isCheckingHealth = false;
        return false;
      }
    } catch (e) {
      stopwatch.stop();
      _lastHealthCheck = DateTime.now();
      metricsNotifier.value = metrics.copyWith(
        status: BackendStatus.offline,
        lastCheck: _lastHealthCheck,
        lastError: e.toString(),
        baseUrl: baseUrl,
      );
      unawaited(SourceHealthService.instance.recordFailure('backend', e.toString()));
      _isCheckingHealth = false;
      return false;
    }
  }

  /// Obtiene fuentes/streams reproducibles desde el backend por TMDB ID.
  /// Compatible con TMDB-Embed-API, CinePro Core y OMSS.
  Future<List<Map<String, dynamic>>> getSources({
    required String tmdbId,
    required String mediaType,
    int? season,
    int? episode,
  }) async {
    if (!isEnabled || tmdbId.isEmpty) return [];

    final isLocalhost = baseUrl.contains('localhost') || baseUrl.contains('127.0.0.1');
    // Si apunta a localhost y no está online verificado, no bloquear la reproducción
    if (isLocalhost && metrics.status != BackendStatus.online) {
      return [];
    }

    if (metrics.status == BackendStatus.offline) {
      return [];
    }

    final normType = (mediaType.toLowerCase().contains('tv') ||
            mediaType.toLowerCase().contains('serie'))
        ? 'series'
        : 'movie';

    final stopwatch = Stopwatch()..start();
    developer.log(
      'Consultando backend scraper en $baseUrl para $normType TMDB: $tmdbId (s:$season e:$episode)',
      name: 'BackendScraperService',
    );

    // Lista de candidatos de rutas REST para compatibilidad total con distintos backends
    final queryParams = <String, String>{};
    if (normType == 'series' && season != null && episode != null) {
      queryParams['season'] = season.toString();
      queryParams['episode'] = episode.toString();
    }

    final candidatePaths = [
      // 1. TMDB-Embed-API standard
      '/api/streams/$normType/$tmdbId',
      // 2. CinePro Core / OMSS v1
      '/api/v1/sources',
      // 3. Generic source endpoint
      '/api/sources',
    ];

    List<Map<String, dynamic>> resolvedServers = [];
    final fastTimeout = Duration(milliseconds: (config.timeoutSeconds * 1000).clamp(1500, 3500));

    for (final path in candidatePaths) {
      try {
        Uri uri;
        if (path == '/api/v1/sources' || path == '/api/sources') {
          final q = Map<String, String>.from(queryParams);
          q['tmdbId'] = tmdbId;
          q['type'] = normType == 'series' ? 'tv' : 'movie';
          uri = Uri.parse('$baseUrl$path').replace(queryParameters: q);
        } else {
          uri = queryParams.isEmpty
              ? Uri.parse('$baseUrl$path')
              : Uri.parse('$baseUrl$path').replace(queryParameters: queryParams);
        }

        final res = await http.get(uri).timeout(fastTimeout);
        if (res.statusCode == 200 && res.body.isNotEmpty) {
          final parsed = jsonDecode(res.body);
          resolvedServers = parseStreamsResponse(parsed);
          if (resolvedServers.isNotEmpty) {
            break;
          }
        }
      } catch (e) {
        developer.log('Intento fallido en $path: $e', name: 'BackendScraperService');
      }
    }

    stopwatch.stop();

    if (resolvedServers.isNotEmpty) {
      metricsNotifier.value = metrics.copyWith(
        status: BackendStatus.online,
        successfulResolutions: metrics.successfulResolutions + 1,
        pingMs: stopwatch.elapsedMilliseconds,
        lastCheck: DateTime.now(),
        lastError: null,
      );
      unawaited(SourceHealthService.instance.recordSuccess('backend', stopwatch.elapsedMilliseconds));
      developer.log(
        'Backend resolvió ${resolvedServers.length} streams exitosamente en ${stopwatch.elapsedMilliseconds}ms',
        name: 'BackendScraperService',
      );
    } else {
      metricsNotifier.value = metrics.copyWith(
        failedResolutions: metrics.failedResolutions + 1,
        lastCheck: DateTime.now(),
      );
      unawaited(SourceHealthService.instance.recordFailure('backend', 'Sin streams disponibles'));
      developer.log(
        'Backend no devolvió streams. Se activará fallback a scrapers locales.',
        name: 'BackendScraperService',
      );
    }

    return resolvedServers;
  }

  /// Parsea respuestas heterogéneas (TMDB-Embed-API, CinePro, OMSS) al formato de Filmotic.
  List<Map<String, dynamic>> parseStreamsResponse(dynamic data) {
    final List<Map<String, dynamic>> list = [];

    List<dynamic> rawItems = [];
    if (data is List) {
      rawItems = data;
    } else if (data is Map) {
      if (data['streams'] is List) {
        rawItems = data['streams'] as List;
      } else if (data['sources'] is List) {
        rawItems = data['sources'] as List;
      } else if (data['data'] is List) {
        rawItems = data['data'] as List;
      }
    }

    for (int i = 0; i < rawItems.length; i++) {
      final item = rawItems[i];
      if (item is! Map) continue;

      final url = (item['url'] ?? item['streamUrl'] ?? item['file'] ?? '').toString();
      if (url.isEmpty || !url.startsWith('http')) continue;

      final rawProvider = (item['provider'] ?? item['name'] ?? item['server'] ?? 'Stream').toString();
      final quality = (item['quality'] ?? item['res'] ?? '1080p').toString();
      final title = (item['title'] ?? 'Opción ${i + 1}').toString();

      // Headers opcionales que el reproductor debe inyectar (Referer, User-Agent)
      final rawHeaders = item['headers'];
      final Map<String, String> headers = {};
      if (rawHeaders is Map) {
        rawHeaders.forEach((k, v) {
          headers[k.toString()] = v.toString();
        });
      }

      // Idioma detectado
      String idioma = 'latino';
      final langHint = '${item['lang'] ?? ''} ${item['language'] ?? ''} $title'.toLowerCase();
      if (langHint.contains('castellano') || langHint.contains('esp') || langHint.contains('es_es')) {
        idioma = 'castellano';
      } else if (langHint.contains('sub') || langHint.contains('vos') || langHint.contains('en_us')) {
        idioma = 'subtitulado';
      } else if (langHint.contains('lat') || langHint.contains('latino')) {
        idioma = 'latino';
      }

      final isM3u8 = url.contains('.m3u8');

      list.add({
        'servidor_nombre': 'Backend · $rawProvider',
        'servidor_url': url,
        'calidad': quality,
        'idioma': idioma,
        'headers': headers,
        'fuente': 'backend',
        'fuente_id': 'backend_${rawProvider.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '')}',
        'is_verified': true,
        if (isM3u8) 'resolved_m3u8': url,
        'peso': 150, // Prioridad superior a los scrapers locales
        'title': title,
      });
    }

    return list;
  }

  /// Búsqueda federada a través del backend si soporta `/api/search`.
  Future<List<Map<String, dynamic>>> search(String query) async {
    if (!isEnabled || query.trim().isEmpty) return [];

    try {
      final uri = Uri.parse('$baseUrl/api/search').replace(
        queryParameters: {'q': query.trim()},
      );
      final res = await http.get(uri).timeout(timeout);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data is List) {
          return data.whereType<Map<String, dynamic>>().toList();
        } else if (data is Map && data['results'] is List) {
          return (data['results'] as List).whereType<Map<String, dynamic>>().toList();
        }
      }
    } catch (e) {
      developer.log('Error buscando en backend: $e', name: 'BackendScraperService');
    }
    return [];
  }

  /// Consulta de ficha o detalles por TMDB ID si el backend lo implementa.
  Future<Map<String, dynamic>?> getDetails(String tmdbId, String mediaType) async {
    if (!isEnabled || tmdbId.isEmpty) return null;

    try {
      final uri = Uri.parse('$baseUrl/api/details/$mediaType/$tmdbId');
      final res = await http.get(uri).timeout(timeout);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data is Map<String, dynamic>) {
          return data;
        }
      }
    } catch (_) {}
    return null;
  }
}
