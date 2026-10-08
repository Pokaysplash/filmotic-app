import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:dart_cast/dart_cast.dart' as dc;

export 'package:dart_cast/dart_cast.dart'
    show CastDevice, CastProtocol, CastMediaType, CastSession, SessionState;

/// Extensiones de compatibilidad con versiones previas
extension CastDeviceCompat on dc.CastDevice {
  String get friendlyName => name;
  UdnCompat get udn => UdnCompat(id);
}

class UdnCompat {
  final String value;
  const UdnCompat(this.value);
  @override
  String toString() => value;
  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is UdnCompat && other.value == value);
  @override
  int get hashCode => value.hashCode;
}

/// Estados posibles de la sesión de casting
enum CastState {
  idle,
  discovering,
  connected,
  casting,
  error,
}

/// Servicio central de Casting unificado (pure Dart: DLNA, Chromecast, AirPlay)
/// Utiliza `dart_cast` con proxy HTTP integrado para inyectar cabeceras HTTP
/// (como Referer y User-Agent) en streams HLS protegidos (Cuevana, PelisPlus, etc.).
class CastService {
  CastService._internal();
  static final CastService instance = CastService._internal();
  factory CastService() => instance;

  late final dc.CastService _dcService = dc.CastService(
    discoveryProviders: [
      dc.ChromecastDiscoveryProvider(),
      dc.AirPlayDiscoveryProvider(),
      dc.DlnaDiscoveryProvider(),
    ],
    sessionFactory: (device) {
      switch (device.protocol) {
        case dc.CastProtocol.chromecast:
          return dc.ChromecastSession(device: device);
        case dc.CastProtocol.airplay:
          return dc.AirPlaySession(device);
        case dc.CastProtocol.dlna:
          return dc.DlnaSession.fromDevice(device);
      }
    },
  );

  dc.CastSession? _activeSession;
  dc.CastSession? get activeSession => _activeSession;

  dc.CastDevice? _connectedDevice;
  dc.CastDevice? get connectedDevice => _connectedDevice;

  final ValueNotifier<CastState> stateNotifier =
      ValueNotifier<CastState>(CastState.idle);
  CastState get state => stateNotifier.value;

  final ValueNotifier<bool> isRemotePlaying = ValueNotifier<bool>(false);

  String? _lastError;
  String? get lastError => _lastError;

  final List<dc.CastDevice> _devices = [];
  List<dc.CastDevice> get devices => List.unmodifiable(_devices);

  final StreamController<List<dc.CastDevice>> _devicesController =
      StreamController<List<dc.CastDevice>>.broadcast();

  StreamSubscription<List<dc.CastDevice>>? _discoverySub;
  StreamSubscription<dc.SessionState>? _sessionStateSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  Timer? _discoveryTimeoutTimer;

  Duration _position = Duration.zero;
  Duration get position => _position;
  final StreamController<Duration> _positionController =
      StreamController<Duration>.broadcast();
  Stream<Duration> get positionStream => _positionController.stream;

  Duration _duration = Duration.zero;
  Duration get duration => _duration;
  final StreamController<Duration> _durationController =
      StreamController<Duration>.broadcast();
  Stream<Duration> get durationStream => _durationController.stream;

  /// Inicialización retrocompatible (no-op en dart_cast pure Dart)
  Future<void> init() async {}

  /// Inicia el descubrimiento de dispositivos en la red local (DLNA, Chromecast, AirPlay)
  Stream<List<dc.CastDevice>> discoverDevices({
    Duration timeout = const Duration(seconds: 10),
  }) {
    _startDiscovery(timeout);
    return _devicesController.stream;
  }

