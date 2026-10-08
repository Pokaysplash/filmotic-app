# 📚 Investigación Previa: Nuevas Fuentes para Filmotic (WAVE 12.17)

Este documento recopila la investigación y análisis técnico de los 3 repositorios y proyectos comunitarios de referencia para la integración de fuentes en paralelo con priorización dinámica en **Filmotic**.

---

## 1. `chrismichaelps/pelisplushd` (PelisPlusHD)

* **Repositorio:** [github.com/ChrisMichaelPerezSantiago/pelisplushd](https://github.com/ChrisMichaelPerezSantiago/pelisplushd)
* **Arquitectura de Referencia:** API / Scraper Node.js en Express con Cheerio.
* **Sitio Objetivo:** Plataformas derivadas de PelisPlusHD (`https://pelisplushd.lat`, `https://ww3.pelisplus.to`, `https://pelisplus.to`).
* **Mapeo de Endpoints & Rutas:**
  * **Catálogo de Películas:** `/peliculas?page={page}` o `/v1/GetAllMovies/{page}`.
  * **Catálogo de Series:** `/series?page={page}` o `/v1/GetAllSeries/{page}`.
  * **Búsqueda:** `/search?s={query}` o `/buscar?s={query}`.
  * **Estructura de Ficha / Detalle:** Extrae póster, sinopsis, año, director y elenco.
  * **Extracción de Servidores:** Iframe de reproducción y reproductores embed (Streamwish, Vidhide, Fembed, Upstream, etc.).
* **Estrategia en Dart para Filmotic:**
  * Implementar `PelisPlusHdScraper` con requests directos HTTP y parseo con `package:html`.
  * Fallback de dominios activos configurables en memoria.

---

## 2. `andresayac/cuevana3` (Cuevana3)

* **Repositorio:** [github.com/andresayac/cuevana3](https://github.com/andresayac/cuevana3)
* **Arquitectura de Referencia:** Scraper PHP / Web Provider modular con métodos estructurados:
  * `getMovies(type, page)`
  * `getSeries(type, page)`
  * `getSearch(query)`
  * `getDetail(url)`
  * `getLinks(url)`
* **Sitio Objetivo:** Plataformas activas de Cuevana3 (`https://wv3.cuevana3.eu`, `https://cuevana3.ch`, `https://ww3.cuevana3.me`).
* **Mapeo de Rutas & Selectores:**
  * **Listado:** `/peliculas`, `/series`, `/peliculas/estrenos`.
  * **Búsqueda:** `/inicio?s={query}` o `/search?s={query}` o `/buscar?q={query}`.
  * **Extracción de Servidores:** Parseo de JSON de hidratación Next.js (`__NEXT_DATA__`) o tags `<iframe data-src="...">` que contienen cyberlockers filtrados (`streamwish`, `vidhide`, `filelions`, `doodstream`).
* **Estrategia en Dart para Filmotic:**
  * Implementar `Cuevana3Scraper` con soporte dual: parseo Next.js JSON y fallback DOM HTML para extraer servidores en latino, castellano y subtitulado.

---

## 3. `jorgeajimenezl/animeflv-api` (AnimeFLV-API)

* **Repositorio:** [github.com/jorgeajimenezl/animeflv-api](https://github.com/jorgeajimenezl/animeflv-api)
* **Arquitectura de Referencia:** Wrapper Python sobre el portal oficial AnimeFLV (`https://www3.animeflv.net`).
* **Mapeo de Endpoints:**
  * **Catálogo & Géneros:** `https://www3.animeflv.net/browse?page={page}&order=rating`.
  * **Búsqueda:** `https://www3.animeflv.net/browse?q={query}`.
  * **Detalle Anime:** `https://www3.animeflv.net/anime/{slug}`. Contiene variables embebidas en JS:
    * `var anime_info = [...]`: ID, título original, géneros, estado.
    * `var episodes = [[1, 2345], [2, 2346], ...]`: lista de capítulos disponibles.
  * **Episodio & Servidores:** `https://www3.animeflv.net/ver/{slug}-{episodio}`. Contiene la variable JavaScript:
    * `var videos = {"SUB": [{"server": "...", "url": "..."}, ...]};`
    * Servidores disponibles: `streamwish`, `yourupload`, `mega`, `okru`, `maru`, `netu`.
* **Estrategia en Dart para Filmotic:**
  * Implementar `AnimeFlvApiScraper` que consuma `www3.animeflv.net` directamente en Dart, extrayendo los episodios y servidores mediante expresiones regulares ultrarrápidas sobre los scripts de la página.

---

## 4. Matriz de Priorización Dinámica (WAVE 12.17)

| Fuente ID | Tipo | Prioridad Inicial | Dominio Base Principal | Salud por Defecto |
|---|---|---|---|---|
| `pelisplushd` | Películas / Series | 1 (Máxima) | `https://ww3.pelisplus.to` / mirrors | Healthy |
| `cuevana3` | Películas / Series | 1 (Máxima) | `https://wv3.cuevana3.eu` | Healthy |
| `animeflv_api` | Anime | 1 (Máxima) | `https://www3.animeflv.net` | Healthy |
| Fuentes Legadas | Películas / Anime / Series | 3 (Baja / Fallback) | Varios | Healthy / Degraded |
