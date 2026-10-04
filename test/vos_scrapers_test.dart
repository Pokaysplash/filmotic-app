import 'package:flutter_test/flutter_test.dart';
import 'package:lol/data/scrapers/seriesflix_scraper.dart';
import 'package:lol/data/scrapers/cineby_scraper.dart';

void main() {
  test('Seriesflix y Cineby busqueda de La Ley y el Orden', () async {
    print('=== Probando búsqueda Seriesflix ===');
    final sResults = await SeriesflixScraper.search('La Ley y el Orden');
    print('Seriesflix items: ${sResults.length}');
    for (final r in sResults.take(3)) {
      print(' - [Seriesflix] ${r.titulo} (${r.tipo}) -> ${r.url}');
    }
    expect(sResults, isNotEmpty);

    print('\n=== Probando búsqueda Cineby ===');
    final cResults = await CinebyScraper.search('La Ley y el Orden');
    print('Cineby items: ${cResults.length}');
    for (final r in cResults.take(3)) {
      print(' - [Cineby] ${r.titulo} (${r.tipo}) [TMDB: ${r.tmdbId}]');
    }
    expect(cResults, isNotEmpty);

    print('\n=== Probando servidores Cineby VOS ===');
    final cFirst = cResults.first;
    final cServers = await CinebyScraper.fetchServers(
      url: cFirst.url,
      tmdbId: cFirst.tmdbId,
      isMovie: cFirst.tipo == 'movie',
      season: 1,
      episode: 1,
    );
    print('Cineby servidores: ${cServers.length}');
    for (final s in cServers) {
      print(' - ${s.nombre} [idioma: ${s.idioma}] -> ${s.url}');
    }
    expect(cServers, isNotEmpty);
    expect(cServers.any((s) => s.idioma == 'subtitulado'), isTrue);
  });
}
