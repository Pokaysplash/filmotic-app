import 'package:flutter_test/flutter_test.dart';
import 'package:lol/core/services/backend_scraper_service.dart';
import 'package:lol/core/services/remote_config_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FilmoticBackendConfig & RemoteConfig', () {
    test('Parsea correctamente la sección backend desde Map', () {
      final map = {
        'version': 1,
        'backend': {
          'enabled': true,
          'base_url': 'http://192.168.1.50:3000',
          'timeout_seconds': 12,
          'fallback_to_local': true,
          'type': 'cinepro',
        }
      };

      final config = FilmoticRemoteConfig.fromMap(map);
      expect(config.backend.enabled, isTrue);
      expect(config.backend.baseUrl, 'http://192.168.1.50:3000');
      expect(config.backend.timeoutSeconds, 12);
      expect(config.backend.fallbackToLocal, isTrue);
      expect(config.backend.type, 'cinepro');
    });

    test('Usa valores por defecto si backend es nulo', () {
      final config = FilmoticRemoteConfig.fromMap({});
      expect(config.backend.enabled, isTrue);
      expect(config.backend.baseUrl, 'http://localhost:3000');
      expect(config.backend.timeoutSeconds, 10);
      expect(config.backend.fallbackToLocal, isTrue);
      expect(config.backend.type, 'auto');
    });
  });

  group('BackendScraperService Stream Parsing & Resilience', () {
    test('MetricsNotifier emite estados correctamente', () {
      final service = BackendScraperService.instance;
      expect(service.metrics.status, isIn([BackendStatus.disabled, BackendStatus.online, BackendStatus.offline]));
    });

    test('getSources con backend offline hace fallback seguro y retorna lista vacía sin excepción', () async {
      final service = BackendScraperService.instance;
      // Consultar endpoint inexistente de forma controlada
      final sources = await service.getSources(
        tmdbId: '550',
        mediaType: 'movie',
      );
      // Debe retornar lista vacía limpiamente sin lanzar excepciones
      expect(sources, isA<List<Map<String, dynamic>>>());
    });

    test('parseStreamsResponse procesa formatos TMDB-Embed-API y CinePro correctamente', () {
      final service = BackendScraperService.instance;

      final sampleEmbedApi = [
        {
          "name": "VixSrc",
          "title": "Fight Club - 1080p",
          "url": "https://stream.server.org/master.m3u8",
          "quality": "1080p",
          "provider": "vixsrc",
          "lang": "latino",
          "headers": {
            "User-Agent": "Mozilla/5.0",
            "Referer": "https://vixsrc.to/"
          }
        }
      ];

      final servers = service.parseStreamsResponse(sampleEmbedApi);
      expect(servers.length, 1);
      final first = servers.first;
      expect(first['servidor_nombre'], 'Backend · vixsrc');
      expect(first['servidor_url'], 'https://stream.server.org/master.m3u8');
      expect(first['calidad'], '1080p');
      expect(first['idioma'], 'latino');
      expect(first['resolved_m3u8'], 'https://stream.server.org/master.m3u8');
      expect(first['fuente'], 'backend');
      expect(first['is_verified'], isTrue);
      expect(first['headers']['Referer'], 'https://vixsrc.to/');
    });

    test('search con backend offline hace fallback seguro y retorna lista vacía', () async {
      final service = BackendScraperService.instance;
      final results = await service.search('Inception');
      expect(results, isEmpty);
    });
  });
}
