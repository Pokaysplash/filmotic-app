import 'package:flutter_test/flutter_test.dart';
import 'package:lol/core/services/guardados_bus.dart';

void main() {
  group('titlesMatch - Verificación de coincidencia universal', () {
    test('Caracteres asiáticos / Hanzi / Donghua (ej: 仙逆)', () {
      expect(titlesMatch('仙逆剧场版：弑仙之战', '仙逆剧场版：弑仙之战'), isTrue);
      expect(titlesMatch('仙逆', '仙逆剧场版：弑仙之战'), isTrue);
      expect(titlesMatch('仙逆剧场版：弑仙之战', '仙逆'), isTrue);
    });

    test('Kanji / Hiragana / Katakana / Anime', () {
      expect(titlesMatch('進撃の巨人', '進撃の巨人'), isTrue);
      expect(titlesMatch('鬼滅の刃', '鬼滅の刃'), isTrue);
      expect(titlesMatch('SPY×FAMILY', 'SPY x FAMILY'), isTrue);
    });

    test('Títulos latinos con signos, puntuación y mayúsculas', () {
      expect(titlesMatch('Demon Slayer', 'Demon Slayer: Kimetsu no Yaiba'), isTrue);
      expect(titlesMatch('Spider-Man: No Way Home', 'spiderman no way home'), isTrue);
      expect(titlesMatch('Renegade Immortal', 'renegade immortal'), isTrue);
      expect(titlesMatch('Un Show Más', 'un show mas'), isTrue);
    });

    test('Títulos completamente no coincidentes retornan false', () {
      expect(titlesMatch('Batman', 'Superman'), isFalse);
      expect(titlesMatch('仙逆', '进击的巨人'), isFalse);
    });
  });
}
