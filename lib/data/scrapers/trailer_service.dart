import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

class TrailerService {
  TrailerService._();
  static final TrailerService instance = TrailerService._();

  static const Map<String, String> _headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept-Language': 'es-MX,es;q=0.9,en;q=0.8',
  };

  /// Busca directamente en YouTube y extrae el videoId de ytInitialData sin usar APIs de pago
  Future<String?> getTrailerVideoId({
    required String titulo,
    int? anio,
  }) async {
    final queryParts = [titulo.trim()];
    if (anio != null && anio > 1900) {
      queryParts.add(anio.toString());
    }
    queryParts.add('trailer español');

    final query = queryParts.join(' ');
    final url =
        'https://www.youtube.com/results?search_query=${Uri.encodeComponent(query)}';

    try {
      final response = await http
          .get(Uri.parse(url), headers: _headers)
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) return null;
      final body = response.body;

      // 1. Extraer de ytInitialData
      final ytDataMatch = RegExp(r'var ytInitialData\s*=\s*(\{[\s\S]*?\});</script>').firstMatch(body);
      if (ytDataMatch != null) {
        final jsonStr = ytDataMatch.group(1)!;
        // Búsqueda por regex de videoId dentro del json estructurado
        final videoIdMatch = RegExp(r'"videoId":"([a-zA-Z0-9_-]{11})"').firstMatch(jsonStr);
        if (videoIdMatch != null) {
          final id = videoIdMatch.group(1);
          debugPrint('TrailerService: videoId encontrado en ytInitialData: $id');
          return id;
        }
      }

      // 2. Fallback regex en todo el cuerpo HTML
      final fallbackMatch = RegExp(r'watch\?v=([a-zA-Z0-9_-]{11})').firstMatch(body);
      if (fallbackMatch != null) {
        final id = fallbackMatch.group(1);
        debugPrint('TrailerService: videoId encontrado por fallback: $id');
        return id;
      }
    } catch (e) {
      debugPrint('Error en TrailerService: $e');
    }

    return null;
  }

  /// Abre un modal con el reproductor incrustado de youtube_player_iframe
  static void showTrailerModal({
    required BuildContext context,
    required String titulo,
    int? anio,
  }) async {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => _TrailerDialog(titulo: titulo, anio: anio),
    );
  }
}

class _TrailerDialog extends StatefulWidget {
  final String titulo;
  final int? anio;

  const _TrailerDialog({required this.titulo, this.anio});

  @override
  State<_TrailerDialog> createState() => _TrailerDialogState();
}

class _TrailerDialogState extends State<_TrailerDialog> {
  bool _loading = true;
  String? _videoId;
  String? _error;
  YoutubePlayerController? _controller;

  @override
  void initState() {
    super.initState();
    _fetchTrailer();
  }

  Future<void> _fetchTrailer() async {
    final videoId = await TrailerService.instance.getTrailerVideoId(
      titulo: widget.titulo,
      anio: widget.anio,
    );

    if (!mounted) return;

    if (videoId != null && videoId.isNotEmpty) {
      _controller = YoutubePlayerController.fromVideoId(
        videoId: videoId,
        autoPlay: true,
        params: const YoutubePlayerParams(
          showFullscreenButton: true,
          showControls: true,
          mute: false,
        ),
      );
      setState(() {
        _videoId = videoId;
        _loading = false;
      });
    } else {
      setState(() {
        _error = 'No se encontró trailer para "${widget.titulo}"';
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _controller?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.black,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Colors.white24),
      ),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            children: [
              if (_loading)
                const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Color(0xFFE50914)),
                      SizedBox(height: 12),
                      Text('Buscando trailer en YouTube...',
                          style: TextStyle(color: Colors.white70, fontSize: 13)),
                    ],
                  ),
                )
              else if (_error != null)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                )
              else if (_controller != null)
                YoutubePlayer(
                  controller: _controller!,
                  aspectRatio: 16 / 9,
                ),
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black54,
                    shape: const CircleBorder(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
