import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as parser;
import 'package:http/http.dart' as http;
import '../models/scraper/detalle_model.dart';
import 'base/base_home_scraper.dart';
import 'base/buscador.dart';

/// Scraper para AnimePahe (https://animepahe.ru)
/// Fuente global de anime en alta definición con subtítulos y audio en múltiples idiomas.
class AnimePaheScraper {
  static const String base = 'https://animepahe.ru';
  static const String userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';
  static const Duration timeout = Duration(seconds: 10);

  static const List<String> generos = [
    'Action',
    'Adventure',
    'Comedy',
    'Drama',
    'Fantasy',
    'Horror',
    'Mystery',
    'Romance',
    'Sci-Fi',
    'Slice of Life',
    'Sports',
    'Supernatural',
  ];

  static List<String> tiposDisponibles() => ['anime', 'airing', 'movies'];

  // ─── LISTADO (FETCH) ──────────────────────────────────────────
  static Future<ScraperResult> fetch({
    String? tipo,
    String? genero,
    bool populares = false,
    int page = 1,
  }) async {
    final url = '$base/api?m=airing&page=$page';

    try {
      final res = await http.get(Uri.parse(url), headers: {
        'User-Agent': userAgent,
      }).timeout(timeout);

      if (res.statusCode != 200) {
        return ScraperResult(
          ok: false,
          error: 'Error al conectar con AnimePahe (${res.statusCode})',
          url: url,
        );
      }

      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final data = json['data'] as List? ?? [];
      final totalPages = int.tryParse(json['last_page']?.toString() ?? '1') ?? 1;

      final items = <ScraperItem>[];
      for (final item in data) {
        if (item is Map) {
          final title = item['anime_title']?.toString() ?? item['title']?.toString() ?? 'Sin título';
          final session = item['anime_session']?.toString() ?? item['session']?.toString() ?? '';
          final snapshot = item['snapshot']?.toString() ?? '';
          final epNum = item['episode']?.toString() ?? '1';

          items.add(ScraperItem(
            sitio: 'animepahe',
            titulo: title,
            tipo: 'anime',
            url: session.isNotEmpty ? '$base/anime/$session' : '$base/play/$session/$epNum',
            poster: snapshot,
            rating: 8.5,
          ));
        }
      }

      return ScraperResult(
        ok: true,
        url: url,
        currentPage: page,
        hasNext: page < totalPages,
        items: items,
      );
    } catch (e) {
      return ScraperResult(ok: false, error: 'Excepción AnimePahe: $e', url: url);
    }
  }

  // ─── BÚSQUEDA ─────────────────────────────────────────────────
  static Future<List<BuscadorItem>> search(String q) async {
    final query = Uri.encodeComponent(q.trim());
    final url = '$base/api?m=search&q=$query';

    try {
      final res = await http.get(Uri.parse(url), headers: {
        'User-Agent': userAgent,
      }).timeout(timeout);

      if (res.statusCode != 200) return [];
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final data = json['data'] as List? ?? [];

      final results = <BuscadorItem>[];
      for (final item in data) {
        if (item is Map) {
          final title = item['title']?.toString() ?? 'Sin título';
          final session = item['session']?.toString() ?? '';
          final poster = item['poster']?.toString() ?? '';

          results.add(BuscadorItem(
            sitio: 'animepahe',
            titulo: title,
            tipo: 'anime',
            url: '$base/anime/$session',
            imagen: poster,
          ));
        }
      }

      return results;
    } catch (_) {
      return [];
    }
  }

