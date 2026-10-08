import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../core/services/source_health_service.dart';
import '../../../../core/services/backend_scraper_service.dart';
import '../../../../data/scrapers/base/registry.dart';
import '../../../../data/scrapers/base/scraper_context.dart';

class SourceHealthPage extends StatefulWidget {
  const SourceHealthPage({super.key});

  @override
  State<SourceHealthPage> createState() => _SourceHealthPageState();
}

class _SourceHealthPageState extends State<SourceHealthPage> {
  final SourceHealthService _healthService = SourceHealthService.instance;
  bool _testingAll = false;

  @override
  void initState() {
    super.initState();
    _healthService.initialize();
  }

  Color _getStatusColor(HealthStatus status) {
    switch (status) {
      case HealthStatus.healthy:
        return const Color(0xFF22C55E); // Verde
      case HealthStatus.degraded:
        return const Color(0xFFF59E0B); // Ámbar/Naranja
      case HealthStatus.down:
        return const Color(0xFFEF4444); // Rojo
    }
  }

  String _getStatusLabel(HealthStatus status) {
    switch (status) {
      case HealthStatus.healthy:
        return 'ÓPTIMA';
      case HealthStatus.degraded:
        return 'LENTA';
      case HealthStatus.down:
        return 'CAÍDA';
    }
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return 'Sin registros';
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Hace instantes';
    if (diff.inMinutes < 60) return 'Hace ${diff.inMinutes}m';
    if (diff.inHours < 24) return 'Hace ${diff.inHours}h';
    return '${dt.day}/${dt.month} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _testSource(String sourceId) async {
    final f = fuenteById(sourceId);
    if (f == null || f.search == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fuente $sourceId no tiene buscador configurado')),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Probando conectividad con ${f.label}...')),
    );

    final sw = Stopwatch()..start();
    try {
      final items = await f.search!('Batman').timeout(const Duration(seconds: 8));
      sw.stop();
      if (items.isNotEmpty) {
        await _healthService.recordSuccess(sourceId, sw.elapsedMilliseconds);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✓ ${f.label} respondió en ${sw.elapsedMilliseconds}ms (${items.length} items)'),
              backgroundColor: const Color(0xFF22C55E),
            ),
          );
        }
      } else {
        await _healthService.recordFailure(sourceId, 'Sin resultados');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('⚠ ${f.label} no devolvió resultados'),
              backgroundColor: const Color(0xFFF59E0B),
            ),
          );
        }
      }
    } catch (e) {
      sw.stop();
      await _healthService.recordFailure(sourceId, e.toString());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✕ ${f.label} falló: $e'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    }
  }

  Future<void> _testAllSources() async {
    setState(() => _testingAll = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Iniciando diagnóstico federado de todas las fuentes...')),
    );

    for (final f in fuentesRegistry) {
      if (f.enabled && f.search != null) {
        await _testSource(f.id);
      }
    }

    if (mounted) {
      setState(() => _testingAll = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Diagnóstico completado')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F12),
      appBar: AppBar(
        backgroundColor: const Color(0xFF141418),
        elevation: 0,
        title: const Text(
          'Estado de las Fuentes',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          IconButton(
            icon: _testingAll
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.refresh_rounded),
            tooltip: 'Probar todas',
            onPressed: _testingAll ? null : _testAllSources,
          ),
        ],
      ),
      body: ValueListenableBuilder<int>(
        valueListenable: _healthService.changeNotifier,
        builder: (context, _, __) {
          final sources = fuentesRegistry;

          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            children: [
              _buildSummaryHeader(sources),
              const SizedBox(height: 18),
              _buildBackendHealthCard(),
              Text(
                'FUENTES LOCALES REGISTRADAS (${sources.length})',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 10),
              ...sources.map((fuente) => _buildSourceHealthCard(fuente)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBackendHealthCard() {
    return ValueListenableBuilder<BackendHealthMetrics>(
      valueListenable: BackendScraperService.instance.metricsNotifier,
      builder: (context, metrics, _) {
        final isEnabled = BackendScraperService.instance.isEnabled;
        final isOnline = metrics.status == BackendStatus.online;
        final isChecking = metrics.status == BackendStatus.checking;
        final statusColor = !isEnabled
            ? Colors.white38
            : isOnline
                ? const Color(0xFF22C55E)
                : const Color(0xFFEF4444);
        final statusLabel = !isEnabled
            ? 'DESHABILITADO'
            : isChecking
                ? 'COMPROBANDO...'
                : isOnline
                    ? 'ONLINE'
                    : 'OFFLINE';

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E26),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isOnline
                  ? const Color(0xFF22C55E).withValues(alpha: 0.35)
                  : Colors.white.withValues(alpha: 0.08),
              width: isOnline ? 1.5 : 1.0,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF6B00).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.cloud_sync_rounded, color: Color(0xFFFF6B00), size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Backend de Scraping Centralizado',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        Text(
                          metrics.baseUrl.isNotEmpty ? metrics.baseUrl : BackendScraperService.instance.baseUrl,
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: statusColor.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          statusLabel,
                          style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Latencia', style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 10)),
                          const SizedBox(height: 2),
                          Text(
                            metrics.pingMs != null ? '${metrics.pingMs} ms' : '--',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Proveedores', style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 10)),
                          const SizedBox(height: 2),
                          Text(
                            metrics.activeProviders > 0 ? '${metrics.activeProviders} activos' : '13-50+',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Éxitos', style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 10)),
                          const SizedBox(height: 2),
                          Text(
                            '${metrics.successfulResolutions}',
                            style: const TextStyle(color: Color(0xFF22C55E), fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    metrics.lastCheck != null
                        ? 'Última verificación: ${_formatDate(metrics.lastCheck)}'
                        : 'No verificado recientemente',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: isChecking
                        ? const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(strokeWidth: 1.8, color: Color(0xFFFF6B00)),
                          )
                        : const Icon(Icons.speed_rounded, size: 14, color: Color(0xFFFF6B00)),
                    label: const Text('Probar Ping', style: TextStyle(fontSize: 12, color: Color(0xFFFF6B00))),
                    onPressed: isChecking
                        ? null
                        : () async {
                            final ok = await BackendScraperService.instance.checkHealth(force: true);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(ok
                                      ? '✓ Backend respondió en ${BackendScraperService.instance.metrics.pingMs}ms'
                                      : '✕ Backend no disponible en ${BackendScraperService.instance.baseUrl}'),
                                  backgroundColor: ok ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
                                ),
                              );
                            }
                          },
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSummaryHeader(List<Fuente> sources) {
    int healthyCount = 0;
    int degradedCount = 0;
    int downCount = 0;

    for (final f in sources) {
      final h = _healthService.getHealth(f.id);
      switch (h.healthStatus) {
        case HealthStatus.healthy:
          healthyCount++;
          break;
        case HealthStatus.degraded:
          degradedCount++;
          break;
        case HealthStatus.down:
          downCount++;
          break;
      }
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A22),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.monitor_heart_rounded, color: Color(0xFFFF6B00), size: 22),
              SizedBox(width: 10),
              Text(
                'Monitoreo Dinámico de Red',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Filmotic evalúa en tiempo real la tasa de éxito y latencia de cada servidor. Las fuentes caídas son aisladas automáticamente sin interrumpir tu experiencia.',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildCountBadge('Óptimas', healthyCount, const Color(0xFF22C55E)),
              const SizedBox(width: 8),
              _buildCountBadge('Lentas', degradedCount, const Color(0xFFF59E0B)),
              const SizedBox(width: 8),
              _buildCountBadge('Caídas', downCount, const Color(0xFFEF4444)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCountBadge(String label, int count, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Text(
              '$count',
              style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(color: color.withValues(alpha: 0.9), fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSourceHealthCard(Fuente fuente) {
    final health = _healthService.getHealth(fuente.id);
    final statusColor = _getStatusColor(health.healthStatus);
    final statusLabel = _getStatusLabel(health.healthStatus);
    final relPct = (health.reliabilityScore * 100).round();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF16161D),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: statusColor.withValues(alpha: 0.25), width: 1.2),
      ),
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: statusColor,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: statusColor.withValues(alpha: 0.5),
                blurRadius: 6,
                spreadRadius: 1,
              ),
            ],
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                fuente.label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: statusColor.withValues(alpha: 0.4)),
              ),
              child: Text(
                statusLabel,
                style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            children: [
              Text(
                'Éxito: $relPct%',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '·  Lat: ${health.avgLatencyMs}ms',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '·  Prio: ${fuente.priority}',
                style: TextStyle(
                  color: fuente.priority == 1 ? const Color(0xFFFF6B00) : Colors.white.withValues(alpha: 0.4),
                  fontSize: 12,
                  fontWeight: fuente.priority == 1 ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Divider(color: Colors.white10),
                const SizedBox(height: 6),
                // Barra de rendimiento
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: health.reliabilityScore.clamp(0.0, 1.0),
                    backgroundColor: Colors.white12,
                    valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                    minHeight: 6,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _metricCol('Peticiones', '${health.totalRequests}'),
                    _metricCol('Éxitos', '${health.successfulResponses}'),
                    _metricCol('Fallos', '${health.failedResponses}'),
                    _metricCol('Score', health.priorityScore.toStringAsFixed(2)),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Último éxito: ${_formatDate(health.lastSuccess)}',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11),
                    ),
                    Text(
                      'Último fallo: ${_formatDate(health.lastFailure)}',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () => _testSource(fuente.id),
                        icon: const Icon(Icons.speed_rounded, size: 16),
                        label: const Text('Probar ahora', style: TextStyle(fontSize: 12)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: 0.05),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      tooltip: 'Reiniciar métricas',
                      onPressed: () async {
                        await _healthService.resetSource(fuente.id);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Métricas de ${fuente.label} reiniciadas')),
                          );
                        }
                      },
                      icon: const Icon(Icons.restore_rounded, size: 16, color: Colors.white70),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricCol(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}
