import '../../data/scrapers/base/buscador.dart';
import '../services/guardados_bus.dart';

const Map<String, String> _kDiacritics = {
  'á': 'a', 'à': 'a', 'ä': 'a', 'â': 'a', 'ã': 'a', 'å': 'a',
  'é': 'e', 'è': 'e', 'ë': 'e', 'ê': 'e',
  'í': 'i', 'ì': 'i', 'ï': 'i', 'î': 'i',
  'ó': 'o', 'ò': 'o', 'ö': 'o', 'ô': 'o', 'õ': 'o',
  'ú': 'u', 'ù': 'u', 'ü': 'u', 'û': 'u',
  'ñ': 'n', 'ç': 'c',
};

/// Normaliza un título para comparar resultados de distintas fuentes:
/// minúsculas, sin acentos, sin año entre paréntesis ni sufijos típicos de
/// los sitios ("online", "latino"...), y solo letras/números.
String normalizeSearchTitle(String raw) {
  var t = raw.toLowerCase().trim();
  final buf = StringBuffer();
  for (final ch in t.split('')) {
    buf.write(_kDiacritics[ch] ?? ch);
  }
  t = buf.toString();
  t = t.replaceAll(RegExp(r'[\(\[]\s*(19|20)\d{2}\s*[\)\]]'), ' ');
  t = t.replaceAll(RegExp(r'\b(ver|online|latino|castellano|sub espanol|hd)\b'), ' ');
  t = t.replaceAll(RegExp(r'\s+(19|20)\d{2}\s*$'), ' ');
  t = t.replaceAll(RegExp(r'^(el|la|los|las|the)\s+'), '');
  return t.replaceAll(RegExp(r'[^a-z0-9]'), '');
}

String _fedType(String tipo) {
  final t = tipo.toLowerCase();
  return (t == 'anime' || t == 'tv' || t == 'serie' || t == 'novela') ? 'tv' : 'movie';
}

/// Une los resultados de TMDB con los de las fuentes (scrapers) mostrando
/// cada título una sola vez:
/// - Si una fuente encuentra un título que TMDB ya tiene, se agrega como
///   fuente extra del resultado TMDB (que abre la ficha y elige el mejor
///   servidor de todas las fuentes al reproducir).
/// - Si varias fuentes tienen el mismo título fuera de TMDB, se muestra una
///   sola tarjeta que abre la fuente más saludable (la primera, porque
///   `buscarEnFuentes` ya las ordena por salud).
List<Map<String, dynamic>> mergeSearchResults({
  required List<Map<String, dynamic>> tmdbItems,
  required List<BuscadorItem> fedItems,
}) {
  final byKey = <String, Map<String, dynamic>>{};
  final tmdbByTitle = <String, List<String>>{};

  for (final raw in tmdbItems) {
    final map = Map<String, dynamic>.from(raw);
    final title = (map['title'] ?? map['name'] ?? map['titulo'] ?? '').toString();
    final norm = normalizeSearchTitle(title);
    final type = canonicalMediaType(
      map['media_type'] ?? (map['name'] != null ? 'tv' : 'movie'),
    );
    final key = '${type}_$norm';
    if (norm.isEmpty || byKey.containsKey(key)) continue;
    map['fuentes_agrupadas'] = <Map<String, String>>[];
    byKey[key] = map;
    tmdbByTitle.putIfAbsent(norm, () => []).add(key);
  }

  void addSources(Map<String, dynamic> target, BuscadorItem f) {
    final fuentes = List<Map<String, String>>.from(target['fuentes_agrupadas'] ?? const []);
    final incoming = f.fuentesAgrupadas ?? [{'sitio': f.sitio, 'url': f.url}];
    for (final s in incoming) {
      if (!fuentes.any((e) => e['sitio'] == s['sitio'])) fuentes.add(s);
    }
    target['fuentes_agrupadas'] = fuentes;
  }

  for (final f in fedItems) {
    final norm = normalizeSearchTitle(f.titulo);
    if (norm.isEmpty) continue;
    final type = _fedType(f.tipo);
    final key = '${type}_$norm';

    // 1. Mismo título y tipo que un resultado ya mostrado.
    var existingKey = byKey.containsKey(key) ? key : null;
    // 2. Mismo título en TMDB con otro tipo, si es inequívoco.
    if (existingKey == null) {
      final candidates = tmdbByTitle[norm];
      if (candidates != null && candidates.length == 1) existingKey = candidates.first;
    }

    if (existingKey != null) {
      final existing = byKey[existingKey]!;
      addSources(existing, f);
      final hasTmdb = (existing['tmdb_id'] is int && (existing['tmdb_id'] as int) > 0);
      if (!hasTmdb && f.tmdbId != null && f.tmdbId! > 0) {
        // Ahora que conocemos el TMDB id, abrir la ficha (mejor servidor).
        existing['tmdb_id'] = f.tmdbId;
        existing['id'] = f.tmdbId;
        existing.remove('sitio');
        existing.remove('url');
      }
      if ((existing['poster_path'] ?? '').toString().isEmpty && f.imagen.isNotEmpty) {
        existing['poster_path'] = f.imagen;
      }
      continue;
    }

    final hasTmdb = f.tmdbId != null && f.tmdbId! > 0;
    byKey[key] = {
      'id': f.tmdbId ?? 0,
      'tmdb_id': f.tmdbId,
      'title': f.titulo,
      'name': f.titulo,
      'media_type': type,
      'poster_path': f.imagen,
      'vote_average': f.rating ?? 0.0,
      'year': f.anio != null ? '${f.anio}' : '',
      'release_date': f.anio != null ? '${f.anio}-01-01' : null,
      'fuentes_agrupadas': f.fuentesAgrupadas ?? [{'sitio': f.sitio, 'url': f.url}],
      // Con TMDB id se abre la ficha y se elige el mejor servidor de todas las
      // fuentes; sin él, se abre directamente la fuente más saludable.
      if (!hasTmdb) 'sitio': f.sitio,
      if (!hasTmdb) 'url': f.url,
    };
  }

  return byKey.values.toList();
}
