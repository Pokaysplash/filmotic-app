import 'dart:async';
import 'dart:convert';
import 'package:html/parser.dart' as parser;
import 'package:http/http.dart' as http;
import '../../core/services/source_health_service.dart';
import '../models/scraper/detalle_model.dart';
import 'base/base_home_scraper.dart';

/// Scraper de AnimeFLV basado en la API web directa de AnimeFLV (WAVE 12.17)
class AnimeFlvApiScraper {
  static const String sourceId = 'animeflv_api';
  static const String baseUrl = 'https://www3.animeflv.net';

  static const String userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';
  static const Duration timeout = Duration(seconds: 8);

  static Future<http.Response?> _request(String path) async {
    final sw = Stopwatch()..start();
    try {
      final url = path.startsWith('http') ? path : '$baseUrl$path';
      final res = await http.get(Uri.parse(url), headers: {
        'User-Agent': userAgent,
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Referer': baseUrl,
      }).timeout(timeout);

      sw.stop();
      if (res.statusCode == 200) {
        SourceHealthService.instance.recordSuccess(sourceId, sw.elapsedMilliseconds);
        return res;
      }
    } catch (_) {
      sw.stop();
    }
    SourceHealthService.instance.recordFailure(sourceId, 'Timeout o error en AnimeFLV');
    return null;
  }

  // ─── FETCH (LISTADO) ───────────────────────────────────────────────────────
  static Future<ScraperResult> fetch({
    String? tipo,
    String? genero,
    int page = 1,
  }) async {
    final res = await _request('/browse?page=$page&order=rating');
    if (res == null) {
      return ScraperResult(ok: false, error: 'Sin respuesta de AnimeFLV');
    }

    try {
      final doc = parser.parse(res.body);
      final items = <ScraperItem>[];
      final cards = doc.querySelectorAll('ul.ListAnimes li article');

      for (final c in cards) {
        final aTag = c.querySelector('a');
        final link = aTag?.attributes['href'] ?? '';
        final title = c.querySelector('h3.Title')?.text.trim() ?? '';
        final img = c.querySelector('div.Image figure img')?.attributes['src'] ?? '';
        final typeText = c.querySelector('span.Type')?.text.trim() ?? 'Anime';

        if (title.isNotEmpty && link.isNotEmpty) {
          items.add(ScraperItem(
            sitio: sourceId,
            titulo: title,
            tipo: 'anime',
            url: link.startsWith('http') ? link : '$baseUrl$link',
            poster: img.startsWith('http') ? img : '$baseUrl$img',
            generos: [typeText],
          ));
        }
      }

      return ScraperResult(
        ok: items.isNotEmpty,
        items: items,
        currentPage: page,
        hasNext: items.length >= 12,
      );
    } catch (e) {
      return ScraperResult(ok: false, error: 'Error parseando AnimeFLV: $e');
    }
  }

  // ─── SEARCH (BÚSQUEDA) ─────────────────────────────────────────────────────
  static Future<List<ScraperItem>> search(String query) async {
    final q = Uri.encodeComponent(query.trim());
    final res = await _request('/browse?q=$q');
    if (res == null) return [];

    try {
      final doc = parser.parse(res.body);
      final items = <ScraperItem>[];
      final cards = doc.querySelectorAll('ul.ListAnimes li article');

      for (final c in cards) {
        final aTag = c.querySelector('a');
        final link = aTag?.attributes['href'] ?? '';
        final title = c.querySelector('h3.Title')?.text.trim() ?? '';
        final img = c.querySelector('div.Image figure img')?.attributes['src'] ?? '';
        final typeText = c.querySelector('span.Type')?.text.trim() ?? 'Anime';

        if (title.isNotEmpty && link.isNotEmpty) {
          items.add(ScraperItem(
            sitio: sourceId,
            titulo: title,
            tipo: 'anime',
            url: link.startsWith('http') ? link : '$baseUrl$link',
            poster: img.startsWith('http') ? img : '$baseUrl$img',
            generos: [typeText],
          ));
        }
      }
      return items;
    } catch (_) {
      return [];
    }
  }

