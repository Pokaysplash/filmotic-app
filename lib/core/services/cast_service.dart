import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:media_cast_dlna/media_cast_dlna.dart';

/// Estados posibles de la sesión de casting DLNA
enum CastState {
  idle,
  discovering,
  connected,
  casting,
  error,
}

/// Servicio central de Casting DLNA / UPnP (Controlador DMC)
/// Permite descubrir reproductores DLNA (Xbox, Smart TV, TV Box),
/// enviar streams VOD (películas y series) y controlar la reproducción remota.
class CastService {
  CastService._internal();
  static final CastService instance = CastService._internal();
  factory CastService() => instance;

  final MediaCastDlnaApi _api = MediaCastDlnaApi();
  MediaCastDlnaDiscoveryEvents? _discoveryEvents;

  final ValueNotifier<CastState> stateNotifier =
      ValueNotifier<CastState>(CastState.idle);
  CastState get state => stateNotifier.value;

  final ValueNotifier<bool> isRemotePlaying = ValueNotifier<bool>(false);

  DlnaDevice? _connectedDevice;
  DlnaDevice? get connectedDevice => _connectedDevice;

  String? _lastError;
  String? get lastError => _lastError;

  final List<DlnaDevice> _devices = [];
  List<DlnaDevice> get devices => List.unmodifiable(_devices);

  final StreamController<List<DlnaDevice>> _devicesController =
      StreamController<List<DlnaDevice>>.broadcast();

  StreamSubscription<DlnaDevice>? _foundSub;
  StreamSubscription<DeviceUdn>? _lostSub;
  StreamSubscription<DeviceUdn>? _offlineSub;
  Timer? _discoveryTimeoutTimer;
  bool _isInitialized = false;

  /// Inicializa la API de UPnP/DLNA en Android
  Future<void> init() async {
    if (_isInitialized) return;
    if (!Platform.isAndroid) return;

    try {
      final initialized = await _api.isUpnpServiceInitialized();
      if (!initialized) {
        await _api.initializeUpnpService();
      }
      _discoveryEvents ??= MediaCastDlnaDiscoveryEvents();
      _isInitialized = true;
    } catch (e) {
      debugPrint('[CastService] init error: $e');
    }
  }

  /// Inicia el descubrimiento de dispositivos en la red local y emite la lista en tiempo real
  Stream<List<DlnaDevice>> discoverDevices({
    Duration timeout = const Duration(seconds: 10),
  }) {
    _startDiscovery(timeout);
    return _devicesController.stream;
  }

  Future<void> _startDiscovery(Duration timeout) async {
    if (!Platform.isAndroid) {
      _lastError = 'El casting DLNA está disponible en dispositivos Android.';
      stateNotifier.value = CastState.error;
      return;
    }

    await init();
    _devices.clear();
    _devicesController.add(List.unmodifiable(_devices));
    _lastError = null;
    stateNotifier.value = CastState.discovering;

    _cancelDiscoverySubscriptions();
    _discoveryEvents ??= MediaCastDlnaDiscoveryEvents();

    _foundSub = _discoveryEvents!.onDeviceFound.listen((device) {
      // Ignorar dispositivos sin nombre amigable
      if (device.friendlyName.trim().isEmpty) return;

      final existingIndex = _devices.indexWhere(
        (item) => item.udn.value == device.udn.value,
      );

      if (existingIndex >= 0) {
        _devices[existingIndex] = device;
      } else {
        _devices.add(device);
      }

      _devicesController.add(List.unmodifiable(_devices));
      if (_devices.isNotEmpty && state == CastState.discovering) {
        _lastError = null;
      }
    });

    _lostSub = _discoveryEvents!.onDeviceLost.listen((udn) {
      _devices.removeWhere((item) => item.udn.value == udn.value);
      _devicesController.add(List.unmodifiable(_devices));
    });

    _offlineSub = _discoveryEvents!.onRendererOffline.listen((udn) {
      _devices.removeWhere((item) => item.udn.value == udn.value);
      _devicesController.add(List.unmodifiable(_devices));
      if (_connectedDevice?.udn.value == udn.value) {
        disconnect();
      }
    });

    try {
      // Búsqueda orientada a MediaRenderers (Smart TV, Xbox, TV Box)
      await _api.startDiscovery(
        DiscoveryOptions(
          searchTarget: SearchTarget(
            target: 'urn:schemas-upnp-org:device:MediaRenderer:1',
          ),
          timeout: DiscoveryTimeout(seconds: timeout.inSeconds),
        ),
      );
    } catch (e) {
      debugPrint('[CastService] startDiscovery error: $e');
    }

    _discoveryTimeoutTimer?.cancel();
    _discoveryTimeoutTimer = Timer(timeout, () {
      if (_devices.isEmpty && state == CastState.discovering) {
        _lastError =
            'No se encontraron dispositivos. Asegúrate de estar en la misma red WiFi y que el dispositivo esté encendido.';
        stateNotifier.value = CastState.error;
      }
    });
  }

