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
  static const Set<String> _kAnimeLangs = {'ja', 'ko', 'zh'};

  /// Falsos positivos frecuentes en TMDB que traen la etiqueta "christmas"
  /// o "holiday" pero NO son películas/series navideñas (ej. Coco, El extraño
  /// mundo de Jack, Terrifier 3, Mujercitas, Hawkeye, Amagami SS, etc.).
  static const Set<int> _kExcludedChristmasIds = {
    354912,  // Coco (Día de Muertos)
    9479,    // El extraño mundo de Jack (Halloween)
    1034541, // Terrifier 3 (Terror)
    331482,  // Mujercitas
    927,     // Gremlins
    562,     // Duro de matar (Die Hard)
    1573,    // Duro de matar 2
    240,     // El Padrino II
    364,     // Batman regresa
    52083,   // Amagami SS (Anime)
    88329,   // Hawkeye
    242977,  // La Palma
    33153,   // Fanny och Alexander
  };

  /// Clásicos navideños garantizados que siempre pasan el filtro aunque
  /// su título en español no contenga la palabra "Navidad" y que tienen
  /// alta disponibilidad en servidores.
  static const Set<int> _kGuaranteedChristmasIds = {
    771,    // Mi pobre angelito
    772,    // Mi pobre angelito 2
    9714,   // Mi pobre angelito 3
    8871,   // El Grinch (2000)
    360920, // El Grinch (2018)
    508965, // Klaus
    5255,   // El expreso polar
    10719,  // Elf, el duende
    17979,  // Los fantasmas de Scrooge
    508,    // Realmente amor
    1581,   // El descanso (The Holiday)
    1585,   // ¡Qué bello es vivir!
    527435, // Crónicas de Navidad
    654028, // Crónicas de Navidad 2
    11395,  // Santa Cláusula
    9021,   // Santa Cláusula 2
    13767,  // Santa Cláusula 3
    9279,   // El regalo prometido
    845781, // Código: Traje rojo
    5825,   // Vacaciones de Navidad
    81188,  // El origen de los guardianes
    51052,  // Operación Regalo (Arthur Christmas)
    9745,   // Jack Frost
    11881,  // Milagro en la calle 34
    13673,  // Una Navidad de locos
    12193,  // Cuatro Navidades
    615666, // El chico que salvó la Navidad
    557940, // Intercambio de princesas
    715931, // Spirited: El espíritu de las fiestas
    756199, // La familia Claus
    529203, // El caballero de la Navidad
    111625, // Dash y Lily
    95612,  // Navidad en casa
    155631, // Santa Cláusula: Un nuevo Santa
    261317, // Mistletoe Murders
    94587,  // Feliz lo que quieras
  };

  static final RegExp _kChristmasSignalRe = RegExp(
    r'navidad|navideñ|christmas|xmas|santa\b|santa\s*claus|pap[aá]\s*noel|noel\b|'
    r'nochebuena|nochevieja|a[ñn]o\s*nuevo|fin\s*de\s*a[ñn]o|new\s*year|'
    r'thanksgiving|acci[oó]n\s*de\s*gracias|'
    r'grinch|scrooge|klaus|mu[eé]rdago|mistletoe|villancic|trineo|polo\s*norte|'
    r'north\s*pole|expreso\s*polar|polar\s*express|mi\s*pobre\s*angelito|'
    r'home\s*alone|solo\s*en\s*casa|regalo\s*prometido|jingle|kringle|'
    r'frosty|rudolph|rodolfo|snowman|muñeco\s*de\s*nieve|cascanueces|'
    r'nutcracker|noche\s*de\s*paz|silent\s*night|duende|elf\b|renos?\b|'
    r'reindeer|julkalender|snøfall|sunes\s*jul|tidsrejsen|felices\s*fiestas|'
    r'esp[ií]ritu\s*navideñ|christmas\s*eve|v[ií]spera\s*de\s*navidad',
    caseSensitive: false,
  );

  static String _todayIso() {
    final now = DateTime.now();
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
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
    final today = _todayIso();

    // Keywords festivas genuinas: christmas (207317), santa claus (1991),
    // thanksgiving (4543), new year (252123), christmas eve (260365).
    const movieKeywords = '207317|1991|4543|252123|260365';

    Future<List<Map<String, dynamic>>> discoverMovies(
      String sortBy,
      String page, {
      String minVotes = '50',
    }) =>
        _fetchList(
          '/discover/movie',
          apiKey: apiKey,
          language: language,
          query: {
            'with_keywords': movieKeywords,
            'without_genres': '27',
            'release_date.lte': today,
            'vote_count.gte': minVotes,
            'sort_by': sortBy,
            'page': page,
            if (isKids) ...{
              'certification_country': 'US',
              'certification.lte': 'PG',
            },
          },
        );

    final batches = await Future.wait([
      // 1. Clásicos y películas conocidas con alta disponibilidad en servidores (páginas 1-4)
      discoverMovies('vote_count.desc', '1', minVotes: '50'),
      discoverMovies('vote_count.desc', '2', minVotes: '50'),
      discoverMovies('vote_count.desc', '3', minVotes: '50'),
      discoverMovies('vote_count.desc', '4', minVotes: '50'),
      // 2. Populares recientes y de temporada que ya tienen votos reales (páginas 1-3)
      discoverMovies('popularity.desc', '1', minVotes: '40'),
      discoverMovies('popularity.desc', '2', minVotes: '40'),
      discoverMovies('popularity.desc', '3', minVotes: '40'),
      // 3. Búsqueda directa por título para completar catálogo amplio
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
      _fetchList(
        '/search/movie',
        apiKey: apiKey,
        language: language,
        query: {'query': 'Santa', 'page': '1'},
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
    final today = _todayIso();

    // Keywords estrictamente de temporada navideña / fin de año / Santa / Acción de Gracias
    // (sin 65="holiday" que mete anime y otras fiestas no relacionadas).
    const tvKeywords = '207317|1991|4543|252123|260365|193048|196450';
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
            'first_air_date.lte': today,
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
        if (_kExcludedChristmasIds.contains(id)) continue;

        final gidsRaw = raw['genre_ids'];
        final gids = <int>{};
        if (gidsRaw is List) {
          for (final g in gidsRaw) {
            final gid = g is num ? g.toInt() : int.tryParse('$g');
            if (gid != null) gids.add(gid);
          }
        }

        // Nunca terror en el Especial de Navidad
        if (gids.contains(27)) continue;

        if (isKids) {
          if (gids.any(_kKidsExcludedGenres.contains)) continue;
        }

        if (mediaType == 'tv') {
          if (gids.any(_kTvExcludedGenres.contains)) continue;
          final votes = raw['vote_count'] is num ? (raw['vote_count'] as num).toInt() : 0;
          if (votes < 3) continue;
        }

        // En películas, exigir un mínimo de votos cuando está presente para
        // evitar películas oscuras sin servidores en español/subtitulado.
        if (mediaType == 'movie' && !_kGuaranteedChristmasIds.contains(id)) {
          final rawVotes = raw['vote_count'];
          if (rawVotes is num && rawVotes.toInt() < 25) {
            continue;
          }
        }

        // Excluir estrenos futuros (aún no disponibles en servidores)
        final dateStr = (raw['release_date'] ?? raw['first_air_date'] ?? '')
            .toString()
            .trim();
        if (dateStr.length >= 10 && dateStr.compareTo(_todayIso()) > 0) {
          continue;
        }

        final title = (raw['title'] ?? raw['name'] ?? raw['titulo'] ?? '')
            .toString()
            .trim();
        if (title.isEmpty) continue;

        final origTitle =
            (raw['original_title'] ?? raw['original_name'] ?? '').toString();
        final overview = (raw['overview'] ?? '').toString();
        final origLang =
            (raw['original_language'] ?? '').toString().trim().toLowerCase();

        // Excluir anime asiático no navideño colado por etiquetas genéricas
        if (gids.contains(16) && _kAnimeLangs.contains(origLang)) {
          if (!_kChristmasSignalRe.hasMatch('$title $origTitle')) {
            continue;
          }
        }

        // Verificar que realmente sea contenido navideño (clásico garantizado
        // o mención navideña explícita en título/sinopsis).
        final isGuaranteed = _kGuaranteedChristmasIds.contains(id);
        final hasSignal =
            _kChristmasSignalRe.hasMatch('$title $origTitle $overview');
        if (!isGuaranteed && !hasSignal) {
          continue;
        }

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
      final votesA = (a['vote_count'] is num)
          ? (a['vote_count'] as num).toDouble()
          : 0.0;
      final votesB = (b['vote_count'] is num)
          ? (b['vote_count'] as num).toDouble()
          : 0.0;
      // Combinar popularidad + fama real (votos) y priorizar español/inglés
      // para que arriba salgan siempre títulos que sí tienen servidores.
      final scoreA = popA + (votesA * 0.025);
      final scoreB = popB + (votesB * 0.025);
      final langA = _kPreferredLangs.contains('${a['original_language']}') ? 1.0 : 0.35;
      final langB = _kPreferredLangs.contains('${b['original_language']}') ? 1.0 : 0.35;
      return (scoreB * langB).compareTo(scoreA * langA);
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

