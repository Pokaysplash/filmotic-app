import 'package:flutter_test/flutter_test.dart';
import 'package:lol/core/utils/navigation_helper.dart';

void main() {
  group('BLOQUE F: Enrutamiento quirúrgico de contenido (Novelas vs TMDB)', () {
    test('1. Item con sitio "canelatv" enruta a DerivarPage y NUNCA a TMDB', () {
      final item = {
        'titulo': 'La Madrastra',
        'url': 'https://canela.tv/series/la-madrastra',
        'sitio': 'canelatv',
        'poster': 'https://img.canela.tv/poster.jpg',
        'tipo': 'novela',
        'tmdb_id': null,
      };

      final target = resolveNavigationTarget(item);

      expect(target.type, equals(NavigationTargetType.derivar));
      expect(target.servicio, equals('canelatv'));
      expect(target.titulo, equals('La Madrastra'));
      expect(target.url, equals('https://canela.tv/series/la-madrastra'));
      expect(target.tmdbId, equals(0), reason: 'No debe tener TMDB ID asignado');
    });

    test('2. Item con tmdb_id válido (ej. 12345) enruta a PageContenido', () {
      final item = {
        'titulo': 'Spider-Man',
        'tmdb_id': 12345,
        'tipo': 'movie',
        'poster_path': '/spider.jpg',
      };

      final target = resolveNavigationTarget(item);

      expect(target.type, equals(NavigationTargetType.pageContenido));
      expect(target.tmdbId, equals(12345));
      expect(target.titulo, equals('Spider-Man'));
    });

    test('3. Item sin sitio ni tmdb_id retorna error honesto', () {
      final item = {
        'titulo': 'Contenido Huérfano Desconocido',
        'tmdb_id': null,
        'sitio': null,
      };

      final target = resolveNavigationTarget(item);

      expect(target.type, equals(NavigationTargetType.error));
      expect(target.errorMessage, isNotNull);
      expect(target.errorMessage, contains('no tiene información disponible'));
    });

    test('4. Item con URL de Canela.TV sin sitio explícito infiere canelatv y DerivarPage', () {
      final item = {
        'titulo': 'El Señor de los Cielos',
        'url': 'https://canela.tv/series/el-senor-de-los-cielos',
        'tipo': 'novela',
      };

      final target = resolveNavigationTarget(item);

      expect(target.type, equals(NavigationTargetType.derivar));
      expect(target.servicio, equals('canelatv'));
      expect(target.titulo, equals('El Señor de los Cielos'));
    });

    test('5. Item con hash id grande (>2M) sin sitio no se confunde con TMDB', () {
      final item = {
        'titulo': 'Novela Sin TMDB',
        'id': 987654321, // hash generado de título
        'tmdb_id': null,
      };

      final target = resolveNavigationTarget(item);

      expect(target.type, equals(NavigationTargetType.error),
          reason: 'No debe considerar un hash como un tmdb_id de TMDB');
    });
  });
}
