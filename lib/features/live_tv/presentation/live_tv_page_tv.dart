import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
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
  static const Color kBgColor = Color(0xFF0D0D12);
  static const Color kPanelBg = Color(0xFF13131A);

  bool _isLoading = true;
  String? _error;
  List<LiveChannel> _allChannels = [];
  List<LiveChannel> _filteredChannels = [];

  String? _selectedCountry;
  String _selectedCategory = '';
  LiveChannel? _selectedChannel;
  int _selectedStreamIndex = 0;

  // Mini-player en vivo estilo Magis TV
  VideoPlayerController? _previewController;
  bool _isPreviewLoading = false;
  String? _previewError;
  Timer? _previewDebounceTimer;

  final Map<String, _ChannelEpgState> _channelEpgMap = {};
  Timer? _nowTimer;

  final List<Map<String, String>> _categories = [
    {'code': '', 'label': 'Todos', 'icon': '📺'},
    {'code': 'nacionales', 'label': 'Nacionales', 'icon': '🇨🇴'},
    {'code': 'sports', 'label': 'Deportes', 'icon': '⚽'},
    {'code': 'news', 'label': 'Noticias', 'icon': '📰'},
    {'code': 'movies', 'label': 'Películas y Series', 'icon': '🎬'},
    {'code': 'kids', 'label': 'Infantil', 'icon': '👶'},
    {'code': 'music', 'label': 'Música', 'icon': '🎵'},
    {'code': 'documentary', 'label': 'Documentales', 'icon': '🌍'},
  ];

  final List<Map<String, String>> _countries = [
    {'code': 'co', 'label': '🇨🇴 Colombia'},
    {'code': 'mx', 'label': '🇲🇽 México'},
    {'code': 'ar', 'label': '🇦🇷 Argentina'},
    {'code': 'es', 'label': '🇪🇸 España'},
    {'code': 'us', 'label': '🇺🇸 USA'},
    {'code': '', 'label': '🌐 Todos'},
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
    _previewDebounceTimer?.cancel();
    _nowTimer?.cancel();
    _disposePreview();
    super.dispose();
  }

  void _disposePreview() {
    try {
      _previewController?.pause();
      _previewController?.dispose();
    } catch (_) {}
    _previewController = null;
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
        group: _selectedCategory.isNotEmpty ? _selectedCategory : null,
        forceRefresh: force,
      );

      if (!mounted) return;

      final filtered = _applyCategoryFilter(channels, _selectedCategory);

      setState(() {
        _allChannels = channels;
        _filteredChannels = filtered;
        _isLoading = false;
        if (filtered.isNotEmpty) {
          final first = filtered.first;
          _selectedChannel = first;
          _selectedStreamIndex = 0;
          _initPreviewChannel(first);
        } else {
          _selectedChannel = null;
          _disposePreview();
        }
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

  List<LiveChannel> _applyCategoryFilter(List<LiveChannel> channels, String categoryCode) {
    if (categoryCode.isEmpty) return channels;
    return channels.where((c) => LiveTvService.matchesCategory(c, categoryCode)).toList();
  }

  void _onCategorySelected(String code) {
    if (_selectedCategory == code) return;
    setState(() {
      _selectedCategory = code;
      _filteredChannels = _applyCategoryFilter(_allChannels, code);
      if (_filteredChannels.isNotEmpty) {
        _selectedChannel = _filteredChannels.first;
        _selectedStreamIndex = 0;
        _initPreviewChannel(_filteredChannels.first);
      } else {
        _selectedChannel = null;
        _disposePreview();
      }
    });
  }

  void _onChannelSelected(LiveChannel channel) {
    if (_selectedChannel?.id == channel.id) {
      // Si ya está seleccionado, entrar directo a pantalla completa
      _openFullScreenPlayer(channel);
      return;
    }
    setState(() {
      _selectedChannel = channel;
      _selectedStreamIndex = 0;
    });
    _initPreviewChannel(channel);
  }

  void _initPreviewChannel(LiveChannel channel, {int streamIndex = 0}) {
    _previewDebounceTimer?.cancel();
    _previewDebounceTimer = Timer(const Duration(milliseconds: 250), () async {
      if (!mounted) return;

      final streams = channel.allStreamUrls;
      if (streams.isEmpty) {
        setState(() {
          _previewError = 'Canal sin enlace de reproducción disponible.';
          _isPreviewLoading = false;
        });
        return;
      }

      final targetIdx = streamIndex.clamp(0, streams.length - 1);
      final streamUrl = streams[targetIdx];

      setState(() {
        _isPreviewLoading = true;
        _previewError = null;
        _selectedStreamIndex = targetIdx;
      });

      _disposePreview();

      try {
        final controller = VideoPlayerController.networkUrl(
          Uri.parse(streamUrl),
          httpHeaders: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          },
        );

        await controller.initialize().timeout(
          const Duration(seconds: 7),
          onTimeout: () {
            throw TimeoutException('Tiempo de espera agotado al conectar');
          },
        );

        if (!mounted || _selectedChannel?.id != channel.id) {
          controller.dispose();
          return;
        }

        await controller.play();
        await controller.setLooping(true);

        setState(() {
          _previewController = controller;
          _isPreviewLoading = false;
          _previewError = null;
        });
      } catch (e) {
        debugPrint('[LiveTvTv] Preview señal $targetIdx falló: $e');
        if (!mounted || _selectedChannel?.id != channel.id) return;

        // Auto-failover al siguiente stream si existe
        if (targetIdx + 1 < streams.length) {
          debugPrint('[LiveTvTv] Probando siguiente señal: ${targetIdx + 1}/${streams.length}');
          _initPreviewChannel(channel, streamIndex: targetIdx + 1);
          return;
        }

        setState(() {
          _isPreviewLoading = false;
          _previewError = 'Señal temporalmente no disponible en este momento.';
        });
      }
    });
  }

  void _openFullScreenPlayer(LiveChannel channel) {
    // Pausar mini player mientras se reproduce en fullscreen
    final channelIndex = _filteredChannels.indexOf(channel);
    tv_player.TvPlayerPage.openLiveChannel(
      context,
      channel,
      initialStreamIndex: _selectedStreamIndex,
      allChannels: _filteredChannels,
      currentChannelIndex: channelIndex >= 0 ? channelIndex : null,
    ).then((_) {
      if (mounted) {
        _previewController?.play();
      }
    });
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBgColor,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: kBrandOrange),
                    )
                  : _error != null
                      ? _buildErrorView()
                      : _buildMagisLayout(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        color: kPanelBg,
        border: Border(bottom: BorderSide(color: Colors.white10)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: kBrandOrange.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.live_tv_rounded, color: kBrandOrange, size: 20),
          ),
          const SizedBox(width: 10),
          const Text(
            'Filmotic TV',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 24),

          // Selector de país rápido
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _countries.map((c) {
                  final isSel = (_selectedCountry ?? '') == c['code'];
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: InkWell(
                      onTap: () {
                        setState(() => _selectedCountry = c['code']);
                        _loadChannels();
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: isSel ? kBrandOrange : Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          c['label']!,
                          style: TextStyle(
                            color: isSel ? Colors.white : Colors.white70,
                            fontSize: 12,
                            fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          // Botón Guía TV
          InkWell(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => EpgPageTv(channels: _allChannels),
                ),
              );
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white12),
              ),
              child: const Row(
                children: [
                  Icon(Icons.calendar_month_rounded, color: Colors.white70, size: 16),
                  SizedBox(width: 6),
                  Text('Guía EPG', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Refrescar canales',
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70, size: 20),
            onPressed: () => _loadChannels(force: true),
          ),
        ],
      ),
    );
  }

  Widget _buildMagisLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── 1. Columna de Categorías (Izquierda) ──
        Container(
          width: 200,
          color: kPanelBg,
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            itemCount: _categories.length,
            itemBuilder: (context, i) {
              final cat = _categories[i];
              final isSel = _selectedCategory == cat['code'];
              return _TvCategoryItem(
                label: cat['label']!,
                icon: cat['icon']!,
                isSelected: isSel,
                onTap: () => _onCategorySelected(cat['code']!),
              );
            },
          ),
        ),

        const VerticalDivider(width: 1, color: Colors.white10),

        // ── 2. Columna de Canales (Centro) ──
        SizedBox(
          width: 320,
          child: _filteredChannels.isEmpty
              ? _buildEmptyView()
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                  itemCount: _filteredChannels.length,
                  itemBuilder: (context, i) {
                    final ch = _filteredChannels[i];
                    final isSel = _selectedChannel?.id == ch.id;
                    final epg = _channelEpgMap[ch.id];
                    return _TvChannelRowItem(
                      channel: ch,
                      epg: epg,
                      isSelected: isSel,
                      onTap: () => _onChannelSelected(ch),
                    );
                  },
                ),
        ),

        const VerticalDivider(width: 1, color: Colors.white10),

        // ── 3. Reproductor / Vista previa (Derecha estilo Magis TV) ──
        Expanded(
          child: _buildRightPlayerPanel(),
        ),
      ],
    );
  }

  Widget _buildRightPlayerPanel() {
    final ch = _selectedChannel;
    if (ch == null) {
      return const Center(
        child: Text(
          'Selecciona un canal para reproducir',
          style: TextStyle(color: Colors.white54, fontSize: 16),
        ),
      );
    }

    final totalStreams = ch.allStreamUrls.length;
    final epg = _channelEpgMap[ch.id];

    return Container(
      color: Colors.black,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Pantalla del reproductor
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Video o Estado
                  Container(
                    color: const Color(0xFF07070A),
                    child: _previewController != null &&
                            _previewController!.value.isInitialized &&
                            !_isPreviewLoading
                        ? AspectRatio(
                            aspectRatio: _previewController!.value.aspectRatio,
                            child: VideoPlayer(_previewController!),
                          )
                        : _isPreviewLoading
                            ? const Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    CircularProgressIndicator(color: kBrandOrange),
                                    SizedBox(height: 12),
                                    Text(
                                      'Conectando a señal en vivo...',
                                      style: TextStyle(color: Colors.white70, fontSize: 13),
                                    ),
                                  ],
                                ),
                              )
                            : Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(20),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.error_outline_rounded, color: kBrandOrange, size: 48),
                                      const SizedBox(height: 10),
                                      Text(
                                        _previewError ?? 'Señal no disponible',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(color: Colors.white, fontSize: 14),
                                      ),
                                      const SizedBox(height: 12),
                                      ElevatedButton.icon(
                                        onPressed: () => _initPreviewChannel(ch),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: kBrandOrange,
                                          foregroundColor: Colors.white,
                                        ),
                                        icon: const Icon(Icons.refresh_rounded, size: 16),
                                        label: const Text('Reintentar señal'),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                  ),

                  // Overlay superior
                  Positioned(
                    top: 12,
                    left: 14,
                    right: 14,
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.fiber_manual_record, color: Colors.white, size: 10),
                              SizedBox(width: 4),
                              Text('EN VIVO', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (ch.isHD)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: kBrandOrange.withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text('HD 1080p', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                          ),
                        const Spacer(),
                        if (totalStreams > 1)
                          InkWell(
                            onTap: () {
                              final nextIdx = (_selectedStreamIndex + 1) % totalStreams;
                              _initPreviewChannel(ch, streamIndex: nextIdx);
                            },
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.7),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.white24),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.sensors_rounded, color: kBrandOrange, size: 14),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Señal ${_selectedStreamIndex + 1}/$totalStreams (Cambiar)',
                                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  // Overlay botón de pantalla completa
                  Positioned(
                    bottom: 12,
                    right: 14,
                    child: ElevatedButton.icon(
                      onPressed: () => _openFullScreenPlayer(ch),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black.withOpacity(0.75),
                        foregroundColor: Colors.white,
                        elevation: 4,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: const BorderSide(color: Colors.white24),
                        ),
                      ),
                      icon: const Icon(Icons.fullscreen_rounded, size: 20),
                      label: const Text('Pantalla Completa', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 14),

          // Detalles del canal actual (Nombre, EPG, Señales)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: kPanelBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              children: [
                if (ch.logo != null && ch.logo!.isNotEmpty)
                  Container(
                    width: 50,
                    height: 50,
                    margin: const EdgeInsets.only(right: 14),
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: CachedNetworkImage(
                      imageUrl: ch.logo!,
                      fit: BoxFit.contain,
                      errorWidget: (_, __, ___) => const Icon(Icons.tv, color: Colors.white38),
                    ),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ch.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (epg?.now != null) ...[
                        Text(
                          'Ahora: ${epg!.now!.title}',
                          style: const TextStyle(color: kBrandOrange, fontSize: 13, fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ] else ...[
                        Text(
                          ch.group ?? 'Canal de televisión abierta',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () => _openFullScreenPlayer(ch),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kBrandOrange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.play_arrow_rounded, size: 22),
                  label: const Text('Ver en Vivo', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                ),
              ],
            ),
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
          ElevatedButton.icon(
            onPressed: () => _loadChannels(force: true),
            style: ElevatedButton.styleFrom(backgroundColor: kBrandOrange),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.tv_off_rounded, color: Colors.white24, size: 48),
            const SizedBox(height: 12),
            Text(
              'No se encontraron canales en esta categoría.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Widget Ítem de Categoría (Izquierda) ──
class _TvCategoryItem extends StatelessWidget {
  final String label;
  final String icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _TvCategoryItem({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const kBrandOrange = Color(0xFFFF6B35);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? kBrandOrange.withValues(alpha: 0.18) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? kBrandOrange.withValues(alpha: 0.6) : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Text(icon, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? kBrandOrange : Colors.white70,
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Widget Fila de Canal en Lista (Centro) ──
class _TvChannelRowItem extends StatelessWidget {
  final LiveChannel channel;
  final _ChannelEpgState? epg;
  final bool isSelected;
  final VoidCallback onTap;

  const _TvChannelRowItem({
    required this.channel,
    required this.epg,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const kBrandOrange = Color(0xFFFF6B35);
    final totalSignals = channel.allStreamUrls.length;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF222234) : const Color(0xFF161622),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? kBrandOrange : Colors.white.withValues(alpha: 0.06),
              width: isSelected ? 2.0 : 1.0,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: kBrandOrange.withValues(alpha: 0.25),
                      blurRadius: 10,
                      spreadRadius: 1,
                    )
                  ]
                : null,
          ),
          child: Row(
            children: [
              // Logo del canal
              Container(
                width: 38,
                height: 38,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: channel.logo != null && channel.logo!.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: channel.logo!,
                        fit: BoxFit.contain,
                        errorWidget: (_, __, ___) => const Icon(Icons.tv, color: Colors.white38, size: 20),
                      )
                    : const Icon(Icons.tv, color: Colors.white38, size: 20),
              ),
              const SizedBox(width: 10),

              // Nombre y EPG
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      channel.name,
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.white70,
                        fontSize: 14,
                        fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    if (epg?.now != null)
                      Text(
                        epg!.now!.title,
                        style: TextStyle(
                          color: isSelected ? kBrandOrange : Colors.white54,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      )
                    else
                      Text(
                        channel.group ?? 'En vivo',
                        style: const TextStyle(color: Colors.white38, fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),

              const SizedBox(width: 6),

              // Badges: HD y Señales
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (channel.isHD)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: kBrandOrange.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: kBrandOrange.withValues(alpha: 0.5)),
                      ),
                      child: const Text('HD', style: TextStyle(color: kBrandOrange, fontSize: 9, fontWeight: FontWeight.bold)),
                    ),
                  if (totalSignals > 1) ...[
                    const SizedBox(height: 3),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '$totalSignals señ.',
                        style: const TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.w600),
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

class _ChannelEpgState {
  final EpgProgram? now;
  final EpgProgram? next;

  const _ChannelEpgState({this.now, this.next});
}
