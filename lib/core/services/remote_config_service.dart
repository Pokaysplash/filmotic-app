import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:sembast/sembast.dart';
import '../storage/app_database.dart';

/// Configuración de la aplicación y versionado en GitHub Releases.
class FilmoticAppInfo {
  final String minVersion;
  final String latestVersion;
  final String updateUrl;
  final String updateMessage;
  final bool forceUpdate;
  final bool isBeta;

  FilmoticAppInfo({
    required this.minVersion,
    required this.latestVersion,
    required this.updateUrl,
    required this.updateMessage,
    required this.forceUpdate,
    this.isBeta = false,
  });

  factory FilmoticAppInfo.fromMap(Map<String, dynamic>? map, {String fallbackMinVersion = '1.0.0'}) {
    final m = map ?? {};
    final minVer = (m['min_version'] ?? fallbackMinVersion).toString();
    final latestVer = (m['latest_version'] ?? minVer).toString();
    final url = (m['update_url'] ??
            'https://github.com/Pokaysplash/filmotic-app/releases/latest/download/filmotic.apk')
        .toString();
    final msg = (m['update_message'] ??
            'Hay una nueva versión de Filmotic disponible. Actualiza para disfrutar de las últimas mejoras.')
        .toString();
    final force = m['force_update'] == true;
    final beta = m['is_beta'] == true;

    return FilmoticAppInfo(
      minVersion: minVer,
      latestVersion: latestVer,
      updateUrl: url,
      updateMessage: msg,
      forceUpdate: force,
      isBeta: beta,
    );
  }

  Map<String, dynamic> toMap() => {
        'min_version': minVersion,
        'latest_version': latestVersion,
        'update_url': updateUrl,
        'update_message': updateMessage,
        'force_update': forceUpdate,
        'is_beta': isBeta,
      };

  static FilmoticAppInfo get defaults => FilmoticAppInfo(
        minVersion: '1.0.0',
        latestVersion: '1.0.0',
        updateUrl:
            'https://github.com/Pokaysplash/filmotic-releases/releases/latest/download/filmotic.apk',
        updateMessage:
            'Hay una nueva versión de Filmotic disponible. Actualiza para disfrutar de las últimas mejoras.',
        forceUpdate: false,
      );
}

class FilmoticLiveTvConfig {
  final bool enabled;
  final String sourcePriority;
  final String customM3uUrl;
  final List<String> fallbackUrls;
  final String defaultCountry;
  final String defaultLanguage;
  final List<String> categories;
  final List<String> featuredChannels;
  final List<Map<String, dynamic>> verifiedSources;
  final bool epgEnabled;
  final int epgRefreshHours;
  final int epgWindowHours;

  FilmoticLiveTvConfig({
    required this.enabled,
    required this.sourcePriority,
    required this.customM3uUrl,
    required this.fallbackUrls,
    required this.defaultCountry,
    required this.defaultLanguage,
    required this.categories,
    required this.featuredChannels,
    this.verifiedSources = const [],
    required this.epgEnabled,
    required this.epgRefreshHours,
    required this.epgWindowHours,
  });

