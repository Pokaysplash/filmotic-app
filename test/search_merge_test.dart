import 'package:flutter_test/flutter_test.dart';
import 'package:lol/core/utils/search_merge.dart';
import 'package:lol/data/scrapers/base/buscador.dart';

BuscadorItem f(String sitio, String titulo, {String tipo = 'movie', int? tmdb}) => BuscadorItem(
      sitio: sitio, titulo: titulo, tipo: tipo, url: 'https://$sitio/x', imagen: '', tmdbId: tmdb);

void main() {
  test('normaliza acentos, año y artículos', () {
    expect(normalizeSearchTitle('Pokémon (2019)'), normalizeSearchTitle('Pokemon'));
    expect(normalizeSearchTitle('El Grinch'), normalizeSearchTitle('Grinch'));
    expect(normalizeSearchTitle('Elf Online Latino'), 'elf');
  });

  test('las fuentes se agrupan en el resultado TMDB y no se repiten', () {
    final out = mergeSearchResults(
      tmdbItems: [
        {'id': 10719, 'tmdb_id': 10719, 'title': 'Elf', 'media_type': 'movie'},
      ],
      fedItems: [f('cuevana3', 'Elf (2003)'), f('pelisplushd', 'Elf'), f('cuevana', 'ELF')],
    );
    expect(out, hasLength(1));
    expect(out.first['sitio'], isNull); // abre la ficha → mejor servidor
    expect((out.first['fuentes_agrupadas'] as List), hasLength(3));
  });

  test('título solo en fuentes: una tarjeta, abre la primera (más saludable)', () {
    final out = mergeSearchResults(
      tmdbItems: const [],
      fedItems: [f('pelisplushd', 'Rara'), f('cuevana3', 'Rara')],
    );
    expect(out, hasLength(1));
    expect(out.first['sitio'], 'pelisplushd');
  });

  test('con tmdb id desde una fuente abre la ficha', () {
    final out = mergeSearchResults(tmdbItems: const [], fedItems: [f('cuevana3', 'X', tmdb: 55)]);
    expect(out.first['sitio'], isNull);
    expect(out.first['tmdb_id'], 55);
  });
}
