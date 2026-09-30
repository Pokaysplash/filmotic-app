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
  bool _dismissedByUser = false;
  int _adKeyIndex = 0;
  Timer? _rotationTimer;
  Timer? _debounceTimer;
  bool _readyToShow = false;
  DateTime? _lastPauseChange;

  late final FocusNode _closeFocusNode;
  bool _closeFocused = false;

  @override
  void initState() {
    super.initState();
    _closeFocusNode = FocusNode(debugLabel: 'ad_pause_close_btn');
    _closeFocusNode.addListener(() {
      if (mounted) setState(() => _closeFocused = _closeFocusNode.hasFocus);
    });
    _evalState();
  }

  @override
  void didUpdateWidget(covariant AdPauseOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Si el video reanudó reproducción, restablecer el descarte del usuario para la próxima pausa
    if (!widget.isPaused && oldWidget.isPaused) {
      _dismissedByUser = false;
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
        !widget.isControlsOrModalOpen &&
        !_dismissedByUser;

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
          !widget.isControlsOrModalOpen &&
          !_dismissedByUser) {
        setState(() {
          _readyToShow = true;
          _adKeyIndex++;
        });
        _startRotationTimer();
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

  void _closeOverlay() {
    setState(() {
      _dismissedByUser = true;
      _readyToShow = false;
    });
    _rotationTimer?.cancel();
  }

  @override
  void dispose() {
    _rotationTimer?.cancel();
    _debounceTimer?.cancel();
    _closeFocusNode.dispose();
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
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          decoration: BoxDecoration(
            color: const Color(0xF2151518),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0x33FFFFFF),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.7),
                blurRadius: 28,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Barra superior: Etiqueta "PUBLICIDAD" y botón cerrar
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
                  InkWell(
                    onTap: _closeOverlay,
                    borderRadius: BorderRadius.circular(20),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(
                        Icons.close_rounded,
                        color: Colors.white70,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

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
              const SizedBox(height: 12),

              // Botones inferiores: Reanudar y Ocultar anuncio
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // Botón Cerrar anuncio con soporte D-Pad
                  Focus(
                    focusNode: _closeFocusNode,
                    onKeyEvent: (node, event) {
                      if (event is KeyDownEvent &&
                          (event.logicalKey == LogicalKeyboardKey.select ||
                              event.logicalKey == LogicalKeyboardKey.enter)) {
                        _closeOverlay();
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
                    child: GestureDetector(
                      onTap: _closeOverlay,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: _closeFocused
                              ? const Color(0xFFFF6B35)
                              : const Color(0x1AFFFFFF),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _closeFocused
                                ? const Color(0xFFFF6B35)
                                : Colors.white12,
                          ),
                        ),
                        child: Text(
                          'Ocultar anuncio',
                          style: TextStyle(
                            color: _closeFocused ? Colors.white : Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (widget.onResume != null) ...[
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: widget.onResume,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF6B35),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.play_arrow_rounded, color: Colors.white, size: 16),
                            SizedBox(width: 4),
                            Text(
                              'Reanudar',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
