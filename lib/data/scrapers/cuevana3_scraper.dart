import 'dart:async';
import 'dart:convert';
import 'package:html/parser.dart' as parser;
import 'package:http/http.dart' as http;
import '../../core/services/source_health_service.dart';
import '../models/scraper/detalle_model.dart';
import 'base/base_home_scraper.dart';

/// Scraper dedicado para Cuevana3 (WAVE 12.17)
class Cuevana3Scraper {
  static const String sourceId = 'cuevana3';
  static const List<String> mirrors = [
    'https://wv3.cuevana3.eu',
    'https://cuevana3.ch',
    'https://ww3.cuevana3.me',
  ];

  static const String userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';
  static const Duration timeout = Duration(seconds: 8);

  static Future<http.Response?> _request(String path) async {
    for (final base in mirrors) {
      final sw = Stopwatch()..start();
      try {
        final url = path.startsWith('http') ? path : '$base$path';
        final res = await http.get(Uri.parse(url), headers: {
          'User-Agent': userAgent,
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        }).timeout(timeout);

        sw.stop();
        if (res.statusCode == 200) {
          SourceHealthService.instance.recordSuccess(sourceId, sw.elapsedMilliseconds);
          return res;
        }
      } catch (_) {
        sw.stop();
      }
    }
    SourceHealthService.instance.recordFailure(sourceId, 'Timeout o error en mirrors');
    return null;
  }

  // ─── FETCH (LISTADO) ───────────────────────────────────────────────────────
  static Future<ScraperResult> fetch({
    String? tipo,
    String? genero,
    int page = 1,
  }) async {
    final isTv = tipo == 'tv' || tipo == 'series' || tipo == 'serie';
    final path = isTv ? '/series' : '/peliculas';

    final res = await _request(path);
    if (res == null) {
      return ScraperResult(ok: false, error: 'Sin respuesta de Cuevana3');
    }

    try {
      final doc = parser.parse(res.body);
      final items = <ScraperItem>[];
      final cards = doc.querySelectorAll('article.item-movies, .film-poster, .card-movie, div.TPost');

      for (final c in cards) {
        final aTag = c.querySelector('a');
        final link = aTag?.attributes['href'] ?? '';
        final title = c.querySelector('.title, .entry-title, h2, h3')?.text.trim() ??
            aTag?.attributes['title'] ??
            '';
        final img = c.querySelector('img')?.attributes['src'] ??
            c.querySelector('img')?.attributes['data-src'] ??
            '';
        final yearText = c.querySelector('.year, .date')?.text.trim();
        final year = int.tryParse(yearText ?? '');

        if (title.isNotEmpty && link.isNotEmpty) {
          items.add(ScraperItem(
            sitio: sourceId,
            titulo: title,
            tipo: isTv ? 'tv' : 'movie',
            url: link.startsWith('http') ? link : '${mirrors.first}$link',
            poster: img.startsWith('http') ? img : (img.isNotEmpty ? '${mirrors.first}$img' : ''),
            year: year,
          ));
        }
      }

      return ScraperResult(
        ok: items.isNotEmpty,
        items: items,
        currentPage: page,
        hasNext: items.length >= 10,
      );
    } catch (e) {
      return ScraperResult(ok: false, error: 'Error parseando Cuevana3: $e');
    }
  }

