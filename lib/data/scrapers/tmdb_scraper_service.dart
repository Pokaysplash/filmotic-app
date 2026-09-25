import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as parser;
import 'package:http/http.dart' as http;
import '../../core/storage/app_database.dart';

class TmdbScrapedInfo {
  final int? tmdbId;
  final String title;
  final String? year;
  final String? overview;
  final String? poster;
  final String? backdrop;
  final List<String> genres;
  final List<String> cast;
  final double? rating;

  TmdbScrapedInfo({
    this.tmdbId,
    required this.title,
    this.year,
    this.overview,
    this.poster,
    this.backdrop,
    this.genres = const [],
    this.cast = const [],
    this.rating,
  });

  Map<String, dynamic> toMap() => {
        'tmdb_id': tmdbId,
        'title': title,
        'year': year,
        'overview': overview,
        'poster': poster,
        'backdrop': backdrop,
        'genres': genres,
        'cast': cast,
        'rating': rating,
      };

  factory TmdbScrapedInfo.fromMap(Map<String, dynamic> map) => TmdbScrapedInfo(
        tmdbId: map['tmdb_id'] as int?,
        title: map['title']?.toString() ?? '',
        year: map['year']?.toString(),
        overview: map['overview']?.toString(),
        poster: map['poster']?.toString(),
        backdrop: map['backdrop']?.toString(),
        genres: (map['genres'] as List?)?.map((e) => e.toString()).toList() ?? [],
        cast: (map['cast'] as List?)?.map((e) => e.toString()).toList() ?? [],
        rating: (map['rating'] as num?)?.toDouble(),
      );
}

class TmdbScraperService {
  TmdbScraperService._();
  static final TmdbScraperService instance = TmdbScraperService._();

  static const String _kBase = 'https://www.themoviedb.org';
  static const Map<String, String> _kHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept-Language': 'es-MX,es;q=0.9,en;q=0.8',
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
  };

  /// Busca directamente en themoviedb.org por scraping HTML y cachea el resultado en Sembast
  Future<TmdbScrapedInfo?> searchAndScrape({
    required String titulo,
    int? year,
  }) async {
    final cleanTitle = titulo.trim();
    if (cleanTitle.isEmpty) return null;

    final cacheKey = 'tmdb_search_${cleanTitle.toLowerCase()}_${year ?? ""}';

    // 1. Verificar si está en caché de Sembast
    final cached = await AppDatabase.instance.getTmdbCache(cacheKey);
    if (cached != null) {
      debugPrint('TmdbScraper: Cache hit para "$cleanTitle"');
      return TmdbScrapedInfo.fromMap(cached);
    }

    try {
      final searchUrl =
          '$_kBase/search?query=${Uri.encodeComponent(cleanTitle)}&language=es-MX';
      final response = await http
          .get(Uri.parse(searchUrl), headers: _kHeaders)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        debugPrint('TmdbScraper: Status ${response.statusCode} en búsqueda');
        return null;
      }

      final doc = parser.parse(response.body);
      final cards = doc.querySelectorAll('.search_results .card, div.card, .results .item');

      if (cards.isEmpty) {
        debugPrint('TmdbScraper: No se encontraron resultados para "$cleanTitle"');
        return null;
      }

      // Tomar el primer resultado o el que mejor coincida con el año
      var selected = cards.first;
      for (final card in cards) {
        final dateText = card.querySelector('.release_date, span.date')?.text ?? '';
        if (year != null && dateText.contains(year.toString())) {
          selected = card;
          break;
        }
      }

      final aTag = selected.querySelector('a.result, h2 a, a.image');
      final detailPath = aTag?.attributes['href'] ?? '';
      final titleText = selected.querySelector('h2, .title')?.text.trim() ?? cleanTitle;
      final overviewText = selected.querySelector('.overview, p')?.text.trim() ?? '';

      final imgTag = selected.querySelector('img.poster, img');
      var posterSrc = imgTag?.attributes['src'] ?? imgTag?.attributes['data-src'] ?? '';
      if (posterSrc.startsWith('/')) {
        posterSrc = 'https://image.tmdb.org/t/p/w500$posterSrc';
      }

      final dateStr = selected.querySelector('.release_date, span.date')?.text ?? '';
      final parsedYear = RegExp(r'\d{4}').firstMatch(dateStr)?.group(0) ?? year?.toString();

      int? tmdbId;
      if (detailPath.isNotEmpty) {
        final idMatch = RegExp(r'/(movie|tv)/(\d+)').firstMatch(detailPath);
        if (idMatch != null) {
          tmdbId = int.tryParse(idMatch.group(2) ?? '');
        }
      }

      List<String> genres = [];
      List<String> cast = [];
      String? backdrop;

      // Obtener detalle completo si hay detailPath
      if (detailPath.isNotEmpty) {
        try {
          final detailUrl = '$_kBase$detailPath?language=es-MX';
          final detailRes = await http
              .get(Uri.parse(detailUrl), headers: _kHeaders)
              .timeout(const Duration(seconds: 6));

          if (detailRes.statusCode == 200) {
            final detailDoc = parser.parse(detailRes.body);

            // Géneros
            final genreElements = detailDoc.querySelectorAll('span.genres a');
            genres = genreElements.map((e) => e.text.trim()).toList();

            // Reparto (cast)
            final castElements = detailDoc.querySelectorAll('ol.people li p a');
            cast = castElements.map((e) => e.text.trim()).take(8).toList();

            // Backdrop
            final metaImage = detailDoc.querySelector('meta[property="og:image"]')?.attributes['content'];
            if (metaImage != null && metaImage.contains('image.tmdb.org')) {
              backdrop = metaImage;
            }
          }
        } catch (_) {}
      }

      final info = TmdbScrapedInfo(
        tmdbId: tmdbId,
        title: titleText,
        year: parsedYear,
        overview: overviewText,
        poster: posterSrc.isNotEmpty ? posterSrc : null,
        backdrop: backdrop ?? posterSrc,
        genres: genres,
        cast: cast,
      );

      // Guardar en caché Sembast
      await AppDatabase.instance.setTmdbCache(cacheKey, info.toMap());

      return info;
    } catch (e) {
      debugPrint('TmdbScraper error: $e');
      return null;
    }
  }
}
