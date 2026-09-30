import 'package:flutter/material.dart';
import '../../data/datasources/remote/tmdb/tmdb_content.dart';
import '../../supabase/guardados_service.dart';

/// Parsea de forma segura cualquier representación de TMDB ID a int canónico.
int? parseCanonicalTmdbId(dynamic raw) {
  if (raw == null) return null;
  if (raw is int && raw > 0) return raw;
  if (raw is num && raw > 0) return raw.toInt();
  if (raw is String) {
    final trimmed = raw.trim();
    final parsed = int.tryParse(trimmed);
    if (parsed != null && parsed > 0) return parsed;
  }
  return null;
}

/// Normaliza el tipo multimedia a 'tv' o 'movie' para llamadas TMDB.
String canonicalMediaType(dynamic raw) {
  final str = raw?.toString().toLowerCase().trim() ?? '';
  if (str == 'tv' || str == 'serie' || str == 'series') return 'tv';
  return 'movie';
}

/// Normaliza el tipo a 'serie' o 'pelicula' para almacenamiento local.
String canonicalTipo(dynamic raw) {
  final str = raw?.toString().toLowerCase().trim() ?? '';
  if (str == 'tv' || str == 'serie' || str == 'series') return 'serie';
  return 'pelicula';
}

/// Compara dos títulos limpiando signos y acentos para evitar falsos negativos.
bool titlesMatch(String? a, String? b) {
  if (a == null || b == null) return false;
  String clean(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9áéíóúüñ]'), '')
      .trim();
  final cleanA = clean(a);
  final cleanB = clean(b);
  if (cleanA.isEmpty || cleanB.isEmpty) return false;
  if (cleanA == cleanB) return true;
  if (cleanA.contains(cleanB) || cleanB.contains(cleanA)) return true;
  return false;
}

/// Modelo canónico para representar un contenido reproducible o almacenable en favoritos.
class Contenido {
  final String id;
  final String titulo;
  final String? poster;
  final String? backdrop;
  final String tipo; // 'pelicula' | 'serie'
  final int? year;
  final int? tmdbId;
  final String? imdbId;
  final double? voteAverage;
  final DateTime timestamp;
  final bool isUnrecoverable;

  const Contenido({
    required this.id,
    required this.titulo,
    this.poster,
    this.backdrop,
    required this.tipo,
    this.year,
    this.tmdbId,
    this.imdbId,
    this.voteAverage,
    required this.timestamp,
    this.isUnrecoverable = false,
  });

  factory Contenido.fromMap(Map<String, dynamic> map) {
    final tmdb = parseCanonicalTmdbId(map['tmdb_id']) ??
        parseCanonicalTmdbId(map['idtmdb']) ??
        parseCanonicalTmdbId(map['idcontenido']) ??
        parseCanonicalTmdbId(map['id']);

    final rawTitulo = (map['titulo'] ??
            map['title'] ??
            map['name'] ??
            map['titulo_contenido'] ??
            'Sin título')
        .toString()
        .trim();
    final tipo = canonicalTipo(map['tipo'] ?? map['type'] ?? map['media_type'] ?? map['mediaType']);

    final rawYear = map['año'] ?? map['year'] ?? map['release_date'] ?? map['first_air_date'];
    int? parsedYear;
    if (rawYear != null) {
      if (rawYear is int) {
        parsedYear = rawYear;
      } else {
        final match = RegExp(r'\b(19\d\d|20\d\d)\b').firstMatch(rawYear.toString());
        if (match != null) {
          parsedYear = int.tryParse(match.group(1)!);
        }
      }
    }

    final rawVote = map['vote_average'] ?? map['voteAverage'];
    final vote = rawVote != null ? double.tryParse(rawVote.toString()) : null;

    final imdb = map['imdb_id']?.toString();
    final unrec = map['unrecoverable'] == true;

    DateTime ts;
    if (map['timestamp'] != null) {
      ts = DateTime.tryParse(map['timestamp'].toString()) ?? DateTime.now();
    } else {
      ts = DateTime.now();
    }

    final canonicalId = (tmdb != null && tmdb > 0)
        ? tmdb.toString()
        : (map['id']?.toString() ?? '');

    return Contenido(
      id: canonicalId,
      titulo: rawTitulo.isNotEmpty ? rawTitulo : 'Sin título',
      poster: (map['poster'] ?? map['poster_path'] ?? map['imagen'])?.toString(),
      backdrop: (map['backdrop'] ?? map['backdrop_path'])?.toString(),
      tipo: tipo,
      year: parsedYear,
      tmdbId: tmdb,
      imdbId: imdb,
      voteAverage: vote,
      timestamp: ts,
      isUnrecoverable: unrec,
    );
  }