  // ─── DETAIL (DETALLE) ──────────────────────────────────────────────────────
  static Future<DetalleContenido> fetchDetail({
    required String url,
    required String titulo,
    required String tipo,
  }) async {
    final res = await _request(url);
    if (res == null) {
      return DetalleContenido(
        ok: false,
        error: 'No se pudo cargar detalle de AnimeFLV',
        servicio: sourceId,
        titulo: titulo,
        tipo: 'anime',
      );
    }

    try {
      final doc = parser.parse(res.body);
      final poster = doc.querySelector('div.AnimeCover div.Image figure img')?.attributes['src'] ?? '';
      final sinopsis = doc.querySelector('div.Description p')?.text.trim();
      final ratingText = doc.querySelector('#votes_prmd')?.text.trim();
      final rating = double.tryParse(ratingText ?? '');

      final generos = doc
          .querySelectorAll('nav.Nvgnrs a')
          .map((a) => a.text.trim())
          .where((g) => g.isNotEmpty)
          .toList();

      final temporadas = <DetalleTemporada>[];
      final capitulos = <DetalleCapitulo>[];

      // Extraer variable episodes y anime_info en JavaScript
      final body = res.body;
      final epRegex = RegExp(r'var\s+episodes\s*=\s*(\[\[.*?\]\]);', dotAll: true);
      final epMatch = epRegex.firstMatch(body);

      // Slug para construir url de episodio: https://www3.animeflv.net/ver/{slug}-{numero}
      final uri = Uri.parse(url);
      final slug = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : '';

      if (epMatch != null) {
        final rawJson = epMatch.group(1);
        if (rawJson != null) {
          final list = jsonDecode(rawJson) as List;
          // AnimeFLV devuelve en orden inverso [último, ..., primero]
          final reversed = list.reversed.toList();
          for (int i = 0; i < reversed.length; i++) {
            final epItem = reversed[i];
            if (epItem is List && epItem.isNotEmpty) {
              final epNum = epItem[0];
              capitulos.add(DetalleCapitulo(
                temporada: 1,
                numero: int.tryParse('$epNum') ?? (i + 1),
                titulo: 'Episodio $epNum',
                url: '$baseUrl/ver/$slug-$epNum',
              ));
            }
          }
        }
      }

      if (capitulos.isNotEmpty) {
        temporadas.add(DetalleTemporada(
          numero: 1,
          nombre: 'Temporada 1',
          episodios: capitulos,
        ));
      }

      final firstEpUrl = capitulos.isNotEmpty ? capitulos.first.url : url;
      final servers = await fetchServers(url: firstEpUrl);

      return DetalleContenido(
        ok: true,
        servicio: sourceId,
        titulo: titulo,
        tipo: 'anime',
        sinopsis: sinopsis,
        poster: poster.startsWith('http') ? poster : '$baseUrl$poster',
        generos: generos.isNotEmpty ? generos : const ['Anime', 'Animación', 'Japón'],
        rating: rating,
        servidores: servers,
        temporadas: temporadas,
      );
    } catch (e) {
      return DetalleContenido(
        ok: false,
        error: 'Error parseando AnimeFLV: $e',
        servicio: sourceId,
        titulo: titulo,
        tipo: 'anime',
      );
    }
  }

  // ─── SERVIDORES ────────────────────────────────────────────────────────────
  static Future<List<DetalleServidor>> fetchServers({
    required String url,
    String? html,
  }) async {
    final servers = <DetalleServidor>[];
    String body = html ?? '';
    if (body.isEmpty) {
      final res = await _request(url);
      if (res != null) body = res.body;
    }
    if (body.isEmpty) return servers;

    try {
      // Extraer variable videos = {"SUB": [...]}
      final videosRegex = RegExp(r'var\s+videos\s*=\s*(\{.*?\});', dotAll: true);
      final match = videosRegex.firstMatch(body);

      if (match != null) {
        final jsonText = match.group(1);
        if (jsonText != null) {
          final data = jsonDecode(jsonText) as Map<String, dynamic>;
          for (final entry in data.entries) {
            final lang = entry.key.toLowerCase();
            final serverList = entry.value;
            if (serverList is List) {
              for (final s in serverList) {
                if (s is Map) {
                  final serverName = (s['title'] ?? s['server'] ?? 'Stream').toString();
                  final code = (s['code'] ?? s['url'] ?? '').toString();
                  if (code.isNotEmpty) {
                    servers.add(DetalleServidor(
                      nombre: 'AnimeFLV · $serverName',
                      url: code,
                      idioma: lang.contains('lat') ? 'latino' : 'subtitulado',
                      calidad: 'HD',
                    ));
                  }
                }
              }
            }
          }
        }
      }

      // Fallback a iframes directos
      if (servers.isEmpty) {
        final doc = parser.parse(body);
        for (final ifr in doc.querySelectorAll('iframe[src]')) {
          final src = ifr.attributes['src'] ?? '';
          if (src.isNotEmpty && !servers.any((s) => s.url == src)) {
            servers.add(DetalleServidor(
              nombre: 'AnimeFLV · Reproductor',
              url: src.startsWith('//') ? 'https:$src' : src,
              idioma: 'subtitulado',
              calidad: 'HD',
            ));
          }
        }
      }
    } catch (_) {}

    return servers;
  }
}
