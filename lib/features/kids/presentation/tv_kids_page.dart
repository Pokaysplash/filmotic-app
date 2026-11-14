import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/storage/app_database.dart';
import '../../../data/datasources/remote/tmdb/tmdb_kids_api.dart';
import '../../content/presentation/tv_content_page.dart';
import '../../profile/presentation/profile_selection_page.dart';

class KidsPageTv extends StatefulWidget {
  final VoidCallback? onRequestMenuFocus;
  final ValueChanged<FocusNode>? onMainFocusNodeCreated;

  const KidsPageTv({
    super.key,
    this.onRequestMenuFocus,
    this.onMainFocusNodeCreated,
  });

  @override
  State<KidsPageTv> createState() => _KidsPageTvState();
}

class _KidsPageTvState extends State<KidsPageTv> {
  static const Color _kKidsAccent = Color(0xFF00C2FF);
  static const Color _kKidsWarm = Color(0xFFFFB800);
  static const Color _kBg = Color(0xFF0B0E17);

  final FocusNode _firstFocusNode = FocusNode(debugLabel: 'tv_kids_first');
  KidsSectionData _data = const KidsSectionData();
  bool _loading = true;
  String _filter = 'all'; // 'all' | 'movie' | 'tv'

  @override
  void initState() {
    super.initState();
    widget.onMainFocusNodeCreated?.call(_firstFocusNode);
    _loadData();
  }

