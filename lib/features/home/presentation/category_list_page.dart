import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../content/presentation/content_page.dart' as mobile_content;
import '../../content/presentation/tv_content_page.dart' as tv_content;

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

  int _focusedIndex = -1;

  @override
  void dispose() {
    _scrollController.dispose();
    _backFocusNode.dispose();
    for (final node in _itemFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
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

  void _openItem(Map<String, dynamic> item) {
    final id = item['tmdb_id'] as int? ??
        item['idcontenido'] as int? ??
        (item['id'] as num?)?.toInt() ??
        0;
    if (id <= 0) return;
    final rawTipo = (item['tipo'] ?? item['type'] ?? item['media_type'] ?? '').toString().toLowerCase();
    final bool isSeries = rawTipo == 'tv' || rawTipo == 'serie' || (item['name'] != null && item['title'] == null);
    final isMovie = widget.isMovie ? !isSeries : (rawTipo == 'movie' || rawTipo == 'pelicula' || !isSeries);
    final mediaType = isMovie ? 'movie' : 'tv';

    if (widget.isTv) {
      Navigator.of(context).push(
        PageRouteBuilder(
          pageBuilder: (_, animation, __) => FadeTransition(
            opacity: animation,
            child: tv_content.PageContenido(
              idcontenido: id,
              tmdbId: id,
              mediaType: mediaType,
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
                '${widget.items.length} títulos',
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
      body: widget.items.isEmpty
          ? Center(
              child: Text(
                'No hay contenido disponible en esta sección.',
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
                14,
                isTv ? 28 : 14,
                isTv ? 36 : 28,
              ),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                childAspectRatio: childRatio,
                crossAxisSpacing: isTv ? 14 : 10,
                mainAxisSpacing: isTv ? 18 : 12,
              ),
              itemCount: widget.items.length,
              itemBuilder: (context, index) {
                final item = widget.items[index];
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
                          _backFocusNode.requestFocus();
                          return KeyEventResult.handled;
                        }
                        _getFocusNodeFor(index - cols).requestFocus();
                        return KeyEventResult.handled;
                      }
                      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                        final next = index + cols;
                        if (next < widget.items.length) {
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
                            index + 1 < widget.items.length) {
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
