import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'core/services/remote_config_service.dart';
import 'features/live_tv/data/live_tv_service.dart';
import 'features/live_tv/data/epg_service.dart';
import 'presentation/mobile/mobile_shell.dart' as mobile;
import 'presentation/tv/tv_shell.dart' as tv;
import 'features/downloads/presentation/notification_helper.dart';
import 'features/profile/presentation/profile_selection_page.dart';
import 'presentation/shared/widgets/filmotic_splash_loader.dart';
import 'presentation/shared/widgets/filmotic_update_dialog.dart';
import 'core/storage/app_database.dart';

// Cast: botones de la notificación (play/pause/seek)
import 'features/player/presentation/widgets/cast_manager.dart';
// ⚠ Ajusta la ruta de import al sitio real de cast_manager.dart en tu proyecto.
//    Ejemplos posibles:
//    'features/player/presentation/widgets/cast_manager.dart'
//    'features/player/cast/cast_manager.dart'
//    'widgets/cast_manager.dart'

const String kModeKey = 'app_mode'; // "mobile" | "tv"
const String kDisclaimerKey = 'disclaimer_accepted';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Notificaciones (descargas + cast)
  await NotificationHelper.init();

  // Foreground Task → mantiene descargas Y cast vivos en segundo plano
  // Un solo init: tanto DownloadManager como CastManager reutilizan este servicio
  // y actualizan título/texto/botones con updateService cuando hace falta.
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'downloads_channel',
      channelName: 'Descargas y Cast',
      channelDescription:
          'Progreso de descargas y transmisión Cast a TV',
      channelImportance: NotificationChannelImportance.LOW,
      priority: NotificationPriority.LOW,
      showWhen: false,
    ),
    iosNotificationOptions: const IOSNotificationOptions(
      showNotification: false,
      playSound: false,
    ),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.repeat(5000), // cada 5 s
      autoRunOnBoot: false,
      allowWakeLock: true,
      allowWifiLock: true,
    ),
  );

  // Escuchar botones de la notificación del Cast (vienen del isolate del servicio)
  FlutterForegroundTask.addTaskDataCallback((data) {
    if (data is Map && data['cast_btn'] is String) {
      CastManager().handleNotificationButton(data['cast_btn'] as String);
    }
  });

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Filmotic',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.black,
      ),
      home: const SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  /// loading | mode
  String _screen = 'loading';

  String? _mode; // mobile | tv

  // Foco modo
  final FocusNode _mobileFocus = FocusNode(debugLabel: 'mode_mobile');
  final FocusNode _tvFocus = FocusNode(debugLabel: 'mode_tv');


  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _mobileFocus.dispose();
    _tvFocus.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // FLUJO:
  //  1) Modo (solo 1ª vez)
  //  2) Home / Perfiles directos sin anuncio de bienvenida
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _bootstrap() async {
    // Inicializar configuración remota sin bloquear el arranque
    await RemoteConfigService.instance.initialize();

    // Mostrar el logo de carga durante 2 segundos
    await Future.delayed(const Duration(seconds: 2));

    // Verificar si se requiere actualización forzada u opcional
    const currentVersion = '1.0.1';
    final appConfig = RemoteConfigService.instance.config.app;

    if (RemoteConfigService.instance.isMandatoryUpdateRequired(currentVersion)) {
      if (!mounted) return;
      _showBlockingUpdateDialog(appConfig);
      return;
    }

    final dismissed = await RemoteConfigService.instance.getDismissedVersion();
    if (RemoteConfigService.instance.isOptionalUpdateAvailable(currentVersion, dismissedVersion: dismissed)) {
      if (!mounted) return;
      await _showOptionalUpdateDialog(appConfig);
    }

    final prefs = await SharedPreferences.getInstance();
    final savedMode = prefs.getString(kModeKey);

    if (savedMode == null) {
      // 1) Primera vez → elegir orientación
      if (!mounted) return;
      setState(() => _screen = 'mode');
      _focusAfterFrame(_mobileFocus);
      return;
    }

    _mode = savedMode;
    await _applyOrientation(savedMode);
    unawaited(_refreshLiveTvInBackground());
    await _goToHome();
  }

  Future<void> _refreshLiveTvInBackground() async {
    try {
      final cfg = RemoteConfigService.instance.config.liveTv;
      if (!cfg.enabled) return;
      await LiveTvService.instance.refreshAll();
      await EpgService.instance.purgeAndRefresh();
    } catch (e) {
      debugPrint('[LiveTvRefresher] Error refresco en segundo plano: $e');
    }
  }

  void _showBlockingUpdateDialog(FilmoticAppInfo appInfo) {
    FilmoticUpdateDialog.show(
      context,
      appInfo: appInfo,
      isMandatory: true,
    );
  }

  Future<void> _showOptionalUpdateDialog(FilmoticAppInfo appInfo) async {
    await FilmoticUpdateDialog.show(
      context,
      appInfo: appInfo,
      isMandatory: false,
      onDismissed: () {
        RemoteConfigService.instance.setDismissedVersion(appInfo.latestVersion);
      },
    );
  }

  void _focusAfterFrame(FocusNode node) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) node.requestFocus();
    });
  }

  Future<void> _applyOrientation(String mode) async {
    if (mode == 'tv') {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    }
  }

  Future<void> _onModeChosen(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kModeKey, mode);
    _mode = mode;
    await _applyOrientation(mode);

    if (!mounted) return;
    setState(() => _screen = 'loading');
    await _goToHome();
  }

  Future<void> _goToHome() async {
    if (!mounted) return;

    await AppDatabase.instance.init();
    final profiles = await AppDatabase.instance.getProfiles();

    // Mostrar siempre selector de perfiles si no hay perfil o hay múltiples perfiles
    if (AppDatabase.instance.activeProfile == null || profiles.isNotEmpty) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const ProfileSelectionPage(),
          transitionDuration: const Duration(milliseconds: 350),
          transitionsBuilder: (_, animation, __, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );
      return;
    }

    final mode = _mode ?? 'mobile';
    final Widget home =
        mode == 'tv' ? const tv.MainHome() : const mobile.MainHome();

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => home,
        transitionDuration: const Duration(milliseconds: 350),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  // ── UI ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_screen == 'mode') {
      return _buildModeSelector();
    }
    return const FilmoticSplashLoader();
  }

  // ── 1) Selector Móvil / TV ─────────────────────────────────────────────

  Widget _buildModeSelector() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  '¿Cómo quieres usar la app?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Puedes cambiarlo más adelante desde ajustes',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.55),
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 48),
                _ModeButton(
                  focusNode: _mobileFocus,
                  icon: Icons.phone_android_rounded,
                  title: 'Móvil',
                  subtitle: 'Orientación vertical',
                  onTap: () => _onModeChosen('mobile'),
                  onArrowDown: () => _tvFocus.requestFocus(),
                ),
                const SizedBox(height: 18),
                _ModeButton(
                  focusNode: _tvFocus,
                  icon: Icons.tv_rounded,
                  title: 'TV / Android TV',
                  subtitle: 'Orientación horizontal',
                  onTap: () => _onModeChosen('tv'),
                  onArrowUp: () => _mobileFocus.requestFocus(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Mode button ────────────────────────────────────────────────────────────

class _ModeButton extends StatelessWidget {
  final FocusNode focusNode;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final VoidCallback? onArrowUp;
  final VoidCallback? onArrowDown;

  const _ModeButton({
    required this.focusNode,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.onArrowUp,
    this.onArrowDown,
  });

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: focusNode,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.select ||
            event.logicalKey == LogicalKeyboardKey.enter) {
          onTap();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowUp &&
            onArrowUp != null) {
          onArrowUp!();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowDown &&
            onArrowDown != null) {
          onArrowDown!();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final hasFocus = Focus.of(context).hasFocus;
          return SizedBox(
            width: double.infinity,
            height: 78,
            child: ElevatedButton(
              onPressed: onTap,
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    hasFocus ? const Color(0xFF2A2A2E) : const Color(0xFF1C1C1E),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: hasFocus
                        ? const Color(0xFFFF6B35)
                        : Colors.white.withOpacity(0.12),
                    width: hasFocus ? 2 : 1,
                  ),
                ),
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 20),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF6B35).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: const Color(0xFFFF6B35), size: 26),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.white.withOpacity(0.55),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 16,
                    color: Colors.white.withOpacity(0.4),
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