  // ─── SEARCH (BÚSQUEDA) ─────────────────────────────────────────────────────
  static Future<List<ScraperItem>> search(String query) async {
    final q = Uri.encodeComponent(query.trim());
    final res = await _request('/inicio?s=$q');
    if (res == null) return [];

    try {
      final doc = parser.parse(res.body);
      final items = <ScraperItem>[];
      final cards = doc.querySelectorAll('article.item-movies, .card-movie, div.TPost, div.film-poster');

      for (final c in cards) {
        final aTag = c.querySelector('a');
        final link = aTag?.attributes['href'] ?? '';
        final title = c.querySelector('.title, .entry-title, h2, h3')?.text.trim() ??
            aTag?.attributes['title'] ??
            '';
        final img = c.querySelector('img')?.attributes['src'] ??
            c.querySelector('img')?.attributes['data-src'] ??
            '';
        final yearText = c.querySelector('.year, .date')?.text.trim();
        final year = int.tryParse(yearText ?? '');
        final isTv = link.contains('/serie') || link.contains('/series');

        if (title.isNotEmpty && link.isNotEmpty) {
          items.add(ScraperItem(
            sitio: sourceId,
            titulo: title,
            tipo: isTv ? 'tv' : 'movie',
            url: link.startsWith('http') ? link : '${mirrors.first}$link',
            poster: img.startsWith('http') ? img : (img.isNotEmpty ? '${mirrors.first}$img' : ''),
            year: year,
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
        error: 'No se pudo cargar detalle de Cuevana3',
        servicio: sourceId,
        titulo: titulo,
        tipo: tipo,
      );
    }

    try {
      final doc = parser.parse(res.body);
      final poster = doc.querySelector('.poster img, div.Image img')?.attributes['src'] ?? '';
      final sinopsis = doc.querySelector('.overview, .entry-content, .sinopsis, p.text')?.text.trim();
      final yearText = doc.querySelector('.year, .date')?.text.trim();
      final isMovie = tipo == 'movie' || !url.contains('/serie');

      final temporadas = <DetalleTemporada>[];
      final capitulos = <DetalleCapitulo>[];

      // Parsear capítulos si es serie
      final epLinks = doc.querySelectorAll('.episodes a, ul.episodes-list a, .list-episodes a, div.TPTblCont a');
      if (epLinks.isNotEmpty) {
        for (int i = 0; i < epLinks.length; i++) {
          final el = epLinks[i];
          final epHref = el.attributes['href'] ?? '';
          final epTitle = el.text.trim();
          if (epHref.isNotEmpty) {
            capitulos.add(DetalleCapitulo(
              temporada: 1,
              numero: i + 1,
              titulo: epTitle.isNotEmpty ? epTitle : 'Capítulo ${i + 1}',
              url: epHref.startsWith('http') ? epHref : '${mirrors.first}$epHref',
            ));
          }
        }
        temporadas.add(DetalleTemporada(
          numero: 1,
          nombre: 'Temporada 1',
          episodios: capitulos,
        ));
      }

      final servers = await fetchServers(url: url, html: res.body);

      return DetalleContenido(
        ok: true,
        servicio: sourceId,
        titulo: titulo,
        tipo: isMovie ? 'movie' : 'tv',
        sinopsis: sinopsis,
        poster: poster.startsWith('http') ? poster : '',
        anio: yearText,
        generos: const ['Películas', 'Estreno', 'Latino'],
        servidores: servers,
        temporadas: temporadas,
      );
    } catch (e) {
      return DetalleContenido(
        ok: false,
        error: 'Error parseando detalle: $e',
        servicio: sourceId,
        titulo: titulo,
        tipo: tipo,
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
      // 1. Extraer Next.js __NEXT_DATA__ JSON si está presente
      final nextDataMatch = RegExp(r'<script id="__NEXT_DATA__" type="application/json">(.*?)</script>').firstMatch(body);
      if (nextDataMatch != null) {
        final jsonStr = nextDataMatch.group(1);
        if (jsonStr != null) {
          final data = jsonDecode(jsonStr);
          final pageProps = data['props']?['pageProps'];
          final videos = pageProps?['thisMovie']?['videos'] ?? pageProps?['episode']?['videos'];
          if (videos is Map) {
            for (final langEntry in videos.entries) {
              final langKey = langEntry.key.toString().toLowerCase();
              final vList = langEntry.value;
              if (vList is List) {
                for (final v in vList) {
                  if (v is Map) {
                    final locker = (v['cyberlocker'] ?? 'Stream').toString();
                    final vUrl = (v['result'] ?? v['url'] ?? '').toString();
                    if (vUrl.isNotEmpty) {
                      servers.add(DetalleServidor(
                        nombre: 'Cuevana3 · $locker',
                        url: vUrl,
                        idioma: langKey.contains('lat') ? 'latino' : (langKey.contains('cast') ? 'castellano' : 'subtitulado'),
                        calidad: 'HD',
                      ));
                    }
                  }
                }
              }
            }
          }
        }
      }

      // 2. Extraer iframes directos del HTML
      final doc = parser.parse(body);
      final iframes = doc.querySelectorAll('iframe[src], [data-server], [data-url], li.opt');
      for (final el in iframes) {
        final sUrl = el.attributes['data-src'] ??
            el.attributes['data-server'] ??
            el.attributes['data-url'] ??
            el.attributes['src'] ??
            '';
        if (sUrl.isEmpty) continue;

        String name = 'Cuevana3';
        if (sUrl.contains('streamwish')) name = 'Streamwish';
        if (sUrl.contains('vidhide')) name = 'VidHide';
        if (sUrl.contains('voe')) name = 'VOE';
        if (sUrl.contains('filelions')) name = 'Filelions';
        if (sUrl.contains('dood')) name = 'Doodstream';

        if (!servers.any((s) => s.url == sUrl)) {
          servers.add(DetalleServidor(
            nombre: 'Cuevana3 · $name',
            url: sUrl.startsWith('//') ? 'https:$sUrl' : sUrl,
            idioma: 'latino',
            calidad: '1080p',
          ));
        }
      }
    } catch (_) {}

    return servers;
  }
}