  void _cancelDiscoverySubscriptions() {
    _discoveryTimeoutTimer?.cancel();
    _foundSub?.cancel();
    _lostSub?.cancel();
    _offlineSub?.cancel();
    _foundSub = null;
    _lostSub = null;
    _offlineSub = null;
  }

  /// Conecta con el dispositivo seleccionado por el usuario (con 1 reintento automático)
  Future<bool> connectToDevice(String deviceUdn) async {
    _lastError = null;

    DlnaDevice? targetDevice;
    try {
      targetDevice = _devices.firstWhere(
        (d) => d.udn.value == deviceUdn,
      );
    } catch (_) {
      if (_connectedDevice != null && _connectedDevice!.udn.value == deviceUdn) {
        targetDevice = _connectedDevice;
      }
    }

    if (targetDevice == null) {
      _lastError = 'Dispositivo no encontrado en la red.';
      stateNotifier.value = CastState.error;
      return false;
    }

    // Reintento de verificación online
    bool isOnline = false;
    for (int attempt = 1; attempt <= 2; attempt++) {
      try {
        isOnline = await _api.isDeviceOnline(targetDevice.udn);
        if (isOnline) break;
      } catch (e) {
        debugPrint('[CastService] connect attempt $attempt failed: $e');
        if (attempt < 2) {
          await Future.delayed(const Duration(milliseconds: 600));
        }
      }
    }

    // Aceptamos la conexión: muchos dispositivos DLNA no responden ping UPnP pero sí llamadas AVTransport
    _connectedDevice = targetDevice;
    stateNotifier.value = CastState.connected;
    return true;
  }

  /// Envía la URL del video y metadatos al dispositivo remoto e inicia la reproducción
  Future<bool> castMedia(
    String videoUrl, {
    String? title,
    String? posterUrl,
  }) async {
    if (_connectedDevice == null) {
      _lastError = 'No hay ningún dispositivo conectado para enviar el video.';
      stateNotifier.value = CastState.error;
      return false;
    }

    if (videoUrl.trim().isEmpty) {
      _lastError = 'La URL del video aún no está disponible.';
      stateNotifier.value = CastState.error;
      return false;
    }

    stateNotifier.value = CastState.casting;
    _lastError = null;

    try {
      final mediaUri = Url(value: videoUrl.trim());
      final metadata = VideoMetadata(
        title: title,
        thumbnailUri: (posterUrl != null && posterUrl.trim().isNotEmpty)
            ? Url(value: posterUrl.trim())
            : null,
      );

      await _api.setMediaUri(_connectedDevice!.udn, mediaUri, metadata);
      await _api.play(_connectedDevice!.udn);
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
    if (_connectedDevice == null) return;
    try {
      await _api.play(_connectedDevice!.udn);
      isRemotePlaying.value = true;
    } catch (e) {
      debugPrint('[CastService] play error: $e');
    }
  }

  /// Pausa la reproducción remota
  Future<void> pause() async {
    if (_connectedDevice == null) return;
    try {
      await _api.pause(_connectedDevice!.udn);
      isRemotePlaying.value = false;
    } catch (e) {
      debugPrint('[CastService] pause error: $e');
    }
  }

  /// Detiene la reproducción remota
  Future<void> stop() async {
    if (_connectedDevice == null) return;
    try {
      await _api.stop(_connectedDevice!.udn);
      isRemotePlaying.value = false;
      stateNotifier.value = CastState.connected;
    } catch (e) {
      debugPrint('[CastService] stop error: $e');
    }
  }

  /// Salta a una posición específica en el dispositivo remoto
  Future<void> seek(Duration position) async {
    if (_connectedDevice == null) return;
    try {
      await _api.seek(
        _connectedDevice!.udn,
        TimePosition(seconds: position.inSeconds),
      );
    } catch (e) {
      debugPrint('[CastService] seek error: $e');
    }
  }

  /// Cierra la conexión, detiene la reproducción remota y resetea el servicio
  Future<void> disconnect() async {
    if (_connectedDevice != null) {
      try {
        await _api.stop(_connectedDevice!.udn);
      } catch (_) {}
    }
    _connectedDevice = null;
    isRemotePlaying.value = false;

    try {
      await _api.stopDiscovery();
    } catch (_) {}

    _cancelDiscoverySubscriptions();
    stateNotifier.value = CastState.idle;
  }
}
