import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AudioBoostService {
  AudioBoostService._();
  static final AudioBoostService instance = AudioBoostService._();

  static const _channel = MethodChannel('com.example.lol/audio');

  /// Filmotic no modifica el volumen del sistema operativo de forma automática;
  /// solo asegura que el reproductor interno use el 100% del volumen multimedia disponible.
  Future<void> boostVolume() async {
    // No-op intencional para respetar el nivel de volumen configurado por el usuario en su sistema.
  }

  /// Ajusta el volumen a un porcentaje (0.0 a 1.0)
  Future<void> setVolumePercent(double percent) async {
    try {
      await _channel.invokeMethod('setVolumePercent', {'percent': percent});
    } catch (e) {
      debugPrint('[AudioBoostService] Error setting volume: $e');
    }
  }

  /// Obtiene el porcentaje actual del volumen multimedia (0.0 a 1.0)
  Future<double> getVolumePercent() async {
    try {
      final res = await _channel.invokeMethod<num>('getVolumePercent');
      return (res ?? 1.0).toDouble();
    } catch (e) {
      debugPrint('[AudioBoostService] Error getting volume: $e');
      return 1.0;
    }
  }
}
