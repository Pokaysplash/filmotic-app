import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../../../core/services/remote_config_service.dart';
import '../../../core/storage/app_database.dart';
import '../domain/channel.dart';
import 'm3u_parser.dart';

class LiveTvService {
  static final LiveTvService instance = LiveTvService._internal();
  factory LiveTvService() => instance;
  LiveTvService._internal();

  static const int _kTtlMillis = 24 * 60 * 60 * 1000; // 24h
  static const String _kCacheVersion = 'v6_aac_verified_';
  String? lastEpgUrl;

  /// Carga canales aplicando filtros y caché Sembast.
  Future<List<LiveChannel>> loadChannels({
    String? country,
    String? language,
    String? group,
    bool forceRefresh = false,
  }) async {
    final listKey = '$_kCacheVersion${_buildListKey(country: country, language: language, group: group)}';

    // 1. Verificar caché Sembast
    if (!forceRefresh) {
      final cacheTime = await AppDatabase.instance.getLiveListCacheTime(listKey);
      if (cacheTime != null) {
        final age = DateTime.now().millisecondsSinceEpoch - cacheTime;
        if (age < _kTtlMillis) {
          final cached = await AppDatabase.instance.getCachedLiveChannels(
            country: country,
            language: language,
            group: group,
          );
          if (cached.isNotEmpty) {
            final list = cached.map((m) => LiveChannel.fromMap(m)).toList();
            var enriched = _enrichWithVerifiedSources(list, country, group: group);
            if (group != null && group.isNotEmpty && group != 'ALL') {
              final filtered = enriched.where((c) => matchesCategory(c, group)).toList();
              if (filtered.isNotEmpty) enriched = filtered;
            }
            return _sortChannels(enriched);
          }
        }
      }
    }

    // 2. Obtener configuración remota
    final config = RemoteConfigService.instance.config.liveTv;
    
    // 3. Preparar e iniciar carga de lista prioritizando el asset local con Xtream Codes
    String? rawBody;
    String effectiveSource = 'assets/filmotic_playlist.m3u';

    if (config.sourcePriority == 'filmotic_master') {
      try {
        rawBody = await rootBundle.loadString('assets/filmotic_playlist.m3u');
      } catch (_) {}

      // Si existe una lista remota válida y completa en customM3uUrl (> 50KB)
      if (config.customM3uUrl.isNotEmpty) {
        try {
          final mainRes = await http.get(Uri.parse(config.customM3uUrl)).timeout(const Duration(seconds: 10));
          if (mainRes.statusCode == 200 && mainRes.bodyBytes.length > 50000) {
            rawBody = utf8.decode(mainRes.bodyBytes);
            effectiveSource = config.customM3uUrl;
          }
        } catch (_) {}
      }
    }

    // Si no usamos master o ambos fallaron, usar iptv-org fallback
    final fallbackUrl = _buildDownloadUrl(country: country, language: language, group: group);
    if (rawBody == null) {
      try {
        final fbRes = await http.get(Uri.parse(fallbackUrl)).timeout(const Duration(seconds: 12));
        if (fbRes.statusCode == 200 && fbRes.bodyBytes.isNotEmpty) {
          rawBody = utf8.decode(fbRes.bodyBytes);
          effectiveSource = fallbackUrl;
        }
      } catch (_) {}
    }

    if (rawBody != null && rawBody.isNotEmpty) {
      try {
        final parseResult = M3UParser.parse(rawBody, effectiveSource);
        if (parseResult.epgUrl != null && parseResult.epgUrl!.isNotEmpty) {
          lastEpgUrl = parseResult.epgUrl;
        }

        var channels = parseResult.channels;

        // Enriquecer con streams por país de iptv-org (agrega señales de respaldo y canales faltantes)
        final isCountry = country != null && country.isNotEmpty && country != 'ALL';
        if (isCountry) {
          final countryUrls = [
            'https://iptv-org.github.io/iptv/countries/${country.toLowerCase()}.m3u',
            'https://raw.githubusercontent.com/iptv-org/iptv/master/streams/${country.toLowerCase()}.m3u',
          ];
          for (final streamsUrl in countryUrls) {
            if (streamsUrl == effectiveSource) continue;
            try {
              final streamsRes = await http.get(Uri.parse(streamsUrl)).timeout(const Duration(seconds: 8));
              if (streamsRes.statusCode == 200) {
                final streamsBody = utf8.decode(streamsRes.bodyBytes);
                final streamsResult = M3UParser.parse(streamsBody, streamsUrl);
                final withCountry = streamsResult.channels.map((c) {
                  return (c.country == null || c.country!.isEmpty)
                      ? c.copyWith(country: country.toUpperCase())
                      : c;
                }).toList();
                channels = _mergeAlternateStreams(channels, withCountry);
              }
            } catch (_) {}
          }
        }

        // Si se especificó una categoría temática, enriquecer con iptv-org
        final hasGroup = group != null && group.isNotEmpty && group != 'ALL';
        if (hasGroup) {
          final catUrl = 'https://iptv-org.github.io/iptv/categories/${group.toLowerCase()}.m3u';
          if (catUrl != effectiveSource) {
            try {
              final catRes = await http.get(Uri.parse(catUrl)).timeout(const Duration(seconds: 8));
              if (catRes.statusCode == 200) {
                final catBody = utf8.decode(catRes.bodyBytes);
                final catResult = M3UParser.parse(catBody, catUrl);
                final esCatChannels = catResult.channels.where((c) {
                  final lang = (c.language ?? '').toLowerCase();
                  final nm = c.name.toLowerCase();
                  final ctry = (c.country ?? '').toUpperCase();
                  return lang == 'spa' || lang == 'es' || nm.contains('esp') || nm.contains('spanish') ||
                         ['CO', 'MX', 'AR', 'ES', 'CL', 'PE', 'VE', 'EC', 'UY', 'PY', 'BO'].contains(ctry);
                }).toList();
                channels = _mergeAlternateStreams(channels, esCatChannels);
              }
            } catch (_) {}
          }
        }

        // Enriquecer con listas de deportes dedicadas si se solicitó la categoría 'sports' o 'deportes'
        final isSports = group != null && (group.toLowerCase() == 'sports' || group.toLowerCase() == 'deportes');
        if (isSports) {
          final sportsUrls = [
            'https://iptv-org.github.io/iptv/categories/sports.m3u',
            'https://raw.githubusercontent.com/abusaeeidx/IPTV-Scraper-Zilla/main/combined-playlist.m3u',
          ];
          for (final sUrl in sportsUrls) {
            try {
              final sRes = await http.get(Uri.parse(sUrl)).timeout(const Duration(seconds: 10));
              if (sRes.statusCode == 200) {
                final sBody = utf8.decode(sRes.bodyBytes);
                final sResult = M3UParser.parse(sBody, sUrl);
                final sportsChannels = sResult.channels.where((c) {
                  final lang = (c.language ?? '').toLowerCase();
                  final nm = c.name.toLowerCase();
                  final grp = (c.group ?? '').toLowerCase();
                  return grp.contains('sport') || grp.contains('deport') ||
                         lang == 'spa' || lang == 'es' || nm.contains('esp') || nm.contains('spanish') ||
                         nm.contains('win') || nm.contains('espn') || nm.contains('fox') || nm.contains('tyc') || nm.contains('directv') || nm.contains('marca');
                }).toList();
                channels = _mergeAlternateStreams(channels, sportsChannels);
              }
            } catch (_) {}
          }
        }

        // Enriquecer con verified_sources configuradas remotamente (RCN, Caracol, etc.)
        channels = _enrichWithVerifiedSources(channels, country, group: group);

        if (channels.isNotEmpty) {
          // Guardar en caché Sembast
          final maps = channels.map((c) => c.toMap()).toList();
          await AppDatabase.instance.saveLiveChannels(listKey, maps);

          var result = channels;
          if (country != null && country.isNotEmpty && country != 'ALL') {
            final cUpper = country.toUpperCase();
            result = result.where((c) {
              final cCountry = c.country?.toUpperCase();
              return cCountry == cUpper || (cCountry == 'LATAM' && ['CO', 'MX', 'AR', 'CL', 'PE', 'VE', 'EC', 'UY', 'PY', 'BO', 'GT', 'PR', 'DO'].contains(cUpper));
            }).toList();
          }
          if (hasGroup) {
            result = result.where((c) => matchesCategory(c, group)).toList();
            if (result.isEmpty) result = channels; // Fallback seguro
          }
          return _sortChannels(result);
        }
      } catch (e) {
        debugPrint('[LiveTvService] Error descargando $fallbackUrl: $e');
      }
    }

    // 3. Fallback a caché previa si la descarga falló
    final fallbackCached = await AppDatabase.instance.getCachedLiveChannels(
      country: country,
      language: language,
      group: group,
    );
    if (fallbackCached.isNotEmpty) {
      final list = fallbackCached.map((m) => LiveChannel.fromMap(m)).toList();
      var enriched = _enrichWithVerifiedSources(list, country, group: group);
      if (group != null && group.isNotEmpty && group != 'ALL') {
        final filtered = enriched.where((c) => matchesCategory(c, group)).toList();
        if (filtered.isNotEmpty) enriched = filtered;
      }
      return _sortChannels(enriched);
    }

    return [];
  }

