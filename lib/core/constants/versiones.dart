import '../services/remote_config_service.dart';

class VersionService {
  // ============================================
  // CONFIGURA AQUÍ LA VERSIÓN ACTUAL DE TU APP
  // ============================================
  static const String currentVersionName = "1.0.0-beta.17"; // version_aceptada
  static const int currentVersionCode = 17; // version_code_aceptada

  /// Obtiene la última versión configurada en RemoteConfig
  static Future<VersionInfo?> getLatestAnimeVersion() async {
    try {
      final appConfig = RemoteConfigService.instance.config.app;
      return VersionInfo(
        id: 1,
        versionAceptada: appConfig.latestVersion,
        versionCodeAceptada: _parseVersionCode(appConfig.latestVersion),
        novedades: appConfig.updateMessage,
        urlApk: appConfig.updateUrl,
        tipo: 'filmotic',
        fechaCreacion: DateTime.now().toIso8601String(),
      );
    } catch (_) {
      return null;
    }
  }

  static int _parseVersionCode(String ver) {
    final parts = ver.replaceAll(RegExp(r'[^0-9.]'), '').split('.');
    int code = 0;
    for (final p in parts) {
      code = code * 100 + (int.tryParse(p) ?? 0);
    }
    return code;
  }

  /// Fuerza la descarga de la configuración remota y verifica si hay actualizaciones
  static Future<UpdateStatus> forceCheckForUpdate() async {
    await RemoteConfigService.instance.forceRefresh();
    return checkForUpdate();
  }

  /// Verifica si se requiere actualización contra RemoteConfig
  static Future<UpdateStatus> checkForUpdate() async {
    final appConfig = RemoteConfigService.instance.config.app;
    final latestVer = appConfig.latestVersion;
    final isMandatory = RemoteConfigService.instance.isMandatoryUpdateRequired(currentVersionName);
    final isOptional = RemoteConfigService.instance.isOptionalUpdateAvailable(currentVersionName);
    final needsUpdate = isMandatory || isOptional;

    final info = VersionInfo(
      id: 1,
      versionAceptada: latestVer,
      versionCodeAceptada: _parseVersionCode(latestVer),
      novedades: appConfig.updateMessage,
      urlApk: appConfig.updateUrl,
      tipo: 'filmotic',
      fechaCreacion: DateTime.now().toIso8601String(),
    );

    return UpdateStatus(
      requiresUpdate: needsUpdate,
      isForceUpdate: isMandatory,
      latestVersion: info,
      message: needsUpdate
          ? "Hay una nueva versión disponible: $latestVer"
          : "Tu aplicación está actualizada",
    );
  }
}

// Modelo de la versión
class VersionInfo {
  final int id;
  final String versionAceptada;
  final int versionCodeAceptada;
  final String novedades;
  final String urlApk; // legacy / fallback
  final String? urlApkArm64; // arm64-v8a
  final String? urlApkArmeabi; // armeabi-v7a
  final String? urlApkX86; // x86 / x86_64
  final String? urlApkUniversal; // APK universal (todas)
  final String tipo;
  final String fechaCreacion;

  VersionInfo({
    required this.id,
    required this.versionAceptada,
    required this.versionCodeAceptada,
    required this.novedades,
    required this.urlApk,
    this.urlApkArm64,
    this.urlApkArmeabi,
    this.urlApkX86,
    this.urlApkUniversal,
    required this.tipo,
    required this.fechaCreacion,
  });

  factory VersionInfo.fromJson(Map<String, dynamic> j) {
    String? _opt(dynamic v) {
      final s = v?.toString().trim();
      return (s != null && s.isNotEmpty) ? s : null;
    }

    return VersionInfo(
      id: int.tryParse('${j['id']}') ?? 0,
      versionAceptada: j['version_aceptada']?.toString() ?? '',
      versionCodeAceptada:
          int.tryParse('${j['version_code_aceptada']}') ?? 0,
      novedades: j['novedades']?.toString() ?? '',
      urlApk: j['url_apk']?.toString() ?? '',
      urlApkArm64: _opt(j['url_apk_arm64']),
      urlApkArmeabi: _opt(j['url_apk_armeabi']),
      urlApkX86: _opt(j['url_apk_x86']),
      urlApkUniversal: _opt(j['url_apk_universal']),
      tipo: j['tipo']?.toString() ?? '',
      fechaCreacion: j['fecha_creacion']?.toString() ?? '',
    );
  }

  /// URL según arquitectura: arm64 | armeabi | x86 | universal
  String? urlForAbi(String abi) {
    switch (abi) {
      case 'arm64':
        return urlApkArm64;
      case 'armeabi':
        return urlApkArmeabi;
      case 'x86':
        return urlApkX86;
      case 'universal':
        return urlApkUniversal ??
            (urlApk.trim().isNotEmpty ? urlApk : null);
      default:
        return null;
    }
  }
}

// Estado de actualización
class UpdateStatus {
  final bool requiresUpdate;
  final bool isForceUpdate;
  final VersionInfo? latestVersion;
  final String message;

  UpdateStatus({
    required this.requiresUpdate,
    required this.isForceUpdate,
    required this.latestVersion,
    required this.message,
  });
}