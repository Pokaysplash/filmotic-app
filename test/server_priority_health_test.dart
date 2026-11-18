import 'package:flutter_test/flutter_test.dart';
import 'package:lol/core/services/server_loader_shared.dart';

void main() {
  test('hostKeyFor extrae el host de video sin www ni TLD', () {
    expect(ServerLoader.hostKeyFor({'servidor_url': 'https://streamwish.to/e/abc'}), 'host:streamwish');
    expect(ServerLoader.hostKeyFor({'servidor_url': 'https://www.2embed.cc/embed/1'}), 'host:2embed');
    expect(ServerLoader.hostKeyFor({'url': 'https://player.vidsrc.net/x'}), 'host:vidsrc');
    expect(ServerLoader.hostKeyFor({}), '');
  });

  test('servidor sin historial queda en tier bueno', () {
    expect(ServerLoader.healthTierFor({'servidor_url': 'https://nuevo-host-xyz.com/e/1', 'fuente': 'fuente_nueva_xyz'}), 0);
  });
}
