import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../domain/channel.dart';

class M3UParseResult {
  final List<LiveChannel> channels;
  final String? epgUrl;

  M3UParseResult({
    required this.channels,
    this.epgUrl,
  });
}

class M3UParser {
  static final RegExp _attrRegex = RegExp(r'([a-zA-Z0-9_\-]+)="([^"]*)"');
  static final RegExp _epgHeaderRegex = RegExp(r'x-tvg-url="([^"]+)"', caseSensitive: false);

  static M3UParseResult parse(String content, String sourceUrl) {
    final channelMap = <String, LiveChannel>{};
    String? epgUrl;

    final lines = content.replaceAll('\r\n', '\n').split('\n');

    String? currentExtInf;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      if (line.startsWith('#EXTM3U')) {
        final match = _epgHeaderRegex.firstMatch(line);
        if (match != null) {
          epgUrl = match.group(1);
        }
        continue;
      }

      if (line.startsWith('#EXTINF:')) {
        currentExtInf = line;
        continue;
      }

      // Si empieza por # pero no es EXTINF ni EXTM3U, ignorar
      if (line.startsWith('#')) {
        continue;
      }

      // Si tenemos un EXTINF pendiente y la línea es una URL válida
      if (currentExtInf != null && (line.startsWith('http://') || line.startsWith('https://'))) {
        final channel = _buildChannel(currentExtInf, line, sourceUrl);
        if (channel != null) {
          final groupKey = _normalizeChannelKey(channel.id, channel.name, channel.country);
          if (channelMap.containsKey(groupKey)) {
            final existing = channelMap[groupKey]!;
            final alts = List<String>.from(existing.alternateUrls);
            if (line != existing.streamUrl && !alts.contains(line)) {
              alts.add(line);
            }
            channelMap[groupKey] = existing.copyWith(
              alternateUrls: alts,
              isHD: existing.isHD || channel.isHD,
              logo: existing.logo ?? channel.logo,
            );
          } else {
            channelMap[groupKey] = channel;
          }
        }
        currentExtInf = null;
      }
    }

    return M3UParseResult(channels: channelMap.values.toList(), epgUrl: epgUrl);
  }

  static String _normalizeChannelKey(String tvgId, String name, String? country) {
    if (tvgId.isNotEmpty && tvgId.contains('@')) {
      final base = tvgId.split('@').first.toLowerCase();
      if (base.isNotEmpty) return base;
    }
    if (tvgId.isNotEmpty && !tvgId.contains(':')) {
      return tvgId.toLowerCase();
    }
    final clean = name
        .toLowerCase()
        .replaceAll(RegExp(r'\([^)]*\)'), '')
        .replaceAll(RegExp(r'\[[^\]]*\]'), '')
        .replaceAll(RegExp(r'\b(1080p|720p|576p|480p|360p|hd|fhd|sd|4k)\b'), '')
        .trim();
    return '${clean}_${(country ?? '').toLowerCase()}';
  }

  static LiveChannel? _buildChannel(String extInf, String streamUrl, String sourceUrl) {
    try {
      final attrs = <String, String>{};
      final matches = _attrRegex.allMatches(extInf);
      for (final m in matches) {
        final k = m.group(1)?.toLowerCase();
        final v = m.group(2);
        if (k != null && v != null) {
          attrs[k] = v.trim();
        }
      }

      // El nombre va después de la última coma
      final commaIndex = extInf.lastIndexOf(',');
      String name = 'Canal en Vivo';
      if (commaIndex != -1 && commaIndex < extInf.length - 1) {
        name = extInf.substring(commaIndex + 1).trim();
      } else if (attrs.containsKey('tvg-name')) {
        name = attrs['tvg-name']!;
      }

      if (name.isEmpty) name = 'Canal en Vivo';

      String tvgId = attrs['tvg-id'] ?? attrs['tvg-name'] ?? '';
      if (tvgId.isEmpty) {
        tvgId = md5.convert(utf8.encode('$name:$streamUrl')).toString();
      }

      final logo = attrs['tvg-logo'];
      final group = attrs['group-title'];
      final country = attrs['tvg-country'];
      final language = attrs['tvg-language'];

      final lowerName = name.toLowerCase();
      final lowerUrl = streamUrl.toLowerCase();
      final isHD = lowerName.contains('hd') ||
          lowerName.contains('1080') ||
          lowerName.contains('720') ||
          lowerUrl.contains('1080') ||
          lowerUrl.contains('720');

      return LiveChannel(
        id: tvgId,
        name: name,
        logo: (logo != null && logo.isNotEmpty) ? logo : null,
        group: (group != null && group.isNotEmpty) ? group : null,
        country: (country != null && country.isNotEmpty) ? country.toUpperCase() : null,
        language: (language != null && language.isNotEmpty) ? language.toLowerCase() : null,
        streamUrl: streamUrl,
        sourceList: sourceUrl,
        isHD: isHD,
      );
    } catch (_) {
      return null;
    }
  }
}
