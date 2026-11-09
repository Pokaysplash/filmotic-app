import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/versiones.dart'; // ← VersionService
import '../../../core/services/update_service.dart';
import '../../../core/storage/app_database.dart';

import 'config_shared.dart';
import 'appearance/appearance_section.dart';
import '../../../presentation/tv/tv_shell.dart' as tv;
import '../../profile/presentation/profile_selection_page.dart';

class ConfigPage extends StatefulWidget {
  const ConfigPage({super.key});

  @override
  State<ConfigPage> createState() => _ConfigPageState();
}

class _ConfigPageState extends State<ConfigPage> {
  bool _loading = true;
  bool _loadingSettings = true;
  String? _error;
  Map<String, dynamic>? _versionData;

  bool _downloading = false;
  double _downloadProgress = 0;
  String? _downloadError;

  @override
  void initState() {
    super.initState();
    _checkVersion();
    _loadAllSettings();
  }

  Future<void> _loadAllSettings() async {
    await AppDatabase.instance.init();
    if (!mounted) return;
    setState(() {
      _loadingSettings = false;
    });
  }

  Future<bool?> _confirmDialog({
    required String title,
    required String body,
    String confirmLabel = 'Activar',
    Color accent = kAccentColor,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: kCardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          body,
          style: const TextStyle(color: Colors.white70, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancelar',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  Future<void> _switchToTv() async {
    final ok = await _confirmDialog(
      title: 'Cambiar a vista TV',
      body:
          'Se aplicará la interfaz optimizada para TV (orientación horizontal).\n\n¿Deseas continuar?',
      confirmLabel: 'Cambiar ahora',
      accent: kAccentColor,
    );
    if (ok != true) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_mode', 'tv');
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const tv.MainHome()),
      (_) => false,
    );
  }


  // ==================== VERSIÓN (VersionService) ====================
  Future<void> _checkVersion({bool manual = false}) async {
    setState(() {
      _loading = true;
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
          _versionData = {
            'has_update': status.requiresUpdate,
            'is_required': status.isForceUpdate,
            'version_name': v.versionAceptada,
            'version_title': status.requiresUpdate
                ? 'Nueva versión ${v.versionAceptada}'
                : 'Estás al día',
            'version_description': v.novedades,
            'download_url': v.urlApk,
            'version_code': v.versionCodeAceptada,
          };
          _loading = false;
        });

        if (manual) {
          if (status.requiresUpdate) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('¡Nueva versión disponible: v${v.versionAceptada}!'),
                backgroundColor: kAccentColor,
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
          _versionData = {
            'has_update': false,
            'is_required': false,
            'version_name': VersionService.currentVersionName,
            'version_title': status.message,
            'version_description': '',
            'download_url': '',
            'version_code': VersionService.currentVersionCode,
          };
          _error = status.message.contains('No se pudo') ? 'Sin conexión' : null;
          _loading = false;
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
        _loading = false;
        _versionData = {
          'has_update': false,
          'is_required': false,
          'version_name': VersionService.currentVersionName,
          'version_title': '',
          'version_description': '',
          'download_url': '',
          'version_code': VersionService.currentVersionCode,
        };
      });
      if (manual) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error al comprobar actualizaciones'),
            backgroundColor: Color(0xFFDC2626),
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _downloadAndInstallApk(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      setState(() => _downloadError = 'No hay enlace de descarga');
      return;
    }

    if (!Platform.isAndroid) {
      await _openDownload(trimmed);
      return;
    }

    setState(() {
      _downloading = true;
      _downloadProgress = 0;
      _downloadError = null;
    });

