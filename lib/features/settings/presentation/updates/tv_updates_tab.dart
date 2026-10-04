import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../tv_config_shared.dart';
import '../../../../core/constants/versiones.dart'; // ← VersionService

class ActualizacionesTab extends StatefulWidget {
  final VoidCallback onRequestTabFocus;

  const ActualizacionesTab({
    super.key,
    required this.onRequestTabFocus,
  });

  @override
  State<ActualizacionesTab> createState() => ActualizacionesTabState();
}

class ActualizacionesTabState extends State<ActualizacionesTab>
    with AutomaticKeepAliveClientMixin {
  bool _loadingVersion = true;
  bool _hasUpdate = false;
  bool _isUpToDate = true;
  String? _latestName;
  String? _latestTitle;
  String? _description;
  String? _downloadUrl;
  String? _error;

  bool _downloading = false;
  double _downloadProgress = 0;
  String? _downloadError;

  late final FocusNode _btnVersion;
  late final FocusNode _btnCommunity;

  FocusNode get firstFocusNode => _btnVersion;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _btnVersion = FocusNode(debugLabel: 'cfg_version');
    _btnCommunity = FocusNode(debugLabel: 'cfg_community');
    _checkVersion();
  }

  @override
  void dispose() {
    _btnVersion.dispose();
    _btnCommunity.dispose();
    super.dispose();
  }

  void refresh() => _checkVersion();

  void requestFirstFocus() => _btnVersion.requestFocus();

  // ==================== VERSIÓN (VersionService) ====================
  Future<void> _checkVersion({bool manual = false}) async {
    setState(() {
      _loadingVersion = true;
      _error = null;
      _downloadError = null;
    });

    try {
      final status = manual
          ? await VersionService.forceCheckForUpdate()
          : await VersionService.checkForUpdate();

      if (!mounted) return;

      if (status.latestVersion != null) {
        final v = status.latestVersion!;
        setState(() {
          _hasUpdate = status.requiresUpdate;
          _isUpToDate = !status.requiresUpdate;
          _latestName = v.versionAceptada;
          _latestTitle = status.requiresUpdate
              ? 'Nueva versión ${v.versionAceptada}'
              : null;
          _description = v.novedades.isNotEmpty ? v.novedades : null;
          _downloadUrl = v.urlApk;
          _loadingVersion = false;
        });

        if (manual) {
          if (status.requiresUpdate) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('¡Nueva versión disponible: v${v.versionAceptada}!'),
                backgroundColor: kConfigAccent,
                duration: const Duration(seconds: 4),
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Filmotic está actualizado (v${VersionService.currentVersionName})'),
                backgroundColor: const Color(0xFF22C55E),
                duration: const Duration(seconds: 3),
              ),
            );
          }
        }
      } else {
        setState(() {
          _hasUpdate = false;
          _isUpToDate = true;
          _latestName = null;
          _latestTitle = null;
          _description = null;
          _downloadUrl = null;
          _error = status.message.contains('No se pudo')
              ? 'Sin conexión'
              : null;
          _loadingVersion = false;
        });
        if (manual) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_error ?? status.message),
              backgroundColor: const Color(0xFFDC2626),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Sin conexión';
        _loadingVersion = false;
      });
      if (manual) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo comprobar la actualización'),
            backgroundColor: Color(0xFFDC2626),
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _onVersionTap() async {
    if (_downloading) return;

    if (_hasUpdate && (_downloadUrl?.isNotEmpty ?? false)) {
      await _downloadAndInstallApk();
    } else {
      await _checkVersion(manual: true);
    }
  }

  Future<void> _downloadAndInstallApk() async {
    final url = _downloadUrl?.trim();
    if (url == null || url.isEmpty) {
      setState(() => _downloadError = 'No hay enlace de descarga');
      return;
    }

    if (!Platform.isAndroid) {
      await openExternalUrl(url);
      return;
    }

    setState(() {
      _downloading = true;
      _downloadProgress = 0;
      _downloadError = null;
    });

    try {
      final dir = await getTemporaryDirectory();
      final filePath = '${dir.path}/filmotic_update.apk';
      final file = File(filePath);
      if (await file.exists()) await file.delete();

      final dio = Dio();
      await dio.download(
        url,
        filePath,
        onReceiveProgress: (received, total) {
          if (total > 0 && mounted) {
            setState(() => _downloadProgress = received / total);
          }
        },
        options: Options(
          responseType: ResponseType.bytes,
          followRedirects: true,
          validateStatus: (s) => s != null && s < 500,
        ),
      );

      if (!mounted) return;

      final result = await OpenFilex.open(
        filePath,
        type: 'application/vnd.android.package-archive',
      );

      if (result.type != ResultType.done && mounted) {
        setState(() {
          _downloadError = result.message.isNotEmpty
              ? result.message
              : 'Activa “Instalar apps desconocidas” e inténtalo de nuevo.';
        });
      }
    } catch (e) {
      debugPrint('Error descarga APK: $e');
      if (mounted) {
        setState(() => _downloadError = 'Error al descargar: $e');
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }


  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        sectionTitle('VERSIÓN', first: true),
        _VersionCard(
          focusNode: _btnVersion,
          loading: _loadingVersion,
          downloading: _downloading,
          downloadProgress: _downloadProgress,
          hasUpdate: _hasUpdate,
          isUpToDate: _isUpToDate,
          currentName: VersionService.currentVersionName,
          currentCode: VersionService.currentVersionCode,
          latestName: _latestName,
          latestTitle: _latestTitle,
          description: _description,
          error: _error ?? _downloadError,
          onTap: _onVersionTap,
          onArrowUp: widget.onRequestTabFocus,
          onArrowDown: () => _btnCommunity.requestFocus(),
          onArrowLeft: widget.onRequestTabFocus,
        ),
        const SizedBox(height: 24),
        sectionTitle('COMUNIDAD Y SOPORTE'),
        _CommunityCard(
          focusNode: _btnCommunity,
          onTap: _openTelegram,
          onArrowUp: () => _btnVersion.requestFocus(),
          onArrowDown: null,
          onArrowLeft: widget.onRequestTabFocus,
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Future<void> _openTelegram() async {
    final uri = Uri.parse('https://t.me/+GFmv2pzxes8yNTcx');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class _VersionCard extends StatelessWidget {
  final FocusNode focusNode;
  final bool loading;
  final bool downloading;
  final double downloadProgress;
  final bool hasUpdate;
  final bool isUpToDate;
  final String currentName;
  final int currentCode;
  final String? latestName;
  final String? latestTitle;
  final String? description;
  final String? error;
  final VoidCallback onTap;
  final VoidCallback onArrowUp;
  final VoidCallback? onArrowDown;
  final VoidCallback? onArrowLeft;

  const _VersionCard({
    required this.focusNode,
    required this.loading,
    required this.downloading,
    required this.downloadProgress,
    required this.hasUpdate,
    required this.isUpToDate,
    required this.currentName,
    required this.currentCode,
    required this.latestName,
    required this.latestTitle,
    required this.description,
    required this.error,
    required this.onTap,
    required this.onArrowUp,
    this.onArrowDown,
    this.onArrowLeft,
  });

  @override
  Widget build(BuildContext context) {
    final pct = (downloadProgress * 100).clamp(0, 100).toStringAsFixed(0);

    return Focus(
      focusNode: focusNode,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.arrowUp) {
          onArrowUp();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowDown) {
          onArrowDown?.call();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowLeft) {
          onArrowLeft?.call();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.enter) {
          if (!downloading) onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      onFocusChange: (hasFocus) {
        if (hasFocus) {
          final ctx = focusNode.context;
          if (ctx != null) {
            Scrollable.ensureVisible(
              ctx,
              alignment: 0.2,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            );
          }
        }
      },
      child: Builder(
        builder: (context) {
          final hasFocus = Focus.of(context).hasFocus;
          return GestureDetector(
            onTap: downloading ? null : onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: kConfigCard,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: hasFocus
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.08),
                  width: hasFocus ? 2.5 : 1.5,
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: hasUpdate
                              ? kConfigAccent.withValues(alpha: 0.15)
                              : Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Icon(
                          hasUpdate
                              ? Icons.system_update_rounded
                              : Icons.check_circle_outline_rounded,
                          color:
                              hasUpdate ? kConfigAccent : Colors.greenAccent,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              loading
                                  ? 'Comprobando...'
                                  : downloading
                                      ? (downloadProgress > 0.02
                                          ? 'Descargando $pct%'
                                          : 'Descargando…')
                                      : (hasUpdate
                                          ? 'Nueva versión disponible'
                                          : 'Estás al día'),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Actual: $currentName ($currentCode)',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.45),
                                fontSize: 12.5,
                              ),
                            ),
                            if (hasUpdate && latestName != null) ...[
                              const SizedBox(height: 6),
                              Text(
                                latestTitle?.isNotEmpty == true
                                    ? '$latestTitle  ·  v$latestName'
                                    : 'Nueva: v$latestName',
                                style: TextStyle(
                                  color: kConfigAccent.withValues(alpha: 0.9),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                            if (error != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                error!,
                                style: TextStyle(
                                  color:
                                      Colors.redAccent.withValues(alpha: 0.9),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (downloading)
                        SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(
                            value: downloadProgress > 0.02
                                ? downloadProgress
                                : null,
                            strokeWidth: 2.5,
                            color: kConfigAccent,
                          ),
                        )
                      else if (hasUpdate)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: kConfigAccent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text(
                            'Descargar',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                loading ? Icons.hourglass_top_rounded : Icons.sync_rounded,
                                color: Colors.white70,
                                size: 16,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                loading ? 'Buscando...' : 'Buscar actualizaciones',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  if (downloading) ...[
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value:
                            downloadProgress > 0.02 ? downloadProgress : null,
                        backgroundColor: Colors.white12,
                        color: kConfigAccent,
                        minHeight: 4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CommunityCard extends StatelessWidget {
  final FocusNode focusNode;
  final VoidCallback onTap;
  final VoidCallback onArrowUp;
  final VoidCallback? onArrowDown;
  final VoidCallback? onArrowLeft;

  const _CommunityCard({
    required this.focusNode,
    required this.onTap,
    required this.onArrowUp,
    this.onArrowDown,
    this.onArrowLeft,
  });

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: focusNode,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.arrowUp) {
          onArrowUp();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowDown) {
          onArrowDown?.call();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowLeft) {
          onArrowLeft?.call();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.enter) {
          onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      onFocusChange: (hasFocus) {
        if (hasFocus) {
          final ctx = focusNode.context;
          if (ctx != null) {
            Scrollable.ensureVisible(
              ctx,
              alignment: 0.2,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            );
          }
        }
      },
      child: Builder(
        builder: (context) {
          final hasFocus = Focus.of(context).hasFocus;
          return GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: kConfigCard,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: hasFocus
                      ? kConfigAccent
                      : Colors.white.withValues(alpha: 0.08),
                  width: hasFocus ? 2.5 : 1.5,
                ),
                boxShadow: hasFocus
                    ? [
                        BoxShadow(
                          color: kConfigAccent.withValues(alpha: 0.35),
                          blurRadius: 16,
                          spreadRadius: 2,
                        ),
                      ]
                    : null,
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: kConfigAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: const Icon(
                      Icons.groups_rounded,
                      color: kConfigAccent,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Comunidad y soporte',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Únete al grupo oficial de Filmotic en Telegram para reportes y sugerencias',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.55),
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: hasFocus
                          ? kConfigAccent
                          : Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.open_in_new_rounded,
                          color: hasFocus ? Colors.white : Colors.white70,
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Abrir',
                          style: TextStyle(
                            color: hasFocus ? Colors.white : Colors.white70,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}