/// Plantilla de configuración de publicidad para Filmotic.
/// Duplicar este archivo como `ads_config.dart` e ingresar los IDs reales.
/// Este archivo NO debe contener credenciales de producción.
library;

class AdsConfig {
  /// ID o Tag del Banner de Adsterra (ej. 320x50)
  static const String adsterraBannerId = "YOUR_ADSTERRA_BANNER_ID_HERE";

  /// URL del endpoint VAST para pre-roll de HilltopAds
  static const String hilltopadsVastUrl = "https://your-vast-endpoint.example.com/vast.xml";

  /// Habilitar o deshabilitar publicidad por defecto
  static const bool enableAdsByDefault = false;
}