  factory FilmoticLiveTvConfig.fromMap(Map<String, dynamic>? map) {
    final m = map ?? {};
    final cats = m['categories'] is List
        ? (m['categories'] as List).map((e) => e.toString().toLowerCase()).toList()
        : <String>['sports', 'news', 'kids', 'movies', 'documentary', 'music'];
    final featured = m['featured_channels'] is List
        ? (m['featured_channels'] as List).map((e) => e.toString()).toList()
        : <String>[
            'Disney Channel',
            'Caracol TV',
            'RCN',
            'Canal 1',
            'Cablenoticias',
            'NTN24',
            'DW Español',
            'France 24 Español',
            'Bloomberg TV',
            'Red Bull TV',
            'NASA TV'
          ];
    final verified = m['verified_sources'] is List
        ? (m['verified_sources'] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList()
        : defaults.verifiedSources;
        
    final fallback = m['fallback_urls'] is List
        ? (m['fallback_urls'] as List).map((e) => e.toString()).toList()
        : <String>[
            "https://iptv-org.github.io/iptv/countries/co.m3u",
            "https://iptv-org.github.io/iptv/languages/spa.m3u"
          ];

    return FilmoticLiveTvConfig(
      enabled: m['enabled'] != false,
      sourcePriority: (m['source_priority'] ?? 'filmotic_master').toString(),
      customM3uUrl: (m['custom_m3u_url'] ?? 'https://raw.githubusercontent.com/Pokaysplash/filmotic-app/main/docs/filmotic_playlist.m3u').toString(),
      fallbackUrls: fallback,
      defaultCountry: (m['default_country'] ?? 'co').toString().toLowerCase(),
      defaultLanguage: (m['default_language'] ?? 'spa').toString().toLowerCase(),
      categories: cats,
      featuredChannels: featured,
      verifiedSources: verified,
      epgEnabled: m['epg_enabled'] != false,
      epgRefreshHours: (m['epg_refresh_hours'] is int) ? m['epg_refresh_hours'] : 6,
      epgWindowHours: (m['epg_window_hours'] is int) ? m['epg_window_hours'] : 48,
    );
  }

  Map<String, dynamic> toMap() => {
        'enabled': enabled,
        'source_priority': sourcePriority,
        'custom_m3u_url': customM3uUrl,
        'fallback_urls': fallbackUrls,
        'default_country': defaultCountry,
        'default_language': defaultLanguage,
        'categories': categories,
        'featured_channels': featuredChannels,
        'verified_sources': verifiedSources,
        'epg_enabled': epgEnabled,
        'epg_refresh_hours': epgRefreshHours,
        'epg_window_hours': epgWindowHours,
      };

  static FilmoticLiveTvConfig get defaults => FilmoticLiveTvConfig(
        enabled: true,
        sourcePriority: 'filmotic_master',
        customM3uUrl: 'https://raw.githubusercontent.com/Pokaysplash/filmotic-app/main/docs/filmotic_playlist.m3u',
        fallbackUrls: [
          "https://iptv-org.github.io/iptv/countries/co.m3u",
          "https://iptv-org.github.io/iptv/languages/spa.m3u"
        ],
        defaultCountry: 'co',
        defaultLanguage: 'spa',
        categories: ['sports', 'news', 'kids', 'movies', 'documentary', 'music'],
        featuredChannels: [
          'Disney Channel',
          'Caracol TV',
          'RCN',
          'Canal 1',
          'Cablenoticias',
          'NTN24',
          'DW Español',
          'France 24 Español',
          'Bloomberg TV',
          'Red Bull TV',
          'NASA TV'
        ],
        verifiedSources: [
          {
            'name': 'Canal RCN',
            'aliases': ['rcn', 'canal rcn', 'canalrcn'],
            'logo': 'https://i.imgur.com/5PhTaHp.png',
            'group': 'General',
            'country': 'CO',
            'streams': [
              'http://181.78.211.244:8005/play/a09t/index.m3u8',
              'https://rcntv-rcnmas-1-us.roku.wurl.tv/playlist.m3u8',
              'http://181.78.17.228:8081/RCN-HD/index.m3u8',
              'http://138.121.15.230:9002/RCN/index.m3u8',
            ],
          },
          {
            'name': 'Caracol TV',
            'aliases': ['caracol', 'caracol tv', 'caracoltv'],
            'logo': 'https://i.imgur.com/4q2T2n6.png',
            'group': 'General',
            'country': 'CO',
            'streams': [
              'http://181.78.211.244:8005/play/a020/index.m3u8',
              'http://181.79.86.130:8000/play/a077/index.m3u8',
              'http://181.78.17.228:8081/CARACOL-HD/index.m3u8',
              'http://138.121.15.230:9002/CARACOL/index.m3u8',
            ],
          },
          {
            'name': 'Noticias RCN',
            'aliases': ['noticias rcn', 'rcn noticias'],
            'logo': 'https://i.imgur.com/FMX4QCM.png',
            'group': 'News',
            'country': 'CO',
            'streams': [
              'https://jmp2.uk/plu-67d9b0ebc290c9499046e88f.m3u8',
            ],
          },
          {
            'name': 'Cablenoticias',
            'aliases': ['cablenoticias', 'cable noticias', 'cablenoticias (1080p)'],
            'logo': 'https://i.imgur.com/sWjXjU6.png',
            'group': 'News',
            'country': 'CO',
            'streams': [
              'http://181.78.211.244:8005/play/a09u/index.m3u8',
              'http://181.78.17.228:8081/CABLENOTICIAS-HD/index.m3u8',
            ],
          },
        ],
        epgEnabled: true,
        epgRefreshHours: 6,
        epgWindowHours: 48,
      );
}

/// Modelo de configuración remota descargable sin recompilar.
class ServerPriorityConfig {
  final List<String> preferredSources;
  final List<String> preferredLanguages;
  final List<String> preferredQuality;

