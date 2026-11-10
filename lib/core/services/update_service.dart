import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  static const MethodChannel _installerChannel =
      MethodChannel('com.example.lol/installer');

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

  /// Directorio idóneo para descargar el paquete de instalación.
  /// Prioriza `getExternalStorageDirectory` (`Android/data/<pkg>/files`), que es
  /// compatible tanto con nuestro FileProvider como con OpenFilex sin requerir
  /// MANAGE_EXTERNAL_STORAGE en Android 11+.
  Future<Directory> getApkStorageDir() async {
    if (Platform.isAndroid) {
      // Limpiar posibles archivos residuales en externalCacheDirectories antiguos
      try {
        final extCacheDirs = await getExternalCacheDirectories();
        if (extCacheDirs != null) {
          for (final d in extCacheDirs) {
            final oldApk = File('${d.path}/filmotic_update.apk');
            if (await oldApk.exists()) await oldApk.delete();
          }
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

  /// Verifica la integridad estructural del archivo APK/ZIP (cabecera inicial PK\x03\x04,
  /// cierre End of Central Directory PK\x05\x06, tamaño esperado y parser PackageManager de Android).
  Future<bool> _validateApkIntegrity(File file, {int? expectedSize}) async {
    try {
      if (!await file.exists()) return false;
      final len = await file.length();

      // El APK de Filmotic supera los 15 MB
      if (len < 15 * 1024 * 1024) {
        debugPrint('[UpdateService] APK rechazado por tamaño insuficiente: $len bytes');
        return false;
      }

      if (expectedSize != null && expectedSize > 0 && len != expectedSize) {
        debugPrint(
          '[UpdateService] APK incompleto: descargados $len bytes de $expectedSize esperados',
        );
        return false;
      }

      // 1. Verificar firma inicial ZIP (PK\x03\x04)
      final headerChunks = await file.openRead(0, 4).toList();
      final headerBytes = headerChunks.expand((x) => x).toList();
      if (headerBytes.length < 4 ||
          headerBytes[0] != 0x50 ||
          headerBytes[1] != 0x4B ||
          headerBytes[2] != 0x03 ||
          headerBytes[3] != 0x04) {
        debugPrint('[UpdateService] APK rechazado: cabecera ZIP inválida');
        return false;
      }

      // 2. Verificar firma final End of Central Directory (PK\x05\x06) en los últimos 1024 bytes
      final tailStart = (len - 1024).clamp(0, len);
      final tailChunks = await file.openRead(tailStart, len).toList();
      final tailBytes = tailChunks.expand((x) => x).toList();
      bool hasEocd = false;
      for (int i = tailBytes.length - 22; i >= 0; i--) {
        if (tailBytes[i] == 0x50 &&
            tailBytes[i + 1] == 0x4B &&
            tailBytes[i + 2] == 0x05 &&
            tailBytes[i + 3] == 0x06) {
          hasEocd = true;
          break;
        }
      }
      if (!hasEocd) {
        debugPrint('[UpdateService] APK rechazado: falta firma EOCD (PK\\x05\\x06) al final del archivo');
        return false;
      }

      // 3. Validar con PackageManager nativo de Android
      if (Platform.isAndroid) {
        try {
          final res = await _installerChannel.invokeMethod<Map<dynamic, dynamic>>(
            'verifyApkFile',
            {'filePath': file.path},
          );
          if (res != null && res['valid'] == false) {
            debugPrint(
              '[UpdateService] PackageManager rechazó el APK: ${res['reason']}',
            );
            return false;
          }
        } catch (e) {
          debugPrint('[UpdateService] Canal verifyApkFile no disponible, usando validación ZIP: $e');
        }
      }

      return true;
    } catch (e) {
      debugPrint('[UpdateService] Error validando integridad del APK: $e');
      return false;
    }
  }

  /// Descarga el APK en limpio con validación estricta de código HTTP e integridad completa
  Future<String> downloadApk({
    required String url,
    required void Function(int received, int total) onProgress,
    CancelToken? cancelToken,
  }) async {
    final dir = await getApkStorageDir();
    final filePath = '${dir.path}/filmotic_update.apk';
    final partPath = '${dir.path}/filmotic_update.apk.part';
    final file = File(filePath);
    final partFile = File(partPath);

    // Eliminar siempre cualquier APK o fragmento previo antes de comenzar una nueva descarga
    // para evitar mezclar bytes de versiones distintas o reutilizar descargas truncadas.
    try {
      if (await file.exists()) await file.delete();
      if (await partFile.exists()) await partFile.delete();
    } catch (_) {}

    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 35),
        receiveTimeout: const Duration(minutes: 8),
      ),
    );

    const int maxRetries = 3;
    Object? lastError;

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        if (await partFile.exists()) {
          await partFile.delete();
        }

        int expectedTotal = -1;
        debugPrint('[UpdateService] Descargando APK limpio (Intento $attempt/$maxRetries)...');

        await dio.download(
          url,
          partPath,
          cancelToken: cancelToken,
          deleteOnError: true,
          fileAccessMode: FileAccessMode.write,
          onReceiveProgress: (received, total) {
            if (total > 0) expectedTotal = total;
            onProgress(received, total);
          },
          options: Options(
            responseType: ResponseType.bytes,
            followRedirects: true,
            maxRedirects: 10,
            validateStatus: (status) =>
                status != null && status >= 200 && status < 400,
          ),
        );

        // Validar que el archivo descargado esté 100% completo y sea un APK válido
        if (await _validateApkIntegrity(partFile, expectedSize: expectedTotal)) {
          if (await file.exists()) await file.delete();
          await partFile.rename(filePath);
          final len = await file.length();
          debugPrint('[UpdateService] APK descargado y verificado al 100% ($len bytes).');
          return filePath;
        } else {
          if (await partFile.exists()) await partFile.delete();
          throw Exception('El paquete descargado está incompleto o corrupto.');
        }
      } catch (e) {
        lastError = e;
        debugPrint('[UpdateService] Fallo en intento $attempt: $e');
        try {
          if (await partFile.exists()) await partFile.delete();
        } catch (_) {}
        if (attempt == maxRetries) break;
        await Future.delayed(Duration(seconds: attempt * 2));
      }
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
  /// 1. Verificación previa de integridad del APK (evita "Error al analizar el paquete")
  /// 2. Solicitud previa segura de permiso REQUEST_INSTALL_PACKAGES
  /// 3. Canal nativo installApkNative (FileProvider + ClipData + grantUriPermission explícito)
  /// 4. flutter_app_installer (FileProvider .fileProvider)
  /// 5. OpenFilex (FileProvider independiente en externalFilesDir)
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

    // 1. Verificar que el APK esté íntegro antes de entregárselo a Android
    if (!await _validateApkIntegrity(file)) {
      try {
        await file.delete();
      } catch (_) {}
      throw Exception('El archivo descargado estaba incompleto. Por favor pulsa "Descargar de nuevo".');
    }

    // 2. Manejo preventivo del permiso para instalar paquetes desconocidos
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

    // 3. Intento 1: Instalador nativo propio con concesión explícita de URI a PackageInstaller
    try {
      final nativeResult = await _installerChannel.invokeMethod<bool>(
        'installApkNative',
        {'filePath': filePath},
      );
      if (nativeResult == true) {
        debugPrint('[UpdateService] Instalador iniciado con canal nativo installApkNative.');
        return true;
      }
    } catch (e) {
      debugPrint('[UpdateService] Falló installApkNative: $e. Intentando flutter_app_installer...');
    }

    // 4. Intento 2: flutter_app_installer
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

    // 5. Intento 3: OpenFilex (compatible al estar en getExternalStorageDirectory)
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
      debugPrint('[UpdateService] Falló OpenFilex: $e');
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

