import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast.dart';
import 'package:sembast/sembast_io.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class LocalAccount {
  final String id;
  final String? email;
  final String nombre;
  final String createdAt;

  LocalAccount({
    required this.id,
    this.email,
    required this.nombre,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'email': email,
        'nombre': nombre,
        'created_at': createdAt,
      };

  factory LocalAccount.fromMap(Map<String, dynamic> map) => LocalAccount(
        id: map['id']?.toString() ?? '',
        email: map['email']?.toString(),
        nombre: map['nombre']?.toString() ?? 'Mi Cuenta',
        createdAt: map['created_at']?.toString() ?? DateTime.now().toIso8601String(),
      );
}

class LocalProfile {
  final String id;
  final String cuentaId;
  final String nombre;
  final String avatar;
  final bool esInfantil;
  final String? pin;
  final String createdAt;

  LocalProfile({
    required this.id,
    required this.cuentaId,
    required this.nombre,
    required this.avatar,
    this.esInfantil = false,
    this.pin,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'cuenta_id': cuentaId,
        'nombre': nombre,
        'avatar': avatar,
        'es_infantil': esInfantil,
        'pin': pin,
        'created_at': createdAt,
      };

  factory LocalProfile.fromMap(Map<String, dynamic> map) => LocalProfile(
        id: map['id']?.toString() ?? '',
        cuentaId: map['cuenta_id']?.toString() ?? '',
        nombre: map['nombre']?.toString() ?? 'Perfil',
        avatar: (map['avatar'] != null &&
                (map['avatar'].toString().contains('unsplash.com') ||
                    map['avatar'].toString().isEmpty))
            ? 'assets/avatars/avatar_1.png'
            : (map['avatar']?.toString() ?? 'assets/avatars/avatar_1.png'),
        esInfantil: map['es_infantil'] == true || map['es_infantil'] == 1,
        pin: map['pin']?.toString(),
        createdAt: map['created_at']?.toString() ?? DateTime.now().toIso8601String(),
      );

  LocalProfile copyWith({
    String? nombre,
    String? avatar,
    bool? esInfantil,
    String? pin,
    bool clearPin = false,
  }) {
    String? cleanPin = pin?.trim();
    if (cleanPin != null && cleanPin.isNotEmpty && !RegExp(r'^\d{4}$').hasMatch(cleanPin)) {
      cleanPin = null;
    }
    return LocalProfile(
      id: id,
      cuentaId: cuentaId,
      nombre: nombre ?? this.nombre,
      avatar: avatar ?? this.avatar,
      esInfantil: esInfantil ?? this.esInfantil,
      pin: clearPin ? null : (pin != null ? cleanPin : this.pin),
      createdAt: createdAt,
    );
  }
}

class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  static const String _dbName = 'pelisapp_sembast.db';
  static const String _kActiveProfileKey = 'active_profile_id';
  static const String _kActiveAccountKey = 'active_account_id';

  Database? _db;

  // Stores Sembast
  final _cuentasStore = stringMapStoreFactory.store('cuentas');
  final _perfilesStore = stringMapStoreFactory.store('perfiles');
  final _favoritosStore = stringMapStoreFactory.store('favoritos');
  final _historialStore = stringMapStoreFactory.store('historial');
  final _cacheTmdbStore = stringMapStoreFactory.store('cache_tmdb');
  final _liveChannelsStore = stringMapStoreFactory.store('live_channels');
  final _liveListsCacheStore = stringMapStoreFactory.store('live_lists_cache');
  final _epgProgramsStore = stringMapStoreFactory.store('epg_programs');
  final _epgMetaStore = stringMapStoreFactory.store('epg_meta');
  final _serverValidationStore = stringMapStoreFactory.store('server_validation_cache');

  final ValueNotifier<LocalProfile?> activeProfileNotifier =
      ValueNotifier<LocalProfile?>(null);

