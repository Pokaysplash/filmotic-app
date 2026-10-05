import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../content/presentation/content_page.dart' as mobile_content;
import '../../content/presentation/tv_content_page.dart' as tv_content;
import '../../discover/domain/mobile/derivar.dart' as mobile_derivar;
import '../../discover/domain/derivar.dart' as tv_derivar;
import '../../../core/services/guardados_bus.dart';
import '../../../data/scrapers/base/registry.dart';

const Color kAccentColor = Color(0xFFFF6B35);
const Color kBgColor = Color(0xFF0A0A0A);
const Color kCardBg = Color(0xFF16161A);

/// Pantalla completa de listado de categoría con soporte tanto para móvil como para Android TV (D-Pad).
class CategoryListPage extends StatefulWidget {
  final String title;
  final List<Map<String, dynamic>> items;
  final bool isMovie;
  final String? categoryKey;
  final bool isTv;

  const CategoryListPage({
    super.key,
    required this.title,
    required this.items,
    this.isMovie = true,
    this.categoryKey,
    this.isTv = false,
  });

  @override
  State<CategoryListPage> createState() => _CategoryListPageState();
}

class _CategoryListPageState extends State<CategoryListPage> {
  final ScrollController _scrollController = ScrollController();
  final FocusNode _backFocusNode = FocusNode(debugLabel: 'category_back_btn');
  final Map<int, FocusNode> _itemFocusNodes = {};

  String _selectedCategory = 'Todos';
  bool _loadingCategory = false;
  final Map<String, List<Map<String, dynamic>>> _categoryCache = {};
  final Map<String, FocusNode> _categoryFocusNodes = {
    'Todos': FocusNode(debugLabel: 'cat_todos'),
    'Películas': FocusNode(debugLabel: 'cat_pelis'),
    'Series': FocusNode(debugLabel: 'cat_series'),
    'Novelas': FocusNode(debugLabel: 'cat_novelas'),
    'Anime': FocusNode(debugLabel: 'cat_anime'),
  };

  int _focusedIndex = -1;

  static const List<String> _kCategories = [
    'Todos',
    'Películas',
    'Series',
    'Novelas',
    'Anime',
  ];

