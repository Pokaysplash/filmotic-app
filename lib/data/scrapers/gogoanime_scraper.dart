import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as parser;
import 'package:http/http.dart' as http;
import '../models/scraper/detalle_model.dart';
import 'base/base_home_scraper.dart';
import 'base/buscador.dart';

/// Scraper para GogoAnime (anitaku.to / gogoanime3.co)
class GogoAnimeScraper {
  static const String base = 'https://anitaku.to';
  static const String userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';
  static const Duration timeout = Duration(seconds: 10);

  static const List<String> generos = [
    'action',
    'adventure',
    'comedy',
    'drama',
    'fantasy',
    'horror',
    'mystery',
    'romance',
    'sci-fi',
    'shounen',
    'sports',
    'supernatural',
  ];

  static List<String> tiposDisponibles() => ['anime', 'popular', 'movies', 'recent'];

  // ─── LISTADO (FETCH) ──────────────────────────────────────────
  static Future<ScraperResult> fetch({
    String? tipo,
    String? genero,
    bool populares = false,
    int page = 1,
  }) async {
    String url = '$base/popular.html?page=$page';
    if (tipo == 'movies') {
      url = '$base/anime-movies.html?page=$page';
    } else if (tipo == 'recent') {
      url = '$base/?page=$page';
    } else if (genero != null && genero.isNotEmpty) {
      url = '$base/genre/$genero?page=$page';
    }

    try {
      final res = await http.get(Uri.parse(url), headers: {'User-Agent': userAgent}).timeout(timeout);
      if (res.statusCode != 200) {
        return ScraperResult(ok: false, error: 'Error al conectar (${res.statusCode})', url: url);
      }

      final doc = parser.parse(res.body);
      final items = <ScraperItem>[];
      final elements = doc.querySelectorAll('.last_episodes ul.items li, .items li');

      for (final el in elements) {
        final aTag = el.querySelector('a');
        final href = aTag?.attributes['href'] ?? '';
        if (href.isEmpty) continue;

        final imgTag = el.querySelector('img');
        var poster = imgTag?.attributes['src'] ?? '';
        if (poster.startsWith('//')) poster = 'https:$poster';

        final title = el.querySelector('.name, .name a')?.text.trim() ?? 'Sin título';

        items.add(ScraperItem(
          sitio: 'gogoanime',
          titulo: title,
          tipo: 'anime',
          url: href.startsWith('http') ? href : '$base$href',
          poster: poster,
          rating: 8.0,
        ));
      }

      return ScraperResult(
        ok: true,
        url: url,
        currentPage: page,
        hasNext: items.length >= 10,
        items: items,
      );
    } catch (e) {
      return ScraperResult(ok: false, error: 'Excepción GogoAnime: $e', url: url);
    }
  }

  // ─── BÚSQUEDA ─────────────────────────────────────────────────
  static Future<List<BuscadorItem>> search(String q) async {
    final query = Uri.encodeComponent(q.trim());
    final url = '$base/search.html?keyword=$query';

    try {
      final res = await http.get(Uri.parse(url), headers: {'User-Agent': userAgent}).timeout(timeout);
      if (res.statusCode != 200) return [];

      final doc = parser.parse(res.body);
      final results = <BuscadorItem>[];
      final elements = doc.querySelectorAll('.last_episodes ul.items li, .items li');

      for (final el in elements) {
        final aTag = el.querySelector('a');
        final href = aTag?.attributes['href'] ?? '';
        if (href.isEmpty) continue;

        final imgTag = el.querySelector('img');
        var poster = imgTag?.attributes['src'] ?? '';
        if (poster.startsWith('//')) poster = 'https:$poster';

        final title = el.querySelector('.name, .name a')?.text.trim() ?? 'Sin título';

        results.add(BuscadorItem(
          sitio: 'gogoanime',
          titulo: title,
          tipo: 'anime',
          url: href.startsWith('http') ? href : '$base$href',
          imagen: poster,
        ));
      }

      return results;
    } catch (_) {
      return [];
    }
  }

