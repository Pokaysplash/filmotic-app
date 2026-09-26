import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../player/presentation/tv/tv_player_page.dart' as tv_player;
import '../data/epg_service.dart';
import '../domain/channel.dart';
import '../domain/epg_program.dart';
import 'epg_program_detail.dart';

class EpgPageTv extends StatefulWidget {
  final List<LiveChannel> channels;

  const EpgPageTv({
    super.key,
    required this.channels,
  });

  @override
  State<EpgPageTv> createState() => _EpgPageTvState();
}

class _EpgPageTvState extends State<EpgPageTv> {
  static const Color kBrandOrange = Color(0xFFFF6B35);
  static const Color kHeaderBg = Color(0xFF0F0F17);
  static const Color kCardBg = Color(0xFF161622);

  static const double _kPixelsPerMinute = 160.0 / 30.0; // 30 min = 160px en TV
  static const double _kChannelColWidth = 180.0;
  static const double _kRowHeight = 84.0;

  late final DateTime _startTime;
  late final DateTime _endTime;

  final Map<String, List<EpgProgram>> _programsMap = {};
  bool _isLoading = true;

  LiveChannel? _activeChannel;
  EpgProgram? _activeProgram;

  final ScrollController _horizontalController = ScrollController();

  @override
  void initState() {
    super.initState();
    final now = DateTime.now().toUtc();
    _startTime = DateTime.utc(now.year, now.month, now.day, now.hour).subtract(const Duration(hours: 1));
    _endTime = _startTime.add(const Duration(hours: 12));

    if (widget.channels.isNotEmpty) {
      _activeChannel = widget.channels.first;
    }
    _loadEpgData();
  }

  @override
  void dispose() {
    _horizontalController.dispose();
    super.dispose();
  }

  Future<void> _loadEpgData() async {
    final channels = widget.channels.take(25).toList();
    for (final ch in channels) {
      final progs = await EpgService.instance.getProgramsForChannel(ch.id, hours: 14);
      _programsMap[ch.id] = progs;
    }
    if (mounted) {
      setState(() {
        _isLoading = false;
        if (_activeChannel != null) {
          final chProgs = _programsMap[_activeChannel!.id];
          _activeProgram = chProgs != null && chProgs.isNotEmpty ? chProgs.first : null;
        }
      });
    }
  }

