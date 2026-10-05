import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'ad_service.dart';
import 'ad_widgets.dart';

/// Overlay publicitario centrado y discreto para cuando el reproductor está en pausa.
/// Cumple estrictamente:
/// 1. Cero publicidad durante reproducción activa.
/// 2. Visible únicamente cuando el video está en pausa real (tras haber iniciado).
/// 3. Rotación automática configurable (por defecto cada 15 segundos).
/// 4. Desaparición instantánea al reanudar el video.
/// 5. No bloquea los controles de reproducción.
/// 6. Navegación fluida con D-Pad para Android TV y botón "Cerrar".
class AdPauseOverlay extends StatefulWidget {
  final bool isPaused;
  final bool hasStartedPlaying;
  final bool isControlsOrModalOpen;
  final VoidCallback? onAdClicked;
  final VoidCallback? onResume;
  final bool isTv;

  const AdPauseOverlay({
    super.key,
    required this.isPaused,
    required this.hasStartedPlaying,
    this.isControlsOrModalOpen = false,
    this.onAdClicked,
    this.onResume,
    this.isTv = false,
  });

  @override
  State<AdPauseOverlay> createState() => _AdPauseOverlayState();
}

class _AdPauseOverlayState extends State<AdPauseOverlay> {
  int _adKeyIndex = 0;
  Timer? _rotationTimer;
  Timer? _debounceTimer;
  bool _readyToShow = false;
  DateTime? _lastPauseChange;

  late final FocusNode _playFocusNode;
  bool _playFocused = false;

  @override
  void initState() {
    super.initState();
    _playFocusNode = FocusNode(debugLabel: 'ad_pause_play_btn');
    _playFocusNode.addListener(() {
      if (mounted) setState(() => _playFocused = _playFocusNode.hasFocus);
    });
    _evalState();
  }

  @override
  void didUpdateWidget(covariant AdPauseOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!widget.isPaused && oldWidget.isPaused) {
      _readyToShow = false;
      _rotationTimer?.cancel();
      _debounceTimer?.cancel();
    }

    if (widget.isPaused != oldWidget.isPaused ||
        widget.hasStartedPlaying != oldWidget.hasStartedPlaying ||
        widget.isControlsOrModalOpen != oldWidget.isControlsOrModalOpen) {
      _evalState();
    }
  }

  void _evalState() {
    if (!AdService.instance.pauseAdEnabled) {
      _readyToShow = false;
      _rotationTimer?.cancel();
      return;
    }

    final shouldShow = widget.isPaused &&
        widget.hasStartedPlaying &&
        !widget.isControlsOrModalOpen;

    if (!shouldShow) {
      _debounceTimer?.cancel();
      _rotationTimer?.cancel();
      if (_readyToShow) {
        setState(() => _readyToShow = false);
      }
      return;
    }

    // Regla: no mostrar al pulsar pausa repetidamente en menos de 2 segundos (debounce de 800ms)
    final now = DateTime.now();
    _lastPauseChange = now;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 800), () {
      if (!mounted) return;
      if (widget.isPaused &&
          widget.hasStartedPlaying &&
          !widget.isControlsOrModalOpen) {
        setState(() {
          _readyToShow = true;
          _adKeyIndex++;
        });
        _startRotationTimer();
        if (widget.isTv) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _readyToShow) {
              _playFocusNode.requestFocus();
            }
          });
        }
      }
    });
  }

  void _startRotationTimer() {
    _rotationTimer?.cancel();
    final seconds = AdService.instance.pauseAdRotationSeconds;
    if (seconds <= 0) return;

    _rotationTimer = Timer.periodic(Duration(seconds: seconds), (_) {
      if (!mounted) return;
      if (_readyToShow && widget.isPaused) {
        setState(() => _adKeyIndex++);
      }
    });
  }

  void _handleResume() {
    setState(() => _readyToShow = false);
    _rotationTimer?.cancel();
    widget.onResume?.call();
  }

  @override
  void dispose() {
    _rotationTimer?.cancel();
    _debounceTimer?.cancel();
    _playFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_readyToShow) return const SizedBox.shrink();

    final size = MediaQuery.sizeOf(context);
    final isTv = widget.isTv || size.width > 800;
    final containerWidth = (size.width * 0.6).clamp(320.0, 560.0);
    final rawPauseKey = AdService.instance.adsterraPauseBannerId;
    final pauseKey = (rawPauseKey.isNotEmpty && rawPauseKey != 'PENDIENTE')
        ? rawPauseKey
        : AdService.instance.adsterraBannerKey;

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: containerWidth,
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          decoration: BoxDecoration(
            color: const Color(0xF5121215),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: const Color(0x33FFFFFF),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.8),
                blurRadius: 32,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Barra superior: Etiqueta "PUBLICIDAD · PAUSA" (SIN botón cerrar)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0x26FFFFFF),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'PUBLICIDAD · PAUSA',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  const Row(
                    children: [
                      Icon(Icons.pause_circle_outline_rounded, color: Colors.white38, size: 16),
                      SizedBox(width: 4),
                      Text(
                        'Pausado',
                        style: TextStyle(
                          color: Colors.white38,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Contenedor del anuncio rotativo
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  height: 100,
                  width: double.infinity,
                  color: Colors.black26,
                  alignment: Alignment.center,
                  child: KeyedSubtree(
                    key: ValueKey('ad_pause_${pauseKey}_$_adKeyIndex'),
                    child: AdsterraBannerWidget(
                      bannerKey: pauseKey,
                      margin: EdgeInsets.zero,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Botón Único y Prominente: "▶ Reproducir"
              Focus(
                focusNode: _playFocusNode,
                onKeyEvent: (node, event) {
                  if (event is KeyDownEvent &&
                      (event.logicalKey == LogicalKeyboardKey.select ||
                          event.logicalKey == LogicalKeyboardKey.enter ||
                          event.logicalKey == LogicalKeyboardKey.mediaPlay ||
                          event.logicalKey == LogicalKeyboardKey.mediaPlayPause)) {
                    _handleResume();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: GestureDetector(
                  onTap: _handleResume,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF6B35),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _playFocused ? Colors.white : Colors.transparent,
                        width: _playFocused ? 2.5 : 0,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFF6B35).withValues(alpha: _playFocused ? 0.6 : 0.3),
                          blurRadius: _playFocused ? 16 : 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Reproducir',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
