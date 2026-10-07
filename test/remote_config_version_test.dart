
import 'package:flutter_test/flutter_test.dart';
import 'package:lol/core/services/remote_config_service.dart';

void main() {
  group('RemoteConfigService Versioning Logic', () {
    test('compareVersions works accurately across standard and patch versions', () {
      expect(RemoteConfigService.compareVersions('1.0.0', '1.0.0'), equals(0));
      expect(RemoteConfigService.compareVersions('1.0.0', '1.0.1'), equals(-1));
      expect(RemoteConfigService.compareVersions('1.0.1', '1.0.0'), equals(1));
      expect(RemoteConfigService.compareVersions('1.1.0', '1.0.9'), equals(1));
      expect(RemoteConfigService.compareVersions('2.0.0', '1.9.9'), equals(1));
      expect(RemoteConfigService.compareVersions('v1.0.0', '1.0.0'), equals(0));
      expect(RemoteConfigService.compareVersions('V1.0.0', '1.0.0'), equals(0));
      expect(RemoteConfigService.compareVersions('1.0.0+1', '1.0.0+2'), equals(0));
      expect(RemoteConfigService.compareVersions('1.0.1+2', '1.0.0+1'), equals(1));
      
      // Casos específicos WAVE 12.15 (tolerancia de formatos)
      expect(RemoteConfigService.compareVersions('1.0.0-beta.14', '1.0.0-beta.14+14'), equals(0));
      expect(RemoteConfigService.compareVersions('1.0.0-beta.14', 'v1.0.0-beta.14'), equals(0));
      expect(RemoteConfigService.compareVersions('1.0.0-beta.14', '1.0.0-BETA.14'), equals(0));
      expect(RemoteConfigService.compareVersions('1.0.0-beta.13', '1.0.0-beta.14'), equals(-1));
      expect(RemoteConfigService.compareVersions('1.0.0-beta.14', '1.0.0-beta.13'), equals(1));
    });

    test('isMandatoryUpdateRequired and isOptionalUpdateAvailable', () {
      final config = RemoteConfigService.instance;
      // Current default min_version is 1.0.0, latest_version is 1.0.0
      expect(config.isMandatoryUpdateRequired('1.0.0'), isFalse);
      expect(config.isOptionalUpdateAvailable('1.0.0'), isFalse);

      expect(config.isMandatoryUpdateRequired('0.9.9'), isTrue);

      // Testing with higher latest version
      final newerConfig = FilmoticRemoteConfig(
        version: 1,
        ads: {},
        enabledSources: [],
        disabledSources: [],
        messages: {},
        app: FilmoticAppInfo(
          minVersion: '1.0.0',
          latestVersion: '1.0.1',
          updateUrl: 'https://example.com/filmotic.apk',
          updateMessage: 'New version!',
          forceUpdate: false,
        ),
      );

      // Verify manual check
      expect(RemoteConfigService.compareVersions('1.0.0', newerConfig.app.minVersion) < 0, isFalse);
      expect(RemoteConfigService.compareVersions('1.0.0', newerConfig.app.latestVersion) < 0, isTrue);
    });

    test('Regla crítica: Si currentVersion >= latestVersion NUNCA se requiere actualización', () {
      final config = RemoteConfigService.instance;
      // Cuando el usuario ya tiene la última versión instalada
      expect(config.isMandatoryUpdateRequired('1.0.0-beta.14'), isFalse);
      expect(config.isOptionalUpdateAvailable('1.0.0-beta.14'), isFalse);
      expect(config.isMandatoryUpdateRequired('1.0.0-beta.14+14'), isFalse);
      expect(config.isOptionalUpdateAvailable('1.0.0-beta.14+14'), isFalse);
    });
  });
}