  const ServerPriorityConfig({
    this.preferredSources = const ['cinecalidad', 'thanhdattoday'],
    this.preferredLanguages = const ['es', 'es-lat', 'es-mx', 'es_MX', 'es_ES'],
    this.preferredQuality = const ['1080p', '720p'],
  });

  factory ServerPriorityConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const ServerPriorityConfig();
    return ServerPriorityConfig(
      preferredSources: map['preferred_sources'] is List 
          ? (map['preferred_sources'] as List).map((e) => e.toString().toLowerCase()).toList() 
          : const ['cinecalidad', 'thanhdattoday'],
      preferredLanguages: map['preferred_languages'] is List 
          ? (map['preferred_languages'] as List).map((e) => e.toString().toLowerCase()).toList() 
          : const ['es', 'es-lat', 'es-mx', 'es_MX', 'es_ES'],
      preferredQuality: map['preferred_quality'] is List 
          ? (map['preferred_quality'] as List).map((e) => e.toString().toLowerCase()).toList() 
          : const ['1080p', '720p'],
    );
  }
}

class FilmoticPlayerConfig {
  final int reconnectTimeoutSeconds;
  final bool fallbackToLowerQualityFirst;
  final bool showReconnectOverlay;
  final bool preValidateServersOnContentOpen;
  final int preValidationTimeoutSeconds;
  final int preValidationConcurrency;
  final int preValidationCacheTtlMinutes;

  const FilmoticPlayerConfig({
    this.reconnectTimeoutSeconds = 60,
    this.fallbackToLowerQualityFirst = true,
    this.showReconnectOverlay = true,
    this.preValidateServersOnContentOpen = false,
    this.preValidationTimeoutSeconds = 15,
    this.preValidationConcurrency = 5,
    this.preValidationCacheTtlMinutes = 15,
  });

  factory FilmoticPlayerConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const FilmoticPlayerConfig();
    return FilmoticPlayerConfig(
      reconnectTimeoutSeconds: (map['reconnect_timeout_seconds'] as num?)?.toInt() ?? 60,
      fallbackToLowerQualityFirst: map['fallback_to_lower_quality_first'] != false,
      showReconnectOverlay: map['show_reconnect_overlay'] != false,
      preValidateServersOnContentOpen: map['pre_validate_servers_on_content_open'] == true,
      preValidationTimeoutSeconds: (map['pre_validation_timeout_seconds'] as num?)?.toInt() ?? 15,
      preValidationConcurrency: (map['pre_validation_concurrency'] as num?)?.toInt() ?? 5,
      preValidationCacheTtlMinutes: (map['pre_validation_cache_ttl_minutes'] as num?)?.toInt() ?? 15,
    );
  }

  Map<String, dynamic> toMap() => {
    'reconnect_timeout_seconds': reconnectTimeoutSeconds,
    'fallback_to_lower_quality_first': fallbackToLowerQualityFirst,
    'show_reconnect_overlay': showReconnectOverlay,
    'pre_validate_servers_on_content_open': preValidateServersOnContentOpen,
    'pre_validation_timeout_seconds': preValidationTimeoutSeconds,
    'pre_validation_concurrency': preValidationConcurrency,
    'pre_validation_cache_ttl_minutes': preValidationCacheTtlMinutes,
  };
}

