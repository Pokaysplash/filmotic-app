import 'package:flutter_test/flutter_test.dart';
import 'package:lol/features/live_tv/data/m3u_parser.dart';

void main() {
  group('Live TV M3U Parser Tests', () {
    test('parses basic M3U playlist with attributes and stream URLs', () {
      const sampleM3u = '''
#EXTM3U x-tvg-url="https://epg.pw/xmltv/co.xml"
#EXTINF:-1 tvg-id="CaracolTV.co" tvg-name="Caracol TV" tvg-logo="https://example.com/caracol.png" tvg-country="CO" tvg-language="spa" group-title="General",Caracol Televisión HD
https://stream.example.com/caracol/live.m3u8
#EXTINF:-1 tvg-id="RCN.co" tvg-name="RCN" tvg-logo="https://example.com/rcn.png" tvg-country="CO" tvg-language="spa" group-title="Noticias",RCN Noticias
https://stream.example.com/rcn/live.m3u8
''';

      final result = M3UParser.parse(sampleM3u, 'https://iptv-org.github.io/iptv/countries/co.m3u');
      expect(result.channels.length, equals(2));
      expect(result.epgUrl, equals('https://epg.pw/xmltv/co.xml'));

      final caracol = result.channels.first;
      expect(caracol.id, equals('CaracolTV.co'));
      expect(caracol.name, equals('Caracol Televisión HD'));
      expect(caracol.logo, equals('https://example.com/caracol.png'));
      expect(caracol.country, equals('CO'));
      expect(caracol.language, equals('spa'));
      expect(caracol.group, equals('General'));
      expect(caracol.streamUrl, equals('https://stream.example.com/caracol/live.m3u8'));
      expect(caracol.isHD, isTrue);

      final rcn = result.channels[1];
      expect(rcn.id, equals('RCN.co'));
      expect(rcn.group, equals('Noticias'));
      expect(rcn.isHD, isFalse);
    });
  });
}