  String _formatHour(DateTime dt) {
    final local = dt.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  void _onProgramFocused(LiveChannel channel, EpgProgram program) {
    setState(() {
      _activeChannel = channel;
      _activeProgram = program;
    });
  }

  void _onProgramSelected(LiveChannel channel, EpgProgram? program) {
    if (program != null && program.isCurrentlyAiring) {
      tv_player.PlayerScreen.openLiveChannel(context, channel);
    } else if (program != null) {
      EpgProgramDetailModal.show(
        context,
        channel: channel,
        program: program,
        onPlay: () => tv_player.PlayerScreen.openLiveChannel(context, channel),
      );
    } else {
      tv_player.PlayerScreen.openLiveChannel(context, channel);
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalMinutes = _endTime.difference(_startTime).inMinutes;
    final totalTimelineWidth = totalMinutes * _kPixelsPerMinute;
    final channels = widget.channels.take(25).toList();

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: kBrandOrange))
            : Column(
                children: [
                  // ── TOP HEADER DINÁMICO TV (PROGRAMA EN FOCO) ──
                  _buildDynamicHeader(),

                  // ── REGLA DE TIEMPO HORIZONTAL ──
                  _buildTimeRuler(totalMinutes, totalTimelineWidth),

                  // ── LISTA DE CANALES CON D-PAD ──
                  Expanded(
                    child: ListView.builder(
                      itemCount: channels.length,
                      itemExtent: _kRowHeight,
                      itemBuilder: (context, index) {
                        final ch = channels[index];
                        final progs = _programsMap[ch.id] ?? [];
                        return _buildTvChannelRow(ch, progs, totalTimelineWidth);
                      },
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildDynamicHeader() {
    final ch = _activeChannel;
    final prog = _activeProgram;

    return Container(
      height: 130,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: kHeaderBg,
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
      ),
      child: Row(
        children: [
          // Logo del canal
          Container(
            width: 80,
            height: 80,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: ch?.logo != null && ch!.logo!.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: ch.logo!,
                    fit: BoxFit.contain,
                    errorWidget: (_, __, ___) => const Icon(Icons.tv, color: Colors.white38, size: 36),
                  )
                : const Icon(Icons.tv, color: Colors.white38, size: 36),
          ),
          const SizedBox(width: 16),

          // Detalles del programa enfocado
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Text(
                      ch?.name ?? 'Guía TV',
                      style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 10),
                    if (prog != null && prog.isCurrentlyAiring)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE50914),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('EN VIVO', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                    if (prog?.category != null && prog!.category!.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: kBrandOrange.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          prog.category!,
                          style: const TextStyle(color: kBrandOrange, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  prog?.title ?? (ch?.name ?? 'Sin información de programación'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (prog != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${_formatHour(prog.startTime)} - ${_formatHour(prog.endTime)} (${prog.duration.inMinutes} min)  •  ${prog.description ?? 'Sin descripción disponible.'}',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),

          // Atajo de control
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(
              children: [
                Icon(Icons.play_circle_fill_rounded, color: kBrandOrange, size: 20),
                SizedBox(width: 8),
                Text(
                  'Presiona OK para ver',
                  style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeRuler(int totalMinutes, double totalWidth) {
    return Container(
      height: 38,
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
              style: TextStyle(color: Colors.white60, fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              controller: _horizontalController,
              scrollDirection: Axis.horizontal,
              physics: const ClampingScrollPhysics(),
              child: SizedBox(
                width: totalWidth,
                child: Stack(
                  children: [
                    for (int mins = 0; mins < totalMinutes; mins += 30)
                      Positioned(
                        left: mins * _kPixelsPerMinute,
                        child: Container(
                          width: 160,
                          padding: const EdgeInsets.only(left: 8, top: 8),
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
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
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
    );
  }

  Widget _buildTvChannelRow(LiveChannel channel, List<EpgProgram> programs, double totalWidth) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
      ),
      child: Row(
        children: [
          // ── Columna Canal fija ──
          Focus(
            onFocusChange: (f) {
              if (f) {
                setState(() => _activeChannel = channel);
              }
            },
            child: Container(
              width: _kChannelColWidth,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF101018),
                border: Border(right: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: channel.logo != null && channel.logo!.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: channel.logo!,
                            fit: BoxFit.contain,
                            errorWidget: (_, __, ___) => const Icon(Icons.tv, color: Colors.white38, size: 24),
                          )
                        : const Icon(Icons.tv, color: Colors.white38, size: 24),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          channel.name,
                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (channel.isHD)
                          const Text('HD', style: TextStyle(color: kBrandOrange, fontSize: 10, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Programas navegables por D-Pad ──
          Expanded(
            child: SingleChildScrollView(
              controller: _horizontalController,
              scrollDirection: Axis.horizontal,
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

                    if (programs.isEmpty)
                      Positioned(
                        left: 0,
                        top: 6,
                        bottom: 6,
                        width: 360,
                        child: _TvProgramBlock(
                          title: 'Emisión continua',
                          timeRange: 'Sin guía detallada',
                          isLive: true,
                          onFocused: () => _onProgramFocused(channel, EpgProgram(
                            id: channel.id,
                            channelId: channel.id,
                            title: channel.name,
                            startTime: DateTime.now().toUtc(),
                            endTime: DateTime.now().toUtc().add(const Duration(hours: 2)),
                          )),
                          onSelect: () => _onProgramSelected(channel, null),
                        ),
                      )
                    else
                      ...programs.map((p) {
                        final startMins = p.startTime.difference(_startTime).inMinutes;
                        final durationMins = p.duration.inMinutes.clamp(15, 360);
                        final left = startMins * _kPixelsPerMinute;
                        final width = (durationMins * _kPixelsPerMinute) - 4.0;

                        return Positioned(
                          left: left,
                          top: 6,
                          bottom: 6,
                          width: width.clamp(80.0, 1200.0),
                          child: _TvProgramBlock(
                            title: p.title,
                            timeRange: '${_formatHour(p.startTime)} - ${_formatHour(p.endTime)}',
                            isLive: p.isCurrentlyAiring,
                            progress: p.progress,
                            onFocused: () => _onProgramFocused(channel, p),
                            onSelect: () => _onProgramSelected(channel, p),
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

class _TvProgramBlock extends StatefulWidget {
  final String title;
  final String timeRange;
  final bool isLive;
  final double? progress;
  final VoidCallback onFocused;
  final VoidCallback onSelect;

  const _TvProgramBlock({
    required this.title,
    required this.timeRange,
    required this.isLive,
    this.progress,
    required this.onFocused,
    required this.onSelect,
  });

  @override
  State<_TvProgramBlock> createState() => _TvProgramBlockState();
}

class _TvProgramBlockState extends State<_TvProgramBlock> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    const kBrandOrange = Color(0xFFFF6B35);

    return Focus(
      onFocusChange: (f) {
        setState(() => _isFocused = f);
        if (f) {
          widget.onFocused();
          // Asegurar visibilidad al navegar con D-pad
          Scrollable.ensureVisible(
            context,
            alignment: 0.5,
            duration: const Duration(milliseconds: 150),
          );
        }
      },
      child: InkWell(
        onTap: widget.onSelect,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: _isFocused
                ? const Color(0xFF2E2436)
                : widget.isLive
                    ? const Color(0xFF201622)
                    : const Color(0xFF161622),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _isFocused ? kBrandOrange : Colors.white.withValues(alpha: 0.1),
              width: _isFocused ? 3.0 : 1.0,
            ),
            boxShadow: _isFocused
                ? [
                    BoxShadow(
                      color: kBrandOrange.withValues(alpha: 0.4),
                      blurRadius: 12,
                      spreadRadius: 1,
                    )
                  ]
                : null,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  if (widget.isLive) ...[
                    Container(
                      width: 7,
                      height: 7,
                      margin: const EdgeInsets.only(right: 6),
                      decoration: const BoxDecoration(
                        color: Color(0xFFE50914),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                  Expanded(
                    child: Text(
                      widget.title,
                      style: TextStyle(
                        color: _isFocused ? Colors.white : Colors.white.withValues(alpha: 0.9),
                        fontSize: 13,
                        fontWeight: _isFocused || widget.isLive ? FontWeight.bold : FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                widget.timeRange,
                style: TextStyle(
                  color: _isFocused ? kBrandOrange : Colors.white54,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (widget.isLive && widget.progress != null) ...[
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: widget.progress!,
                    minHeight: 3,
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
  }
}
