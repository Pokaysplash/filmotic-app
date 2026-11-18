import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../../core/constants/tmdb_apis.dart';
import '../../../../core/storage/app_database.dart';

/// Recolecta todo el catálogo navideño desde múltiples endpoints de TMDB
/// (keywords `christmas` [207317] y `holiday` [65], clásicos más votados y
/// búsqueda directa en español/inglés) garantizando cero duplicados.
class TmdbChristmasApi {
  TmdbChristmasApi._();
  static final TmdbChristmasApi instance = TmdbChristmasApi._();

  static const String _base = 'https://api.themoviedb.org/3';
  static const Set<int> _kKidsExcludedGenres = {27, 80, 53, 10752, 10768};
  static const Set<int> _kTvExcludedGenres = {10764, 10767, 10763, 10766};
  static const Set<String> _kPreferredLangs = {'es', 'en'};
  static const Map<String, String> _headers = {
    'Accept': 'application/json',
    'User-Agent': 'Filmotic/1.0',
  };

  List<Map<String, dynamic>>? _cachedMovies;
  DateTime? _cachedAt;
  bool? _cachedKidsMode;
  List<Map<String, dynamic>>? _cachedSeries;
  DateTime? _cachedSeriesAt;
  bool? _cachedSeriesKidsMode;
  static const Duration _cacheTtl = Duration(minutes: 25);

  Future<List<Map<String, dynamic>>> fetchAllChristmasMovies({
    bool forceRefresh = false,
  }) async {
    final isKids = AppDatabase.instance.activeProfile?.esInfantil == true;
    if (!forceRefresh &&
        _cachedMovies != null &&
        _cachedAt != null &&
        _cachedKidsMode == isKids &&
        DateTime.now().difference(_cachedAt!) < _cacheTtl) {
      return _cachedMovies!;
    }

    final apiKey = await TmdbApis.getApiKey();
    final language = await TmdbApis.getLanguage();

    final batches = await Future.wait([
      // 1. Keyword principal "christmas" (207317) ordenado por popularidad (páginas 1-3)
      _fetchList(
        '/discover/movie',
        apiKey: apiKey,
        language: language,
        query: {
          'with_keywords': '207317',
          'sort_by': 'popularity.desc',
          'page': '1',
          if (isKids) ...{'certification_country': 'US', 'certification.lte': 'PG'},
        },
      ),
      _fetchList(
        '/discover/movie',
        apiKey: apiKey,
        language: language,
        query: {
          'with_keywords': '207317',
          'sort_by': 'popularity.desc',
          'page': '2',
          if (isKids) ...{'certification_country': 'US', 'certification.lte': 'PG'},
        },
      ),
      _fetchList(
        '/discover/movie',
        apiKey: apiKey,
        language: language,
        query: {
          'with_keywords': '207317',
          'sort_by': 'popularity.desc',
          'page': '3',
          if (isKids) ...{'certification_country': 'US', 'certification.lte': 'PG'},
        },
      ),
      // 2. Clásicos navideños con más votos de todos los tiempos
      _fetchList(
        '/discover/movie',
        apiKey: apiKey,
        language: language,
        query: {
          'with_keywords': '207317',
          'sort_by': 'vote_count.desc',
          'page': '1',
          if (isKids) ...{'certification_country': 'US', 'certification.lte': 'PG'},
        },
      ),
      // 3. Keyword complementaria "holiday" (65)
      _fetchList(
        '/discover/movie',
        apiKey: apiKey,
        language: language,
        query: {
          'with_keywords': '65',
          'sort_by': 'popularity.desc',
          'page': '1',
          if (isKids) ...{'certification_country': 'US', 'certification.lte': 'PG'},
        },
      ),
      // 4. Búsqueda directa por título "Navidad" y "Christmas" para estrenos sin keyword
      _fetchList(
        '/search/movie',
        apiKey: apiKey,
        language: language,
        query: {'query': 'Navidad', 'page': '1'},
      ),
      _fetchList(
        '/search/movie',
        apiKey: apiKey,
        language: language,
        query: {'query': 'Christmas', 'page': '1'},
      ),
    ]);

    final merged = mergeUniqueChristmasMovies(batches, isKids: isKids);
    if (merged.isNotEmpty) {
      _cachedMovies = merged;
      _cachedAt = DateTime.now();
      _cachedKidsMode = isKids;
    }
    return merged;
  }