class FilmoticRemoteConfig {
  final int version;
  final Map<String, dynamic> ads;
  final List<String> enabledSources;
  final List<String> disabledSources;
  final Map<String, dynamic> messages;
  final FilmoticAppInfo app;
  final FilmoticLiveTvConfig liveTv;
  final ServerPriorityConfig serverPriority;
  final FilmoticPlayerConfig player;

  /// Compatibilidad hacia atrás con min_app_version
  String get minAppVersion => app.minVersion;

  FilmoticRemoteConfig({
    required this.version,
    required this.ads,
    required this.enabledSources,
    required this.disabledSources,
    required this.messages,
    required this.app,
    FilmoticLiveTvConfig? liveTv,
    ServerPriorityConfig? serverPriority,
    FilmoticPlayerConfig? player,
  }) : liveTv = liveTv ?? FilmoticLiveTvConfig.defaults,
       serverPriority = serverPriority ?? const ServerPriorityConfig(),
       player = player ?? const FilmoticPlayerConfig();

  factory FilmoticRemoteConfig.fromMap(Map<String, dynamic> map) {
    final adsMap = map['ads'] is Map ? Map<String, dynamic>.from(map['ads']) : <String, dynamic>{};
    final sourcesMap = map['sources'] is Map ? map['sources'] : {};
    final enabled = sourcesMap['enabled'] is List
        ? (sourcesMap['enabled'] as List).map((e) => e.toString().toLowerCase()).toList()
        : <String>['cuevana', 'pelisplus', 'serieskao', 'tioplus', 'animeflv', 'cinehax', 'canela', 'seriesflix', 'cineby'];
    final disabled = sourcesMap['disabled'] is List
        ? (sourcesMap['disabled'] as List).map((e) => e.toString().toLowerCase()).toList()
        : <String>[];
    final messagesMap = map['messages'] is Map ? Map<String, dynamic>.from(map['messages']) : <String, dynamic>{};
    final fallbackMin = map['min_app_version']?.toString() ?? '1.0.0';
    final appInfo = map['app'] is Map
        ? FilmoticAppInfo.fromMap(Map<String, dynamic>.from(map['app']), fallbackMinVersion: fallbackMin)
        : FilmoticAppInfo.fromMap(null, fallbackMinVersion: fallbackMin);
    final liveTvConf = map['live_tv'] is Map
        ? FilmoticLiveTvConfig.fromMap(Map<String, dynamic>.from(map['live_tv']))
        : FilmoticLiveTvConfig.defaults;
    final serverPriorityConf = map['server_priority'] is Map
        ? ServerPriorityConfig.fromMap(Map<String, dynamic>.from(map['server_priority']))
        : const ServerPriorityConfig();
    final playerConf = map['player'] is Map
        ? FilmoticPlayerConfig.fromMap(Map<String, dynamic>.from(map['player']))
        : const FilmoticPlayerConfig();

    return FilmoticRemoteConfig(
      version: (map['version'] is int) ? map['version'] : 1,
      ads: adsMap,
      enabledSources: enabled,
      disabledSources: disabled,
      messages: messagesMap,
      app: appInfo,
      liveTv: liveTvConf,
      serverPriority: serverPriorityConf,
      player: playerConf,
    );
  }

  Map<String, dynamic> toMap() => {
        'version': version,
        'ads': ads,
        'sources': {
          'enabled': enabledSources,
          'disabled': disabledSources,
        },
        'messages': messages,
        'app': app.toMap(),
        'min_app_version': app.minVersion,
        'live_tv': liveTv.toMap(),
        'player': player.toMap(),
      };

  static FilmoticRemoteConfig get defaults => FilmoticRemoteConfig(
        version: 1,
        ads: {
          'adsterra_banner_key': 'b40d7be87e3186a983946460caa04802',
          'adsterra_native_container_id': 'container-512fc1ea8b3c9db09a992edbaf608772',
          'adsterra_native_script_url': 'https://pl31504029.profitableratecpmnetwork.com/512fc1ea8b3c9db09a992edbaf608772/invoke.js',
          'hilltopads_vast_url': 'PENDIENTE',
        },
        enabledSources: [
          'cuevana',
          'pelisplus',
          'serieskao',
          'tioplus',
          'animeflv',
          'cinehax',
          'canela',
          'seriesflix',
          'cineby',
        ],
        disabledSources: [
          'telemundo',
        ],
        messages: {
          'maintenance': null,
          'welcome_banner': null,
        },
        app: FilmoticAppInfo.defaults,
        liveTv: FilmoticLiveTvConfig.defaults,
        player: const FilmoticPlayerConfig(),
      );
}

