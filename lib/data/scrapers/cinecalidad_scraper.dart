import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/scraper/detalle_model.dart';
import 'base/base_home_scraper.dart';
import 'base/buscador.dart';
import '../extractors/providers/cinecalidad_extractor.dart';

class CinecalidadScraper {
  static const String baseApi = 'https://tmdb.allcalidad.re';
  static const String webBase = 'https://www.cinecalidad.am';

  static const List<String> generos = [
    'acción',
    'animación',
    'aventura',
    'ciencia-ficción',
    'comedia',
    'crimen',
    'drama',
    'fantasía',
    'terror',
    'romance',
    'suspense',
  ];

  static List<String> tiposDisponibles() => ['movie', 'popular', 'latest'];

  static String _detectIdioma(String text) {
    final lower = text.toLowerCase();
    if (lower.contains('latino') || lower.contains('español latino') || lower.contains('audio latino')) {
      return 'latino';
    }
    if (lower.contains('castellano') || lower.contains('españa') || lower.contains('cast')) {
      return 'castellano';
    }
    if (lower.contains('subtitulado') || lower.contains('sub') || lower.contains('vose')) {
      return 'subtitulado';
    }
    if (lower.contains('ingles') || lower.contains('inglés') || lower.contains('english')) {
      return 'inglés';
    }
    return 'latino'; // Default en Cinecalidad
  }

  // ─── LISTADO (FETCH) ──────────────────────────────────────────
  static Future<ScraperResult> fetch({
    String? tipo,
    String? genero,
    bool populares = false,
    int page = 1,
  }) async {
    final sort = (populares || tipo == 'popular') ? 'popular' : 'latest';
    final limit = 24;

    var uriString = '$baseApi/v1/items?kind=movie&sort=$sort&page=$page&limit=$limit';
    if (genero != null && genero.isNotEmpty) {
      uriString += '&genre=${Uri.encodeComponent(genero)}';
    }

    try {
      final res = await http.get(
        Uri.parse(uriString),
        headers: {
          'Accept': 'application/json',
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        },
      ).timeout(const Duration(seconds: 15));

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final data = json.decode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        final rawItems = data['items'] as List? ?? [];
        final pagination = data['pagination'] as Map<String, dynamic>? ?? {};

        final items = <ScraperItem>[];
        for (final item in rawItems) {
          if (item is! Map<String, dynamic>) continue;

          final tmdbId = item['tmdb_id'] as int?;
          final title = item['title']?.toString() ?? 'Sin título';
          final posterPath = item['poster_path']?.toString() ?? '';
          final posterUrl = posterPath.isNotEmpty
              ? (posterPath.startsWith('http') ? posterPath : 'https://image.tmdb.org/t/p/w342$posterPath')
              : '';
          final code = item['code']?.toString() ?? '';
          final year = item['year'] as int? ??
              int.tryParse(item['release_date']?.toString().split('-').first ?? '');
          final rating = (item['vote_average'] as num?)?.toDouble();
          final overview = item['overview']?.toString();
          final slug = item['slug']?.toString() ?? '';

          items.add(ScraperItem(
            titulo: title,
            tipo: 'movie',
            url: code.isNotEmpty ? 'https://vimeos.net/embed-$code.html' : '$webBase/pelicula/$tmdbId/$slug',
            poster: posterUrl,
            year: year,
            rating: rating,
            tmdbId: tmdbId,
            sinopsis: overview,
          ));
        }

        debugPrint('[Cinecalidad] Encontrados ${items.length} elementos (Página $page)');

        final hasNext = pagination['has_next'] as bool? ?? (items.length >= limit);

        return ScraperResult(
          ok: true,
          url: uriString,
          currentPage: page,
          hasNext: hasNext,
          items: items,
        );
      }
    } catch (e) {
      debugPrint('[Cinecalidad] Error cargando catálogo: $e');
    }

