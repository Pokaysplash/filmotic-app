import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../domain/channel.dart';
import '../domain/epg_program.dart';

class EpgProgramDetailModal extends StatelessWidget {
  final LiveChannel channel;
  final EpgProgram program;
  final VoidCallback? onPlay;

  const EpgProgramDetailModal({
    super.key,
    required this.channel,
    required this.program,
    this.onPlay,
  });

  static Future<void> show(
    BuildContext context, {
    required LiveChannel channel,
    required EpgProgram program,
    VoidCallback? onPlay,
  }) {
    return showDialog(
      context: context,
      builder: (ctx) => EpgProgramDetailModal(
        channel: channel,
        program: program,
        onPlay: onPlay,
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final local = dt.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final isLive = program.isCurrentlyAiring;
    final startStr = _formatTime(program.startTime);
    final endStr = _formatTime(program.endTime);
    final durationMins = program.duration.inMinutes;

    return Dialog(
      backgroundColor: const Color(0xFF181820),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header con Canal y Badge
              Row(
                children: [
                  if (channel.logo != null && channel.logo!.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        width: 44,
                        height: 44,
                        color: Colors.white.withValues(alpha: 0.05),
                        child: CachedNetworkImage(
                          imageUrl: channel.logo!,
                          fit: BoxFit.contain,
                          errorWidget: (_, __, ___) => const Icon(Icons.tv, color: Colors.white54),
                        ),
                      ),
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          channel.name,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Row(
                          children: [
                            if (channel.country != null)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                margin: const EdgeInsets.only(right: 6),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  channel.country!.toUpperCase(),
                                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                              ),
                            if (program.category != null && program.category!.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFF6B35).withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  program.category!,
                                  style: const TextStyle(color: Color(0xFFFF6B35), fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (isLive)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE50914),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.fiber_manual_record, color: Colors.white, size: 10),
                          SizedBox(width: 4),
                          Text(
                            'EN VIVO',
                            style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),

              // Título del programa
              Text(
                program.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 8),

              // Horario y Duración
              Row(
                children: [
                  const Icon(Icons.access_time_rounded, color: Colors.white60, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    '$startStr - $endStr ($durationMins min)',
                    style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ],
              ),

              // Barra de progreso si está al aire
              if (isLive) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: program.progress,
                    backgroundColor: Colors.white12,
                    valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFFF6B35)),
                    minHeight: 4,
                  ),
                ),
              ],

              // Descripción
              if (program.description != null && program.description!.isNotEmpty) ...[
                const SizedBox(height: 16),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 140),
                  child: SingleChildScrollView(
                    child: Text(
                      program.description!,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // Botones de acción
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cerrar', style: TextStyle(color: Colors.white60)),
                  ),
                  const SizedBox(width: 12),
                  if (onPlay != null)
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF6B35),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      ),
                      onPressed: () {
                        Navigator.of(context).pop();
                        onPlay!();
                      },
                      icon: Icon(isLive ? Icons.play_arrow_rounded : Icons.tv_rounded),
                      label: Text(
                        isLive ? 'Ver ahora' : 'Sintonizar canal',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
