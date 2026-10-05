import 'package:flutter_test/flutter_test.dart';
import 'package:lol/data/scrapers/canelatv_scraper.dart';
import 'package:lol/data/scrapers/jkanime_scraper.dart';
import 'package:lol/data/scrapers/tioanime_scraper.dart';
import 'package:lol/data/extractors/providers/canela_extractor.dart';
import 'package:lol/features/player/data/native_resolvers.dart';

void main() {
  test('Bloque A: Canela.TV fetch, detail y Brightcove stream', () async {
    print('--- Probando Canela.TV ---');
    final res = await CanelaTVScraper.fetch(tipo: 'series', page: 1);
    expect(res.items.isNotEmpty, true, reason: 'Debe traer items de novelas/series');
    print('Canela items encontrados: ${res.items.length}');
    final item = res.items.first;
    print('Primer item: ${item.titulo} (${item.url})');

    final detail = await CanelaTVScraper.fetchDetail(
      url: item.url,
      titulo: item.titulo,
      tipo: 'series',
    );
    expect(detail.temporadas.isNotEmpty, true, reason: 'Debe traer temporadas');
    final firstSeason = detail.temporadas.first;
    print('Temporada 1 episodios: ${firstSeason.episodios.length}');
    expect(firstSeason.episodios.isNotEmpty, true, reason: 'Debe traer episodios');

    final firstCap = firstSeason.episodios.first;
    print('Capitulo 1: ${firstCap.titulo} (${firstCap.url})');

    final servers = await CanelaTVScraper.fetchServers(url: firstCap.url);
    expect(servers.isNotEmpty, true, reason: 'Debe extraer servidor Brightcove');
    print('Servidor resuelto: ${servers.first.nombre} (${servers.first.url})');
    expect(servers.first.url.contains('.m3u8'), true, reason: 'Debe ser stream HLS .m3u8');
  });

  test('Bloque B & E: TioAnime servidores y deteccion de idioma', () async {
    print('--- Probando TioAnime Naruto ---');
    final searchItems = await TioAnimeScraper.search('Naruto');
    expect(searchItems.isNotEmpty, true, reason: 'Debe encontrar Naruto');
    print('TioAnime encontró ${searchItems.length} resultados');

    // Probar detalle del primer resultado
    final detail = await TioAnimeScraper.fetchDetail(
      url: searchItems.first.url,
      titulo: searchItems.first.titulo,
      tipo: 'anime',
    );
    expect(detail.temporadas.isNotEmpty, true);
    final firstCap = detail.temporadas.first.episodios.first;
    print('TioAnime Episodio: ${firstCap.titulo} -> ${firstCap.url}');

    final servers = await TioAnimeScraper.fetchServers(url: firstCap.url);
    expect(servers.isNotEmpty, true, reason: 'Debe extraer servidores');
    for (final s in servers) {
      print('Servidor: ${s.nombre} | Idioma: ${s.idioma} | URL: ${s.url}');
      // Idioma no debe ser latino por defecto si es sub
      expect(s.idioma, isNot(equals('latino')), reason: 'No debe marcar latino erróneamente');
    }
  });

  test('Bloque B: JKAnime servidores y resolucion', () async {
    print('--- Probando JKAnime Naruto ---');
    final searchItems = await JKAnimeScraper.search('Naruto');
    expect(searchItems.isNotEmpty, true, reason: 'Debe encontrar Naruto');
    print('JKAnime encontró ${searchItems.length} resultados');

    final item = searchItems.first;
    final detail = await JKAnimeScraper.fetchDetail(
      url: item.url,
      titulo: item.titulo,
      tipo: 'anime',
    );
    expect(detail.temporadas.isNotEmpty, true);
    final firstCap = detail.temporadas.first.episodios.first;
    print('JKAnime Episodio: ${firstCap.titulo} -> ${firstCap.url}');

    final servers = await JKAnimeScraper.fetchServers(url: firstCap.url);
    expect(servers.isNotEmpty, true, reason: 'Debe extraer servidores');
    print('JKAnime servidores extraidos: ${servers.length}');
    for (final s in servers) {
      print('Servidor: ${s.nombre} | ${s.url}');
    }
  });
}
