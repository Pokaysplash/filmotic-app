import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/services/remote_config_service.dart';
import '../../player/presentation/tv/tv_player_page.dart' as tv_player;
import '../data/epg_service.dart';
import '../data/live_tv_service.dart';
import '../domain/channel.dart';
import '../domain/epg_program.dart';
import 'epg_page_tv.dart';

class LiveTvPageTv extends StatefulWidget {
  final VoidCallback? onRequestMenuFocus;

  const LiveTvPageTv({
    super.key,
    this.onRequestMenuFocus,
  });

  @override
  State<LiveTvPageTv> createState() => _LiveTvPageTvState();
}

class _LiveTvPageTvState extends State<LiveTvPageTv> {
  static const Color kBrandOrange = Color(0xFFFF6B35);
  static const Color kCardBg = Color(0xFF14141E);
  static const Color kCardBgFocused = Color(0xFF222234);

  bool _isLoading = true;
  String? _error;
  List<LiveChannel> _allChannels = [];
  List<LiveChannel> _filteredChannels = [];

  String? _selectedCountry;
  String? _selectedCategory;
  LiveChannel? _focusedChannel;

  final Map<String, _ChannelEpgState> _channelEpgMap = {};
  Timer? _nowTimer;

  final List<Map<String, String>> _countries = [
    {'code': '', 'label': 'Todos los países'},
    {'code': 'co', 'label': '🇨🇴 Colombia'},
    {'code': 'mx', 'label': '🇲🇽 México'},
    {'code': 'ar', 'label': '🇦🇷 Argentina'},
    {'code': 'es', 'label': '🇪🇸 España'},
    {'code': 'us', 'label': '🇺🇸 Estados Unidos'},
  ];

  final List<Map<String, String>> _categories = [
    {'code': '', 'label': 'Todas'},
    {'code': 'sports', 'label': '⚽ Deportes'},
    {'code': 'news', 'label': '📰 Noticias'},
    {'code': 'kids', 'label': '👶 Infantil'},
    {'code': 'movies', 'label': '🎬 Películas'},
    {'code': 'music', 'label': '🎵 Música'},
    {'code': 'documentary', 'label': '🌍 Documentales'},
  ];

