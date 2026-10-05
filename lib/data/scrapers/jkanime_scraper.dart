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
    if (lower.contains('latino') || RegExp(r'\b(lat|audio latino)\b').hasMatch(lower)) return 'latino';
    if (lower.contains('castellano') || RegExp(r'\b(esp|cast)\b').hasMatch(lower)) return 'castellano';
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

      final cards = doc.querySelectorAll('.anime__item');
      for (final card in cards) {
        final a = card.querySelector('.anime__item__text h5 a') ??
            card.querySelector('h5 a') ??
            card.querySelector('a');
        final href = a?.attributes['href'] ?? '';
        if (href.isEmpty) continue;

        final title = a?.text.trim() ?? card.querySelector('h5 a, .title')?.text.trim() ?? '';
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

      // Episodios: JKAnime maneja paginación ajax /ajax/episodes/{anime_id}/1
      final capitulos = <DetalleCapitulo>[];
      final slug = url.replaceAll(RegExp(r'/+$'), '').split('/').last;

      int totalEps = 0;
      final matchId = RegExp(r'/ajax/episodes/(\d+)/').firstMatch(res.body);
      if (matchId != null) {
        final animeId = matchId.group(1);
        final matchMeta = RegExp(r'<meta name="csrf-token" content="([^"]+)"').firstMatch(res.body);
        final token = matchMeta?.group(1) ?? '';
        final rawCookie = res.headers['set-cookie'] ?? '';
        final cookies = rawCookie.split(',').map((c) => c.split(';')[0].trim()).join('; ');

        try {
          final epRes = await http.post(
            Uri.parse('$base/ajax/episodes/$animeId/1'),
            headers: {
              'User-Agent': userAgent,
              'X-Requested-With': 'XMLHttpRequest',
              'X-CSRF-TOKEN': token,
              'Referer': url,
              if (cookies.isNotEmpty) 'Cookie': cookies,
            },
            body: {'_token': token},
          ).timeout(const Duration(seconds: 4));

          if (epRes.statusCode == 200) {
            final json = jsonDecode(epRes.body);
            totalEps = int.tryParse(json['total']?.toString() ?? '0') ?? 0;
          }
        } catch (_) {}
      }

      if (totalEps <= 0) {
        // Fallback: buscar número máximo en HTML
        final matchMaxEp = RegExp(r'/(?:[a-zA-Z0-9_-]+)/(\d+)/').allMatches(res.body);
        for (final m in matchMaxEp) {
          final n = int.tryParse(m.group(1) ?? '') ?? 0;
          if (n > totalEps && n < 2000) totalEps = n;
        }
      }

      if (totalEps <= 0) {
        // Contenido de 1 episodio o película
        totalEps = 1;
      }

      for (int i = 1; i <= totalEps; i++) {
        capitulos.add(DetalleCapitulo(
          temporada: 1,
          numero: i,
          titulo: totalEps == 1 ? (titulo.isNotEmpty ? titulo : 'Película') : 'Episodio $i',
          url: '$base/$slug/$i/',
          imagen: poster,
        ));
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

    // Extraer servidores del array servers = [{remote: "base64", server: "Name"}]
    final serversMatch = RegExp(r'servers\s*=\s*(\[\{[\s\S]*?\}\]);').firstMatch(pageHtml);
    if (serversMatch != null) {
      try {
        final list = jsonDecode(serversMatch.group(1)!) as List;
        for (final item in list) {
          if (item is Map) {
            final sName = item['server']?.toString() ?? 'Server';
            final remoteB64 = item['remote']?.toString() ?? '';
            if (remoteB64.isEmpty) continue;
            try {
              final decodedUrl = utf8.decode(base64Decode(remoteB64)).trim();
              if (decodedUrl.isNotEmpty && !seen.contains(decodedUrl)) {
                seen.add(decodedUrl);
                servers.add(DetalleServidor(
                  nombre: 'JKAnime · $sName',
                  url: decodedUrl,
                  idioma: _detectIdioma(sName),
                  calidad: 'HD',
                ));
              }
            } catch (_) {}
          }
        }
      } catch (_) {}
    }

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
        idioma: 'subtitulado',
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