    return ScraperResult(
      ok: false,
      error: 'Error al conectar con el servidor de Cinecalidad',
      url: uriString,
    );
  }

  // ─── BÚSQUEDA ─────────────────────────────────────────────────
  static Future<List<BuscadorItem>> search(String q) async {
    final query = Uri.encodeComponent(q.trim());
    final uri = '$baseApi/v1/items?kind=movie&q=$query&limit=24';

    try {
      final res = await http.get(
        Uri.parse(uri),
        headers: {
          'Accept': 'application/json',
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        },
      ).timeout(const Duration(seconds: 15));

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final data = json.decode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        final rawItems = data['items'] as List? ?? [];
        final results = <BuscadorItem>[];

        for (final item in rawItems) {
          if (item is! Map<String, dynamic>) continue;
          final tmdbId = item['tmdb_id'] as int?;
          final title = item['title']?.toString() ?? 'Sin título';
          final posterPath = item['poster_path']?.toString() ?? '';
          final posterUrl = posterPath.isNotEmpty
              ? (posterPath.startsWith('http') ? posterPath : 'https://image.tmdb.org/t/p/w342$posterPath')
              : '';
          final code = item['code']?.toString() ?? '';
          final year = item['year'] as int? ??
              int.tryParse(item['release_date']?.toString().split('-').first ?? '');
          final rating = (item['vote_average'] as num?)?.toDouble();
          final slug = item['slug']?.toString() ?? '';

          results.add(BuscadorItem(
            sitio: 'cinecalidad',
            titulo: title,
            tipo: 'movie',
            url: code.isNotEmpty ? 'https://vimeos.net/embed-$code.html' : '$webBase/pelicula/$tmdbId/$slug',
            imagen: posterUrl,
            anio: year,
            rating: rating,
            tmdbId: tmdbId,
          ));
        }

        debugPrint('[Cinecalidad] Búsqueda "$q": ${results.length} resultados');
        return results;
      }
    } catch (e) {
      debugPrint('[Cinecalidad] Error en búsqueda "$q": $e');
    }

    return [];
  }

  // ─── DETALLE Y SERVIDORES ─────────────────────────────────────
  static Future<DetalleContenido> fetchDetail({
    required String url,
    required String titulo,
    required String tipo,
  }) async {
    final servidores = <DetalleServidor>[];
    final seenUrls = <String>{};

    // 1. Extraer tmdbId si está en la URL (ej: /pelicula/533535/deadpool-wolverine)
    final tmdbMatch = RegExp(r'/pelicula/(\d+)').firstMatch(url);
    final tmdbId = tmdbMatch != null ? int.tryParse(tmdbMatch.group(1)!) : null;

    if (tmdbId != null && tmdbId > 0) {
      try {
        await for (final s in CinecalidadService.scrape(
          tmdbId: tmdbId,
          isMovie: tipo == 'movie',
        )) {
          if (!seenUrls.contains(s.url)) {
            seenUrls.add(s.url);
            servidores.add(DetalleServidor(
              nombre: s.serverClean.isNotEmpty ? 'Cinecalidad · ${s.serverClean}' : s.serverName,
              url: s.url,
              idioma: s.idioma == 'es_ES' ? 'castellano' : (s.idioma == 'en_US' ? 'subtitulado' : 'latino'),
              calidad: s.calidad,
            ));
          }
        }
      } catch (_) {}
    }

    // 2. Si no hay servidores o la URL es directa, intentar scrapear HTML directo
    if (servidores.isEmpty && url.startsWith('http')) {
      try {
        final res = await http.get(Uri.parse(url), headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        }).timeout(const Duration(seconds: 10));

        if (res.statusCode == 200) {
          final html = res.body;
          // Buscar data-option o enlaces
          final optRe = RegExp(r'data-option="([^"]+)"', caseSensitive: false);
          for (final m in optRe.allMatches(html)) {
            var raw = m.group(1) ?? '';
            if (raw.contains('zopass=')) {
              try {
                final uri = Uri.parse(raw.startsWith('http') ? raw : 'https://dummy$raw');
                final zopass = uri.queryParameters['zopass'];
                if (zopass != null && zopass.isNotEmpty) {
                  raw = utf8.decode(base64Decode(zopass));
                }
              } catch (_) {}
            }
            if (raw.isNotEmpty && !seenUrls.contains(raw)) {
              seenUrls.add(raw);
              servidores.add(DetalleServidor(
                nombre: 'Cinecalidad · Stream HD',
                url: raw,
                idioma: _detectIdioma(html),
                calidad: html.contains('4K') ? '4K' : (html.contains('720p') ? '720p' : '1080p'),
              ));
            }
          }
        }
      } catch (_) {}
    }

    // 3. Fallback si no hubo otros
    if (servidores.isEmpty) {
      servidores.add(DetalleServidor(
        nombre: 'Cinecalidad · Stream 1080p',
        url: url,
        idioma: 'latino',
        calidad: '1080p',
      ));
    }

    return DetalleContenido(
      ok: true,
      servicio: 'cinecalidad',
      titulo: titulo,
      tipo: tipo,
      servidores: servidores,
    );
  }
}
