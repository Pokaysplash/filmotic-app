import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as parser;
import 'package:http/http.dart' as http;
import '../models/scraper/detalle_model.dart';
import 'base/base_home_scraper.dart';
import 'base/buscador.dart';

class ThanhDatTodayScraper {
  static const String base = 'https://thanhdattoday.online';

  static const List<String> generos = [
    'action',
    'adventure',
    'animation',
    'comedy',
    'crime',
    'documentary',
    'drama',
    'family',
    'fantasy',
    'horror',
    'mystery',
    'romance',
    'science-fiction',
    'thriller',
    'war',
    'western',
  ];

  static List<String> tiposDisponibles() => ['movie', 'tv', 'populares', 'top'];

  static String _detectIdioma(String text) {
    final lower = text.toLowerCase();
    if (lower.contains('latino') || lower.contains('es-la') || lower.contains('spanish latino')) {
      return 'latino';
    }
    if (lower.contains('castellano') || lower.contains('es-es') || lower.contains('español')) {
      return 'castellano';
    }
    if (lower.contains('sub') || lower.contains('subtitulado') || lower.contains('vostfr') || lower.contains('vose')) {
      return 'subtitulado';
    }
    if (lower.contains('english') || lower.contains('ingles') || lower.contains('inglés')) {
      return 'inglés';
    }
    return 'subtitulado';
  }

  // ─── LISTADO (FETCH) ──────────────────────────────────────────
  static Future<ScraperResult> fetch({
    String? tipo,
    String? genero,
    bool populares = false,
    int page = 1,
  }) async {
    String url = base;
    if (genero != null && genero.isNotEmpty) {
      url = '$base/genre/$genero/';
    } else if (tipo == 'tv' || tipo == 'series') {
      url = '$base/tv-series/';
    } else if (tipo == 'top') {
      url = '$base/top-imdb/';
    } else if (populares) {
      url = '$base/trending/';
    } else {
      url = '$base/movies-hd/';
    }

    if (page > 1) {
      url = '$url?page=$page';
    }

    try {
      final res = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36',
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        },
      ).timeout(const Duration(seconds: 15));

      if (res.statusCode < 200 || res.statusCode >= 400) {
        return ScraperResult(ok: false, error: 'Status ${res.statusCode}', url: url);
      }

      final doc = parser.parse(res.body);
      final items = <ScraperItem>[];

      final cards = doc.querySelectorAll('a.card, .grid a, .card');

      for (final card in cards) {
        final link = card.attributes['href'] ?? card.querySelector('a')?.attributes['href'] ?? '';
        if (link.isEmpty || link.startsWith('#')) continue;

        final imgTag = card.querySelector('img');
        var poster = imgTag?.attributes['data-src'] ??
            imgTag?.attributes['src'] ??
            imgTag?.attributes['data-original'] ??
            '';
        if (poster.startsWith('//')) poster = 'https:$poster';

        final title = card.querySelector('.meta h3, h3, .film-title, .title')?.text.trim() ??
            imgTag?.attributes['alt'] ??
            card.attributes['title'] ??
            'Sin título';

        final isTv = link.contains('/tv/') ||
            link.contains('/tv-series/') ||
            link.contains('/series/');

        final yearStr = card.querySelector('.year, .row .year')?.text.replaceAll(RegExp(r'\D'), '');
        final year = int.tryParse(yearStr ?? '');

        final ratingStr = card.querySelector('.rating, .row .rating')?.text.replaceAll('★', '').trim();
        final rating = double.tryParse(ratingStr ?? '');

        // Extraer TMDB ID del enlace (ej: /movie/resident-evil-1423191/)
        int? tmdbId;
        final idMatch = RegExp(r'-(\d+)/?$').firstMatch(link);
        if (idMatch != null) {
          tmdbId = int.tryParse(idMatch.group(1)!);
        }

        final fullUrl = link.startsWith('http') ? link : '$base$link';

        items.add(ScraperItem(
          sitio: 'thanhdattoday',
          titulo: title,
          tipo: isTv ? 'tv' : 'movie',
          url: fullUrl,
          poster: poster,
          year: year,
          rating: rating,
          tmdbId: tmdbId,
        ));
      }

      debugPrint('[HDToday] Encontrados ${items.length} elementos (Página $page)');

