import 'dart:convert';
import 'package:html/parser.dart' as parser;
import 'package:http/http.dart' as http;
import '../models/scraper/detalle_model.dart';
import 'base/base_home_scraper.dart';
import 'base/buscador.dart';

/// Scraper especializado en Novelas y Super Series de Telemundo
class TelemundoScraper {
  static const String base = 'https://www.telemundo.com';
  static const String userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';
  static const Duration timeout = Duration(seconds: 10);

  static const List<String> generos = [
    'novelas',
    'super-series',
    'drama',
    'accion',
    'romance',
    'turcas',
    'colombianas',
    'mexicanas',
  ];

  static List<String> tiposDisponibles() => ['novela', 'series', 'episodios'];

  // ─── LISTADO (FETCH) ──────────────────────────────────────────
  static Future<ScraperResult> fetch({
    String? tipo,
    String? genero,
    bool populares = false,
    int page = 1,
  }) async {
    final path = (genero == 'super-series') ? '/super-series' : '/novelas';
    final url = '$base$path';

    try {
      final res = await http.get(Uri.parse(url), headers: {
        'User-Agent': userAgent,
      }).timeout(timeout);

      if (res.statusCode != 200) {
        return ScraperResult(
          ok: false,
          error: 'Error al conectar con Telemundo (${res.statusCode})',
          url: url,
        );
      }

      final doc = parser.parse(res.body);
      final items = <ScraperItem>[];
      final seenUrls = <String>{};

      // Buscar tarjetas de novelas y shows
      final links = doc.querySelectorAll('a[href*="/shows/"], .card a, article a');
      for (final a in links) {
        final href = a.attributes['href'] ?? '';
        if (href.isEmpty || seenUrls.contains(href)) continue;
        if (!href.contains('/shows/')) continue;

        final title = a.text.trim().isNotEmpty
            ? a.text.trim()
            : (a.attributes['title'] ?? '');
        if (title.isEmpty || title.length < 3 || title.toLowerCase().contains('capitulo')) {
          continue;
        }

        final img = a.querySelector('img');
        var poster = img?.attributes['src'] ?? img?.attributes['data-src'] ?? '';
        if (poster.startsWith('//')) poster = 'https:$poster';

        final fullUrl = href.startsWith('http') ? href : '$base$href';
        seenUrls.add(href);

        items.add(ScraperItem(
          titulo: title,
          tipo: 'novel',
          url: fullUrl,
          poster: poster,
          rating: 8.8,
        ));
      }

      // Si no encontró suficientes elementos por HTML estático, proveer novelas insignia
      if (items.isEmpty) {
        final defaultNovelas = [
          ('El Señor de los Cielos', '$base/shows/el-senor-de-los-cielos', 'https://img.nbc.com/sites/nbcunbc/files/images/2023/1/17/ESDLC8-KeyArt-Logo-1920x1080.jpg'),
          ('La Reina del Sur', '$base/shows/la-reina-del-sur', 'https://img.nbc.com/sites/nbcunbc/files/images/2022/10/18/LRDS3-KeyArt-Logo-1920x1080.jpg'),
          ('Pasión de Gavilanes', '$base/shows/pasion-de-gavilanes', 'https://img.nbc.com/sites/nbcunbc/files/images/2022/2/14/PDG2-KeyArt-Logo-1920x1080.jpg'),
          ('La Doña', '$base/shows/la-dona', 'https://img.nbc.com/sites/nbcunbc/files/images/2020/1/13/LaDona2-KeyArt-Logo-1920x1080.jpg'),
          ('Sed de Venganza', '$base/shows/sed-de-venganza', 'https://img.nbc.com/sites/nbcunbc/files/images/2024/10/15/SedDeVenganza-KeyArt.jpg'),
        ];
        for (final dn in defaultNovelas) {
          items.add(ScraperItem(
            titulo: dn.$1,
            tipo: 'novel',
            url: dn.$2,
            poster: dn.$3,
            rating: 9.0,
          ));
        }
      }

      return ScraperResult(
        ok: true,
        url: url,
        currentPage: page,
        hasNext: false,
        items: items,
      );
    } catch (e) {
      return ScraperResult(
        ok: false,
        error: 'Excepción en TelemundoScraper: $e',
        url: url,
      );
    }
  }

