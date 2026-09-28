import asyncio
import httpx
import json
import re
import unicodedata
from datetime import datetime
from pathlib import Path

# Detección de soporte HTTP/2
try:
    import h2
    HAS_HTTP2 = True
except ImportError:
    HAS_HTTP2 = False

# 1. Cargar configuración
def load_config():
    script_dir = Path(__file__).parent.resolve()
    cfg_file = script_dir / 'sources.json'
    if not cfg_file.exists():
        cfg_file = Path('sources.json')
    with open(cfg_file, 'r', encoding='utf-8') as f:
        return json.load(f)

# 2. Descargar todas las listas en paralelo
async def download_all_sources(sources, client):
    async def fetch(source):
        try:
            print(f"   Descargando {source['name']}...", flush=True)
            response = await client.get(source['url'], timeout=15)
            if response.status_code == 200:
                return (source, response.text)
            else:
                print(f"   [!] Error HTTP {response.status_code} en {source['name']}", flush=True)
                return (source, "")
        except Exception as e:
            print(f"   [!] Falló la conexión a {source['name']}: {str(e)}", flush=True)
            return (source, "")
            
    tasks = [fetch(src) for src in sources]
    return await asyncio.gather(*tasks)

# 3. Parser de M3U con extracción de país e idioma
def parse_m3u(content, source):
    channels = []
    lines = content.split('\n')
    current_channel = None
    
    cat_country_map = {
        'colombia': 'CO',
        'espana': 'ES',
        'mexico': 'MX',
        'argentina': 'AR',
        'chile': 'CL',
        'peru': 'PE',
        'venezuela': 'VE',
    }
    
    for line in lines:
        line = line.strip()
        if line.startswith('#EXTINF:'):
            current_channel = {
                'source': source['name'],
                'priority': source['priority'],
                'category': source['category']
            }
            
            # Extraer tvg-id
            tvg_id_match = re.search(r'tvg-id="([^"]+)"', line)
            current_channel['tvg_id'] = tvg_id_match.group(1).strip() if tvg_id_match else None
            
            # Extraer tvg-country
            tvg_country_match = re.search(r'tvg-country="([^"]+)"', line)
            if tvg_country_match:
                current_channel['country'] = tvg_country_match.group(1).strip().upper()
            else:
                current_channel['country'] = cat_country_map.get(source['category'], '')
            
            # Extraer tvg-language
            tvg_lang_match = re.search(r'tvg-language="([^"]+)"', line)
            if tvg_lang_match:
                current_channel['language'] = tvg_lang_match.group(1).strip().lower()
            else:
                current_channel['language'] = 'spa' if current_channel['country'] in ['CO', 'ES', 'MX', 'AR', 'CL', 'PE', 'VE'] else ''
            
            # Extraer tvg-logo
            tvg_logo_match = re.search(r'tvg-logo="([^"]+)"', line)
            current_channel['logo'] = tvg_logo_match.group(1).strip() if tvg_logo_match else ""
            
            # Extraer group-title
            group_match = re.search(r'group-title="([^"]+)"', line)
            current_channel['group'] = group_match.group(1).strip() if group_match else source['category']
            
            # Extraer nombre
            name_parts = line.split(',')
            if len(name_parts) > 1:
                current_channel['name'] = name_parts[-1].strip()
            else:
                current_channel['name'] = "Desconocido"
                
        elif line and not line.startswith('#') and current_channel is not None:
            if line.startswith('http'):
                current_channel['url'] = line
                channels.append(current_channel)
            current_channel = None
            
    return channels