  Future<void> _startDiscovery(Duration timeout) async {
    _devices.clear();
    _devicesController.add(List.unmodifiable(_devices));
    _lastError = null;
    stateNotifier.value = CastState.discovering;

    _discoverySub?.cancel();
    _discoveryTimeoutTimer?.cancel();

    try {
      final stream = _dcService.startDiscovery(timeout: timeout);
      _discoverySub = stream.listen(
        (list) {
          _devices.clear();
          final seenIds = <String>{};
          for (final d in list) {
            if (d.name.trim().isNotEmpty && seenIds.add(d.id)) {
              _devices.add(d);
            }
          }
          _devicesController.add(List.unmodifiable(_devices));
          if (_devices.isNotEmpty && state == CastState.discovering) {
            _lastError = null;
          }
        },
        onError: (err) {
          debugPrint('[CastService] discovery error: $err');
        },
        onDone: () {
          if (state == CastState.discovering) {
            stateNotifier.value =
                _devices.isNotEmpty ? CastState.idle : CastState.error;
            if (_devices.isEmpty) {
              _lastError =
                  'No se encontraron dispositivos. Asegúrate de estar en la misma red WiFi y que el dispositivo esté encendido.';
            }
          }
        },
      );
    } catch (e) {
      debugPrint('[CastService] startDiscovery error: $e');
    }

    _discoveryTimeoutTimer = Timer(timeout, () {
      if (_devices.isEmpty && state == CastState.discovering) {
        _lastError =
            'No se encontraron dispositivos. Asegúrate de estar en la misma red WiFi y que el dispositivo esté encendido.';
        stateNotifier.value = CastState.error;
      } else if (state == CastState.discovering) {
        stateNotifier.value = CastState.idle;
      }
    });
  }

  /// Conecta con el dispositivo seleccionado
  Future<bool> connectToDevice(String deviceId) async {
    _lastError = null;
    dc.CastDevice? targetDevice;
    try {
      targetDevice = _devices.firstWhere(
        (d) => d.id == deviceId,
      );
    } catch (_) {
      if (_connectedDevice != null && _connectedDevice!.id == deviceId) {
        targetDevice = _connectedDevice;
      }
    }

    if (targetDevice == null) {
      _lastError = 'Dispositivo no encontrado en la red.';
      stateNotifier.value = CastState.error;
      return false;
    }

    try {
      final session = await _dcService.connect(targetDevice);
      _activeSession = session;
      _connectedDevice = targetDevice;
      _attachSessionListeners(session);
      stateNotifier.value = CastState.connected;
      return true;
    } catch (e) {
      debugPrint('[CastService] connect error: $e');
      _lastError = 'Error al conectar con ${targetDevice.name}.';
      stateNotifier.value = CastState.error;
      return false;
    }
  }

  void _attachSessionListeners(dc.CastSession session) {
    _sessionStateSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();

    _sessionStateSub = session.stateStream.listen((sessState) {
      debugPrint('[CastService] Session state: $sessState');
      switch (sessState) {
        case dc.SessionState.connecting:
          stateNotifier.value = CastState.connected;
          break;
        case dc.SessionState.connected:
          stateNotifier.value = CastState.connected;
          break;
        case dc.SessionState.loading:
        case dc.SessionState.playing:
        case dc.SessionState.buffering:
          stateNotifier.value = CastState.casting;
          isRemotePlaying.value = (sessState == dc.SessionState.playing);
          break;
        case dc.SessionState.paused:
          stateNotifier.value = CastState.casting;
          isRemotePlaying.value = false;
          break;
        case dc.SessionState.idle:
          isRemotePlaying.value = false;
          if (stateNotifier.value == CastState.casting) {
            stateNotifier.value = CastState.connected;
          }
          break;
        case dc.SessionState.disconnected:
          isRemotePlaying.value = false;
          _activeSession = null;
          _connectedDevice = null;
          stateNotifier.value = CastState.idle;
          break;
      }
    });

    _positionSub = session.positionStream.listen((pos) {
      _position = pos;
      _positionController.add(pos);
    });

    _durationSub = session.durationStream.listen((dur) {
      _duration = dur;
      _durationController.add(dur);
    });
  }

