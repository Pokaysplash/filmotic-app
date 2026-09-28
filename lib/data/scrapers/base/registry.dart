// lib/fuentes/apis/home/registry.dart
//
// ÚNICO lugar donde se registran las fuentes.
// Para agregar una fuente nueva:
//   1. Implementa el scraper (fetch) y/o el parser de búsqueda (en buscador.dart).
//   2. Añade una entrada Fuente aquí.
//   3. pag.dart la usa automáticamente — no hace falta tocarlo.

import 'scraper_context.dart';
import '../home/serieskao_scraper.dart';
import '../home/tioplus_scraper.dart';
import '../home/cuevana_scraper.dart';
import '../home/pelisplus_scraper.dart';
import '../cinecalidad_scraper.dart';
import '../thanhdattoday_scraper.dart';
import '../animeflv_scraper.dart';
import 'buscador.dart';
import '../../../core/services/remote_config_service.dart';
/// Todas las fuentes disponibles (listado + búsqueda).
final List<Fuente> fuentesRegistry = [
  // ── Cuevana ────────────────────────────────────────────────────────────
  Fuente(
    id: 'cuevana',
    label: 'Cuevana',
    tipos: CuevanaScraper.tiposDisponibles(),
    generos: CuevanaScraper.generos,
    supportsPopulares: true,
    hasListing: true,
    hasSearch: true,
    fetch: ({String? tipo, String? genero, bool populares = false, int page = 1}) {
      return CuevanaScraper.fetch(
        tipo: populares ? 'tendencias' : (genero == null || genero.isEmpty ? tipo : null),
        genero: genero == null || genero.isEmpty ? null : genero,
        page: page,
      );
    },
    search: BuscadorScraper.searchCuevana,
  ),

  // ── PelisPlus ──────────────────────────────────────────────────────────
  Fuente(
    id: 'pelisplus',
    label: 'PelisPlus',
    tipos: PelisPlusScraper.tiposDisponibles(),
    generos: PelisPlusScraper.generos,
    supportsPopulares: true,
    hasListing: true,
    hasSearch: true,
    fetch: ({String? tipo, String? genero, bool populares = false, int page = 1}) {
      return PelisPlusScraper.fetch(
        tipo: genero == null || genero.isEmpty ? tipo : null,
        genero: genero == null || genero.isEmpty ? null : genero,
        page: page,
      );
    },
    search: BuscadorScraper.searchPelisPlus,
  ),

  // ── SeriesKao ──────────────────────────────────────────────────────────
  Fuente(
    id: 'serieskao',
    label: 'SeriesKao',
    tipos: SeriesKaoScraper.tiposDisponibles(),
    generos: SeriesKaoScraper.generos,
    supportsPopulares: true,
    hasListing: true,
    hasSearch: true,
    fetch: ({String? tipo, String? genero, bool populares = false, int page = 1}) {
      return SeriesKaoScraper.fetch(
        tipo: genero == null || genero.isEmpty ? tipo : null,
        genero: genero == null || genero.isEmpty ? null : genero,
        populares: populares,
        page: page,
      );
    },
    search: BuscadorScraper.searchSeriesKao,
  ),

  // ── TioPlus ────────────────────────────────────────────────────────────
  Fuente(
    id: 'tioplus',
    label: 'TioPlus',
    tipos: TioPlusScraper.tiposDisponibles(),
    generos: const [
      'accion',
      'drama',
      'comedia',
      'terror',
      'romance',
      'ciencia-ficcion',
    ],
    supportsPopulares: true,
    hasListing: true,
    hasSearch: true,
    fetch: ({String? tipo, String? genero, bool populares = false, int page = 1}) {
      return TioPlusScraper.fetch(
        tipo: tipo ?? 'movie',
        genero: genero == null || genero.isEmpty ? null : genero,
        page: page,
      );
    },
    search: BuscadorScraper.searchTioPlus,
  ),

  // ── CineHax (solo búsqueda) ────────────────────────────────────────────
  Fuente(
    id: 'cinehax',
    label: 'CineHax',
    tipos: const ['movie', 'tv'],
    generos: const [],
    hasListing: false,
    hasSearch: true,
    search: BuscadorScraper.searchCineHax,
  ),

  // ── Cinecalidad ────────────────────────────────────────────────────────
  Fuente(
    id: 'cinecalidad',
    label: 'Cinecalidad',
    tipos: CinecalidadScraper.tiposDisponibles(),
    generos: CinecalidadScraper.generos,
    supportsPopulares: true,
    hasListing: true,
    hasSearch: true,
    fetch: ({String? tipo, String? genero, bool populares = false, int page = 1}) {
      return CinecalidadScraper.fetch(
        tipo: genero == null || genero.isEmpty ? tipo : null,
        genero: genero == null || genero.isEmpty ? null : genero,
        populares: populares,
        page: page,
      );
    },
    search: CinecalidadScraper.search,
  ),

  // ── ThanhDatToday ──────────────────────────────────────────────────────
  Fuente(
    id: 'thanhdattoday',
    label: 'ThanhDatToday',
    tipos: ThanhDatTodayScraper.tiposDisponibles(),
    generos: ThanhDatTodayScraper.generos,
    supportsPopulares: true,
    hasListing: true,
    hasSearch: true,
    fetch: ({String? tipo, String? genero, bool populares = false, int page = 1}) {
      return ThanhDatTodayScraper.fetch(
        tipo: genero == null || genero.isEmpty ? tipo : null,
        genero: genero == null || genero.isEmpty ? null : genero,
        populares: populares,
        page: page,
      );
    },
    search: ThanhDatTodayScraper.search,
  ),

  // ── AnimeFLV ───────────────────────────────────────────────────────────
  Fuente(
    id: 'animeflv',
    label: 'AnimeFLV',
    tipos: AnimeFLVScraper.tiposDisponibles(),
    generos: AnimeFLVScraper.generos,
    supportsPopulares: true,
    hasListing: true,
    hasSearch: true,
    fetch: ({String? tipo, String? genero, bool populares = false, int page = 1}) {
      return AnimeFLVScraper.fetch(
        tipo: genero == null || genero.isEmpty ? tipo : null,
        genero: genero == null || genero.isEmpty ? null : genero,
        populares: populares,
        page: page,
      );
    },
    search: AnimeFLVScraper.search,
  ),
];

