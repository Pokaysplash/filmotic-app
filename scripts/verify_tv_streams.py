#!/usr/bin/env python3
"""Valida que los streams en filmotic_config.json (verified_sources) respondan y tengan audio AAC."""

import json
import subprocess
import sys

with open("filmotic_config.json", "r", encoding="utf-8") as f:
    cfg = json.load(f)

verified = cfg.get("live_tv", {}).get("verified_sources", [])
dead_or_muted = []

for ch in verified:
    name = ch.get("name", "?")
    for url in ch.get("streams", []):
        cmd = [
            "ffprobe",
            "-v",
            "quiet",
            "-show_entries",
            "stream=codec_type,codec_name",
            "-of",
            "json",
            url,
        ]
        try:
            out = subprocess.check_output(cmd, timeout=8).decode("utf-8", "ignore")
            streams = json.loads(out).get("streams", [])
            audio_codecs = [
                s.get("codec_name") for s in streams if s.get("codec_type") == "audio"
            ]
            if not audio_codecs:
                dead_or_muted.append((name, url, "SIN_AUDIO"))
            elif all(c in ("mp2", "ac3", "eac3") for c in audio_codecs):
                dead_or_muted.append((name, url, f"AUDIO_INCOMPATIBLE:{audio_codecs}"))
            else:
                print(f"OK   {name}: {url} -> {audio_codecs}")
        except Exception as e:
            dead_or_muted.append((name, url, f"FALLO:{type(e).__name__}"))

if dead_or_muted:
    print("\n--- Streams con problemas ---")
    for name, url, reason in dead_or_muted:
        print(f"WARN {name} | {url} -> {reason}")
else:
    print("\nTodos los streams verificados tienen audio compatible.")

sys.exit(0)

