import 'dart:convert';
import 'package:html/parser.dart' as parser;
import 'package:http/http.dart' as http;
import '../models/scraper/detalle_model.dart';
import 'base/base_home_scraper.dart';
import 'base/buscador.dart';

class AnimeFLVScraper {
  static const String base = 'https://animeflv.com.es';

  static const List<String> generos = [
    'accion',
    'aventura',
    'comedia',
    'drama',
    'escolar',
    'fantasia',
    'magia',
    'mecha',
    'misterio',
    'romance',
    'shounen',
    'sobrenatural',
  ];

  static List<String> tiposDisponibles() => ['anime', 'emision', 'populares', 'peliculas'];

  static String _detectIdioma(String text) {
    final lower = text.toLowerCase();
    if (lower.contains('latino') || lower.contains('lat') || lower.contains('audio latino')) {
      return 'latino';
    }
    if (lower.contains('castellano') || lower.contains('españa')) {
      return 'castellano';
    }
    if (lower.contains('ingles') || lower.contains('inglés')) {
      return 'inglés';
    }
    return 'subtitulado'; // AnimeFLV es por defecto subtitulado en español
  }

  // ─── LISTADO (FETCH) ──────────────────────────────────────────
  static Future<ScraperResult> fetch({
    String? tipo,
    String? genero,
    bool populares = false,
    int page = 1,
  }) async {
    String url = '$base/browse';
    final queryParams = <String>[];

    if (genero != null && genero.isNotEmpty) {
      queryParams.add('genre=$genero');
    }
    if (tipo == 'emision') {
      queryParams.add('status=1');
    } else if (tipo == 'peliculas') {
      queryParams.add('type=movie');
    } else if (populares) {
      queryParams.add('order=rating');
    }

    if (page > 1) {
      queryParams.add('page=$page');
    }

    if (queryParams.isNotEmpty) {
      url = '$url?${queryParams.join('&')}';
    }

    final html = await fetchHtml(url);
    if (html == null) {
      return ScraperResult(ok: false, error: 'No se pudo conectar a AnimeFLV', url: url);
    }

    final doc = parser.parse(html);
    final items = <ScraperItem>[];

    final elements = doc.querySelectorAll('ul.ListAnimes li article, .AnimeList li, article.Anime');
    for (final el in elements) {
      final aTag = el.querySelector('a');
      final link = aTag?.attributes['href'] ?? '';
      if (link.isEmpty) continue;

      final imgTag = el.querySelector('img');
      var poster = imgTag?.attributes['src'] ?? imgTag?.attributes['data-cfsrc'] ?? '';
      if (poster.startsWith('//')) poster = 'https:$poster';

      final title = el.querySelector('.Title, h3.Title, h2')?.text.trim() ??
          imgTag?.attributes['alt'] ??
          'Sin título';

      final ratingStr = el.querySelector('.Vote span, .Rating')?.text.replaceAll(RegExp(r'[^0-9.]'), '');
      final rating = double.tryParse(ratingStr ?? '');

      items.add(ScraperItem(
        titulo: title,
        tipo: 'anime',
        url: link.startsWith('http') ? link : '$base$link',
        poster: poster,
        rating: rating,
      ));
    }

    return ScraperResult(
      ok: true,
      url: url,
      currentPage: page,
      hasNext: items.length >= 12,
      items: items,
    );
  }

  // ─── BÚSQUEDA ─────────────────────────────────────────────────
  static Future<List<BuscadorItem>> search(String q) async {
    final query = Uri.encodeComponent(q.trim());
    final url = '$base/browse?q=$query';
    final html = await fetchHtml(url);
    if (html == null) return [];

    final doc = parser.parse(html);
    final results = <BuscadorItem>[];

    final elements = doc.querySelectorAll('ul.ListAnimes li article, article.Anime, .ListAnimes li');
    for (final el in elements) {
      final a = el.querySelector('a');
      final href = a?.attributes['href'] ?? '';
      if (href.isEmpty) continue;

      final img = el.querySelector('img');
      var poster = img?.attributes['src'] ?? img?.attributes['data-cfsrc'] ?? '';
      if (poster.startsWith('//')) poster = 'https:$poster';

      final title = el.querySelector('.Title, h3')?.text.trim() ??
          img?.attributes['alt'] ??
          'Sin título';

      results.add(BuscadorItem(
        sitio: 'animeflv',
        titulo: title,
        tipo: 'anime',
        url: href.startsWith('http') ? href : '$base$href',
        imagen: poster,
      ));
    }

    return results;
  }

