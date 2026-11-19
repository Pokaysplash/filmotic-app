// lib/data/extractors/providers/gnula_extractor.dart
//
// Extractor para ver.gnula.one (catálogo de películas en Latino, Castellano y Subtitulado).
// Usa el endpoint JSON de sugerencias (/wp-json/gnula/v1/suggest?q=...) para
// encontrar la película exacta por título y año, y luego resuelve los embeds
// (?trembed=N&trid=ID&trtype=1) mapeando espejos caídos a espejos activos.

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../core/constants/tmdb_apis.dart';

class GnulaServer {
  final String serverName;
  final String url;
  final String calidad;
  final String idioma; // es_MX | es_ES | en_US
  final String fuente;

  const GnulaServer({
    required this.serverName,
    required this.url,
    required this.calidad,
    required this.idioma,
    this.fuente = 'gnula',
  });

  Map<String, dynamic> toModalMap() => {
        'servidor_nombre': serverName,
        'servidor': serverName,
        'servidor_url': url,
        'url': url,
        'calidad': calidad,
        'idioma': idioma,
        'language': idioma,
        'fuente': fuente,
        'provider': fuente,
      };
}

class GnulaService {
  static const String _base = 'https://ver.gnula.one';
  static const String _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  static const Map<String, String> _kDomainMap = {
    'streamwish.to': 'embedwish.com',
    'strwish.com': 'embedwish.com',
    'hlswish.com': 'embedwish.com',
    'hglink.to': 'embedwish.com',
    'vidhidepro.com': 'callistanise.com',
    'vidhidepre.com': 'callistanise.com',
    'vidhidevip.com': 'callistanise.com',
    'vidhide.com': 'callistanise.com',
    'filelions.to': 'callistanise.com',
    'filelions.com': 'callistanise.com',
    'filelions.live': 'callistanise.com',
  };

  static Map<String, String> _headers([String? referer]) => {
        'User-Agent': _ua,
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'es-ES,es;q=0.9,en;q=0.8',
        'Referer': referer ?? '$_base/',
      };

  static Stream<GnulaServer> scrape({
    required int tmdbId,
    required bool isMovie,
    int season = 1,
    int episode = 1,
  }) async* {
    // ver.gnula.one es catálogo de películas
    if (!isMovie || tmdbId <= 0) return;

    final tmdb = await _fetchTmdbMovie(tmdbId);
    if (tmdb == null) return;

    final pageUrl = await _findMoviePage(
      titles: tmdb.titles,
      year: tmdb.year,
    );
    if (pageUrl == null) return;

    final html = await _getText(pageUrl, referer: '$_base/');
    if (html == null || html.isEmpty) return;

    final trembeds = _extractTrembeds(html);
    if (trembeds.isEmpty) return;

    // Resolvemos hasta 8 embeds en paralelo para mantener latencia baja
    final limited = trembeds.take(8).toList();
    final resolved = await Future.wait(
      limited.map((item) => _resolveTrembed(item, pageUrl)),
    );

    final seen = <String>{};
    for (final s in resolved) {
      if (s == null) continue;
      if (seen.add(s.url)) {
        yield s;
      }
    }
  }

