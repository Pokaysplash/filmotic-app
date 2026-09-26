import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
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
  String? lastEpgUrl;

  /// Carga canales aplicando filtros y caché Sembast.
  Future<List<LiveChannel>> loadChannels({
    String? country,
    String? language,
    String? group,
    bool forceRefresh = false,
  }) async {
    final listKey = _buildListKey(country: country, language: language, group: group);

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
            return _sortChannels(cached.map((m) => LiveChannel.fromMap(m)).toList());
          }
        }
      }
    }

    // 2. Descargar lista de iptv-org
    final url = _buildDownloadUrl(country: country, language: language, group: group);
    try {
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        final body = utf8.decode(res.bodyBytes);
        final parseResult = M3UParser.parse(body, url);
        if (parseResult.epgUrl != null && parseResult.epgUrl!.isNotEmpty) {
          lastEpgUrl = parseResult.epgUrl;
        }

        if (parseResult.channels.isNotEmpty) {
          // Guardar en caché Sembast
          final maps = parseResult.channels.map((c) => c.toMap()).toList();
          await AppDatabase.instance.saveLiveChannels(listKey, maps);
          return _sortChannels(parseResult.channels);
        }
      }
    } catch (e) {
      debugPrint('[LiveTvService] Error descargando $url: $e');
    }

    // 3. Fallback a caché previa si la descarga falló
    final fallbackCached = await AppDatabase.instance.getCachedLiveChannels(
      country: country,
      language: language,
      group: group,
    );
    if (fallbackCached.isNotEmpty) {
      return _sortChannels(fallbackCached.map((m) => LiveChannel.fromMap(m)).toList());
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

  List<LiveChannel> _sortChannels(List<LiveChannel> channels) {
    final featured = RemoteConfigService.instance.config.liveTv.featuredChannels;
    if (featured.isEmpty) return channels;

    final featuredSet = featured.map((e) => e.toLowerCase()).toSet();
    final featuredList = <LiveChannel>[];
    final regularList = <LiveChannel>[];

    for (final ch in channels) {
      if (featuredSet.contains(ch.name.toLowerCase())) {
        featuredList.add(ch);
      } else {
        regularList.add(ch);
      }
    }

    return [...featuredList, ...regularList];
  }
}
