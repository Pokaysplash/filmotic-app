import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'ad_service.dart';
import 'ad_widgets.dart';

/// Overlay de banner publicitario monetizado (Adsterra 320x50) que aparece
/// periódicamente durante la reproducción en una esquina derecha de la pantalla.
/// - En series: cada 15 minutos.
/// - En películas: cada 30 minutos.
/// - Permanece visible durante 5 segundos y desaparece automáticamente.
class PeriodicAdOverlay extends StatefulWidget {
  final Duration? interval;
  final Duration displayDuration;
  final bool isSeries;
  final bool isPaused;
  final bool enabled;
  final bool isTv;

  const PeriodicAdOverlay({
    super.key,
    this.interval,
    this.displayDuration = const Duration(seconds: 5),
    this.isSeries = false,
    this.isPaused = false,
    this.enabled = true,
    this.isTv = false,
  });

  @override
  State<PeriodicAdOverlay> createState() => _PeriodicAdOverlayState();
}

class _PeriodicAdOverlayState extends State<PeriodicAdOverlay>
    with SingleTickerProviderStateMixin {
  Timer? _periodicTimer;
  Timer? _preloadTimer;
  Timer? _dismissTimer;
  bool _isMountedAd = false;
  bool _isVisible = false;
  int _adKeyIndex = 0;
  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  Duration get _effectiveInterval =>
      widget.interval ??
      (widget.isSeries
          ? const Duration(minutes: 15)
          : const Duration(minutes: 30));

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fadeAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeInOut,
    );

    _startPeriodicTimer();
  }

  @override
  void didUpdateWidget(covariant PeriodicAdOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.interval != oldWidget.interval ||
        widget.isSeries != oldWidget.isSeries ||
        widget.enabled != oldWidget.enabled) {
      _startPeriodicTimer();
    }
  }

  void _startPeriodicTimer() {
    _periodicTimer?.cancel();
    _preloadTimer?.cancel();
    if (!widget.enabled || !AdService.instance.enabled) return;

    _periodicTimer = Timer.periodic(_effectiveInterval, (timer) {
      if (!mounted) return;
      if (widget.isPaused) {
        debugPrint(
          '[PeriodicAd] Reproductor pausado. Posponiendo banner periódico.',
        );
        return;
      }
      _triggerAdCycle();
    });
  }

  void _triggerAdCycle() {
    if (!mounted || _isVisible || _isMountedAd) return;

    // 1. Pre-cargar el banner de Adsterra 2.5s antes de mostrarlo para que
    //    los 5 segundos en pantalla sean con el anuncio ya renderizado.
    setState(() {
      _adKeyIndex++;
      _isMountedAd = true;
      _isVisible = false;
    });

    _preloadTimer?.cancel();
    _preloadTimer = Timer(const Duration(milliseconds: 2500), () {
      if (!mounted) return;
      if (widget.isPaused) {
        setState(() {
          _isMountedAd = false;
          _isVisible = false;
        });
        return;
      }
      _showAd();
    });
  }

  void _showAd() {
    if (!mounted) return;
    setState(() => _isVisible = true);
    _animController.forward(from: 0);

    _incrementMetrics();

    // Ocultar exactamente tras 5 segundos (displayDuration)
    _dismissTimer?.cancel();
    _dismissTimer = Timer(widget.displayDuration, () {
      if (!mounted) return;
      _animController.reverse().then((_) {
        if (mounted) {
          setState(() {
            _isVisible = false;
            _isMountedAd = false;
          });
        }
      });
    });
  }

  Future<void> _incrementMetrics() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final current = prefs.getInt('periodic_ads_shown') ?? 0;
      await prefs.setInt('periodic_ads_shown', current + 1);
    } catch (_) {}
  }

  @override
  void dispose() {
    _periodicTimer?.cancel();
    _preloadTimer?.cancel();
    _dismissTimer?.cancel();
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isMountedAd || !AdService.instance.enabled) {
      return const SizedBox.shrink();
    }

    final bannerKey = AdService.instance.adsterraBannerKey;
    if (bannerKey.isEmpty || bannerKey == 'PENDIENTE') {
      return const SizedBox.shrink();
    }

    final double scale = widget.isTv ? 0.95 : 0.82;

    return Positioned(
      top: widget.isTv ? 24 : 14,
      right: widget.isTv ? 24 : 14,
      child: IgnorePointer(
        ignoring: !_isVisible,
        child: FadeTransition(
          opacity: _fadeAnim,
          child: Transform.scale(
            scale: scale,
            alignment: Alignment.topRight,
            child: Container(
              width: 328,
              height: 58,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: const Color(0xD9101014),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.14),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.55),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: KeyedSubtree(
                  key: ValueKey('periodic_banner_${bannerKey}_$_adKeyIndex'),
                  child: AdsterraBannerWidget(
                    bannerKey: bannerKey,
                    margin: EdgeInsets.zero,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
