import 'package:flutter_test/flutter_test.dart';
import '../lib/core/services/server_loader_shared.dart';
import '../lib/data/extractors/hls/hls_extractor.dart';

void main() {
  group('BLOQUE A & B: Episode & Smart Parallel Resolver Tests', () {
    test('1. NativeResolvers detecta servidores conocidos por URL', () {
      expect(NativeResolvers.detectServer('https://streamwish.to/e/abc123xyz'), 'streamwish');
      expect(NativeResolvers.detectServer('https://vidhidepro.com/v/987654'), 'vidhide');
      expect(NativeResolvers.detectServer('https://voe.sx/e/testvoe'), 'voe');
      expect(NativeResolvers.detectServer('https://filemoon.sx/e/fm123'), 'filemoon');
      expect(NativeResolvers.detectServer('https://unknownsite.xyz/video'), 'unknown');
    });

    test('2. ServerLoader.statusNotifier reacciona al estado de conexión', () {
      expect(ServerLoader.statusNotifier, isNotNull);
      ServerLoader.statusNotifier.value = 'Conectando al mejor servidor...';
      expect(ServerLoader.statusNotifier.value, 'Conectando al mejor servidor...');

      ServerLoader.statusNotifier.value = 'Probando múltiples servidores...';
      expect(ServerLoader.statusNotifier.value, 'Probando múltiples servidores...');

      ServerLoader.statusNotifier.value = 'Conectado a StreamWish HD';
      expect(ServerLoader.statusNotifier.value, 'Conectado a StreamWish HD');
    });

    test('3. PlayableSource estructura datos de stream correctamente', () {
      const source = PlayableSource(
        url: 'https://example.com/stream.m3u8',
        headers: {'Referer': 'https://example.com/'},
        quality: '1080p',
        serverName: 'Cuevana StreamWish',
        idioma: 'es_MX',
        rawServer: {'servidor': 'streamwish'},
      );

      expect(source.url, 'https://example.com/stream.m3u8');
      expect(source.headers['Referer'], 'https://example.com/');
      expect(source.serverName, 'Cuevana StreamWish');
      expect(source.idioma, 'es_MX');
    });
  });
}
