import 'package:flutter/foundation.dart';
import 'package:lol/core/services/guardados_bus.dart';

enum NavigationTargetType {
  derivar,
  pageContenido,
  error,
}

class NavigationTarget {
  final NavigationTargetType type;
  final String servicio;
  final String url;
  final String titulo;
  final String tipo;
  final int tmdbId;
  final String? errorMessage;

  const NavigationTarget({
    required this.type,
    this.servicio = '',
    this.url = '',
    this.titulo = '',
    this.tipo = 'movie',
    this.tmdbId = 0,
    this.errorMessage,
  });
}

/// Resuelve quirúrgicamente el destino de navegación para cualquier item:
/// 1. Si tiene `sitio` o URL externa reconocible -> DerivarPage (sin pasar por TMDB)
/// 2. Si tiene `tmdb_id` válido (>0 y <2000000) -> PageContenido
/// 3. Ni sitio ni TMDB -> error honesto
NavigationTarget resolveNavigationTarget(Map<String, dynamic> item) {
  final rawSitio = (item['sitio'] ?? item['fuente'] ?? '').toString().trim();
  final url = (item['url'] ?? item['link'] ?? '').toString().trim();
  final titulo = (item['titulo'] ?? item['title'] ?? item['name'] ?? '').toString().trim();
  final tipo = canonicalMediaType(
      item['media_type'] ?? item['type'] ?? item['tipo'] ?? 'movie');

  String sitio = rawSitio.toLowerCase();
  if (sitio.isEmpty && url.isNotEmpty) {
    final lowerUrl = url.toLowerCase();
    if (lowerUrl.contains('canela.tv') || lowerUrl.contains('canelatv')) {
      sitio = 'canelatv';
    } else if (lowerUrl.contains('telemundo')) {
      sitio = 'telemundo';
    } else if (lowerUrl.contains('jkanime')) {
      sitio = 'jkanime';
    } else if (lowerUrl.contains('tioanime')) {
      sitio = 'tioanime';
    } else if (lowerUrl.contains('animeflv')) {
      sitio = 'animeflv';
    } else if (lowerUrl.contains('cuevana')) {
      sitio = 'cuevana';
    } else if (lowerUrl.contains('pelisplus')) {
      sitio = 'pelisplus';
    } else if (lowerUrl.contains('serieskao')) {
      sitio = 'serieskao';
    } else if (lowerUrl.contains('tioplus')) {
      sitio = 'tioplus';
    } else if (lowerUrl.contains('seriesflix')) {
      sitio = 'seriesflix';
    } else if (lowerUrl.contains('cineby')) {
      sitio = 'cineby';
    } else if (lowerUrl.contains('thanhdattoday')) {
      sitio = 'thanhdattoday';
    } else if (lowerUrl.contains('cinecalidad')) {
      sitio = 'cinecalidad';
    }
  }

  final tmdbRaw = item['tmdb_id'] ?? item['idtmdb'] ?? item['idcontenido'];
  debugPrint('[Navigation] Abriendo contenido: "$titulo" | sitio: ${sitio.isEmpty ? "null" : sitio} | tmdb_id: $tmdbRaw');

  // Regla estricta 1: Fuente externa (novelas, anime, scrapers)
  if (sitio.isNotEmpty) {
    debugPrint('[Navigation] Enrutando a: DerivarPage (servicio: $sitio)');
    return NavigationTarget(
      type: NavigationTargetType.derivar,
      servicio: sitio,
      url: url,
      titulo: titulo,
      tipo: tipo,
    );
  }

  // Regla estricta 2: TMDB con ID válido
  final tmdbId = parseCanonicalTmdbId(item['tmdb_id'] ?? item['idtmdb'] ?? item['idcontenido'] ?? item['contenido_id'] ?? item['id']);
  if (tmdbId != null && tmdbId > 0 && tmdbId < 2000000) {
    debugPrint('[Navigation] Enrutando a: PageContenido (tmdbId: $tmdbId)');
    return NavigationTarget(
      type: NavigationTargetType.pageContenido,
      tmdbId: tmdbId,
      titulo: titulo,
      tipo: tipo,
    );
  }

  // Regla estricta 3: Ni fuente externa ni TMDB válido -> error honesto
  debugPrint('[Navigation] Error: sin fuente externa ni tmdbId válido para "$titulo"');
  return const NavigationTarget(
    type: NavigationTargetType.error,
    errorMessage: 'Este contenido no tiene información disponible',
  );
}