# 4. Clasificación de Prioridad
def clasificar_canal(channel):
    """
    Devuelve la prioridad del canal (1 = máxima, 4 = descartable).
    """
    name = channel.get('name', '').lower()
    group = channel.get('group', '').lower()
    country = channel.get('country', '').upper()
    language = channel.get('language', '').lower()
    
    # PRIORIDAD 1: Deportes (cualquier país)
    keywords_deportes = [
        'sport', 'deport', 'futbol', 'fútbol', 'soccer', 
        'espn', 'fox sport', 'directv sport', 'movistar deport',
        'dazn', 'gol tv', 'teledeporte', 'tdp', 'beinsport',
        'eurosport', 'sky sport', 'nba', 'nfl', 'mlb', 'ufc',
        'gol', 'win sports', 'tyc sports', 'clarosports'
    ]
    if any(kw in group or kw in name for kw in keywords_deportes):
        return 1
    
    # PRIORIDAD 1: España (cualquier categoría)
    if country == 'ES':
        return 1
    
    # PRIORIDAD 2: LATAM principal (CO, MX, AR)
    if country in ['CO', 'MX', 'AR']:
        return 2
    
    # PRIORIDAD 3: Resto LATAM (CL, PE, VE, EC, UY, BO, PY)
    if country in ['CL', 'PE', 'VE', 'EC', 'UY', 'BO', 'PY']:
        return 3
    
    # PRIORIDAD 3: Categorías útiles en español
    if language in ['spa', 'es'] and any(cat in group for cat in ['news', 'noticias', 'kids', 'infantil', 'movie', 'pelicula', 'peliculas']):
        return 3
    
    # PRIORIDAD 4: Descartable
    return 4

def es_canal_descartable(channel):
    name = channel.get('name', '').lower()
    descartables = ['test', 'backup', 'offline', '[not 24/7]', 'not 24/7']
    return any(d in name for d in descartables)

# 5. Normalización y Deduplicación
def normalize_name(name):
    name = unicodedata.normalize('NFKD', name).encode('ASCII', 'ignore').decode('utf-8')
    name = re.sub(r'(?i)\b(hd|fhd|sd|1080p|720p|4k|tv|en vivo|online)\b', '', name)
    name = re.sub(r'[^a-z0-9]', '', name.lower())
    return name

def deduplicate(channels, config_out):
    grouped = {}
    for ch in channels:
        tvg_id = (ch.get('tvg_id') or '').strip().lower()
        norm_name = normalize_name(ch.get('name', ''))
        
        if tvg_id:
            key = f"tvg:{tvg_id}"
        elif norm_name:
            key = f"name:{norm_name}"
        else:
            key = f"url:{ch.get('url', '')}"
            
        if key not in grouped:
            grouped[key] = []
        grouped[key].append(ch)
        
    unique = []
    for key, group in grouped.items():
        def sort_key(x):
            prio_contenido = clasificar_canal(x)
            prio_fuente = x.get('priority', 99)
            hd_pref = 0 if (config_out.get('keep_hd_first', True) and re.search(r'(?i)(HD|FHD|1080p)', x.get('name', ''))) else 1
            return (prio_contenido, prio_fuente, hd_pref)
            
        group.sort(key=sort_key)
        unique.append(group[0])
        
    return unique

# 6. Verificación con Timeout Estricto
async def _check_single(channel, client, timeout_val):
    url = channel['url']
    h_timeout = httpx.Timeout(timeout_val, connect=timeout_val, read=timeout_val, write=timeout_val, pool=timeout_val)
    
    # 1. Intentar HEAD (rápido)
    try:
        response = await client.head(url, timeout=h_timeout, follow_redirects=True)
        if response.status_code < 400 or response.status_code in (401, 403):
            channel['is_valid'] = True
            return channel
    except Exception:
        pass

    # 2. Fallback a GET byte-range
    try:
        headers = {'Range': 'bytes=0-512'}
        response = await client.get(url, headers=headers, timeout=h_timeout, follow_redirects=True)
        if response.status_code < 400 or response.status_code in (401, 403):
            channel['is_valid'] = True
            return channel
    except Exception:
        pass

    channel['is_valid'] = False
    return channel

async def verify_channel(channel, client, timeout_sec, semaphore, progress):
    async with semaphore:
        channel['is_valid'] = False
        try:
            # Forzar corte con asyncio.wait_for para evitar cuelgues por sockets infinitos
            await asyncio.wait_for(_check_single(channel, client, timeout_sec), timeout=timeout_sec + 1.5)
        except Exception:
            channel['is_valid'] = False
        finally:
            progress[0] += 1
            if channel.get('is_valid', False):
                progress[2] += 1
            if progress[0] % 100 == 0 or progress[0] == progress[1]:
                print(f"   [{progress[0]}/{progress[1]}] verificados ({progress[2]} válidos)...", flush=True)
                
        return channel

