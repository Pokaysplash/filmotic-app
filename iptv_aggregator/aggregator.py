import asyncio
import httpx
import json
import re
import unicodedata
from datetime import datetime
from pathlib import Path

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
            print(f"   Descargando {source['name']}...")
            response = await client.get(source['url'], timeout=20)
            if response.status_code == 200:
                return (source, response.text)
            else:
                print(f"   [!] Error HTTP {response.status_code} en {source['name']}")
                return (source, "")
        except Exception as e:
            print(f"   [!] Falló la conexión a {source['name']}: {str(e)}")
            return (source, "")
            
    tasks = [fetch(src) for src in sources]
    return await asyncio.gather(*tasks)

# 3. Parser de M3U
def parse_m3u(content, source):
    channels = []
    lines = content.split('\n')
    current_channel = None
    
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

# 4. Normalización y Deduplicación
def normalize_name(name):
    # Lowercase, quitar tildes y palabras comunes
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
        # Ordenar por prioridad (menor número = más prioridad)
        group.sort(key=lambda x: x['priority'])
        if config_out.get('keep_hd_first', True):
            # Priorizar HD/FHD/1080p en el nombre si hay empate
            best_priority = group[0]['priority']
            best_priority_group = [x for x in group if x['priority'] == best_priority]
            best_priority_group.sort(key=lambda x: 0 if re.search(r'(?i)(HD|FHD|1080p)', x['name']) else 1)
            unique.append(best_priority_group[0])
        else:
            unique.append(group[0])
        
    return unique

# 5. Verificar canales en paralelo
async def verify_channel(channel, client, timeout, semaphore, progress):
    async with semaphore:
        channel['is_valid'] = False
        url = channel['url']
        try:
            # 1. Intentar HEAD (rápido)
            response = await client.head(url, timeout=timeout, follow_redirects=True)
            # Permitir HTTP 200-399 y 401/403 (streams válidos con tokens o headers)
            if response.status_code < 400 or response.status_code in (401, 403):
                channel['is_valid'] = True
            else:
                # 2. Fallback a GET byte-range
                headers = {'Range': 'bytes=0-1024'}
                response = await client.get(url, headers=headers, timeout=timeout, follow_redirects=True)
                if response.status_code < 400 or response.status_code in (401, 403):
                    channel['is_valid'] = True
        except Exception:
            # 3. Si HEAD falló por conexión o rechazo, intentar GET parcial
            try:
                headers = {'Range': 'bytes=0-1024'}
                response = await client.get(url, headers=headers, timeout=timeout, follow_redirects=True)
                if response.status_code < 400 or response.status_code in (401, 403):
                    channel['is_valid'] = True
            except Exception:
                pass
        
        progress[0] += 1
        if channel['is_valid']:
            progress[2] += 1
            
        if progress[0] % 100 == 0 or progress[0] == progress[1]:
            print(f"   [{progress[0]}/{progress[1]}] verificados ({progress[2]} válidos)...")
            
        return channel

async def verify_all_channels(channels, config):
    timeout = config.get('timeout_seconds', 10)
    concurrent = config.get('concurrent_checks', 60)
    user_agent = config.get('user_agent', 'Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36')
    
    semaphore = asyncio.Semaphore(concurrent)
    progress = [0, len(channels), 0]
    
    headers = {
        'User-Agent': user_agent,
        'Accept': '*/*',
    }
    limits = httpx.Limits(max_connections=concurrent * 2, max_keepalive_connections=concurrent)
    async with httpx.AsyncClient(verify=False, headers=headers, limits=limits) as client:
        tasks = [verify_channel(ch, client, timeout, semaphore, progress) for ch in channels]
        return await asyncio.gather(*tasks)