  @override
  void initState() {
    super.initState();
    final cfg = RemoteConfigService.instance.config.liveTv;
    _selectedCountry = cfg.defaultCountry.isNotEmpty ? cfg.defaultCountry : 'co';
    _loadChannels();

    _nowTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _nowTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadChannels({bool force = false}) async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final channels = await LiveTvService.instance.loadChannels(
        country: _selectedCountry?.isNotEmpty == true ? _selectedCountry : null,
        group: _selectedCategory?.isNotEmpty == true ? _selectedCategory : null,
        forceRefresh: force,
      );

      if (!mounted) return;
      setState(() {
        _allChannels = channels;
        _filteredChannels = channels;
        if (channels.isNotEmpty) {
          _focusedChannel = channels.first;
        }
        _isLoading = false;
      });

      _fetchEpgForVisible();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Error cargando canales de televisión.';
      });
    }
  }

  void _fetchEpgForVisible() async {
    final ids = _filteredChannels.take(30).map((c) => c.id).toList();
    if (ids.isEmpty) return;

    final epgUrl = LiveTvService.instance.lastEpgUrl;
    await EpgService.instance.loadEpgForChannels(
      ids,
      countryCode: _selectedCountry,
      customEpgUrl: epgUrl,
    );

    for (final ch in _filteredChannels.take(30)) {
      final now = await EpgService.instance.getNowPlaying(ch.id);
      final next = await EpgService.instance.getNextProgram(ch.id);
      if (mounted) {
        setState(() {
          _channelEpgMap[ch.id] = _ChannelEpgState(now: now, next: next);
        });
      }
    }
  }

  void _playChannel(LiveChannel channel) {
    tv_player.PlayerScreen.openLiveChannel(context, channel);
  }

  void _openCountryPicker() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1B1B26),
        title: const Text('Seleccionar País', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: 340,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _countries.length,
            itemBuilder: (_, i) {
              final c = _countries[i];
              final isSel = (_selectedCountry ?? '') == c['code'];
              return ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                tileColor: isSel ? kBrandOrange.withValues(alpha: 0.2) : Colors.transparent,
                title: Text(
                  c['label']!,
                  style: TextStyle(
                    color: isSel ? kBrandOrange : Colors.white,
                    fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                onTap: () {
                  Navigator.of(ctx).pop();
                  setState(() => _selectedCountry = c['code']);
                  _loadChannels();
                },
              );
            },
          ),
        ),
      ),
    );
  }

  void _openCategoryPicker() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1B1B26),
        title: const Text('Seleccionar Categoría', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: 340,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _categories.length,
            itemBuilder: (_, i) {
              final cat = _categories[i];
              final isSel = (_selectedCategory ?? '') == cat['code'];
              return ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                tileColor: isSel ? kBrandOrange.withValues(alpha: 0.2) : Colors.transparent,
                title: Text(
                  cat['label']!,
                  style: TextStyle(
                    color: isSel ? kBrandOrange : Colors.white,
                    fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                onTap: () {
                  Navigator.of(ctx).pop();
                  setState(() => _selectedCategory = cat['code']);
                  _loadChannels();
                },
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // ── TOP HEADER / PREVIEW BAR DINÁMICO ──
            _buildTopPreviewBar(),

            // ── BARRA DE ACCIONES Y FILTROS TV ──
            _buildTvActionsBar(),

            // ── GRID DE CANALES CON D-PAD ──
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: kBrandOrange))
                  : _error != null
                      ? _buildErrorView()
                      : _filteredChannels.isEmpty
                          ? _buildEmptyView()
                          : GridView.builder(
                              padding: const EdgeInsets.fromLTRB(28, 12, 28, 28),
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 4,
                                childAspectRatio: 1.15,
                                crossAxisSpacing: 16,
                                mainAxisSpacing: 16,
                              ),
                              itemCount: _filteredChannels.length,
                              itemBuilder: (context, index) {
                                final channel = _filteredChannels[index];
                                final epg = _channelEpgMap[channel.id];
                                return _TvChannelCard(
                                  channel: channel,
                                  epg: epg,
                                  onFocused: () {
                                    setState(() => _focusedChannel = channel);
                                  },
                                  onSelect: () => _playChannel(channel),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopPreviewBar() {
    final ch = _focusedChannel;
    final epg = ch != null ? _channelEpgMap[ch.id] : null;
    final countryObj = _countries.firstWhere(
      (c) => c['code'] == (ch?.country?.toLowerCase() ?? ''),
      orElse: () => {'label': ch?.country?.toUpperCase() ?? ''},
    );

    return Container(
      height: 140,
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F17),
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
      ),
      child: Row(
        children: [
          // Logo grande
          Container(
            width: 100,
            height: 100,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: ch?.logo != null && ch!.logo!.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: ch.logo!,
                    fit: BoxFit.contain,
                    errorWidget: (_, __, ___) => const Icon(Icons.tv_rounded, color: Colors.white38, size: 40),
                  )
                : const Icon(Icons.tv_rounded, color: Colors.white38, size: 40),
          ),
          const SizedBox(width: 20),

          // Información del canal y programa actual
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Text(
                      ch?.name ?? 'Selecciona un canal',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (ch?.isHD == true)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: kBrandOrange.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: kBrandOrange.withValues(alpha: 0.5)),
                        ),
                        child: const Text('HD', style: TextStyle(color: kBrandOrange, fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                    const SizedBox(width: 8),
                    if (countryObj['label']!.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          countryObj['label']!,
                          style: const TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),

                // Now playing en grande
                if (epg?.now != null) ...[
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE50914),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('EN VIVO', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
                      ),
                      Expanded(
                        child: Text(
                          epg!.now!.title,
                          style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  if (epg.now!.description != null && epg.now!.description!.isNotEmpty)
                    Text(
                      epg.now!.description!,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ] else ...[
                  Text(
                    ch?.group ?? 'Canal de televisión abierta',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13),
                  ),
                ],
              ],
            ),
          ),

          // Botón Guía TV
          _TvActionButton(
            icon: Icons.calendar_view_week_rounded,
            label: 'Guía Completa',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => EpgPageTv(channels: _allChannels),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTvActionsBar() {
    final curCountry = _countries.firstWhere(
      (c) => c['code'] == (_selectedCountry ?? ''),
      orElse: () => {'label': 'Todos'},
    );
    final curCategory = _categories.firstWhere(
      (cat) => cat['code'] == (_selectedCategory ?? ''),
      orElse: () => {'label': 'Todas'},
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 8),
      color: Colors.black,
      child: Row(
        children: [
          _TvFilterChip(
            label: 'País: ${curCountry['label']}',
            onTap: _openCountryPicker,
          ),
          const SizedBox(width: 12),
          _TvFilterChip(
            label: 'Categoría: ${curCategory['label']}',
            onTap: _openCategoryPicker,
          ),
          const SizedBox(width: 12),
          _TvFilterChip(
            label: 'Refrescar',
            icon: Icons.refresh_rounded,
            onTap: () => _loadChannels(force: true),
          ),
          const Spacer(),
          Text(
            '${_filteredChannels.length} canales disponibles',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.signal_wifi_bad_rounded, color: Colors.white38, size: 56),
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: Colors.white70, fontSize: 16)),
          const SizedBox(height: 16),
          _TvActionButton(
            icon: Icons.refresh_rounded,
            label: 'Reintentar',
            onTap: () => _loadChannels(force: true),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.tv_off_rounded, color: Colors.white24, size: 56),
          const SizedBox(height: 12),
          Text(
            'No hay canales disponibles para esta categoría o país.',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 16),
          ),
        ],
      ),
    );
  }
}

