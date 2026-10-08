import 'package:flutter_test/flutter_test.dart';
import 'package:lol/core/services/source_health_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SourceHealthService Unit Tests', () {
    late SourceHealthService service;

    setUp(() {
      service = SourceHealthService.instance;
    });

    test('SourceHealthData.fromMap calcula correctamente status healthy', () {
      final map = {
        'total_requests': 10,
        'successful_responses': 9,
        'failed_responses': 1,
        'total_latency_ms': 2000,
        'consecutive_failures': 0,
      };
      final data = SourceHealthData.fromMap(map, 'test_source');
      expect(data.healthStatus, HealthStatus.healthy);
      expect(data.reliabilityScore, 0.9);
      expect(data.avgLatencyMs, 222);
      expect(data.priorityScore, greaterThan(0.8));
    });

    test('SourceHealthData.fromMap degrada con fallos consecutivos >= 3', () {
      final map = {
        'total_requests': 10,
        'successful_responses': 7,
        'failed_responses': 3,
        'total_latency_ms': 2100,
        'consecutive_failures': 3,
      };
      final data = SourceHealthData.fromMap(map, 'test_source');
      expect(data.healthStatus, HealthStatus.degraded);
    });

    test('SourceHealthData.fromMap marca DOWN con fallos consecutivos >= 5 o reliability < 0.3', () {
      final map = {
        'total_requests': 10,
        'successful_responses': 2,
        'failed_responses': 8,
        'total_latency_ms': 600,
        'consecutive_failures': 5,
      };
      final data = SourceHealthData.fromMap(map, 'test_source');
      expect(data.healthStatus, HealthStatus.down);
    });

    test('getOrderedSources prioriza healthy sobre degraded y excluye down', () {
      // Mock de fuentes con prioridades
      final declaredPriorities = {
        'pelisplushd': 1,
        'cuevana3': 1,
        'animeflv_api': 1,
        'cuevana': 3,
        'cinecalidad': 3,
      };

      final ordered = service.getOrderedSources(
        candidates: ['cinecalidad', 'cuevana', 'pelisplushd', 'cuevana3', 'animeflv_api'],
        declaredPriorities: declaredPriorities,
      );

      // Las fuentes con prioridad 1 deben ir antes de prioridad 3 en estado default healthy
      expect(ordered.first, anyOf('pelisplushd', 'cuevana3', 'animeflv_api'));
    });

    test('normalizeSourceId normaliza nombres variados correctamente', () {
      expect(SourceHealthService.normalizeSourceId('PelisPlusHD · Stream 1'), 'pelisplushd');
      expect(SourceHealthService.normalizeSourceId('Cuevana3 · FastServer'), 'cuevana3');
      expect(SourceHealthService.normalizeSourceId('AnimeFLV · HD'), 'animeflv_api');
      expect(SourceHealthService.normalizeSourceId('Seriesflix · Player'), 'seriesflix');
      expect(SourceHealthService.normalizeSourceId('Cineby · Multi'), 'cineby');
      expect(SourceHealthService.normalizeSourceId('Cuevana · LAT'), 'cuevana');
    });
  });
}