async def verify_all_channels(channels, config):
    timeout_sec = config.get('timeout_seconds', 5)
    concurrent = config.get('concurrent_checks', 150)
    user_agent = config.get('user_agent', 'Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36')
    
    semaphore = asyncio.Semaphore(concurrent)
    progress = [0, len(channels), 0]
    
    headers = {
        'User-Agent': user_agent,
        'Accept': '*/*',
    }
    limits = httpx.Limits(max_connections=200, max_keepalive_connections=100)
    
    client_kwargs = {
        'verify': False,
        'headers': headers,
        'limits': limits,
    }
    if HAS_HTTP2:
        client_kwargs['http2'] = True
        
    async with httpx.AsyncClient(**client_kwargs) as client:
        tasks = [verify_channel(ch, client, timeout_sec, semaphore, progress) for ch in channels]
        return await asyncio.gather(*tasks)

# 7. Ordenar por prioridad
def ordenar_por_prioridad(channels):
    """
    Ordena los canales por prioridad (1 primero, 4 último) y dentro de cada
    grupo por nombre.
    """
    return sorted(channels, key=lambda c: (clasificar_canal(c), c.get('name', '').lower()))

# 8. Generar M3U maestro
def generate_m3u(channels, output_path):
    with open(output_path, 'w', encoding='utf-8') as f:
        f.write('#EXTM3U x-tvg-url="https://iptv-org.github.io/epg/guides/es/guia.tv.epg.xml"\n')
        
        for ch in channels:
            extinf = '#EXTINF:-1'
            if ch.get('tvg_id'):
                extinf += f' tvg-id="{ch["tvg_id"]}"'
            if ch.get('country'):
                extinf += f' tvg-country="{ch["country"]}"'
            if ch.get('language'):
                extinf += f' tvg-language="{ch["language"]}"'
            if ch.get('logo'):
                extinf += f' tvg-logo="{ch["logo"]}"'
            extinf += f' group-title="{ch["group"].capitalize()}",{ch["name"]}\n'
            f.write(extinf)
            f.write(f'{ch["url"]}\n')

