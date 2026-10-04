import 'dart:convert';
import 'package:html/parser.dart' as parser;
import 'package:http/http.dart' as http;
import '../models/scraper/detalle_model.dart';
import 'base/base_home_scraper.dart';
import 'base/buscador.dart';

/// Scraper especializado en Anime para JKAnime (jkanime.net)
class JKAnimeScraper {
  static const String base = 'https://jkanime.net';
  static const String userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';
  static const Duration timeout = Duration(seconds: 10);

  static const List<String> generos = [
    'accion',
    'aventura',
    'comedia',
    'drama',
    'fantasia',
    'magia',
    'sobrenatural',
    'shounen',
    'romance',
    'isekai',
    'ciencia-ficcion',
  ];

  static List<String> tiposDisponibles() => ['anime', 'peliculas', 'ovas', 'especiales'];

  static String _detectIdioma(String text) {
    final lower = text.toLowerCase();
    if (lower.contains('latino') || lower.contains('lat')) return 'latino';
    if (lower.contains('castellano') || lower.contains('esp')) return 'castellano';
    return 'subtitulado';
  }

  // ─── LISTADO (FETCH) ──────────────────────────────────────────
  static Future<ScraperResult> fetch({
    String? tipo,
    String? genero,
    bool populares = false,
    int page = 1,
  }) async {
    final url = (genero != null && genero.isNotEmpty)
        ? '$base/genero/$genero/$page/'
        : '$base/directorio/$page/';

    try {
      final res = await http.get(Uri.parse(url), headers: {
        'User-Agent': userAgent,
      }).timeout(timeout);

      if (res.statusCode != 200) {
        return ScraperResult(
          ok: false,
          error: 'Error al conectar con JKAnime (${res.statusCode})',
          url: url,
        );
      }

      final doc = parser.parse(res.body);
      final items = <ScraperItem>[];

      final cards = doc.querySelectorAll('.anime__item, .custom_div, .anime-card');
      for (final card in cards) {
        final a = card.querySelector('h5 a, a');
        final href = a?.attributes['href'] ?? '';
        if (href.isEmpty) continue;

        final title = card.querySelector('h5 a, .title, h2')?.text.trim() ??
            a?.text.trim() ??
            '';
        if (title.isEmpty) continue;

        final img = card.querySelector('div[data-setbg], img');
        var poster = img?.attributes['data-setbg'] ??
            img?.attributes['src'] ??
            '';
        if (poster.startsWith('//')) poster = 'https:$poster';

        items.add(ScraperItem(
          titulo: title,
          tipo: 'anime',
          url: href.startsWith('http') ? href : '$base$href',
          poster: poster,
          rating: 8.5,
        ));
      }

      return ScraperResult(
        ok: true,
        url: url,
        currentPage: page,
        hasNext: items.length >= 15,
        items: items,
      );
    } catch (e) {
      return ScraperResult(
        ok: false,
        error: 'Excepción en JKAnimeScraper: $e',
        url: url,
      );
    }
  }

