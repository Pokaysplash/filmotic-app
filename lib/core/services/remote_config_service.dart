import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:sembast/sembast.dart';
import '../storage/app_database.dart';

/// Modelo de configuración remota descargable sin recompilar.
class FilmoticRemoteConfig {
  final int version;
  final Map<String, dynamic> ads;
  final List<String> enabledSources;
  final List<String> disabledSources;
  final Map<String, dynamic> messages;
  final String minAppVersion;

  FilmoticRemoteConfig({
    required this.version,
    required this.ads,
    required this.enabledSources,
    required this.disabledSources,
    required this.messages,
    required this.minAppVersion,
  });

  factory FilmoticRemoteConfig.fromMap(Map<String, dynamic> map) {
    final adsMap = map['ads'] is Map ? Map<String, dynamic>.from(map['ads']) : <String, dynamic>{};
    final sourcesMap = map['sources'] is Map ? map['sources'] : {};
    final enabled = sourcesMap['enabled'] is List
        ? (sourcesMap['enabled'] as List).map((e) => e.toString().toLowerCase()).toList()
        : <String>['cinecalidad', 'thanhdattoday', 'animeflv', 'serieskao', 'tioplus', 'cuevana'];
    final disabled = sourcesMap['disabled'] is List
        ? (sourcesMap['disabled'] as List).map((e) => e.toString().toLowerCase()).toList()
        : <String>['pelisplus'];
    final messagesMap = map['messages'] is Map ? Map<String, dynamic>.from(map['messages']) : <String, dynamic>{};
    final minVer = map['min_app_version']?.toString() ?? '1.0.0';

    return FilmoticRemoteConfig(
      version: (map['version'] is int) ? map['version'] : 1,
      ads: adsMap,
      enabledSources: enabled,
      disabledSources: disabled,
      messages: messagesMap,
      minAppVersion: minVer,
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
        'min_app_version': minAppVersion,
      };

  static FilmoticRemoteConfig get defaults => FilmoticRemoteConfig(
        version: 1,
        ads: {
          'adsterra_banner_id': 'ADSTERRA_DEFAULT_320x50',
          'hilltopads_vast_url': 'https://hilltopads.example.com/vast/sample.xml',
        },
        enabledSources: ['cinecalidad', 'thanhdattoday', 'animeflv', 'serieskao', 'tioplus', 'cuevana'],
        disabledSources: ['pelisplus'],
        messages: {
          'maintenance': null,
          'welcome_banner': null,
        },
        minAppVersion: '1.0.0',
      );
}

/// Servicio que gestiona la configuración remota con caché Sembast de 24h.
class RemoteConfigService {
  static final RemoteConfigService instance = RemoteConfigService._internal();
  factory RemoteConfigService() => instance;
  RemoteConfigService._internal();

  static const String _kConfigUrl =
      'https://raw.githubusercontent.com/Filmotic/config/main/filmotic_config.json';
  static const String _kConfigStore = 'filmotic_remote_config';
  static const String _kConfigKey = 'cached_config';
  static const String _kTimestampKey = 'cached_config_timestamp';
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

  /// Comprueba si la versión instalada es menor que minAppVersion
  bool isUpdateRequired(String currentVersion) {
    try {
      final cleanCurrent = currentVersion.split(' ').first.trim();
      final currentParts = cleanCurrent.split('.').map((p) => int.tryParse(p) ?? 0).toList();
      final minParts = _config.minAppVersion.split('.').map((p) => int.tryParse(p) ?? 0).toList();

      for (int i = 0; i < minParts.length; i++) {
        final cur = i < currentParts.length ? currentParts[i] : 0;
        final req = minParts[i];
        if (cur < req) return true;
        if (cur > req) return false;
      }
    } catch (_) {}
    return false;
  }
}
