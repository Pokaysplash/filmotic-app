# Notas de Arquitectura LolPlusTV

## 1. Visión General del Proyecto
LolPlusTV es una aplicación desarrollada en Flutter con arquitectura modular por capas orientada al streaming y consumo de contenido multimedia. Soporta tanto dispositivos móviles (Mobile Shell) como Android TV (TV Shell con navegación D-Pad).

## 2. Estructura de Capas
- **`lib/core/`**:
  - `constants/`: Claves de almacenamiento, versiones, constantes de reproducción y addons.
  - `network/`: Cliente HTTP, interceptores, caché de peticiones, validación de red.
  - `storage/`: `LocalStorage` (SharedPreferences), `database.dart` (placeholder), `cache_manager.dart`.
  - `utils/`: Utilidades para HTML, JSON, Strings, URLs, plataformas y fechas.
  - `errors/` & `result/`: Manejo de excepciones y tipos de resultado funcional (`Result`, `Failure`, `Success`).
- **`lib/data/`**:
  - `scrapers/`: Implementaciones de scraping para listados (`home/`), detalles (`detail/`), servidores (`servers/`) y base común (`base/` con `registry.dart`, `buscador.dart`, `base_home_scraper.dart`, `detalle_scraper.dart`).
  - `extractors/`: Extracción directa de reproductores y streams (HLS/m3u8/mp4) como `hls_extractor.dart` y resolvers de hosts (`providers/`).
  - `aggregators/`: `source_aggregator.dart`, `server_aggregator.dart`, `main_fuentes_servidores.dart` para combinar y normalizar streams de múltiples orígenes.
- **`lib/domain/`**:
  - `models/`: Modelos de dominio (`content`, `player`, `server`, `source`, `user`, `addon`).
  - `repositories/`: Contratos de repositorios para favoritos, historial, fuentes y servidores.
  - `services/`: Servicios de dominio para orquestar la reproducción y extracción.
- **`lib/features/`**:
  - Módulos funcionales de la UI: `home`, `discover`, `search`, `content`, `player`, `profile`, `favorites`, `history`, `addons`, `settings`, `downloads`.
- **`lib/presentation/`**:
  - `mobile/mobile_shell.dart`: Shell principal para pantallas móviles táctiles.
  - `tv/tv_shell.dart`: Shell adaptado para Android TV con navegación optimizada para control remoto (D-Pad).

## 3. Patrón de Fuentes y Addons
1. **Listado (`fetch`)**: Cada fuente define un scraper (e.g. `fetch(tipo, genero, page)`) que retorna `ScraperResult` con lista de `ScraperItem`.
2. **Búsqueda (`search`)**: Cada fuente define su función en `BuscadorScraper` retornando `List<BuscadorItem>`.
3. **Registro (`registry.dart`)**: Las fuentes se registran en `fuentesRegistry` indicando si soportan listado (`hasListing`) y búsqueda (`hasSearch`).
4. **Detalle (`detalle_scraper.dart`)**: Recibe `servicio`, `url`, `titulo`, `tipo` y delega a su respectivo detalle scraper para parsear temporadas, episodios y sinopsis.
5. **Servidores (`main_fuentes_servidores.dart` & `server_aggregator.dart`)**: Obtiene los links de servidores o embeds según el contenido o episodio y los envía a verificación de stream.
6. **Extracción HLS (`hls_extractor.dart`)**: Resuelve URLs m3u8 mediante resolvers nativos o headless webview interceptando peticiones.

## 4. Plan de Adaptación
1. **Sembast Core Storage**: Reemplazar y desacoplar de Supabase, implementando un motor NoSQL local con colecciones para `cuentas`, `perfiles`, `favoritos` e `historial`.
2. **P2P Account Transfer**: Crear `TransferService` con `ServerSocket` y lectura QR para migrar perfiles entre dispositivos en red local con seguridad PIN y token UUID.
3. **Nuevas Fuentes**:
   - `thanhdattoday.online`
   - `cinecalidad.am`
   - `animeflv.com.es`
4. **Fallback Secuencial de Streams**: `ServerFallbackService` con timeout de 5s por servidor para garantizar reproducción automática sin intervención manual.
5. **TMDB y Trailers por Scraping**: Búsqueda directa en web themoviedb.org y extracción de `ytInitialData` para trailers de YouTube sin API keys de pago.
6. **Soporte TV y Build**: Asegurar compatibilidad D-Pad y manifiesto para Android TV.