/// Servicio que gestiona la configuración remota con caché Sembast de 24h.
class RemoteConfigService {
  static final RemoteConfigService instance = RemoteConfigService._internal();
  factory RemoteConfigService() => instance;
  RemoteConfigService._internal();

  static const String _kConfigUrl =
      'https://raw.githubusercontent.com/Pokaysplash/filmotic-app/main/filmotic_config.json';
  static const String _kConfigStore = 'filmotic_remote_config';
  static const String _kConfigKey = 'cached_config';
  static const String _kTimestampKey = 'cached_config_timestamp';
  static const String _kDismissedVersionKey = 'dismissed_version';
  static const int _kTtlHours = 6;
  Timer? _autoRepairTimer;

  final StoreRef<String, dynamic> _store = stringMapStoreFactory.store(_kConfigStore);

  FilmoticRemoteConfig _config = FilmoticRemoteConfig.defaults;
  FilmoticRemoteConfig get config => _config;

  bool isSourceEnabled(String sourceId) {
    final id = sourceId.toLowerCase().trim();
    if (_config.disabledSources.contains(id)) return false;
    if (id == 'canelatv' && _config.disabledSources.contains('canela')) return false;
    if (id == 'canela' && _config.disabledSources.contains('canelatv')) return false;

    if (_config.enabledSources.isNotEmpty) {
      if (_config.enabledSources.contains(id)) return true;
      if (id == 'canelatv' && _config.enabledSources.contains('canela')) return true;
      if (id == 'canela' && _config.enabledSources.contains('canelatv')) return true;
      return false;
    }
    return true;
  }

  Future<void> initialize({String? customUrl}) async {
    // 1. Cargar caché Sembast existente
    await _loadFromCache();

    // 2. Descargar si el TTL ha expirado o no hay caché
    await _fetchAndCache(customUrl ?? _kConfigUrl);

    // 3. Iniciar auto-reparación cada 6 horas
    _autoRepairTimer?.cancel();
    _autoRepairTimer = Timer.periodic(const Duration(hours: 6), (_) {
      _fetchAndCache(customUrl ?? _kConfigUrl, force: true);
    });
  }

  /// Fuerza la actualización de la configuración desde el servidor ignorando el TTL y la caché.
  Future<bool> forceRefresh({String? customUrl}) async {
    return _fetchAndCache(customUrl ?? _kConfigUrl, force: true);
  }

  Future<void> _loadFromCache() async {
    try {
      final db = await AppDatabase.instance.database;
      final cached = await _store.record(_kConfigKey).get(db);
      if (cached != null && cached is Map) {
        _config = FilmoticRemoteConfig.fromMap(Map<String, dynamic>.from(cached));
      }
    } catch (e) {
      debugPrint('[RemoteConfig] Error leyendo caché Sembast: $e');
    }
  }

