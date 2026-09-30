import '../core/storage/app_database.dart';

/// Servicio unificado de Guardados usando Sembast por perfil.
class GuardadosService {
  static Future<List<Map<String, dynamic>>> getAll() async {
    return AppDatabase.instance.getFavorites();
  }

  static Future<bool> isSaved(int idcontenido) async {
    return AppDatabase.instance.isFavorite(idcontenido);
  }

  static Future<bool> toggle(dynamic item) async {
    if (item == null) return false;
    final Map<String, dynamic> map;
    if (item is Map<String, dynamic>) {
      map = item;
    } else if (item is Map) {
      map = Map<String, dynamic>.from(item);
    } else {
      try {
        map = (item as dynamic).toMap() as Map<String, dynamic>;
      } catch (_) {
        return false;
      }
    }
    return AppDatabase.instance.toggleFavorite(map);
  }

  static Future<void> update(Map<String, dynamic> item) async {
    await AppDatabase.instance.updateFavorite(item);
  }

  static Future<void> remove(int idcontenido) async {
    await AppDatabase.instance.removeFavorite(idcontenido);
  }

  static Future<void> clearAll() async {
    final favs = await getAll();
    for (final f in favs) {
      final id = f['idcontenido'] as int? ?? f['contenido_id'] as int? ?? 0;
      if (id > 0) {
        await remove(id);
      }
    }
  }
}