/// Fuentes que tienen listado (aparecen en el selector de servicio).
List<Fuente> get fuentesConListado => fuentesRegistry
    .where((f) =>
        f.hasListing && RemoteConfigService.instance.isSourceEnabled(f.id))
    .toList();

/// Fuentes que tienen búsqueda (aparecen en el filtro de búsqueda).
List<Fuente> get fuentesConBusqueda => fuentesRegistry
    .where((f) =>
        f.hasSearch && RemoteConfigService.instance.isSourceEnabled(f.id))
    .toList();

/// Busca una fuente por id.
Fuente? fuenteById(String id) {
  try {
    return fuentesRegistry.firstWhere((f) => f.id == id);
  } catch (_) {
    return null;
  }
}

Future<BuscadorResult> buscarEnFuentes({
  required String q,
  String tipo = 'todas',
}) async {
  final query = q.trim();
  if (query.isEmpty) {
    return BuscadorResult(ok: false, error: 'Escribe algo para buscar');
  }

  final aBuscar = tipo == 'todas'
      ? fuentesConBusqueda
      : fuentesConBusqueda.where((f) => f.id == tipo).toList();

  if (aBuscar.isEmpty) {
    return BuscadorResult(
      ok: false,
      error: 'Fuente de búsqueda no encontrada: $tipo',
    );
  }

  // Ejecutar búsqueda en paralelo
  final futures = aBuscar.map((fuente) async {
    if (fuente.search == null) return <BuscadorItem>[];
    try {
      return await fuente.search!(query);
    } catch (_) {
      return <BuscadorItem>[];
    }
  });

  final listResults = await Future.wait(futures);

  final todosLosItems = <BuscadorItem>[];
  for (final items in listResults) {
    todosLosItems.addAll(items);
  }

  // Deduplicar por título normalizado
  final deduplicados = <String, BuscadorItem>{};
  for (final item in todosLosItems) {
    // Normalizar: sin espacios, minúsculas
    final normTitle = item.titulo.toLowerCase().replaceAll(RegExp(r'\s+'), '');
    final key = '${item.tipo}_$normTitle';

    if (deduplicados.containsKey(key)) {
      final existente = deduplicados[key]!;
      final agrupadas = List<Map<String, String>>.from(existente.fuentesAgrupadas ?? []);
      agrupadas.add({'sitio': item.sitio, 'url': item.url});

      deduplicados[key] = BuscadorItem(
        sitio: existente.sitio, // visual fallback
        titulo: existente.titulo,
        tipo: existente.tipo,
        url: existente.url,
        imagen: existente.imagen.isNotEmpty ? existente.imagen : item.imagen,
        anio: existente.anio ?? item.anio,
        rating: existente.rating ?? item.rating,
        tmdbId: existente.tmdbId ?? item.tmdbId,
        fuentesAgrupadas: agrupadas,
      );
    } else {
      deduplicados[key] = BuscadorItem(
        sitio: item.sitio,
        titulo: item.titulo,
        tipo: item.tipo,
        url: item.url,
        imagen: item.imagen,
        anio: item.anio,
        rating: item.rating,
        tmdbId: item.tmdbId,
        fuentesAgrupadas: [{'sitio': item.sitio, 'url': item.url}],
      );
    }
  }

  final deduplicatedList = deduplicados.values.toList();

  return BuscadorResult(
    ok: true,
    query: query,
    tipo: tipo,
    total: deduplicatedList.length,
    resultados: {'todas': deduplicatedList},
  );
}