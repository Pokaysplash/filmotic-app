import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'remote_config_service.dart';

/// Overlay de banner publicitario que aparece periódicamente durante la reproducción.
/// Aparece en la esquina superior derecha durante [displayDuration] (por defecto 5 segundos)
/// cada [interval] (por defecto 40 minutos), solo si el contenido NO está pausado.
class PeriodicAdOverlay extends StatefulWidget {
  final Duration interval;
  final Duration displayDuration;
  final bool isPaused;
  final bool enabled;
  final bool isTv;

  const PeriodicAdOverlay({
    super.key,
    this.interval = const Duration(minutes: 40),
    this.displayDuration = const Duration(seconds: 5),
    this.isPaused = false,
    this.enabled = true,
    this.isTv = false,
  });

  @override
  State<PeriodicAdOverlay> createState() => _PeriodicAdOverlayState();
}

class _PeriodicAdOverlayState extends State<PeriodicAdOverlay> with SingleTickerProviderStateMixin {
  Timer? _periodicTimer;
  Timer? _dismissTimer;
  bool _isVisible = false;
  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  static const Color _accentOrange = Color(0xFFFF6B35);

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeInOut);

    _startPeriodicTimer();
  }

  @override
  void didUpdateWidget(covariant PeriodicAdOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.interval != oldWidget.interval || widget.enabled != oldWidget.enabled) {
      _startPeriodicTimer();
    }
  }

  void _startPeriodicTimer() {
    _periodicTimer?.cancel();
    if (!widget.enabled) return;

    _periodicTimer = Timer.periodic(widget.interval, (timer) {
      if (!mounted) return;
      // Si el reproductor está pausado, no interferir con el banner de pausa:
      // se pospone para el siguiente ciclo.
      if (widget.isPaused) {
        debugPrint('[PeriodicAd] Reproductor pausado. Posponiendo banner periódico.');
        return;
      }
      _showAd();
    });
  }

  void _showAd() {
    if (!mounted || _isVisible) return;
    setState(() => _isVisible = true);
    _animController.forward();

    // Registrar métrica en Sembast
    _incrementMetrics();

    _dismissTimer?.cancel();
    _dismissTimer = Timer(widget.displayDuration, () {
      if (!mounted) return;
      _animController.reverse().then((_) {
        if (mounted) setState(() => _isVisible = false);
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
    _dismissTimer?.cancel();
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isVisible) return const SizedBox.shrink();

    final width = widget.isTv ? 240.0 : 180.0;
    final height = widget.isTv ? 80.0 : 60.0;

    return Positioned(
      top: widget.isTv ? 28 : 16,
      right: widget.isTv ? 28 : 16,
      child: FadeTransition(
        opacity: _fadeAnim,
        child: IgnorePointer(
          // No debe bloquear los toques o controles del reproductor
          ignoring: false,
          child: Container(
            width: width,
            height: height,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xE6141419),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _accentOrange.withOpacity(0.55),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.6),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: widget.isTv ? 36 : 28,
                  height: widget.isTv ? 36 : 28,
                  decoration: BoxDecoration(
                    color: _accentOrange.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.campaign_rounded,
                    color: _accentOrange,
                    size: widget.isTv ? 22 : 18,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              'AD',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: widget.isTv ? 9.5 : 8.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              'Filmotic Premium',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: widget.isTv ? 12 : 10.5,
                                fontWeight: FontWeight.w700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Disfruta sin límites',
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: widget.isTv ? 10.5 : 9,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