      return ScraperResult(
        ok: true,
        url: url,
        currentPage: page,
        hasNext: items.length >= 20,
        items: items,
      );
    } catch (e) {
      debugPrint('[HDToday] Error en fetch: $e');
      return ScraperResult(ok: false, error: e.toString(), url: url);
    }
  }

  // ─── BÚSQUEDA ─────────────────────────────────────────────────
  static Future<List<BuscadorItem>> search(String q) async {
    final query = Uri.encodeComponent(q.trim());
    final url = '$base/search?q=$query';

    try {
      final res = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36',
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        },
      ).timeout(const Duration(seconds: 15));

      if (res.statusCode < 200 || res.statusCode >= 400) return [];

      final doc = parser.parse(res.body);
      final results = <BuscadorItem>[];

      final cards = doc.querySelectorAll('a.card, .grid a, .card');
      for (final card in cards) {
        final link = card.attributes['href'] ?? card.querySelector('a')?.attributes['href'] ?? '';
        if (link.isEmpty || link.startsWith('#')) continue;

        final imgTag = card.querySelector('img');
        var poster = imgTag?.attributes['data-src'] ??
            imgTag?.attributes['src'] ??
            imgTag?.attributes['data-original'] ??
            '';
        if (poster.startsWith('//')) poster = 'https:$poster';

        final title = card.querySelector('.meta h3, h3, .title')?.text.trim() ??
            imgTag?.attributes['alt'] ??
            'Sin título';

        final isTv = link.contains('/tv/') || link.contains('/tv-series/') || link.contains('/series/');
        final yearStr = card.querySelector('.year, .row .year')?.text.replaceAll(RegExp(r'\D'), '');
        final year = int.tryParse(yearStr ?? '');

        int? tmdbId;
        final idMatch = RegExp(r'-(\d+)/?$').firstMatch(link);
        if (idMatch != null) {
          tmdbId = int.tryParse(idMatch.group(1)!);
        }

        final fullUrl = link.startsWith('http') ? link : '$base$link';

        results.add(BuscadorItem(
          sitio: 'thanhdattoday',
          titulo: title,
          tipo: isTv ? 'tv' : 'movie',
          url: fullUrl,
          imagen: poster,
          anio: year,
          tmdbId: tmdbId,
        ));
      }

      debugPrint('[HDToday] Búsqueda "$q": ${results.length} resultados');
      return results;
    } catch (e) {
      debugPrint('[HDToday] Error en búsqueda "$q": $e');
      return [];
    }
  }

  // ─── DETALLE Y SERVIDORES ─────────────────────────────────────
  static Future<DetalleContenido> fetchDetail({
    required String url,
    required String titulo,
    required String tipo,
  }) async {
    final servidores = <DetalleServidor>[];

    // Extraer TMDB ID del enlace
    final idMatch = RegExp(r'-(\d+)/?$').firstMatch(url);
    final tmdbId = idMatch?.group(1);

    if (tmdbId != null && tmdbId.isNotEmpty) {
      // Servidores directos conocidos por TMDB
      servidores.addAll([
        DetalleServidor(
          nombre: 'HDToday Server 1 (Vidcore)',
          url: 'https://vidcore.net/movie/$tmdbId?autoPlay=true&sub=en',
          idioma: 'subtitulado',
          calidad: '1080p',
        ),
        DetalleServidor(
          nombre: 'HDToday Server 2 (VidSrc)',
          url: 'https://vidsrc.me/embed/movie?tmdb=$tmdbId',
          idioma: 'subtitulado',
          calidad: '1080p',
        ),
        DetalleServidor(
          nombre: 'HDToday Server 3 (MultiEmbed)',
          url: 'https://multiembed.mov/directstream.php?video_id=$tmdbId&tmdb=1',
          idioma: 'subtitulado',
          calidad: 'HD',
        ),
        DetalleServidor(
          nombre: 'HDToday Server 4 (VidSrc Pro)',
          url: 'https://vidsrc.pro/embed/movie/$tmdbId',
          idioma: 'subtitulado',
          calidad: '1080p',
        ),
      ]);
    }

    return DetalleContenido(
      ok: true,
      servicio: 'thanhdattoday',
      titulo: titulo,
      tipo: tipo,
      servidores: servidores,
    );
  }

  static Future<List<DetalleServidor>> fetchServers({required String url}) async {
    final idMatch = RegExp(r'/(\d+)/?$').firstMatch(url) ?? RegExp(r'-(\d+)/?$').firstMatch(url);
    final tmdbId = idMatch?.group(1);
    if (tmdbId != null && tmdbId.isNotEmpty) {
      return [
        DetalleServidor(
          nombre: 'HDToday Server 1 (Vidcore)',
          url: 'https://vidcore.net/movie/$tmdbId?autoPlay=true&sub=en',
          idioma: 'subtitulado',
          calidad: '1080p',
        ),
        DetalleServidor(
          nombre: 'HDToday Server 2 (VidSrc)',
          url: 'https://vidsrc.me/embed/movie?tmdb=$tmdbId',
          idioma: 'subtitulado',
          calidad: '1080p',
        ),
        DetalleServidor(
          nombre: 'HDToday Server 3 (MultiEmbed)',
          url: 'https://multiembed.mov/directstream.php?video_id=$tmdbId&tmdb=1',
          idioma: 'subtitulado',
          calidad: 'HD',
        ),
        DetalleServidor(
          nombre: 'HDToday Server 4 (VidSrc Pro)',
          url: 'https://vidsrc.pro/embed/movie/$tmdbId',
          idioma: 'subtitulado',
          calidad: '1080p',
        ),
      ];
    }
    final detail = await fetchDetail(url: url, titulo: '', tipo: 'movie');
    return detail.servidores;
  }
}
