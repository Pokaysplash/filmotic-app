// lib/data/extractors/providers/animeflv_extractor.dart
//
// Extractor de servidores de AnimeFLV (animeflv.com.es).
// Extrae embeds directos (Blogger, Voe, Mp4Upload, StreamWish, Zilla, YourUpload, etc.).
// Totalmente compatible con MainFuentes / sources.dart / ServidoresModal.

import 'dart:async';
import 'dart:convert';

import 'package:html/parser.dart' as parser;
import 'package:http/http.dart' as http;

class AnimeFlvServer {
  final String serverName;
  final String url;
  final String calidad;
  final String idioma;
  final int tmdbId;
  final int season;
  final int episode;

  const AnimeFlvServer({
    required this.serverName,
    required this.url,
    this.calidad = 'HD',
    this.idioma = 'SUB',
    required this.tmdbId,
    required this.season,
    required this.episode,
  });

  Map<String, dynamic> toModalMap() {
    return {
      'servidor_nombre': 'AnimeFLV · $serverName',
      'servidor_url': url,
      'calidad': calidad,
      'idioma': idioma,
      'estado': 'activo',
      'es_animeflv': true,
      'tmdb_id': tmdbId,
      'season': season,
      'episode': episode,
      'fuente': 'animeflv',
      'type': 'embed',
      'provider': 'AnimeFLV',
    };
  }
}

class AnimeFlvService {
  AnimeFlvService._();

  static const String _kBase = 'https://animeflv.com.es';
  static const String _kTmdbKey = 'a2d9bbed370d9f678e34006f8750a5a5';
  static const String _kTmdbBase = 'https://api.themoviedb.org/3';
  static const String _kUa =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';
  static const Duration _timeout = Duration(seconds: 10);

  /// Scrapea servidores desde AnimeFLV para un contenido dado por tmdbId.
  static Stream<AnimeFlvServer> scrape({
    required int tmdbId,
    required bool isMovie,
    int season = 1,
    int episode = 1,
  }) async* {
    if (tmdbId <= 0) return;

    try {
      final mediaType = isMovie ? 'movie' : 'tv';

      // 1. Obtener títulos de TMDB (original japonés/romaji, español, inglés)
      final titles = await _getTmdbTitles(
        tmdbId: tmdbId,
        mediaType: mediaType,
        season: season,
      );
      if (titles.isEmpty) return;

      // 2. Buscar URL del episodio o película en AnimeFLV
      final episodeUrl = await _findEpisodeUrl(
        titles: titles,
        isMovie: isMovie,
        season: season,
        episode: episode,
      );
      if (episodeUrl == null || episodeUrl.isEmpty) return;

      // 3. Descargar HTML de la página del episodio
      final html = await _fetchHtml(episodeUrl);
      if (html == null || html.isEmpty) return;

      // 4. Extraer servidores de video (data-src Base64, iframes, scripts)
      final servers = _extractServers(html: html, episodeUrl: episodeUrl);
      if (servers.isEmpty) return;

      final seen = <String>{};
      for (final s in servers) {
        final url = s['url']?.toString().trim() ?? '';
        if (url.isEmpty || seen.contains(url)) continue;
        seen.add(url);

        final name = s['name']?.toString() ?? 'Online';
        final idioma = s['idioma']?.toString() ?? 'SUB';

        yield AnimeFlvServer(
          serverName: name,
          url: url,
          calidad: 'HD',
          idioma: idioma,
          tmdbId: tmdbId,
          season: isMovie ? 0 : season,
          episode: isMovie ? 1 : episode,
        );

        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    } catch (_) {
      // Silencioso: el agregador maneja fallbacks entre fuentes
    }
  }

  // ─────────────────────────────────────────────────────────
  // TMDB — Títulos en japonés/romaji, español e inglés
  // ─────────────────────────────────────────────────────────

  static Future<List<String>> _getTmdbTitles({
    required int tmdbId,
    required String mediaType,
    required int season,
  }) async {
    final titles = <String>{};

    Future<void> fetchDetail(String? lang) async {
      try {
        final uri = Uri.parse(
          '$_kTmdbBase/$mediaType/$tmdbId?api_key=$_kTmdbKey${lang != null ? '&language=$lang' : ''}',
        );
        final res = await http.get(uri, headers: {
          'Accept': 'application/json',
          'User-Agent': _kUa,
        }).timeout(_timeout);

        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          if (data is Map<String, dynamic>) {
            final t = data['title']?.toString() ?? data['name']?.toString();
            if (t != null && t.trim().isNotEmpty) titles.add(t.trim());

            final ot = data['original_title']?.toString() ??
                data['original_name']?.toString();
            if (ot != null && ot.trim().isNotEmpty) titles.add(ot.trim());
          }
        }
      } catch (_) {}
    }

    await Future.wait([
      fetchDetail('es-MX'),
      fetchDetail('en-US'),
      fetchDetail(null), // Idioma original
    ]);

    // Si es serie y temporada > 1, intentar obtener el nombre de la temporada
    if (mediaType == 'tv' && season > 1) {
      try {
        final uri = Uri.parse(
          '$_kTmdbBase/tv/$tmdbId/season/$season?api_key=$_kTmdbKey&language=es-MX',
        );
        final res = await http.get(uri, headers: {
          'Accept': 'application/json',
          'User-Agent': _kUa,
        }).timeout(_timeout);
        if (res.statusCode == 200) {
          final sData = jsonDecode(res.body);
          if (sData is Map<String, dynamic>) {
            final sName = sData['name']?.toString();
            if (sName != null &&
                sName.trim().isNotEmpty &&
                !sName.toLowerCase().startsWith('temporada')) {
              titles.add(sName.trim());
            }
          }
        }
      } catch (_) {}
    }

    return titles.toList();
  }

