import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/services/cast_service.dart';

/// Panel central que sustituye al reproductor local cuando se transmite por DLNA
/// (Smart TV, Xbox, TV Box). Muestra el estado, la carátula, y controles remotos.
class DlnaCastingOverlay extends StatefulWidget {
  final String title;
  final String? posterUrl;
  final Duration currentPosition;
  final Duration totalDuration;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onDisconnect;
  final VoidCallback onBackPressed;
  final VoidCallback? onReconnectTimeout;
  final bool isTv;

  const DlnaCastingOverlay({
    super.key,
    required this.title,
    this.posterUrl,
    required this.currentPosition,
    required this.totalDuration,
    required this.onSeek,
    required this.onDisconnect,
    required this.onBackPressed,
    this.onReconnectTimeout,
    this.isTv = false,
  });

  @override
  State<DlnaCastingOverlay> createState() => _DlnaCastingOverlayState();
}

class _DlnaCastingOverlayState extends State<DlnaCastingOverlay> {
  final CastService _castService = CastService.instance;
  late Duration _position;

  // Reconexión automática
  bool _isReconnecting = false;
  int _reconnectSecondsLeft = 30;
  Timer? _reconnectTimer;
  String? _lastDeviceUdn;
  String? _lastDeviceName;

  // D-Pad focus nodes para Android TV
  late final FocusNode _playPauseFocusNode;
  late final FocusNode _rewindFocusNode;
  late final FocusNode _forwardFocusNode;
  late final FocusNode _stopFocusNode;
  late final FocusNode _disconnectFocusNode;
  late final FocusNode _backFocusNode;

  static const Color kOrange = Color(0xFFFF6B35);
  static const Color kBgDark = Color(0xF2101014);

