import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/remote_config_service.dart';
import '../../../core/services/update_service.dart';

/// Diálogo interactivo para descargar e instalar actualizaciones dentro de Filmotic.
class FilmoticUpdateDialog extends StatefulWidget {
  final FilmoticAppInfo appInfo;
  final bool isMandatory;
  final VoidCallback? onDismissed;

  const FilmoticUpdateDialog({
    super.key,
    required this.appInfo,
    this.isMandatory = false,
    this.onDismissed,
  });

  /// Muestra el diálogo modal de actualización
  static Future<void> show(
    BuildContext context, {
    required FilmoticAppInfo appInfo,
    bool isMandatory = false,
    VoidCallback? onDismissed,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: !isMandatory,
      builder: (ctx) => PopScope(
        canPop: !isMandatory,
        child: FilmoticUpdateDialog(
          appInfo: appInfo,
          isMandatory: isMandatory,
          onDismissed: onDismissed,
        ),
      ),
    );
  }

  @override
  State<FilmoticUpdateDialog> createState() => _FilmoticUpdateDialogState();
}

class _FilmoticUpdateDialogState extends State<FilmoticUpdateDialog> {
  bool _downloading = false;
  double _progress = 0.0;
  int _receivedBytes = 0;
  int _totalBytes = 0;
  String? _downloadError;
  String? _cachedFilePath;
  int _attempts = 0;

  static const Color _kOrange = Color(0xFFFF6B35);

  @override
  void initState() {
    super.initState();
    _loadAttempts();
  }

  Future<void> _loadAttempts() async {
    final a = await UpdateService.instance.getUpdateAttempts(widget.appInfo.latestVersion);
    if (mounted) setState(() => _attempts = a);
  }

  Future<void> _startDownloadAndInstall() async {
    final url = widget.appInfo.updateUrl.trim();
    if (url.isEmpty) {
      setState(() => _downloadError = 'No hay enlace de descarga configurado.');
      return;
    }

    if (!Platform.isAndroid) {
      await _openFallbackUrl(url);
      return;
    }

    setState(() {
      _downloading = true;
      _progress = 0.0;
      _receivedBytes = 0;
      _totalBytes = 0;
      _downloadError = null;
    });

    final updatedAttempts = await UpdateService.instance.recordUpdateAttempt(widget.appInfo.latestVersion);
    if (mounted) setState(() => _attempts = updatedAttempts);

    try {
      final dir = await getTemporaryDirectory();
      final filePath = '${dir.path}/filmotic_update.apk';
      final file = File(filePath);
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (_) {}
      }

      final dio = Dio();
      await dio.download(
        url,
        filePath,
        onReceiveProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            _receivedBytes = received;
            _totalBytes = total;
            if (total > 0) {
              _progress = received / total;
            }
          });
        },
        options: Options(
          responseType: ResponseType.bytes,
          followRedirects: true,
          maxRedirects: 5,
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      _cachedFilePath = filePath;

      if (!mounted) return;
      await _installApk(filePath);
    } catch (e) {
      debugPrint('[FilmoticUpdate] Error descargando APK: $e');
      if (mounted) {
        setState(() {
          _downloadError = 'Error de conexión durante la descarga: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _downloading = false);
      }
    }
  }

  Future<void> _installApk(String filePath) async {
    try {
      await UpdateService.instance.markPendingUpdate(widget.appInfo.latestVersion);
      final result = await OpenFilex.open(
        filePath,
        type: 'application/vnd.android.package-archive',
      );

      if (!mounted) return;

      if (result.type != ResultType.done) {
        setState(() {
          _downloadError = result.message.isNotEmpty
              ? result.message
              : 'Para completar la actualización, activa el permiso "Instalar apps desconocidas" en Ajustes de Android.';
        });
      }
    } catch (e) {
      debugPrint('[FilmoticUpdate] Error ejecutando instalador: $e');
      if (mounted) {
        setState(() {
          _downloadError = 'No se pudo iniciar el instalador de Android: $e';
        });
      }
    }
  }

  Future<void> _openFallbackUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1C1C1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      titlePadding: const EdgeInsets.fromLTRB(22, 22, 22, 12),
      contentPadding: const EdgeInsets.fromLTRB(22, 0, 22, 16),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _kOrange.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              widget.isMandatory
                  ? Icons.system_update_rounded
                  : Icons.new_releases_rounded,
              color: _kOrange,
              size: 26,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              widget.isMandatory
                  ? 'Actualización requerida'
                  : 'Nueva versión (${widget.appInfo.latestVersion})',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 17,
              ),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.appInfo.updateMessage,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 14,
                height: 1.45,
              ),
            ),
            if (widget.isMandatory) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white10),
                ),
                child: Text(
                  'Versión mínima requerida: v${widget.appInfo.minVersion}',
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],

            // ── Estado de Descarga en Progreso ──
            if (_downloading) ...[
              const SizedBox(height: 20),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: _progress > 0 ? _progress : null,
                  backgroundColor: Colors.white.withValues(alpha: 0.08),
                  valueColor: const AlwaysStoppedAnimation<Color>(_kOrange),
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _progress > 0
                        ? '${(_progress * 100).toInt()}% descargado'
                        : 'Conectando...',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (_totalBytes > 0) ...[
                    Text(
                      '${(_receivedBytes / (1024 * 1024)).toStringAsFixed(1)} / ${(_totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ],

            // ── Mensaje de Error / Guía de Permisos ──
            if (_downloadError != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.info_outline_rounded, color: Colors.orangeAccent, size: 18),
                        SizedBox(width: 8),
                        Text(
                          'Aviso de instalación',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _downloadError!,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (!_downloading) ...[
          if (!widget.isMandatory) ...[
            TextButton(
              onPressed: () {
                widget.onDismissed?.call();
                Navigator.of(context).pop();
              },
              child: const Text(
                'Más tarde',
                style: TextStyle(color: Colors.white60),
              ),
            ),
          ] else if (_attempts >= 2 || _downloadError != null) ...[
            TextButton(
              onPressed: () async {
                await UpdateService.instance.bypassUpdateFor24Hours(widget.appInfo.latestVersion);
                widget.onDismissed?.call();
                if (context.mounted) Navigator.of(context).pop();
              },
              child: const Text(
                'Continuar sin actualizar',
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
            ),
          ],
          if (_cachedFilePath != null) ...[
            TextButton.icon(
              icon: const Icon(Icons.install_mobile_rounded, size: 18),
              label: const Text('Reintentar instalar'),
              style: TextButton.styleFrom(foregroundColor: _kOrange),
              onPressed: () => _installApk(_cachedFilePath!),
            ),
          ],
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: _kOrange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            icon: const Icon(Icons.download_rounded, size: 18),
            label: Text(_cachedFilePath != null ? 'Descargar de nuevo' : 'Actualizar ahora'),
            onPressed: _startDownloadAndInstall,
          ),
          if (_downloadError != null) ...[
            TextButton.icon(
              icon: const Icon(Icons.open_in_browser_rounded, size: 16),
              label: const Text('Abrir en navegador'),
              style: TextButton.styleFrom(foregroundColor: Colors.white70),
              onPressed: () => _openFallbackUrl(widget.appInfo.updateUrl),
            ),
          ],
        ] else ...[
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Text(
              'No cierres la app mientras se descarga...',
              style: TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ),
        ],
      ],
    );
  }
}
