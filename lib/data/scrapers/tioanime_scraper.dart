import 'dart:convert';
import 'package:html/parser.dart' as parser;
import 'package:http/http.dart' as http;
import '../models/scraper/detalle_model.dart';
import 'base/base_home_scraper.dart';
import 'base/buscador.dart';

/// Scraper especializado en Anime para TioAnime (tioanime.com)
class TioAnimeScraper {
  static const String base = 'https://tioanime.com';
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
    'terror',
  ];

  static List<String> tiposDisponibles() => ['anime', 'pelicula', 'ova', 'especial'];

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
    final queryParams = <String>[];
    if (genero != null && genero.isNotEmpty) queryParams.add('genero=$genero');
    if (tipo != null && tipo.isNotEmpty) queryParams.add('tipo=$tipo');
    if (page > 1) queryParams.add('p=$page');

    final qStr = queryParams.isNotEmpty ? '?${queryParams.join('&')}' : '';
    final url = '$base/directorio$qStr';

    try {
      final res = await http.get(Uri.parse(url), headers: {
        'User-Agent': userAgent,
      }).timeout(timeout);

      if (res.statusCode != 200) {
        return ScraperResult(
          ok: false,
          error: 'Error al conectar con TioAnime (${res.statusCode})',
          url: url,
        );
      }

      final doc = parser.parse(res.body);
      final items = <ScraperItem>[];

      final cards = doc.querySelectorAll('article.anime, .anime');
      for (final card in cards) {
        final a = card.querySelector('a');
        final href = a?.attributes['href'] ?? '';
        if (href.isEmpty) continue;

        final title = card.querySelector('.title, h3')?.text.trim() ?? '';
        if (title.isEmpty) continue;

        final img = card.querySelector('img');
        var poster = img?.attributes['src'] ?? '';
        if (poster.startsWith('/')) poster = '$base$poster';

        items.add(ScraperItem(
          titulo: title,
          tipo: 'anime',
          url: href.startsWith('http') ? href : '$base$href',
          poster: poster,
          rating: 8.7,
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
        error: 'Excepción en TioAnimeScraper: $e',
        url: url,
      );
    }
  }

  // ─── BÚSQUEDA ─────────────────────────────────────────────────
  static Future<List<BuscadorItem>> search(String q) async {
    final query = Uri.encodeComponent(q.trim());
    final url = '$base/directorio?q=$query';

    try {
      final res = await http.get(Uri.parse(url), headers: {
        'User-Agent': userAgent,
      }).timeout(timeout);

      if (res.statusCode != 200) return [];
      final doc = parser.parse(res.body);
      final results = <BuscadorItem>[];

      final cards = doc.querySelectorAll('article.anime, .anime');
      for (final card in cards) {
        final a = card.querySelector('a');
        final href = a?.attributes['href'] ?? '';
        if (href.isEmpty) continue;

        final title = card.querySelector('.title, h3')?.text.trim() ?? '';
        if (title.isEmpty) continue;

        final img = card.querySelector('img');
        var poster = img?.attributes['src'] ?? '';
        if (poster.startsWith('/')) poster = '$base$poster';

        results.add(BuscadorItem(
          sitio: 'tioanime',
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
          error: 'Error al conectar con TioAnime (${res.statusCode})',
          servicio: 'tioanime',
          titulo: titulo,
          tipo: tipo,
        );
      }

      final doc = parser.parse(res.body);

      // Sinopsis
      final sinopsis = doc.querySelector('.sinopsis, .sinopsis p, p')?.text.trim() ?? '';

      // Poster
      final imgEl = doc.querySelector('.thumb img, .anime-thumb img');
      var poster = imgEl?.attributes['src'] ?? '';
      if (poster.startsWith('/')) poster = '$base$poster';

      // Géneros
      final genres = doc.querySelectorAll('.genres a, .generos a')
          .map((e) => e.text.trim())
          .where((e) => e.isNotEmpty)
          .toList();

      // Episodios parseados del script de TioAnime:
      // var episodes = [1, 2, 3, ...];
      final capitulos = <DetalleCapitulo>[];
      final slug = url.replaceAll(RegExp(r'/+$'), '').split('/').last;

      final matchEpisodes = RegExp(r'var episodes\s*=\s*(\[[\s\S]*?\]);').firstMatch(res.body);
      if (matchEpisodes != null) {
        try {
          final list = jsonDecode(matchEpisodes.group(1)!) as List;
          // Ordenar ascendente
          final numbers = list.map((e) => int.tryParse('$e') ?? 0).where((n) => n > 0).toList();
          numbers.sort();

          for (final epNum in numbers) {
            capitulos.add(DetalleCapitulo(
              temporada: 1,
              numero: epNum,
              titulo: 'Episodio $epNum',
              url: '$base/ver/$slug-$epNum',
              imagen: poster,
            ));
          }
        } catch (_) {}
      }

      // Si no parseó script, intentar enlaces directos
      if (capitulos.isEmpty) {
        final epLinks = doc.querySelectorAll('a[href*="/ver/"]');
        int idx = 1;
        for (final a in epLinks) {
          final href = a.attributes['href'] ?? '';
          if (href.isEmpty) continue;
          capitulos.add(DetalleCapitulo(
            temporada: 1,
            numero: idx,
            titulo: 'Episodio $idx',
            url: href.startsWith('http') ? href : '$base$href',
            imagen: poster,
          ));
          idx++;
        }
      }

      final temporadas = capitulos.isNotEmpty
          ? [DetalleTemporada(numero: 1, nombre: 'Temporada 1', episodios: capitulos)]
          : <DetalleTemporada>[];

      final firstEpUrl = capitulos.isNotEmpty ? capitulos.first.url : url;
      final servidores = await fetchServers(url: firstEpUrl);

      return DetalleContenido(
        ok: true,
        servicio: 'tioanime',
        titulo: titulo,
        tipo: tipo,
        sinopsis: sinopsis,
        poster: poster,
        backdrop: poster,
        generos: genres.isNotEmpty ? genres : ['Anime', 'Animación'],
        servidores: servidores,
        temporadas: temporadas,
      );
    } catch (e) {
      return DetalleContenido(
        ok: false,
        error: 'Excepción TioAnime detalle: $e',
        servicio: 'tioanime',
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

    // TioAnime almacena los servidores en:
    // var videos = [["Mega","https:\/\/mega.nz\/embed\/...",0,0],["YourUpload",...]];
    final matchVideos = RegExp(r'var videos\s*=\s*(\[\[[\s\S]*?\]\]);').firstMatch(pageHtml);
    if (matchVideos != null) {
      try {
        final list = jsonDecode(matchVideos.group(1)!) as List;
        for (final item in list) {
          if (item is List && item.length >= 2) {
            final sName = item[0]?.toString() ?? 'Server';
            var sUrl = item[1]?.toString() ?? '';
            sUrl = sUrl.replaceAll(r'\/', '/');
            if (sUrl.isNotEmpty) {
              servers.add(DetalleServidor(
                nombre: 'TioAnime · $sName',
                url: sUrl,
                idioma: _detectIdioma(sName),
                calidad: 'HD',
              ));
            }
          }
        }
      } catch (_) {}
    }

    // Fallback: Iframes
    if (servers.isEmpty) {
      final doc = parser.parse(pageHtml);
      for (final iframe in doc.querySelectorAll('iframe')) {
        final src = iframe.attributes['src'] ?? '';
        if (src.isNotEmpty && !src.contains('recaptcha')) {
          servers.add(DetalleServidor(
            nombre: 'TioAnime · Embed',
            url: src.startsWith('//') ? 'https:$src' : src,
            idioma: _detectIdioma(src),
            calidad: 'HD',
          ));
        }
      }
    }

    return servers;
  }
}
