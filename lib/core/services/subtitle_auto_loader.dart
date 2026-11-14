import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/tmdb_apis.dart';

class AutoLoadedSubtitle {
  final String id;
  final String lang;
  final String label;
  final String rawContent;

  const AutoLoadedSubtitle({
    required this.id,
    required this.lang,
    required this.label,
    required this.rawContent,
  });
}

/// Servicio ligero para resolver IMDb ID desde TMDB y descargar automáticamente
/// el mejor subtítulo de OpenSubtitles v3 cuando el contenido se reproduce en
/// idioma original o subtitulado.
class SubtitleAutoLoader {
  SubtitleAutoLoader._();
  static final SubtitleAutoLoader instance = SubtitleAutoLoader._();

  final Map<String, String> _imdbCache = {};

  /// Limpia etiquetas HTML/ASS/VTT y restos de formato roto (ej. `face="Trebuchet MS">`)
  /// para mostrar subtítulos siempre en texto limpio.
  static String cleanSubtitleText(String text) {
    return text
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll(RegExp(r'\{\\[^}]*\}'), '')
        .replaceAll(
          RegExp(r'\b(?:face|color|size)\s*=\s*"[^"]*"\s*>?', caseSensitive: false),
          '',
        )
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .trim();
  }

  /// Determina si conviene activar subtítulos automáticamente según el servidor
  /// que se está reproduciendo, el idioma original y las preferencias.
  static bool shouldAutoEnable({
    required String? serverIdioma,
    required String? originalLanguage,
    required String preferredAudio,
  }) {
    final srv = (serverIdioma ?? '').trim().toLowerCase();
    final orig = (originalLanguage ?? '').trim().toLowerCase();
    final pref = preferredAudio.trim().toLowerCase();

    final serverIsSpanish = srv == 'es_mx' ||
        srv == 'es_es' ||
        srv == 'latino' ||
        srv == 'castellano' ||
        srv == 'es' ||
        srv == 'spa';

    if (pref == 'subtitulado' || pref == 'original') {
      if (!serverIsSpanish) return true;
      // Si el usuario eligió original y la obra NO es originalmente en español,
      // pero el servidor tampoco está marcado como español, activar subtítulos.
      return orig.isNotEmpty && orig != 'es' && !serverIsSpanish;
    }

    // Incluso en modo automático, si el único servidor que funcionó está en
    // inglés/japonés/original (no español), activar subtítulos automáticamente.
    return srv == 'en_us' ||
        srv == 'subtitulado' ||
        srv == 'original' ||
        srv == 'ja' ||
        srv == 'ko';
  }

  /// Resuelve y descarga el mejor subtítulo para el contenido actual.
  Future<AutoLoadedSubtitle?> fetchBestSubtitle({
    required int? tmdbId,
    String? imdbId,
    required bool isMovie,
    int season = 1,
    int episode = 1,
  }) async {
    try {
      String? resolvedImdb = imdbId?.trim();
      if ((resolvedImdb == null || resolvedImdb.isEmpty) &&
          tmdbId != null &&
          tmdbId > 0) {
        resolvedImdb = await _resolveImdbId(tmdbId: tmdbId, isMovie: isMovie);
      }
      if (resolvedImdb == null || resolvedImdb.isEmpty) return null;

      final prefs = await SharedPreferences.getInstance();
      final subPref =
          (prefs.getString('subtitulo_predeterminado') ?? 'spa').toLowerCase();
      final wantEnglish =
          subPref == 'en' || subPref == 'eng' || subPref == 'en_us';

      final url = isMovie
          ? 'https://opensubtitles-v3.strem.io/subtitles/movie/$resolvedImdb.json'
          : 'https://opensubtitles-v3.strem.io/subtitles/series/$resolvedImdb:$season:$episode.json';

      final res = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 7));
      if (res.statusCode != 200) return null;

      final data = jsonDecode(utf8.decode(res.bodyBytes));
      final list = (data['subtitles'] as List?)
              ?.whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList() ??
          [];
      if (list.isEmpty) return null;

      Map<String, dynamic>? picked;
      final preferredLangs = wantEnglish
          ? ['eng', 'en', 'spa', 'es', 'pob']
          : ['spa', 'es', 'lat', 'es-la', 'eng', 'en'];

      for (final target in preferredLangs) {
        for (final s in list) {
          final l = (s['lang'] ?? '').toString().toLowerCase();
          if (l == target || l.startsWith(target)) {
            picked = s;
            break;
          }
        }
        if (picked != null) break;
      }
      picked ??= list.first;

      final subUrl = (picked['url'] ?? '').toString().trim();
      if (subUrl.isEmpty) return null;

      final subRes = await http
          .get(Uri.parse(subUrl))
          .timeout(const Duration(seconds: 8));
      if (subRes.statusCode != 200 || subRes.bodyBytes.isEmpty) return null;

      String text;
      try {
        text = utf8.decode(subRes.bodyBytes);
      } catch (_) {
        text = latin1.decode(subRes.bodyBytes);
      }

      final lang = (picked['lang'] ?? (wantEnglish ? 'eng' : 'spa')).toString();
      return AutoLoadedSubtitle(
        id: (picked['id'] ?? subUrl).toString(),
        lang: lang,
        label: lang.startsWith('en') ? 'Inglés (Auto)' : 'Español (Auto)',
        rawContent: text,
      );
    } catch (e) {
      debugPrint('[SubtitleAutoLoader] Error: $e');
      return null;
    }
  }

  Future<String?> _resolveImdbId({
    required int tmdbId,
    required bool isMovie,
  }) async {
    final key = '${isMovie ? 'm' : 't'}_$tmdbId';
    if (_imdbCache.containsKey(key)) return _imdbCache[key];

    try {
      final apiKey = await TmdbApis.getApiKey();
      if (apiKey.isEmpty) return null;
      final type = isMovie ? 'movie' : 'tv';
      final url =
          'https://api.themoviedb.org/3/$type/$tmdbId/external_ids?api_key=$apiKey';
      final res = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final imdb = (data['imdb_id'] ?? '').toString().trim();
      if (imdb.isNotEmpty) {
        _imdbCache[key] = imdb;
        return imdb;
      }
    } catch (_) {}
    return null;
  }
}

