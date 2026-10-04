import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/scraper/detalle_model.dart';
import 'base/base_home_scraper.dart';
import 'base/buscador.dart';
import '../extractors/providers/canela_extractor.dart';

/// Scraper especializado en Telenovelas y Series de Canela.TV
class CanelaTVScraper {
  static const String baseSearchApi = 'https://search-cdn.cms.api.canela.tv/content/search';
  static const String baseDataStore = 'https://data-store-cdn.cms.api.canela.tv';
  static const String userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';
  static const Duration timeout = Duration(seconds: 10);

  static const List<String> generos = [
    'novelas',
    'turcas',
    'drama',
    'romance',
    'colombianas',
    'mexicanas',
    'clasicos',
    'comedia',
  ];

  static List<String> tiposDisponibles() => ['novela', 'series', 'peliculas'];

  static String _cleanTitle(dynamic titles) {
    if (titles is List && titles.isNotEmpty) {
      for (final t in titles) {
        if (t is Map && t['lang'] == 'es-MX') {
          return t['n']?.toString() ?? '';
        }
      }
      final first = titles.first;
      if (first is Map) return first['n']?.toString() ?? '';
      return first.toString();
    }
    return titles?.toString() ?? '';
  }

  static String _extractPoster(Map<String, dynamic> item) {
    final ia = item['ia'];
    final id = item['id']?.toString() ?? '';
    if (id.isEmpty) return '';

    if (ia is List && ia.contains('0-2x3')) {
      return '$baseDataStore/$id/0-2x3.jpg';
    } else if (ia is List && ia.contains('0-16x9')) {
      return '$baseDataStore/$id/0-16x9.jpg';
    }
    return '$baseDataStore/$id/0-2x3.jpg';
  }

  // ─── LISTADO (FETCH) ──────────────────────────────────────────
  static Future<ScraperResult> fetch({
    String? tipo,
    String? genero,
    bool populares = false,
    int page = 1,
  }) async {
    final start = (page - 1) * 24 + 1;
    final term = (genero != null && genero.isNotEmpty)
        ? genero
        : (populares ? 'novelas' : 'novelas');

    final url = '$baseSearchApi?term=${Uri.encodeComponent(term)}&rows=24&start=$start';

    try {
      final res = await http.get(Uri.parse(url), headers: {
        'Accept': 'application/json',
        'User-Agent': userAgent,
      }).timeout(timeout);

      if (res.statusCode != 200) {
        return ScraperResult(
          ok: false,
          error: 'Error al conectar con Canela.TV (${res.statusCode})',
          url: url,
        );
      }

      final data = jsonDecode(res.body);
      final items = <ScraperItem>[];

      if (data is Map && data['results'] is List) {
        for (final r in data['results']) {
          if (r is! Map) continue;
          final map = Map<String, dynamic>.from(r);
          final id = map['id']?.toString() ?? '';
          final slug = map['nu']?.toString() ?? map['slug']?.toString() ?? id;
          final title = _cleanTitle(map['title'] ?? map['lon'] ?? map['n']);
          if (title.isEmpty || id.isEmpty) continue;

          final poster = _extractPoster(map);
          final cty = map['cty']?.toString() ?? map['type']?.toString() ?? 'series';
          final scraperTipo = cty.contains('movie') ? 'movie' : 'novel';

          items.add(ScraperItem(
            titulo: title,
            tipo: scraperTipo,
            url: 'https://canela.tv/series/$slug?id=$id',
            poster: poster,
            rating: 8.5,
          ));
        }
      }

      return ScraperResult(
        ok: true,
        url: url,
        currentPage: page,
        hasNext: items.length >= 20,
        items: items,
      );
    } catch (e) {
      return ScraperResult(
        ok: false,
        error: 'Excepción en CanelaTVScraper: $e',
        url: url,
      );
    }
  }