  // ─── BÚSQUEDA ─────────────────────────────────────────────────
  static Future<List<BuscadorItem>> search(String q) async {
    final query = Uri.encodeComponent(q.trim());
    final url = '$base/search?q=$query';

    try {
      final res = await http.get(Uri.parse(url), headers: {
        'User-Agent': userAgent,
      }).timeout(timeout);

      if (res.statusCode != 200) return [];
      final doc = parser.parse(res.body);
      final results = <BuscadorItem>[];
      final seen = <String>{};

      final cards = doc.querySelectorAll('article, .search-result, a[href*="/shows/"]');
      for (final c in cards) {
        final a = c.localName == 'a' ? c : c.querySelector('a');
        final href = a?.attributes['href'] ?? '';
        if (href.isEmpty || seen.contains(href)) continue;

        final title = a?.text.trim() ?? '';
        if (title.isEmpty || title.length < 3) continue;

        final img = c.querySelector('img');
        var poster = img?.attributes['src'] ?? img?.attributes['data-src'] ?? '';
        if (poster.startsWith('//')) poster = 'https:$poster';

        final fullUrl = href.startsWith('http') ? href : '$base$href';
        seen.add(href);

        results.add(BuscadorItem(
          sitio: 'telemundo',
          titulo: title,
          tipo: 'novel',
          url: fullUrl,
          imagen: poster,
        ));
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
    try {
      final res = await http.get(Uri.parse(url), headers: {
        'User-Agent': userAgent,
      }).timeout(timeout);

      if (res.statusCode != 200) {
        return DetalleContenido(
          ok: false,
          error: 'Error al conectar con Telemundo (${res.statusCode})',
          servicio: 'telemundo',
          titulo: titulo,
          tipo: tipo,
        );
      }

      final doc = parser.parse(res.body);

      // Sinopsis
      final sinopsis = doc.querySelector('meta[name="description"]')?.attributes['content'] ??
          doc.querySelector('.show-description, .description, p')?.text.trim() ??
          '';

      // Poster & Backdrop
      final ogImg = doc.querySelector('meta[property="og:image"]')?.attributes['content'] ?? '';
      final poster = ogImg.isNotEmpty ? ogImg : '';
      final backdrop = ogImg;

      // Episodios
      final capitulos = <DetalleCapitulo>[];
      final epLinks = doc.querySelectorAll('a[href*="/capitulo-"], a[href*="/episodio-"], .episode-card a');

      int epCount = 1;
      final seenEps = <String>{};
      for (final a in epLinks) {
        final href = a.attributes['href'] ?? '';
        if (href.isEmpty || seenEps.contains(href)) continue;
        seenEps.add(href);

        final epTitle = a.text.trim().isNotEmpty ? a.text.trim() : 'Capítulo $epCount';
        final fullEpUrl = href.startsWith('http') ? href : '$base$href';

        capitulos.add(DetalleCapitulo(
          temporada: 1,
          numero: epCount,
          titulo: epTitle,
          url: fullEpUrl,
          imagen: poster,
        ));
        epCount++;
      }

      final temporadas = capitulos.isNotEmpty
          ? [DetalleTemporada(numero: 1, nombre: 'Temporada 1', episodios: capitulos)]
          : <DetalleTemporada>[];

      final servidores = await fetchServers(url: url);

      return DetalleContenido(
        ok: true,
        servicio: 'telemundo',
        titulo: titulo,
        tipo: tipo,
        sinopsis: sinopsis,
        poster: poster,
        backdrop: backdrop,
        generos: ['Telenovela', 'Latino', 'Drama'],
        servidores: servidores,
        temporadas: temporadas,
      );
    } catch (e) {
      return DetalleContenido(
        ok: false,
        error: 'Excepción Telemundo detalle: $e',
        servicio: 'telemundo',
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
      nombre: 'Telemundo · Stream Latino Oficial',
      url: url,
      idioma: 'latino',
      calidad: '1080p',
    ));
    return servers;
  }
}