  @override
  void initState() {
    super.initState();
    _position = widget.currentPosition;
    _lastDeviceUdn = _castService.connectedDevice?.udn.value;
    _lastDeviceName = _castService.connectedDevice?.friendlyName ?? 'Dispositivo DLNA';

    _playPauseFocusNode = FocusNode(debugLabel: 'cast_play_pause');
    _rewindFocusNode = FocusNode(debugLabel: 'cast_rewind');
    _forwardFocusNode = FocusNode(debugLabel: 'cast_forward');
    _stopFocusNode = FocusNode(debugLabel: 'cast_stop');
    _disconnectFocusNode = FocusNode(debugLabel: 'cast_disconnect');
    _backFocusNode = FocusNode(debugLabel: 'cast_back');

    _castService.stateNotifier.addListener(_handleCastStateChanged);

    if (widget.isTv) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _playPauseFocusNode.requestFocus();
      });
    }
  }

  @override
  void didUpdateWidget(covariant DlnaCastingOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentPosition != oldWidget.currentPosition) {
      _position = widget.currentPosition;
    }
  }

  void _handleCastStateChanged() {
    if (!mounted) return;
    final state = _castService.state;

    if (state == CastState.connected || state == CastState.casting) {
      _lastDeviceUdn = _castService.connectedDevice?.udn.value;
      _lastDeviceName = _castService.connectedDevice?.friendlyName ?? _lastDeviceName;
      if (_isReconnecting) {
        _stopReconnect(success: true);
      }
    } else if (state == CastState.error || state == CastState.idle) {
      // Si estábamos transmitiendo y la conexión se perdió, iniciar reintento
      if (!_isReconnecting && _lastDeviceUdn != null) {
        _startReconnect();
      }
    }
  }

  void _startReconnect() {
    setState(() {
      _isReconnecting = true;
      _reconnectSecondsLeft = 30;
    });

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }

      setState(() => _reconnectSecondsLeft--);

      // Reintentar reconexión cada 5 segundos
      if (_reconnectSecondsLeft % 5 == 0 && _lastDeviceUdn != null) {
        try {
          final ok = await _castService.connectToDevice(_lastDeviceUdn!);
          if (ok && mounted) {
            _stopReconnect(success: true);
            return;
          }
        } catch (_) {}
      }

      if (_reconnectSecondsLeft <= 0) {
        timer.cancel();
        _stopReconnect(success: false);
      }
    });
  }

  void _stopReconnect({required bool success}) {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    if (!mounted) return;

    setState(() => _isReconnecting = false);

    if (!success) {
      widget.onReconnectTimeout?.call();
    }
  }

  @override
  void dispose() {
    _castService.stateNotifier.removeListener(_handleCastStateChanged);
    _reconnectTimer?.cancel();
    _playPauseFocusNode.dispose();
    _rewindFocusNode.dispose();
    _forwardFocusNode.dispose();
    _stopFocusNode.dispose();
    _disconnectFocusNode.dispose();
    _backFocusNode.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);
    final sMinutes = minutes.toString().padLeft(2, '0');
    final sSeconds = seconds.toString().padLeft(2, '0');
    if (hours > 0) {
      return '$hours:$sMinutes:$sSeconds';
    }
    return '$sMinutes:$sSeconds';
  }

  @override
  Widget build(BuildContext context) {
    final deviceName = _castService.connectedDevice?.friendlyName ?? _lastDeviceName ?? 'TV / Xbox';

    return Container(
      color: kBgDark,
      child: SafeArea(
        child: Stack(
          children: [
            // Contenido principal centrado
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Banner de Reconexión si se perdió la señal
                    if (_isReconnecting) ...[
                      Container(
                        margin: const EdgeInsets.only(bottom: 20),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade900.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.amberAccent, width: 1.2),
                          boxShadow: const [
                            BoxShadow(color: Colors.black45, blurRadius: 10, offset: Offset(0, 4)),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Flexible(
                              child: Text(
                                'Conexión perdida con $deviceName. Reintentando ($_reconnectSecondsLeft s)...',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // Icono Grande de TV con Glow y Badge
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: kOrange.withValues(alpha: 0.12),
                            boxShadow: [
                              BoxShadow(
                                color: kOrange.withValues(alpha: 0.25),
                                blurRadius: 40,
                                spreadRadius: 10,
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.tv_rounded,
                          size: 72,
                          color: kOrange,
                        ),
                        Positioned(
                          right: 14,
                          bottom: 14,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Color(0xFF222222),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.cast_connected_rounded,
                              size: 20,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),

                    // Texto: "Reproduciendo en [Nombre]"
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Colors.greenAccent,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Reproduciendo en $deviceName',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Título del contenido
                    Text(
                      widget.title,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Poster estilizado (si está disponible)
                    if (widget.posterUrl != null && widget.posterUrl!.isNotEmpty) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          width: 110,
                          height: 155,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.6),
                                blurRadius: 16,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Image.network(
                            widget.posterUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: const Color(0xFF222222),
                              child: const Icon(Icons.movie_rounded, color: Colors.white30, size: 40),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],

                    // Barra de progreso remota
                    if (widget.totalDuration > Duration.zero) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          children: [
                            SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 4,
                                activeTrackColor: kOrange,
                                inactiveTrackColor: Colors.white24,
                                thumbColor: kOrange,
                                overlayColor: kOrange.withValues(alpha: 0.2),
                                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                              ),
                              child: Slider(
                                min: 0.0,
                                max: widget.totalDuration.inMilliseconds.toDouble(),
                                value: _position.inMilliseconds
                                    .toDouble()
                                    .clamp(0.0, widget.totalDuration.inMilliseconds.toDouble()),
                                onChanged: (value) {
                                  setState(() => _position = Duration(milliseconds: value.toInt()));
                                },
                                onChangeEnd: (value) {
                                  final newPos = Duration(milliseconds: value.toInt());
                                  widget.onSeek(newPos);
                                  _castService.seek(newPos);
                                },
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    _formatDuration(_position),
                                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                                  ),
                                  Text(
                                    _formatDuration(widget.totalDuration),
                                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Controles remotos (Seek -10s, Play/Pause, Seek +10s, Stop)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Retroceder 10s
                        Focus(
                          focusNode: _rewindFocusNode,
                          child: IconButton(
                            icon: const Icon(Icons.replay_10_rounded, color: Colors.white70, size: 34),
                            tooltip: 'Retroceder 10 segundos',
                            onPressed: () {
                              final newPos = _position - const Duration(seconds: 10);
                              final target = newPos < Duration.zero ? Duration.zero : newPos;
                              setState(() => _position = target);
                              widget.onSeek(target);
                              _castService.seek(target);
                            },
                          ),
                        ),
                        const SizedBox(width: 16),

                        // Play / Pause Remoto
                        ValueListenableBuilder<bool>(
                          valueListenable: _castService.isRemotePlaying,
                          builder: (context, isPlaying, _) {
                            return Focus(
                              focusNode: _playPauseFocusNode,
                              child: GestureDetector(
                                onTap: () {
                                  if (isPlaying) {
                                    _castService.pause();
                                  } else {
                                    _castService.play();
                                  }
                                },
                                child: Container(
                                  width: 68,
                                  height: 68,
                                  decoration: BoxDecoration(
                                    color: kOrange,
                                    shape: BoxShape.circle,
                                    border: _playPauseFocusNode.hasFocus
                                        ? Border.all(color: Colors.white, width: 3)
                                        : null,
                                    boxShadow: [
                                      BoxShadow(
                                        color: kOrange.withValues(alpha: 0.4),
                                        blurRadius: 18,
                                        offset: const Offset(0, 6),
                                      ),
                                    ],
                                  ),
                                  child: Icon(
                                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                    color: Colors.white,
                                    size: 40,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(width: 16),

                        // Avanzar 10s
                        Focus(
                          focusNode: _forwardFocusNode,
                          child: IconButton(
                            icon: const Icon(Icons.forward_10_rounded, color: Colors.white70, size: 34),
                            tooltip: 'Adelantar 10 segundos',
                            onPressed: () {
                              final newPos = _position + const Duration(seconds: 10);
                              final target = newPos > widget.totalDuration ? widget.totalDuration : newPos;
                              setState(() => _position = target);
                              widget.onSeek(target);
                              _castService.seek(target);
                            },
                          ),
                        ),
                        const SizedBox(width: 12),

                        // Stop
                        Focus(
                          focusNode: _stopFocusNode,
                          child: IconButton(
                            icon: const Icon(Icons.stop_circle_outlined, color: Colors.white54, size: 30),
                            tooltip: 'Detener reproducción remota',
                            onPressed: () => _castService.stop(),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Barra superior fija: Botón Atrás y Botón Desconectar
            Positioned(
              top: 10,
              left: 12,
              right: 12,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Focus(
                    focusNode: _backFocusNode,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
                      onPressed: widget.onBackPressed,
                    ),
                  ),
                  Focus(
                    focusNode: _disconnectFocusNode,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF26262B),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                          side: const BorderSide(color: Color(0x33FF6B35), width: 1.2),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      ),
                      icon: const Icon(Icons.cast_connected_rounded, size: 16, color: kOrange),
                      label: const Text(
                        'Desconectar',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      onPressed: widget.onDisconnect,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
