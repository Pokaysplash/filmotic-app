import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../../core/constants/tmdb_apis.dart';

class KidsSectionData {
  final List<Map<String, dynamic>> hero;
  final List<Map<String, dynamic>> animatedMovies;
  final List<Map<String, dynamic>> kidsSeries;
  final List<Map<String, dynamic>> familyAdventures;
  final List<Map<String, dynamic>> kidsComedy;
  final List<Map<String, dynamic>> animatedSeries;
  final List<Map<String, dynamic>> preschool;
  final List<Map<String, dynamic>> disneyPixar;
  final List<Map<String, dynamic>> dreamworksIllumination;
  final List<Map<String, dynamic>> studioGhibli;

  const KidsSectionData({
    this.hero = const [],
    this.animatedMovies = const [],
    this.kidsSeries = const [],
    this.familyAdventures = const [],
    this.kidsComedy = const [],
    this.animatedSeries = const [],
    this.preschool = const [],
    this.disneyPixar = const [],
    this.dreamworksIllumination = const [],
    this.studioGhibli = const [],
  });

  bool get isEmpty =>
      hero.isEmpty &&
      animatedMovies.isEmpty &&
      kidsSeries.isEmpty &&
      familyAdventures.isEmpty &&
      kidsComedy.isEmpty &&
      animatedSeries.isEmpty &&
      preschool.isEmpty &&
      disneyPixar.isEmpty &&
      dreamworksIllumination.isEmpty &&
      studioGhibli.isEmpty;
}

/// API dedicada de TMDB para la Zona Infantil.
/// Aplica filtros estrictos (include_adult=false, certification.lte=PG,
/// géneros infantiles/familiares y exclusión de géneros adultos/violentos).
class TmdbKidsApi {
  TmdbKidsApi._();
  static final TmdbKidsApi instance = TmdbKidsApi._();

  static const String _base = 'https://api.themoviedb.org/3';
  static const String _excludedGenres = '27,80,53,10752,10768,18,10749';
  static const Map<String, String> _headers = {
    'Accept': 'application/json',
    'User-Agent': 'Filmotic/1.0',
  };

  KidsSectionData? _cached;
  DateTime? _cachedAt;
  static const Duration _cacheTtl = Duration(minutes: 20);

