# Investigación Comparativa de Backends de Scraping (WAVE 12.19)
**Filmotic - Arquitectura Híbrida: Backend API Centralizado + Fallback Local**

---

## 1. Resumen Ejecutivo y Arquitectura Propuesta

Actualmente Filmotic ejecuta los scrapers de forma distribuida en el dispositivo cliente (móvil y Android TV). Aunque esto garantiza autonomía, presenta desafíos de mantenimiento continuo: los sitios web de streaming cambian con frecuencia sus protecciones y estructuras HTML, obligando a recompilar y actualizar el APK ante cada cambio.

El modelo utilizado por aplicaciones consolidadas (Kino, MagisTV, XuperTV) desacopla la extracción del cliente:

```
┌─────────────────────────────────┐
│     Filmotic Client             │
│  (Móvil Flutter & Android TV)   │
└───────────────┬─────────────────┘
                │
         1. HTTP Request
                │
                ▼
┌─────────────────────────────────┐         ┌───────────────────────────────┐
│     Backend de Scraping         │◀───────▶│  TMDB API & Redis Cache       │
│   (VPS / Docker / Node.js)      │         └───────────────────────────────┘
│  - 13 a 50+ proveedores         │
│  - Bypass Ad & Header Injection │
│  - Actualizable sin tocar APK   │
└───────────────┬─────────────────┘
                │
   [En caso de Fallo o Timeout]
                ▼
┌─────────────────────────────────┐
│  Scrapers Nativos Filmotic      │
│  (PelisPlusHD, Cuevana, Anime)  │
│      [Fallback de Emergencia]   │
└─────────────────────────────────┘
```

---

## 2. Comparación de los 3 Proyectos Evaluados

| Criterio | 🥇 CinePro Core (`cinepro-org/core`) | 🥈 TMDB-Embed-API (`Inside4ndroid/TMDB-Embed-API`) | 🥉 Consumet API (`consumet/consumet-api`) |
| :--- | :--- | :--- | :--- |
| **Repositorio** | `cinepro-org/core` | `Inside4ndroid/TMDB-Embed-API` | `consumet/consumet-api` |
| **Estándar / Protocolo** | OMSS (Open Media Streaming Standard) + Stremio + MCP | REST API directo JSON | Multi-provider REST por categoría |
| **Parámetro de Entrada** | TMDB ID / IMDB ID (`movie` o `tv`) | TMDB ID (`movie` o `series`) | Query de texto / Slug propietario por proveedor |
| **Resolución Directa TMDB** | ✅ Sí (automático por ID) | ✅ Sí (automático por ID) | ❌ No (requiere búsqueda y mapeo previo) |
| **Cantidad de Fuentes** | 50+ proveedores modulares | 13+ proveedores (VixSrc, Vidlink, StreamFlix, etc.) | ~15 proveedores (varios inactivos) |
| **Formato de Respuesta** | Stream list OMSS / Streams array | Array de objetos `{name, title, url, quality, provider, headers}` | Objeto dependiente del scraper |
| **Soporte Docker** | `ghcr.io/cinepro-org/core:latest` | `inside4ndroid/tmdb-embed-api` | `riimuru/consumet-api` |
| **Requisitos** | TMDB API Key, Node.js 20+, Redis (opcional) | TMDB API Key, Node.js | Node.js |
| **Compatibilidad Filmotic** | **Alta** (Ideal para Stremio/OMSS federado) | **Máxima** (Endpoints diseñados exactamente para reproductores) | **Media/Baja** (Inestable para películas en español) |

---

## 3. Análisis en Detalle

### 🥇 1. CinePro Core (`cinepro-org/core`)
- **Fortalezas**:
  - Altísima cobertura con más de 50 proveedores.
  - Implementa el estándar OMSS y compatibilidad Stremio Addon (`/stremio/manifest.json`), lo que permite conectar Filmotic tanto como API directa como a través del ecosistema Stremio.
  - Integración nativa con Redis para cachear streams resueltos (reduciendo llamadas redundantes).
  - Admite Model Context Protocol (MCP).
- **Despliegue Docker**:
  ```bash
  docker run -d --name cinepro-core \
    -p 3000:3000 \
    -e TMDB_API_KEY=<tu_api_key_tmdb> \
    ghcr.io/cinepro-org/core:latest
  ```
- **Despliegue Node.js Nativo**:
  ```bash
  git clone https://github.com/cinepro-org/core.git
  cd core
  npm install
  TMDB_API_KEY=<tu_api_key_tmdb> npm run start
  ```

---

### 🥈 2. TMDB-Embed-API (`Inside4ndroid/TMDB-Embed-API`)
- **Fortalezas**:
  - **La integración más limpia y directa con Filmotic**: Filmotic ya cuenta con `tmdbId`, temporada y capítulo en su modelo de datos.
  - Endpoints REST simples:
    - `GET /api/health` -> Chequeo de liveness del servicio.
    - `GET /api/status` -> Estado de los proveedores.
    - `GET /api/streams/:type/:tmdbId?season=X&episode=Y` -> Devuelve lista directa de streams con headers necesarios para `video_player`.
  - Mapeo 1:1 con el reproductor de Filmotic:
    ```json
    [
      {
        "name": "Vidlink",
        "title": "Película - 1080p",
        "url": "https://stream.server/master.m3u8",
        "quality": "1080p",
        "provider": "vidlink",
        "headers": {
          "User-Agent": "Mozilla/5.0...",
          "Referer": "https://vidlink.pro/"
        }
      }
    ]
    ```
- **Despliegue Docker**:
  ```bash
  docker run -d --name tmdb-embed-api \
    -p 3000:3000 \
    -e TMDB_API_KEY=<tu_api_key_tmdb> \
    inside4ndroid/tmdb-embed-api
  ```

---

### 🥉 3. Consumet API (`consumet/consumet-api`)
- **Fortalezas**:
  - Amplia documentación y comunidad histórica en anime.
- **Desventajas**:
  - El servicio público oficial fue descontinuado.
  - No usa TMDB IDs directamente en las fuentes principales de películas/series (requiere flujo en 3 pasos: búsqueda por texto -> selección de id interno -> extracción de stream).
  - Varios de sus scrapers de películas occidentales (FlixHQ, Fmovies) sufren caídas frecuentes por bloqueos de Cloudflare.

---

## 4. Estrategia de Implementación en Filmotic

### Soporte Dual (CinePro / TMDB-Embed / Generic OMSS)
El cliente `BackendScraperService` de Filmotic se implementa con una interfaz universal agnóstica:
1. **Configuración en `filmotic_config.json`**:
   - `backend.enabled`: `true`/`false`.
   - `backend.base_url`: URL del servidor (ej. `http://localhost:3000` o VPS en la nube).
   - `backend.type`: `tmdb_embed` | `cinepro` | `generic`.
   - `backend.timeout_seconds`: 10 segundos.
   - `backend.fallback_to_local`: `true` (mantiene scrapers nativos si el backend no responde).
2. **Fallback Transparente**:
   - Si el backend devuelve streams con éxito, se priorizan y enriquecen en el reproductor.
   - Si el backend experimenta timeout o error de red, el sistema conmuta automáticamente a los scrapers locales de Filmotic sin interrumpir la experiencia de usuario.
