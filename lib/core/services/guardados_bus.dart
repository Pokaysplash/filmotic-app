import 'package:flutter/material.dart';
import '../../supabase/guardados_service.dart';

/// Modelo canónico para representar un contenido reproducible o almacenable en favoritos.
class Contenido {
  final String id;
  final String titulo;
  final String? poster;
  final String? backdrop;
  final String tipo; // 'pelicula' | 'serie'
  final int? year;
  final int? tmdbId;
  final double? voteAverage;
  final DateTime timestamp;

  const Contenido({
    required this.id,
    required this.titulo,
    this.poster,
    this.backdrop,
    required this.tipo,
    this.year,
    this.tmdbId,
    this.voteAverage,
    required this.timestamp,
  });

  factory Contenido.fromMap(Map<String, dynamic> map) {
    final rawId = map['idcontenido'] ??
        map['contenido_id'] ??
        map['tmdb_id'] ??
        map['id'] ??
        '';
    final rawTitulo = (map['titulo'] ??
            map['title'] ??
            map['name'] ??
            map['titulo_contenido'] ??
            'Sin título')
        .toString()
        .trim();
    final rawTipo = (map['tipo'] ??
            map['type'] ??
            map['media_type'] ??
            map['mediaType'] ??
            'pelicula')
        .toString()
        .toLowerCase();
    final tipo = (rawTipo == 'tv' || rawTipo == 'serie') ? 'serie' : 'pelicula';

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

    final rawTmdb = map['tmdb_id'] ?? map['tmdbId'] ?? map['idtmdb'];
    final tmdb = rawTmdb != null ? int.tryParse(rawTmdb.toString()) : int.tryParse(rawId.toString());

    DateTime ts;
    if (map['timestamp'] != null) {
      ts = DateTime.tryParse(map['timestamp'].toString()) ?? DateTime.now();
    } else {
      ts = DateTime.now();
    }

    return Contenido(
      id: rawId.toString(),
      titulo: rawTitulo.isNotEmpty ? rawTitulo : 'Sin título',
      poster: (map['poster'] ?? map['poster_path'] ?? map['imagen'])?.toString(),
      backdrop: (map['backdrop'] ?? map['backdrop_path'])?.toString(),
      tipo: tipo,
      year: parsedYear,
      tmdbId: tmdb,
      voteAverage: vote,
      timestamp: ts,
    );
  }

  Map<String, dynamic> toMap() {
    final intId = int.tryParse(id) ?? tmdbId ?? 0;
    return {
      'id': id,
      'idcontenido': intId,
      'contenido_id': intId,
      'tmdb_id': tmdbId ?? intId,
      'idtmdb': tmdbId ?? intId,
      'titulo': titulo,
      'title': titulo,
      'name': titulo,
      'poster': poster,
      'poster_path': poster,
      'backdrop': backdrop,
      'backdrop_path': backdrop,
      'tipo': tipo,
      'type': tipo,
      'media_type': tipo == 'serie' ? 'tv' : 'movie',
      'año': year,
      'year': year,
      'vote_average': voteAverage,
      'timestamp': timestamp.toIso8601String(),
      'metadatos_completos': titulo.isNotEmpty &&
          titulo != 'Sin título' &&
          poster != null &&
          poster!.isNotEmpty &&
          poster != 'null',
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
