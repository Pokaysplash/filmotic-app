#!/usr/bin/env python3
import json
import urllib.request
import urllib.parse
import subprocess
import os
import re

SERVER = "http://myultratv.com:8080"
USER = "Marchant-8"
PASS = "Marisol-3"

print(f"[*] Conectando a {SERVER} con credenciales activas ({USER})...")

def fetch_json(url):
    req = urllib.request.Request(url, headers={'User-Agent': 'IPTVSmarters/1.0'})
    with urllib.request.urlopen(req, timeout=25) as response:
        return json.loads(response.read().decode('utf-8', errors='ignore'))

# 1. Obtener categorías
cat_url = f"{SERVER}/player_api.php?username={USER}&password={PASS}&action=get_live_categories"
categories = fetch_json(cat_url)
print(f"[*] Categorías encontradas: {len(categories)}")

EXCLUDE_WORDS = [
    "RUSIA", "ARABE", "UCRANIA", "FILIPINAS", "COREA", "ALEMANIA", "FRANCIA", 
    "MALASIA", "UK", "AFGHANISTAN", "ALBANIA", "ABU DABI", "TURQUIA", "ALGERIA", 
    "ANGOLA", "ANDORRA", "ROMANIA", "CANADA", "INDONESIA", "BRUNEI", "INDIA", 
    "TAILANDIA", "ITALIA", "POLONIA", "CROACIA", "ASIA", "PORTUGAL", "SUECIA", 
    "BELGICA", "ESLOVAQUIA", "MARRUECOS", "AUSTRALIA", "ARMENIA", "XXX", "ADULTOS"
]

target_category_ids = set()
cat_map = {}

for cat in categories:
    cid = str(cat.get("category_id"))
    cname = cat.get("category_name", "").strip()
    upper = cname.upper()
    
    if any(ex in upper for ex in EXCLUDE_WORDS):
        continue
    
    clean_group = re.sub(r'^[→\s\-\•]+|[←\s\-\•]+$', '', cname).strip()
    if clean_group:
        target_category_ids.add(cid)
        cat_map[cid] = clean_group

print(f"[*] Categorías hispanas/deportes seleccionadas: {len(target_category_ids)}")

# 2. Obtener streams en vivo
streams_url = f"{SERVER}/player_api.php?username={USER}&password={PASS}&action=get_live_streams"
print("[*] Descargando listado completo de streams...")
all_streams = fetch_json(streams_url)
print(f"[*] Total streams en panel: {len(all_streams)}")

# Mapeo de país según categoría y nombre
def detect_country(group, name):
    g = group.upper()
    n = name.upper()
    if "COLOMBIA" in g or n.startswith("COL•") or "COLOMBIA" in n: return "CO"
    if "MÉXICO" in g or "MEXICO" in g or n.startswith("MEX•") or "MEXICO" in n: return "MX"
    if "ARGENTINA" in g or n.startswith("ARG•") or "ARGENTINA" in n: return "AR"
    if "CHILE" in g or n.startswith("CL•") or n.startswith("CHI•") or "CHILE" in n: return "CL"
    if "PERÚ" in g or "PERU" in g or n.startswith("PE•") or n.startswith("PER•") or "PERU" in n: return "PE"
    if "ESPAÑA" in g or "ESPANA" in g or "DAZN" in g or n.startswith("ESP•") or "ESPAÑA" in n: return "ES"
    if "URUGUAY" in g or n.startswith("UY•"): return "UY"
    if "PARAGUAY" in g or n.startswith("PY•"): return "PY"
    if "BOLIVIA" in g or n.startswith("BO•"): return "BO"
    if "ECUADOR" in g or n.startswith("EC•"): return "EC"
    if "VENEZUELA" in g or n.startswith("VE•"): return "VE"
    if "GUATEMALA" in g: return "GT"
    if "PUERTO RICO" in g: return "PR"
    if "REPÚBLICA DOMINICANA" in g or "DOMINICANA" in g: return "DO"
    if "USA" in g or "TELEMUNDO" in g or "UNIVISION" in g: return "US"
    return "LATAM"