  LocalProfile? _cachedActiveProfile;
  LocalProfile? get activeProfile => _cachedActiveProfile;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final docsDir = await getApplicationSupportDirectory();
    final dbPath = p.join(docsDir.path, _dbName);
    final db = await databaseFactoryIo.openDatabase(dbPath);
    return db;
  }

  /// Inicializa la base de datos y garantiza que existan cuenta y perfil por defecto.
  Future<void> init() async {
    final db = await database;

    // Verificar si hay cuentas
    final accounts = await _cuentasStore.find(db);
    String defaultAccId;
    if (accounts.isEmpty) {
      defaultAccId = const Uuid().v4();
      final defaultAcc = LocalAccount(
        id: defaultAccId,
        nombre: 'Cuenta Principal',
        email: null,
        createdAt: DateTime.now().toIso8601String(),
      );
      await _cuentasStore.record(defaultAccId).put(db, defaultAcc.toMap());
    } else {
      defaultAccId = accounts.first.key;
    }

    // Verificar si hay perfiles para esa cuenta
    final profiles = await _perfilesStore.find(
      db,
      finder: Finder(
        filter: Filter.equals('cuenta_id', defaultAccId),
      ),
    );

    if (profiles.isEmpty) {
      final defaultProfId = const Uuid().v4();
      final defaultProf = LocalProfile(
        id: defaultProfId,
        cuentaId: defaultAccId,
        nombre: 'Usuario',
        avatar: 'assets/avatars/avatar_1.png',
        esInfantil: false,
        pin: null,
        createdAt: DateTime.now().toIso8601String(),
      );
      await _perfilesStore.record(defaultProfId).put(db, defaultProf.toMap());
    }

    // Cargar perfil activo de SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final savedProfileId = prefs.getString(_kActiveProfileKey);
    if (savedProfileId != null) {
      final snap = await _perfilesStore.record(savedProfileId).get(db);
      if (snap != null) {
        _cachedActiveProfile = LocalProfile.fromMap(snap);
        activeProfileNotifier.value = _cachedActiveProfile;
      }
    }

    if (_cachedActiveProfile == null) {
      final all = await getProfiles();
      if (all.isNotEmpty) {
        await setActiveProfile(all.first);
      }
    }
  }

  // ══════════════════════════════════════════════════════════════
  // CUENTAS
  // ══════════════════════════════════════════════════════════════

  Future<List<LocalAccount>> getAccounts() async {
    final db = await database;
    final records = await _cuentasStore.find(db);
    return records.map((r) => LocalAccount.fromMap(r.value)).toList();
  }

  Future<LocalAccount?> getAccount(String id) async {
    final db = await database;
    final map = await _cuentasStore.record(id).get(db);
    if (map == null) return null;
    return LocalAccount.fromMap(map);
  }

  Future<LocalAccount> createAccount({required String nombre, String? email}) async {
    final db = await database;
    final id = const Uuid().v4();
    final acc = LocalAccount(
      id: id,
      nombre: nombre.trim(),
      email: email?.trim(),
      createdAt: DateTime.now().toIso8601String(),
    );
    await _cuentasStore.record(id).put(db, acc.toMap());
    return acc;
  }

  Future<void> updateAccount(LocalAccount acc) async {
    final db = await database;
    await _cuentasStore.record(acc.id).put(db, acc.toMap());
  }

  // ══════════════════════════════════════════════════════════════
  // PERFILES (Máximo 5 perfiles)
  // ══════════════════════════════════════════════════════════════

  Future<List<LocalProfile>> getProfiles({String? cuentaId}) async {
    final db = await database;
    Finder? finder;
    if (cuentaId != null) {
      finder = Finder(filter: Filter.equals('cuenta_id', cuentaId));
    }
    final records = await _perfilesStore.find(db, finder: finder);
    return records.map((r) => LocalProfile.fromMap(r.value)).toList();
  }

  Future<LocalProfile?> getProfile(String id) async {
    final db = await database;
    final map = await _perfilesStore.record(id).get(db);
    if (map == null) return null;
    return LocalProfile.fromMap(map);
  }

  Future<LocalProfile> createProfile({
    String? cuentaId,
    required String nombre,
    required String avatar,
    bool esInfantil = false,
    String? pin,
  }) async {
    final db = await database;
    final accounts = await getAccounts();
    final targetCuentaId = cuentaId ?? (accounts.isNotEmpty ? accounts.first.id : 'default_acc');

    // Comprobar límite de 5 perfiles
    final existing = await getProfiles(cuentaId: targetCuentaId);
    if (existing.length >= 5) {
      throw Exception('Límite de 5 perfiles alcanzado para esta cuenta.');
    }

    final id = const Uuid().v4();
    final profile = LocalProfile(
      id: id,
      cuentaId: targetCuentaId,
      nombre: nombre.trim(),
      avatar: avatar.trim(),
      esInfantil: esInfantil,
      pin: (pin != null && pin.trim().length == 4) ? pin.trim() : null,
      createdAt: DateTime.now().toIso8601String(),
    );

    await _perfilesStore.record(id).put(db, profile.toMap());
    return profile;
  }

  Future<void> updateProfile(LocalProfile profile) async {
    final db = await database;
    await _perfilesStore.record(profile.id).put(db, profile.toMap());
    if (_cachedActiveProfile?.id == profile.id) {
      _cachedActiveProfile = profile;
      activeProfileNotifier.value = profile;
    }
  }

  Future<void> deleteProfile(String profileId) async {
    final db = await database;
    await _perfilesStore.record(profileId).delete(db);

    // Borrar favoritos asociados al perfil
    await _favoritosStore.delete(
      db,
      finder: Finder(filter: Filter.equals('perfil_id', profileId)),
    );

    // Borrar historial asociado al perfil
    await _historialStore.delete(
      db,
      finder: Finder(filter: Filter.equals('perfil_id', profileId)),
    );

    if (_cachedActiveProfile?.id == profileId) {
      final remaining = await getProfiles();
      if (remaining.isNotEmpty) {
        await setActiveProfile(remaining.first);
      } else {
        _cachedActiveProfile = null;
        activeProfileNotifier.value = null;
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_kActiveProfileKey);
      }
    }
  }

  Future<void> setActiveProfile(LocalProfile profile) async {
    _cachedActiveProfile = profile;
    activeProfileNotifier.value = profile;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kActiveProfileKey, profile.id);
  }

  bool verifyPin(LocalProfile profile, String inputPin) {
    final stored = profile.pin?.trim();
    if (stored == null || stored.isEmpty || stored.length != 4) return false;
    return stored == inputPin.trim();
  }

  // ══════════════════════════════════════════════════════════════
  // FAVORITOS (por perfil activo)
  // ══════════════════════════════════════════════════════════════

  String _favKey(String perfilId, int contenidoId) => '${perfilId}_$contenidoId';

  Future<List<Map<String, dynamic>>> getFavorites({String? perfilId}) async {
    final targetId = perfilId ?? _cachedActiveProfile?.id;
    if (targetId == null) return [];
    final db = await database;
    final records = await _favoritosStore.find(
      db,
      finder: Finder(
        filter: Filter.equals('perfil_id', targetId),
        sortOrders: [SortOrder('timestamp', false)],
      ),
    );
    return records.map((r) => Map<String, dynamic>.from(r.value)).toList();
  }

  Future<bool> isFavorite(int contenidoId, {String? perfilId}) async {
    final targetId = perfilId ?? _cachedActiveProfile?.id;
    if (targetId == null) return false;
    final db = await database;
    final key = _favKey(targetId, contenidoId);
    final record = await _favoritosStore.record(key).get(db);
    return record != null;
  }

  Future<bool> toggleFavorite(Map<String, dynamic> item, {String? perfilId}) async {
    final targetId = perfilId ?? _cachedActiveProfile?.id;
    if (targetId == null) return false;

    final contenidoId = item['idcontenido'] as int? ??
        item['contenido_id'] as int? ??
        item['tmdb_id'] as int? ??
        item['idtmdb'] as int? ??
        int.tryParse(item['id']?.toString() ?? '') ??
        0;
    if (contenidoId == 0) return false;

    final db = await database;
    final key = _favKey(targetId, contenidoId);
    final exists = await _favoritosStore.record(key).get(db) != null;

    if (exists) {
      await _favoritosStore.record(key).delete(db);
      return false; // Removido
    } else {
      final titulo = (item['titulo'] ?? item['title'] ?? item['name'] ?? 'Sin título').toString().trim();
      final poster = item['poster'] ?? item['poster_path'] ?? item['imagen'];
      final backdrop = item['backdrop'] ?? item['backdrop_path'];
      final rawTipo = (item['tipo'] ?? item['type'] ?? item['media_type'] ?? item['mediaType'] ?? 'movie').toString().toLowerCase();
      final tipo = (rawTipo == 'tv' || rawTipo == 'serie') ? 'serie' : 'pelicula';
      final year = item['año'] ?? item['year'] ?? item['release_date'] ?? item['first_air_date'];
      final tmdbId = item['tmdb_id'] ?? item['idtmdb'] ?? (contenidoId > 0 ? contenidoId : null);
      final voteAverage = item['vote_average'];
      final bool completos = (titulo.isNotEmpty && titulo != 'Sin título' && titulo != 'N/A') &&
          (poster != null && poster.toString().isNotEmpty && poster.toString() != 'null');

      final data = {
        'id': key,
        'perfil_id': targetId,
        'idcontenido': contenidoId,
        'contenido_id': contenidoId,
        'titulo': titulo,
        'title': titulo,
        'poster': poster,
        'poster_path': poster,
        'backdrop': backdrop,
        'backdrop_path': backdrop,
        'tipo': tipo,
        'año': year,
        'year': year,
        'tmdb_id': tmdbId,
        'vote_average': voteAverage,
        'timestamp': DateTime.now().toIso8601String(),
        'metadatos_completos': completos,
        'metadata': item,
      };
      await _favoritosStore.record(key).put(db, data);
      return true; // Agregado
    }
  }

  Future<void> updateFavorite(Map<String, dynamic> item, {String? perfilId}) async {
    final targetId = perfilId ?? _cachedActiveProfile?.id;
    if (targetId == null) return;
    final contenidoId = item['idcontenido'] as int? ??
        item['contenido_id'] as int? ??
        item['tmdb_id'] as int? ??
        int.tryParse(item['id']?.toString() ?? '') ??
        0;
    if (contenidoId == 0) return;
    final db = await database;
    final key = _favKey(targetId, contenidoId);
    final existing = await _favoritosStore.record(key).get(db);
    if (existing != null) {
      final updated = Map<String, dynamic>.from(existing)..addAll(item);
      await _favoritosStore.record(key).put(db, updated);
    }
  }

  Future<void> removeFavorite(int contenidoId, {String? perfilId}) async {
    final targetId = perfilId ?? _cachedActiveProfile?.id;
    if (targetId == null) return;
    final db = await database;
    final key = _favKey(targetId, contenidoId);
    await _favoritosStore.record(key).delete(db);
  }

  // ══════════════════════════════════════════════════════════════
  // HISTORIAL (por perfil activo)
  // ══════════════════════════════════════════════════════════════

  String _histKey(String perfilId, int contenidoId, String episodioId) =>
      '${perfilId}_${contenidoId}_$episodioId';

  Future<List<Map<String, dynamic>>> getHistory({String? perfilId}) async {
    final targetId = perfilId ?? _cachedActiveProfile?.id;
    if (targetId == null) return [];
    final db = await database;
    final records = await _historialStore.find(
      db,
      finder: Finder(
        filter: Filter.equals('perfil_id', targetId),
        sortOrders: [SortOrder('fecha', false)],
      ),
    );
    return records.map((r) => Map<String, dynamic>.from(r.value)).toList();
  }

  Future<void> saveHistory({
    String? perfilId,
    required int contenidoId,
    String episodioId = 'movie',
    required int progresoSegundos,
    int duracionTotal = 0,
    int? temporada,
    int? capitulo,
    String? titulo,
    String? poster,
    String? tipo,
    String? videoUrl,
    int? tmdbId,
  }) async {
    final targetId = perfilId ?? _cachedActiveProfile?.id;
    if (targetId == null || contenidoId <= 0) return;

    final db = await database;
    final key = _histKey(targetId, contenidoId, episodioId);
    final data = {
      'id': key,
      'perfil_id': targetId,
      'contenido_id': contenidoId,
      'idcontenido': contenidoId,
      'episodio_id': episodioId,
      'progreso_segundos': progresoSegundos,
      'segundo': progresoSegundos, // compatibilidad con player
      'duracion_total': duracionTotal,
      'total': duracionTotal,
      'fecha': DateTime.now().toIso8601String(),
      'timestamp': DateTime.now().toIso8601String(),
      'temporada': temporada,
      'capitulo': capitulo,
      'titulo': titulo,
      'title': titulo,
      'poster': poster,
      'tipo': tipo ?? 'movie',
      'media_type': tipo ?? 'movie',
      'videoUrl': videoUrl,
      'tmdb_id': tmdbId ?? contenidoId,
    };

    await _historialStore.record(key).put(db, data);
  }

  Future<Map<String, dynamic>?> getHistoryItem(
    int contenidoId, {
    String episodioId = 'movie',
    String? perfilId,
  }) async {
    final targetId = perfilId ?? _cachedActiveProfile?.id;
    if (targetId == null) return null;
    final db = await database;
    final key = _histKey(targetId, contenidoId, episodioId);
    final record = await _historialStore.record(key).get(db);
    return record != null ? Map<String, dynamic>.from(record) : null;
  }

  Future<void> clearHistory({String? perfilId}) async {
    final targetId = perfilId ?? _cachedActiveProfile?.id;
    if (targetId == null) return;
    final db = await database;
    await _historialStore.delete(
      db,
      finder: Finder(filter: Filter.equals('perfil_id', targetId)),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // CACHÉ TMDB (Sembast)
  // ══════════════════════════════════════════════════════════════

  Future<Map<String, dynamic>?> getTmdbCache(String key) async {
    final db = await database;
    final record = await _cacheTmdbStore.record(key).get(db);
    if (record == null) return null;
    return Map<String, dynamic>.from(record);
  }

  Future<void> setTmdbCache(String key, Map<String, dynamic> data) async {
    final db = await database;
    await _cacheTmdbStore.record(key).put(db, {
      ...data,
      '_cached_at': DateTime.now().toIso8601String(),
    });
  }

  // ══════════════════════════════════════════════════════════════
  // CACHÉ DE VALIDACIÓN DE SERVIDORES (TTL 1h)
  // ══════════════════════════════════════════════════════════════

  Future<Map<String, dynamic>?> getCachedServerStatus(String serverKey) async {
    try {
      final db = await database;
      final record = await _serverValidationStore.record(serverKey).get(db);
      if (record == null) return null;
      final cachedAtStr = record['cached_at']?.toString();
      if (cachedAtStr == null) return null;
      final cachedAt = DateTime.tryParse(cachedAtStr);
      if (cachedAt == null || DateTime.now().difference(cachedAt).inHours >= 1) {
        return null; // Expirado (TTL 1h)
      }
      return Map<String, dynamic>.from(record);
    } catch (_) {
      return null;
    }
  }

  Future<void> setCachedServerStatus(
    String serverKey, {
    required bool isValid,
    bool hasAudio = true,
  }) async {
    try {
      final db = await database;
      await _serverValidationStore.record(serverKey).put(db, {
        'is_valid': isValid,
        'has_audio': hasAudio,
        'cached_at': DateTime.now().toIso8601String(),
      });
    } catch (_) {}
  }

  // ══════════════════════════════════════════════════════════════
  // EXPORT / IMPORT (Transferencia P2P FASE 3)
  // ══════════════════════════════════════════════════════════════

  Future<Map<String, dynamic>> exportDataForTransfer({String? cuentaId}) async {
    final db = await database;
    final accounts = await getAccounts();
    final targetAcc = cuentaId != null
        ? accounts.firstWhere((a) => a.id == cuentaId, orElse: () => accounts.first)
        : accounts.first;

    final profiles = await getProfiles(cuentaId: targetAcc.id);
    final profileIds = profiles.map((p) => p.id).toSet();

    final allFavs = await _favoritosStore.find(db);
    final favs = allFavs
        .where((r) => profileIds.contains(r.value['perfil_id']))
        .map((r) => r.value)
        .toList();

    final allHist = await _historialStore.find(db);
    final hist = allHist
        .where((r) => profileIds.contains(r.value['perfil_id']))
        .map((r) => r.value)
        .toList();

    return {
      'version': 1,
      'exported_at': DateTime.now().toIso8601String(),
      'account': targetAcc.toMap(),
      'profiles': profiles.map((p) => p.toMap()).toList(),
      'favorites': favs,
      'history': hist,
    };
  }

  Future<void> importTransferData(Map<String, dynamic> payload) async {
    final db = await database;
    final accountMap = payload['account'] as Map<String, dynamic>?;
    final profilesList = (payload['profiles'] as List?) ?? [];
    final favoritesList = (payload['favorites'] as List?) ?? [];
    final historyList = (payload['history'] as List?) ?? [];

    if (accountMap != null) {
      final acc = LocalAccount.fromMap(accountMap);
      await _cuentasStore.record(acc.id).put(db, acc.toMap());
    }

    for (final p in profilesList) {
      if (p is Map) {
        final map = Map<String, dynamic>.from(p);
        final prof = LocalProfile.fromMap(map);
        await _perfilesStore.record(prof.id).put(db, prof.toMap());
      }
    }

    for (final f in favoritesList) {
      if (f is Map) {
        final map = Map<String, dynamic>.from(f);
        final id = map['id']?.toString() ??
            '${map['perfil_id']}_${map['contenido_id'] ?? map['idcontenido']}';
        await _favoritosStore.record(id).put(db, map);
      }
    }

    for (final h in historyList) {
      if (h is Map) {
        final map = Map<String, dynamic>.from(h);
        final id = map['id']?.toString() ??
            '${map['perfil_id']}_${map['contenido_id']}_${map['episodio_id']}';
        await _historialStore.record(id).put(db, map);
      }
    }

    // Actualizar perfil activo si no hay ninguno
    if (_cachedActiveProfile == null && profilesList.isNotEmpty) {
      final first = LocalProfile.fromMap(Map<String, dynamic>.from(profilesList.first));
      await setActiveProfile(first);
    }
  }

  // ══════════════════════════════════════════════════════════════
  // LIVE TV & EPG (Caché local Sembast)
  // ══════════════════════════════════════════════════════════════

  Future<void> saveLiveChannels(String listKey, List<Map<String, dynamic>> channels) async {
    final db = await database;
    await db.transaction((txn) async {
      for (final ch in channels) {
        final id = ch['id']?.toString() ?? '';
        if (id.isNotEmpty) {
          await _liveChannelsStore.record(id).put(txn, ch);
        }
      }
      await _liveListsCacheStore.record(listKey).put(txn, {
        'key': listKey,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'count': channels.length,
      });
    });
  }

  Future<List<Map<String, dynamic>>> getCachedLiveChannels({String? country, String? language, String? group}) async {
    final db = await database;
    final records = await _liveChannelsStore.find(db);
    var list = records.map((r) => r.value).toList();
    if (country != null && country.isNotEmpty && country != 'ALL') {
      list = list.where((c) => (c['country']?.toString().toUpperCase() == country.toUpperCase())).toList();
    }
    if (language != null && language.isNotEmpty && language != 'ALL') {
      list = list.where((c) => (c['language']?.toString().toLowerCase() == language.toLowerCase())).toList();
    }
    if (group != null && group.isNotEmpty && group != 'ALL') {
      list = list.where((c) => (c['group']?.toString().toLowerCase().contains(group.toLowerCase()) == true)).toList();
    }
    return list;
  }

  Future<int?> getLiveListCacheTime(String listKey) async {
    final db = await database;
    final record = await _liveListsCacheStore.record(listKey).get(db);
    return record?['timestamp'] as int?;
  }

  Future<void> saveEpgPrograms(String channelId, List<Map<String, dynamic>> programs) async {
    final db = await database;
    await db.transaction((txn) async {
      for (final p in programs) {
        final id = p['id']?.toString() ?? '';
        if (id.isNotEmpty) {
          await _epgProgramsStore.record(id).put(txn, p);
        }
      }
      await _epgMetaStore.record(channelId).put(txn, {
        'channel_id': channelId,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
    });
  }

  Future<List<Map<String, dynamic>>> getEpgPrograms(String channelId) async {
    final db = await database;
    final records = await _epgProgramsStore.find(
      db,
      finder: Finder(
        filter: Filter.equals('channel_id', channelId),
        sortOrders: [SortOrder('start_time', true)],
      ),
    );
    return records.map((r) => r.value).toList();
  }

  Future<int?> getEpgCacheTime(String channelId) async {
    final db = await database;
    final record = await _epgMetaStore.record(channelId).get(db);
    return record?['timestamp'] as int?;
  }

  Future<void> purgeOldEpgPrograms() async {
    final db = await database;
    final cutoff = DateTime.now().toUtc().subtract(const Duration(hours: 24)).toIso8601String();
    await _epgProgramsStore.delete(
      db,
      finder: Finder(
        filter: Filter.lessThan('end_time', cutoff),
      ),
    );
  }
}
