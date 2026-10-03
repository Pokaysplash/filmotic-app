import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

/// Servicio extractor oficial para Canela.TV (VOD de Películas y Series en Español).
/// Extrae transmisiones HLS directas (master.m3u8) autenticadas vía Edge API.
class CanelaService {
  CanelaService._();

  static const _kTmdbKey = 'a2d9bbed370d9f678e34006f8750a5a5';
  static const _kTmdbBase = 'https://api.themoviedb.org/3';

  static const _kUa =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  // Canela Edge & CMS Endpoints
  static const _kOAuthUrl =
      'https://auth-platform.edge.api.canela.tv/oauth2/token';
  static const _kGuestQpatUrl =
      'https://auth-gw.edge.api.canela.tv/platform/access/token';
  static const _kClientRegUrl =
      'https://device-register-service.edge.api.canela.tv/device/app/register';
  static const _kPlaybackAuthUrl =
      'https://playback-auth-service.edge.api.canela.tv/media/content/authorize';
  static const _kSearchUrl = 'https://search-cdn.cms.api.canela.tv/content/search';
  static const _kVodMetaUrl = 'https://data-store-cdn.cms.api.canela.tv';

  static const _kClientId = 'canela-canela-web';

  // Cache en memoria de tokens de sesión
  static String? _cachedOAuthToken;
  static int _oAuthTokenExpiresAt = 0;

  static String? _cachedQpatToken;
  static int _qpatTokenExpiresAt = 0;

  static const _kUuid = Uuid();

  /// Scrapea enlaces directos desde Canela.TV para la película o episodio solicitado.
  static Stream<CanelaServer> scrape({
    required int tmdbId,
    required bool isMovie,
    int season = 1,
    int episode = 1,
  }) async* {
    if (tmdbId <= 0) {
      throw Exception('tmdbId inválido');
    }

    final tmdb = await _getTmdbInfo(tmdbId, isMovie ? 'movie' : 'tv');
    if (tmdb.titles.isEmpty) {
      throw Exception('No se obtuvo información de TMDB');
    }

    // 1. Buscar en Canela por título en español y original
    final match = await _searchCanela(
      titles: tmdb.titles,
      year: tmdb.year,
      isMovie: isMovie,
    );

    if (match == null) {
      throw Exception('No se encontró contenido coincidente en Canela.TV');
    }

    String contentId;
    String catalogType;

    if (isMovie) {
      contentId = match.slug.isNotEmpty ? match.slug : match.id;
      catalogType = 'movie';
    } else {
      // Para series: buscar la temporada y el episodio correspondiente
      final epInfo = await _findEpisode(
        seriesId: match.id,
        seasonNum: season,
        episodeNum: episode,
      );
      if (epInfo == null) {
        throw Exception(
          'Episodio S${season}E$episode no encontrado en Canela.TV',
        );
      }
      contentId = epInfo.slug.isNotEmpty ? epInfo.slug : epInfo.id;
      catalogType = 'tvepisode';
    }

    // 2. Obtener la URL de reproducción HLS master.m3u8 mediante el flujo de autorización
    final streamUrl = await _authorizePlayback(
      contentId: contentId,
      catalogType: catalogType,
    );

    if (streamUrl == null || streamUrl.isEmpty) {
      throw Exception('No se pudo generar el stream de reproducción');
    }

    yield CanelaServer(
      serverName: 'Directo HD',
      url: streamUrl,
      calidad: '1080p',
      idioma: 'LAT',
      tmdbId: tmdbId,
      season: isMovie ? 0 : season,
      episode: isMovie ? 0 : episode,
    );
  }

  // ─── TMDB Info ─────────────────────────────────────────────────────────────