  // ─────────────────────────────────────────────────────────
  // Búsqueda en AnimeFLV
  // ─────────────────────────────────────────────────────────

  static Future<String?> _findEpisodeUrl({
    required List<String> titles,
    required bool isMovie,
    required int season,
    required int episode,
  }) async {
    final epTarget = isMovie ? 1 : episode;

    for (final title in titles) {
      // 1. Consultar API WP-JSON Search
      final queries = <String>[];
      if (!isMovie) {
        queries.add('$title Episodio $epTarget');
        queries.add('$title $epTarget');
        if (season > 1) {
          queries.add('$title Season $season Episodio $epTarget');
          queries.add('$title $season Episodio $epTarget');
        }
        queries.add(title);
      } else {
        queries.add('$title Pelicula');
        queries.add('$title Movie');
        queries.add('$title Episodio 1');
        queries.add(title);
      }

      for (final q in queries) {
        final found = await _queryWpSearch(q, epTarget, isMovie);
        if (found != null && found.isNotEmpty) return found;
      }

      // 2. Probar slug directo
      final directSlug = _slugify(title);
      final candidateUrls = <String>[
        '$_kBase/$directSlug-episodio-$epTarget/',
        if (season > 1) ...[
          '$_kBase/$directSlug-season-$season-episodio-$epTarget/',
          '$_kBase/$directSlug-${season}nd-season-episodio-$epTarget/',
          '$_kBase/$directSlug-${season}rd-season-episodio-$epTarget/',
          '$_kBase/$directSlug-${season}th-season-episodio-$epTarget/',
        ],
        if (isMovie) '$_kBase/$directSlug-pelicula/',
      ];

      for (final url in candidateUrls) {
        if (await _checkUrlExists(url)) {
          return url;
        }
      }
    }

    return null;
  }