  // ─── DETALLE ──────────────────────────────────────────────────
  static Future<DetalleContenido> fetchDetail({
    required String url,
    required String titulo,
    String tipo = 'anime',
  }) async {
    try {
      final res = await http.get(Uri.parse(url), headers: {'User-Agent': userAgent}).timeout(timeout);
      if (res.statusCode != 200) {
        return DetalleContenido(
          ok: false,
          error: 'Error GogoAnime (${res.statusCode})',
          servicio: 'gogoanime',
          titulo: titulo,
          tipo: tipo,
        );
      }

      final doc = parser.parse(res.body);

      final sinopsisEl = doc.querySelector('.description, .type span:contains("Plot Summary:")');
      final sinopsis = sinopsisEl?.parent?.text.replaceAll('Plot Summary:', '').trim() ??
          doc.querySelector('.description')?.text.trim() ??
          '';

      final imgEl = doc.querySelector('.anime_info_body_bg img');
      var poster = imgEl?.attributes['src'] ?? '';
      if (poster.startsWith('//')) poster = 'https:$poster';

      final genres = doc.querySelectorAll('.type a[href*="/genre/"]').map((e) => e.text.trim()).toList();

      // En GogoAnime, los episodios se obtienen del ID del anime o listado #episode_page
      final animeIdEl = doc.querySelector('#movie_id');
      final animeId = animeIdEl?.attributes['value'] ?? '';

      final capitulos = <DetalleCapitulo>[];
      final slug = url.replaceAll(RegExp(r'/+$'), '').split('/').last.replaceAll('category/', '');

      if (animeId.isNotEmpty) {
        try {
          final epListUrl = 'https://ajax.gogocdn.net/ajax/load-list-episode?ep_start=0&ep_end=2000&id=$animeId&default_ep=0&alias=$slug';
          final epRes = await http.get(Uri.parse(epListUrl), headers: {'User-Agent': userAgent}).timeout(const Duration(seconds: 5));
          if (epRes.statusCode == 200) {
            final epDoc = parser.parse(epRes.body);
            final epLinks = epDoc.querySelectorAll('ul li a');
            final sorted = epLinks.reversed.toList();
            for (int i = 0; i < sorted.length; i++) {
              final a = sorted[i];
              final epHref = a.attributes['href']?.trim() ?? '';
              final epNumStr = a.querySelector('.name')?.text.replaceAll('EP', '').trim() ?? '${i + 1}';
              final epNum = int.tryParse(epNumStr) ?? (i + 1);

              capitulos.add(DetalleCapitulo(
                temporada: 1,
                numero: epNum,
                titulo: 'Episodio $epNum',
                url: epHref.startsWith('http') ? epHref : '$base$epHref',
                imagen: poster,
              ));
            }
          }
        } catch (_) {}
      }

      final temporadas = capitulos.isNotEmpty
          ? [DetalleTemporada(numero: 1, nombre: 'Temporada 1', episodios: capitulos)]
          : <DetalleTemporada>[];

      final firstEpUrl = capitulos.isNotEmpty ? capitulos.first.url : url;
      final servidores = await fetchServers(url: firstEpUrl);

      debugPrint('[GogoAnime] Episodios encontrados: ${capitulos.length}');
      debugPrint('[GogoAnime] Servidores encontrados: ${servidores.length}');

      return DetalleContenido(
        ok: true,
        servicio: 'gogoanime',
        titulo: titulo,
        tipo: tipo,
        sinopsis: sinopsis,
        poster: poster,
        backdrop: poster,
        generos: genres,
        servidores: servidores,
        temporadas: temporadas,
      );
    } catch (e) {
      return DetalleContenido(
        ok: false,
        error: 'Excepción GogoAnime: $e',
        servicio: 'gogoanime',
        titulo: titulo,
        tipo: tipo,
      );
    }
  }

  // ─── SERVIDORES ───────────────────────────────────────────────
  static Future<List<DetalleServidor>> fetchServers({
    required String url,
  }) async {
    try {
      final res = await http.get(Uri.parse(url), headers: {'User-Agent': userAgent}).timeout(timeout);
      if (res.statusCode != 200) return [];

      final doc = parser.parse(res.body);
      final servers = <DetalleServidor>[];
      final seen = <String>{};

      final serverLinks = doc.querySelectorAll('.anime_muti_link ul li a, ul.anime_muti_link li a');
      for (final a in serverLinks) {
        var sUrl = a.attributes['data-video'] ?? a.attributes['href'] ?? '';
        if (sUrl.startsWith('//')) sUrl = 'https:$sUrl';
        final name = a.text.replaceAll('Choose this server', '').trim();

        if (sUrl.isNotEmpty && sUrl.startsWith('http') && !seen.contains(sUrl)) {
          seen.add(sUrl);
          servers.add(DetalleServidor(
            nombre: 'GogoAnime · ${name.isNotEmpty ? name : "Stream"}',
            url: sUrl,
            idioma: 'subtitulado',
            calidad: 'HD',
          ));
        }
      }

      // Iframes embed
      final ifr = doc.querySelector('.play-video iframe');
      var src = ifr?.attributes['src'] ?? '';
      if (src.startsWith('//')) src = 'https:$src';
      if (src.isNotEmpty && !seen.contains(src)) {
        seen.add(src);
        servers.add(DetalleServidor(
          nombre: 'GogoAnime · Vidstreaming Directo',
          url: src,
          idioma: 'subtitulado',
          calidad: 'HD',
        ));
      }

      return servers;
    } catch (_) {
      return [];
    }
  }
}
