import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/versiones.dart';
import 'remote_config_service.dart';

/// Servicio para coordinar y verificar el ciclo de actualización de Filmotic.
class UpdateService {
  UpdateService._();
  static final UpdateService instance = UpdateService._();

  static const String _kPendingUpdateKey = 'pending_update_version';
  static const String _kUpdateAttemptsKey = 'update_attempt_count_';
  static const String _kLastBypassedTimestampKey = 'update_bypassed_timestamp_';

  /// Obtiene la versión real instalada en el sistema según el package manager
  /// con fallback en cascada a VersionService.currentVersionName
  Future<String> getInstalledVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final v = info.version.trim();
      debugPrint('[Update] Installed: $v | Hardcoded: ${VersionService.currentVersionName}');
      if (v.isNotEmpty) return v;
      return VersionService.currentVersionName;
    } catch (e) {
      debugPrint('[UpdateService] Error leyendo package_info: $e -> Fallback: ${VersionService.currentVersionName}');
      return VersionService.currentVersionName;
    }
  }

  /// Registra un intento de actualización del usuario y devuelve el total
  Future<int> recordUpdateAttempt(String targetVersion) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_kUpdateAttemptsKey${targetVersion.trim()}';
      final current = (prefs.getInt(key) ?? 0) + 1;
      await prefs.setInt(key, current);
      return current;
    } catch (_) {
      return 1;
    }
  }

  /// Obtiene el número de intentos de actualización para una versión dada
  Future<int> getUpdateAttempts(String targetVersion) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_kUpdateAttemptsKey${targetVersion.trim()}';
      return prefs.getInt(key) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Activa la válvula de escape por 24 horas para una versión específica
  Future<void> bypassUpdateFor24Hours(String targetVersion) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now().millisecondsSinceEpoch;
      await prefs.setInt('$_kLastBypassedTimestampKey${targetVersion.trim()}', now);
      await RemoteConfigService.instance.setDismissedVersion(targetVersion);
      debugPrint('[UpdateService] Válvula de escape activada para $targetVersion por 24h');
    } catch (e) {
      debugPrint('[UpdateService] Error guardando bypass: $e');
    }
  }

  /// Verifica si la actualización está temporalmente silenciada/bypassed por 24h
  Future<bool> isUpdateBypassed(String targetVersion) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timestamp = prefs.getInt('$_kLastBypassedTimestampKey${targetVersion.trim()}');
      if (timestamp == null) return false;
      final diff = DateTime.now().millisecondsSinceEpoch - timestamp;
      return diff < const Duration(hours: 24).inMilliseconds;
    } catch (_) {
      return false;
    }
  }

  /// Obtiene el build number real instalado
  Future<int> getInstalledBuildNumber() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return int.tryParse(info.buildNumber) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Valida si la versión instalada coincide con la esperada
  Future<bool> verifyInstallation(String expectedVersion) async {
    final current = await getInstalledVersion();
    if (current.isEmpty) return false;
    final normalizedCurrent = current.trim().toLowerCase();
    final normalizedExpected = expectedVersion.trim().toLowerCase();
    return normalizedCurrent == normalizedExpected ||
        normalizedCurrent.contains(normalizedExpected) ||
        normalizedExpected.contains(normalizedCurrent);
  }

  /// Registra que se inició un proceso de instalación de actualización
  Future<void> markPendingUpdate(String targetVersion) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kPendingUpdateKey, targetVersion.trim());
      await recordUpdateAttempt(targetVersion);
      debugPrint('[UpdateService] Marcada actualización pendiente: $targetVersion');
    } catch (e) {
      debugPrint('[UpdateService] Error guardando pending update: $e');
    }
  }

  /// Limpia la marca de actualización pendiente
  Future<void> clearPendingUpdate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kPendingUpdateKey);
    } catch (_) {}
  }

  /// Verifica tras reabrir la app si una actualización previa se aplicó exitosamente
  Future<void> checkPostInstallStatus(BuildContext context, {String? fallbackUrl}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final expectedVersion = prefs.getString(_kPendingUpdateKey);
      if (expectedVersion == null || expectedVersion.isEmpty) return;

      // Limpiar para no repetir en reinicios subsecuentes
      await prefs.remove(_kPendingUpdateKey);

      final success = await verifyInstallation(expectedVersion);
      final currentVersion = await getInstalledVersion();

      if (!success) {
        debugPrint(
          '[UpdateService] ERROR: La actualización no se aplicó. '
          'Esperada: $expectedVersion, Instalada: $currentVersion',
        );

        if (!context.mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF1E1E1E),
            duration: const Duration(seconds: 10),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Color(0xFFFF6B35), width: 1),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Color(0xFFFF6B35), size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Actualización no completada',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'La versión actual sigue siendo v$currentVersion. Descarga el APK manualmente desde el navegador.',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
            action: SnackBarAction(
              label: 'Descargar',
              textColor: const Color(0xFFFF6B35),
              onPressed: () {
                final targetUrl = fallbackUrl ??
                    'https://github.com/Pokaysplash/filmotic-app/releases/latest/download/filmotic.apk';
                openFallbackUrl(targetUrl);
              },
            ),
          ),
        );
      } else {
        debugPrint('[UpdateService] Actualización verificada con éxito: v$currentVersion');
      }
    } catch (e) {
      debugPrint('[UpdateService] Error en checkPostInstallStatus: $e');
    }
  }

  /// Abre URL en el navegador externo como fallback seguro
  Future<void> openFallbackUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('[UpdateService] Error abriendo fallback URL: $e');
    }
  }
}
