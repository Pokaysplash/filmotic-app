import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/services/remote_config_service.dart';
import '../../../core/storage/app_database.dart';
import '../../../data/datasources/remote/tmdb/tmdb_kids_api.dart';
import '../../content/presentation/content_page.dart';
import '../../live_tv/data/live_tv_service.dart';
import '../../live_tv/domain/channel.dart';
import '../../player/presentation/player_page.dart';
import '../../profile/presentation/profile_selection_page.dart';

class KidsPage extends StatefulWidget {
  const KidsPage({super.key});

  @override
  State<KidsPage> createState() => _KidsPageState();
}

class _KidsPageState extends State<KidsPage> {
  static const Color _kKidsAccent = Color(0xFF00C2FF);
  static const Color _kKidsWarm = Color(0xFFFFB800);
  static const Color _kBg = Color(0xFF0A0D16);

  KidsSectionData _data = const KidsSectionData();
  List<LiveChannel> _kidsChannels = const [];
  bool _loading = true;
  String _filter = 'all'; // 'all' | 'movie' | 'tv' | 'live'
  int _heroIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData({bool forceRefresh = false}) async {
    if (mounted && _data.isEmpty) {
      setState(() => _loading = true);
    }

    final catalogFuture =
        TmdbKidsApi.instance.fetchKidsCatalog(forceRefresh: forceRefresh);
    final liveEnabled = RemoteConfigService.instance.config.liveTv.enabled;
    final channelsFuture = liveEnabled
        ? LiveTvService.instance
            .loadChannels(group: 'kids', forceRefresh: forceRefresh)
            .catchError((_) => <LiveChannel>[])
        : Future.value(<LiveChannel>[]);

    final results = await Future.wait([catalogFuture, channelsFuture]);
    if (!mounted) return;
    setState(() {
      _data = results[0] as KidsSectionData;
      _kidsChannels = results[1] as List<LiveChannel>;
      _loading = false;
      _heroIndex = 0;
    });
  }

