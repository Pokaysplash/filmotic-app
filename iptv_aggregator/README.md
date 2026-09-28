# Filmotic IPTV Aggregator

Un motor automatizado para descargar, pre-filtrar, verificar, deduplicar y agrupar múltiples listas M3U en una única lista maestra limpia (`filmotic_playlist.m3u`). Este agregador asegura que Filmotic ofrezca siempre canales verificados en un rango óptimo (600–1200 canales), priorizando al 100% las señales deportivas y de España.

## Características Principales

- **Priorización Deportiva y España (Prioridad 1)**: Nunca se descartan canales deportivos (fútbol, ESPN, Fox Sports, DAZN, Movistar Deportes, Eurosport, etc.) ni canales de España, ubicándolos al inicio del archivo M3U.
- **Pre-filtrado Inteligente**: Descarta nombres irrelevantes (`test`, `backup`, `offline`, `[not 24/7]`) y señales fuera del ámbito hispanohablante antes de verificar, reduciendo el tiempo de procesamiento drásticamente.
- **Verificación Asíncrona Ultrarrápida**: Peticiones HEAD concurrentes (150 tareas en paralelo) con fallback a GET parcial (`Range: bytes=0-512`) y timeout de 5s.
- **Límite Suave (Soft Cap)**: Si la lista de canales activos excede 1200, preserva todos los canales de Prioridad 1 y ajusta el resto para no saturar dispositivos como Android TV.
- **Actualización Automática**: GitHub Actions programado cada 24 horas (`0 6 * * *` UTC) con límite de tiempo de 15 minutos.

## Sistema de Clasificación de Prioridad

Cada canal se clasifica según su nombre, grupo, país (`tvg-country`) e idioma (`tvg-language`):

1. **Prioridad 1 (Máxima - Preservación 100%)**:
   - Todo canal deportivo de cualquier país (palabras clave: `sport`, `deport`, `futbol`, `soccer`, `espn`, `fox`, `directv`, `movistar`, `dazn`, `gol`, `teledeporte`, `tdp`, etc.).
   - Todo canal originario de España (`country: ES`).
2. **Prioridad 2 (LATAM Principal)**:
   - Canales nacionales y regionales de Colombia (`CO`), México (`MX`) y Argentina (`AR`).
3. **Prioridad 3 (Resto de LATAM y Español temático)**:
   - Canales de Chile (`CL`), Perú (`PE`), Venezuela (`VE`), Ecuador (`EC`), Uruguay (`UY`), Bolivia (`BO`) y Paraguay (`PY`).
   - Canales en español de categorías de interés: Noticias, Infantil, Películas y Documentales.
4. **Prioridad 4 (Descartable)**:
   - Canales de otras regiones, idiomas no latinos o sin coincidencia relevante (se descartan antes de verificar).

## Instalación y Ejecución Local

1. Instala las dependencias:
   ```bash
   pip install -r requirements.txt
   ```

2. Ejecuta el script:
   ```bash
   python aggregator.py
   ```

3. El archivo resultante se guardará en `output/filmotic_playlist.m3u` y en `../docs/filmotic_playlist.m3u`.

## Notas Legales

Filmotic y este agregador utilizan estrictamente listas IPTV **públicas y de libre acceso (open source)** como `iptv-org`. Este script **NO** aloja ni retransmite señales de video; funciona puramente como un filtro y validador de disponibilidad HTTP.
