import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:lol/core/services/cast_service.dart';
import 'package:dart_cast/dart_cast.dart' as dc;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WAVE 12.16 - Migración DLNA a dart_cast', () {
    test('CastService singleton e inicialización correcta', () {
      final service = CastService.instance;
      expect(service, isNotNull);
      expect(service.state, equals(CastState.idle));
      expect(service.isRemotePlaying.value, isFalse);
      expect(service.connectedDevice, isNull);
    });

    test('Compatibilidad con CastDevice y extensiones friendlyName / udn', () {
      final device = dc.CastDevice(
        id: 'uuid:xbox-one-living-room',
        name: 'Xbox One S',
        protocol: dc.CastProtocol.dlna,
        address: InternetAddress('192.168.1.50'),
        port: 1900,
      );

      // Verificamos getters nativos y extensiones de compatibilidad
      expect(device.id, equals('uuid:xbox-one-living-room'));
      expect(device.name, equals('Xbox One S'));
      expect(device.friendlyName, equals('Xbox One S'));
      expect(device.udn.value, equals('uuid:xbox-one-living-room'));
      expect(device.protocol, equals(dc.CastProtocol.dlna));
      expect(device.address.address, equals('192.168.1.50'));
    });

    test('Detección de tipos de contenido y proxy headers en 3 contenidos distintos', () {
      // 1. Película de Cuevana (HLS)
      const cuevanaStream = 'https://stream.cuevana3.ch/hls/matrix_resurrections/master.m3u8';
      final cuevanaHeaders = {
        'Referer': 'https://www.cuevana3.ch',
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      };

      final cuevanaMedia = dc.CastMedia(
        url: cuevanaStream,
        type: dc.CastMediaType.hls,
        title: 'The Matrix Resurrections (Cuevana)',
        httpHeaders: cuevanaHeaders,
      );
      expect(cuevanaMedia.type, equals(dc.CastMediaType.hls));
      expect(cuevanaMedia.httpHeaders['Referer'], equals('https://www.cuevana3.ch'));
      expect(cuevanaMedia.httpHeaders['User-Agent'], contains('Mozilla/5.0'));

      // 2. Serie de PelisPlus (HLS)
      const pelisplusStream = 'https://pelisplus.lat/stream/stranger_things_s04e01/index.m3u8';
      final pelisplusHeaders = {
        'Referer': 'https://pelisplus.lat',
        'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)',
      };

      final pelisplusMedia = dc.CastMedia(
        url: pelisplusStream,
        type: dc.CastMediaType.hls,
        title: 'Stranger Things S04E01 (PelisPlus)',
        httpHeaders: pelisplusHeaders,
      );
      expect(pelisplusMedia.type, equals(dc.CastMediaType.hls));
      expect(pelisplusMedia.httpHeaders['Referer'], equals('https://pelisplus.lat'));

      // 3. Contenido de Canela.TV (HLS Brightcove)
      const canelaStream = 'https://manifest.prod.boltdns.net/manifest/v1/hls/v4/clear/5176766487001/canela_content/master.m3u8';
      final canelaHeaders = {
        'Referer': 'https://www.canela.tv/',
        'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)',
      };

      final canelaMedia = dc.CastMedia(
        url: canelaStream,
        type: dc.CastMediaType.hls,
        title: 'Canela TV Original HLS',
        httpHeaders: canelaHeaders,
      );
      expect(canelaMedia.type, equals(dc.CastMediaType.hls));
      expect(canelaMedia.httpHeaders['Referer'], equals('https://www.canela.tv/'));
      expect(canelaMedia.httpHeaders['User-Agent'], contains('Mac OS X'));
    });
  });
}
