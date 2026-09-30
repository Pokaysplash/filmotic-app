import 'package:flutter/material.dart';
import 'remote_config_service.dart';
import 'ad_widgets.dart';

/// Servicio de gestión y renderizado de publicidad para Filmotic.
/// Integra banners y anuncios nativos de Adsterra mediante WebViews locales aislados.
/// Respeta la política estricta de CERO publicidad intrusiva durante la reproducción.
class AdService {
  static final AdService _instance = AdService._internal();
  static AdService get instance => _instance;
  factory AdService() => _instance;
  AdService._internal();

  /// Flag general para activar o pausar publicidad (activo por defecto con Adsterra)
  bool enabled = true;

  /// Clave del Banner 320x50 de Adsterra
  String get adsterraBannerKey {
    final ads = RemoteConfigService.instance.config.ads;
    final key = ads['adsterra_banner_key']?.toString() ??
        ads['adsterra_banner_id']?.toString() ??
        '';
    if (key.isNotEmpty && key != 'PENDIENTE') return key;
    return 'b40d7be87e3186a983946460caa04802';
  }

  /// ID del contenedor del Native Banner de Adsterra
  String get adsterraNativeContainerId {
    final ads = RemoteConfigService.instance.config.ads;
    final id = ads['adsterra_native_container_id']?.toString() ?? '';
    if (id.isNotEmpty && id != 'PENDIENTE') return id;
    return 'container-512fc1ea8b3c9db09a992edbaf608772';
  }

  /// URL del script del Native Banner de Adsterra
  String get adsterraNativeScriptUrl {
    final ads = RemoteConfigService.instance.config.ads;
    final url = ads['adsterra_native_script_url']?.toString() ?? '';
    if (url.isNotEmpty && url != 'PENDIENTE') return url;
    return 'https://pl31504029.profitableratecpmnetwork.com/512fc1ea8b3c9db09a992edbaf608772/invoke.js';
  }

  /// Activar o desactivar anuncios en pausa desde remote config
  bool get pauseAdEnabled {
    if (!enabled) return false;
    final ads = RemoteConfigService.instance.config.ads;
    final val = ads['pause_ad_enabled'];
    if (val is bool) return val;
    if (val != null) return val.toString().toLowerCase() == 'true';
    return true;
  }

  /// Período de rotación de anuncios en pausa en segundos (default: 15s)
  int get pauseAdRotationSeconds {
    final ads = RemoteConfigService.instance.config.ads;
    final val = ads['pause_ad_rotation_seconds'];
    if (val is int && val > 0) return val;
    if (val != null) {
      final parsed = int.tryParse(val.toString());
      if (parsed != null && parsed > 0) return parsed;
    }
    return 15;
  }

  /// Clave de la zona de pausa de Adsterra (fallback a banner key si está PENDIENTE)
  String get adsterraPauseBannerId {
    final ads = RemoteConfigService.instance.config.ads;
    final id = ads['adsterra_pause_banner_id']?.toString() ?? '';
    if (id.isNotEmpty && id != 'PENDIENTE') return id;
    return adsterraBannerKey;
  }

  /// URL de HilltopAds VAST (preparado para VAST pre-roll)
  String get hilltopadsVastUrl {
    final ads = RemoteConfigService.instance.config.ads;
    final remoteUrl = ads['hilltopads_vast_url']?.toString();
    if (remoteUrl != null && remoteUrl.isNotEmpty && remoteUrl != 'PENDIENTE') {
      return remoteUrl;
    }
    return '';
  }

  DateTime? _lastPreRollShown;

  /// Inicialización del servicio
  Future<void> initialize() async {
    debugPrint(
        '[Filmotic AdService] Inicializado con Adsterra. Banner Key: $adsterraBannerKey | Native Container: $adsterraNativeContainerId');
  }

  /// Construye el widget de Banner 320x50 para la parte inferior del catálogo o detalle
  Widget buildBanner({EdgeInsetsGeometry? margin}) {
    if (!enabled) return const SizedBox.shrink();

    final key = adsterraBannerKey;
    if (key.isEmpty || key == 'PENDIENTE') {
      return const SizedBox.shrink();
    }

    return AdsterraBannerWidget(
      bannerKey: key,
      margin: margin,
    );
  }

  /// Construye el widget Native Banner camuflado como tarjeta dentro del catálogo
  Widget buildNativeBanner({
    double height = 250,
    EdgeInsetsGeometry? margin,
  }) {
    if (!enabled) return const SizedBox.shrink();

    final containerId = adsterraNativeContainerId;
    final scriptUrl = adsterraNativeScriptUrl;

    if (containerId.isEmpty ||
        containerId == 'PENDIENTE' ||
        scriptUrl.isEmpty ||
        scriptUrl == 'PENDIENTE') {
      return const SizedBox.shrink();
    }

    return AdsterraNativeBannerWidget(
      containerId: containerId,
      scriptUrl: scriptUrl,
      height: height,
      margin: margin,
    );
  }

  /// Método retrocompatible con llamadas previas
  static Widget buildBannerAdSlot({
    EdgeInsetsGeometry margin = const EdgeInsets.symmetric(vertical: 8),
  }) {
    return _instance.buildBanner(margin: margin);
  }

  /// Método retrocompatible con llamadas previas
  static Widget buildNativeCardSlot() {
    return _instance.buildNativeBanner();
  }

  /// Control opcional de anuncios pre-roll (cero anuncios dentro de reproducción)
  Future<void> showPreRollAd(BuildContext context) async {
    final vastUrl = hilltopadsVastUrl;
    if (!enabled || vastUrl.isEmpty || vastUrl == 'PENDIENTE') return;

    final now = DateTime.now();
    if (_lastPreRollShown != null &&
        now.difference(_lastPreRollShown!).inMinutes < 15) {
      return;
    }

    _lastPreRollShown = now;
    debugPrint('[Filmotic AdService] Solicitando VAST Pre-roll...');
  }
}