  Future<List<LiveChannel>> getChannelsByCountry(String countryCode) =>
      loadChannels(country: countryCode);

  Future<List<LiveChannel>> getChannelsByCategory(String category) =>
      loadChannels(group: category);

  Future<List<LiveChannel>> searchChannels(String query, {List<LiveChannel>? existing}) async {
    final cleanQ = query.trim().toLowerCase();
    if (cleanQ.isEmpty) return existing ?? [];

    List<LiveChannel> source = existing ?? [];
    if (source.isEmpty) {
      final cached = await AppDatabase.instance.getCachedLiveChannels();
      source = cached.map((m) => LiveChannel.fromMap(m)).toList();
    }

    return source.where((c) {
      final matchName = c.name.toLowerCase().contains(cleanQ);
      final matchGroup = c.group?.toLowerCase().contains(cleanQ) == true;
      final matchCountry = c.country?.toLowerCase() == cleanQ;
      return matchName || matchGroup || matchCountry;
    }).toList();
  }

  /// Refresca en segundo plano las listas más populares
  Future<void> refreshAll() async {
    final remote = RemoteConfigService.instance.config.liveTv;
    final defaultCountry = remote.defaultCountry;
    final defaultLang = remote.defaultLanguage;

    unawaited(loadChannels(country: defaultCountry, forceRefresh: true));
    if (defaultLang.isNotEmpty && defaultLang != 'all') {
      unawaited(loadChannels(language: defaultLang, forceRefresh: true));
    }
  }

