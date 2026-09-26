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

  bool _onlyWorking = false;
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

      // Validar canales en segundo plano
      LiveTvService.instance.validateChannelsInBackground(_filteredChannels, () {
        if (mounted) setState(() {});
      });
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
        if (_onlyWorking) {
          final isOnline = LiveTvService.instance.isChannelOnline(c.id);
          if (isOnline == false) return false;
        }
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
    final bottomPad = MediaQuery.paddingOf(context).bottom;
    final navOffset = 12.0 + bottomPad + 58.0 + 8.0;

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

          // ── Contenido Principal (Tipo Lista en Rectángulos) ──
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
                            child: ListView.separated(
                              padding: EdgeInsets.fromLTRB(16, 8, 16, navOffset + 55),
                              itemCount: _filteredChannels.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                final channel = _filteredChannels[index];
                                final epg = _channelEpgMap[channel.id];
                                return _buildChannelTile(channel, epg);
                              },
                            ),
                          ),
          ),

          // ── Banner Publicitario Adsterra posicionado ENCIMA del menú flotante ──
          AdService.instance.buildBanner(
            margin: EdgeInsets.only(bottom: navOffset),
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
          const SizedBox(height: 10),

          // Filtro "Solo canales en línea" y contador
          Row(
            children: [
              FilterChip(
                label: const Text('Solo en línea', style: TextStyle(fontSize: 12)),
                avatar: Icon(
                  _onlyWorking ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                  size: 15,
                  color: _onlyWorking ? kBrandOrange : Colors.white38,
                ),
                selected: _onlyWorking,
                selectedColor: kBrandOrange.withValues(alpha: 0.22),
                backgroundColor: const Color(0xFF1B1B26),
                side: BorderSide(color: _onlyWorking ? kBrandOrange : Colors.white12),
                labelStyle: TextStyle(
                  color: _onlyWorking ? Colors.white : Colors.white70,
                  fontWeight: _onlyWorking ? FontWeight.bold : FontWeight.normal,
                ),
                onSelected: (val) {
                  setState(() => _onlyWorking = val);
                  _applyFilters();
                },
              ),
              const Spacer(),
              Text(
                '${_filteredChannels.length} canales',
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChannelTile(LiveChannel channel, _ChannelEpgState? epg) {
    final isOnline = LiveTvService.instance.isChannelOnline(channel.id);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF151520),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _playChannel(channel),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                // Logo rectangular estilizado
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
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
                const SizedBox(width: 14),

                // Info del canal
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              channel.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (channel.isHD)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                              margin: const EdgeInsets.only(left: 6),
                              decoration: BoxDecoration(
                                color: kBrandOrange.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: kBrandOrange.withValues(alpha: 0.4)),
                              ),
                              child: const Text(
                                'HD',
                                style: TextStyle(
                                  color: kBrandOrange,
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          if (channel.allStreamUrls.length > 1)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                              margin: const EdgeInsets.only(left: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E88E5).withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: const Color(0xFF1E88E5).withValues(alpha: 0.4)),
                              ),
                              child: Text(
                                '${channel.allStreamUrls.length} SEÑALES',
                                style: const TextStyle(
                                  color: Color(0xFF64B5F6),
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          if (channel.country != null && channel.country!.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                              margin: const EdgeInsets.only(left: 6),
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
                      const SizedBox(height: 4),

                      // Estado en línea y programa EPG o categoría
                      Row(
                        children: [
                          if (isOnline == true) ...[
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                color: Color(0xFF2ECC71),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                          ] else if (isOnline == false) ...[
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                color: Colors.redAccent,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                          ],
                          Expanded(
                            child: Text(
                              epg?.now != null
                                  ? epg!.now!.title
                                  : (channel.group != null && channel.group!.isNotEmpty
                                      ? channel.group!
                                      : 'Canal en vivo'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.55),
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),

                // Botón play
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: kBrandOrange.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: kBrandOrange,
                    size: 22,
                  ),
                ),
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
