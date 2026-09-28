# Filmotic IPTV Aggregator

Un motor automatizado para descargar, verificar, deduplicar y agrupar múltiples listas M3U en una única lista maestra limpia (`filmotic_playlist.m3u`). Este agregador asegura que Filmotic ofrezca siempre canales verificados (solo aquellos que respondan a peticiones HTTP en tiempo real) descartando canales caídos.

## Requisitos

- Python 3.9 o superior.

## Instalación local

1. Instala las dependencias:
   ```bash
   pip install -r requirements.txt
   ```

2. Ejecuta el script:
   ```bash
   python aggregator.py
   ```

3. El archivo resultante estará en `output/filmotic_playlist.m3u` (y si existe la carpeta `../docs/`, también se guardará allí para facilitar su publicación en GitHub Pages).

## Funcionamiento

El script funciona en 5 etapas rápidas:
1. **Descarga**: Obtiene todos los M3U declarados en `sources.json`.
2. **Parseo**: Extrae información vital (`tvg-id`, `tvg-logo`, grupos, nombre y URL) de la etiqueta `#EXTINF`.
3. **Deduplicación**: Agrupa canales similares por `tvg-id` o nombre normalizado, descartando duplicados priorizando según el orden `priority` en el `sources.json` y dando preferencia a calidades HD.
4. **Verificación Activa**: Realiza peticiones asíncronas (HTTP HEAD, si falla hace HTTP GET Byte-Range) a la URL de stream de cada canal. Los canales con `Timeout` (5s por defecto) o errores 404/500 son descartados y no ingresan al archivo final.
5. **Generación**: Crea el M3U maestro categorizado y limpio.

## Añadir nuevas listas

Abre `sources.json` y añade un bloque en la sección `"sources"`:
```json
{
  "name": "Nombre de tu lista",
  "url": "https://url.al.m3u",
  "priority": 1,
  "category": "Mi Categoria"
}
```
*Las listas con menor número en `priority` (1 es mejor que 2) sobreescribirán los canales con el mismo nombre de otras listas.*

## Notas legales

Filmotic y este agregador utilizan estrictamente listas IPTV **públicas y de libre acceso (open source)** como `iptv-org` y equivalentes comunitarios. Este script **NO** aloja, retransmite, guarda ni redistribuye el contenido de las señales de video; funciona puramente como un buscador asíncrono que valida si un enlace de terceros (URL) reporta estatus activo o no.