  String _buildListKey({String? country, String? language, String? group}) {
    if (country != null && country.isNotEmpty && country != 'ALL') return 'country_$country';
    if (language != null && language.isNotEmpty && language != 'ALL') return 'lang_$language';
    if (group != null && group.isNotEmpty && group != 'ALL') return 'group_$group';
    return 'index_all';
  }

  String _buildDownloadUrl({String? country, String? language, String? group}) {
    if (country != null && country.isNotEmpty && country != 'ALL') {
      return 'https://iptv-org.github.io/iptv/countries/${country.toLowerCase()}.m3u';
    }
    if (language != null && language.isNotEmpty && language != 'ALL') {
      return 'https://iptv-org.github.io/iptv/languages/${language.toLowerCase()}.m3u';
    }
    if (group != null && group.isNotEmpty && group != 'ALL') {
      return 'https://iptv-org.github.io/iptv/categories/${group.toLowerCase()}.m3u';
    }
    return 'https://iptv-org.github.io/iptv/index.m3u';
  }

  final Map<String, bool> _channelHealth = {};
  final Map<String, bool> _streamUrlHealth = {};

  /// Verifica la disponibilidad real de un stream (descarta respuestas vacías de 0 bytes o páginas HTML de error)
  Future<bool> probeChannel(String streamUrl) async {
    final clean = streamUrl.trim();
    if (clean.isEmpty) return false;
    if (_streamUrlHealth.containsKey(clean)) {
      return _streamUrlHealth[clean]!;
    }
    try {
      final uri = Uri.parse(clean);
      final client = http.Client();
      try {
        final req = http.Request('GET', uri)
          ..headers['User-Agent'] = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
          ..headers['Accept'] = '*/*'
          ..headers['Range'] = 'bytes=0-1024';
        final streamed = await client.send(req).timeout(const Duration(milliseconds: 2500));
        final status = streamed.statusCode;
        if (status < 200 || status >= 400) {
          _streamUrlHealth[clean] = false;
          return false;
        }
        if (streamed.contentLength != null && streamed.contentLength! == 0) {
          _streamUrlHealth[clean] = false;
          return false;
        }

        // Leer los primeros bytes para confirmar que no sea un stream muerto de 0 bytes ni HTML de error
        final bytes = <int>[];
        await for (final chunk in streamed.stream.timeout(const Duration(milliseconds: 2000))) {
          bytes.addAll(chunk);
          if (bytes.length >= 256) break;
        }
        if (bytes.isEmpty) {
          _streamUrlHealth[clean] = false;
          return false;
        }

        final contentType = (streamed.headers['content-type'] ?? '').toLowerCase();
        final isM3u8 = clean.toLowerCase().contains('.m3u8') || contentType.contains('mpegurl');
        if (isM3u8 || contentType.contains('text/html')) {
          final sample = utf8.decode(bytes, allowMalformed: true).trimLeft().toLowerCase();
          if (sample.startsWith('<!doctype html') || sample.startsWith('<html') || sample.startsWith('error')) {
            _streamUrlHealth[clean] = false;
            return false;
          }
          if (isM3u8 && !sample.contains('#extm3u') && !sample.contains('#ext-x-')) {
            _streamUrlHealth[clean] = false;
            return false;
          }
        }

        _streamUrlHealth[clean] = true;
        return true;
      } finally {
        client.close();
      }
    } catch (_) {
      _streamUrlHealth[clean] = false;
      return false;
    }
  }

