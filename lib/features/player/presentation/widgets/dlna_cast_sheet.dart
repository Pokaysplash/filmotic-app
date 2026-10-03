import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_cast_dlna/media_cast_dlna.dart';
import '../../../../core/services/cast_service.dart';

/// Modal bottom sheet para descubrimiento y selección de dispositivos DLNA
class DlnaCastSheet extends StatefulWidget {
  final String videoUrl;
  final String title;
  final String? posterUrl;
  final VoidCallback onCastStarted;

  const DlnaCastSheet({
    super.key,
    required this.videoUrl,
    required this.title,
    this.posterUrl,
    required this.onCastStarted,
  });

  static Future<void> show({
    required BuildContext context,
    required String videoUrl,
    required String title,
    String? posterUrl,
    required VoidCallback onCastStarted,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DlnaCastSheet(
        videoUrl: videoUrl,
        title: title,
        posterUrl: posterUrl,
        onCastStarted: onCastStarted,
      ),
    );
  }

  @override
  State<DlnaCastSheet> createState() => _DlnaCastSheetState();
}

class _DlnaCastSheetState extends State<DlnaCastSheet> {
  final CastService _castService = CastService.instance;
  StreamSubscription<List<DlnaDevice>>? _sub;
  List<DlnaDevice> _devices = [];
  bool _isSearching = true;
  String? _connectingUdn;
  String? _errorMessage;

  static const Color kOrange = Color(0xFFFF6B35);
  static const Color kBgDark = Color(0xFF161616);
  static const Color kCardDark = Color(0xFF222222);

  @override
  void initState() {
    super.initState();
    _startSearch();
  }

  void _startSearch() {
    setState(() {
      _isSearching = true;
      _errorMessage = null;
      _devices = List.from(_castService.devices);
    });

    _sub?.cancel();
    _sub = _castService.discoverDevices(timeout: const Duration(seconds: 10)).listen(
      (list) {
        if (!mounted) return;
        setState(() {
          _devices = list;
          if (list.isNotEmpty) {
            _errorMessage = null;
          }
        });
      },
    );

    // Timeout de 10 segundos
    Future.delayed(const Duration(seconds: 10), () {
      if (!mounted) return;
      if (_devices.isEmpty) {
        setState(() {
          _isSearching = false;
          _errorMessage =
              'No se encontraron dispositivos. Asegúrate de estar en la misma red WiFi y que el dispositivo esté encendido.';
        });
      } else {
        setState(() => _isSearching = false);
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _selectDevice(DlnaDevice device) async {
    setState(() => _connectingUdn = device.udn.value);

    // 1. Conectar al dispositivo
    final connected = await _castService.connectToDevice(device.udn.value);
    if (!connected || !mounted) {
      setState(() {
        _connectingUdn = null;
        _errorMessage = _castService.lastError ??
            'Error al conectar con ${device.friendlyName}.';
      });
      return;
    }

    // 2. Enviar el stream VOD
    final success = await _castService.castMedia(
      widget.videoUrl,
      title: widget.title,
      posterUrl: widget.posterUrl,
    );

    if (!mounted) return;

    if (success) {
      widget.onCastStarted();
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.cast_connected_rounded, color: kOrange, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Reproduciendo en ${device.friendlyName}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF1E1E1E),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          duration: const Duration(seconds: 4),
        ),
      );
    } else {
      setState(() {
        _connectingUdn = null;
        _errorMessage = _castService.lastError ??
            'Este dispositivo no puede reproducir este formato. Prueba con otro contenido.';
      });
    }
  }

  IconData _deviceIcon(DlnaDevice device) {
    final name = device.friendlyName.toLowerCase();
    final model = device.modelDetails.modelName.toLowerCase();
    if (name.contains('xbox') || model.contains('xbox')) {
      return Icons.videogame_asset_rounded;
    }
    if (name.contains('speaker') || name.contains('audio')) {
      return Icons.speaker_group_rounded;
    }
    return Icons.tv_rounded;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      decoration: const BoxDecoration(
        color: kBgDark,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black87,
            blurRadius: 20,
            spreadRadius: 5,
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Píldora de arrastre
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 6),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Cabecera
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 12, 10),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: kOrange.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.cast_rounded,
                      color: kOrange,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Enviar a TV',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Dispositivos DLNA en tu red WiFi (Xbox, Smart TV)',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_isSearching)
                    const Padding(
                      padding: EdgeInsets.all(8.0),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: kOrange,
                        ),
                      ),
                    )
                  else
                    IconButton(
                      icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
                      tooltip: 'Buscar de nuevo',
                      onPressed: _startSearch,
                    ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white54),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white10, height: 1),

            // Mensaje de error / aviso
            if (_errorMessage != null)
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.redAccent.withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.error_outline_rounded,
                          color: Colors.redAccent,
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('Reintentar búsqueda'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kCardDark,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: const BorderSide(color: Colors.white12),
                          ),
                        ),
                        onPressed: _startSearch,
                      ),
                    ),
                  ],
                ),
              ),

            // Lista de dispositivos
            if (_devices.isNotEmpty)
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  itemCount: _devices.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final device = _devices[index];
                    final isConnectingThis = _connectingUdn == device.udn.value;
                    final subtitle = [
                      if (device.manufacturerDetails.manufacturer.isNotEmpty)
                        device.manufacturerDetails.manufacturer,
                      if (device.modelDetails.modelName.isNotEmpty &&
                          device.modelDetails.modelName !=
                              device.manufacturerDetails.manufacturer)
                        device.modelDetails.modelName,
                    ].join(' · ');

                    return Material(
                      color: kCardDark,
                      borderRadius: BorderRadius.circular(12),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: isConnectingThis ? null : () => _selectDevice(device),
                        splashColor: kOrange.withValues(alpha: 0.15),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.05),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  _deviceIcon(device),
                                  color: isConnectingThis ? kOrange : Colors.white70,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      device.friendlyName,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    if (subtitle.isNotEmpty) ...[
                                      const SizedBox(height: 3),
                                      Text(
                                        subtitle,
                                        style: const TextStyle(
                                          color: Colors.white38,
                                          fontSize: 12,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              if (isConnectingThis)
                                const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: kOrange,
                                  ),
                                )
                              else
                                const Icon(
                                  Icons.chevron_right_rounded,
                                  color: Colors.white38,
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              )
            else if (_isSearching && _errorMessage == null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 36),
                child: Column(
                  children: [
                    const SizedBox(
                      width: 32,
                      height: 32,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: kOrange,
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Buscando dispositivos en la red...',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Verifica que tu TV o Xbox estén en el mismo WiFi',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
