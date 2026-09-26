import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../domain/epg_program.dart';

class XmltvParser {
  static final RegExp _programmeRegex = RegExp(
    r'<programme\s+([^>]+)>(.*?)</programme>',
    dotAll: true,
    caseSensitive: false,
  );

  static final RegExp _attrRegex = RegExp(r'([a-zA-Z0-9_\-]+)="([^"]*)"');
  static final RegExp _titleRegex = RegExp(r'<title[^>]*>(.*?)</title>', dotAll: true, caseSensitive: false);
  static final RegExp _descRegex = RegExp(r'<desc[^>]*>(.*?)</desc>', dotAll: true, caseSensitive: false);
  static final RegExp _categoryRegex = RegExp(r'<category[^>]*>(.*?)</category>', dotAll: true, caseSensitive: false);
  static final RegExp _iconRegex = RegExp(r'<icon\s+src="([^"]+)"', caseSensitive: false);

  /// Parsea XMLTV filtrando solo los programas dentro de la ventana de tiempo especificada.
  /// Por defecto: desde 2 horas antes de ahora hasta 48 horas en el futuro.
  static Future<List<EpgProgram>> parseXmltv(
    String content, {
    DateTime? from,
    DateTime? to,
    Set<String>? filterChannelIds,
  }) async {
    final now = DateTime.now().toUtc();
    final windowStart = from ?? now.subtract(const Duration(hours: 2));
    final windowEnd = to ?? now.add(const Duration(hours: 48));

    final programs = <EpgProgram>[];

    // Procesar todos los tags <programme>
    final matches = _programmeRegex.allMatches(content);

    for (final match in matches) {
      final headerAttrs = match.group(1) ?? '';
      final body = match.group(2) ?? '';

      final attrs = <String, String>{};
      for (final attrMatch in _attrRegex.allMatches(headerAttrs)) {
        final k = attrMatch.group(1)?.toLowerCase();
        final v = attrMatch.group(2);
        if (k != null && v != null) {
          attrs[k] = v;
        }
      }

      final channelId = attrs['channel'];
      if (channelId == null || channelId.isEmpty) continue;

      if (filterChannelIds != null && !filterChannelIds.contains(channelId)) {
        continue;
      }

      final startRaw = attrs['start'];
      final stopRaw = attrs['stop'];
      if (startRaw == null || stopRaw == null) continue;

      final start = parseDate(startRaw);
      final stop = parseDate(stopRaw);
      if (start == null || stop == null) continue;

      // Filtrar programas fuera de la ventana de tiempo
      if (stop.isBefore(windowStart) || start.isAfter(windowEnd)) {
        continue;
      }

      final titleMatch = _titleRegex.firstMatch(body);
      final rawTitle = titleMatch?.group(1)?.trim();
      if (rawTitle == null || rawTitle.isEmpty) continue;

      final title = _unescapeXml(rawTitle);

      final descMatch = _descRegex.firstMatch(body);
      final desc = descMatch != null ? _unescapeXml(descMatch.group(1)?.trim() ?? '') : null;

      final catMatch = _categoryRegex.firstMatch(body);
      final cat = catMatch != null ? _unescapeXml(catMatch.group(1)?.trim() ?? '') : null;

      final iconMatch = _iconRegex.firstMatch(body);
      final icon = iconMatch?.group(1);

      final isCurrentlyLive = now.isAfter(start) && now.isBefore(stop);
      final id = md5.convert(utf8.encode('$channelId:${start.toIso8601String()}:$title')).toString();

      programs.add(
        EpgProgram(
          id: id,
          channelId: channelId,
          title: title,
          description: (desc != null && desc.isNotEmpty) ? desc : null,
          category: (cat != null && cat.isNotEmpty) ? cat : null,
          icon: (icon != null && icon.isNotEmpty) ? icon : null,
          startTime: start,
          endTime: stop,
          isLive: isCurrentlyLive,
        ),
      );
    }

    return programs;
  }

  static DateTime? parseDate(String raw) {
    try {
      final trimmed = raw.trim();
      final parts = trimmed.split(' ');
      final dtStr = parts[0];
      if (dtStr.length < 8) return null;

      final year = int.parse(dtStr.substring(0, 4));
      final month = int.parse(dtStr.substring(4, 6));
      final day = int.parse(dtStr.substring(6, 8));
      final hour = dtStr.length >= 10 ? int.parse(dtStr.substring(8, 10)) : 0;
      final minute = dtStr.length >= 12 ? int.parse(dtStr.substring(10, 12)) : 0;
      final second = dtStr.length >= 14 ? int.parse(dtStr.substring(12, 14)) : 0;

      var dt = DateTime.utc(year, month, day, hour, minute, second);

      if (parts.length > 1) {
        final tz = parts[1];
        if (tz.length == 5) {
          final sign = tz[0] == '-' ? -1 : 1;
          final tzH = int.parse(tz.substring(1, 3));
          final tzM = int.parse(tz.substring(3, 5));
          final totalMinutes = sign * (tzH * 60 + tzM);
          dt = dt.subtract(Duration(minutes: totalMinutes));
        }
      }

      return dt;
    } catch (_) {
      return null;
    }
  }

  static String _unescapeXml(String text) {
    return text
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'");
  }
}