  // ─── BÚSQUEDA ─────────────────────────────────────────────────
  static Future<List<BuscadorItem>> search(String q) async {
    final query = Uri.encodeComponent(q.trim());
    final url = '$baseSearchApi?term=$query&rows=20';

    try {
      final res = await http.get(Uri.parse(url), headers: {
        'Accept': 'application/json',
        'User-Agent': userAgent,
      }).timeout(timeout);

      if (res.statusCode != 200) return [];
      final data = jsonDecode(res.body);
      final results = <BuscadorItem>[];

      if (data is Map && data['results'] is List) {
        for (final r in data['results']) {
          if (r is! Map) continue;
          final map = Map<String, dynamic>.from(r);
          final id = map['id']?.toString() ?? '';
          final slug = map['nu']?.toString() ?? map['slug']?.toString() ?? id;
          final title = _cleanTitle(map['title'] ?? map['lon'] ?? map['n']);
          if (title.isEmpty || id.isEmpty) continue;

          final poster = _extractPoster(map);
          final cty = map['cty']?.toString() ?? map['type']?.toString() ?? 'series';
          final tipo = cty.contains('movie') ? 'movie' : 'novel';

          results.add(BuscadorItem(
            sitio: 'canelatv',
            titulo: title,
            tipo: tipo,
            url: 'https://canela.tv/series/$slug?id=$id',
            imagen: poster,
          ));
        }
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
    String tipo = 'novel',
  }) async {
    final uri = Uri.parse(url);
    final id = uri.queryParameters['id'] ?? (url.split('/').last.split('?').first);

    if (id.isEmpty) {
      return DetalleContenido(
        ok: false,
        error: 'ID de contenido no válido para Canela.TV',
        servicio: 'canelatv',
        titulo: titulo,
        tipo: tipo,
      );
    }

    try {
      final metaUrl = '$baseDataStore/$id.json';
      final res = await http.get(Uri.parse(metaUrl), headers: {
        'Accept': 'application/json',
        'User-Agent': userAgent,
      }).timeout(timeout);

      if (res.statusCode != 200) {
        return DetalleContenido(
          ok: false,
          error: 'Error al obtener detalle de Canela.TV (${res.statusCode})',
          servicio: 'canelatv',
          titulo: titulo,
          tipo: tipo,
        );
      }

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final title = _cleanTitle(data['lon'] ?? data['title']) ?? titulo;

      // Sinopsis
      var sinopsis = '';
      if (data['lod'] is List && (data['lod'] as List).isNotEmpty) {
        for (final d in data['lod']) {
          if (d is Map && d['lang'] == 'es-MX') {
            sinopsis = d['d']?.toString() ?? '';
            break;
          }
        }
        if (sinopsis.isEmpty && data['lod'][0] is Map) {
          sinopsis = data['lod'][0]['d']?.toString() ?? '';
        }
      }

      // Póster y backdrop
      final poster = _extractPoster(data);
      final backdrop = '$baseDataStore/$id/0-16x9.jpg';

      // Géneros
      final genres = <String>['Telenovela', 'Drama', 'Latino'];

      // Episodios / Temporadas
      final temporadas = <DetalleTemporada>[];
      final capitulos = <DetalleCapitulo>[];

      final seasonsData = data['seasons'] ?? data['s'];
      if (seasonsData is List && seasonsData.isNotEmpty) {
        for (int sIdx = 0; sIdx < seasonsData.length; sIdx++) {
          final s = seasonsData[sIdx];
          if (s is! Map) continue;
          final epList = s['episodes'] ?? s['e'];
          final tempCaps = <DetalleCapitulo>[];

          if (epList is List) {
            for (int eIdx = 0; eIdx < epList.length; eIdx++) {
              final ep = epList[eIdx];
              if (ep is! Map) continue;
              final epTitle = _cleanTitle(ep['lon'] ?? ep['title']) ?? 'Episodio ${eIdx + 1}';
              final epId = ep['id']?.toString() ?? '${sIdx + 1}_${eIdx + 1}';

              final cap = DetalleCapitulo(
                temporada: sIdx + 1,
                numero: eIdx + 1,
                titulo: epTitle,
                url: 'https://canela.tv/play/$epId?series=$id',
                imagen: '$baseDataStore/$epId/0-16x9.jpg',
              );
              tempCaps.add(cap);
              capitulos.add(cap);
            }
          }

          if (tempCaps.isNotEmpty) {
            temporadas.add(DetalleTemporada(
              numero: sIdx + 1,
              nombre: 'Temporada ${sIdx + 1}',
              episodios: tempCaps,
            ));
          }
        }
      }

      if (temporadas.isEmpty && capitulos.isNotEmpty) {
        temporadas.add(DetalleTemporada(
          numero: 1,
          nombre: 'Temporada 1',
          episodios: capitulos,
        ));
      }

      // Servidores
      final servidores = await fetchServers(url: url);

      return DetalleContenido(
        ok: true,
        servicio: 'canelatv',
        titulo: title.isNotEmpty ? title : titulo,
        tipo: tipo,
        sinopsis: sinopsis,
        poster: poster,
        backdrop: backdrop,
        generos: genres,
        servidores: servidores,
        temporadas: temporadas,
      );
    } catch (e) {
      return DetalleContenido(
        ok: false,
        error: 'Excepción CanelaTV detalle: $e',
        servicio: 'canelatv',
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
    final servers = <DetalleServidor>[];
    servers.add(DetalleServidor(
      nombre: 'Canela.TV · Stream HD 1080p',
      url: url,
      idioma: 'latino',
      calidad: '1080p',
    ));
    return servers;
  }
}