  @override
  void dispose() {
    _firstFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadData({bool forceRefresh = false}) async {
    if (mounted && _data.isEmpty) {
      setState(() => _loading = true);
    }
    final data =
        await TmdbKidsApi.instance.fetchKidsCatalog(forceRefresh: forceRefresh);
    if (!mounted) return;
    setState(() {
      _data = data;
      _loading = false;
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

  Future<void> _openProfiles() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ProfileSelectionPage()),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final profile = AppDatabase.instance.activeProfile;
    final isKidsProfile = profile?.esInfantil == true;

    final rows = <({String title, List<Map<String, dynamic>> items})>[
      if ((_filter == 'all' || _filter == 'movie') &&
          _data.animatedMovies.isNotEmpty)
        (title: 'Películas Animadas', items: _data.animatedMovies),
      if ((_filter == 'all' || _filter == 'movie') &&
          _data.disneyPixar.isNotEmpty)
        (title: 'Disney & Pixar', items: _data.disneyPixar),
      if ((_filter == 'all' || _filter == 'tv') && _data.kidsSeries.isNotEmpty)
        (title: 'Series para Niños', items: _data.kidsSeries),
      if ((_filter == 'all' || _filter == 'movie') &&
          _data.dreamworksIllumination.isNotEmpty)
        (
          title: 'DreamWorks & Illumination',
          items: _data.dreamworksIllumination
        ),
      if ((_filter == 'all' || _filter == 'movie') &&
          _data.familyAdventures.isNotEmpty)
        (title: 'Aventuras en Familia', items: _data.familyAdventures),
      if ((_filter == 'all' || _filter == 'movie') &&
          _data.studioGhibli.isNotEmpty)
        (title: 'Studio Ghibli', items: _data.studioGhibli),
      if ((_filter == 'all' || _filter == 'tv') &&
          _data.animatedSeries.isNotEmpty)
        (title: 'Dibujos Animados', items: _data.animatedSeries),
      if ((_filter == 'all' || _filter == 'movie') &&
          _data.kidsComedy.isNotEmpty)
        (title: 'Comedias y Risas', items: _data.kidsComedy),
      if ((_filter == 'all' || _filter == 'tv') && _data.preschool.isNotEmpty)
        (title: 'Para los Más Pequeños', items: _data.preschool),
    ];

    return Container(
      color: _kBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 24, 32, 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [_kKidsAccent, Color(0xFF7B5CFF)],
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.child_care_rounded,
                      color: Colors.white, size: 26),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Zona Infantil',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      isKidsProfile
                          ? 'Perfil activo: ${profile?.nombre ?? 'Infantil'} · Solo contenido infantil'
                          : 'Contenido seguro para niños',
                      style: TextStyle(
                        color: isKidsProfile ? _kKidsAccent : Colors.white60,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                _TvFilterButton(
                  focusNode: _firstFocusNode,
                  label: 'Todo',
                  selected: _filter == 'all',
                  isFirstInRow: true,
                  onLeftEdge: widget.onRequestMenuFocus,
                  onPressed: () => setState(() => _filter = 'all'),
                ),
                const SizedBox(width: 10),
                _TvFilterButton(
                  label: 'Películas',
                  selected: _filter == 'movie',
                  onPressed: () => setState(() => _filter = 'movie'),
                ),
                const SizedBox(width: 10),
                _TvFilterButton(
                  label: 'Series',
                  selected: _filter == 'tv',
                  onPressed: () => setState(() => _filter = 'tv'),
                ),
                const SizedBox(width: 10),
                _TvFilterButton(
                  label: 'Cambiar Perfil',
                  selected: false,
                  onPressed: _openProfiles,
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: _kKidsAccent),
                  )
                : rows.isEmpty
                    ? Center(
                        child: _TvFilterButton(
                          label: 'Reintentar',
                          selected: true,
                          isFirstInRow: true,
                          onLeftEdge: widget.onRequestMenuFocus,
                          onPressed: () => _loadData(forceRefresh: true),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 36),
                        itemCount: rows.length,
                        itemBuilder: (_, rowIdx) {
                          final row = rows[rowIdx];
                          return _buildTvRow(row.title, row.items);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildTvRow(String title, List<Map<String, dynamic>> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 14, 32, 10),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 18,
                decoration: BoxDecoration(
                  color: _kKidsWarm,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 220,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 32),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (_, idx) {
              final item = items[idx];
              return _TvKidsPosterCard(
                item: item,
                isFirstInRow: idx == 0,
                onLeftEdge: widget.onRequestMenuFocus,
                onTap: () => _openItem(item),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _TvFilterButton extends StatefulWidget {
  final FocusNode? focusNode;
  final String label;
  final bool selected;
  final bool isFirstInRow;
  final VoidCallback? onLeftEdge;
  final VoidCallback onPressed;

  const _TvFilterButton({
    this.focusNode,
    required this.label,
    required this.selected,
    this.isFirstInRow = false,
    this.onLeftEdge,
    required this.onPressed,
  });

  @override
  State<_TvFilterButton> createState() => _TvFilterButtonState();
}

class _TvFilterButtonState extends State<_TvFilterButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (widget.isFirstInRow &&
            event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          widget.onLeftEdge?.call();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.select ||
            event.logicalKey == LogicalKeyboardKey.enter) {
          widget.onPressed();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: widget.selected
                ? const Color(0xFF00C2FF)
                : const Color(0xFF171C2E),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _focused
                  ? Colors.white
                  : (widget.selected
                      ? const Color(0xFF00C2FF)
                      : Colors.white24),
              width: _focused ? 2.2 : 1,
            ),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              color: widget.selected ? Colors.black : Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _TvKidsPosterCard extends StatefulWidget {
  final Map<String, dynamic> item;
  final bool isFirstInRow;
  final VoidCallback? onLeftEdge;
  final VoidCallback onTap;

  const _TvKidsPosterCard({
    required this.item,
    required this.isFirstInRow,
    this.onLeftEdge,
    required this.onTap,
  });

  @override
  State<_TvKidsPosterCard> createState() => _TvKidsPosterCardState();
}

class _TvKidsPosterCardState extends State<_TvKidsPosterCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final poster = (widget.item['poster_path'] ?? '').toString();
    final title = (widget.item['titulo'] ??
            widget.item['title'] ??
            widget.item['name'] ??
            '')
        .toString();

    return Focus(
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (widget.isFirstInRow &&
            event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          widget.onLeftEdge?.call();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.select ||
            event.logicalKey == LogicalKeyboardKey.enter) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _focused ? 1.06 : 1.0,
          duration: const Duration(milliseconds: 140),
          child: SizedBox(
            width: 126,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 126,
                  height: 176,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color:
                          _focused ? const Color(0xFF00C2FF) : Colors.white12,
                      width: _focused ? 2.5 : 1,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: CachedNetworkImage(
                      imageUrl: 'https://image.tmdb.org/t/p/w342$poster',
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => Container(
                        color: const Color(0xFF151B2E),
                        child: const Icon(Icons.movie_rounded,
                            color: Colors.white24),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _focused ? const Color(0xFF00C2FF) : Colors.white,
                    fontSize: 12.5,
                    fontWeight: _focused ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