class _TvChannelCard extends StatefulWidget {
  final LiveChannel channel;
  final _ChannelEpgState? epg;
  final VoidCallback onFocused;
  final VoidCallback onSelect;

  const _TvChannelCard({
    required this.channel,
    required this.epg,
    required this.onFocused,
    required this.onSelect,
  });

  @override
  State<_TvChannelCard> createState() => _TvChannelCardState();
}

class _TvChannelCardState extends State<_TvChannelCard> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    const kBrandOrange = Color(0xFFFF6B35);

    return Focus(
      onFocusChange: (f) {
        setState(() => _isFocused = f);
        if (f) widget.onFocused();
      },
      child: InkWell(
        onTap: widget.onSelect,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedScale(
          scale: _isFocused ? 1.05 : 1.0,
          duration: const Duration(milliseconds: 150),
          child: Container(
            decoration: BoxDecoration(
              color: _isFocused ? const Color(0xFF222234) : const Color(0xFF14141E),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _isFocused ? kBrandOrange : Colors.white.withValues(alpha: 0.08),
                width: _isFocused ? 3.0 : 1.0,
              ),
              boxShadow: _isFocused
                  ? [
                      BoxShadow(
                        color: kBrandOrange.withValues(alpha: 0.35),
                        blurRadius: 16,
                        spreadRadius: 2,
                      )
                    ]
                  : null,
            ),
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Logo
                    Container(
                      width: 44,
                      height: 44,
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: widget.channel.logo != null && widget.channel.logo!.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: widget.channel.logo!,
                              fit: BoxFit.contain,
                              errorWidget: (_, __, ___) => const Icon(Icons.tv, color: Colors.white38, size: 24),
                            )
                          : const Icon(Icons.tv, color: Colors.white38, size: 24),
                    ),
                    const Spacer(),
                    if (widget.channel.isHD)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: kBrandOrange.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: kBrandOrange.withValues(alpha: 0.5)),
                        ),
                        child: const Text('HD', style: TextStyle(color: kBrandOrange, fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  widget.channel.name,
                  style: TextStyle(
                    color: _isFocused ? Colors.white : Colors.white70,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const Spacer(),
                if (widget.epg?.now != null) ...[
                  Row(
                    children: [
                      const Icon(Icons.fiber_manual_record, color: kBrandOrange, size: 8),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          widget.epg!.now!.title,
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: widget.epg!.now!.progress,
                      minHeight: 2.5,
                      backgroundColor: Colors.white12,
                      valueColor: const AlwaysStoppedAnimation<Color>(kBrandOrange),
                    ),
                  ),
                ] else ...[
                  Text(
                    widget.channel.group ?? 'En vivo',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 11),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TvActionButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _TvActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  State<_TvActionButton> createState() => _TvActionButtonState();
}

class _TvActionButtonState extends State<_TvActionButton> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    const kBrandOrange = Color(0xFFFF6B35);

    return Focus(
      onFocusChange: (f) => setState(() => _isFocused = f),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: _isFocused ? kBrandOrange : Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _isFocused ? Colors.white : Colors.white.withValues(alpha: 0.15),
            ),
          ),
          child: Row(
            children: [
              Icon(widget.icon, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TvFilterChip extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback onTap;

  const _TvFilterChip({
    required this.label,
    this.icon,
    required this.onTap,
  });

  @override
  State<_TvFilterChip> createState() => _TvFilterChipState();
}

class _TvFilterChipState extends State<_TvFilterChip> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    const kBrandOrange = Color(0xFFFF6B35);

    return Focus(
      onFocusChange: (f) => setState(() => _isFocused = f),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: _isFocused ? kBrandOrange.withValues(alpha: 0.3) : const Color(0xFF1B1B26),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _isFocused ? kBrandOrange : Colors.white.withValues(alpha: 0.1),
              width: _isFocused ? 2 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, color: _isFocused ? kBrandOrange : Colors.white70, size: 14),
                const SizedBox(width: 6),
              ],
              Text(
                widget.label,
                style: TextStyle(
                  color: _isFocused ? Colors.white : Colors.white70,
                  fontSize: 12,
                  fontWeight: _isFocused ? FontWeight.bold : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChannelEpgState {
  final EpgProgram? now;
  final EpgProgram? next;
  const _ChannelEpgState({this.now, this.next});
}
