import 'package:flutter/material.dart';

/// Servicio de preparación de publicidad para Filmotic.
/// Compatible con redes no restrictivas como Adsterra (banners) y HilltopAds (VAST pre-roll).
/// No utiliza Google AdMob debido a restricciones de contenido.
class AdService {
  static final AdService _instance = AdService._internal();
  factory AdService() => _instance;
  AdService._internal();

  /// Flag general para activar o desactivar publicidad
  bool enabled = false;

  /// Control de frecuencia para no saturar al usuario
  DateTime? _lastPreRollShown;

  /// Inicializa los SDKs o configuraciones de anuncios (Adsterra / HilltopAds)
  Future<void> initialize() async {
    // Preparado para inicializar SDKs de Adsterra o HilltopAds
    debugPrint('[Filmotic AdService] Inicializado en modo pasivo.');
  }

  /// Muestra anuncio pre-roll (VAST) antes de iniciar reproducción de video si aplica
  Future<void> showPreRollAd(BuildContext context) async {
    if (!enabled) return;

    final now = DateTime.now();
    if (_lastPreRollShown != null &&
        now.difference(_lastPreRollShown!).inMinutes < 15) {
      // Evitar mostrar anuncio si ya se vio uno hace menos de 15 minutos
      return;
    }

    _lastPreRollShown = now;
    debugPrint('[Filmotic AdService] Solicitando VAST Pre-roll (HilltopAds)...');
    // En producción se cargará la URL de VAST / WebView o reproductor pre-roll
  }

  /// Widget de Banner 320x50 discreto para la parte inferior del catálogo o ficha
  static Widget buildBannerAdSlot({
    EdgeInsetsGeometry margin = const EdgeInsets.symmetric(vertical: 8),
  }) {
    // Reserva de espacio discreto (320x50)
    return Container(
      margin: margin,
      alignment: Alignment.center,
      child: Container(
        width: 320,
        height: 50,
        decoration: BoxDecoration(
          color: const Color(0xFF141414),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.ads_click_rounded, size: 18, color: Colors.white24),
            const SizedBox(width: 8),
            Text(
              'Espacio Publicitario Reservado',
              style: TextStyle(
                color: Colors.white24,
                fontSize: 11,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Widget de tarjeta nativa discreta para filas de catálogo
  static Widget buildNativeCardSlot() {
    return Container(
      width: 130,
      margin: const EdgeInsets.only(right: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF181818),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.campaign_outlined, color: Colors.white30, size: 28),
            const SizedBox(height: 6),
            Text(
              'Publicidad',
              style: TextStyle(color: Colors.white30, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
