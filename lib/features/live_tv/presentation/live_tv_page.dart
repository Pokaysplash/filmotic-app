import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/services/ad_service.dart';
import '../../../core/services/remote_config_service.dart';
import '../../player/presentation/player_page.dart';
import '../data/epg_service.dart';
import '../data/live_tv_service.dart';
import '../domain/channel.dart';
import '../domain/epg_program.dart';
import 'epg_page.dart';
import 'epg_program_detail.dart';

class LiveTvPage extends StatefulWidget {
  const LiveTvPage({super.key});

  @override
  State<LiveTvPage> createState() => _LiveTvPageState();
}

class _LiveTvPageState extends State<LiveTvPage> {
  static const Color kBrandOrange = Color(0xFFFF6B35);
  static const Color kCardBg = Color(0xFF14141E);

  bool _isLoading = true;
  String? _error;
  List<LiveChannel> _allChannels = [];
  List<LiveChannel> _filteredChannels = [];

  String? _selectedCountry;
  String? _selectedCategory;
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _nowTimer;

  final Map<String, _ChannelEpgState> _channelEpgMap = {};

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

    // Timer para refrescar "Now Playing" cada minuto
    _nowTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _nowTimer?.cancel();
    _searchCtrl.dispose();
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
        _isLoading = false;
      });

      _applyFilters();

      // Cargar EPG para los primeros 30 canales visibles
      _fetchEpgForVisible();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Error cargando canales. Desliza para reintentar.';
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

  void _applyFilters() {
    final query = _searchCtrl.text.trim().toLowerCase();
    setState(() {
      _filteredChannels = _allChannels.where((c) {
        if (query.isNotEmpty) {
          final matchesName = c.name.toLowerCase().contains(query);
          final matchesGroup = c.group?.toLowerCase().contains(query) ?? false;
          if (!matchesName && !matchesGroup) return false;
        }
        return true;
      }).toList();
    });
  }

  void _playChannel(LiveChannel channel) {
    PlayerScreen.openLiveChannel(context, channel);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: kBrandOrange.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.live_tv_rounded, color: kBrandOrange, size: 22),
            ),
            const SizedBox(width: 10),
            const Text(
              'TV en Vivo',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 20,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: Colors.white.withValues(alpha: 0.08),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            icon: const Icon(Icons.calendar_view_week_rounded, color: kBrandOrange, size: 18),
            label: const Text(
              'Guía TV',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => EpgPage(channels: _allChannels),
                ),
              );
            },
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Column(
        children: [
          // ── Barra de Filtros y Búsqueda ──
          _buildFilterBar(),

          // ── Contenido Principal ──
          Expanded(
            child: _isLoading
                ? _buildLoadingSkeleton()
                : _error != null
                    ? _buildErrorView()
                    : _filteredChannels.isEmpty
                        ? _buildEmptyView()
                        : RefreshIndicator(
                            color: kBrandOrange,
                            backgroundColor: kCardBg,
                            onRefresh: () => _loadChannels(force: true),
                            child: GridView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                childAspectRatio: 0.88,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                              ),
                              itemCount: _filteredChannels.length,
                              itemBuilder: (context, index) {
                                final channel = _filteredChannels[index];
                                final epg = _channelEpgMap[channel.id];
                                return _buildChannelCard(channel, epg);
                              },
                            ),
                          ),
          ),

          // ── Banner Publicitario Adsterra ──
          AdService.instance.buildBanner(
            margin: const EdgeInsets.only(bottom: 6),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      decoration: BoxDecoration(
        color: Colors.black,
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
      ),
      child: Column(
        children: [
          // Buscador
          Container(
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFF1B1B26),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: TextField(
              controller: _searchCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              onChanged: (_) => _applyFilters(),
              decoration: InputDecoration(
                hintText: 'Buscar canal por nombre o categoría...',
                hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 13),
                prefixIcon: const Icon(Icons.search_rounded, color: Colors.white54, size: 20),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.white54, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          _applyFilters();
                        },
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Dropdowns / Filtros de país y categoría
          Row(
            children: [
              // Selector País
              Expanded(
                child: Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1B1B26),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedCountry ?? '',
                      dropdownColor: const Color(0xFF1B1B26),
                      icon: const Icon(Icons.arrow_drop_down, color: Colors.white70),
                      isExpanded: true,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      items: _countries.map((c) {
                        return DropdownMenuItem(
                          value: c['code'],
                          child: Text(c['label']!, overflow: TextOverflow.ellipsis),
                        );
                      }).toList(),
                      onChanged: (val) {
                        setState(() => _selectedCountry = val);
                        _loadChannels();
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // Selector Categoría
              Expanded(
                child: Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1B1B26),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedCategory ?? '',
                      dropdownColor: const Color(0xFF1B1B26),
                      icon: const Icon(Icons.arrow_drop_down, color: Colors.white70),
                      isExpanded: true,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      items: _categories.map((cat) {
                        return DropdownMenuItem(
                          value: cat['code'],
                          child: Text(cat['label']!, overflow: TextOverflow.ellipsis),
                        );
                      }).toList(),
                      onChanged: (val) {
                        setState(() => _selectedCategory = val);
                        _loadChannels();
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChannelCard(LiveChannel channel, _ChannelEpgState? epg) {
    return Container(
      decoration: BoxDecoration(
        color: kCardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _playChannel(channel),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top row: Logo + Badges
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Logo
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.all(4),
                      child: channel.logo != null && channel.logo!.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: channel.logo!,
                              fit: BoxFit.contain,
                              errorWidget: (_, __, ___) => const Icon(
                                Icons.tv_rounded,
                                color: Colors.white38,
                                size: 24,
                              ),
                            )
                          : const Icon(Icons.tv_rounded, color: Colors.white38, size: 24),
                    ),
                    const Spacer(),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (channel.isHD)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            margin: const EdgeInsets.only(bottom: 4),
                            decoration: BoxDecoration(
                              color: kBrandOrange.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: kBrandOrange.withValues(alpha: 0.4)),
                            ),
                            child: const Text(
                              'HD',
                              style: TextStyle(
                                color: kBrandOrange,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        if (channel.country != null && channel.country!.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              channel.country!.toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Channel Name
                Text(
                  channel.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const Spacer(),

                // EPG Section (Now / Next)
                if (epg != null && epg.now != null) ...[
                  Row(
                    children: [
                      const Icon(Icons.play_circle_filled_rounded, color: kBrandOrange, size: 12),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          epg.now!.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
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
                      value: epg.now!.progress,
                      minHeight: 2.5,
                      backgroundColor: Colors.white12,
                      valueColor: const AlwaysStoppedAnimation<Color>(kBrandOrange),
                    ),
                  ),
                  if (epg.next != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Sig: ${epg.next!.title}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 10,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ] else ...[
                  Text(
                    channel.group ?? 'Canal en vivo',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingSkeleton() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: kBrandOrange),
          const SizedBox(height: 16),
          Text(
            'Cargando canales en vivo...',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.signal_wifi_bad_rounded, color: Colors.white38, size: 48),
            const SizedBox(height: 12),
            Text(
              _error!,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: kBrandOrange,
                foregroundColor: Colors.white,
              ),
              onPressed: () => _loadChannels(force: true),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.tv_off_rounded, color: Colors.white24, size: 48),
          const SizedBox(height: 12),
          Text(
            'No se encontraron canales con estos filtros.',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 14),
          ),
        ],
      ),
    );
  }
}

class _ChannelEpgState {
  final EpgProgram? now;
  final EpgProgram? next;
  const _ChannelEpgState({this.now, this.next});
}
