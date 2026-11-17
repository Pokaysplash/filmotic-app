import 'package:flutter_test/flutter_test.dart';
import 'package:lol/core/services/server_loader_shared.dart';
import 'package:lol/core/services/subtitle_auto_loader.dart';
import 'package:lol/data/datasources/remote/tmdb/tmdb_christmas_api.dart';
import 'package:lol/features/live_tv/data/m3u_parser.dart';

void main() {
  group('ServerLoaderPrefs original language resolution', () {
    test('original mode picks Spanish when content original_language is es', () {
      const prefs = ServerLoaderPrefs(idiomaAudioPredeterminado: 'original');
      expect(prefs.preferredIdiomaCodeFor('es'), 'es_MX');
      expect(prefs.idiomaFallbackOrderFor('es'), ['es_MX', 'es_ES', 'en_US']);
    });

    test('original mode picks en_US/VOSE when content original_language is en or ja', () {
      const prefs = ServerLoaderPrefs(idiomaAudioPredeterminado: 'original');
      expect(prefs.preferredIdiomaCodeFor('en'), 'en_US');
      expect(prefs.preferredIdiomaCodeFor('ja'), 'en_US');
      expect(prefs.idiomaFallbackOrderFor('ja'), ['en_US', 'es_MX', 'es_ES']);
    });

    test('languageDisplayName maps common TMDB codes', () {
      expect(ServerLoaderPrefs.languageDisplayName('en'), 'Inglés');
      expect(ServerLoaderPrefs.languageDisplayName('es'), 'Español');
      expect(ServerLoaderPrefs.languageDisplayName('ja'), 'Japonés');
      expect(ServerLoaderPrefs.languageDisplayName('ko'), 'Coreano');
    });
  });

  group('SubtitleAutoLoader.shouldAutoEnable', () {
    test('enables subtitles when preferredAudio is original and server is not Spanish', () {
      expect(
        SubtitleAutoLoader.shouldAutoEnable(
          serverIdioma: 'en_US',
          originalLanguage: 'en',
          preferredAudio: 'original',
        ),
        isTrue,
      );
    });

    test('does not auto-enable subtitles for Spanish audio when preferredAudio is latino', () {
      expect(
        SubtitleAutoLoader.shouldAutoEnable(
          serverIdioma: 'es_MX',
          originalLanguage: 'en',
          preferredAudio: 'latino',
        ),
        isFalse,
      );
    });

    test('enables subtitles when fallback server is non-Spanish', () {
      expect(
        SubtitleAutoLoader.shouldAutoEnable(
          serverIdioma: 'en_US',
          originalLanguage: 'en',
          preferredAudio: 'latino',
        ),
        isTrue,
      );
    });

    test('cleanSubtitleText strips broken HTML/ASS tags and entities', () {
      const dirty =
          r'{\an8}<font face="Trebuchet MS">Hola &amp; bienvenidos</font> face="Arial">!';
      expect(
        SubtitleAutoLoader.cleanSubtitleText(dirty),
        'Hola & bienvenidos !',
      );
    });
  });

  group('M3UParser', () {
    test('parses valid EXTINF channel entries', () {
      const sample = '''
#EXTM3U
#EXTINF:-1 tvg-id="rcn" tvg-name="Canal RCN" group-title="General" tvg-country="CO",Canal RCN
https://rcntv-rcnmas-1-us.roku.wurl.tv/playlist.m3u8
''';
      final result = M3UParser.parse(sample, 'test');
      expect(result.channels, hasLength(1));
      expect(result.channels.first.name, 'Canal RCN');
      expect(
        result.channels.first.streamUrl,
        'https://rcntv-rcnmas-1-us.roku.wurl.tv/playlist.m3u8',
      );
    });
  });

  group('TmdbChristmasApi.mergeUniqueChristmasMovies', () {
    test('deduplicates by id across batches and sorts by popularity', () {
      final batch1 = [
        {
          'id': 771,
          'title': 'Home Alone',
          'poster_path': '/a.jpg',
          'popularity': 120.0,
          'genre_ids': [35, 10751],
        },
        {
          'id': 562,
          'title': 'Die Hard',
          'poster_path': '/b.jpg',
          'popularity': 90.0,
          'genre_ids': [28, 53],
        },
      ];
      final batch2 = [
        {
          'id': 771,
          'title': 'Home Alone (dup)',
          'poster_path': '/a.jpg',
          'popularity': 999.0,
          'genre_ids': [35, 10751],
        },
        {
          'id': 508965,
          'title': 'Klaus',
          'poster_path': '/c.jpg',
          'popularity': 150.0,
          'genre_ids': [16, 10751],
        },
      ];

      final merged = TmdbChristmasApi.mergeUniqueChristmasMovies([batch1, batch2]);
      expect(merged.map((m) => m['id']).toList(), [508965, 771, 562]);

      final kidsOnly = TmdbChristmasApi.mergeUniqueChristmasMovies(
        [batch1, batch2],
        isKids: true,
      );
      expect(kidsOnly.map((m) => m['id']).toList(), [508965, 771]);
    });
  });
}

