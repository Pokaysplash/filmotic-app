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
import '../canelatv_scraper.dart';
import '../telemundo_scraper.dart';
import '../jkanime_scraper.dart';
import '../tioanime_scraper.dart';
import '../seriesflix_scraper.dart';
import '../cineby_scraper.dart';
import '../animepahe_scraper.dart';
import '../gogoanime_scraper.dart';
import '../animeav1_scraper.dart';
import '../pelisplushd_scraper.dart';
import '../cuevana3_scraper.dart';
import '../animeflv_api_scraper.dart';
import 'buscador.dart';
import '../../../core/services/remote_config_service.dart';
import '../../../core/services/source_health_service.dart';

/// Todas las fuentes disponibles (listado + búsqueda) agrupadas por categoría.
final List<Fuente> fuentesRegistry = [
  // ── PelisPlusHD (WAVE 12.17 - Prioridad Alta) ─────────────────────────
  Fuente(
    id: 'pelisplushd',
    label: 'PelisPlusHD',
    category: 'movie',
    language: 'es',
    priority: 1,
    tipos: const ['movie', 'tv'],
    generos: const ['Acción', 'Comedia', 'Drama', 'Terror', 'Ciencia Ficción'],
    supportsPopulares: true,
    hasListing: true,
    hasSearch: true,
    fetch: ({String? tipo, String? genero, bool populares = false, int page = 1}) {
      return PelisPlusHdScraper.fetch(tipo: tipo, genero: genero, page: page);
    },
    search: (q) async {
      final items = await PelisPlusHdScraper.search(q);
      return items.map((i) => BuscadorItem(
        sitio: 'pelisplushd',
        titulo: i.titulo,
        tipo: i.tipo,
        url: i.url,
        imagen: i.poster,
        anio: i.year,
      )).toList();
    },
  ),

  // ── Cuevana3 (WAVE 12.17 - Prioridad Alta) ───────────────────────────
  Fuente(
    id: 'cuevana3',
    label: 'Cuevana3',
    category: 'movie',
    language: 'es',
    priority: 1,
    tipos: const ['movie', 'tv'],
    generos: const ['Acción', 'Estrenos', 'Comedia', 'Drama', 'Terror'],
    supportsPopulares: true,
    hasListing: true,
    hasSearch: true,
    fetch: ({String? tipo, String? genero, bool populares = false, int page = 1}) {
      return Cuevana3Scraper.fetch(tipo: tipo, genero: genero, page: page);
    },
    search: (q) async {
      final items = await Cuevana3Scraper.search(q);
      return items.map((i) => BuscadorItem(
        sitio: 'cuevana3',
        titulo: i.titulo,
        tipo: i.tipo,
        url: i.url,
        imagen: i.poster,
        anio: i.year,
      )).toList();
    },
  ),

  // ── AnimeFLV API (WAVE 12.17 - Prioridad Alta) ────────────────────────
  Fuente(
    id: 'animeflv_api',
    label: 'AnimeFLV (API)',
    category: 'anime',
    language: 'sub',
    priority: 1,
    tipos: const ['anime'],
    generos: const ['Anime', 'Acción', 'Aventura', 'Comedia', 'Shounen'],
    supportsPopulares: true,
    hasListing: true,
    hasSearch: true,
    fetch: ({String? tipo, String? genero, bool populares = false, int page = 1}) {
      return AnimeFlvApiScraper.fetch(tipo: tipo, genero: genero, page: page);
    },
    search: (q) async {
      final items = await AnimeFlvApiScraper.search(q);
      return items.map((i) => BuscadorItem(
        sitio: 'animeflv_api',
        titulo: i.titulo,
        tipo: 'anime',
        url: i.url,
        imagen: i.poster,
      )).toList();
    },
  ),

  // ── Cuevana (Películas y Series) ──────────────────────────────────────
  Fuente(
    id: 'cuevana',
    label: 'Cuevana',
    category: 'movie',
    language: 'es',
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

  // ── PelisPlus (Películas y Series) ───────────────────────────────────
  Fuente(
    id: 'pelisplus',
    label: 'PelisPlus',
    category: 'movie',
    language: 'es',
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

  // ── SeriesKao (Series) ───────────────────────────────────────────────
  Fuente(
    id: 'serieskao',
    label: 'SeriesKao',
    category: 'series',
    language: 'es',
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

  // ── TioPlus (Películas y Series) ─────────────────────────────────────
  Fuente(
    id: 'tioplus',
    label: 'TioPlus',
    category: 'movie',
    language: 'es',
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
    category: 'movie',
    language: 'es',
    tipos: const ['movie', 'tv'],
    generos: const [],
    hasListing: false,
    hasSearch: true,
    search: BuscadorScraper.searchCineHax,
  ),

  // ── Cinecalidad (Películas Multi-calidad) ──────────────────────────────
  Fuente(
    id: 'cinecalidad',
    label: 'Cinecalidad',
    category: 'movie',
    language: 'es',
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

  // ── ThanhDatToday (Películas y Series) ─────────────────────────────────
  Fuente(
    id: 'thanhdattoday',
    label: 'ThanhDatToday',
    category: 'movie',
    language: 'sub',
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

  // ── Canela.TV (Novelas y Series Latinas/Turcas) ─────────────────────────
  Fuente(
    id: 'canelatv',
    label: 'Canela.TV',
    category: 'novel',
    language: 'es',
    tipos: CanelaTVScraper.tiposDisponibles(),
    generos: CanelaTVScraper.generos,
    supportsPopulares: true,
    hasListing: true,
    hasSearch: true,
    fetch: ({String? tipo, String? genero, bool populares = false, int page = 1}) {
      return CanelaTVScraper.fetch(
        tipo: tipo,
        genero: genero,
        populares: populares,
        page: page,
      );
    },
    search: CanelaTVScraper.search,
  ),

  // ── Telemundo (Novelas y Súper Series) ──────────────────────────────────
  Fuente(
    id: 'telemundo',
    label: 'Telemundo',
    category: 'novel',
    language: 'es',
    tipos: TelemundoScraper.tiposDisponibles(),
    generos: TelemundoScraper.generos,
    supportsPopulares: false,
    hasListing: true,
    hasSearch: true,
    fetch: ({String? tipo, String? genero, bool populares = false, int page = 1}) {
      return TelemundoScraper.fetch(
        tipo: tipo,
        genero: genero,
        populares: populares,
        page: page,
      );
    },
    search: TelemundoScraper.search,
  ),

  // ── AnimeFLV (Anime Sub & Lat) ──────────────────────────────────────────
  Fuente(
    id: 'animeflv',
    label: 'AnimeFLV',
    category: 'anime',
    language: 'sub',
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

  // ── JKAnime (Anime) ────────────────────────────────────────────────────
  Fuente(
    id: 'jkanime',
    label: 'JKAnime',
    category: 'anime',
    language: 'sub',
    tipos: JKAnimeScraper.tiposDisponibles(),
    generos: JKAnimeScraper.generos,
    supportsPopulares: true,
    hasListing: true,
    hasSearch: true,
    fetch: ({String? tipo, String? genero, bool populares = false, int page = 1}) {
      return JKAnimeScraper.fetch(
        tipo: tipo,
        genero: genero,
        populares: populares,
        page: page,
      );
    },
    search: JKAnimeScraper.search,
  ),

  // ── TioAnime (Anime) ───────────────────────────────────────────────────
  Fuente(
    id: 'tioanime',
    label: 'TioAnime',
    category: 'anime',
    language: 'sub',
    tipos: TioAnimeScraper.tiposDisponibles(),
    generos: TioAnimeScraper.generos,
    supportsPopulares: true,
    hasListing: true,
    hasSearch: true,
    fetch: ({String? tipo, String? genero, bool populares = false, int page = 1}) {
      return TioAnimeScraper.fetch(
        tipo: tipo,
        genero: genero,
        populares: populares,
        page: page,
      );
    },
    search: TioAnimeScraper.search,
  ),

  // ── AnimePahe (Anime Global HD) ────────────────────────────────────────
  Fuente(
    id: 'animepahe',
    label: 'AnimePahe',
    category: 'anime',
    language: 'sub',
    tipos: AnimePaheScraper.tiposDisponibles(),
    generos: AnimePaheScraper.generos,
    supportsPopulares: true,
    hasListing: true,
    hasSearch: true,
    fetch: ({String? tipo, String? genero, bool populares = false, int page = 1}) {
      return AnimePaheScraper.fetch(
        tipo: tipo,
        genero: genero,
        populares: populares,
        page: page,
      );
    },
    search: AnimePaheScraper.search,
  ),

  // ── GogoAnime (Anime Sub & Dub) ────────────────────────────────────────
  Fuente(
    id: 'gogoanime',
    label: 'GogoAnime',
    category: 'anime',
    language: 'sub',
    tipos: GogoAnimeScraper.tiposDisponibles(),
    generos: GogoAnimeScraper.generos,
    supportsPopulares: true,
    hasListing: true,
    hasSearch: true,
    fetch: ({String? tipo, String? genero, bool populares = false, int page = 1}) {
      return GogoAnimeScraper.fetch(
        tipo: tipo,
        genero: genero,
        populares: populares,
        page: page,
      );
    },
    search: GogoAnimeScraper.search,
  ),

  // ── AnimeAV1 (Anime HD 1080p) ──────────────────────────────────────────
  Fuente(
    id: 'animeav1',
    label: 'AnimeAV1',
    category: 'anime',
    language: 'sub',
    tipos: AnimeAV1Scraper.tiposDisponibles(),
    generos: AnimeAV1Scraper.generos,
    supportsPopulares: true,
    hasListing: true,
    hasSearch: true,
    fetch: ({String? tipo, String? genero, bool populares = false, int page = 1}) {
      return AnimeAV1Scraper.fetch(
        tipo: tipo,
        genero: genero,
        populares: populares,
        page: page,
      );
    },
    search: AnimeAV1Scraper.search,
  ),

  // ── Seriesflix (Series y Películas - Latino, Castellano, VOS) ──────────
  Fuente(
    id: 'seriesflix',
    label: 'Seriesflix',
    category: 'series',
    language: 'sub',
    tipos: SeriesflixScraper.tiposDisponibles(),
    generos: SeriesflixScraper.generos,
    supportsPopulares: true,
    hasListing: true,
    hasSearch: true,
    fetch: ({String? tipo, String? genero, bool populares = false, int page = 1}) {
      return SeriesflixScraper.fetch(
        tipo: tipo,
        genero: genero,
        populares: populares,
        page: page,
      );
    },
    search: SeriesflixScraper.search,
  ),

  // ── Cineby (Películas y Series - VOS Original) ────────────────────────
  Fuente(
    id: 'cineby',
    label: 'Cineby',
    category: 'movie',
    language: 'sub',
    tipos: CinebyScraper.tiposDisponibles(),
    generos: CinebyScraper.generos,
    supportsPopulares: true,
    hasListing: true,
    hasSearch: true,
    fetch: ({String? tipo, String? genero, bool populares = false, int page = 1}) {
      return CinebyScraper.fetch(
        tipo: tipo,
        genero: genero,
        populares: populares,
        page: page,
      );
    },
    search: CinebyScraper.search,
  ),
];

/// Obtiene fuentes filtradas por su categoría ('movie', 'series', 'anime', 'novel').
List<Fuente> getFuentesByCategory(String category) => fuentesRegistry
    .where((f) =>
        f.category == category &&
        RemoteConfigService.instance.isSourceEnabled(f.id))
    .toList();

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

  final baseFuentes = tipo == 'todas'
      ? fuentesConBusqueda
      : fuentesConBusqueda.where((f) => f.id == tipo).toList();

  if (baseFuentes.isEmpty) {
    return BuscadorResult(
      ok: false,
      error: 'Fuente de búsqueda no encontrada: $tipo',
    );
  }

  // Mapa de prioridades estáticas declaradas
  final declaredPriorities = <String, int>{
    for (final f in baseFuentes) f.id: f.priority,
  };

  // Ordenar y filtrar dinámicamente según estado de salud
  final orderedIds = SourceHealthService.instance.getOrderedSources(
    candidates: baseFuentes.map((f) => f.id).toList(),
    declaredPriorities: declaredPriorities,
  );

  final aBuscar = baseFuentes
      .where((f) => orderedIds.contains(f.id))
      .toList()
    ..sort((a, b) => orderedIds.indexOf(a.id).compareTo(orderedIds.indexOf(b.id)));

  if (aBuscar.isEmpty) {
    return BuscadorResult(
      ok: false,
      error: 'No pudimos conectar con las fuentes en este momento. Reintentando...',
    );
  }

  // Ejecutar búsqueda en paralelo registrando telemetría de salud
  final futures = aBuscar.map((fuente) async {
    if (fuente.search == null) return <BuscadorItem>[];
    final sw = Stopwatch()..start();
    try {
      final items = await fuente.search!(query);
      sw.stop();
      if (items.isNotEmpty) {
        SourceHealthService.instance.recordSuccess(fuente.id, sw.elapsedMilliseconds);
      }
      return items;
    } catch (e) {
      sw.stop();
      SourceHealthService.instance.recordFailure(fuente.id, e.toString());
      return <BuscadorItem>[];
    }
  });

  final listResults = await Future.wait(futures);

  final todosLosItems = <BuscadorItem>[];
  for (final items in listResults) {
    todosLosItems.addAll(items);
  }

  if (todosLosItems.isEmpty) {
    return BuscadorResult(
      ok: false,
      error: 'No se encontraron resultados disponibles para "$query".',
      query: query,
      tipo: tipo,
      total: 0,
      resultados: {'todas': const []},
    );
  }

  // Deduplicar por título normalizado, priorizando la fuente más saludable y rápida
  final deduplicados = <String, BuscadorItem>{};
  for (final item in todosLosItems) {
    final normTitle = item.titulo.toLowerCase().replaceAll(RegExp(r'\s+'), '');
    final key = '${item.tipo}_$normTitle';

    if (deduplicados.containsKey(key)) {
      final existente = deduplicados[key]!;
      final agrupadas = List<Map<String, String>>.from(existente.fuentesAgrupadas ?? []);
      if (!agrupadas.any((g) => g['sitio'] == item.sitio)) {
        agrupadas.add({'sitio': item.sitio, 'url': item.url});
      }

      deduplicados[key] = BuscadorItem(
        sitio: existente.sitio,
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