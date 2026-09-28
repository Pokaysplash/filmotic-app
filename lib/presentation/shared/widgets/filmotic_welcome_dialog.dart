import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// Diálogo de bienvenida modal exclusivo para móvil que invita al usuario
/// a unirse a la comunidad oficial de Filmotic en Telegram para reportar bugs.
class FilmoticWelcomeDialog extends StatelessWidget {
  static const String keyHasSeen = 'has_seen_welcome_dialog';
  static const String telegramUrl = 'https://t.me/+GFmv2pzxes8yNTcx';

  const FilmoticWelcomeDialog({super.key});

  /// Verifica y muestra el diálogo solo una vez en dispositivos móviles.
  static Future<void> checkAndShow(BuildContext context) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final mode = prefs.getString('app_mode') ?? 'mobile';
      // Solo mostrar en móvil, nunca en TV
      if (mode == 'tv') return;

      final hasSeen = prefs.getBool(keyHasSeen) ?? false;
      if (hasSeen) return;

      if (!context.mounted) return;

      await prefs.setBool(keyHasSeen, true);

      if (!context.mounted) return;

      await showDialog(
        context: context,
        barrierDismissible: true,
        builder: (ctx) => const FilmoticWelcomeDialog(),
      );
    } catch (e) {
      debugPrint('[FilmoticWelcomeDialog] Error comprobando bienvenida: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    const telegramBlue = Color(0xFF229ED9);

    return Dialog(
      backgroundColor: const Color(0xFF19191E),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icono de Telegram / Comunidad
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: telegramBlue.withValues(alpha: 0.15),
                shape: BoxShape.circle,
                border: Border.all(
                  color: telegramBlue.withValues(alpha: 0.35),
                  width: 1.5,
                ),
              ),
              child: const Icon(
                Icons.groups_rounded,
                color: telegramBlue,
                size: 32,
              ),
            ),
            const SizedBox(height: 18),

            // Título
            const Text(
              '¡Bienvenido a Filmotic!',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 12),

            // Mensaje
            Text(
              'Esta es una versión beta. Si encuentras algún error, únete a nuestra comunidad en Telegram para reportarlo.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.75),
                fontSize: 14,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 24),

            // Botón 1: Unirme al grupo
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () async {
                  Navigator.of(context).pop();
                  final uri = Uri.parse(telegramUrl);
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                },
                icon: const Icon(Icons.send_rounded, size: 18, color: Colors.white),
                label: const Text(
                  'Unirme al grupo',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: telegramBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 4,
                  shadowColor: telegramBlue.withValues(alpha: 0.5),
                ),
              ),
            ),
            const SizedBox(height: 10),

            // Botón 2: Más tarde
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white60,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Más tarde',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