  /// Encuentra rápidamente el índice de la primera señal activa de un canal (saltando señales de 0 bytes o caídas)
  Future<int> findFirstWorkingStreamIndex(List<String> streams, {int startIndex = 0}) async {
    if (streams.length <= 1) return 0;
    final safeStart = startIndex.clamp(0, streams.length - 1);

    // Probar hasta 4 señales candidatas en paralelo para respuesta instantánea (< 500ms)
    final candidates = <int>[];
    for (int offset = 0; offset < streams.length && candidates.length < 4; offset++) {
      final idx = (safeStart + offset) % streams.length;
      final url = streams[idx].trim();
      if (url.isEmpty) continue;
      if (_streamUrlHealth[url] == false) continue;
      if (_streamUrlHealth[url] == true) return idx;
      candidates.add(idx);
    }

    if (candidates.isEmpty) return safeStart;

    try {
      final results = await Future.wait(
        candidates.map((idx) => probeChannel(streams[idx])),
      ).timeout(const Duration(milliseconds: 2400), onTimeout: () => List.filled(candidates.length, false));

      for (int i = 0; i < candidates.length; i++) {
        if (results[i]) {
          return candidates[i];
        }
      }
    } catch (_) {}

    return safeStart;
  }

  void markStreamUrlStatus(String streamUrl, bool isOnline) {
    final clean = streamUrl.trim();
    if (clean.isNotEmpty) {
      _streamUrlHealth[clean] = isOnline;
    }
  }

