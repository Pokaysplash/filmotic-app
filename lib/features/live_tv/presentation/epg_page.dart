import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../player/presentation/player_page.dart';
import '../data/epg_service.dart';
import '../domain/channel.dart';
import '../domain/epg_program.dart';
import 'epg_program_detail.dart';

class EpgPage extends StatefulWidget {
  final List<LiveChannel> channels;

  const EpgPage({
    super.key,
    required this.channels,
  });

  @override
  State<EpgPage> createState() => _EpgPageState();
}

class _EpgPageState extends State<EpgPage> {
  static const Color kBrandOrange = Color(0xFFFF6B35);
  static const Color kGridBg = Color(0xFF0D0D14);
  static const Color kCardBg = Color(0xFF181824);

  // Cada 30 minutos = 100 píxeles de ancho
  static const double _kPixelsPerMinute = 100.0 / 30.0;
  static const double _kChannelColWidth = 110.0;
  static const double _kRowHeight = 72.0;

  late final DateTime _startTime;
  late final DateTime _endTime;
  final ScrollController _horizontalController = ScrollController();
  final ScrollController _verticalController = ScrollController();

  final Map<String, List<EpgProgram>> _programsMap = {};
  bool _isLoading = true;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now().toUtc();
    // Iniciar 1 hora antes de ahora, hasta 18 horas después
    _startTime = DateTime.utc(now.year, now.month, now.day, now.hour).subtract(const Duration(hours: 1));
    _endTime = _startTime.add(const Duration(hours: 18));

    _loadEpgData();