  Map<String, dynamic> toMap() {
    final validTmdb = tmdbId ?? parseCanonicalTmdbId(id) ?? 0;
    return {
      'id': validTmdb > 0 ? validTmdb.toString() : id,
      'idcontenido': validTmdb,
      'contenido_id': validTmdb,
      'tmdb_id': validTmdb,
      'idtmdb': validTmdb,
      if (imdbId != null) 'imdb_id': imdbId,
      'titulo': titulo,
      'title': titulo,
      'name': titulo,
      'poster': poster,
      'poster_path': poster,
      'backdrop': backdrop,
      'backdrop_path': backdrop,
      'tipo': tipo,
      'type': canonicalMediaType(tipo),
      'media_type': canonicalMediaType(tipo),
      'año': year,
      'year': year,
      'vote_average': voteAverage,
      'timestamp': timestamp.toIso8601String(),
      'unrecoverable': isUnrecoverable,
      'metadatos_completos': titulo.isNotEmpty &&
          titulo != 'Sin título' &&
          poster != null &&
          poster!.isNotEmpty &&
          poster != 'null' &&
          validTmdb > 0,
    };
  }
}

/// Bus de eventos global para cambios en la lista de favoritos / guardados.
/// Notifica instantáneamente a listeners en móvil y Android TV.
class GuardadosBus {
  GuardadosBus._();

  static final ValueNotifier<int> version = ValueNotifier<int>(0);

  /// Incrementa la versión para notificar a todos los listeners activos.
  static void bump() {
    version.value++;
  }
}

/// Fachada unificada de favoritos para móvil y Android TV.
class GuardadosCache {
  GuardadosCache._();

  /// Obtiene todos los favoritos del perfil activo.
  static Future<List<Map<String, dynamic>>> getAll() async {
    return GuardadosService.getAll();
  }

  /// Verifica si un contenido está guardado por su id.
  static Future<bool> isSaved(int idcontenido) async {
    return GuardadosService.isSaved(idcontenido);
  }

  /// Alterna el estado de guardado (guarda si no está, elimina si está).
  /// Acepta un [Contenido] o un [Map<String, dynamic>].
  static Future<bool> toggle(dynamic item) async {
    final result = await GuardadosService.toggle(item);
    GuardadosBus.bump();
    return result;
  }

  /// Actualiza metadatos de un favorito existente en la base de datos.
  static Future<void> update(Map<String, dynamic> item) async {
    await GuardadosService.update(item);
    GuardadosBus.bump();
  }

  /// Elimina un contenido de favoritos.
  static Future<void> remove(int idcontenido) async {
    await GuardadosService.remove(idcontenido);
    GuardadosBus.bump();
  }

  /// Intenta recuperar un tmdb_id correcto buscando en TMDB por título (+ año opcional).
  static Future<int?> recoverTmdbId({
    required String title,
    String? mediaType,
    int? year,
  }) async {
    final clean = title.trim();
    if (clean.isEmpty || clean == 'Sin título' || clean == 'N/A' || clean == 'Cargando contenido...') {
      return null;
    }
    try {
      final results = await TmdbContentService().searchContent(
        query: clean,
        mediaType: mediaType,
        year: year,
      );
      for (final res in results) {
        final resTitle = (res['title'] ?? res['name'] ?? '').toString();
        if (titlesMatch(clean, resTitle)) {
          final id = parseCanonicalTmdbId(res['id']);
          if (id != null && id > 0) return id;
        }
      }
      if (results.isNotEmpty) {
        final firstId = parseCanonicalTmdbId(results.first['id']);
        if (firstId != null && firstId > 0) return firstId;
      }
    } catch (e) {
      debugPrint('[GuardadosCache] Error en recoverTmdbId: $e');
    }
    return null;
  }
}


/// Toast flotante centrado para Android TV, visible sobre cualquier interfaz o D-Pad.
void showTvToast(
  BuildContext context, {
  required String message,
  required IconData icon,
  Color? iconColor,
  Duration duration = const Duration(seconds: 2),
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;

  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (ctx) => Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xE61E1E24),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: iconColor ?? const Color(0xFFFF6B35), size: 26),
              const SizedBox(width: 14),
              Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  overlay.insert(entry);
  Future.delayed(duration, () {
    if (entry.mounted) {
      entry.remove();
    }
  });
}
