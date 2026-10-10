import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lol/core/services/server_loader_shared.dart';
import 'package:lol/data/aggregators/source_aggregator.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  test('diag pipeline SVU S1E1', () async {
    SharedPreferences.setMockInitialValues({
      'cinesrc_enabled': true,
      'poseidon_enabled': true,
      'smartpelis_enabled': true,
      'seriesmetro_enabled': true,
      'un_servidor_por_idioma': false,
    });
    final main = MainFuentes();
    await main.loadConfig();
    // ignore: avoid_print
    print('ACTIVAS: ${main.config.fuentesActivas.map((f) => f.name).toList()}');

    final sw = Stopwatch()..start();
    final servers = <Map<String, dynamic>>[];
    await for (final ev in main
        .fetchProgressive(tmdbId: 2734, isMovie: false, season: 1, episode: 1, forzarVerificar: false)
        .timeout(const Duration(seconds: 60), onTimeout: (s) => s.close())) {
      if (ev.isDone) {
        // ignore: avoid_print
        print('[${sw.elapsedMilliseconds}ms] DONE ${ev.fuente.name} err=${ev.error}');
      }
      if (ev.servidor != null) {
        servers.add(Map<String, dynamic>.from(ev.servidor!));
        // ignore: avoid_print
        print('[${sw.elapsedMilliseconds}ms] SRV ${ev.fuente.name} ${ev.servidor!['idioma']} ${ev.servidor!['servidor_nombre'] ?? ev.servidor!['servidor']} ${ev.servidor!['servidor_url']}');
      }
    }

    final loader = ServerLoader();
    for (final s in servers) {
      final t = Stopwatch()..start();
      final p = await loader.tryResolveServer(s).catchError((_) => null);
      // ignore: avoid_print
      print('RESOLVE ${s['fuente_id']} ${s['servidor_url']} -> ${p?.url ?? 'NULL'} (${t.elapsedMilliseconds}ms)');
    }
  }, timeout: const Timeout(Duration(minutes: 6)));
}
