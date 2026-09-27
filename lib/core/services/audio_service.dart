import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AudioBoostService {
  AudioBoostService._();
  static final AudioBoostService instance = AudioBoostService._();

  static const _channel = MethodChannel('com.example.lol/audio');

  /// Asegura que el volumen multimedia del sistema esté en al menos el 95%
  /// para evitar que el audio suene débil o casi inaudible por defecto.
  Future<void> boostVolume() async {
    try {
      await _channel.invokeMethod('boostVolume');
    } catch (e) {
      debugPrint('[AudioBoostService] Error boosting volume: $e');
    }
  }

  /// Ajusta el volumen a un porcentaje (0.0 a 1.0)
  Future<void> setVolumePercent(double percent) async {
    try {
      await _channel.invokeMethod('setVolumePercent', {'percent': percent});
    } catch (e) {
      debugPrint('[AudioBoostService] Error setting volume: $e');
    }
  }
}