# 9. Main
async def main():
    config = load_config()
    
    client_kwargs = {'verify': False}
    if HAS_HTTP2:
        client_kwargs['http2'] = True
        
    async with httpx.AsyncClient(**client_kwargs) as client:
        print("[1/5] Descargando listas curadas...", flush=True)
        raw_lists = await download_all_sources(config['sources'], client)
        
        print("[2/5] Parseando y pre-filtrando canales...", flush=True)
        all_channels = []
        raw_counts = {}
        for source, content in raw_lists:
            if content:
                parsed = parse_m3u(content, source)
                raw_counts[source['name']] = len(parsed)
                all_channels.extend(parsed)
            else:
                raw_counts[source['name']] = 0
        print(f"   Total crudos descargados: {len(all_channels)} canales", flush=True)
        
        # Filtrar canales no útiles por nombre
        utiles = [c for c in all_channels if not es_canal_descartable(c)]
        descartados_nombre = len(all_channels) - len(utiles)
        if descartados_nombre > 0:
            print(f"   Descartados por nombre (test, offline, not 24/7): {descartados_nombre}", flush=True)
            
        # Filtrar canales por clasificación (Conservar Prioridad 1, 2 y 3)
        canales_clasificados = [(c, clasificar_canal(c)) for c in utiles]
        canales_filtrados = [c for c, prio in canales_clasificados if prio <= 3]
        descartados_prio = len(utiles) - len(canales_filtrados)
        print(f"   Descartados por país/categoría (Prioridad 4): {descartados_prio}", flush=True)
        print(f"   Canales retenidos para verificación: {len(canales_filtrados)}", flush=True)
        
        print("[3/5] Deduplicando...", flush=True)
        unique_channels = deduplicate(canales_filtrados, config.get('output', {}))
        print(f"   Total canales únicos a verificar: {len(unique_channels)}", flush=True)
        
        # Desglose de canales únicos por prioridad
        prio_counts_pre = {1: 0, 2: 0, 3: 0}
        for c in unique_channels:
            p = clasificar_canal(c)
            prio_counts_pre[p] = prio_counts_pre.get(p, 0) + 1
        print(f"   - Prioridad 1 (Deportes y España): {prio_counts_pre[1]}", flush=True)
        print(f"   - Prioridad 2 (LATAM Principal CO/MX/AR): {prio_counts_pre[2]}", flush=True)
        print(f"   - Prioridad 3 (Resto LATAM y Español temático): {prio_counts_pre[3]}", flush=True)
        
        timeout_sec = config.get('verification', {}).get('timeout_seconds', 5)
        print(f"[4/5] Verificando canales activos (timeout {timeout_sec}s, 150 concurrentes)...", flush=True)
        verified = await verify_all_channels(unique_channels, config.get('verification', {}))
        valid_channels = [c for c in verified if c['is_valid']]
        print(f"   Total canales verificados y activos: {len(valid_channels)}", flush=True)
        
        # Ordenar por prioridad garantizando Deportes y España al principio
        valid_channels = ordenar_por_prioridad(valid_channels)
        
        # Limitar total solo si es excesivo (> 1200) sin tocar prioridad 1
        MAX_CANALES = 1200
        if len(valid_channels) > MAX_CANALES:
            prioridad_1 = [c for c in valid_channels if clasificar_canal(c) == 1]
            resto = [c for c in valid_channels if clasificar_canal(c) != 1]
            canales_finales = prioridad_1 + resto[:MAX_CANALES - len(prioridad_1)]
            print(f"   [!] Ajustando límite a {MAX_CANALES} canales (Prioridad 1 conservada al 100%: {len(prioridad_1)})", flush=True)
            valid_channels = canales_finales
            
        print("[5/5] Generando M3U maestro ordenado por prioridad...", flush=True)
        script_dir = Path(__file__).parent.resolve()
        output_dir = script_dir / 'output'
        output_dir.mkdir(exist_ok=True)
        output_path = output_dir / 'filmotic_playlist.m3u'
        generate_m3u(valid_channels, output_path)
        
        # Guardar también en docs/ si existe
        docs_path = script_dir.parent / 'docs' / 'filmotic_playlist.m3u'
        if docs_path.parent.exists():
            generate_m3u(valid_channels, docs_path)
        
        print(f"\n✅ Listo. Archivo generado en: {output_path}", flush=True)
        print(f"   Canales finales en playlist: {len(valid_channels)}", flush=True)
        print(f"   Tamaño: {output_path.stat().st_size / 1024:.1f} KB", flush=True)
        print(f"   Fecha: {datetime.now().isoformat()}", flush=True)
        
        # Reporte de resultados
        print("\n" + "="*55, flush=True)
        print("📊 REPORTE DE RESULTADOS IPTV AGGREGATOR", flush=True)
        print("="*55, flush=True)
        prio_counts_post = {1: 0, 2: 0, 3: 0}
        deportes_count = 0
        espana_count = 0
        for c in valid_channels:
            p = clasificar_canal(c)
            prio_counts_post[p] = prio_counts_post.get(p, 0) + 1
            name_lower = c.get('name', '').lower()
            group_lower = c.get('group', '').lower()
            if any(kw in group_lower or kw in name_lower for kw in ['sport', 'deport', 'futbol', 'soccer', 'espn', 'fox', 'directv', 'movistar', 'dazn', 'gol', 'teledeporte', 'tdp']):
                deportes_count += 1
            if c.get('country') == 'ES':
                espana_count += 1

        print(f"Canales totales en M3U: {len(valid_channels)}", flush=True)
        print(f" - Prioridad 1 (Deportes y España): {prio_counts_post[1]}", flush=True)
        print(f"   * Total deportivos identificados: {deportes_count}", flush=True)
        print(f"   * Total canales de España: {espana_count}", flush=True)
        print(f" - Prioridad 2 (LATAM Principal CO/MX/AR): {prio_counts_post[2]}", flush=True)
        print(f" - Prioridad 3 (Resto LATAM y Español): {prio_counts_post[3]}", flush=True)
        
        print("\n📁 Canales válidos por categoría:", flush=True)
        categories = {}
        for c in valid_channels:
            cat = c.get('group', 'General').capitalize()
            categories[cat] = categories.get(cat, 0) + 1
        for cat, count in sorted(categories.items(), key=lambda x: x[1], reverse=True)[:15]:
            print(f"   - {cat}: {count}", flush=True)
            
        print("\n🏆 Top fuentes que más aportaron:", flush=True)
        source_contributions = {}
        for c in valid_channels:
            src = c.get('source', 'Desconocido')
            source_contributions[src] = source_contributions.get(src, 0) + 1
        for src, count in sorted(source_contributions.items(), key=lambda x: x[1], reverse=True):
            print(f"   - {src}: {count} canales", flush=True)
        print("="*55 + "\n", flush=True)

if __name__ == "__main__":
    asyncio.run(main())
