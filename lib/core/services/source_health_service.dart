import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:sembast/sembast.dart';
import '../storage/app_database.dart';

enum HealthStatus { healthy, degraded, down }

class SourceHealthData {
  final String sourceId;
  final int totalRequests;
  final int successfulResponses;
  final int failedResponses;
  final int totalLatencyMs;
  final DateTime? lastSuccess;
  final DateTime? lastFailure;
  final int consecutiveFailures;
  final double reliabilityScore;
  final int avgLatencyMs;
  final HealthStatus healthStatus;
  final double priorityScore;
  final int backoffMinutes;

  const SourceHealthData({
    required this.sourceId,
    this.totalRequests = 0,
    this.successfulResponses = 0,
    this.failedResponses = 0,
    this.totalLatencyMs = 0,
    this.lastSuccess,
    this.lastFailure,
    this.consecutiveFailures = 0,
    this.reliabilityScore = 1.0,
    this.avgLatencyMs = 200,
    this.healthStatus = HealthStatus.healthy,
    this.priorityScore = 1.0,
    this.backoffMinutes = 30,
  });

  String get statusString {
    switch (healthStatus) {
      case HealthStatus.healthy:
        return 'healthy';
      case HealthStatus.degraded:
        return 'degraded';
      case HealthStatus.down:
        return 'down';
    }
  }

  Map<String, dynamic> toMap() => {
        'source_id': sourceId,
        'total_requests': totalRequests,
        'successful_responses': successfulResponses,
        'failed_responses': failedResponses,
        'total_latency_ms': totalLatencyMs,
        'last_success': lastSuccess?.toIso8601String(),
        'last_failure': lastFailure?.toIso8601String(),
        'consecutive_failures': consecutiveFailures,
        'reliability_score': reliabilityScore,
        'avg_latency_ms': avgLatencyMs,
        'health_status': statusString,
        'priority_score': priorityScore,
        'backoff_minutes': backoffMinutes,
      };

  factory SourceHealthData.fromMap(Map<String, dynamic> map, String id) {
    final total = (map['total_requests'] as num?)?.toInt() ?? 0;
    final success = (map['successful_responses'] as num?)?.toInt() ?? 0;
    final fails = (map['failed_responses'] as num?)?.toInt() ?? 0;
    final latency = (map['total_latency_ms'] as num?)?.toInt() ?? 0;
    final consecFails = (map['consecutive_failures'] as num?)?.toInt() ?? 0;
    final backoff = (map['backoff_minutes'] as num?)?.toInt() ?? 30;

    DateTime? lSuccess;
    if (map['last_success'] != null) {
      lSuccess = DateTime.tryParse(map['last_success'].toString());
    }
    DateTime? lFailure;
    if (map['last_failure'] != null) {
      lFailure = DateTime.tryParse(map['last_failure'].toString());
    }

    final rel = total > 0 ? (success / total).clamp(0.0, 1.0) : 1.0;
    final avgLat = success > 0 ? (latency / success).round() : 200;

    HealthStatus status;
    if (rel >= 0.7 && consecFails < 3) {
      status = HealthStatus.healthy;
    } else if (rel < 0.3 || consecFails >= 5) {
      status = HealthStatus.down;
    } else {
      status = HealthStatus.degraded;
    }

    final normLat = (avgLat / 5000.0).clamp(0.0, 1.0);
    final pScore = (rel * 0.6) + ((1.0 - normLat) * 0.4);

    return SourceHealthData(
      sourceId: id,
      totalRequests: total,
      successfulResponses: success,
      failedResponses: fails,
      totalLatencyMs: latency,
      lastSuccess: lSuccess,
      lastFailure: lFailure,
      consecutiveFailures: consecFails,
      reliabilityScore: rel,
      avgLatencyMs: avgLat,
      healthStatus: status,
      priorityScore: pScore,
      backoffMinutes: backoff,
    );
  }
}

/// Motor central de salud y priorización dinámica de fuentes de contenido.
class SourceHealthService {
  static final SourceHealthService instance = SourceHealthService._internal();
  factory SourceHealthService() => instance;
  SourceHealthService._internal();

  static const String _kStoreName = 'source_health';
  final StoreRef<String, Map<String, dynamic>> _store =
      stringMapStoreFactory.store(_kStoreName);

  final Map<String, SourceHealthData> _memoryCache = {};
  bool _initialized = false;

