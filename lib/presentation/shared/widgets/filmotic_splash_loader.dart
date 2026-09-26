import 'dart:math' as math;
import 'package:flutter/material.dart';

class FilmoticSplashLoader extends StatefulWidget {
  final String? message;
  final double logoSize;

  const FilmoticSplashLoader({
    super.key,
    this.message,
    this.logoSize = 78.0,
  });

  @override
  State<FilmoticSplashLoader> createState() => _FilmoticSplashLoaderState();
}

class _FilmoticSplashLoaderState extends State<FilmoticSplashLoader>
    with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseScale;
  late final Animation<double> _glowOpacity;

  late final AnimationController _rotateController;

  @override
  void initState() {
    super.initState();

    // Pulso suave para el resplandor y el logo (respiración)
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _pulseScale = Tween<double>(begin: 0.94, end: 1.05).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeInOutSine,
      ),
    );

    _glowOpacity = Tween<double>(begin: 0.25, end: 0.65).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeInOutSine,
      ),
    );

    // Rotación continua del halo exterior
    _rotateController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _rotateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const primaryOrange = Color(0xFFFF6B35);
    const secondaryOrange = Color(0xFFFF8C42);
    const bgDark = Color(0xFF0B0B0E);

    final size = widget.logoSize;
    final ringSize = size * 1.55;

    return Scaffold(
      backgroundColor: bgDark,
      body: Center(
        child: AnimatedBuilder(
          animation: Listenable.merge([_pulseController, _rotateController]),
          builder: (context, _) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // ── Contenedor del Logo con Halo y Anillo Orbital ──
                SizedBox(
                  width: ringSize + 40,
                  height: ringSize + 40,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // 1. Resplandor ambiental de fondo (Glow)
                      Container(
                        width: ringSize * 1.2,
                        height: ringSize * 1.2,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: primaryOrange.withValues(
                                alpha: _glowOpacity.value,
                              ),
                              blurRadius: 45,
                              spreadRadius: 8,
                            ),
                          ],
                        ),
                      ),

                      // 2. Anillo exterior animado (Spinning Orbit)
                      Transform.rotate(
                        angle: _rotateController.value * 2 * math.pi,
                        child: CustomPaint(
                          size: Size(ringSize, ringSize),
                          painter: _GlowRingPainter(
                            primaryColor: primaryOrange,
                            secondaryColor: secondaryOrange,
                          ),
                        ),
                      ),

                      // 3. Logo central con pulso sutil de respiración
                      Transform.scale(
                        scale: _pulseScale.value,
                        child: Container(
                          width: size,
                          height: size,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [primaryOrange, secondaryOrange],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(size * 0.28),
                            boxShadow: [
                              BoxShadow(
                                color: primaryOrange.withValues(alpha: 0.5),
                                blurRadius: 20,
                                offset: const Offset(0, 6),
                              ),
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.4),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Center(
                            child: Text(
                              'F',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: size * 0.65,
                                height: 1.0,
                                letterSpacing: -0.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 28),

                // ── Tipografía Filmotic ──
                RichText(
                  text: const TextSpan(
                    children: [
                      TextSpan(
                        text: 'Film',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                        ),
                      ),
                      TextSpan(
                        text: 'otic',
                        style: TextStyle(
                          color: primaryOrange,
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 14),

                // ── Mensaje o indicador de puntos sutil ──
                if (widget.message != null && widget.message!.isNotEmpty) ...[
                  Text(
                    widget.message!,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.65),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.3,
                    ),
                  ),
                ] else ...[
                  _PulsingDots(color: primaryOrange.withValues(alpha: 0.8)),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Dibuja un arco con gradiente y terminación circular para el halo giratorio
class _GlowRingPainter extends CustomPainter {
  final Color primaryColor;
  final Color secondaryColor;

  _GlowRingPainter({
    required this.primaryColor,
    required this.secondaryColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Track de fondo tenue
    final trackPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(center, radius, trackPaint);

    // Segmento brillante en gradiente
    final rect = Rect.fromCircle(center: center, radius: radius);
    final sweepGradient = SweepGradient(
      colors: [
        primaryColor.withValues(alpha: 0.0),
        primaryColor.withValues(alpha: 0.4),
        secondaryColor,
      ],
      stops: const [0.0, 0.45, 1.0],
      startAngle: 0.0,
      endAngle: math.pi * 1.5,
    );

    final activePaint = Paint()
      ..shader = sweepGradient.createShader(rect)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;

    canvas.drawArc(
      rect,
      0,
      math.pi * 1.45,
      false,
      activePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _GlowRingPainter oldDelegate) => false;
}

/// Tres puntos sutiles animados para dar feedback visual de carga fluida
class _PulsingDots extends StatefulWidget {
  final Color color;

  const _PulsingDots({required this.color});

  @override
  State<_PulsingDots> createState() => _PulsingDotsState();
}

class _PulsingDotsState extends State<_PulsingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (index) {
            final delay = index * 0.25;
            final progress = (_controller.value - delay) % 1.0;
            final double scale = 0.6 + 0.4 * math.sin(progress * math.pi).abs();
            final double opacity = 0.3 + 0.7 * math.sin(progress * math.pi).abs();

            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: 5.5,
              height: 5.5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color.withValues(alpha: opacity),
              ),
              transform: Matrix4.diagonal3Values(scale, scale, 1.0),
            );
          }),
        );
      },
    );
  }
}
