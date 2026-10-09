import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../../core/constants/tmdb_apis.dart';
import '../../../../core/storage/app_database.dart';

class TmdbMetadata {
  final int tmdbId;
  final String mediaType;
  final String title;
  final String? originalTitle;
  final String? imdbId;
  final int? year;
  final Map<String, dynamic> raw;

  const TmdbMetadata({
    required this.tmdbId,
    required this.mediaType,
    required this.title,
    this.originalTitle,
    this.imdbId,
    this.year,
    this.raw = const {},
  });
}

/// Servicio centralizado de metadatos TMDB con deduplicación en vuelo y caché en Sembast.
/// Evita que múltiples extractores concurrentes saturen la API de TMDB o reciban HTTP 400.
class TmdbMetadataService {
  TmdbMetadataService._();
  static final TmdbMetadataService instance = TmdbMetadataService._();

  static const String _base = 'https://api.themoviedb.org/3';
  static final Map<String, Future<TmdbMetadata?>> _inFlight = {};

  Future<TmdbMetadata?> getMetadata({
    required int tmdbId,
    required bool isMovie,
    String language = 'es-MX',
  }) async {
    if (tmdbId <= 0) return null;
    final mediaType = isMovie ? 'movie' : 'tv';
    final cacheKey = 'meta_${mediaType}_${tmdbId}_$language';

    // 1) Comprobar caché en disco (Sembast)
    try {
      final cached = await AppDatabase.instance.getTmdbCache(cacheKey);
      if (cached != null) {
        return _fromMap(tmdbId, mediaType, cached);
      }
    } catch (_) {}

    // 2) Deduplicación en vuelo: si ya hay una petición corriendo para este ID, reusarla
    if (_inFlight.containsKey(cacheKey)) {
      return _inFlight[cacheKey];
    }

    final completer = Completer<TmdbMetadata?>();
    _inFlight[cacheKey] = completer.future;

    try {
      final key = await TmdbApis.getApiKey();
      final url = '$_base/$mediaType/$tmdbId?api_key=$key&language=$language&append_to_response=external_ids,translations';
      final res = await http.get(
        Uri.parse(url),
        headers: {
          'Accept': 'application/json',
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        },
      ).timeout(const Duration(seconds: 12));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data is Map<String, dynamic> && data['success'] != false) {
          unawaited(AppDatabase.instance.setTmdbCache(cacheKey, data));
          final meta = _fromMap(tmdbId, mediaType, data);
          completer.complete(meta);
          return meta;
        }
      }
      completer.complete(null);
    } catch (e) {
      completer.complete(null);
    } finally {
      _inFlight.remove(cacheKey);
    }

    return completer.future;
  }

  TmdbMetadata _fromMap(int tmdbId, String mediaType, Map<String, dynamic> data) {
    final title = (mediaType == 'movie' ? (data['title'] ?? data['name']) : (data['name'] ?? data['title']))?.toString() ?? '';
    final orig = (mediaType == 'movie' ? data['original_title'] : data['original_name'])?.toString();

    // Extraer imdb_id
    String? imdb = data['imdb_id']?.toString();
    if ((imdb == null || imdb.isEmpty) && data['external_ids'] is Map) {
      imdb = data['external_ids']['imdb_id']?.toString();
    }

    int? year;
    final dateStr = (mediaType == 'movie' ? data['release_date'] : data['first_air_date'])?.toString();
    if (dateStr != null && dateStr.length >= 4) {
      year = int.tryParse(dateStr.substring(0, 4));
    }

    return TmdbMetadata(
      tmdbId: tmdbId,
      mediaType: mediaType,
      title: title,
      originalTitle: orig,
      imdbId: (imdb != null && imdb.isNotEmpty) ? imdb : null,
      year: year,
      raw: data,
    );
  }
}
