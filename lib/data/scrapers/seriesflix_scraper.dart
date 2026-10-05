import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/scraper/detalle_model.dart';
import 'base/base_home_scraper.dart';
import 'base/buscador.dart';

/// Scraper modular para Seriesflix (https://seriesflix.vip)
/// Soporta catálogo, búsqueda, ficha de series/películas y servidores
/// en Latino, Castellano y VOS (Subtitulado).
class SeriesflixScraper {
  static const String baseUrl = 'https://seriesflix.vip';
  static const Duration _timeout = Duration(seconds: 15);
  static const Map<String, String> _headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
    'Accept-Language': 'es-MX,es;q=0.9,en;q=0.8',
    'Accept':
        'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
  };

  static const List<String> generos = [
    'marvel',
    'disney',
    'dc',
    'aventura',
    'terror',
    'estrenos',
    'accion',
    'drama',
    'comedia',
    'crimen',
    'animacion',
    'fantasia',
    'romance',
  ];

  static List<String> tiposDisponibles() => ['series', 'peliculas'];

  static String _cleanPoster(String? src) {
    if (src == null || src.isEmpty) return '';
    var s = src.trim();
    if (s.startsWith('//')) {
      s = 'https:$s';
    } else if (s.startsWith('/')) {
      s = '$baseUrl$s';
    }
    return s;
  }

  static String _cleanUrl(String? href) {
    if (href == null || href.isEmpty) return '';
    var h = href.trim();
    if (h.startsWith('/')) {
      h = '$baseUrl$h';
    }
    return h;
  }

  static String _normalizeIdioma(String raw) {
    final lower = raw.toLowerCase().trim();
    if (lower.contains('sub') ||
        lower.contains('vose') ||
        lower.contains('vos') ||
        lower.contains('inglés') ||
        lower.contains('ingles') ||
        lower.contains('english')) {
      return 'subtitulado';
    }
    if (lower.contains('castellano') ||
        lower.contains('españa') ||
        lower.contains('español') ||
        lower.contains('cast')) {
      return 'castellano';
    }
    return 'latino';
  }

  // ─── LISTADO (FETCH) ──────────────────────────────────────────
  static Future<ScraperResult> fetch({
    String? tipo,
    String? genero,
    bool populares = false,
    int page = 1,
  }) async {
    String url;
    if (genero != null && genero.isNotEmpty) {
      final genSlug = Uri.encodeComponent(genero.toLowerCase().trim());
      url = page > 1
          ? '$baseUrl/genero/$genSlug/page/$page/'
          : '$baseUrl/genero/$genSlug/';
    } else if (tipo == 'peliculas' || tipo == 'movie') {
      url = page > 1 ? '$baseUrl/peliculas/page/$page/' : '$baseUrl/peliculas/';
    } else {
      url = page > 1 ? '$baseUrl/series/page/$page/' : '$baseUrl/series/';
    }

    try {
      final res = await http.get(Uri.parse(url), headers: _headers).timeout(_timeout);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final html = res.body;
        final items = _parseMovieItems(html);
        return ScraperResult(
          ok: true,
          url: url,
          currentPage: page,
          hasNext: items.length >= 12,
          items: items,
        );
      }
    } catch (e) {
      debugPrint('[Seriesflix] Error en fetch: $e');
    }

    return ScraperResult(
      ok: false,
      error: 'Error al conectar con Seriesflix',
      url: url,
    );
  }

  static List<ScraperItem> _parseMovieItems(String html) {
    final items = <ScraperItem>[];
    final itemPattern = RegExp(
      r'<div class="movie-item"[^>]*>([\s\S]*?)</div>\s*</div>',
      caseSensitive: false,
    );

    for (final match in itemPattern.allMatches(html)) {
      final block = match.group(1) ?? '';

      final aMatch = RegExp(r'<a\s+href="([^"]+)"', caseSensitive: false).firstMatch(block);
      final href = _cleanUrl(aMatch?.group(1));
      if (href.isEmpty) continue;

      final imgMatch = RegExp(r'<img[^>]*src="([^"]+)"[^>]*alt="([^"]*)"', caseSensitive: false).firstMatch(block) ??
          RegExp(r'<img[^>]*alt="([^"]*)"[^>]*src="([^"]+)"', caseSensitive: false).firstMatch(block);

      String poster = '';
      String title = '';
      if (imgMatch != null) {
        final g1 = imgMatch.group(1) ?? '';
        final g2 = imgMatch.group(2) ?? '';
        if (g1.startsWith('http') || g1.startsWith('//') || g1.startsWith('/')) {
          poster = _cleanPoster(g1);
          title = g2;
        } else {
          title = g1;
          poster = _cleanPoster(g2);
        }
      }

      if (title.isEmpty) {
        final pTitle = RegExp(r'<p class="title[^"]*">([^<]+)</p>', caseSensitive: false).firstMatch(block);
        title = pTitle?.group(1)?.trim() ?? '';
      }

      if (title.isEmpty) {
        // Extraer del slug
        final slug = Uri.parse(href).pathSegments.where((s) => s.isNotEmpty).lastOrNull ?? '';
        title = slug.replaceAll('-', ' ').toUpperCase();
      }

      final yearMatch = RegExp(r'<span class="year[^"]*">\s*(\d{4})\s*</span>', caseSensitive: false).firstMatch(block);
      final year = yearMatch != null ? int.tryParse(yearMatch.group(1)!) : null;

      final isTv = href.contains('/serie/');
      final tipo = isTv ? 'tv' : 'movie';

      items.add(ScraperItem(
        sitio: 'seriesflix',
        titulo: title.trim(),
        tipo: tipo,
        url: href,
        poster: poster,
        year: year,
      ));
    }

    return items;
  }

  // ─── BÚSQUEDA ─────────────────────────────────────────────────
  static Future<List<BuscadorItem>> search(String q) async {
    final query = q.trim();
    if (query.isEmpty) return [];

    final searchUrls = <String>[
      '$baseUrl/busqueda/${Uri.encodeComponent(query)}',
    ];

    // Soporte especial para búsquedas bilingües comunes (ej: "la ley y el orden" -> "law order")
    final qLower = query.toLowerCase();
    if (qLower.contains('ley') && qLower.contains('orden')) {
      searchUrls.add('$baseUrl/busqueda/law%20order');
    }

    final allItems = <BuscadorItem>[];
    final seenUrls = <String>{};

    for (final url in searchUrls) {
      try {
        final res = await http.get(Uri.parse(url), headers: _headers).timeout(_timeout);
        if (res.statusCode >= 200 && res.statusCode < 300) {
          final items = _parseMovieItems(res.body);
          for (final item in items) {
            if (!seenUrls.contains(item.url)) {
              seenUrls.add(item.url);
              allItems.add(BuscadorItem(
                sitio: 'seriesflix',
                titulo: item.titulo,
                tipo: item.tipo,
                url: item.url,
                imagen: item.poster,
                anio: item.year,
              ));
            }
          }
        }
      } catch (e) {
        debugPrint('[Seriesflix] Error en búsqueda "$url": $e');
      }
    }

    return allItems;
  }

  // ─── DETALLE ──────────────────────────────────────────────────
  static Future<DetalleContenido> fetchDetail({
    required String url,
    required String titulo,
    required String tipo,
  }) async {
    try {
      final cleanUrl = _cleanUrl(url);
      final res = await http.get(Uri.parse(cleanUrl), headers: _headers).timeout(_timeout);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final html = res.body;

        // Extraer póster
        final posterMatch = RegExp(r'<figure>\s*<img[^>]*src="([^"]+)"[^>]*class="[^"]*poster[^"]*"', caseSensitive: false).firstMatch(html) ??
            RegExp(r'<img[^>]*class="[^"]*poster[^"]*"[^>]*src="([^"]+)"', caseSensitive: false).firstMatch(html);
        final poster = _cleanPoster(posterMatch?.group(1));

        // Extraer sinopsis
        final sinopsisMatch = RegExp(r'<div class="overview"[^>]*>([\s\S]*?)</div>', caseSensitive: false).firstMatch(html) ??
            RegExp(r'<p class="story[^"]*">([\s\S]*?)</p>', caseSensitive: false).firstMatch(html) ??
            RegExp(r'<div class="description[^"]*">([\s\S]*?)</div>', caseSensitive: false).firstMatch(html);
        final sinopsis = sinopsisMatch?.group(1)?.replaceAll(RegExp(r'<[^>]*>'), '').trim();

        // Extraer año
        final yearMatch = RegExp(r'<span class="date[^"]*">\s*(\d{4})\s*</span>', caseSensitive: false).firstMatch(html) ??
            RegExp(r'<span class="year[^"]*">\s*(\d{4})\s*</span>', caseSensitive: false).firstMatch(html);
        final year = yearMatch?.group(1);

        final isTv = tipo == 'tv' || tipo == 'series' || cleanUrl.contains('/serie/');

        if (isTv) {
          // Extraer temporadas y episodios
          final temporadas = await _extractTemporadas(html, cleanUrl);

          return DetalleContenido(
            ok: true,
            servicio: 'seriesflix',
            titulo: titulo,
            tipo: 'tv',
            anio: year,
            sinopsis: sinopsis,
            poster: poster,
            temporadas: temporadas,
          );
        } else {
          // Extraer servidores de película directamente
          final servidores = _extractServersFromHtml(html);

          return DetalleContenido(
            ok: true,
            servicio: 'seriesflix',
            titulo: titulo,
            tipo: 'movie',
            anio: year,
            sinopsis: sinopsis,
            poster: poster,
            servidores: servidores,
          );
        }
      }
    } catch (e) {
      debugPrint('[Seriesflix] Error en fetchDetail: $e');
    }

    return DetalleContenido(
      ok: false,
      error: 'Error al obtener detalle de Seriesflix',
      servicio: 'seriesflix',
      titulo: titulo,
      tipo: tipo,
    );
  }

  static Future<List<DetalleTemporada>> _extractTemporadas(String html, String serieUrl) async {
    final temporadas = <DetalleTemporada>[];
    final seasonMatches = RegExp(
      r'<a\s+href="([^"]*seriesflix\.vip/temporada/[^"]+)"[^>]*>([\s\S]*?)</a>',
      caseSensitive: false,
    ).allMatches(html).toList();

    // Deduplicar URLs de temporadas
    final seenSeasonUrls = <String>{};
    final uniqueSeasons = <String>[];
    for (final m in seasonMatches) {
      final sUrl = m.group(1) ?? '';
      if (sUrl.isNotEmpty && !seenSeasonUrls.contains(sUrl)) {
        seenSeasonUrls.add(sUrl);
        uniqueSeasons.add(sUrl);
      }
    }

    for (int i = 0; i < uniqueSeasons.length; i++) {
      final sUrl = uniqueSeasons[i];
      final numMatch = RegExp(r'-(\d+)/?$').firstMatch(sUrl);
      final seasonNum = numMatch != null ? int.tryParse(numMatch.group(1)!) ?? (i + 1) : (i + 1);

      try {
        final sRes = await http.get(Uri.parse(sUrl), headers: _headers).timeout(_timeout);
        if (sRes.statusCode >= 200 && sRes.statusCode < 300) {
          final sHtml = sRes.body;
          final episodios = <DetalleCapitulo>[];

          final epMatches = RegExp(
            r'<a\s+href="([^"]*seriesflix\.vip/episodio/[^"]+)"[^>]*>([\s\S]*?)</a>',
            caseSensitive: false,
          ).allMatches(sHtml);

          final seenEpUrls = <String>{};
          for (final epMatch in epMatches) {
            final epUrl = epMatch.group(1) ?? '';
            if (epUrl.isEmpty || seenEpUrls.contains(epUrl)) continue;
            seenEpUrls.add(epUrl);

            final inner = epMatch.group(2) ?? '';
            // Buscar número de episodio (ej: 24x1 o episodio 1)
            final epNumMatch = RegExp(r'(\d+)x(\d+)', caseSensitive: false).firstMatch(epUrl) ??
                RegExp(r'(\d+)x(\d+)', caseSensitive: false).firstMatch(inner) ??
                RegExp(r'episodio\s*(\d+)', caseSensitive: false).firstMatch(inner);

            final epNumber = epNumMatch != null
                ? int.tryParse(epNumMatch.group(epNumMatch.groupCount)!) ?? (episodios.length + 1)
                : (episodios.length + 1);

            final epTitleMatch = RegExp(r'alt="Poster del episodio \d+ de ([^"]+)"', caseSensitive: false).firstMatch(inner) ??
                RegExp(r'<span class="title">([^<]+)</span>', caseSensitive: false).firstMatch(inner);
            final epTitle = epTitleMatch?.group(1)?.trim() ?? 'Episodio $epNumber';

            episodios.add(DetalleCapitulo(
              temporada: seasonNum,
              numero: epNumber,
              titulo: epTitle,
              url: epUrl,
            ));
          }

          episodios.sort((a, b) => a.numero.compareTo(b.numero));

          temporadas.add(DetalleTemporada(
            numero: seasonNum,
            nombre: 'Temporada $seasonNum',
            episodios: episodios,
          ));
        }
      } catch (e) {
        debugPrint('[Seriesflix] Error cargando temporada $sUrl: $e');
      }
    }

    temporadas.sort((a, b) => a.numero.compareTo(b.numero));
    return temporadas;
  }

  // ─── SERVIDORES (FETCH_SERVERS) ───────────────────────────────
  static Future<List<DetalleServidor>> fetchServers({required String url}) async {
    final cleanUrl = _cleanUrl(url);
    try {
      final res = await http.get(Uri.parse(cleanUrl), headers: _headers).timeout(_timeout);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        return _extractServersFromHtml(res.body);
      }
    } catch (e) {
      debugPrint('[Seriesflix] Error en fetchServers ($url): $e');
    }
    return [];
  }

  static List<DetalleServidor> _extractServersFromHtml(String html) {
    final servidores = <DetalleServidor>[];
    final seenUrls = <String>{};

    // Extraer tabs con su idioma
    final tabPattern = RegExp(
      r'<li class="tab-video-item">([\s\S]*?)</li>\s*</ul>',
      caseSensitive: false,
    );

    final tabs = tabPattern.allMatches(html).toList();

    if (tabs.isNotEmpty) {
      for (final tab in tabs) {
        final tabHtml = tab.group(0) ?? '';
        final langMatch = RegExp(
          r'<div class="tab-item-name">\s*([^<\s]+)',
          caseSensitive: false,
        ).firstMatch(tabHtml);
        final langRaw = langMatch?.group(1) ?? 'Latino';
        final idioma = _normalizeIdioma(langRaw);

        final srvMatches = RegExp(
          r'data-server="([^"]+)"',
          caseSensitive: false,
        ).allMatches(tabHtml);

        for (final sm in srvMatches) {
          final b64 = sm.group(1) ?? '';
          if (b64.isEmpty) continue;
          try {
            var decoded = utf8.decode(base64Decode(b64)).trim();
            // Desempaquetar query param `url=` si existe (ej. nupload iframe wrapper de voe)
            if (decoded.contains('url=')) {
              final uri = Uri.tryParse(decoded);
              final innerUrl = uri?.queryParameters['url'];
              if (innerUrl != null && innerUrl.isNotEmpty) {
                decoded = innerUrl;
              }
            }

            if (decoded.isNotEmpty && !seenUrls.contains(decoded)) {
              seenUrls.add(decoded);
              final srvName = _detectServerName(decoded);
              servidores.add(DetalleServidor(
                nombre: 'Seriesflix · $srvName',
                url: decoded,
                idioma: idioma,
                calidad: 'HD',
              ));
            }
          } catch (_) {}
        }
      }
    } else {
      // Fallback directo si no hay estructura de tabs
      final srvMatches = RegExp(
        r'data-server="([^"]+)"',
        caseSensitive: false,
      ).allMatches(html);

      for (final sm in srvMatches) {
        final b64 = sm.group(1) ?? '';
        if (b64.isEmpty) continue;
        try {
          var decoded = utf8.decode(base64Decode(b64)).trim();
          if (decoded.contains('url=')) {
            final uri = Uri.tryParse(decoded);
            final innerUrl = uri?.queryParameters['url'];
            if (innerUrl != null && innerUrl.isNotEmpty) {
              decoded = innerUrl;
            }
          }

          if (decoded.isNotEmpty && !seenUrls.contains(decoded)) {
            seenUrls.add(decoded);
            servidores.add(DetalleServidor(
              nombre: 'Seriesflix · ${_detectServerName(decoded)}',
              url: decoded,
              idioma: _normalizeIdioma(html),
              calidad: 'HD',
            ));
          }
        } catch (_) {}
      }
    }

    return servidores;
  }

  static String _detectServerName(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('voe.sx') || lower.contains('voe-network')) return 'VOE';
    if (lower.contains('nupload')) return 'NUpload';
    if (lower.contains('streamwish') || lower.contains('wishembed')) return 'StreamWish';
    if (lower.contains('dood') || lower.contains('ds2play')) return 'Doodstream';
    if (lower.contains('filelions')) return 'FileLions';
    if (lower.contains('vidhide')) return 'VidHide';
    if (lower.contains('luluvdo') || lower.contains('lulustream')) return 'LuluStream';
    if (lower.contains('mp4upload')) return 'Mp4Upload';
    return 'Stream';
  }

  // ─── BÚSQUEDA Y EXTRACCIÓN POR TMDB / TÍTULO PARA MAIN AGGREGATOR ───
  static Stream<Map<String, dynamic>> scrapeStream({
    required int tmdbId,
    required bool isMovie,
    int season = 1,
    int episode = 1,
    String? titleHint,
  }) async* {
    String? queryTitle = titleHint;

    // Si no tenemos título, intentar resolverlo desde la API pública de Cineby/TMDB
    if (queryTitle == null || queryTitle.isEmpty) {
      try {
        final type = isMovie ? 'movie' : 'series';
        final res = await http.get(
          Uri.parse('https://mv-ba.onrender.com/api/v2/content/details/$type/$tmdbId'),
          headers: {'User-Agent': 'Mozilla/5.0'},
        ).timeout(const Duration(seconds: 6));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          if (data is Map && data['title'] != null) {
            queryTitle = data['title'].toString();
          }
        }
      } catch (_) {}
    }

    if (queryTitle == null || queryTitle.isEmpty) return;

    final searchResults = await search(queryTitle);
    if (searchResults.isEmpty) return;

    final candidate = searchResults.first;

    if (isMovie) {
      final servers = await fetchServers(url: candidate.url);
      for (final s in servers) {
        yield {
          'servidor_nombre': s.nombre,
          'servidor_url': s.url,
          'calidad': s.calidad ?? 'HD',
          'idioma': s.idioma ?? 'latino',
          'estado': 'activo',
          'es_seriesflix': true,
        };
      }
    } else {
      // Buscar la temporada y episodio
      try {
        final res = await http.get(Uri.parse(candidate.url), headers: _headers).timeout(_timeout);
        if (res.statusCode >= 200 && res.statusCode < 300) {
          final html = res.body;
          final seasonRegex = RegExp(r'<a\s+href="([^"]*seriesflix\.vip/temporada/[^"]+)"', caseSensitive: false);
          final seasonUrls = seasonRegex.allMatches(html).map((m) => m.group(1)!).toSet().toList();

          String? targetSeasonUrl;
          for (final sUrl in seasonUrls) {
            if (sUrl.endsWith('-$season') || sUrl.endsWith('-$season/')) {
              targetSeasonUrl = sUrl;
              break;
            }
          }
          targetSeasonUrl ??= seasonUrls.firstOrNull;

          if (targetSeasonUrl != null) {
            final sRes = await http.get(Uri.parse(targetSeasonUrl), headers: _headers).timeout(_timeout);
            if (sRes.statusCode >= 200 && sRes.statusCode < 300) {
              final sHtml = sRes.body;
              final epRegex = RegExp(r'<a\s+href="([^"]*seriesflix\.vip/episodio/[^"]+)"', caseSensitive: false);
              final epUrls = epRegex.allMatches(sHtml).map((m) => m.group(1)!).toSet().toList();

              String? targetEpUrl;
              final tag = '${season}x$episode';
              for (final eUrl in epUrls) {
                if (eUrl.contains(tag)) {
                  targetEpUrl = eUrl;
                  break;
                }
              }
              targetEpUrl ??= epUrls.firstOrNull;

              if (targetEpUrl != null) {
                final servers = await fetchServers(url: targetEpUrl);
                for (final s in servers) {
                  yield {
                    'servidor_nombre': s.nombre,
                    'servidor_url': s.url,
                    'calidad': s.calidad ?? 'HD',
                    'idioma': s.idioma ?? 'subtitulado',
                    'estado': 'activo',
                    'es_seriesflix': true,
                  };
                }
              }
            }
          }
        }
      } catch (e) {
        debugPrint('[Seriesflix] Error resolviendo stream de episodio: $e');
      }
    }
  }
}