  // ─── BÚSQUEDA ─────────────────────────────────────────────────
  static Future<List<BuscadorItem>> search(String q) async {
    final query = Uri.encodeComponent(q.trim());
    final url = '$base/buscar/$query/';

    try {
      final res = await http.get(Uri.parse(url), headers: {
        'User-Agent': userAgent,
      }).timeout(timeout);

      if (res.statusCode != 200) return [];
      final doc = parser.parse(res.body);
      final results = <BuscadorItem>[];

      final cards = doc.querySelectorAll('.anime__item, .custom_div');
      for (final card in cards) {
        final a = card.querySelector('h5 a, a');
        final href = a?.attributes['href'] ?? '';
        if (href.isEmpty) continue;

        final title = card.querySelector('h5 a, .title')?.text.trim() ?? '';
        if (title.isEmpty) continue;

        final img = card.querySelector('div[data-setbg], img');
        var poster = img?.attributes['data-setbg'] ?? img?.attributes['src'] ?? '';
        if (poster.startsWith('//')) poster = 'https:$poster';

        results.add(BuscadorItem(
          sitio: 'jkanime',
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
      final res = await http.get(Uri.parse(url), headers: {
        'User-Agent': userAgent,
      }).timeout(timeout);

      if (res.statusCode != 200) {
        return DetalleContenido(
          ok: false,
          error: 'Error al conectar con JKAnime (${res.statusCode})',
          servicio: 'jkanime',
          titulo: titulo,
          tipo: tipo,
        );
      }

      final doc = parser.parse(res.body);

      // Sinopsis
      final sinopsis = doc.querySelector('.anime__details__text p, .sinopsis, p')?.text.trim() ?? '';

      // Poster & Backdrop
      final posterEl = doc.querySelector('.anime__details__pic, .anime__details__pic img');
      var poster = posterEl?.attributes['data-setbg'] ?? posterEl?.attributes['src'] ?? '';
      if (poster.startsWith('//')) poster = 'https:$poster';
      final backdrop = poster;

      // Géneros
      final genres = doc.querySelectorAll('.anime__details__widget ul li a, .genres a')
          .map((e) => e.text.trim())
          .where((e) => e.isNotEmpty)
          .toList();

      // Episodios
      final capitulos = <DetalleCapitulo>[];
      final slug = url.replaceAll(RegExp(r'/+$'), '').split('/').last;

      // Buscar rango de episodios en HTML o scripts
      final epLinks = doc.querySelectorAll('.anime__item__text a, .episodes a');
      if (epLinks.isNotEmpty) {
        int idx = 1;
        for (final a in epLinks) {
          final href = a.attributes['href'] ?? '';
          if (href.isEmpty) continue;
          final epTitle = a.text.trim().isNotEmpty ? a.text.trim() : 'Episodio $idx';
          capitulos.add(DetalleCapitulo(
            temporada: 1,
            numero: idx,
            titulo: epTitle,
            url: href.startsWith('http') ? href : '$base$href',
            imagen: poster,
          ));
          idx++;
        }
      } else {
        // En JKAnime los episodios siguen el patrón $base/$slug/$ep/
        // Intentar parsear el último episodio disponible
        final matchMaxEp = RegExp(r'/(?:[a-zA-Z0-9_-]+)/(\d+)/').allMatches(res.body);
        int maxEp = 12;
        for (final m in matchMaxEp) {
          final n = int.tryParse(m.group(1) ?? '') ?? 0;
          if (n > maxEp && n < 2000) maxEp = n;
        }

        for (int i = 1; i <= maxEp; i++) {
          capitulos.add(DetalleCapitulo(
            temporada: 1,
            numero: i,
            titulo: 'Episodio $i',
            url: '$base/$slug/$i/',
            imagen: poster,
          ));
        }
      }

      final temporadas = capitulos.isNotEmpty
          ? [DetalleTemporada(numero: 1, nombre: 'Temporada 1', episodios: capitulos)]
          : <DetalleTemporada>[];

      final firstEpUrl = capitulos.isNotEmpty ? capitulos.first.url : url;
      final servidores = await fetchServers(url: firstEpUrl);

      return DetalleContenido(
        ok: true,
        servicio: 'jkanime',
        titulo: titulo,
        tipo: tipo,
        sinopsis: sinopsis,
        poster: poster,
        backdrop: backdrop,
        generos: genres.isNotEmpty ? genres : ['Anime', 'Animación'],
        servidores: servidores,
        temporadas: temporadas,
      );
    } catch (e) {
      return DetalleContenido(
        ok: false,
        error: 'Excepción JKAnime detalle: $e',
        servicio: 'jkanime',
        titulo: titulo,
        tipo: tipo,
      );
    }
  }

  // ─── SERVIDORES ───────────────────────────────────────────────
  static Future<List<DetalleServidor>> fetchServers({
    required String url,
    String? html,
  }) async {
    final pageHtml = html ?? (await fetchHtml(url));
    if (pageHtml == null || pageHtml.isEmpty) return [];

    final servers = <DetalleServidor>[];
    final seen = <String>{};

    // Extraer iframes del array video[N]
    // Ejemplo: video[0] = '<iframe ... src="https://jkanime.net/jkplayer/um?e=..." ...></iframe>';
    final videoMatches = RegExp(r'''video\[(\d+)\]\s*=\s*['"]<iframe[^>]*src=['"]([^'"]+)['"]''').allMatches(pageHtml);
    for (final m in videoMatches) {
      final sUrl = m.group(2) ?? '';
      if (sUrl.isEmpty || seen.contains(sUrl)) continue;
      seen.add(sUrl);

      servers.add(DetalleServidor(
        nombre: 'JKAnime · Player ${m.group(1)}',
        url: sUrl,
        idioma: _detectIdioma('$sUrl $pageHtml'),
        calidad: 'HD',
      ));
    }

    // Extraer iframes directos
    final doc = parser.parse(pageHtml);
    for (final iframe in doc.querySelectorAll('iframe')) {
      final src = iframe.attributes['src'] ?? '';
      if (src.isEmpty || seen.contains(src) || src.contains('google') || src.contains('recaptcha')) continue;
      seen.add(src);

      servers.add(DetalleServidor(
        nombre: 'JKAnime · Embed Directo',
        url: src.startsWith('//') ? 'https:$src' : src,
        idioma: _detectIdioma(src),
        calidad: 'HD',
      ));
    }

    return servers;
  }
}