def normalize_group(raw_group):
    g = raw_group.upper()
    if any(k in g for k in ["DEPORTE", "SPORT", "FUTBOL", "FÚTBOL", "NBA", "TENIS", "PPV", "LIGA", "DAZN", "DISNEY+"]):
        return "Deportes"
    if any(k in g for k in ["CINE", "SERIES", "MOVIE", "GOLDEN", "UNIVERSAL", "STARZ"]):
        return "Cine & Series"
    if any(k in g for k in ["INFANTIL", "KIDS", "FAMILIA"]):
        return "Infantiles"
    if any(k in g for k in ["NOTICIA", "NEWS"]):
        return "Noticias"
    if any(k in g for k in ["CULTURA", "DOCUMENTAL", "HISTORIA"]):
        return "Cultura"
    if any(k in g for k in ["MÚSICA", "MUSICA"]):
        return "Música"
    if any(k in g for k in ["COLOMBIA"]):
        return "Colombia"
    if any(k in g for k in ["MÉXICO", "MEXICO"]):
        return "México"
    if any(k in g for k in ["ARGENTINA"]):
        return "Argentina"
    if any(k in g for k in ["CHILE"]):
        return "Chile"
    if any(k in g for k in ["PERÚ", "PERU"]):
        return "Perú"
    if any(k in g for k in ["ESPAÑA", "TDT"]):
        return "España"
    return raw_group

xtream_channels = []

for s in all_streams:
    cid = str(s.get("category_id"))
    if cid not in target_category_ids:
        continue
    
    sid = s.get("stream_id")
    name = (s.get("name") or "").strip()
    icon = (s.get("stream_icon") or "").strip()
    
    if not sid or not name:
        continue
    
    raw_group = cat_map.get(cid, "General")
    norm_group = normalize_group(raw_group)
    country = detect_country(raw_group, name)
    stream_url = f"{SERVER}/live/{USER}/{PASS}/{sid}.m3u8"
    
    xtream_channels.append({
        "name": name,
        "stream_url": stream_url,
        "logo": icon,
        "group": norm_group,
        "country": country,
    })

print(f"[*] Canales en español seleccionados: {len(xtream_channels)}")

# Obtener canales de respaldo originales de Git HEAD
backup_lines = []
try:
    git_head = subprocess.check_output(["git", "show", "HEAD:docs/filmotic_playlist.m3u"]).decode('utf-8', errors='ignore')
    for line in git_head.splitlines(keepends=True):
        if not line.startswith("#EXTM3U"):
            backup_lines.append(line)
    print(f"[*] Canales originales de respaldo extraídos de Git HEAD ({len(backup_lines)} líneas).")
except Exception as ge:
    print(f"[!] Aviso al leer Git HEAD: {ge}")

output_path = "docs/filmotic_playlist.m3u"
with open(output_path, "w", encoding="utf-8") as out:
    out.write('#EXTM3U x-tvg-url="https://iptv-org.github.io/epg/guides/es/guia.tv.epg.xml"\n')
    
    # Canales de prioridad 1 (Xtream Codes del post)
    for ch in xtream_channels:
        name = ch["name"].replace('"', '')
        logo = ch["logo"]
        grp = ch["group"]
        country = ch["country"]
        url = ch["stream_url"]
        
        logo_attr = f' tvg-logo="{logo}"' if logo else ''
        out.write(f'#EXTINF:-1 tvg-name="{name}" tvg-country="{country}" tvg-language="spa"{logo_attr} group-title="{grp}",{name}\n')
        out.write(f'{url}\n')

    # Canales de respaldo (Filmotic Backup)
    out.write('\n# --- CANALES DE RESPALDO (FILMOTIC BACKUP) ---\n')
    for line in backup_lines:
        out.write(line)

print(f"[+] Lista generada exitosamente en {output_path} ({len(xtream_channels)} canales principales + respaldos).")
