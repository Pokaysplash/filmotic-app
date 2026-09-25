import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

/// Widget de Banner 320x50 para Adsterra usando WebView local.
/// Carga el tag HTML oficial de Adsterra de forma aislada y abre clics en navegador externo.
class AdsterraBannerWidget extends StatefulWidget {
  final String bannerKey;
  final EdgeInsetsGeometry? margin;

  const AdsterraBannerWidget({
    super.key,
    required this.bannerKey,
    this.margin,
  });

  @override
  State<AdsterraBannerWidget> createState() => _AdsterraBannerWidgetState();
}

class _AdsterraBannerWidgetState extends State<AdsterraBannerWidget> {
  bool _hasError = false;

  String _buildHtml(String key) {
    return '''
<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    html, body {
      margin: 0;
      padding: 0;
      background: transparent;
      overflow: hidden;
      width: 320px;
      height: 50px;
      display: flex;
      justify-content: center;
      align-items: center;
    }
  </style>
</head>
<body>
  <script type="text/javascript">
    atOptions = {
      'key' : '$key',
      'format' : 'iframe',
      'height' : 50,
      'width' : 320,
      'params' : {}
    };
  </script>
  <script type="text/javascript" src="https://www.highperformanceformat.com/$key/invoke.js"></script>
</body>
</html>
''';
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError || widget.bannerKey.isEmpty || widget.bannerKey == 'PENDIENTE') {
      return const SizedBox.shrink();
    }

    // flutter_inappwebview solo corre en plataformas móviles nativas de forma garantizada
    if (kIsWeb) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: widget.margin ?? const EdgeInsets.symmetric(vertical: 8),
      alignment: Alignment.center,
      child: SizedBox(
        width: 320,
        height: 50,
        child: InAppWebView(
          initialData: InAppWebViewInitialData(
            data: _buildHtml(widget.bannerKey),
            mimeType: 'text/html',
            encoding: 'utf-8',
            baseUrl: WebUri('https://www.highperformanceformat.com'),
          ),
          initialSettings: InAppWebViewSettings(
            transparentBackground: true,
            supportZoom: false,
            disableHorizontalScroll: true,
            disableVerticalScroll: true,
            javaScriptEnabled: true,
            useShouldOverrideUrlLoading: true,
            mediaPlaybackRequiresUserGesture: false,
            allowsInlineMediaPlayback: true,
          ),
          shouldOverrideUrlLoading: (controller, navigationAction) async {
            final uri = navigationAction.request.url;
            if (uri != null) {
              final urlStr = uri.toString();
              // Permitir cargas internas de scripts o iframes de adsterra
              if (urlStr.startsWith('data:') ||
                  urlStr == 'about:blank' ||
                  urlStr.contains('highperformanceformat.com') ||
                  urlStr.contains('profitablecpmrate.com') ||
                  urlStr.contains('adsterra')) {
                return NavigationActionPolicy.ALLOW;
              }

              // Clic del usuario en el anuncio: abrir en navegador externo
              try {
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              } catch (e) {
                debugPrint('[AdsterraBanner] Error abriendo enlace de anuncio: $e');
              }
              return NavigationActionPolicy.CANCEL;
            }
            return NavigationActionPolicy.ALLOW;
          },
          onReceivedError: (controller, request, error) {
            debugPrint('[AdsterraBanner] Error WebView: ${error.description}');
            if (mounted) {
              setState(() => _hasError = true);
            }
          },
        ),
      ),
    );
  }
}

/// Widget de Native Banner para Adsterra camuflado como tarjeta en el catálogo.
/// Carga el script y el contenedor nativo asignado con altura fija y bordes redondeados.
class AdsterraNativeBannerWidget extends StatefulWidget {
  final String containerId;
  final String scriptUrl;
  final double height;
  final EdgeInsetsGeometry? margin;

  const AdsterraNativeBannerWidget({
    super.key,
    required this.containerId,
    required this.scriptUrl,
    this.height = 250,
    this.margin,
  });

  @override
  State<AdsterraNativeBannerWidget> createState() =>
      _AdsterraNativeBannerWidgetState();
}

class _AdsterraNativeBannerWidgetState extends State<AdsterraNativeBannerWidget> {
  bool _hasError = false;

  String _buildHtml(String containerId, String scriptUrl) {
    return '''
<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    html, body {
      margin: 0;
      padding: 0;
      background: transparent;
      overflow: hidden;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      color: #ffffff;
      width: 100%;
      height: 100%;
    }
    #$containerId {
      width: 100%;
      height: 100%;
      display: flex;
      justify-content: center;
      align-items: center;
    }
  </style>
</head>
<body>
  <script async="async" data-cfasync="false" src="$scriptUrl"></script>
  <div id="$containerId"></div>
</body>
</html>
''';
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError ||
        widget.containerId.isEmpty ||
        widget.containerId == 'PENDIENTE' ||
        widget.scriptUrl.isEmpty ||
        widget.scriptUrl == 'PENDIENTE') {
      return const SizedBox.shrink();
    }

    if (kIsWeb) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: widget.margin ??
          const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      height: widget.height,
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF16161A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          InAppWebView(
            initialData: InAppWebViewInitialData(
              data: _buildHtml(widget.containerId, widget.scriptUrl),
              mimeType: 'text/html',
              encoding: 'utf-8',
              baseUrl: WebUri('https://profitableratecpmnetwork.com'),
            ),
            initialSettings: InAppWebViewSettings(
              transparentBackground: true,
              supportZoom: false,
              disableHorizontalScroll: true,
              disableVerticalScroll: true,
              javaScriptEnabled: true,
              useShouldOverrideUrlLoading: true,
              mediaPlaybackRequiresUserGesture: false,
              allowsInlineMediaPlayback: true,
            ),
            shouldOverrideUrlLoading: (controller, navigationAction) async {
              final uri = navigationAction.request.url;
              if (uri != null) {
                final urlStr = uri.toString();
                if (urlStr.startsWith('data:') ||
                    urlStr == 'about:blank' ||
                    urlStr.contains('profitableratecpmnetwork.com') ||
                    urlStr.contains('highperformanceformat.com') ||
                    urlStr.contains('adsterra')) {
                  return NavigationActionPolicy.ALLOW;
                }

                try {
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                } catch (e) {
                  debugPrint(
                      '[AdsterraNative] Error abriendo enlace de anuncio: $e');
                }
                return NavigationActionPolicy.CANCEL;
              }
              return NavigationActionPolicy.ALLOW;
            },
            onReceivedError: (controller, request, error) {
              debugPrint(
                  '[AdsterraNative] Error WebView: ${error.description}');
              if (mounted) {
                setState(() => _hasError = true);
              }
            },
          ),
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'AD',
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