  static Future<String?> _queryWpSearch(
    String query,
    int epTarget,
    bool isMovie,
  ) async {
    try {
      final uri = Uri.parse(
        '$_kBase/wp-json/wp/v2/search?search=${Uri.encodeComponent(query)}',
      );
      final res = await http.get(uri, headers: {
        'Accept': 'application/json',
        'User-Agent': _kUa,
      }).timeout(_timeout);

      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body);
      if (data is! List || data.isEmpty) return null;

      final epPattern = RegExp('episodio[- ]$epTarget(?:[^0-9]|\$)', caseSensitive: false);

      for (final item in data) {
        if (item is! Map) continue;
        final url = item['url']?.toString() ?? '';
        final title = item['title']?.toString() ?? '';

        if (url.isEmpty) continue;

        if (isMovie) {
          // Si es película, cualquier resultado que coincida o tenga episodio 1
          if (url.contains('episodio-1') ||
              url.contains('pelicula') ||
              title.toLowerCase().contains('pelicula') ||
              title.toLowerCase().contains('movie')) {
            return url;
          }
        } else {
          // Si es serie, verificar que coincida con el número de episodio
          if (epPattern.hasMatch(url) || epPattern.hasMatch(title)) {
            return url;
          }
        }
      }

      // Si sólo vino 1 resultado y tiene episodio en la url, validarlo
      if (data.length == 1) {
        final url = data[0]['url']?.toString() ?? '';
        if (epPattern.hasMatch(url)) return url;
      }
    } catch (_) {}
    return null;
  }

  static Future<bool> _checkUrlExists(String url) async {
    try {
      final res = await http.head(Uri.parse(url), headers: {
        'User-Agent': _kUa,
      }).timeout(const Duration(seconds: 4));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static String _slugify(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[:・·_]+'), ' ')
        .replaceAll(RegExp(r'[^a-z0-9\s-]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '-')
        .replaceAll(RegExp(r'-+'), '-');
  }

  // ─────────────────────────────────────────────────────────
  // Extracción de Servidores desde el HTML del episodio
  // ─────────────────────────────────────────────────────────

  static List<Map<String, String>> _extractServers({
    required String html,
    required String episodeUrl,
  }) {
    final results = <Map<String, String>>[];
    final seenUrls = <String>{};

    // 1. Extraer botones con data-src en Base64
    //    Ejemplo: <button data-src="aHR0cHM6Ly92b2Uuc3gvZS9... ">OPCIÓN 2</button>
    final doc = parser.parse(html);
    final elementsWithDataSrc = doc.querySelectorAll('[data-src]');

    for (final el in elementsWithDataSrc) {
      final rawB64 = el.attributes['data-src']?.trim() ?? '';
      if (rawB64.isEmpty) continue;

      String decodedUrl = '';
      try {
        decodedUrl = utf8.decode(base64.decode(base64.normalize(rawB64))).trim();
      } catch (_) {
        // Podría ser URL directa no codificada
        if (rawB64.startsWith('http')) {
          decodedUrl = rawB64;
        }
      }

      if (decodedUrl.isEmpty || !decodedUrl.startsWith('http')) continue;
      if (seenUrls.contains(decodedUrl)) continue;
      seenUrls.add(decodedUrl);

      final label = el.text.trim();
      final serverName = _resolveServerName(decodedUrl, label);
      final idioma = _detectIdioma('$label $decodedUrl $html');

      results.add({
        'name': serverName,
        'url': decodedUrl,
        'idioma': idioma,
      });
    }

    // 2. Extraer iframes en el HTML
    final iframes = doc.querySelectorAll('iframe');
    for (final iframe in iframes) {
      var src = iframe.attributes['src']?.trim() ?? '';
      if (src.isEmpty) continue;
      if (src.startsWith('//')) src = 'https:$src';
      if (!src.startsWith('http')) continue;

      // Filtrar recaptcha y trackers comunes
      final lower = src.toLowerCase();
      if (lower.contains('recaptcha') ||
          lower.contains('google.com') ||
          lower.contains('facebook.com') ||
          lower.contains('disqus.com')) {
        continue;
      }

      if (seenUrls.contains(src)) continue;
      seenUrls.add(src);

      final serverName = _resolveServerName(src, 'Directo');
      final idioma = _detectIdioma(src);

      results.add({
        'name': serverName,
        'url': src,
        'idioma': idioma,
      });
    }

    // 3. Extraer variables JS clásicas de AnimeFLV: var videos = {"SUB": [...], "LAT": [...]};
    final matchVideos =
        RegExp(r'var videos\s*=\s*(\{[\s\S]*?\});').firstMatch(html);
    if (matchVideos != null) {
      try {
        final map = jsonDecode(matchVideos.group(1)!) as Map<String, dynamic>;
        map.forEach((langKey, list) {
          final lang = _detectIdioma(langKey);
          if (list is List) {
            for (final item in list) {
              if (item is Map) {
                final title = item['title']?.toString() ?? 'Server';
                final code =
                    item['code']?.toString() ?? item['url']?.toString() ?? '';
                if (code.isNotEmpty && code.startsWith('http')) {
                  if (!seenUrls.contains(code)) {
                    seenUrls.add(code);
                    results.add({
                      'name': _resolveServerName(code, title),
                      'url': code,
                      'idioma': lang,
                    });
                  }
                }
              }
            }
          }
        });
      } catch (_) {}
    }

    return results;
  }

  static String _resolveServerName(String url, String fallback) {
    final lower = url.toLowerCase();
    if (lower.contains('blogger.com') || lower.contains('blogspot')) {
      return 'Blogger';
    }
    if (lower.contains('voe.sx')) return 'Voe';
    if (lower.contains('mp4upload')) return 'Mp4Upload';
    if (lower.contains('byselapuix') ||
        lower.contains('streamwish') ||
        lower.contains('wishembed')) {
      return 'StreamWish';
    }
    if (lower.contains('zilla-networks')) return 'Zilla';
    if (lower.contains('uns.bio') ||
        lower.contains('yourupload') ||
        lower.contains('animeav1')) {
      return 'YourUpload';
    }
    if (lower.contains('dood') || lower.contains('ds2play')) return 'Doodstream';
    if (lower.contains('streamtape')) return 'Streamtape';
    if (lower.contains('filemoon')) return 'Filemoon';
    if (lower.contains('ok.ru')) return 'OkRu';
    if (lower.contains('mega.nz')) return 'Mega';

    final cleanFallback = fallback.replaceAll(RegExp(r'[^a-zA-Z0-9 ]'), '').trim();
    return cleanFallback.isNotEmpty ? cleanFallback : 'Online';
  }

  static String _detectIdioma(String text) {
    final lower = text.toLowerCase();
    if (lower.contains('latino') || lower.contains('lat')) return 'LAT';
    if (lower.contains('castellano') || lower.contains('cast') || lower.contains('españa')) {
      return 'CAST';
    }
    if (lower.contains('ingles') || lower.contains('english')) return 'ENG';
    return 'SUB';
  }

  static Future<String?> _fetchHtml(String url) async {
    try {
      final res = await http.get(Uri.parse(url), headers: {
        'User-Agent': _kUa,
      }).timeout(_timeout);
      if (res.statusCode == 200) return res.body;
    } catch (_) {}
    return null;
  }
}