  Future<KidsSectionData> fetchKidsCatalog({bool forceRefresh = false}) async {
    if (!forceRefresh &&
        _cached != null &&
        _cachedAt != null &&
        DateTime.now().difference(_cachedAt!) < _cacheTtl) {
      return _cached!;
    }

    final apiKey = await TmdbApis.getApiKey();
    final language = await TmdbApis.getLanguage();

    final results = await Future.wait([
      _discover(
        '/discover/movie',
        apiKey: apiKey,
        language: language,
        query: {
          'with_genres': '16,10751',
          'without_genres': _excludedGenres,
          'certification_country': 'US',
          'certification.lte': 'PG',
          'sort_by': 'popularity.desc',
          'vote_count.gte': '40',
        },
        mediaType: 'movie',
      ),
      _discover(
        '/discover/tv',
        apiKey: apiKey,
        language: language,
        query: {
          'with_genres': '10762',
          'without_genres': _excludedGenres,
          'sort_by': 'popularity.desc',
          'vote_count.gte': '10',
        },
        mediaType: 'tv',
      ),
      _discover(
        '/discover/movie',
        apiKey: apiKey,
        language: language,
        query: {
          'with_genres': '10751,12',
          'without_genres': _excludedGenres,
          'certification_country': 'US',
          'certification.lte': 'PG',
          'sort_by': 'popularity.desc',
          'vote_count.gte': '40',
        },
        mediaType: 'movie',
      ),
      _discover(
        '/discover/movie',
        apiKey: apiKey,
        language: language,
        query: {
          'with_genres': '16,35,10751',
          'without_genres': _excludedGenres,
          'certification_country': 'US',
          'certification.lte': 'PG',
          'sort_by': 'popularity.desc',
          'vote_count.gte': '35',
        },
        mediaType: 'movie',
      ),
      _discover(
        '/discover/tv',
        apiKey: apiKey,
        language: language,
        query: {
          'with_genres': '16,10751',
          'without_genres': '$_excludedGenres,10759,10765,9648',
          'sort_by': 'popularity.desc',
          'vote_count.gte': '15',
        },
        mediaType: 'tv',
      ),
      _discover(
        '/discover/tv',
        apiKey: apiKey,
        language: language,
        query: {
          'with_genres': '10762',
          'without_genres': '$_excludedGenres,10759,10765',
          'sort_by': 'vote_average.desc',
          'vote_count.gte': '25',
        },
        mediaType: 'tv',
      ),
      _discover(
        '/discover/movie',
        apiKey: apiKey,
        language: language,
        query: {
          'with_companies': '2|3|6125',
          'with_genres': '16|10751',
          'without_genres': _excludedGenres,
          'certification_country': 'US',
          'certification.lte': 'PG',
          'sort_by': 'popularity.desc',
          'vote_count.gte': '50',
        },
        mediaType: 'movie',
      ),
      _discover(
        '/discover/movie',
        apiKey: apiKey,
        language: language,
        query: {
          'with_companies': '521|6704',
          'with_genres': '16',
          'without_genres': _excludedGenres,
          'certification_country': 'US',
          'certification.lte': 'PG',
          'sort_by': 'popularity.desc',
          'vote_count.gte': '50',
        },
        mediaType: 'movie',
      ),
      _discover(
        '/discover/movie',
        apiKey: apiKey,
        language: language,
        query: {
          'with_companies': '10342',
          'with_genres': '16',
          'without_genres': _excludedGenres,
          'certification_country': 'US',
          'certification.lte': 'PG',
          'sort_by': 'popularity.desc',
          'vote_count.gte': '40',
        },
        mediaType: 'movie',
      ),
    ]);

    final animatedMovies = results[0];
    final kidsSeries = results[1];
    final familyAdventures = results[2];
    final kidsComedy = results[3];
    final animatedSeries = results[4];
    final preschool = results[5];
    final disneyPixar = results[6];
    final dreamworksIllumination = results[7];
    final studioGhibli = results[8];

    final heroPool = <Map<String, dynamic>>[];
    final seenHero = <String>{};
    for (final list in [animatedMovies, kidsSeries, familyAdventures]) {
      for (final item in list.take(5)) {
        final backdrop = (item['backdrop_path'] ?? '').toString();
        if (backdrop.isEmpty) continue;
        final key = '${item['media_type']}_${item['id']}';
        if (seenHero.add(key)) {
          heroPool.add(item);
        }
      }
    }

    final data = KidsSectionData(
      hero: heroPool.take(8).toList(),
      animatedMovies: animatedMovies,
      kidsSeries: kidsSeries,
      familyAdventures: familyAdventures,
      kidsComedy: kidsComedy,
      animatedSeries: animatedSeries,
      preschool: preschool,
      disneyPixar: disneyPixar,
      dreamworksIllumination: dreamworksIllumination,
      studioGhibli: studioGhibli,
    );

    if (!data.isEmpty) {
      _cached = data;
      _cachedAt = DateTime.now();
    }
    return data;
  }

  Future<List<Map<String, dynamic>>> _discover(
    String path, {
    required String apiKey,
    required String language,
    required Map<String, String> query,
    required String mediaType,
  }) async {
    final uri = Uri.parse('$_base$path').replace(
      queryParameters: {
        'api_key': apiKey,
        'language': language,
        'include_adult': 'false',
        'page': '1',
        ...query,
      },
    );
    try {
      final res = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return const [];
      final body = jsonDecode(res.body);
      final rawList = body is Map ? body['results'] : null;
      if (rawList is! List) return const [];

      final out = <Map<String, dynamic>>[];
      for (final raw in rawList) {
        if (raw is! Map) continue;
        final m = Map<String, dynamic>.from(raw);
        if (m['adult'] == true) continue;
        final poster = (m['poster_path'] ?? '').toString();
        if (poster.isEmpty) continue;
        final title = (m['title'] ?? m['name'] ?? '').toString().trim();
        if (title.isEmpty) continue;
        final id = m['id'];
        if (id == null) continue;

        m['tmdb_id'] = id;
        m['media_type'] = mediaType;
        m['titulo'] = title;
        out.add(m);
      }
      return out;
    } catch (_) {
      return const [];
    }
  }
}