  bool? isChannelOnline(String channelId) => _channelHealth[channelId];

  void markChannelStatus(String channelId, bool isOnline) {
    _channelHealth[channelId] = isOnline;
  }

  /// Valida en segundo plano una lista de canales en lotes concurrentes
  Future<void> validateChannelsInBackground(
    List<LiveChannel> channels,
    void Function() onProgress,
  ) async {
    final toTest = channels.take(30).toList();
    for (int i = 0; i < toTest.length; i += 4) {
      final chunk = toTest.sublist(i, (i + 4 < toTest.length) ? i + 4 : toTest.length);
      await Future.wait(chunk.map((ch) async {
        if (_channelHealth.containsKey(ch.id)) return;
        bool ok = await probeChannel(ch.streamUrl);
        if (!ok && ch.allStreamUrls.length > 1) {
          final workingIdx = await findFirstWorkingStreamIndex(ch.allStreamUrls, startIndex: 1);
          ok = _streamUrlHealth[ch.allStreamUrls[workingIdx].trim()] == true;
        }
        _channelHealth[ch.id] = ok;
      }));
      onProgress();
    }
  }

  /// Enriquecer canales existentes con fuentes verificadas y canales de alta disponibilidad
  static bool _isKnownMutedStream(String url) {
    final u = url.trim().toLowerCase();
    if (u.contains('138.121.15.230:9002/') && !u.contains('win-sport')) {
      return true;
    }
    if (u.contains('181.78.17.228:8081/') ||
        u.contains('181.78.14.26:4000/') ||
        u.contains('181.78.211.244:8005/play/a09u') ||
        u.contains('190.61.47.54:8000/play/a00v') ||
        u.contains('190.109.2.92:8000/play/a010') ||
        u.contains('181.78.12.119:16123/play/ch18')) {
      return true;
    }
    return false;
  }

  List<LiveChannel> _enrichWithVerifiedSources(
    List<LiveChannel> channels,
    String? country, {
    String? group,
  }) {
    final verifiedList = RemoteConfigService.instance.config.liveTv.verifiedSources;
    if (verifiedList.isEmpty) return channels;

    final updated = List<LiveChannel>.from(channels);

    for (final v in verifiedList) {
      final vName = (v['name'] ?? '').toString();
      final vCountry = (v['country'] ?? '').toString().toUpperCase();
      final vGroup = (v['group'] ?? '').toString();

      // Si se filtra por país específico pero la fuente es de otro país, permitirla si coincide con el grupo solicitado
      if (country != null && country.isNotEmpty && country != 'ALL' && vCountry.isNotEmpty) {
        final matchesGroupFilter = group != null && group.isNotEmpty && matchesCategory(
          LiveChannel(
            id: '',
            name: vName,
            group: vGroup,
            streamUrl: '',
            sourceList: '',
            isHD: true,
          ),
          group,
        );
        if (country.toUpperCase() != vCountry && !matchesGroupFilter) {
          continue;
        }
      }

      final rawStreams = (v['streams'] as List?)
              ?.map((e) => e.toString().trim())
              .where((s) => s.isNotEmpty)
              .toList() ??
          [];
      if (rawStreams.isEmpty) continue;

      final aliases = (v['aliases'] as List?)
              ?.map((e) => e.toString().toLowerCase().trim())
              .toList() ??
          [vName.toLowerCase()];
      if (!aliases.contains(vName.toLowerCase())) aliases.add(vName.toLowerCase());

      final matchIndex = updated.indexWhere((ch) {
        final chLower = ch.name.toLowerCase();
        final chId = ch.id.toLowerCase();
        return aliases.any((a) =>
            chLower == a ||
            chLower.startsWith('$a ') ||
            chLower.startsWith('$a(') ||
            chLower.contains(a) ||
            chId.contains(a));
      });

      if (matchIndex != -1) {
        final existing = updated[matchIndex];
        final combined = <String>[];
        for (final s in rawStreams) {
          if (!combined.contains(s)) combined.add(s);
        }
        for (final s in existing.allStreamUrls) {
          if (!combined.contains(s) && !_isKnownMutedStream(s)) {
            combined.add(s);
          }
        }

        updated[matchIndex] = existing.copyWith(
          name: vName,
          logo: existing.logo ?? v['logo']?.toString(),
          streamUrl: combined.first,
          alternateUrls: combined.length > 1 ? combined.sublist(1) : [],
          isHD: true,
          group: existing.group ?? vGroup,
        );
      } else {
        final newChannel = LiveChannel(
          id: 'verified_${vName.replaceAll(' ', '_').toLowerCase()}',
          name: vName,
          logo: v['logo']?.toString(),
          group: vGroup.isNotEmpty ? vGroup : 'General',
          country: vCountry.isNotEmpty ? vCountry : 'CO',
          language: 'spa',
          streamUrl: rawStreams.first,
          alternateUrls: rawStreams.length > 1 ? rawStreams.sublist(1) : [],
          sourceList: 'verified_sources',
          isHD: true,
        );
        updated.insert(0, newChannel);
      }
    }

    return updated;
  }