  @override
  void dispose() {
    _scrollController.dispose();
    _backFocusNode.dispose();
    for (final node in _categoryFocusNodes.values) {
      node.dispose();
    }
    for (final node in _itemFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  Future<void> _selectCategory(String cat) async {
    if (_selectedCategory == cat) return;
    setState(() {
      _selectedCategory = cat;
      _focusedIndex = -1;
    });

    if (cat == 'Novelas' && !_categoryCache.containsKey('Novelas')) {
      setState(() => _loadingCategory = true);
      try {
        final novelSources = getFuentesByCategory('novel');
        final items = <Map<String, dynamic>>[];
        for (final src in novelSources) {
          if (src.fetch != null) {
            final res = await src.fetch!();
            for (final it in res.items) {
              items.add({
                'id': it.tmdbId ?? it.titulo.hashCode.abs(),
                'tmdb_id': it.tmdbId ?? 0,
                'title': it.titulo,
                'name': it.titulo,
                'poster_path': it.poster,
                'vote_average': it.rating ?? 0.0,
                'year': it.year != null ? '${it.year}' : '',
                'media_type': 'tv',
                'sitio': src.id,
                'url': it.url,
              });
            }
          }
        }
        _categoryCache['Novelas'] = items;
      } catch (_) {}
      if (mounted) setState(() => _loadingCategory = false);
    } else if (cat == 'Anime' && !_categoryCache.containsKey('Anime')) {
      setState(() => _loadingCategory = true);
      try {
        final animeSources = getFuentesByCategory('anime');
        final items = <Map<String, dynamic>>[];
        for (final src in animeSources) {
          if (src.fetch != null) {
            final res = await src.fetch!();
            for (final it in res.items) {
              items.add({
                'id': it.tmdbId ?? it.titulo.hashCode.abs(),
                'tmdb_id': it.tmdbId ?? 0,
                'title': it.titulo,
                'name': it.titulo,
                'poster_path': it.poster,
                'vote_average': it.rating ?? 0.0,
                'year': it.year != null ? '${it.year}' : '',
                'media_type': 'tv',
                'sitio': src.id,
                'url': it.url,
              });
            }
          }
        }
        _categoryCache['Anime'] = items;
      } catch (_) {}
      if (mounted) setState(() => _loadingCategory = false);
    }
  }

  List<Map<String, dynamic>> get _currentItems {
    switch (_selectedCategory) {
      case 'Películas':
        return widget.items.where((i) {
          final t = (i['tipo'] ?? i['type'] ?? i['media_type'] ?? '').toString().toLowerCase();
          return t == 'movie' || t == 'pelicula' || (i['title'] != null && i['name'] == null);
        }).toList();
      case 'Series':
        return widget.items.where((i) {
          final t = (i['tipo'] ?? i['type'] ?? i['media_type'] ?? '').toString().toLowerCase();
          return t == 'tv' || t == 'serie' || (i['name'] != null && i['title'] == null);
        }).toList();
      case 'Novelas':
        final fromWidget = widget.items.where((i) {
          final t = (i['title'] ?? i['name'] ?? '').toString().toLowerCase();
          final g = (i['genre'] ?? i['genero'] ?? '').toString().toLowerCase();
          return t.contains('novela') || g.contains('novela') || g.contains('drama');
        }).toList();
        if (fromWidget.isNotEmpty) return fromWidget;
        return _categoryCache['Novelas'] ?? [];
      case 'Anime':
        final fromWidget = widget.items.where((i) {
          final t = (i['title'] ?? i['name'] ?? '').toString().toLowerCase();
          final g = (i['genre'] ?? i['genero'] ?? '').toString().toLowerCase();
          return g.contains('anime') || g.contains('animacion');
        }).toList();
        if (fromWidget.isNotEmpty) return fromWidget;
        return _categoryCache['Anime'] ?? [];
      default:
        return widget.items;
    }
  }

  FocusNode _getFocusNodeFor(int index) {
    return _itemFocusNodes.putIfAbsent(
      index,
      () => FocusNode(debugLabel: 'category_item_$index'),
    );
  }

  String _getImageUrl(Map<String, dynamic> item) {
    final poster = item['poster_path']?.toString() ?? '';
    if (poster.isNotEmpty && poster.startsWith('http')) return poster;
    if (poster.isNotEmpty && !poster.contains('[')) {
      return 'https://image.tmdb.org/t/p/w500$poster';
    }
    final backdrop = item['backdrop_path']?.toString() ?? '';
    if (backdrop.isNotEmpty && backdrop.startsWith('http')) return backdrop;
    if (backdrop.isNotEmpty && !backdrop.contains('[')) {
      return 'https://image.tmdb.org/t/p/w500$backdrop';
    }
    return '';
  }

  String _getTitle(Map<String, dynamic> item) {
    return (item['title'] ?? item['name'] ?? 'Sin título').toString();
  }

  double _getRating(Map<String, dynamic> item) {
    final vote = item['vote_average'];
    if (vote is num) return vote.toDouble();
    return double.tryParse('$vote') ?? 0.0;
  }

  String _getYear(Map<String, dynamic> item) {
    final date = (item['release_date'] ?? item['first_air_date'])?.toString() ?? '';
    if (date.length >= 4) return date.substring(0, 4);
    return '';
  }

  String _detectSitio(Map<String, dynamic> item) {
    final s = (item['sitio'] ?? item['fuente'] ?? '').toString().trim();
    if (s.isNotEmpty) return s.toLowerCase();
    final url = (item['url'] ?? item['link'] ?? '').toString().toLowerCase();
    if (url.contains('canela.tv') || url.contains('canelatv')) return 'canela';
    if (url.contains('jkanime')) return 'jkanime';
    if (url.contains('tioanime')) return 'tioanime';
    if (url.contains('animeflv')) return 'animeflv';
    if (url.contains('cuevana')) return 'cuevana';
    if (url.contains('pelisplus')) return 'pelisplus';
    if (url.contains('serieskao')) return 'serieskao';
    if (url.contains('tioplus')) return 'tioplus';
    if (url.contains('seriesflix')) return 'seriesflix';
    if (url.contains('cineby')) return 'cineby';
    if (url.contains('thanhdattoday')) return 'thanhdattoday';
    if (url.contains('cinecalidad')) return 'cinecalidad';
    if (url.contains('telemundo')) return 'telemundo';
    return '';
  }

  void _openItem(Map<String, dynamic> item) {
    final sitio = _detectSitio(item);
    final externalUrl = (item['url'] ?? item['link'] ?? '').toString().trim();
    final rawTipo = (item['tipo'] ?? item['type'] ?? item['media_type'] ?? '').toString().toLowerCase();
    final bool isSeries = rawTipo == 'tv' || rawTipo == 'serie' || (item['name'] != null && item['title'] == null);
    final isMovie = widget.isMovie ? !isSeries : (rawTipo == 'movie' || rawTipo == 'pelicula' || !isSeries);
    final mediaType = isMovie ? 'movie' : 'tv';
    final titulo = (item['titulo'] ?? item['title'] ?? item['name'] ?? '').toString().trim();

    final esFuenteExterna = sitio.isNotEmpty && externalUrl.isNotEmpty;
    if (esFuenteExterna) {
      if (widget.isTv) {
        Navigator.of(context).push(
          PageRouteBuilder(
            pageBuilder: (_, animation, __) => FadeTransition(
              opacity: animation,
              child: tv_derivar.DerivarTvPage(
                servicio: sitio,
                url: externalUrl,
                titulo: titulo,
                tipo: mediaType,
              ),
            ),
            transitionDuration: const Duration(milliseconds: 250),
          ),
        );
      } else {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => mobile_derivar.DerivarPage(
              servicio: sitio,
              url: externalUrl,
              titulo: titulo,
              tipo: mediaType,
            ),
          ),
        );
      }
      return;
    }

    final id = parseCanonicalTmdbId(item['tmdb_id']) ??
        parseCanonicalTmdbId(item['idtmdb']) ??
        parseCanonicalTmdbId(item['idcontenido']) ??
        parseCanonicalTmdbId(item['contenido_id']) ??
        parseCanonicalTmdbId(item['id']) ??
        0;
    if (id <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Este contenido no tiene información disponible'),
          backgroundColor: Colors.redAccent,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    if (widget.isTv) {
      Navigator.of(context).push(
        PageRouteBuilder(
          pageBuilder: (_, animation, __) => FadeTransition(
            opacity: animation,
            child: tv_content.PageContenido(
              idcontenido: id,
              tmdbId: id,
              mediaType: mediaType,
              expectedTitle: titulo.isNotEmpty ? titulo : null,
            ),
          ),
          transitionDuration: const Duration(milliseconds: 250),
        ),
      );
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => mobile_content.PageContenido(
            idcontenido: id,
            tmdbId: id,
            mediaType: mediaType,
            expectedTitle: titulo.isNotEmpty ? titulo : null,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTv = widget.isTv || MediaQuery.sizeOf(context).width > 700;
    final cols = isTv ? 6 : 3;
    final childRatio = isTv ? 0.68 : 0.65;

    return Scaffold(
      backgroundColor: kBgColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: isTv
            ? Focus(
                focusNode: _backFocusNode,
                autofocus: widget.items.isEmpty,
                onKeyEvent: (node, event) {
                  if (event is! KeyDownEvent) return KeyEventResult.ignored;
                  if (event.logicalKey == LogicalKeyboardKey.arrowDown &&
                      widget.items.isNotEmpty) {
                    _getFocusNodeFor(0).requestFocus();
                    return KeyEventResult.handled;
                  }
                  if (event.logicalKey == LogicalKeyboardKey.select ||
                      event.logicalKey == LogicalKeyboardKey.enter) {
                    Navigator.of(context).pop();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: Builder(
                  builder: (context) {
                    final hasFocus = Focus.of(context).hasFocus;
                    return IconButton(
                      icon: Icon(
                        Icons.arrow_back_rounded,
                        color: hasFocus ? kAccentColor : Colors.white,
                        size: 26,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    );
                  },
                ),
              )
            : IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                widget.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 20,
                  letterSpacing: -0.3,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${_currentItems.length} títulos',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Barra de categorías (Todos, Películas, Series, Novelas, Anime) ──
          Container(
            height: 48,
            padding: EdgeInsets.symmetric(horizontal: isTv ? 28 : 14),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _kCategories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, catIdx) {
                final cat = _kCategories[catIdx];
                final isSelected = _selectedCategory == cat;
                final fNode = _categoryFocusNodes[cat];

                if (isTv && fNode != null) {
                  return Focus(
                    focusNode: fNode,
                    onKeyEvent: (node, event) {
                      if (event is! KeyDownEvent) return KeyEventResult.ignored;
                      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                        if (_currentItems.isNotEmpty) {
                          _getFocusNodeFor(0).requestFocus();
                          return KeyEventResult.handled;
                        }
                      }
                      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                        _backFocusNode.requestFocus();
                        return KeyEventResult.handled;
                      }
                      if (event.logicalKey == LogicalKeyboardKey.arrowLeft && catIdx > 0) {
                        _categoryFocusNodes[_kCategories[catIdx - 1]]?.requestFocus();
                        return KeyEventResult.handled;
                      }
                      if (event.logicalKey == LogicalKeyboardKey.arrowRight && catIdx < _kCategories.length - 1) {
                        _categoryFocusNodes[_kCategories[catIdx + 1]]?.requestFocus();
                        return KeyEventResult.handled;
                      }
                      if (event.logicalKey == LogicalKeyboardKey.select ||
                          event.logicalKey == LogicalKeyboardKey.enter) {
                        _selectCategory(cat);
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
                    child: Builder(
                      builder: (bCtx) {
                        final hasFocus = Focus.of(bCtx).hasFocus;
                        return ChoiceChip(
                          label: Text(cat),
                          selected: isSelected,
                          onSelected: (_) => _selectCategory(cat),
                          selectedColor: kAccentColor,
                          backgroundColor: hasFocus ? Colors.white24 : const Color(0xFF1E1E24),
                          labelStyle: TextStyle(
                            color: isSelected || hasFocus ? Colors.white : Colors.white70,
                            fontWeight: isSelected || hasFocus ? FontWeight.bold : FontWeight.w500,
                            fontSize: 13,
                          ),
                          side: BorderSide(
                            color: hasFocus
                                ? Colors.white
                                : (isSelected ? kAccentColor : Colors.white12),
                            width: hasFocus ? 2.0 : 1.0,
                          ),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        );
                      },
                    ),
                  );
                }

                return ChoiceChip(
                  label: Text(cat),
                  selected: isSelected,
                  onSelected: (_) => _selectCategory(cat),
                  selectedColor: kAccentColor,
                  backgroundColor: const Color(0xFF1E1E24),
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : Colors.white70,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    fontSize: 13,
                  ),
                  side: BorderSide(
                    color: isSelected ? kAccentColor : Colors.white12,
                  ),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                );
              },
            ),
          ),
          const SizedBox(height: 6),

          // ── Cuerpo de la lista / Grid ──
          Expanded(
            child: _loadingCategory
                ? const Center(
                    child: CircularProgressIndicator(
                      color: kAccentColor,
                      strokeWidth: 2.5,
                    ),
                  )
                : _currentItems.isEmpty
                    ? Center(
                        child: Text(
                          'No hay contenido disponible para "$_selectedCategory".',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 15,
                          ),
                        ),
                      )
                    : GridView.builder(
                        controller: _scrollController,
                        padding: EdgeInsets.fromLTRB(
                          isTv ? 28 : 14,
                          8,
                          isTv ? 28 : 14,
                          isTv ? 36 : 28,
                        ),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: cols,
                          childAspectRatio: childRatio,
                          crossAxisSpacing: isTv ? 14 : 10,
                          mainAxisSpacing: isTv ? 18 : 12,
                        ),
                        itemCount: _currentItems.length,
                        itemBuilder: (context, index) {
                          final item = _currentItems[index];
                          final posterUrl = _getImageUrl(item);
                          final title = _getTitle(item);
                          final rating = _getRating(item);
                          final year = _getYear(item);

                          if (isTv) {
                            final node = _getFocusNodeFor(index);
                            return Focus(
                              focusNode: node,
                              autofocus: index == 0,
                              onFocusChange: (hasFocus) {
                                if (hasFocus) {
                                  setState(() => _focusedIndex = index);
                                  final ctx = node.context;
                                  if (ctx != null) {
                                    Scrollable.ensureVisible(
                                      ctx,
                                      alignment: 0.3,
                                      duration: const Duration(milliseconds: 200),
                                      curve: Curves.easeInOut,
                                    );
                                  }
                                }
                              },
                              onKeyEvent: (node, event) {
                                if (event is! KeyDownEvent) return KeyEventResult.ignored;

                                if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                                  if (index < cols) {
                                    _categoryFocusNodes[_selectedCategory]?.requestFocus();
                                    return KeyEventResult.handled;
                                  }
                                  _getFocusNodeFor(index - cols).requestFocus();
                                  return KeyEventResult.handled;
                                }
                                if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                                  final next = index + cols;
                                  if (next < _currentItems.length) {
                                    _getFocusNodeFor(next).requestFocus();
                                    return KeyEventResult.handled;
                                  }
                                  return KeyEventResult.ignored;
                                }
                                if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                                  if (index % cols > 0) {
                                    _getFocusNodeFor(index - 1).requestFocus();
                                    return KeyEventResult.handled;
                                  }
                                  return KeyEventResult.ignored;
                                }
                                if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                                  if ((index % cols < cols - 1) &&
                                      index + 1 < _currentItems.length) {
                                    _getFocusNodeFor(index + 1).requestFocus();
                                    return KeyEventResult.handled;
                                  }
                                  return KeyEventResult.ignored;
                                }
                                if (event.logicalKey == LogicalKeyboardKey.select ||
                                    event.logicalKey == LogicalKeyboardKey.enter) {
                                  _openItem(item);
                                  return KeyEventResult.handled;
                                }
                                return KeyEventResult.ignored;
                              },
                    child: Builder(
                      builder: (fCtx) {
                        final hasFocus = Focus.of(fCtx).hasFocus;
                        return GestureDetector(
                          onTap: () => _openItem(item),
                          child: AnimatedScale(
                            scale: hasFocus ? 1.05 : 1.0,
                            duration: const Duration(milliseconds: 140),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 140),
                              decoration: BoxDecoration(
                                color: kCardBg,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: hasFocus ? Colors.white : Colors.transparent,
                                  width: hasFocus ? 2.5 : 1.0,
                                ),
                                boxShadow: hasFocus
                                    ? [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.6),
                                          blurRadius: 14,
                                          spreadRadius: 2,
                                        ),
                                      ]
                                    : null,
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  if (posterUrl.isNotEmpty)
                                    CachedNetworkImage(
                                      imageUrl: posterUrl,
                                      fit: BoxFit.cover,
                                      memCacheWidth: 320,
                                      errorWidget: (_, __, ___) => _FallbackTitle(title: title),
                                    )
                                  else
                                    _FallbackTitle(title: title),
                                  if (rating > 0)
                                    Positioned(
                                      top: 8,
                                      left: 8,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withValues(alpha: 0.75),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.star_rounded, color: Colors.amber, size: 12),
                                            const SizedBox(width: 3),
                                            Text(
                                              rating.toStringAsFixed(1),
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  if (year.isNotEmpty)
                                    Positioned(
                                      top: 8,
                                      right: 8,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withValues(alpha: 0.75),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          year,
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  );
                }

                // Vista móvil táctil
                return GestureDetector(
                  onTap: () => _openItem(item),
                  child: Container(
                    decoration: BoxDecoration(
                      color: kCardBg,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 6,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (posterUrl.isNotEmpty)
                          CachedNetworkImage(
                            imageUrl: posterUrl,
                            fit: BoxFit.cover,
                            memCacheWidth: 260,
                            errorWidget: (_, __, ___) => _FallbackTitle(title: title),
                          )
                        else
                          _FallbackTitle(title: title),
                        if (rating > 0)
                          Positioned(
                            top: 6,
                            left: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.8),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.star_rounded, color: Colors.amber, size: 11),
                                  const SizedBox(width: 2),
                                  Text(
                                    rating.toStringAsFixed(1),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
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
        ],
      ),
    );
  }
}

class _FallbackTitle extends StatelessWidget {
  final String title;
  const _FallbackTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1E1E24),
      padding: const EdgeInsets.all(10),
      alignment: Alignment.center,
      child: Text(
        title,
        maxLines: 3,
        textAlign: TextAlign.center,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
