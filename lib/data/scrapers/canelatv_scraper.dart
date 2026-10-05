import 'dart:convert';
import 'package:collection/collection.dart';
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
    final id = item['id']?.toString() ?? '';
    if (id.isEmpty) return '';
    final ia = item['ia'];
    if (ia is List && ia.contains('0-7x10')) {
      return 'https://image-resizer-cloud-cdn.cms.api.canela.tv/image/$id/0-7x10.jpg';
    }
    if (ia is List && ia.contains('0-2x3')) {
      return 'https://image-resizer-cloud-cdn.cms.api.canela.tv/image/$id/0-2x3.jpg';
    }
    return 'https://image-resizer-cloud-cdn.cms.api.canela.tv/image/$id/0-16x9.jpg';
  }

  // ─── LISTADO (FETCH) ──────────────────────────────────────────
  static Future<ScraperResult> fetch({
    String? tipo,
    String? genero,
    bool populares = false,
    int page = 1,
  }) async {
    final term = (genero != null && genero.isNotEmpty) ? genero : 'novela';
    final cty = (tipo == 'peliculas' || tipo == 'movie') ? 'movie' : 'tvseries';
    final url =
        '$baseSearchApi?mode=detail&st=published&term=${Uri.encodeComponent(term)}&cty=$cty&pageNumber=$page&pageSize=24&reg=co&dt=web&client=canela-canela-web';

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
      final list = data is Map ? (data['data'] as List?) : null;

      if (list != null) {
        for (final r in list) {
          if (r is! Map) continue;
          final map = Map<String, dynamic>.from(r);
          final id = map['id']?.toString() ?? '';
          final slug = map['nu']?.toString() ?? map['slug']?.toString() ?? id;
          final title = _cleanTitle(map['lon'] ?? map['title'] ?? map['n']);
          if (title.isEmpty || id.isEmpty) continue;

          final poster = _extractPoster(map);
          final itemCty = map['cty']?.toString() ?? 'tvseries';
          final scraperTipo = itemCty.contains('movie') ? 'movie' : 'novel';

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
    final url =
        '$baseSearchApi?mode=detail&st=published&term=$query&cty=tvseries&pageNumber=1&pageSize=20&reg=co&dt=web&client=canela-canela-web';

    try {
      final res = await http.get(Uri.parse(url), headers: {
        'Accept': 'application/json',
        'User-Agent': userAgent,
      }).timeout(timeout);

      if (res.statusCode != 200) return [];
      final data = jsonDecode(res.body);
      final results = <BuscadorItem>[];
      final list = data is Map ? (data['data'] as List?) : null;

      if (list != null) {
        for (final r in list) {
          if (r is! Map) continue;
          final map = Map<String, dynamic>.from(r);
          final id = map['id']?.toString() ?? '';
          final slug = map['nu']?.toString() ?? map['slug']?.toString() ?? id;
          final title = _cleanTitle(map['lon'] ?? map['title'] ?? map['n']);
          if (title.isEmpty || id.isEmpty) continue;

          final poster = _extractPoster(map);
          final itemCty = map['cty']?.toString() ?? 'tvseries';
          final tipo = itemCty.contains('movie') ? 'movie' : 'novel';

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
    var id = uri.queryParameters['id'] ?? (url.split('/').last.split('?').first);

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
      // Si el id es un slug sin UUID y no vino parámetro id, resolverlo vía búsqueda
      if (!id.contains('-') && uri.queryParameters['id'] == null) {
        final searchItems = await search(titulo.isNotEmpty ? titulo : id);
        final found = searchItems.firstWhereOrNull((e) => e.url.contains(id));
        if (found != null) {
          final fUri = Uri.parse(found.url);
          id = fUri.queryParameters['id'] ?? id;
        }
      }

      // 1. Obtener temporadas
      final seasonsUrl =
          '$baseDataStore/content/series/$id/seasons?pageNumber=1&pageSize=30&reg=co&dt=web&client=canela-canela-web';
      final sRes = await http.get(Uri.parse(seasonsUrl), headers: {
        'Accept': 'application/json',
        'User-Agent': userAgent,
      }).timeout(timeout);

      final temporadas = <DetalleTemporada>[];
      final capitulos = <DetalleCapitulo>[];
      final poster =
          'https://image-resizer-cloud-cdn.cms.api.canela.tv/image/$id/0-7x10.jpg';
      final backdrop =
          'https://image-resizer-cloud-cdn.cms.api.canela.tv/image/$id/0-16x9.jpg';
      String sinopsis = '';

      if (sRes.statusCode == 200) {
        final sData = jsonDecode(sRes.body);
        final sList = sData is Map ? (sData['data'] as List?) : null;

        if (sList != null && sList.isNotEmpty) {
          for (int sIdx = 0; sIdx < sList.length; sIdx++) {
            final sItem = sList[sIdx];
            if (sItem is! Map) continue;
            final seasonId = sItem['id']?.toString() ?? '';
            final snum = sItem['snum'] ?? (sIdx + 1);
            final sName = sItem['title']?.toString() ?? 'Temporada $snum';

            // Obtener episodios de esta temporada
            final epUrl =
                '$baseDataStore/content/series/$id/episodes?seasonId=$seasonId&pageNumber=1&pageSize=100&sortBy=epz&sortOrder=asc&reg=co&dt=web&client=canela-canela-web';
            final epRes = await http.get(Uri.parse(epUrl), headers: {
              'Accept': 'application/json',
              'User-Agent': userAgent,
            }).timeout(timeout);

            final tempCaps = <DetalleCapitulo>[];
            if (epRes.statusCode == 200) {
              final epData = jsonDecode(epRes.body);
              final epList = epData is Map ? (epData['data'] as List?) : null;
              if (epList != null) {
                for (int eIdx = 0; eIdx < epList.length; eIdx++) {
                  final ep = epList[eIdx];
                  if (ep is! Map) continue;
                  final epId = ep['id']?.toString() ?? '';
                  final epSlug =
                      (ep['nu'] ?? ep['cnu'])?.toString() ?? epId;
                  final epTitle = _cleanTitle(ep['lon'] ?? ep['title']);
                  final epNum = ep['epnum'] is int
                      ? ep['epnum'] as int
                      : (int.tryParse('${ep['epnum'] ?? ep['epz']}') ??
                          (eIdx + 1));
                  final epPoster =
                      'https://image-resizer-cloud-cdn.cms.api.canela.tv/image/$epId/0-16x9.jpg';

                  final cap = DetalleCapitulo(
                    temporada: snum is int
                        ? snum
                        : (int.tryParse('$snum') ?? (sIdx + 1)),
                    numero: epNum,
                    titulo: epTitle.isNotEmpty ? epTitle : 'Capítulo $epNum',
                    url: 'https://canela.tv/play/$epSlug?id=$epId&series=$id',
                    imagen: epPoster,
                  );
                  tempCaps.add(cap);
                  capitulos.add(cap);
                }
              }
            }

            if (tempCaps.isNotEmpty) {
              temporadas.add(DetalleTemporada(
                numero: snum is int
                    ? snum
                    : (int.tryParse('$snum') ?? (sIdx + 1)),
                nombre: sName,
                episodios: tempCaps,
              ));
            }
          }
        }
      }

      final firstEpUrl = capitulos.isNotEmpty ? capitulos.first.url : url;
      final servidores = await fetchServers(url: firstEpUrl);

      return DetalleContenido(
        ok: true,
        servicio: 'canelatv',
        titulo: titulo,
        tipo: tipo,
        sinopsis: sinopsis,
        poster: poster,
        backdrop: backdrop,
        generos: const ['Telenovela', 'Drama', 'Latino'],
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
    try {
      final uri = Uri.parse(url);
      final slug = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : '';
      final id = uri.queryParameters['id'] ?? slug;
      final targetContentId = slug.isNotEmpty ? slug : id;

      if (targetContentId.isNotEmpty) {
        final streamUrl = await CanelaService.getStreamUrl(
          contentId: targetContentId,
          catalogType: 'tvepisode',
        );
        if (streamUrl != null && streamUrl.isNotEmpty) {
          servers.add(DetalleServidor(
            nombre: 'Canela.TV · Stream HD Oficial',
            url: streamUrl,
            idioma: 'latino',
            calidad: '1080p',
          ));
          return servers;
        }
      }
    } catch (_) {}

    // Fallback
    servers.add(DetalleServidor(
      nombre: 'Canela.TV · Stream HD 1080p',
      url: url,
      idioma: 'latino',
      calidad: '1080p',
    ));
    return servers;
  }
}
