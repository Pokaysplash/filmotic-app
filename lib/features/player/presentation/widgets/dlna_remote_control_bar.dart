import 'package:flutter/material.dart';
import '../../../../core/services/cast_service.dart';

/// Barra de control remoto minimalista en la parte inferior del reproductor móvil
/// Se muestra cuando hay una sesión activa de Cast hacia Smart TV / Xbox.
class DlnaRemoteControlBar extends StatelessWidget {
  final VoidCallback? onDisconnect;

  const DlnaRemoteControlBar({
    super.key,
    this.onDisconnect,
  });

  static const Color kOrange = Color(0xFFFF6B35);
  static const Color kBgDark = Color(0xEE161616);

  @override
  Widget build(BuildContext context) {
    final castService = CastService.instance;

    return ValueListenableBuilder<CastState>(
      valueListenable: castService.stateNotifier,
      builder: (context, state, _) {
        if (state != CastState.connected && state != CastState.casting) {
          return const SizedBox.shrink();
        }

        final device = castService.connectedDevice;
        final deviceName = device?.friendlyName ?? 'TV';

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: kBgDark,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: kOrange.withValues(alpha: 0.35), width: 1.2),
            boxShadow: const [
              BoxShadow(
                color: Colors.black54,
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              // Icono de Cast conectado animado o pulsante
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: kOrange.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.cast_connected_rounded,
                  color: kOrange,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              // Nombre del dispositivo
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Transmitiendo a $deviceName',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 1),
                    Text(
                      state == CastState.casting
                          ? 'Control remoto activo'
                          : 'Conectado',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              // Botón Play / Pause remoto
              ValueListenableBuilder<bool>(
                valueListenable: castService.isRemotePlaying,
                builder: (context, isPlaying, _) {
                  return IconButton(
                    icon: Icon(
                      isPlaying
                          ? Icons.pause_circle_filled_rounded
                          : Icons.play_circle_filled_rounded,
                      color: Colors.white,
                      size: 32,
                    ),
                    tooltip: isPlaying ? 'Pausar en TV' : 'Reanudar en TV',
                    onPressed: () {
                      if (isPlaying) {
                        castService.pause();
                      } else {
                        castService.play();
                      }
                    },
                  );
                },
              ),
              // Botón Stop remoto
              IconButton(
                icon: const Icon(
                  Icons.stop_circle_outlined,
                  color: Colors.white70,
                  size: 26,
                ),
                tooltip: 'Detener en TV',
                onPressed: () => castService.stop(),
              ),
              // Separador sutil
              Container(
                height: 20,
                width: 1,
                color: Colors.white24,
                margin: const EdgeInsets.symmetric(horizontal: 4),
              ),
              // Botón Desconectar
              IconButton(
                icon: const Icon(
                  Icons.close_rounded,
                  color: Colors.white60,
                  size: 20,
                ),
                tooltip: 'Desconectar de TV',
                onPressed: () async {
                  await castService.disconnect();
                  onDisconnect?.call();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Sesión de Cast finalizada'),
                        backgroundColor: Color(0xFF222222),
                        behavior: SnackBarBehavior.floating,
                        duration: Duration(seconds: 2),
                      ),
                    );
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