  Future<List<Map<String, dynamic>>> fetchAllChristmasSeries({
    bool forceRefresh = false,
  }) async {
    final isKids = AppDatabase.instance.activeProfile?.esInfantil == true;
    if (!forceRefresh &&
        _cachedSeries != null &&
        _cachedSeriesAt != null &&
        _cachedSeriesKidsMode == isKids &&
        DateTime.now().difference(_cachedSeriesAt!) < _cacheTtl) {
      return _cachedSeries!;
    }

    final apiKey = await TmdbApis.getApiKey();
    final language = await TmdbApis.getLanguage();

    // Keywords: christmas, holiday, christmas eve, christmas spirit, christmas story.
    const tvKeywords = '207317|65|260365|193048|196450';
    // Sin reality, talk shows, noticias ni telenovelas: casi nunca están en
    // las fuentes y al abrirlos no aparecía nada.
    const tvExcludedGenres = '10764,10767,10763,10766';
    Future<List<Map<String, dynamic>>> discoverTv(String sort, String page) =>
        _fetchList(
          '/discover/tv',
          apiKey: apiKey,
          language: language,
          query: {
            'with_keywords': tvKeywords,
            'without_genres': tvExcludedGenres,
            'vote_count.gte': '3',
            'sort_by': sort,
            'page': page,
          },
        );

    final batches = await Future.wait([
      discoverTv('popularity.desc', '1'),
      discoverTv('popularity.desc', '2'),
      discoverTv('popularity.desc', '3'),
      discoverTv('vote_count.desc', '1'),
      _fetchList(
        '/search/tv',
        apiKey: apiKey,
        language: language,
        query: {'query': 'Navidad', 'page': '1'},
      ),
      _fetchList(
        '/search/tv',
        apiKey: apiKey,
        language: language,
        query: {'query': 'Christmas', 'page': '1'},
      ),
    ]);

    final merged = mergeUniqueChristmasMovies(
      batches,
      isKids: isKids,
      mediaType: 'tv',
    );
    if (merged.isNotEmpty) {
      _cachedSeries = merged;
      _cachedSeriesAt = DateTime.now();
      _cachedSeriesKidsMode = isKids;
    }
    return merged;
  }

  /// Une listas de TMDB eliminando cualquier duplicado por `id` y ordenando por popularidad.
  static List<Map<String, dynamic>> mergeUniqueChristmasMovies(
    List<List<Map<String, dynamic>>> batches, {
    bool isKids = false,
    String mediaType = 'movie',
  }) {
    final seenIds = <int>{};
    final out = <Map<String, dynamic>>[];

    for (final batch in batches) {
      for (final raw in batch) {
        if (raw['adult'] == true) continue;
        final poster = (raw['poster_path'] ?? '').toString().trim();
        if (poster.isEmpty) continue;

        final id = raw['id'] is num
            ? (raw['id'] as num).toInt()
            : int.tryParse('${raw['id']}') ?? 0;
        if (id <= 0 || !seenIds.add(id)) continue;

        if (isKids) {
          final gids = raw['genre_ids'];
          if (gids is List &&
              gids.any((g) {
                final gid = g is num ? g.toInt() : int.tryParse('$g');
                return gid != null && _kKidsExcludedGenres.contains(gid);
              })) {
            continue;
          }
        }

        if (mediaType == 'tv') {
          final gids = raw['genre_ids'];
          if (gids is List &&
              gids.any((g) {
                final gid = g is num ? g.toInt() : int.tryParse('$g');
                return gid != null && _kTvExcludedGenres.contains(gid);
              })) {
            continue;
          }
          final votes = raw['vote_count'] is num ? (raw['vote_count'] as num).toInt() : 0;
          if (votes < 3) continue;
        }

        final title = (raw['title'] ?? raw['name'] ?? raw['titulo'] ?? '')
            .toString()
            .trim();
        if (title.isEmpty) continue;

        final normalized = Map<String, dynamic>.from(raw);
        normalized['id'] = id;
        normalized['tmdb_id'] = id;
        normalized['media_type'] = mediaType;
        normalized['titulo'] = title;
        out.add(normalized);
      }
    }

    out.sort((a, b) {
      final popA = (a['popularity'] is num)
          ? (a['popularity'] as num).toDouble()
          : double.tryParse('${a['popularity']}') ?? 0.0;
      final popB = (b['popularity'] is num)
          ? (b['popularity'] as num).toDouble()
          : double.tryParse('${b['popularity']}') ?? 0.0;
      // Español/inglés primero: son los que realmente tienen las fuentes.
      final langA = _kPreferredLangs.contains('${a['original_language']}') ? 1.0 : 0.35;
      final langB = _kPreferredLangs.contains('${b['original_language']}') ? 1.0 : 0.35;
      return (popB * langB).compareTo(popA * langA);
    });

    return out;
  }

  Future<List<Map<String, dynamic>>> _fetchList(
    String path, {
    required String apiKey,
    required String language,
    required Map<String, String> query,
  }) async {
    final uri = Uri.parse('$_base$path').replace(
      queryParameters: {
        'api_key': apiKey,
        'language': language,
        'include_adult': 'false',
        ...query,
      },
    );
    try {
      final res = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return const [];
      final decoded = jsonDecode(res.body);
      final results = decoded is Map ? decoded['results'] : null;
      if (results is! List) return const [];
      return results
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      return const [];
    }
  }
}