  static Future<({List<String> titles, String year})?> _fetchTmdbMovie(
    int tmdbId,
  ) async {
    try {
      final apiKey = await TmdbApis.getApiKey();
      final resEs = await http
          .get(
            Uri.parse(
              'https://api.themoviedb.org/3/movie/$tmdbId?api_key=$apiKey&language=es-MX',
            ),
          )
          .timeout(const Duration(seconds: 6));
      if (resEs.statusCode != 200) return null;
      final data = jsonDecode(resEs.body) as Map<String, dynamic>;

      final titles = <String>[];
      void addTitle(dynamic v) {
        final s = (v ?? '').toString().trim();
        if (s.isNotEmpty && !titles.contains(s)) titles.add(s);
      }

      addTitle(data['title']);
      addTitle(data['original_title']);

      final release = (data['release_date'] ?? '').toString();
      final year = release.length >= 4 ? release.substring(0, 4) : '';
      return (titles: titles, year: year);
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _findMoviePage({
    required List<String> titles,
    required String year,
  }) async {
    for (final title in titles) {
      final encoded = Uri.encodeQueryComponent(title);
      final url = '$_base/wp-json/gnula/v1/suggest?q=$encoded';
      final body = await _getText(url, referer: '$_base/');
      if (body == null || body.isEmpty) continue;

      try {
        final decoded = jsonDecode(body);
        if (decoded is! List || decoded.isEmpty) continue;

        final targetNorm = _normalize(title);
        String? bestUrl;
        int bestScore = -1;

        for (final item in decoded) {
          if (item is! Map) continue;
          final candUrl = (item['url'] ?? '').toString().trim();
          final candTitle = (item['title'] ?? '').toString().trim();
          final candYear = (item['year'] ?? '').toString().trim();
          if (candUrl.isEmpty || candTitle.isEmpty) continue;

          final candNorm = _normalize(candTitle);
          int score = 0;
          if (candNorm == targetNorm) {
            score += 100;
          } else if (candNorm.contains(targetNorm) ||
              targetNorm.contains(candNorm)) {
            score += 60;
          } else {
            final tWords = targetNorm.split(' ').where((w) => w.length > 2).toSet();
            final cWords = candNorm.split(' ').where((w) => w.length > 2).toSet();
            if (tWords.isEmpty || cWords.isEmpty) continue;
            final overlap = tWords.intersection(cWords).length;
            final ratio = overlap / tWords.length;
            if (ratio < 0.65) continue;
            score += (ratio * 50).round();
          }

          if (year.isNotEmpty && candYear == year) {
            score += 40;
          } else if (year.isNotEmpty && candYear.isNotEmpty) {
            final y1 = int.tryParse(year);
            final y2 = int.tryParse(candYear);
            if (y1 != null && y2 != null && (y1 - y2).abs() <= 1) {
              score += 20;
            } else if (y1 != null && y2 != null && (y1 - y2).abs() > 2) {
              score -= 30;
            }
          }

          if (score > bestScore) {
            bestScore = score;
            bestUrl = candUrl;
          }
        }

        if (bestUrl != null && bestScore >= 60) {
          return bestUrl;
        }
      } catch (_) {}
    }
    return null;
  }

  static List<({String trembedUrl, String idioma})> _extractTrembeds(
    String html,
  ) {
    final out = <({String trembedUrl, String idioma})>[];
    final seen = <String>{};

    // Bloques por idioma: id="gn-ls-latino" | "gn-ls-castellano" | "gn-ls-subtitulado"
    final blockRe = RegExp(
      r'<div\s+class="gn-player__servers[^"]*"[^>]*id="gn-ls-([a-z]+)"[^>]*>(.*?)</div>',
      dotAll: true,
      caseSensitive: false,
    );
    final linkRe = RegExp(
      r'data-src="([^"]*trembed=\d+[^"]*)"',
      caseSensitive: false,
    );

    for (final b in blockRe.allMatches(html)) {
      final langRaw = (b.group(1) ?? '').toLowerCase();
      final idioma = _mapLang(langRaw);
      final body = b.group(2) ?? '';
      for (final m in linkRe.allMatches(body)) {
        final rawUrl = (m.group(1) ?? '').replaceAll('&#038;', '&').replaceAll('&amp;', '&');
        if (rawUrl.isEmpty || !seen.add(rawUrl)) continue;
        out.add((trembedUrl: rawUrl, idioma: idioma));
      }
    }

    // Fallback si la estructura cambia ligeramente
    if (out.isEmpty) {
      for (final m in linkRe.allMatches(html)) {
        final rawUrl = (m.group(1) ?? '').replaceAll('&#038;', '&').replaceAll('&amp;', '&');
        if (rawUrl.isEmpty || !seen.add(rawUrl)) continue;
        out.add((trembedUrl: rawUrl, idioma: 'es_MX'));
      }
    }

    return out;
  }

  static Future<GnulaServer?> _resolveTrembed(
    ({String trembedUrl, String idioma}) item,
    String pageUrl,
  ) async {
    final html = await _getText(item.trembedUrl, referer: pageUrl);
    if (html == null || html.isEmpty) return null;

    final iframeMatch = RegExp(
      r'''<iframe[^>]+src=["']([^"']+)["']''',
      caseSensitive: false,
    ).firstMatch(html);
    if (iframeMatch == null) return null;

    var embedUrl = (iframeMatch.group(1) ?? '').trim();
    if (embedUrl.isEmpty) return null;
    if (embedUrl.startsWith('//')) embedUrl = 'https:$embedUrl';

    // Detectar idioma si viene en el fragmento (#lang=LAT / #lang=SUB / #lang=ESP)
    var idioma = item.idioma;
    final hashIdx = embedUrl.indexOf('#');
    if (hashIdx != -1) {
      final frag = embedUrl.substring(hashIdx).toLowerCase();
      if (frag.contains('lat')) {
        idioma = 'es_MX';
      } else if (frag.contains('esp') || frag.contains('cas')) {
        idioma = 'es_ES';
      } else if (frag.contains('sub')) {
        idioma = 'en_US';
      }
      embedUrl = embedUrl.substring(0, hashIdx);
    }

    embedUrl = _applyDomainMap(embedUrl);
    final host = Uri.tryParse(embedUrl)?.host.toLowerCase() ?? '';
    if (host.isEmpty) return null;

    // Filtrar hosts de anuncios / no reproducibles conocidos
    if (host.contains('facebook.com') || host.contains('youtube.com')) {
      return null;
    }

    final serverName = _prettyServerName(host);
    return GnulaServer(
      serverName: serverName,
      url: embedUrl,
      calidad: 'HD',
      idioma: idioma,
    );
  }

  static String _applyDomainMap(String url) {
    var out = url;
    _kDomainMap.forEach((dead, alive) {
      out = out.replaceAll(dead, alive);
    });
    return out;
  }

  static String _prettyServerName(String host) {
    if (host.contains('embedwish') ||
        host.contains('hgplaycdn') ||
        host.contains('wishembed') ||
        host.contains('sfastwish') ||
        host.contains('streamwish')) {
      return 'StreamWish';
    }
    if (host.contains('callistanise') ||
        host.contains('vidhide') ||
        host.contains('morencius')) {
      return 'VidHide';
    }
    if (host.contains('voe')) return 'VOE';
    if (host.contains('filemoon')) return 'Filemoon';
    if (host.contains('dood')) return 'Doodstream';
    if (host.contains('vidara')) return 'Vidara';
    if (host.contains('fiuxy')) return 'Fiuxy';
    final clean = host.replaceFirst('www.', '').split('.').first;
    if (clean.isEmpty) return 'Gnula';
    return clean[0].toUpperCase() + clean.substring(1);
  }

  static String _mapLang(String raw) {
    if (raw.contains('castellano') || raw.contains('esp')) return 'es_ES';
    if (raw.contains('sub') || raw.contains('vose') || raw.contains('ing')) {
      return 'en_US';
    }
    return 'es_MX';
  }

  static String _normalize(String s) {
    const accents = 'áéíóúüñÁÉÍÓÚÜÑ';
    const plain = 'aeiouunAEIOUUN';
    var out = s;
    for (var i = 0; i < accents.length; i++) {
      out = out.replaceAll(accents[i], plain[i]);
    }
    return out
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static Future<String?> _getText(String url, {String? referer}) async {
    try {
      final res = await http
          .get(Uri.parse(url), headers: _headers(referer))
          .timeout(const Duration(seconds: 7));
      if (res.statusCode == 200) return res.body;
    } catch (_) {}
    return null;
  }
}