# 6. Generar M3U maestro
def generate_m3u(channels, output_path, config_out):
    if config_out.get('sort_by_category', True):
        channels.sort(key=lambda x: (x['category'], x['name']))
        
    with open(output_path, 'w', encoding='utf-8') as f:
        f.write('#EXTM3U x-tvg-url="https://iptv-org.github.io/epg/guides/es/guia.tv.epg.xml"\n')
        
        for ch in channels:
            extinf = '#EXTINF:-1'
            if ch.get('tvg_id'):
                extinf += f' tvg-id="{ch["tvg_id"]}"'
            if ch.get('logo'):
                extinf += f' tvg-logo="{ch["logo"]}"'
            extinf += f' group-title="{ch["category"].capitalize()}",{ch["name"]}\n'
            f.write(extinf)
            f.write(f'{ch["url"]}\n')

# 7. Main
async def main():
    config = load_config()
    
    async with httpx.AsyncClient(verify=False) as client:
        print("[1/5] Descargando listas...")
        raw_lists = await download_all_sources(config['sources'], client)
        
        print("[2/5] Parseando canales...")
        all_channels = []
        raw_counts = {}
        for source, content in raw_lists:
            if content:
                parsed = parse_m3u(content, source)
                raw_counts[source['name']] = len(parsed)
                all_channels.extend(parsed)
            else:
                raw_counts[source['name']] = 0
        print(f"   Total: {len(all_channels)} canales crudos")
        
        print("[3/5] Deduplicando...")
        unique_channels = deduplicate(all_channels, config['output'])
        print(f"   Total: {len(unique_channels)} canales únicos")
        
        print(f"[4/5] Verificando canales (timeout {config['verification'].get('timeout_seconds', 10)}s)...")
        verified = await verify_all_channels(unique_channels, config['verification'])
        valid = [c for c in verified if c['is_valid']]
        print(f"   Total: {len(valid)} canales verificados y activos")
        
        print("[5/5] Generando M3U maestro...")
        script_dir = Path(__file__).parent.resolve()
        output_dir = script_dir / 'output'
        output_dir.mkdir(exist_ok=True)
        output_path = output_dir / 'filmotic_playlist.m3u'
        generate_m3u(valid, output_path, config['output'])
        
        # Guardar también en docs/ de la raíz del repo si existe
        docs_path = script_dir.parent / 'docs' / 'filmotic_playlist.m3u'
        if docs_path.parent.exists():
            generate_m3u(valid, docs_path, config['output'])
        
        print(f"\n✅ Listo. Archivo generado en: {output_path}")
        print(f"   Tamaño: {output_path.stat().st_size / 1024:.1f} KB")
        print(f"   Fecha: {datetime.now().isoformat()}")
        
        # Reporte detallado de estadísticas
        print("\n" + "="*50)
        print("📊 REPORTE DE RESULTADOS IPTV AGGREGATOR")
        print("="*50)
        print(f"Canales crudos totales: {len(all_channels)}")
        print(f"Canales tras deduplicación: {len(unique_channels)}")
        print(f"Canales verificados y activos: {len(valid)}")
        
        print("\n📈 Canales crudos por fuente:")
        for src_name, count in raw_counts.items():
            print(f"   - {src_name}: {count}")
            
        print("\n🏆 Top 10 fuentes que más aportaron a la lista final:")
        source_contributions = {}
        for c in valid:
            src = c.get('source', 'Desconocido')
            source_contributions[src] = source_contributions.get(src, 0) + 1
        sorted_sources = sorted(source_contributions.items(), key=lambda x: x[1], reverse=True)[:10]
        for src, count in sorted_sources:
            print(f"   - {src}: {count} canales")

        print("\n📁 Canales válidos por categoría:")
        categories = {}
        for c in valid:
            cat = c.get('category', 'general').capitalize()
            categories[cat] = categories.get(cat, 0) + 1
        for cat, count in sorted(categories.items(), key=lambda x: x[1], reverse=True):
            print(f"   - {cat}: {count}")
        print("="*50 + "\n")

if __name__ == "__main__":
    asyncio.run(main())
