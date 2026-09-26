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

  FilmoticAppInfo({
    required this.minVersion,
    required this.latestVersion,
    required this.updateUrl,
    required this.updateMessage,
    required this.forceUpdate,
  });

  factory FilmoticAppInfo.fromMap(Map<String, dynamic>? map, {String fallbackMinVersion = '1.0.0'}) {
    final m = map ?? {};
    final minVer = (m['min_version'] ?? fallbackMinVersion).toString();
    final latestVer = (m['latest_version'] ?? minVer).toString();
    final url = (m['update_url'] ??
            'https://github.com/Pokaysplash/filmotic-releases/releases/latest/download/filmotic.apk')
        .toString();
    final msg = (m['update_message'] ??
            'Hay una nueva versión de Filmotic disponible. Actualiza para disfrutar de las últimas mejoras.')
        .toString();
    final force = m['force_update'] == true;

    return FilmoticAppInfo(
      minVersion: minVer,
      latestVersion: latestVer,
      updateUrl: url,
      updateMessage: msg,
      forceUpdate: force,
    );
  }

  Map<String, dynamic> toMap() => {
        'min_version': minVersion,
        'latest_version': latestVersion,
        'update_url': updateUrl,
        'update_message': updateMessage,
        'force_update': forceUpdate,
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
  final String defaultCountry;
  final String defaultLanguage;
  final List<String> categories;
  final List<String> featuredChannels;
  final bool epgEnabled;
  final int epgRefreshHours;
  final int epgWindowHours;

  FilmoticLiveTvConfig({
    required this.enabled,
    required this.defaultCountry,
    required this.defaultLanguage,
    required this.categories,
    required this.featuredChannels,
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
            'Caracol TV',
            'RCN',
            'NTN24',
            'DW Español',
            'France 24 Español',
            'Bloomberg TV',
            'Red Bull TV',
            'NASA TV'
          ];

    return FilmoticLiveTvConfig(
      enabled: m['enabled'] != false,
      defaultCountry: (m['default_country'] ?? 'co').toString().toLowerCase(),
      defaultLanguage: (m['default_language'] ?? 'spa').toString().toLowerCase(),
      categories: cats,
      featuredChannels: featured,
      epgEnabled: m['epg_enabled'] != false,
      epgRefreshHours: (m['epg_refresh_hours'] is int) ? m['epg_refresh_hours'] : 6,
      epgWindowHours: (m['epg_window_hours'] is int) ? m['epg_window_hours'] : 48,
    );
  }

  Map<String, dynamic> toMap() => {
        'enabled': enabled,
        'default_country': defaultCountry,
        'default_language': defaultLanguage,
        'categories': categories,
        'featured_channels': featuredChannels,
        'epg_enabled': epgEnabled,
        'epg_refresh_hours': epgRefreshHours,
        'epg_window_hours': epgWindowHours,
      };

  static FilmoticLiveTvConfig get defaults => FilmoticLiveTvConfig(
        enabled: true,
        defaultCountry: 'co',
        defaultLanguage: 'spa',
        categories: ['sports', 'news', 'kids', 'movies', 'documentary', 'music'],
        featuredChannels: [
          'Caracol TV',
          'RCN',
          'NTN24',
          'DW Español',
          'France 24 Español',
          'Bloomberg TV',
          'Red Bull TV',
          'NASA TV'
        ],
        epgEnabled: true,
        epgRefreshHours: 6,
        epgWindowHours: 48,
      );
}

/// Modelo de configuración remota descargable sin recompilar.
class FilmoticRemoteConfig {
  final int version;
  final Map<String, dynamic> ads;
  final List<String> enabledSources;
  final List<String> disabledSources;
  final Map<String, dynamic> messages;
  final FilmoticAppInfo app;
  final FilmoticLiveTvConfig liveTv;

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
  }) : liveTv = liveTv ?? FilmoticLiveTvConfig.defaults;

  factory FilmoticRemoteConfig.fromMap(Map<String, dynamic> map) {
    final adsMap = map['ads'] is Map ? Map<String, dynamic>.from(map['ads']) : <String, dynamic>{};
    final sourcesMap = map['sources'] is Map ? map['sources'] : {};
    final enabled = sourcesMap['enabled'] is List
        ? (sourcesMap['enabled'] as List).map((e) => e.toString().toLowerCase()).toList()
        : <String>['cinecalidad', 'thanhdattoday', 'animeflv', 'serieskao', 'tioplus', 'cuevana', 'pelisplus', 'cinehax'];
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

    return FilmoticRemoteConfig(
      version: (map['version'] is int) ? map['version'] : 1,
      ads: adsMap,
      enabledSources: enabled,
      disabledSources: disabled,
      messages: messagesMap,
      app: appInfo,
      liveTv: liveTvConf,
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
          'cinecalidad',
          'thanhdattoday',
          'animeflv',
          'serieskao',
          'tioplus',
          'cuevana',
          'pelisplus',
          'cinehax'
        ],
        disabledSources: [],
        messages: {
          'maintenance': null,
          'welcome_banner': null,
        },
        app: FilmoticAppInfo.defaults,
        liveTv: FilmoticLiveTvConfig.defaults,
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
  static const int _kTtlHours = 24;

  final StoreRef<String, dynamic> _store = stringMapStoreFactory.store(_kConfigStore);

  FilmoticRemoteConfig _config = FilmoticRemoteConfig.defaults;
  FilmoticRemoteConfig get config => _config;

  bool isSourceEnabled(String sourceId) {
    final id = sourceId.toLowerCase();
    if (_config.disabledSources.contains(id)) return false;
    if (_config.enabledSources.isNotEmpty) {
      return _config.enabledSources.contains(id);
    }
    return true;
  }

  Future<void> initialize({String? customUrl}) async {
    // 1. Cargar caché Sembast existente
    await _loadFromCache();

    // 2. Descargar si el TTL ha expirado o no hay caché
    _fetchAndCache(customUrl ?? _kConfigUrl);
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

  Future<bool> _fetchAndCache(String url) async {
    try {
      final db = await AppDatabase.instance.database;
      final tsRecord = await _store.record(_kTimestampKey).get(db);
      final lastFetched = tsRecord != null ? DateTime.tryParse(tsRecord.toString()) : null;

      if (lastFetched != null && DateTime.now().difference(lastFetched).inHours < _kTtlHours) {
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
      // Limpiar prefijos como 'v' o sufijos como '+1'
      final clean1 = v1.trim().replaceFirst(RegExp(r'^v'), '').split('+').first.split('-').first.trim();
      final clean2 = v2.trim().replaceFirst(RegExp(r'^v'), '').split('+').first.split('-').first.trim();

      final parts1 = clean1.split('.').map((p) => int.tryParse(p) ?? 0).toList();
      final parts2 = clean2.split('.').map((p) => int.tryParse(p) ?? 0).toList();

      final maxLen = parts1.length > parts2.length ? parts1.length : parts2.length;
      for (int i = 0; i < maxLen; i++) {
        final p1 = i < parts1.length ? parts1[i] : 0;
        final p2 = i < parts2.length ? parts2[i] : 0;
        if (p1 < p2) return -1;
        if (p1 > p2) return 1;
      }
      return 0;
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