  Future<bool> _fetchAndCache(String url, {bool force = false}) async {
    try {
      final db = await AppDatabase.instance.database;
      final tsRecord = await _store.record(_kTimestampKey).get(db);
      final lastFetched = tsRecord != null ? DateTime.tryParse(tsRecord.toString()) : null;

      if (!force && lastFetched != null && DateTime.now().difference(lastFetched).inHours < _kTtlHours) {
        debugPrint(
            '[RemoteConfig] Usando configuración en caché (TTL activo: ${_kTtlHours - DateTime.now().difference(lastFetched).inHours}h restantes)');
        return true;
      }

      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        if (decoded is Map<String, dynamic>) {
          _config = FilmoticRemoteConfig.fromMap(decoded);
          await _store.record(_kConfigKey).put(db, _config.toMap());
          await _store.record(_kTimestampKey).put(db, DateTime.now().toIso8601String());
          debugPrint('[RemoteConfig] Configuración actualizada y guardada en Sembast.');
          return true;
        }
      }
    } catch (e) {
      debugPrint('[RemoteConfig] Fallo de conexión ($e). Usando valores predeterminados o caché.');
    }
    return false;
  }

  /// Recupera la versión que el usuario descartó pulsar "Más tarde"
  Future<String?> getDismissedVersion() async {
    try {
      final db = await AppDatabase.instance.database;
      final record = await _store.record(_kDismissedVersionKey).get(db);
      if (record != null && record is Map) {
        return record['version']?.toString();
      }
    } catch (e) {
      debugPrint('[RemoteConfig] Error leyendo versión descartada: $e');
    }
    return null;
  }

  /// Guarda la versión descartada para no volver a molestar con la misma versión
  Future<void> setDismissedVersion(String version) async {
    try {
      final db = await AppDatabase.instance.database;
      await _store.record(_kDismissedVersionKey).put(db, {'version': version});
    } catch (e) {
      debugPrint('[RemoteConfig] Error guardando versión descartada: $e');
    }
  }

  /// Compara dos versiones semánticas (ej: '1.0.1' vs '1.0.0').
  /// Retorna:
  ///  -1 si v1 < v2
  ///   0 si v1 == v2
  ///   1 si v1 > v2
  static int compareVersions(String v1, String v2) {
    try {
      final s1 = v1.trim().replaceFirst(RegExp(r'^v'), '').split('+').first.trim();
      final s2 = v2.trim().replaceFirst(RegExp(r'^v'), '').split('+').first.trim();

      final base1 = s1.split('-').first.trim();
      final base2 = s2.split('-').first.trim();

      final parts1 = base1.split('.').map((p) => int.tryParse(p) ?? 0).toList();
      final parts2 = base2.split('.').map((p) => int.tryParse(p) ?? 0).toList();

      final maxLen = parts1.length > parts2.length ? parts1.length : parts2.length;
      for (int i = 0; i < maxLen; i++) {
        final p1 = i < parts1.length ? parts1[i] : 0;
        final p2 = i < parts2.length ? parts2[i] : 0;
        if (p1 < p2) return -1;
        if (p1 > p2) return 1;
      }

      // Si las partes base son idénticas, evaluar sufijos pre-release (ej. -beta.4 vs -beta.5)
      final hasSuffix1 = s1.contains('-');
      final hasSuffix2 = s2.contains('-');
      if (!hasSuffix1 && !hasSuffix2) return 0;
      if (!hasSuffix1 && hasSuffix2) return 1; // 1.0.0 > 1.0.0-beta.5
      if (hasSuffix1 && !hasSuffix2) return -1; // 1.0.0-beta.5 < 1.0.0

      // Ambas tienen sufijo: comparar el número dentro del sufijo
      final sub1 = s1.substring(s1.indexOf('-') + 1);
      final sub2 = s2.substring(s2.indexOf('-') + 1);

      final num1 = int.tryParse(sub1.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      final num2 = int.tryParse(sub2.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      if (num1 < num2) return -1;
      if (num1 > num2) return 1;

      return sub1.compareTo(sub2);
    } catch (_) {
      return 0;
    }
  }

  /// Retorna true si se requiere actualización forzada / bloqueante:
  /// - min_version > version_instalada O
  /// - force_update es true
  bool isMandatoryUpdateRequired(String currentVersion) {
    if (_config.app.forceUpdate) return true;
    return compareVersions(currentVersion, _config.app.minVersion) < 0;
  }

  /// Retorna true si hay una nueva versión opcional disponible que no ha sido descartada
  bool isOptionalUpdateAvailable(String currentVersion, {String? dismissedVersion}) {
    if (isMandatoryUpdateRequired(currentVersion)) return false;
    final hasNewer = compareVersions(currentVersion, _config.app.latestVersion) < 0;
    if (!hasNewer) return false;
    if (dismissedVersion != null && dismissedVersion == _config.app.latestVersion) {
      return false;
    }
    return true;
  }

  /// Compatibilidad hacia atrás
  bool isUpdateRequired(String currentVersion) => isMandatoryUpdateRequired(currentVersion);
}