    _ticker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });

    // Auto-scroll al tiempo actual después de renderizar
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToCurrentTime();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _horizontalController.dispose();
    _verticalController.dispose();
    super.dispose();
  }

  void _scrollToCurrentTime() {
    final now = DateTime.now().toUtc();
    final minsFromStart = now.difference(_startTime).inMinutes;
    if (minsFromStart > 0 && _horizontalController.hasClients) {
      final target = (minsFromStart * _kPixelsPerMinute) - 60.0;
      _horizontalController.animateTo(
        target.clamp(0.0, _horizontalController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _loadEpgData() async {
    final channels = widget.channels.take(30).toList();
    for (final ch in channels) {
      final progs = await EpgService.instance.getProgramsForChannel(ch.id, hours: 20);
      _programsMap[ch.id] = progs;
    }
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  void _onProgramTap(LiveChannel channel, EpgProgram program) {
    EpgProgramDetailModal.show(
      context,
      channel: channel,
      program: program,
      onPlay: () {
        PlayerScreen.openLiveChannel(context, channel);
      },
    );
  }

  String _formatHour(DateTime dt) {
    final local = dt.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final totalMinutes = _endTime.difference(_startTime).inMinutes;
    final totalTimelineWidth = totalMinutes * _kPixelsPerMinute;
    final channels = widget.channels.take(30).toList();

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: const Text(
          'Guía de Programación',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          IconButton(
            tooltip: 'Ir a la hora actual',
            icon: const Icon(Icons.my_location_rounded, color: kBrandOrange),
            onPressed: _scrollToCurrentTime,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: kBrandOrange))
          : Column(
              children: [
                // ── HEADER HORIZONTAL: CANALES LABEL + HORAS ──
                Container(
                  height: 40,
                  color: const Color(0xFF14141E),
                  child: Row(
                    children: [
                      Container(
                        width: _kChannelColWidth,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          border: Border(
                            right: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                            bottom: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                          ),
                        ),
                        child: const Text(
                          'CANAL',
                          style: TextStyle(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          controller: _horizontalController,
                          scrollDirection: Axis.horizontal,
                          physics: const ClampingScrollPhysics(),
                          child: SizedBox(
                            width: totalTimelineWidth,
                            child: Stack(
                              children: [
                                for (int mins = 0; mins < totalMinutes; mins += 30)
                                  Positioned(
                                    left: mins * _kPixelsPerMinute,
                                    child: Container(
                                      width: 100,
                                      padding: const EdgeInsets.only(left: 6, top: 10),
                                      decoration: BoxDecoration(
                                        border: Border(
                                          left: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                                          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                                        ),
                                      ),
                                      child: Text(
                                        _formatHour(_startTime.add(Duration(minutes: mins))),
                                        style: TextStyle(
                                          color: Colors.white.withValues(alpha: 0.7),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
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

                // ── CUERPO: LISTA DE FILAS DE CANALES ──
                Expanded(
                  child: ListView.builder(
                    controller: _verticalController,
                    itemCount: channels.length,
                    itemBuilder: (context, index) {
                      final ch = channels[index];
                      final progs = _programsMap[ch.id] ?? [];
                      return _buildChannelRow(ch, progs, totalTimelineWidth);
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildChannelRow(LiveChannel channel, List<EpgProgram> programs, double totalWidth) {
    return Container(
      height: _kRowHeight,
      decoration: BoxDecoration(
        color: kGridBg,
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
      ),
      child: Row(
        children: [
          // ── Columna fija del Canal ──
          GestureDetector(
            onTap: () => PlayerScreen.openLiveChannel(context, channel),
            child: Container(
              width: _kChannelColWidth,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF12121A),
                border: Border(right: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    padding: const EdgeInsets.all(2),
                    child: channel.logo != null && channel.logo!.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: channel.logo!,
                            fit: BoxFit.contain,
                            errorWidget: (_, __, ___) => const Icon(Icons.tv, color: Colors.white38, size: 18),
                          )
                        : const Icon(Icons.tv, color: Colors.white38, size: 18),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          channel.name,
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (channel.isHD)
                          const Text('HD', style: TextStyle(color: kBrandOrange, fontSize: 9, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Bloques de Programas en la línea de tiempo ──
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              controller: _horizontalController,
              physics: const ClampingScrollPhysics(),
              child: SizedBox(
                width: totalWidth,
                height: _kRowHeight,
                child: Stack(
                  children: [
                    // Grid lines verticales cada 30 min
                    for (int mins = 0; mins < _endTime.difference(_startTime).inMinutes; mins += 30)
                      Positioned(
                        left: mins * _kPixelsPerMinute,
                        top: 0,
                        bottom: 0,
                        child: Container(
                          width: 1,
                          color: Colors.white.withValues(alpha: 0.04),
                        ),
                      ),

                    // Programas
                    if (programs.isEmpty)
                      Positioned(
                        left: 0,
                        top: 6,
                        bottom: 6,
                        width: 300,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          alignment: Alignment.centerLeft,
                          decoration: BoxDecoration(
                            color: kCardBg.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'Sin información de programación',
                            style: TextStyle(color: Colors.white38, fontSize: 12),
                          ),
                        ),
                      )
                    else
                      ...programs.map((p) {
                        final startMins = p.startTime.difference(_startTime).inMinutes;
                        final durationMins = p.duration.inMinutes.clamp(10, 360);
                        final left = startMins * _kPixelsPerMinute;
                        final width = (durationMins * _kPixelsPerMinute) - 3.0;
                        final isLive = p.isCurrentlyAiring;

                        return Positioned(
                          left: left,
                          top: 4,
                          bottom: 4,
                          width: width.clamp(50.0, 800.0),
                          child: GestureDetector(
                            onTap: () => _onProgramTap(channel, p),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                              decoration: BoxDecoration(
                                color: isLive ? const Color(0xFF261A22) : kCardBg,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isLive ? kBrandOrange : Colors.white.withValues(alpha: 0.08),
                                  width: isLive ? 1.5 : 1.0,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Row(
                                    children: [
                                      if (isLive) ...[
                                        Container(
                                          width: 6,
                                          height: 6,
                                          margin: const EdgeInsets.only(right: 5),
                                          decoration: const BoxDecoration(
                                            color: Color(0xFFE50914),
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                      ],
                                      Expanded(
                                        child: Text(
                                          p.title,
                                          style: TextStyle(
                                            color: isLive ? Colors.white : Colors.white.withValues(alpha: 0.9),
                                            fontSize: 12,
                                            fontWeight: isLive ? FontWeight.w700 : FontWeight.w500,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${_formatHour(p.startTime)} - ${_formatHour(p.endTime)}',
                                    style: TextStyle(
                                      color: isLive ? kBrandOrange : Colors.white38,
                                      fontSize: 10,
                                    ),
                                  ),
                                  if (isLive) ...[
                                    const SizedBox(height: 4),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(2),
                                      child: LinearProgressIndicator(
                                        value: p.progress,
                                        minHeight: 2,
                                        backgroundColor: Colors.white12,
                                        valueColor: const AlwaysStoppedAnimation<Color>(kBrandOrange),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
