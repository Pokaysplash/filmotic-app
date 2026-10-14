import 'dart:io';
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app_installer/flutter_app_installer.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
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

  /// Directorio idóneo para descargar el paquete de instalación
  Future<Directory> getApkStorageDir() async {
    if (Platform.isAndroid) {
      try {
        final extDirs = await getExternalCacheDirectories();
        if (extDirs != null && extDirs.isNotEmpty) {
          return extDirs.first;
        }
      } catch (_) {}
      try {
        final extDir = await getExternalStorageDirectory();
        if (extDir != null) {
          return extDir;
        }
      } catch (_) {}
    }
    return await getTemporaryDirectory();
  }

  /// Descarga el APK con validación estricta de código HTTP y verificación de integridad
  Future<String> downloadApk({
    required String url,
    required void Function(int received, int total) onProgress,
    CancelToken? cancelToken,
  }) async {
    final dir = await getApkStorageDir();
    final filePath = '${dir.path}/filmotic_update.apk';
    final file = File(filePath);

    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 35),
        receiveTimeout: const Duration(minutes: 6),
      ),
    );

    const int maxRetries = 4;
    Object? lastError;

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        int existingLength = 0;
        if (await file.exists()) {
          existingLength = await file.length();
        }

        final isResume = existingLength > 0;
        final headers = isResume ? {'Range': 'bytes=$existingLength-'} : null;

        debugPrint('[UpdateService] Descargando APK (Intento $attempt/$maxRetries, bytes previos: $existingLength)...');

        final response = await dio.download(
          url,
          filePath,
          cancelToken: cancelToken,
          deleteOnError: false, // ¡Conserva los bytes descargados si la red fluctúa!
          fileAccessMode: isResume ? FileAccessMode.append : FileAccessMode.write,
          onReceiveProgress: (received, total) {
            final fullTotal = total > 0 ? (total + (isResume ? existingLength : 0)) : -1;
            final fullReceived = received + (isResume ? existingLength : 0);
            onProgress(fullReceived, fullTotal);
          },
          options: Options(
            responseType: ResponseType.bytes,
            followRedirects: true,
            maxRedirects: 10,
            headers: headers,
            validateStatus: (status) =>
                status != null && ((status >= 200 && status < 400) || status == 416),
          ),
        );

        if (response.statusCode == 416) {
          debugPrint('[UpdateService] Código 416: El archivo ya estaba completo.');
        }

        // Validar si el archivo ya quedó completo e íntegro
        if (await file.exists()) {
          final len = await file.length();
          if (len >= 5 * 1024 * 1024) {
            final headerBytes = await file.openRead(0, 4).first;
            if (headerBytes.length >= 4 &&
                headerBytes[0] == 0x50 &&
                headerBytes[1] == 0x4B &&
                headerBytes[2] == 0x03 &&
                headerBytes[3] == 0x04) {
              debugPrint('[UpdateService] APK descargado con éxito y verificado ($len bytes).');
              return filePath;
            }
          }
        }
      } catch (e) {
        lastError = e;
        debugPrint('[UpdateService] Fallo temporal en intento $attempt: $e');
        if (attempt == maxRetries) break;
        // Espera breve para dar tiempo a que la conexión móvil se estabilice
        await Future.delayed(Duration(seconds: attempt * 2));
      }
    }

    // Comprobación final si el archivo ya fue descargado completamente
    if (await file.exists()) {
      try {
        final length = await file.length();
        if (length >= 5 * 1024 * 1024) {
          final headerBytes = await file.openRead(0, 4).first;
          if (headerBytes.length >= 4 &&
              headerBytes[0] == 0x50 &&
              headerBytes[1] == 0x4B &&
              headerBytes[2] == 0x03 &&
              headerBytes[3] == 0x04) {
            return filePath;
          }
        }
        await file.delete();
      } catch (_) {}
    }

    if (lastError != null) {
      throw lastError;
    }
    throw Exception('La conexión se interrumpió antes de completar la descarga.');
  }

  /// Formatea errores para presentarlos de manera amigable y limpia al usuario
  static String formatUserFriendlyError(dynamic error) {
    if (error == null) return 'Error desconocido al actualizar';
    final errStr = error.toString().toLowerCase();

    if (errStr.contains('connection closed') ||
        errStr.contains('connection reset') ||
        errStr.contains('socketexception') ||
        errStr.contains('httpexception') ||
        (error is DioException &&
            (error.type == DioExceptionType.connectionError ||
             error.type == DioExceptionType.connectionTimeout ||
             error.type == DioExceptionType.receiveTimeout ||
             error.type == DioExceptionType.sendTimeout ||
             error.type == DioExceptionType.unknown))) {
      return 'La conexión a internet se interrumpió durante la descarga.';
    }

    if (error is DioException) {
      final code = error.response?.statusCode;
      if (code != null) {
        return 'El servidor de descargas respondió con error ($code).';
      }
      return 'Error de conexión al descargar la actualización.';
    }

    var clean = error
        .toString()
        .replaceFirst(RegExp(r'^(Exception|PlatformException\([^)]*\)|DioException\s*\[[^\]]*\]):\s*'), '')
        .trim();

    if (clean.contains('REQUEST_INSTALL_PACKAGES') ||
        clean.contains('Instalar apps desconocidas')) {
      return 'Para instalar la actualización, autoriza "Instalar apps desconocidas" para Filmotic en los Ajustes de Android.';
    }

    if (clean.length > 110) {
      return 'No se pudo completar la instalación automática.';
    }

    return clean;
  }

  /// Inicia el instalador nativo de Android con estrategia resiliente en cascada:
  /// 1. Solicitud previa segura de permiso REQUEST_INSTALL_PACKAGES (sin abortar)
  /// 2. flutter_app_installer (FileProvider .fileProvider)
  /// 3. OpenFilex (FileProvider propio e independiente)
  /// 4. AndroidIntent (intent ACTION_VIEW directo)
  Future<bool> installApk({
    required String filePath,
    required String targetVersion,
  }) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('La instalación de APK solo es compatible con Android.');
    }

    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('El archivo de instalación no fue encontrado en el almacenamiento.');
    }

    // 1. Manejo preventivo del permiso para instalar paquetes desconocidos
    try {
      final installPerm = await Permission.requestInstallPackages.status;
      if (!installPerm.isGranted) {
        debugPrint('[UpdateService] Permiso REQUEST_INSTALL_PACKAGES pendiente. Solicitando...');
        await Permission.requestInstallPackages.request();
      }
    } catch (e) {
      debugPrint('[UpdateService] Solicitud de permiso REQUEST_INSTALL_PACKAGES omitida: $e');
    }

    await markPendingUpdate(targetVersion);

    // 2. Intento 1: flutter_app_installer
    try {
      final flutterAppInstaller = FlutterAppInstaller();
      final result = await flutterAppInstaller.installApk(
        filePath: filePath,
        silently: false,
      );
      if (result == true) {
        debugPrint('[UpdateService] Instalador iniciado con flutter_app_installer.');
        return true;
      }
    } catch (e) {
      debugPrint('[UpdateService] Falló flutter_app_installer: $e. Intentando OpenFilex...');
    }

    // 3. Intento 2: OpenFilex (altamente compatible en Android TV y móviles)
    try {
      final openResult = await OpenFilex.open(
        filePath,
        type: 'application/vnd.android.package-archive',
      );
      debugPrint('[UpdateService] OpenFilex resultado: ${openResult.type} - ${openResult.message}');
      if (openResult.type == ResultType.done) {
        return true;
      }
    } catch (e) {
      debugPrint('[UpdateService] Falló OpenFilex: $e. Intentando AndroidIntent directo...');
    }

    // 4. Intento 3: AndroidIntent directo con ACTION_VIEW
    try {
      final intent = AndroidIntent(
        action: 'android.intent.action.VIEW',
        data: Uri.file(filePath).toString(),
        type: 'application/vnd.android.package-archive',
        flags: const [
          Flag.FLAG_ACTIVITY_NEW_TASK,
          Flag.FLAG_GRANT_READ_URI_PERMISSION,
        ],
      );
      await intent.launch();
      return true;
    } catch (e) {
      debugPrint('[UpdateService] Falló AndroidIntent directo: $e');
    }

    throw Exception(
      'No se pudo abrir el instalador del paquete en tu dispositivo. Puedes autorizar "Instalar apps desconocidas" en Ajustes o descargar el APK desde el navegador.',
    );
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