  /// Envía la URL del video y metadatos con cabeceras HTTP (Referer / User-Agent)
  /// al dispositivo remoto a través del proxy HTTP de dart_cast.
  Future<bool> castMedia(
    String videoUrl, {
    String? title,
    String? posterUrl,
    Map<String, String>? headers,
  }) async {
    if (_activeSession == null || _connectedDevice == null) {
      _lastError = 'No hay ningún dispositivo conectado para enviar el video.';
      stateNotifier.value = CastState.error;
      return false;
    }

    final cleanUrl = videoUrl.trim();
    if (cleanUrl.isEmpty) {
      _lastError = 'La URL del video aún no está disponible.';
      stateNotifier.value = CastState.error;
      return false;
    }

    stateNotifier.value = CastState.casting;
    _lastError = null;

    try {
      final mediaType = _detectMediaType(cleanUrl);
      final httpHeaders = Map<String, String>.from(headers ?? {});

      // Inyectar User-Agent estándar si no viene especificado
      if (!httpHeaders.keys.any((k) => k.toLowerCase() == 'user-agent')) {
        httpHeaders['User-Agent'] =
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
      }

      final media = dc.CastMedia(
        url: cleanUrl,
        type: mediaType,
        title: title,
        imageUrl: posterUrl,
        httpHeaders: httpHeaders,
      );

      await _activeSession!.loadMedia(media);
      isRemotePlaying.value = true;
      return true;
    } catch (e) {
      debugPrint('[CastService] castMedia error: $e');
      _lastError =
          'Este dispositivo no puede reproducir este formato. Prueba con otro contenido.';
      stateNotifier.value = CastState.error;
      return false;
    }
  }

  /// Reanuda la reproducción remota
  Future<void> play() async {
    if (_activeSession == null) return;
    try {
      await _activeSession!.play();
      isRemotePlaying.value = true;
    } catch (e) {
      debugPrint('[CastService] play error: $e');
    }
  }

  /// Pausa la reproducción remota
  Future<void> pause() async {
    if (_activeSession == null) return;
    try {
      await _activeSession!.pause();
      isRemotePlaying.value = false;
    } catch (e) {
      debugPrint('[CastService] pause error: $e');
    }
  }

  /// Detiene la reproducción remota
  Future<void> stop() async {
    if (_activeSession == null) return;
    try {
      await _activeSession!.stop();
      isRemotePlaying.value = false;
      stateNotifier.value = CastState.connected;
    } catch (e) {
      debugPrint('[CastService] stop error: $e');
    }
  }

  /// Salta a una posición específica en el dispositivo remoto
  Future<void> seek(Duration position) async {
    if (_activeSession == null) return;
    try {
      await _activeSession!.seek(position);
    } catch (e) {
      debugPrint('[CastService] seek error: $e');
    }
  }

  /// Cierra la conexión, detiene la reproducción remota y resetea el servicio
  Future<void> disconnect() async {
    _discoveryTimeoutTimer?.cancel();
    _discoverySub?.cancel();
    _sessionStateSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();

    if (_activeSession != null) {
      try {
        await _activeSession!.stop();
      } catch (_) {}
      try {
        await _activeSession!.disconnect();
      } catch (_) {}
      _activeSession = null;
    }

    _connectedDevice = null;
    isRemotePlaying.value = false;
    stateNotifier.value = CastState.idle;
  }

  static dc.CastMediaType _detectMediaType(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('.m3u8') ||
        lower.contains('.m3u') ||
        lower.contains('hls') ||
        lower.contains('format=m3u8') ||
        lower.contains('/stream/')) {
      return dc.CastMediaType.hls;
    }
    if (lower.contains('.ts')) {
      return dc.CastMediaType.mpegTs;
    }
    if (lower.contains('.mkv')) {
      return dc.CastMediaType.mkv;
    }
    return dc.CastMediaType.mp4;
  }
}