  // ─── DETALLE ──────────────────────────────────────────────────
  static Future<DetalleContenido> fetchDetail({
    required String url,
    required String titulo,
    String tipo = 'anime',
  }) async {
    final html = await fetchHtml(url);
    if (html == null) {
      return DetalleContenido(
        ok: false,
        error: 'Error al conectar con AnimeFLV',
        servicio: 'animeflv',
        titulo: titulo,
        tipo: 'anime',
      );
    }

    final doc = parser.parse(html);

    // Sinopsis
    final sinopsis = doc.querySelector('.Description p, .Description, .Sinopsis')?.text.trim() ?? '';

    // Poster
    final posterEl = doc.querySelector('.Image img, .AnimeCover img');
    var poster = posterEl?.attributes['src'] ?? posterEl?.attributes['data-cfsrc'] ?? '';
    if (poster.startsWith('//')) poster = 'https:$poster';

    // Backdrop
    var backdrop = poster;
    final bgEl = doc.querySelector('.Bg, .Cover');
    final bgStyle = bgEl?.attributes['style'] ?? '';
    final bgMatch = RegExp(r'url\((.*?)\)').firstMatch(bgStyle);
    if (bgMatch != null) {
      backdrop = bgMatch.group(1)?.replaceAll("'", '').replaceAll('"', '') ?? poster;
    }

    // Géneros
    final genres = doc.querySelectorAll('.Nvgnrs a').map((e) => e.text.trim()).toList();

    // Parsear episodios del script AnimeFLV (var episodes = [[1, 1], [2, 2], ...];)
    final capitulos = <DetalleCapitulo>[];
    final matchEpisodes = RegExp(r'var episodes\s*=\s*(\[\[[\s\S]*?\]\]);').firstMatch(html);

    if (matchEpisodes != null) {
      try {
        final rawJson = matchEpisodes.group(1)!;
        final list = jsonDecode(rawJson) as List;
        // Episodes están ordenados descendentemente [num, id]
        final sorted = list.reversed.toList();
        for (int i = 0; i < sorted.length; i++) {
          final epItem = sorted[i];
          final epNum = epItem[0] is int ? epItem[0] as int : (i + 1);
          // La url del episodio en AnimeFLV suele ser /ver/{slug}-{epNum}
          final slug = url.split('/').last;
          final epUrl = '$base/ver/$slug-$epNum';

          capitulos.add(DetalleCapitulo(
            temporada: 1,
            numero: epNum,
            titulo: 'Episodio $epNum',
            url: epUrl,
            imagen: poster,
          ));
        }
      } catch (_) {}
    }

    // Servidores del primer episodio o película si aplica
    final servidores = await fetchServers(url: url, html: html);

    final temporadas = capitulos.isNotEmpty
        ? [DetalleTemporada(numero: 1, nombre: 'Temporada 1', episodios: capitulos)]
        : <DetalleTemporada>[];

    return DetalleContenido(
      ok: true,
      servicio: 'animeflv',
      titulo: titulo,
      tipo: 'anime',
      sinopsis: sinopsis,
      poster: poster,
      backdrop: backdrop,
      generos: genres,
      servidores: servidores,
      temporadas: temporadas,
    );
  }

  // ─── SERVIDORES Y DETECCIÓN DE IDIOMA ─────────────────────────
  static Future<List<DetalleServidor>> fetchServers({
    required String url,
    String? html,
  }) async {
    final pageHtml = html ?? await fetchHtml(url);
    if (pageHtml == null) return [];

    final doc = parser.parse(pageHtml);
    final servers = <DetalleServidor>[];

    // 1. Extraer botones data-src codificados en Base64 (nuevo formato AnimeFLV)
    final elementsWithDataSrc = doc.querySelectorAll('[data-src]');
    for (final el in elementsWithDataSrc) {
      final rawB64 = el.attributes['data-src']?.trim() ?? '';
      if (rawB64.isEmpty) continue;

      String decodedUrl = '';
      try {
        decodedUrl = utf8.decode(base64.decode(base64.normalize(rawB64))).trim();
      } catch (_) {
        if (rawB64.startsWith('http')) decodedUrl = rawB64;
      }

      if (decodedUrl.isNotEmpty && decodedUrl.startsWith('http')) {
        final label = el.text.trim();
        servers.add(DetalleServidor(
          nombre: label.isNotEmpty ? 'AnimeFLV · $label' : 'AnimeFLV · Server',
          url: decodedUrl,
          idioma: _detectIdioma('$label $decodedUrl'),
          calidad: 'HD',
        ));
      }
    }

    // 2. AnimeFLV almacena los streams en: var videos = {"SUB": [...], "LAT": [...]};
    final matchVideos = RegExp(r'var videos\s*=\s*(\{[\s\S]*?\});').firstMatch(pageHtml);
    if (matchVideos != null) {
      try {
        final videosMap = jsonDecode(matchVideos.group(1)!) as Map<String, dynamic>;

        videosMap.forEach((langKey, list) {
          final idioma = _detectIdioma(langKey);
          if (list is List) {
            for (final item in list) {
              if (item is Map) {
                final title = item['title']?.toString() ?? 'Server';
                final code = item['code']?.toString() ?? item['url']?.toString() ?? '';
                if (code.isNotEmpty) {
                  servers.add(DetalleServidor(
                    nombre: 'AnimeFLV · $title',
                    url: code,
                    idioma: idioma,
                    calidad: 'HD',
                  ));
                }
              }
            }
          }
        });
      } catch (_) {}
    }

    // 3. Iframes adicionales en el HTML
    final iframes = doc.querySelectorAll('iframe');
    for (final iframe in iframes) {
      var src = iframe.attributes['src'] ?? '';
      if (src.isNotEmpty && !src.contains('recaptcha')) {
        if (src.startsWith('//')) src = 'https:$src';
        servers.add(DetalleServidor(
          nombre: 'Stream Direct',
          url: src,
          idioma: _detectIdioma(pageHtml),
          calidad: 'HD',
        ));
      }
    }

    return servers;
  }
}