  static Future<_TmdbInfo> _getTmdbInfo(int tmdbId, String mediaType) async {
    final endpoint = mediaType == 'movie' ? 'movie' : 'tv';

    Future<Map<String, dynamic>?> fetchLang(String lang) async {
      try {
        final r = await http
            .get(
              Uri.parse(
                '$_kTmdbBase/$endpoint/$tmdbId?api_key=$_kTmdbKey&language=$lang',
              ),
              headers: {'Accept': 'application/json', 'User-Agent': _kUa},
            )
            .timeout(const Duration(seconds: 10));
        if (r.statusCode != 200) return null;
        final data = jsonDecode(r.body);
        if (data is! Map<String, dynamic>) return null;
        if (data['success'] == false) return null;
        return data;
      } catch (_) {
        return null;
      }
    }

    final es = await fetchLang('es-MX') ?? await fetchLang('es');
    final en = await fetchLang('en-US');

    final titles = <String>{};
    int? year;

    void addFrom(Map<String, dynamic>? d) {
      if (d == null) return;
      final t = d['title'] ?? d['name'];
      final ot = d['original_title'] ?? d['original_name'];
      if (t is String && t.trim().isNotEmpty) titles.add(t.trim());
      if (ot is String && ot.trim().isNotEmpty) titles.add(ot.trim());

      final date = (d['release_date'] ?? d['first_air_date']) as String?;
      if (date != null && date.length >= 4) {
        year ??= int.tryParse(date.substring(0, 4));
      }
    }

    addFrom(es);
    addFrom(en);

    return _TmdbInfo(titles: titles.toList(), year: year);
  }

  // ─── Búsqueda en Canela.TV ──────────────────────────────────────────────────

  static Future<_CanelaMatch?> _searchCanela({
    required List<String> titles,
    int? year,
    required bool isMovie,
  }) async {
    final cty = isMovie ? 'movie' : 'tvseries';

    for (final title in titles) {
      final query = title.trim();
      if (query.isEmpty) continue;

      try {
        final params = {
          'mode': 'detail',
          'st': 'published',
          'term': query,
          'cty': cty,
          'pageNumber': '1',
          'pageSize': '15',
          'reg': 'co',
          'dt': 'web',
          'client': _kClientId,
        };

        final uri = Uri.parse(_kSearchUrl).replace(queryParameters: params);
        final resp = await http
            .get(uri, headers: {'User-Agent': _kUa, 'Accept': 'application/json'})
            .timeout(const Duration(seconds: 10));

        if (resp.statusCode != 200) continue;
        final json = jsonDecode(resp.body);
        if (json is! Map<String, dynamic>) continue;
        final list = json['data'];
        if (list is! List || list.isEmpty) continue;

        // Evaluar candidatos
        _CanelaMatch? bestMatch;
        double bestScore = 0;

        for (final item in list) {
          if (item is! Map<String, dynamic>) continue;
          final itemCty = item['cty'] as String?;
          if (itemCty != cty) continue;

          final itemId = item['id'] as String? ?? '';
          final slug = (item['cnu'] ?? item['nu']) as String? ?? '';
          if (itemId.isEmpty && slug.isEmpty) continue;

          // Extraer nombres en español e inglés del item
          final itemTitles = <String>[];
          if (item['lon'] is List) {
            for (final lonItem in item['lon'] as List) {
              if (lonItem is Map && lonItem['n'] is String) {
                itemTitles.add(lonItem['n'] as String);
              }
            }
          }
          if (item['name'] is String) itemTitles.add(item['name'] as String);
          if (slug.isNotEmpty) itemTitles.add(slug.replaceAll('-', ' '));

          final itemYear = item['r'] is int
              ? item['r'] as int
              : int.tryParse(item['r']?.toString() ?? '');

          final score = _calculateScore(
            targetTitle: query,
            targetYear: year,
            candidateTitles: itemTitles,
            candidateYear: itemYear,
          );

          if (score > bestScore && score >= 0.70) {
            bestScore = score;
            bestMatch = _CanelaMatch(
              id: itemId,
              slug: slug,
              title: itemTitles.isNotEmpty ? itemTitles.first : slug,
              year: itemYear,
            );
          }
        }

        if (bestMatch != null) {
          return bestMatch;
        }
      } catch (_) {}
    }

    return null;
  }

  // ─── Búsqueda de Temporadas y Episodios ─────────────────────────────────────