  // ─── DETALLE Y TEMPORADAS ─────────────────────────────────────
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
          error: 'Error de conexión con AnimePahe (${res.statusCode})',
          servicio: 'animepahe',
          titulo: titulo,
          tipo: tipo,
        );
      }

      final doc = parser.parse(res.body);

      final sinopsis = doc.querySelector('.anime-synopsis, .synopsis, p')?.text.trim() ?? '';
      final posterEl = doc.querySelector('.anime-poster a, .poster img, .anime-poster img');
      var poster = posterEl?.attributes['href'] ?? posterEl?.attributes['src'] ?? '';
      if (poster.startsWith('//')) poster = 'https:$poster';

      final genres = doc.querySelectorAll('.anime-genre a, .genres a').map((e) => e.text.trim()).toList();

      final session = url.replaceAll(RegExp(r'/+$'), '').split('/').last;

      // Cargar episodios vía API de AnimePahe
      final capitulos = <DetalleCapitulo>[];
      try {
        final epApiUrl = '$base/api?m=release&id=$session&sort=episode_asc&page=1';
        final epRes = await http.get(Uri.parse(epApiUrl), headers: {'User-Agent': userAgent}).timeout(const Duration(seconds: 6));
        if (epRes.statusCode == 200) {
          final epJson = jsonDecode(epRes.body) as Map<String, dynamic>;
          final epData = epJson['data'] as List? ?? [];
          for (final ep in epData) {
            if (ep is Map) {
              final epNum = int.tryParse(ep['episode']?.toString() ?? '1') ?? 1;
              final epSession = ep['session']?.toString() ?? '';
              final snap = ep['snapshot']?.toString() ?? poster;

              capitulos.add(DetalleCapitulo(
                temporada: 1,
                numero: epNum,
                titulo: 'Episodio $epNum',
                url: '$base/play/$session/$epSession',
                imagen: snap,
              ));
            }
          }
        }
      } catch (_) {}

      // Fallback: Si la API falló, buscar episodios en el HTML
      if (capitulos.isEmpty) {
        final epLinks = doc.querySelectorAll('.episode-list a, .episode a, a[href*="/play/"]');
        int epIdx = 1;
        for (final a in epLinks) {
          final href = a.attributes['href'] ?? '';
          if (href.isEmpty) continue;
          final fullUrl = href.startsWith('http') ? href : '$base$href';
          capitulos.add(DetalleCapitulo(
            temporada: 1,
            numero: epIdx,
            titulo: 'Episodio $epIdx',
            url: fullUrl,
            imagen: poster,
          ));
          epIdx++;
        }
      }

      final temporadas = capitulos.isNotEmpty
          ? [DetalleTemporada(numero: 1, nombre: 'Temporada 1', episodios: capitulos)]
          : <DetalleTemporada>[];

      final firstEpUrl = capitulos.isNotEmpty ? capitulos.first.url : url;
      final servidores = await fetchServers(url: firstEpUrl);

      debugPrint('[AnimePahe] Episodios encontrados: ${capitulos.length}');
      debugPrint('[AnimePahe] Servidores encontrados: ${servidores.length}');

      return DetalleContenido(
        ok: true,
        servicio: 'animepahe',
        titulo: titulo,
        tipo: tipo,
        sinopsis: sinopsis,
        poster: poster,
        backdrop: poster,
        generos: genres,
        servidores: servidores,
        temporadas: temporadas,
      );
    } catch (e) {
      return DetalleContenido(
        ok: false,
        error: 'Excepción AnimePahe: $e',
        servicio: 'animepahe',
        titulo: titulo,
        tipo: tipo,
      );
    }
  }

  // ─── SERVIDORES ───────────────────────────────────────────────
  static Future<List<DetalleServidor>> fetchServers({
    required String url,
  }) async {
    try {
      final res = await http.get(Uri.parse(url), headers: {
        'User-Agent': userAgent,
      }).timeout(timeout);

      if (res.statusCode != 200) return [];

      final doc = parser.parse(res.body);
      final servers = <DetalleServidor>[];
      final seen = <String>{};

      // AnimePahe expone botones para descarga/embed (#pickDownload, .dropdown-item, kwik, etc.)
      final buttons = doc.querySelectorAll('#pickDownload a, .dropdown-menu a, #resolutionMenu button, a[data-src]');
      for (final btn in buttons) {
        final link = btn.attributes['href'] ?? btn.attributes['data-src'] ?? '';
        final text = btn.text.trim();
        if (link.isNotEmpty && link.startsWith('http') && !seen.contains(link)) {
          seen.add(link);
          final isSub = !text.toLowerCase().contains('dub');
          servers.add(DetalleServidor(
            nombre: 'AnimePahe · ${text.isNotEmpty ? text : "Server"}',
            url: link,
            idioma: isSub ? 'subtitulado' : 'latino',
            calidad: text.contains('1080') ? '1080p' : (text.contains('720') ? '720p' : 'HD'),
          ));
        }
      }

      // Si no encontró botones directos, extraer iframes de reproducción
      final iframes = doc.querySelectorAll('iframe');
      for (final ifr in iframes) {
        final src = ifr.attributes['src'] ?? '';
        if (src.isNotEmpty && !seen.contains(src) && !src.contains('recaptcha')) {
          final fullSrc = src.startsWith('//') ? 'https:$src' : src;
          seen.add(fullSrc);
          servers.add(DetalleServidor(
            nombre: 'AnimePahe · Stream Directo',
            url: fullSrc,
            idioma: 'subtitulado',
            calidad: 'HD',
          ));
        }
      }

      return servers;
    } catch (_) {
      return [];
    }
  }
}