    try {
      final targetVer = _versionData?['version_name']?.toString() ?? 'latest';
      final filePath = await UpdateService.instance.downloadApk(
        url: trimmed,
        onProgress: (received, total) {
          if (total > 0 && mounted) {
            setState(() => _downloadProgress = received / total);
          }
        },
      );

      await UpdateService.instance.installApk(
        filePath: filePath,
        targetVersion: targetVer,
      );
    } catch (e) {
      debugPrint('Error descarga/instalación APK: $e');
      if (mounted) {
        setState(() => _downloadError = UpdateService.formatUserFriendlyError(e));
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _openDownload(String url) async {
    if (url.isEmpty) return;
    final uri = Uri.parse(url);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(uri);
      }
    } catch (e) {
      debugPrint('Error abriendo enlace: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo abrir el enlace'),
            backgroundColor: Color(0xFF1a1a1a),
          ),
        );
      }
    }
  }

  void _openSection({
    required String title,
    required IconData icon,
    required Color accent,
    required Widget Function(VoidCallback refresh) builder,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StatefulBuilder(
          builder: (context, setSectionState) {
            void refresh() {
              setSectionState(() {});
            }

            return _ConfigSectionPage(
              title: title,
              icon: icon,
              accent: accent,
              child: builder(refresh),
            );
          },
        ),
      ),
    );
  }


  Widget _buildSectionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accent,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: kCardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 14, 16),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: accent, size: 26),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.55),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.white.withValues(alpha: 0.35),
                  size: 24,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVersionCard() {
    final hasUpdate = _versionData?['has_update'] == true;
    final isRequired = _versionData?['is_required'] == true;
    final latestName = _versionData?['version_name']?.toString() ?? '';
    final latestTitle = _versionData?['version_title']?.toString() ?? '';
    final description = _versionData?['version_description']?.toString() ?? '';
    final downloadUrl = _versionData?['download_url']?.toString() ?? '';

    final pct = (_downloadProgress * 100).clamp(0, 100).toStringAsFixed(0);
    final errorMsg = _downloadError ?? _error;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: kCardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasUpdate
              ? (isRequired
                  ? kAccentColor.withValues(alpha: 0.6)
                  : Colors.white.withValues(alpha: 0.15))
              : Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: hasUpdate
                        ? kAccentColor.withValues(alpha: 0.15)
                        : Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    hasUpdate
                        ? Icons.system_update_rounded
                        : Icons.check_circle_outline_rounded,
                    color: hasUpdate ? kAccentColor : Colors.greenAccent,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _downloading
                            ? (_downloadProgress > 0.02
                                ? 'Descargando $pct%'
                                : 'Descargando…')
                            : hasUpdate
                                ? (isRequired
                                    ? 'Actualización obligatoria'
                                    : 'Nueva versión disponible')
                                : 'Estás al día',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Versión actual: ${VersionService.currentVersionName} (${VersionService.currentVersionCode})',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (hasUpdate) ...[
            const Divider(color: Color(0xFF2C2C2E), height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    latestTitle.isNotEmpty
                        ? latestTitle
                        : 'Versión $latestName',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'v$latestName',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 13,
                    ),
                  ),
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      description.replaceAll('\\n', '\n'),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.75),
                        fontSize: 13.5,
                        height: 1.45,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (errorMsg != null) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Text(
                  errorMsg,
                  style: const TextStyle(
                    color: Color(0xFFFF6B6B),
                    fontSize: 12,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => _openDownload(downloadUrl),
                    icon: const Icon(Icons.open_in_browser_rounded, size: 16),
                    label: const Text('Descargar desde el navegador'),
                    style: TextButton.styleFrom(
                      foregroundColor: kAccentColor,
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ),
              ),
            ],
            if (_downloading) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value:
                        _downloadProgress > 0.02 ? _downloadProgress : null,
                    backgroundColor: Colors.white12,
                    color: kAccentColor,
                    minHeight: 4,
                  ),
                ),
              ),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: (_downloading || downloadUrl.isEmpty)
                      ? null
                      : () => _downloadAndInstallApk(downloadUrl),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kAccentColor,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor:
                        kAccentColor.withValues(alpha: 0.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: _downloading
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                value: _downloadProgress > 0.02
                                    ? _downloadProgress
                                    : null,
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              _downloadProgress > 0.02
                                  ? 'Descargando $pct%'
                                  : 'Descargando…',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.download_rounded, size: 22),
                            SizedBox(width: 8),
                            Text(
                              'Actualizar ahora',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Center(
                child: TextButton.icon(
                  onPressed: _loading ? null : () => _checkVersion(manual: true),
                  icon: _loading
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
                        )
                      : const Icon(Icons.sync_rounded, size: 16, color: Colors.white70),
                  label: Text(
                    _loading ? 'Comprobando...' : 'Buscar actualizaciones de nuevo',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ),
              ),
            ),
          ] else ...[
            if (errorMsg != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Text(
                  errorMsg,
                  style: const TextStyle(
                    color: Color(0xFFFF6B6B),
                    fontSize: 13,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: SizedBox(
                width: double.infinity,
                height: 46,
                child: OutlinedButton.icon(
                  onPressed: _loading ? null : () => _checkVersion(manual: true),
                  icon: _loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.sync_rounded, size: 20),
                  label: Text(
                    _loading ? 'Comprobando servidores...' : 'Buscar actualizaciones',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    backgroundColor: Colors.white.withValues(alpha: 0.04),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomSafe = MediaQuery.paddingOf(context).bottom;
    final listBottomPad = 40.0 + bottomSafe + 72.0;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: const Text(
          'Configuración',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _loading && _loadingSettings
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : RefreshIndicator(
              color: kAccentColor,
              backgroundColor: kCardColor,
              onRefresh: () async {
                await _checkVersion();
                await _loadAllSettings();
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                padding: EdgeInsets.fromLTRB(16, 8, 16, listBottomPad),
                children: [
                  ValueListenableBuilder<LocalProfile?>(
                    valueListenable: AppDatabase.instance.activeProfileNotifier,
                    builder: (context, activeProf, _) {
                      final pName = activeProf?.nombre ?? 'Principal';
                      final pSubtitle = activeProf?.esInfantil == true
                          ? 'Perfil activo: $pName (Infantil) · Toca para cambiar'
                          : 'Perfil activo: $pName · Toca para cambiar';
                      return _buildSectionCard(
                        title: 'Cambiar perfil',
                        subtitle: pSubtitle,
                        icon: Icons.account_circle_rounded,
                        accent: const Color(0xFFFF6B35),
                        onTap: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const ProfileSelectionPage(
                                allowDismiss: true,
                              ),
                            ),
                          );
                          await _loadAllSettings();
                        },
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  _buildSectionCard(
                    title: 'Apariencia',
                    subtitle: 'Modo de interfaz y vista Android TV',
                    icon: Icons.tv_rounded,
                    accent: const Color(0xFF0EA5E9),
                    onTap: () => _openSection(
                      title: 'Apariencia',
                      icon: Icons.tv_rounded,
                      accent: const Color(0xFF0EA5E9),
                      builder: (refresh) => Column(
                        children: AparienciaSection(
                          onSwitchToTv: _switchToTv,
                        ).build(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildVersionCard(),
                  const SizedBox(height: 8),
                  _buildSectionCard(
                    title: 'Comunidad y soporte',
                    subtitle: 'Únete al grupo oficial de Filmotic',
                    icon: Icons.groups_rounded,
                    accent: const Color(0xFFFF6B35),
                    onTap: () async {
                      final uri = Uri.parse('https://t.me/+GFmv2pzxes8yNTcx');
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    },
                  ),
                ],
              ),
            ),
    );
  }
}



class _ConfigSectionPage extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color accent;
  final Widget child;

  const _ConfigSectionPage({
    required this.title,
    required this.icon,
    required this.accent,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final bottomSafe = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: accent, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
            ),
          ],
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.fromLTRB(16, 8, 16, 40.0 + bottomSafe),
        children: [child],
      ),
    );
  }
}