  /// Clasificador y comparador de categorías para LiveChannel
  static bool matchesCategory(LiveChannel channel, String? categoryCode) {
    if (categoryCode == null ||
        categoryCode.isEmpty ||
        categoryCode == 'ALL' ||
        categoryCode == 'todas') {
      return true;
    }
    final cat = categoryCode.toLowerCase().trim();
    final group = (channel.group ?? '').toLowerCase();
    final name = channel.name.toLowerCase();

    switch (cat) {
      case 'sports':
      case 'deportes':
        return group.contains('sport') ||
            group.contains('deport') ||
            name.contains('sport') ||
            name.contains('deport') ||
            name.contains('win') ||
            name.contains('espn') ||
            name.contains('fox') ||
            name.contains('directv') ||
            name.contains('dsports') ||
            name.contains('tyc') ||
            name.contains('claro') ||
            name.contains('gol') ||
            name.contains('futbol') ||
            name.contains('racing') ||
            name.contains('nba') ||
            name.contains('tudn') ||
            name.contains('red bull');

      case 'news':
      case 'noticias':
        return group.contains('news') ||
            group.contains('noticia') ||
            name.contains('noticia') ||
            name.contains('news') ||
            name.contains('ntn24') ||
            name.contains('cablenoticias') ||
            name.contains('cable noticias') ||
            name.contains('cnn') ||
            name.contains('dw') ||
            name.contains('france 24') ||
            name.contains('telesur') ||
            name.contains('euronews') ||
            name.contains('rt') ||
            name.contains('hora 20');

      case 'kids':
      case 'infantil':
        return group.contains('kid') ||
            group.contains('infantil') ||
            group.contains('anim') ||
            name.contains('cartoon') ||
            name.contains('disney') ||
            name.contains('nickelodeon') ||
            name.contains('nick') ||
            name.contains('boing') ||
            name.contains('clan') ||
            name.contains('baby') ||
            name.contains('infantil') ||
            name.contains('discovery kids') ||
            name.contains('toonz') ||
            name.contains('anime');

      case 'movies':
      case 'peliculas':
      case 'cine':
        return group.contains('movie') ||
            group.contains('cine') ||
            group.contains('film') ||
            name.contains('cine') ||
            name.contains('movie') ||
            name.contains('film') ||
            name.contains('cinema') ||
            name.contains('hbo') ||
            name.contains('cinemax') ||
            name.contains('tnt') ||
            name.contains('star channel') ||
            name.contains('warner') ||
            name.contains('space') ||
            name.contains('universal') ||
            name.contains('paramount') ||
            name.contains('sony') ||
            name.contains('axn') ||
            name.contains('golden') ||
            name.contains('pluto tv cine') ||
            name.contains('runtime');

      case 'music':
      case 'musica':
        return group.contains('music') ||
            group.contains('musica') ||
            name.contains('music') ||
            name.contains('musica') ||
            name.contains('mtv') ||
            name.contains('htv') ||
            name.contains('vh1') ||
            name.contains('hits') ||
            name.contains('radio');

      case 'documentary':
      case 'documentales':
        return group.contains('doc') ||
            name.contains('doc') ||
            name.contains('discovery') ||
            name.contains('natgeo') ||
            name.contains('national geographic') ||
            name.contains('history') ||
            name.contains('animal planet');

      case 'nacionales':
      case 'locales':
        return name.contains('rcn') ||
            name.contains('caracol') ||
            name.contains('canal 1') ||
            name.contains('canal uno') ||
            name.contains('señal colombia') ||
            name.contains('teleantioquia') ||
            name.contains('telecaribe') ||
            name.contains('telepacifico') ||
            name.contains('telecafe') ||
            name.contains('canal tro') ||
            name.contains('citytv') ||
            name.contains('canal trece') ||
            group.contains('general');

      default:
        return group.contains(cat) || name.contains(cat);
    }
  }