  /// Notificador para cambios reactivos en la interfaz
  final ValueNotifier<int> changeNotifier = ValueNotifier<int>(0);

  static String normalizeSourceId(String raw) {
    final lower = raw.toLowerCase().trim();
    if (lower.contains('pelisplushd')) return 'pelisplushd';
    if (lower.contains('cuevana3')) return 'cuevana3';
    if (lower.contains('animeflv') && lower.contains('api')) return 'animeflv_api';
    if (lower.contains('animeflv')) return 'animeflv_api';
    if (lower.contains('cuevana')) return 'cuevana';
    if (lower.contains('pelisplus')) return 'pelisplus';
    if (lower.contains('cinecalidad')) return 'cinecalidad';
    if (lower.contains('seriesflix')) return 'seriesflix';
    if (lower.contains('cineby')) return 'cineby';
    if (lower.contains('tioplus')) return 'tioplus';
    if (lower.contains('tioanime')) return 'tioanime';
    if (lower.contains('jkanime')) return 'jkanime';
    if (lower.contains('canela')) return 'canelatv';
    if (lower.contains('telemundo')) return 'telemundo';
    if (lower.contains('thanhdat')) return 'thanhdattoday';
    if (lower.contains('embed69') || lower.contains('serieskao')) return 'embed69';
    if (lower.contains('unlimplay') || lower.contains('cinehax')) return 'unlimplay';
    final clean = lower.split('·').first.trim().replaceAll(RegExp(r'[^a-z0-9_]'), '');
    return clean.isNotEmpty ? clean : 'unknown';
  }

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      final db = await AppDatabase.instance.database;
      final records = await _store.find(db);
      for (final r in records) {
        _memoryCache[r.key] = SourceHealthData.fromMap(r.value, r.key);
      }
      _initialized = true;
    } catch (e) {
      debugPrint('[SourceHealth] Error al inicializar: $e');
    }
  }

  /// Registra una respuesta exitosa y actualiza las métricas de latencia y confiabilidad
  Future<void> recordSuccess(String sourceId, int latencyMs) async {
    await initialize();
    final current = _memoryCache[sourceId] ?? SourceHealthData(sourceId: sourceId);

    final total = current.totalRequests + 1;
    final success = current.successfulResponses + 1;
    final totalLat = current.totalLatencyMs + latencyMs;
    final avgLat = (totalLat / success).round();
    final rel = (success / total).clamp(0.0, 1.0);

    HealthStatus status;
    if (rel >= 0.7) {
      status = HealthStatus.healthy;
    } else if (rel < 0.3) {
      status = HealthStatus.down;
    } else {
      status = HealthStatus.degraded;
    }

    final normLat = (avgLat / 5000.0).clamp(0.0, 1.0);
    final pScore = (rel * 0.6) + ((1.0 - normLat) * 0.4);

    final updated = SourceHealthData(
      sourceId: sourceId,
      totalRequests: total,
      successfulResponses: success,
      failedResponses: current.failedResponses,
      totalLatencyMs: totalLat,
      lastSuccess: DateTime.now(),
      lastFailure: current.lastFailure,
      consecutiveFailures: 0,
      reliabilityScore: rel,
      avgLatencyMs: avgLat,
      healthStatus: status,
      priorityScore: pScore,
      backoffMinutes: 30, // resetea backoff al tener éxito
    );

    _memoryCache[sourceId] = updated;
    debugPrint('[SourceHealth] $sourceId éxito (${latencyMs}ms) → score: ${pScore.toStringAsFixed(2)} [${updated.statusString}]');

    await _saveToDisk(updated);
    changeNotifier.value++;
  }

  /// Registra una respuesta fallida (timeout, error 500, etc.)
  Future<void> recordFailure(String sourceId, String reason) async {
    await initialize();
    final current = _memoryCache[sourceId] ?? SourceHealthData(sourceId: sourceId);

    final total = current.totalRequests + 1;
    final fails = current.failedResponses + 1;
    final consecFails = current.consecutiveFailures + 1;
    final rel = current.successfulResponses > 0
        ? (current.successfulResponses / total).clamp(0.0, 1.0)
        : 0.0;
    final avgLat = current.avgLatencyMs;

    HealthStatus status;
    int backoff = current.backoffMinutes;
    if (rel < 0.3 || consecFails >= 5) {
      status = HealthStatus.down;
      if (consecFails % 3 == 0) {
        // Backoff exponencial con tope de 6 horas (360 minutos)
        backoff = (backoff * 2).clamp(30, 360);
      }
    } else if (rel < 0.7 || consecFails >= 3) {
      status = HealthStatus.degraded;
    } else {
      status = HealthStatus.healthy;
    }

    final normLat = (avgLat / 5000.0).clamp(0.0, 1.0);
    final pScore = (rel * 0.6) + ((1.0 - normLat) * 0.4);

    final updated = SourceHealthData(
      sourceId: sourceId,
      totalRequests: total,
      successfulResponses: current.successfulResponses,
      failedResponses: fails,
      totalLatencyMs: current.totalLatencyMs,
      lastSuccess: current.lastSuccess,
      lastFailure: DateTime.now(),
      consecutiveFailures: consecFails,
      reliabilityScore: rel,
      avgLatencyMs: avgLat,
      healthStatus: status,
      priorityScore: pScore,
      backoffMinutes: backoff,
    );

    _memoryCache[sourceId] = updated;
    debugPrint('[SourceHealth] $sourceId falló ($reason). Fallos consecutivos: $consecFails [${updated.statusString}]');

    await _saveToDisk(updated);
    changeNotifier.value++;
  }

  SourceHealthData getHealth(String sourceId) {
    return _memoryCache[sourceId] ?? SourceHealthData(sourceId: sourceId);
  }

  List<SourceHealthData> getAllHealth() {
    return _memoryCache.values.toList();
  }

  /// Resetea manualmente el estado de una fuente
  Future<void> resetSource(String sourceId) async {
    final updated = SourceHealthData(sourceId: sourceId);
    _memoryCache[sourceId] = updated;
    await _saveToDisk(updated);
    changeNotifier.value++;
  }

  /// Comprueba si una fuente marcada como DOWN puede reintentarse por expiración del backoff
  bool canRetryDownSource(String sourceId) {
    final data = _memoryCache[sourceId];
    if (data == null || data.healthStatus != HealthStatus.down) return true;
    if (data.lastFailure == null) return true;

    final diff = DateTime.now().difference(data.lastFailure!);
    return diff.inMinutes >= data.backoffMinutes;
  }

  /// Devuelve las fuentes candidatas ordenadas dinámicamente por salud y score de prioridad:
  /// 1. Excluye 'down' (salvo que ya deba reintentarse).
  /// 2. 'healthy' ordenadas por priorityScore descendente.
  /// 3. 'degraded' ordenadas por priorityScore descendente.
  /// 4. Empate: orden de prioridad declarada provista en [declaredPriorities].
  List<String> getOrderedSources({
    required List<String> candidates,
    Map<String, int> declaredPriorities = const {},
  }) {
    final validSources = <String>[];

    for (final id in candidates) {
      final health = getHealth(id);
      if (health.healthStatus == HealthStatus.down) {
        if (canRetryDownSource(id)) {
          validSources.add(id);
        } else {
          debugPrint('[SourceHealth] Omitiendo fuente down: $id (reintento en ${health.backoffMinutes}m)');
        }
      } else {
        validSources.add(id);
      }
    }

    validSources.sort((a, b) {
      final ha = getHealth(a);
      final hb = getHealth(b);

      // Priorizar estado: healthy (0) antes que degraded (1)
      final statusRankA = ha.healthStatus == HealthStatus.healthy ? 0 : 1;
      final statusRankB = hb.healthStatus == HealthStatus.healthy ? 0 : 1;
      if (statusRankA != statusRankB) {
        return statusRankA.compareTo(statusRankB);
      }

      // Comparar score de prioridad dinámico (mayor score = mejor)
      final scoreDiff = hb.priorityScore.compareTo(ha.priorityScore);
      if (scoreDiff != 0) return scoreDiff;

      // Desempate: prioridad declarada (menor número = mayor prioridad, ej. 1 antes que 3)
      final prioA = declaredPriorities[a] ?? 3;
      final prioB = declaredPriorities[b] ?? 3;
      return prioA.compareTo(prioB);
    });

    return validSources;
  }

  Future<void> _saveToDisk(SourceHealthData data) async {
    try {
      final db = await AppDatabase.instance.database;
      await _store.record(data.sourceId).put(db, data.toMap());
    } catch (e) {
      debugPrint('[SourceHealth] Error al guardar en Sembast: $e');
    }
  }
}