  static Future<_CanelaEpisode?> _findEpisode({
    required String seriesId,
    required int seasonNum,
    required int episodeNum,
  }) async {
    try {
      // 1. Obtener temporadas
      final seasonsUri = Uri.parse(
        '$_kVodMetaUrl/content/series/$seriesId/seasons',
      ).replace(
        queryParameters: {
          'pageNumber': '1',
          'pageSize': '30',
          'reg': 'co',
          'dt': 'web',
          'client': _kClientId,
        },
      );

      final sResp = await http
          .get(seasonsUri, headers: {'User-Agent': _kUa, 'Accept': 'application/json'})
          .timeout(const Duration(seconds: 10));

      if (sResp.statusCode != 200) return null;
      final sJson = jsonDecode(sResp.body);
      final sList = sJson['data'] as List?;
      if (sList == null || sList.isEmpty) return null;

      String? targetSeasonId;
      for (final sItem in sList) {
        if (sItem is Map<String, dynamic>) {
          final snum = sItem['snum'];
          final parsedNum = snum is int ? snum : int.tryParse(snum?.toString() ?? '');
          if (parsedNum == seasonNum) {
            targetSeasonId = sItem['id'] as String?;
            break;
          }
        }
      }

      targetSeasonId ??= (sList.first as Map<String, dynamic>)['id'] as String?;
      if (targetSeasonId == null || targetSeasonId.isEmpty) return null;

      // 2. Obtener episodios de la temporada
      final epUri = Uri.parse(
        '$_kVodMetaUrl/content/series/$seriesId/episodes',
      ).replace(
        queryParameters: {
          'seasonId': targetSeasonId,
          'pageNumber': '1',
          'pageSize': '100',
          'sortBy': 'epz',
          'sortOrder': 'asc',
          'reg': 'co',
          'dt': 'web',
          'client': _kClientId,
        },
      );

      final epResp = await http
          .get(epUri, headers: {'User-Agent': _kUa, 'Accept': 'application/json'})
          .timeout(const Duration(seconds: 10));

      if (epResp.statusCode != 200) return null;
      final epJson = jsonDecode(epResp.body);
      final epList = epJson['data'] as List?;
      if (epList == null || epList.isEmpty) return null;

      for (final epItem in epList) {
        if (epItem is Map<String, dynamic>) {
          final epnum = epItem['epnum'];
          final parsedEp = epnum is int ? epnum : int.tryParse(epnum?.toString() ?? '');
          if (parsedEp == episodeNum) {
            final epId = epItem['id'] as String? ?? '';
            final epSlug = (epItem['nu'] ?? epItem['cnu']) as String? ?? '';
            return _CanelaEpisode(id: epId, slug: epSlug, episodeNum: parsedEp ?? 1);
          }
        }
      }

      // Si no coincide exactamente, usar el índice como fallback
      if (episodeNum - 1 < epList.length) {
        final fallbackItem = epList[episodeNum - 1] as Map<String, dynamic>;
        final epId = fallbackItem['id'] as String? ?? '';
        final epSlug = (fallbackItem['nu'] ?? fallbackItem['cnu']) as String? ?? '';
        return _CanelaEpisode(id: epId, slug: epSlug, episodeNum: episodeNum);
      }
    } catch (_) {}

    return null;
  }

  // ─── Autorización de Reproducción (Edge JWT & HLS Stream) ──────────────────

  static _CanelaSession? _cachedSession;

