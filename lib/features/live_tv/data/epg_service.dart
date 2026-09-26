import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../../core/services/remote_config_service.dart';
import '../../../core/storage/app_database.dart';
import '../domain/epg_program.dart';
import 'xmltv_parser.dart';

class EpgService {
  static final EpgService instance = EpgService._internal();
  factory EpgService() => instance;
  EpgService._internal();

  final Map<String, List<EpgProgram>> _inMemoryCache = {};
  final Set<String> _loadingChannels = {};

  /// Carga el EPG para una lista de canales dados sus IDs.
  Future<void> loadEpgForChannels(
    List<String> channelIds, {
    String? countryCode,
    String? customEpgUrl,
    bool forceRefresh = false,
  }) async {
    final cfg = RemoteConfigService.instance.config.liveTv;
    if (!cfg.epgEnabled) return;

    final ttlHours = cfg.epgRefreshHours;
    final ttlMillis = ttlHours * 60 * 60 * 1000;

    // Filtrar canales que no estén en caché o cuyo TTL haya expirado
    final now = DateTime.now();
    final neededChannelIds = <String>[];

    for (final chId in channelIds) {
      if (chId.isEmpty) continue;
      if (_loadingChannels.contains(chId)) continue;

      if (!forceRefresh) {
        final lastUpdate = await AppDatabase.instance.getEpgCacheTime(chId);
        if (lastUpdate != null && (now.millisecondsSinceEpoch - lastUpdate) < ttlMillis) {
          // Ya está al día en caché, cargarlo en memoria si hace falta
          if (!_inMemoryCache.containsKey(chId)) {
            final raw = await AppDatabase.instance.getEpgPrograms(chId);
            if (raw.isNotEmpty) {
              _inMemoryCache[chId] = raw.map((m) => EpgProgram.fromMap(m)).toList();
            }
          }
          continue;
        }
      }
      neededChannelIds.add(chId);
    }

    if (neededChannelIds.isEmpty) return;

    // Marcar como cargando
    _loadingChannels.addAll(neededChannelIds);

    try {
      // Determinar URLs de EPG a probar en orden
      final epgUrls = <String>[];
      if (customEpgUrl != null && customEpgUrl.isNotEmpty) {
        epgUrls.add(customEpgUrl);
      }
      final cCode = (countryCode ?? cfg.defaultCountry).toLowerCase();
      epgUrls.add('https://epg.pw/xmltv/$cCode.xml');
      epgUrls.add('https://iptv-org.github.io/epg/guides/$cCode.xml');

      String? downloadedXml;
      for (final url in epgUrls) {
        try {
          final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
          if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
            downloadedXml = utf8.decode(res.bodyBytes, allowMalformed: true);
            if (downloadedXml.contains('<programme')) {
              break;
            }
          }
        } catch (e) {
          debugPrint('Error descargando EPG desde $url: $e');
        }
      }

      if (downloadedXml != null && downloadedXml.isNotEmpty) {
        final parsed = await XmltvParser.parseXmltv(
          downloadedXml,
          filterChannelIds: neededChannelIds.toSet(),
        );

        // Agrupar por canal
        final Map<String, List<EpgProgram>> byChannel = {};
        for (final prog in parsed) {
          byChannel.putIfAbsent(prog.channelId, () => []).add(prog);
        }

        // Guardar en base de datos y memoria
        for (final chId in neededChannelIds) {
          final list = byChannel[chId] ?? [];
          _inMemoryCache[chId] = list;
          final maps = list.map((p) => p.toMap()).toList();
          await AppDatabase.instance.saveEpgPrograms(chId, maps);
        }
      }
    } catch (e) {
      debugPrint('Error procesando EPG: $e');
    } finally {
      _loadingChannels.removeAll(neededChannelIds);
    }
  }

  /// Retorna la lista de programas de un canal para las próximas `hours` horas
  Future<List<EpgProgram>> getProgramsForChannel(String channelId, {int hours = 24}) async {
    if (channelId.isEmpty) return [];

    List<EpgProgram>? progs = _inMemoryCache[channelId];
    if (progs == null || progs.isEmpty) {
      final raw = await AppDatabase.instance.getEpgPrograms(channelId);
      progs = raw.map((m) => EpgProgram.fromMap(m)).toList();
      _inMemoryCache[channelId] = progs;
    }

    final nowUtc = DateTime.now().toUtc();
    final maxUtc = nowUtc.add(Duration(hours: hours));
    final minUtc = nowUtc.subtract(const Duration(hours: 1));

    return progs.where((p) {
      return p.endTime.isAfter(minUtc) && p.startTime.isBefore(maxUtc);
    }).toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
  }

  /// Retorna el programa que está al aire ahora mismo para un canal
  Future<EpgProgram?> getNowPlaying(String channelId) async {
    if (channelId.isEmpty) return null;
    final progs = await getProgramsForChannel(channelId, hours: 4);
    for (final p in progs) {
      if (p.isCurrentlyAiring) {
        return p;
      }
    }
    return null;
  }

  /// Retorna el siguiente programa después del que está al aire
  Future<EpgProgram?> getNextProgram(String channelId) async {
    if (channelId.isEmpty) return null;
    final nowUtc = DateTime.now().toUtc();
    final progs = await getProgramsForChannel(channelId, hours: 6);
    for (final p in progs) {
      if (p.startTime.isAfter(nowUtc)) {
        return p;
      }
    }
    return null;
  }

  /// Limpia programas pasados y refresca
  Future<void> purgeAndRefresh() async {
    await AppDatabase.instance.purgeOldEpgPrograms();
    _inMemoryCache.clear();
  }
}