  void _openItem(Map<String, dynamic> item) {
    final title =
        (item['titulo'] ?? item['title'] ?? item['name'] ?? '').toString().trim();
    final tipo = canonicalMediaType(
      item['media_type'] ?? item['type'] ?? item['tipo'] ?? 'movie',
    );
    final tmdbId = parseCanonicalTmdbId(
      item['tmdb_id'] ?? item['idtmdb'] ?? item['idcontenido'] ?? item['id'],
    );
    if (tmdbId == null || tmdbId <= 0) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PageContenido(
          idcontenido: tmdbId,
          tmdbId: tmdbId,
          mediaType: tipo,
          expectedTitle: title.isNotEmpty ? title : null,
        ),
      ),
    );
  }

  void _openChannel(LiveChannel channel) {
    PlayerScreen.openLiveChannel(
      context,
      channel,
      allChannels: _kidsChannels,
      currentChannelIndex: _kidsChannels.indexOf(channel),
    );
  }

  Future<void> _openProfileSelector() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ProfileSelectionPage()),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final activeProfile = AppDatabase.instance.activeProfile;
    final isKidsProfile = activeProfile?.esInfantil == true;
    final bottomPad = MediaQuery.paddingOf(context).bottom + 92;

    return Scaffold(
      backgroundColor: _kBg,
      body: RefreshIndicator(
        color: _kKidsAccent,
        backgroundColor: const Color(0xFF151B2E),
        onRefresh: () => _loadData(forceRefresh: true),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: _buildHeader(activeProfile, isKidsProfile),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
                child: _buildFilterChips(),
              ),
            ),
            if (_loading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: CircularProgressIndicator(color: _kKidsAccent),
                ),
              )
            else if (_data.isEmpty && _kidsChannels.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.child_care_rounded,
                          color: _kKidsAccent, size: 52),
                      const SizedBox(height: 12),
                      const Text(
                        'No se pudo cargar el catálogo infantil',
                        style: TextStyle(
                            color: Colors.white70,
                            fontSize: 15,
                            fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: () => _loadData(forceRefresh: true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kKidsAccent,
                          foregroundColor: Colors.black,
                        ),
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Reintentar'),
                      ),
                    ],
                  ),
                ),
              )
            else
              SliverList(
                delegate: SliverChildListDelegate([
                  if (_filter == 'all' && _data.hero.isNotEmpty) ...[
                    _buildHeroBanner(),
                    const SizedBox(height: 20),
                  ],
                  if ((_filter == 'all' || _filter == 'live') &&
                      _kidsChannels.isNotEmpty)
                    _buildKidsChannelsRow(),
                  if ((_filter == 'all' || _filter == 'movie') &&
                      _data.animatedMovies.isNotEmpty)
                    _buildPosterRow('Películas Animadas', _data.animatedMovies),
                  if ((_filter == 'all' || _filter == 'movie') &&
                      _data.disneyPixar.isNotEmpty)
                    _buildPosterRow('Disney & Pixar', _data.disneyPixar),
                  if ((_filter == 'all' || _filter == 'tv') &&
                      _data.kidsSeries.isNotEmpty)
                    _buildPosterRow('Series para Niños', _data.kidsSeries),
                  if ((_filter == 'all' || _filter == 'movie') &&
                      _data.dreamworksIllumination.isNotEmpty)
                    _buildPosterRow('DreamWorks & Illumination',
                        _data.dreamworksIllumination),
                  if ((_filter == 'all' || _filter == 'movie') &&
                      _data.familyAdventures.isNotEmpty)
                    _buildPosterRow(
                        'Aventuras en Familia', _data.familyAdventures),
                  if ((_filter == 'all' || _filter == 'movie') &&
                      _data.studioGhibli.isNotEmpty)
                    _buildPosterRow('Studio Ghibli', _data.studioGhibli),
                  if ((_filter == 'all' || _filter == 'tv') &&
                      _data.animatedSeries.isNotEmpty)
                    _buildPosterRow('Dibujos Animados', _data.animatedSeries),
                  if ((_filter == 'all' || _filter == 'movie') &&
                      _data.kidsComedy.isNotEmpty)
                    _buildPosterRow('Comedias y Risas', _data.kidsComedy),
                  if ((_filter == 'all' || _filter == 'tv') &&
                      _data.preschool.isNotEmpty)
                    _buildPosterRow('Para los Más Pequeños', _data.preschool),
                  SizedBox(height: bottomPad),
                ]),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(LocalProfile? profile, bool isKidsProfile) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [_kKidsAccent, Color(0xFF7B5CFF)],
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.child_care_rounded,
              color: Colors.white, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Zona Infantil',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                isKidsProfile
                    ? 'Perfil activo: ${profile?.nombre ?? 'Infantil'} · Modo seguro'
                    : 'Contenido seguro para niños · Toca para usar perfil infantil',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isKidsProfile ? _kKidsAccent : Colors.white60,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        InkWell(
          onTap: _openProfileSelector,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: isKidsProfile
                  ? _kKidsAccent.withValues(alpha: 0.16)
                  : Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isKidsProfile ? _kKidsAccent : Colors.white24,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isKidsProfile
                      ? Icons.verified_user_rounded
                      : Icons.switch_account_rounded,
                  color: isKidsProfile ? _kKidsAccent : Colors.white,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  isKidsProfile ? 'Cambiar' : 'Perfiles',
                  style: TextStyle(
                    color: isKidsProfile ? _kKidsAccent : Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFilterChips() {
    final chips = <({String id, String label, IconData icon})>[
      (id: 'all', label: 'Todo', icon: Icons.auto_awesome_rounded),
      (id: 'movie', label: 'Películas', icon: Icons.movie_rounded),
      (id: 'tv', label: 'Series', icon: Icons.tv_rounded),
      if (_kidsChannels.isNotEmpty)
        (id: 'live', label: 'TV Infantil', icon: Icons.live_tv_rounded),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: chips.map((c) {
          final selected = _filter == c.id;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              selected: selected,
              onSelected: (_) => setState(() => _filter = c.id),
              avatar: Icon(
                c.icon,
                size: 16,
                color: selected ? Colors.black : Colors.white70,
              ),
              label: Text(c.label),
              labelStyle: TextStyle(
                color: selected ? Colors.black : Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
              ),
              selectedColor: _kKidsAccent,
              backgroundColor: const Color(0xFF151B2E),
              side: BorderSide(
                color: selected ? _kKidsAccent : Colors.white12,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildHeroBanner() {
    final item = _data.hero[_heroIndex % _data.hero.length];
    final backdrop = (item['backdrop_path'] ?? '').toString();
    final title = (item['titulo'] ?? item['title'] ?? item['name'] ?? '').toString();
    final overview = (item['overview'] ?? '').toString();
    final rating = (item['vote_average'] is num)
        ? (item['vote_average'] as num).toStringAsFixed(1)
        : '';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GestureDetector(
        onTap: () => _openItem(item),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: SizedBox(
            height: 220,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CachedNetworkImage(
                  imageUrl: 'https://image.tmdb.org/t/p/w780$backdrop',
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) =>
                      Container(color: const Color(0xFF151B2E)),
                ),
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.15),
                        Colors.black.withValues(alpha: 0.88),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 14,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: _kKidsWarm,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'INFANTIL',
                              style: TextStyle(
                                color: Colors.black,
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          if (rating.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            const Icon(Icons.star_rounded,
                                color: _kKidsWarm, size: 15),
                            const SizedBox(width: 3),
                            Text(
                              rating,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                          const Spacer(),
                          if (_data.hero.length > 1)
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              onPressed: () => setState(() {
                                _heroIndex =
                                    (_heroIndex + 1) % _data.hero.length;
                              }),
                              icon: const Icon(Icons.skip_next_rounded,
                                  color: Colors.white70),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (overview.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          overview,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12),
                        ),
                      ],
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

  Widget _buildKidsChannelsRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 4, 16, 10),
          child: Text(
            'Canales de TV Infantil',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        SizedBox(
          height: 92,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _kidsChannels.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, idx) {
              final ch = _kidsChannels[idx];
              return GestureDetector(
                onTap: () => _openChannel(ch),
                child: Container(
                  width: 150,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF151B2E),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _kKidsAccent.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      if (ch.logo != null && ch.logo!.isNotEmpty)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: CachedNetworkImage(
                            imageUrl: ch.logo!,
                            width: 40,
                            height: 40,
                            fit: BoxFit.contain,
                            errorWidget: (_, __, ___) => const Icon(
                              Icons.live_tv_rounded,
                              color: _kKidsAccent,
                              size: 28,
                            ),
                          ),
                        )
                      else
                        const Icon(Icons.live_tv_rounded,
                            color: _kKidsAccent, size: 28),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          ch.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 18),
      ],
    );
  }

  Widget _buildPosterRow(String title, List<Map<String, dynamic>> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
          child: Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        SizedBox(
          height: 196,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, idx) {
              final item = items[idx];
              final poster = (item['poster_path'] ?? '').toString();
              final itemTitle =
                  (item['titulo'] ?? item['title'] ?? item['name'] ?? '')
                      .toString();
              return GestureDetector(
                onTap: () => _openItem(item),
                child: SizedBox(
                  width: 112,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: CachedNetworkImage(
                          imageUrl: 'https://image.tmdb.org/t/p/w342$poster',
                          width: 112,
                          height: 158,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => Container(
                            width: 112,
                            height: 158,
                            color: const Color(0xFF151B2E),
                            child: const Icon(Icons.movie_rounded,
                                color: Colors.white24),
                          ),
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        itemTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 14),
      ],
    );
  }
}
