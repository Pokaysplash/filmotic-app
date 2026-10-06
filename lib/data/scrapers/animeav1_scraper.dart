import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as parser;
import 'package:http/http.dart' as http;
import '../models/scraper/detalle_model.dart';
import 'base/base_home_scraper.dart';
import 'base/buscador.dart';

/// Scraper para AnimeAV1 (https://animeav1.com)
class AnimeAV1Scraper {
  static const String base = 'https://animeav1.com';
  static const String userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';
  static const Duration timeout = Duration(seconds: 10);

  static const List<String> generos = [
    'accion',
    'aventura',
    'comedia',
    'drama',
    'fantasia',
    'romance',
    'shounen',
    'sobrenatural',
  ];

  static List<String> tiposDisponibles() => ['anime', 'emision', 'populares', 'peliculas'];

  // ─── LISTADO (FETCH) ──────────────────────────────────────────
  static Future<ScraperResult> fetch({
    String? tipo,
    String? genero,
    bool populares = false,
    int page = 1,
  }) async {
    final url = '$base/animes?page=$page';

    try {
      final res = await http.get(Uri.parse(url), headers: {'User-Agent': userAgent}).timeout(timeout);
      if (res.statusCode != 200) {
        return ScraperResult(ok: false, error: 'Error al conectar con AnimeAV1 (${res.statusCode})', url: url);
      }

      final doc = parser.parse(res.body);
      final items = <ScraperItem>[];
      final elements = doc.querySelectorAll('.anime-card, .card, article.anime, .grid article');

      for (final el in elements) {
        final aTag = el.querySelector('a');
        final href = aTag?.attributes['href'] ?? '';
        if (href.isEmpty) continue;

        final imgTag = el.querySelector('img');
        var poster = imgTag?.attributes['src'] ?? imgTag?.attributes['data-src'] ?? '';
        if (poster.startsWith('//')) poster = 'https:$poster';

        final title = el.querySelector('.title, h3, h2')?.text.trim() ?? 'Sin título';

        items.add(ScraperItem(
          sitio: 'animeav1',
          titulo: title,
          tipo: 'anime',
          url: href.startsWith('http') ? href : '$base$href',
          poster: poster,
          rating: 8.5,
        ));
      }

      return ScraperResult(
        ok: true,
        url: url,
        currentPage: page,
        hasNext: items.length >= 10,
        items: items,
      );
    } catch (e) {
      return ScraperResult(ok: false, error: 'Excepción AnimeAV1: $e', url: url);
    }
  }

  // ─── BÚSQUEDA ─────────────────────────────────────────────────
  static Future<List<BuscadorItem>> search(String q) async {
    final query = Uri.encodeComponent(q.trim());
    final url = '$base/search?q=$query';

    try {
      final res = await http.get(Uri.parse(url), headers: {'User-Agent': userAgent}).timeout(timeout);
      if (res.statusCode != 200) return [];

      final doc = parser.parse(res.body);
      final results = <BuscadorItem>[];
      final elements = doc.querySelectorAll('.anime-card, .card, article.anime, .grid article');

      for (final el in elements) {
        final aTag = el.querySelector('a');
        final href = aTag?.attributes['href'] ?? '';
        if (href.isEmpty) continue;

        final imgTag = el.querySelector('img');
        var poster = imgTag?.attributes['src'] ?? imgTag?.attributes['data-src'] ?? '';
        if (poster.startsWith('//')) poster = 'https:$poster';

        final title = el.querySelector('.title, h3, h2')?.text.trim() ?? 'Sin título';

        results.add(BuscadorItem(
          sitio: 'animeav1',
          titulo: title,
          tipo: 'anime',
          url: href.startsWith('http') ? href : '$base$href',
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
    String tipo = 'anime',
  }) async {
    try {
      final res = await http.get(Uri.parse(url), headers: {'User-Agent': userAgent}).timeout(timeout);
      if (res.statusCode != 200) {
        return DetalleContenido(
          ok: false,
          error: 'Error AnimeAV1 (${res.statusCode})',
          servicio: 'animeav1',
          titulo: titulo,
          tipo: tipo,
        );
      }

      final doc = parser.parse(res.body);
      final sinopsis = doc.querySelector('.sinopsis, .synopsis, .description, p')?.text.trim() ?? '';

      final imgEl = doc.querySelector('.poster img, .cover img, img');
      var poster = imgEl?.attributes['src'] ?? '';
      if (poster.startsWith('//')) poster = 'https:$poster';

      final genres = doc.querySelectorAll('.genres a, .generos a').map((e) => e.text.trim()).toList();

      final capitulos = <DetalleCapitulo>[];
      final epLinks = doc.querySelectorAll('.episodes a, a[href*="/ver/"], a[href*="/episodio/"]');
      int epIdx = 1;
      for (final a in epLinks) {
        final href = a.attributes['href'] ?? '';
        if (href.isEmpty) continue;
        final epTitle = a.text.trim();
        final epNumMatch = RegExp(r'(\d+)').firstMatch(epTitle);
        final epNum = epNumMatch != null ? (int.tryParse(epNumMatch.group(1)!) ?? epIdx) : epIdx;

        capitulos.add(DetalleCapitulo(
          temporada: 1,
          numero: epNum,
          titulo: 'Episodio $epNum',
          url: href.startsWith('http') ? href : '$base$href',
          imagen: poster,
        ));
        epIdx++;
      }

      final temporadas = capitulos.isNotEmpty
          ? [DetalleTemporada(numero: 1, nombre: 'Temporada 1', episodios: capitulos)]
          : <DetalleTemporada>[];

      final firstEpUrl = capitulos.isNotEmpty ? capitulos.first.url : url;
      final servidores = await fetchServers(url: firstEpUrl);

      debugPrint('[AnimeAV1] Episodios encontrados: ${capitulos.length}');
      debugPrint('[AnimeAV1] Servidores encontrados: ${servidores.length}');

      return DetalleContenido(
        ok: true,
        servicio: 'animeav1',
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
        error: 'Excepción AnimeAV1: $e',
        servicio: 'animeav1',
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
      final res = await http.get(Uri.parse(url), headers: {'User-Agent': userAgent}).timeout(timeout);
      if (res.statusCode != 200) return [];

      final doc = parser.parse(res.body);
      final servers = <DetalleServidor>[];
      final seen = <String>{};

      final iframes = doc.querySelectorAll('iframe');
      for (final ifr in iframes) {
        var src = ifr.attributes['src'] ?? '';
        if (src.startsWith('//')) src = 'https:$src';
        if (src.isNotEmpty && !seen.contains(src) && !src.contains('recaptcha')) {
          seen.add(src);
          servers.add(DetalleServidor(
            nombre: 'AnimeAV1 · Reproductor HD',
            url: src,
            idioma: 'subtitulado',
            calidad: '1080p',
          ));
        }
      }

      return servers;
    } catch (_) {
      return [];
    }
  }
}