  static Future<_CanelaSession?> _getSession() async {
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (_cachedSession != null && nowSec < _cachedSession!.expiresAt - 60) {
      return _cachedSession;
    }

    try {
      // 1. OAuth
      final oAuthToken = await _getOAuthToken();
      if (oAuthToken == null) return null;

      // 2. QPAT con deviceId consistente
      final deviceId = _kUuid.v4();
      final qpatResp = await http
          .post(
            Uri.parse(_kGuestQpatUrl),
            headers: {
              'User-Agent': _kUa,
              'Content-Type': 'application/json',
              'x-client-id': _kClientId,
              'Authorization': 'Bearer $oAuthToken',
            },
            body: jsonEncode({
              'deviceId': deviceId,
              'deviceName': 'web',
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (qpatResp.statusCode != 200) return null;
      final qpatJson = jsonDecode(qpatResp.body);
      final qpatData = qpatJson['data'] as Map<String, dynamic>?;
      final qpatToken = qpatData?['token'] as String?;
      if (qpatToken == null || qpatToken.isEmpty) return null;

      // 3. Registrar dispositivo con el mismo deviceId
      final regResp = await http
          .post(
            Uri.parse(_kClientRegUrl),
            headers: {
              'User-Agent': _kUa,
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $oAuthToken',
              'X-Client-Id': _kClientId,
              'X-Authorization': qpatToken,
            },
            body: jsonEncode({'uniqueId': deviceId}),
          )
          .timeout(const Duration(seconds: 10));

      if (regResp.statusCode != 200) return null;
      final regJson = jsonDecode(regResp.body);
      final regData = regJson['data'] as Map<String, dynamic>?;
      if (regData == null) return null;

      final secretB64 = regData['secret'] as String?;
      final registeredDevId = (regData['deviceId'] as String?) ?? deviceId;
      if (secretB64 == null || secretB64.isEmpty) return null;

      final session = _CanelaSession(
        oAuthToken: oAuthToken,
        qpatToken: qpatToken,
        deviceId: registeredDevId,
        secretB64: secretB64,
        expiresAt: nowSec + 1800, // 30 min de validez
      );
      _cachedSession = session;
      return session;
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _authorizePlayback({
    required String contentId,
    required String catalogType,
  }) async {
    try {
      final session = await _getSession();
      if (session == null) return null;

      // Generar JWT HS256 firmado con secret
      String b64Url(List<int> bytes) =>
          base64UrlEncode(bytes).replaceAll('=', '');

      final header = {'alg': 'HS256', 'typ': 'JWT'};
      final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final payload = {
        'deviceId': session.deviceId,
        'aud': 'playback-auth-service',
        'iat': nowSec,
        'exp': nowSec + 60,
      };

      final hStr = b64Url(utf8.encode(jsonEncode(header)));
      final pStr = b64Url(utf8.encode(jsonEncode(payload)));
      final signingInput = '$hStr.$pStr';

      final keyBytes = base64Decode(session.secretB64);
      final hmacSha256 = Hmac(sha256, keyBytes);
      final digest = hmacSha256.convert(utf8.encode(signingInput));
      final sigStr = b64Url(digest.bytes);
      final jwtToken = '$signingInput.$sigStr';

      // Solicitar autorización de contenido
      final authResp = await http
          .post(
            Uri.parse(_kPlaybackAuthUrl),
            headers: {
              'User-Agent': _kUa,
              'Content-Type': 'application/json',
              'X-Device-Id': jwtToken,
              'Authorization': 'Bearer ${session.oAuthToken}',
              'X-Client-Id': _kClientId,
              'X-Authorization': session.qpatToken,
            },
            body: jsonEncode({
              'deviceName': 'web',
              'deviceId': session.deviceId,
              'contentId': contentId,
              'contentTypeId': 'vod',
              'catalogType': catalogType,
              'mediaFormat': 'hls',
              'drm': 'none',
              'delivery': 'streaming',
              'disableSsai': 'false',
              'deviceToken': jwtToken,
            }),
          )
          .timeout(const Duration(seconds: 12));

      if (authResp.statusCode != 200) return null;
      final authJson = jsonDecode(authResp.body);
      final authData = authJson['data'] as Map<String, dynamic>?;
      return authData?['contentUrl'] as String?;
    } catch (_) {
      return null;
    }
  }

  // ─── Manejo de Tokens OAuth ────────────────────────────────────────────────

  static Future<String?> _getOAuthToken() async {
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (_cachedOAuthToken != null && nowSec < _oAuthTokenExpiresAt - 60) {
      return _cachedOAuthToken;
    }

    try {
      final resp = await http
          .post(
            Uri.parse(_kOAuthUrl),
            headers: {
              'User-Agent': _kUa,
              'Content-Type': 'application/x-www-form-urlencoded',
            },
            body: {
              'client_id': 'webclient-ui-app',
              'client_secret': '59b587d5-efe2-481f-a687-51042bb87bad',
              'grant_type': 'client_credentials',
              'audience': 'edge-service',
              'scope': 'openid',
            },
          )
          .timeout(const Duration(seconds: 10));

      if (resp.statusCode != 200) return null;
      final json = jsonDecode(resp.body);
      final token = json['access_token'] as String?;
      final expiresIn = (json['expires_in'] as int?) ?? 600;

      if (token != null && token.isNotEmpty) {
        _cachedOAuthToken = token;
        _oAuthTokenExpiresAt = nowSec + expiresIn;
        return token;
      }
    } catch (_) {}
    return null;
  }

  // ─── Scoring de Similitud de Títulos ───────────────────────────────────────

  static double _calculateScore({
    required String targetTitle,
    int? targetYear,
    required List<String> candidateTitles,
    int? candidateYear,
  }) {
    double bestTitleSim = 0;
    final cleanTarget = _normalizeString(targetTitle);

    for (final cTitle in candidateTitles) {
      final cleanCandidate = _normalizeString(cTitle);
      if (cleanCandidate == cleanTarget) {
        bestTitleSim = 1.0;
        break;
      }
      if (cleanCandidate.contains(cleanTarget) ||
          cleanTarget.contains(cleanCandidate)) {
        final sim = cleanCandidate.length < cleanTarget.length
            ? cleanCandidate.length / cleanTarget.length
            : cleanTarget.length / cleanCandidate.length;
        if (sim > bestTitleSim) bestTitleSim = sim;
      } else {
        final sim = _wordOverlap(cleanTarget, cleanCandidate);
        if (sim > bestTitleSim) bestTitleSim = sim;
      }
    }

    double yearBonus = 0;
    if (targetYear != null && candidateYear != null) {
      if (targetYear == candidateYear) {
        yearBonus = 0.2;
      } else if ((targetYear - candidateYear).abs() == 1) {
        yearBonus = 0.1;
      } else {
        yearBonus = -0.2;
      }
    }

    return (bestTitleSim * 0.8) + yearBonus;
  }

  static double _wordOverlap(String s1, String s2) {
    final words1 = s1.split(RegExp(r'\s+')).where((w) => w.length > 2).toSet();
    final words2 = s2.split(RegExp(r'\s+')).where((w) => w.length > 2).toSet();
    if (words1.isEmpty || words2.isEmpty) return 0;
    final intersection = words1.intersection(words2);
    return (2.0 * intersection.length) / (words1.length + words2.length);
  }

  static String _normalizeString(String str) {
    return str
        .toLowerCase()
        .replaceAll(RegExp(r'[áàäâ]'), 'a')
        .replaceAll(RegExp(r'[éèëê]'), 'e')
        .replaceAll(RegExp(r'[íìïî]'), 'i')
        .replaceAll(RegExp(r'[óòöô]'), 'o')
        .replaceAll(RegExp(r'[úùüû]'), 'u')
        .replaceAll('ñ', 'n')
        .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
        .trim();
  }
}

class _TmdbInfo {
  final List<String> titles;
  final int? year;

  const _TmdbInfo({required this.titles, this.year});
}

class _CanelaMatch {
  final String id;
  final String slug;
  final String title;
  final int? year;

  const _CanelaMatch({
    required this.id,
    required this.slug,
    required this.title,
    this.year,
  });
}

class _CanelaEpisode {
  final String id;
  final String slug;
  final int episodeNum;

  const _CanelaEpisode({
    required this.id,
    required this.slug,
    required this.episodeNum,
  });
}

class CanelaServer {
  final String serverName;
  final String url;
  final String calidad;
  final String idioma;
  final int tmdbId;
  final int season;
  final int episode;

  const CanelaServer({
    required this.serverName,
    required this.url,
    this.calidad = '1080p',
    this.idioma = 'LAT',
    required this.tmdbId,
    required this.season,
    required this.episode,
  });

  Map<String, dynamic> toModalMap() {
    return {
      'servidor_nombre': 'Canela · $serverName',
      'servidor_url': url,
      'calidad': calidad,
      'idioma': idioma,
      'estado': 'activo',
      'es_canela': true,
      'tmdb_id': tmdbId,
      'season': season,
      'episode': episode,
      'fuente': 'canela',
    };
  }
}

class _CanelaSession {
  final String oAuthToken;
  final String qpatToken;
  final String deviceId;
  final String secretB64;
  final int expiresAt;

  const _CanelaSession({
    required this.oAuthToken,
    required this.qpatToken,
    required this.deviceId,
    required this.secretB64,
    required this.expiresAt,
  });
}
