import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/scraper/detalle_model.dart';
import 'base/base_home_scraper.dart';
import 'base/buscador.dart';

/// Scraper modular para Cineby (https://cineby.me)
/// Extrae contenido en Versión Original (Inglés) con subtítulos en Español (VOS).
class CinebyScraper {
  static const String baseApi = 'https://mv-ba.onrender.com/api';
  static const String embedBase = 'https://api.cineby.homes';
  static const String vidsrcMetaApi = 'https://data.vidsrc.sh/api.php';
  static const Duration _timeout = Duration(seconds: 12);

  static const Map<String, String> _headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
    'Accept': 'application/json, text/plain, */*',
    'Referer': 'https://movie.cineby.me/',
  };

  static const List<String> generos = [
    'action',
    'adventure',
    'animation',
    'comedy',
    'crime',
    'drama',
    'fantasy',
    'horror',
    'romance',
    'sci-fi',
    'thriller',
  ];

  static List<String> tiposDisponibles() => ['movie', 'series', 'trending'];

  // ─── LISTADO (FETCH) ──────────────────────────────────────────
  static Future<ScraperResult> fetch({
    String? tipo,
    String? genero,
    bool populares = false,
    int page = 1,
  }) async {
    final endpoint = '$baseApi/v2/content/trending';
    try {
      final res = await http.get(Uri.parse(endpoint), headers: _headers).timeout(_timeout);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final data = jsonDecode(res.body);
        if (data is List) {
          final items = <ScraperItem>[];
          for (final item in data) {
            if (item is! Map) continue;
            final id = item['id'];
            final tmdbId = id is int ? id : int.tryParse(id?.toString() ?? '');
            final title = item['title']?.toString() ?? 'Sin título';
            final poster = item['poster']?.toString() ?? '';
            final typeStr = item['type']?.toString() == 'series' ? 'tv' : 'movie';

            // Filtrar por tipo si se especifica
            if (tipo != null && tipo.isNotEmpty && tipo != 'trending') {
              final wanted = (tipo == 'series' || tipo == 'tv') ? 'tv' : 'movie';
              if (typeStr != wanted) continue;
            }

            final year = item['year'] is int
                ? item['year'] as int
                : int.tryParse(item['year']?.toString() ?? '');
            final rating = (item['rating'] as num?)?.toDouble();
            final desc = item['description']?.toString();

            items.add(ScraperItem(
              titulo: title,
              tipo: typeStr,
              url: 'https://cineby.me/$typeStr/$tmdbId',
              poster: poster,
              year: year,
              rating: rating,
              tmdbId: tmdbId,
              sinopsis: desc,
            ));
          }

          return ScraperResult(
            ok: true,
            url: endpoint,
            currentPage: page,
            hasNext: false, // trending es lista fija
            items: items,
          );
        }
      }
    } catch (e) {
      debugPrint('[Cineby] Error en fetch: $e');
    }

    return ScraperResult(
      ok: false,
      error: 'Error al conectar con Cineby',
      url: endpoint,
    );
  }

  // ─── BÚSQUEDA ─────────────────────────────────────────────────
  static Future<List<BuscadorItem>> search(String q) async {
    final query = q.trim();
    if (query.isEmpty) return [];

    final results = <BuscadorItem>[];
    final seenIds = <int>{};

    // 1. Si la consulta es un TMDB ID numérico
    final tmdbId = int.tryParse(query);
    if (tmdbId != null && tmdbId > 0) {
      for (final type in ['series', 'movie']) {
        try {
          final res = await http.get(
            Uri.parse('$baseApi/v2/content/details/$type/$tmdbId'),
            headers: _headers,
          ).timeout(_timeout);

          if (res.statusCode == 200) {
            final data = jsonDecode(res.body);
            if (data is Map && data['title'] != null) {
              final id = tmdbId;
              seenIds.add(id);
              final tType = type == 'series' ? 'tv' : 'movie';
              results.add(BuscadorItem(
                sitio: 'cineby',
                titulo: data['title'].toString(),
                tipo: tType,
                url: 'https://cineby.me/$tType/$id',
                imagen: data['poster']?.toString() ?? '',
                anio: data['year'] is int ? data['year'] as int : null,
                rating: (data['rating'] as num?)?.toDouble(),
                tmdbId: id,
              ));
              return results;
            }
          }
        } catch (_) {}
      }
    }

    // 2. Búsqueda por texto (y alternativas para búsquedas bilingües como "la ley y el orden" -> "Law & Order")
    final searchTerms = <String>[query];
    final qLower = query.toLowerCase();
    if (qLower.contains('ley') && qLower.contains('orden')) {
      searchTerms.add('Law & Order');
      searchTerms.add('Law');
    }

    for (final term in searchTerms) {
      try {
        final url = '$baseApi/v2/content/search?q=${Uri.encodeComponent(term)}';
        final res = await http.get(Uri.parse(url), headers: _headers).timeout(_timeout);
        if (res.statusCode >= 200 && res.statusCode < 300) {
          final data = jsonDecode(res.body);
          if (data is List) {
            for (final item in data) {
              if (item is! Map) continue;
              final rawId = item['id'];
              final id = rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '');
              if (id == null || seenIds.contains(id)) continue;
              seenIds.add(id);

              final title = item['title']?.toString() ?? 'Sin título';
              final typeStr = item['type']?.toString() == 'series' ? 'tv' : 'movie';
              final poster = item['poster']?.toString() ?? '';
              final year = item['year'] is int
                  ? item['year'] as int
                  : int.tryParse(item['year']?.toString() ?? '');
              final rating = (item['rating'] as num?)?.toDouble();

              results.add(BuscadorItem(
                sitio: 'cineby',
                titulo: title,
                tipo: typeStr,
                url: 'https://cineby.me/$typeStr/$id',
                imagen: poster,
                anio: year,
                rating: rating,
                tmdbId: id,
              ));
            }
          }
        }
      } catch (e) {
        debugPrint('[Cineby] Error en búsqueda "$term": $e');
      }
    }

    return results;
  }

  // ─── DETALLE ──────────────────────────────────────────────────
  static Future<DetalleContenido> fetchDetail({
    required String url,
    required String titulo,
    required String tipo,
  }) async {
    // Extraer tmdbId de la URL (ej: https://cineby.me/tv/106158 o https://cineby.me/movie/533535)
    final idMatch = RegExp(r'/(?:tv|series|movie)/(\d+)', caseSensitive: false).firstMatch(url);
    final tmdbId = idMatch != null ? int.tryParse(idMatch.group(1)!) : null;

    final isTv = tipo == 'tv' || tipo == 'series' || url.contains('/tv/') || url.contains('/series/');
    final apiType = isTv ? 'series' : 'movie';

    Map<String, dynamic>? metaData;
    if (tmdbId != null) {
      try {
        final res = await http.get(
          Uri.parse('$baseApi/v2/content/details/$apiType/$tmdbId'),
          headers: _headers,
        ).timeout(_timeout);
        if (res.statusCode == 200) {
          metaData = jsonDecode(res.body) as Map<String, dynamic>?;
        }
      } catch (_) {}
    }

    final realTitle = metaData?['title']?.toString() ?? titulo;
    final poster = metaData?['poster']?.toString();
    final backdrop = metaData?['backdrop']?.toString();
    final sinopsis = metaData?['description']?.toString();
    final year = metaData?['year']?.toString();
    final rating = (metaData?['rating'] as num?)?.toDouble();

    if (isTv && tmdbId != null) {
      // Extraer temporadas desde VidSrc metadata API
      final temporadas = await _fetchTvSeasons(tmdbId);
      return DetalleContenido(
        ok: true,
        servicio: 'cineby',
        titulo: realTitle,
        tipo: 'tv',
        tmdbId: tmdbId,
        anio: year,
        sinopsis: sinopsis,
        poster: poster,
        backdrop: backdrop,
        rating: rating,
        temporadas: temporadas,
      );
    } else {
      // Película: generar servidores directos de Cineby
      final servidores = <DetalleServidor>[];
      if (tmdbId != null) {
        servidores.addAll(await _resolveMovieServers(tmdbId));
      }

      return DetalleContenido(
        ok: true,
        servicio: 'cineby',
        titulo: realTitle,
        tipo: 'movie',
        tmdbId: tmdbId,
        anio: year,
        sinopsis: sinopsis,
        poster: poster,
        backdrop: backdrop,
        rating: rating,
        servidores: servidores,
      );
    }
  }

  static Future<List<DetalleTemporada>> _fetchTvSeasons(int tmdbId) async {
    final temporadas = <DetalleTemporada>[];
    try {
      final res = await http.get(
        Uri.parse('$vidsrcMetaApi?type=tv&tmdb=$tmdbId'),
        headers: {'User-Agent': 'Mozilla/5.0'},
      ).timeout(_timeout);

      if (res.statusCode == 200) {
        final json = jsonDecode(res.body);
        final data = json is Map ? json['data'] : null;
        final epsMap = data is Map ? data['eps'] : null;

        if (epsMap is Map) {
          final seasonKeys = epsMap.keys.map((k) => int.tryParse(k.toString()) ?? 0).where((k) => k > 0).toList()..sort();

          for (final sNum in seasonKeys) {
            final epList = epsMap[sNum.toString()];
            final episodios = <DetalleCapitulo>[];

            if (epList is List) {
              for (final epVal in epList) {
                final epNum = int.tryParse(epVal.toString()) ?? 1;
                episodios.add(DetalleCapitulo(
                  temporada: sNum,
                  numero: epNum,
                  titulo: 'Episodio $epNum',
                  url: 'https://cineby.me/tv/$tmdbId/$sNum/$epNum',
                ));
              }
            }

            episodios.sort((a, b) => a.numero.compareTo(b.numero));
            temporadas.add(DetalleTemporada(
              numero: sNum,
              nombre: 'Temporada $sNum',
              episodios: episodios,
            ));
          }
        }
      }
    } catch (e) {
      debugPrint('[Cineby] Error cargando temporadas VidSrc ($tmdbId): $e');
    }

    // Fallback: temporada 1 básica con 10 episodios si falló la API
    if (temporadas.isEmpty) {
      final fallbackEps = List.generate(
        10,
        (i) => DetalleCapitulo(
          temporada: 1,
          numero: i + 1,
          titulo: 'Episodio ${i + 1}',
          url: 'https://cineby.me/tv/$tmdbId/1/${i + 1}',
        ),
      );
      temporadas.add(DetalleTemporada(numero: 1, nombre: 'Temporada 1', episodios: fallbackEps));
    }

    return temporadas;
  }

  static Future<List<DetalleServidor>> _resolveMovieServers(int tmdbId) async {
    final list = <DetalleServidor>[];

    // 1. Resolver fuente directa mediante vs_src.php
    try {
      final vsUrl = '$embedBase/vs_src.php?type=movie&id=$tmdbId';
      final res = await http.get(
        Uri.parse(vsUrl),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
          'Referer': '$embedBase/embed/movie/$tmdbId',
        },
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data is Map && data['src'] != null) {
          final src = data['src'].toString();
          if (src.isNotEmpty) {
            list.add(DetalleServidor(
              nombre: 'Cineby · Stream VOS',
              url: src,
              idioma: 'subtitulado',
              calidad: '1080p',
            ));
          }
        }
      }
    } catch (_) {}

    // 2. Embed directo Cineby
    list.add(DetalleServidor(
      nombre: 'Cineby · Player HD',
      url: '$embedBase/embed/movie/$tmdbId',
      idioma: 'subtitulado',
      calidad: '1080p',
    ));

    return list;
  }

  // ─── SERVIDORES (FETCH_SERVERS) ───────────────────────────────
  static Future<List<DetalleServidor>> fetchServers({
    required String url,
    int? tmdbId,
    bool isMovie = true,
    int season = 1,
    int episode = 1,
  }) async {
    var id = tmdbId;
    var movie = isMovie;
    var s = season;
    var e = episode;

    // Intentar deducir de la URL si faltan parámetros
    if (id == null) {
      final m = RegExp(r'/(?:tv|series|movie)/(\d+)(?:/(\d+)/(\d+))?', caseSensitive: false).firstMatch(url);
      if (m != null) {
        id = int.tryParse(m.group(1)!);
        movie = !url.contains('/tv/') && !url.contains('/series/');
        if (m.group(2) != null) s = int.tryParse(m.group(2)!) ?? season;
        if (m.group(3) != null) e = int.tryParse(m.group(3)!) ?? episode;
      }
    }

    if (id == null) return [];

    final servers = <DetalleServidor>[];

    // Intentar resolver stream vs_src
    try {
      final typeStr = movie ? 'movie' : 'tv';
      final vsUrl = movie
          ? '$embedBase/vs_src.php?type=movie&id=$id'
          : '$embedBase/vs_src.php?type=tv&id=$id&season=$s&episode=$e';

      final res = await http.get(
        Uri.parse(vsUrl),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
          'Referer': movie
              ? '$embedBase/embed/movie/$id'
              : '$embedBase/embed/tv/$id/$s/$e',
        },
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data is Map && data['src'] != null) {
          final src = data['src'].toString();
          if (src.isNotEmpty) {
            servers.add(DetalleServidor(
              nombre: 'Cineby · Stream VOS',
              url: src,
              idioma: 'subtitulado',
              calidad: '1080p',
            ));
          }
        }
      }
    } catch (_) {}

    // Fallback: Embed general
    final embedUrl = movie
        ? '$embedBase/embed/movie/$id'
        : '$embedBase/embed/tv/$id/$s/$e';

    servers.add(DetalleServidor(
      nombre: 'Cineby · Player HD',
      url: embedUrl,
      idioma: 'subtitulado',
      calidad: '1080p',
    ));

    return servers;
  }

  // ─── STREAM PARA MAIN_FUENTES_SERVIDORES ──────────────────────
  static Stream<Map<String, dynamic>> scrapeStream({
    required int tmdbId,
    required bool isMovie,
    int season = 1,
    int episode = 1,
  }) async* {
    if (tmdbId <= 0) return;

    // 1. Obtener stream directo de vs_src
    try {
      final vsUrl = isMovie
          ? '$embedBase/vs_src.php?type=movie&id=$tmdbId'
          : '$embedBase/vs_src.php?type=tv&id=$tmdbId&season=$season&episode=$episode';

      final res = await http.get(
        Uri.parse(vsUrl),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
          'Referer': isMovie
              ? '$embedBase/embed/movie/$tmdbId'
              : '$embedBase/embed/tv/$tmdbId/$season/$episode',
        },
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data is Map && data['src'] != null) {
          final src = data['src'].toString();
          if (src.isNotEmpty) {
            yield {
              'servidor_nombre': 'Cineby · Stream VOS',
              'servidor_url': src,
              'calidad': '1080p',
              'idioma': 'en_US', // VOS / Subtitulado
              'estado': 'activo',
              'es_cineby': true,
            };
          }
        }
      }
    } catch (_) {}

    // 2. Yield embed player
    final embedUrl = isMovie
        ? '$embedBase/embed/movie/$tmdbId'
        : '$embedBase/embed/tv/$tmdbId/$season/$episode';

    yield {
      'servidor_nombre': 'Cineby · Player HD',
      'servidor_url': embedUrl,
      'calidad': '1080p',
      'idioma': 'en_US', // VOS / Subtitulado
      'estado': 'activo',
      'es_cineby': true,
    };
  }
}
