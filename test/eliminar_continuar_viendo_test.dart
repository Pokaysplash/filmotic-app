import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lol/core/services/guardados_bus.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Continuar Viendo - Eliminación e HistorialBus', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('HistorialBus incrementa su versión al llamar a bump()', () {
      final initialVersion = HistorialBus.version.value;
      int notifications = 0;

      void listener() {
        notifications++;
      }

      HistorialBus.version.addListener(listener);

      HistorialBus.bump();
      expect(HistorialBus.version.value, equals(initialVersion + 1));
      expect(notifications, equals(1));

      HistorialBus.bump();
      expect(HistorialBus.version.value, equals(initialVersion + 2));
      expect(notifications, equals(2));

      HistorialBus.version.removeListener(listener);
    });

    test('HistorialHelper elimina película de SharedPreferences y dispara HistorialBus', () async {
      SharedPreferences.setMockInitialValues({
        'cachePlayer_99901': jsonEncode({
          'idcontenido': 99901,
          'titulo': 'Película de Prueba',
          'segundo': 1200,
          'tipo': 'movie',
        }),
        'cachePlayerRapido_99901': jsonEncode({
          'idcontenido': 99901,
          'segundo': 1200,
        }),
        'cachePlayer_555': jsonEncode({
          'idcontenido': 555,
          'titulo': 'Otra Película',
          'segundo': 500,
        }),
      });

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('cachePlayer_99901'), isTrue);
      expect(prefs.containsKey('cachePlayerRapido_99901'), isTrue);
      expect(prefs.containsKey('cachePlayer_555'), isTrue);

      final initialVersion = HistorialBus.version.value;

      await HistorialHelper.eliminarDeHistorial(
        id: 99901,
        tmdbId: 99901,
      );

      expect(prefs.containsKey('cachePlayer_99901'), isFalse);
      expect(prefs.containsKey('cachePlayerRapido_99901'), isFalse);
      expect(prefs.containsKey('cachePlayer_555'), isTrue);
      expect(HistorialBus.version.value, greaterThan(initialVersion));
    });

    test('HistorialHelper elimina episodios de series de SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({
        'cachePlayer_88801_T1_C1': jsonEncode({
          'idcontenido': 88801,
          'temporada': 1,
          'capitulo': 1,
          'segundo': 800,
          'tipo': 'tv',
        }),
        'cachePlayer_88801_T1_C2': jsonEncode({
          'idcontenido': 88801,
          'temporada': 1,
          'capitulo': 2,
          'segundo': 450,
          'tipo': 'tv',
        }),
        'cachePlayerRapido_88801_T1_C1': jsonEncode({
          'idcontenido': 88801,
          'temporada': 1,
          'capitulo': 1,
        }),
      });

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('cachePlayer_88801_T1_C1'), isTrue);
      expect(prefs.containsKey('cachePlayer_88801_T1_C2'), isTrue);

      // Eliminar episodio puntual
      await HistorialHelper.eliminarDeHistorial(
        id: 88801,
        temporada: 1,
        capitulo: 1,
      );

      expect(prefs.containsKey('cachePlayer_88801_T1_C1'), isFalse);
      expect(prefs.containsKey('cachePlayerRapido_88801_T1_C1'), isFalse);
    });
  });
}