  /// Combina streams alternativos descargados de la lista general y agrega canales nuevos
  List<LiveChannel> _mergeAlternateStreams(List<LiveChannel> base, List<LiveChannel> extras) {
    final map = <String, LiveChannel>{};
    for (final c in base) {
      final key = M3UParser.canonicalChannelName(c.name);
      final effKey = key.isNotEmpty ? key : c.name.toLowerCase().trim();
      map[effKey] = c;
    }

    for (final extra in extras) {
      if (extra.name.contains('[Geo-blocked]')) continue;
      final key = M3UParser.canonicalChannelName(extra.name);
      final effKey = key.isNotEmpty ? key : extra.name.toLowerCase().trim();
      if (map.containsKey(effKey)) {
        final existing = map[effKey]!;
        final existingIsLowPrio = existing.streamUrl.contains('myultratv.com:8080');
        final extraIsLowPrio = extra.streamUrl.contains('myultratv.com:8080');

        String primaryUrl = existing.streamUrl;
        final combined = <String>[];

        if (existingIsLowPrio && !extraIsLowPrio && extra.streamUrl.isNotEmpty) {
          primaryUrl = extra.streamUrl;
          for (final u in extra.alternateUrls) {
            if (u != primaryUrl && !combined.contains(u)) combined.add(u);
          }
          for (final u in existing.allStreamUrls) {
            if (u != primaryUrl && !combined.contains(u)) combined.add(u);
          }
        } else {
          combined.addAll(existing.alternateUrls);
          for (final u in extra.allStreamUrls) {
            if (u != primaryUrl && !combined.contains(u)) {
              combined.add(u);
            }
          }
        }

        map[effKey] = existing.copyWith(
          streamUrl: primaryUrl,
          alternateUrls: combined,
          isHD: existing.isHD || extra.isHD,
          logo: existing.logo ?? extra.logo,
        );
      } else {
        map[effKey] = extra;
      }
    }
    return map.values.toList();
  }

  List<LiveChannel> _sortChannels(List<LiveChannel> channels) {
    // Filtrar canales que están explícitamente marcados como geobloqueados
    final available = channels.where((c) => !c.name.contains('[Geo-blocked]')).toList();

    final featured = RemoteConfigService.instance.config.liveTv.featuredChannels;
    final featuredSet = featured.map((e) => e.toLowerCase()).toSet();
    final featuredList = <LiveChannel>[];
    final verifiedList = <LiveChannel>[];
    final regularList = <LiveChannel>[];

    for (final ch in available) {
      if (featuredSet.isNotEmpty && featuredSet.any((f) => ch.name.toLowerCase().contains(f))) {
        featuredList.add(ch);
      } else if (!ch.streamUrl.contains('myultratv.com:8080')) {
        verifiedList.add(ch);
      } else {
        regularList.add(ch);
      }
    }

    return [...featuredList, ...verifiedList, ...regularList];
  }
}
