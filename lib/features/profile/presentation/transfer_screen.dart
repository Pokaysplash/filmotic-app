import 'dart:math';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../core/network/transfer_service.dart';
import '../../../core/storage/app_database.dart';

const _kAccent = Color(0xFFFF6B35);

class TransferScreen extends StatefulWidget {
  const TransferScreen({super.key});

  @override
  State<TransferScreen> createState() => _TransferScreenState();
}

class _TransferScreenState extends State<TransferScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // ── Origen (Servidor) ──
  bool _isHosting = false;
  TransferPayloadInfo? _hostInfo;
  String _hostPin = '';
  String _hostStatus = 'Presiona "Iniciar Compartir" para generar el QR.';

  // ── Destino (Cliente) ──
  bool _isConnecting = false;
  bool _isScanning = false;
  String _clientStatus = '';
  final _ipController = TextEditingController();
  final _portController = TextEditingController();
  final _tokenController = TextEditingController();
  final _pinController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _generateRandomPin();
  }

  void _generateRandomPin() {
    final rand = Random();
    final p = (1000 + rand.nextInt(9000)).toString();
    setState(() => _hostPin = p);
  }

  @override
  void dispose() {
    TransferService.instance.stopServer();
    _tabController.dispose();
    _ipController.dispose();
    _portController.dispose();
    _tokenController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _startHostServer() async {
    setState(() {
      _isHosting = true;
      _hostStatus = 'Iniciando servidor de transferencia...';
    });

    final info = await TransferService.instance.startServer(
      pin: _hostPin,
      onStatus: (status) {
        if (mounted) setState(() => _hostStatus = status);
      },
      onCompleted: (success, message) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: success ? Colors.green : Colors.redAccent,
          ),
        );
      },
    );

    if (mounted) {
      setState(() {
        _hostInfo = info;
        if (info == null) {
          _isHosting = false;
        }
      });
    }
  }

  Future<void> _stopHostServer() async {
    await TransferService.instance.stopServer();
    if (mounted) {
      setState(() {
        _isHosting = false;
        _hostInfo = null;
        _hostStatus = 'Servidor detenido.';
      });
    }
  }

  Future<void> _connectClient() async {
    final ip = _ipController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? 0;
    final token = _tokenController.text.trim();
    final pin = _pinController.text.trim();

    if (ip.isEmpty || port <= 0 || token.isEmpty || pin.length != 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor completa todos los campos (IP, Puerto, Token y PIN de 4 dígitos).'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isConnecting = true;
      _clientStatus = 'Iniciando conexión con $ip:$port...';
    });

    final success = await TransferService.instance.connectAndImport(
      ip: ip,
      port: port,
      token: token,
      pin: pin,
      onStatus: (status) {
        if (mounted) setState(() => _clientStatus = status);
      },
    );

    if (!mounted) return;
    setState(() => _isConnecting = false);

    if (success) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1c1c24),
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green),
              SizedBox(width: 8),
              Text('¡Transferencia Exitosa!', style: TextStyle(color: Colors.white)),
            ],
          ),
          content: const Text(
            'Se han importado todas las cuentas, perfiles, favoritos e historial en este dispositivo.',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _kAccent),
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pop(context, true);
              },
              child: const Text('Continuar', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_clientStatus.isNotEmpty ? _clientStatus : 'Fallo en la transferencia.'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF141418),
        title: const Text('Transferir Cuentas P2P'),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: _kAccent,
          tabs: const [
            Tab(icon: Icon(Icons.qr_code), text: 'Enviar (Origen)'),
            Tab(icon: Icon(Icons.download_rounded), text: 'Recibir (Destino)'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildSendTab(),
          _buildReceiveTab(),
        ],
      ),
    );
  }

  Widget _buildSendTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Text(
            'Transfiere tus perfiles a otro dispositivo en la misma red WiFi o LAN sin depender de la nube.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 24),
          if (!_isHosting) ...[
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF181822),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                children: [
                  const Icon(Icons.phonelink_ring_outlined, size: 60, color: _kAccent),
                  const SizedBox(height: 16),
                  const Text(
                    'Listo para compartir',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'PIN de seguridad asignado: $_hostPin',
                    style: const TextStyle(color: Colors.amberAccent, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kAccent,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.wifi_tethering, color: Colors.white),
                    label: const Text('Iniciar Compartir', style: TextStyle(color: Colors.white, fontSize: 16)),
                    onPressed: _startHostServer,
                  ),
                ],
              ),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF181822),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white24),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: _hostInfo != null
                        ? QrImageView(
                            data: _hostInfo!.toQrString(),
                            version: QrVersions.auto,
                            size: 200,
                          )
                        : const SizedBox(
                            width: 200,
                            height: 200,
                            child: Center(child: CircularProgressIndicator(color: _kAccent)),
                          ),
                  ),
                  const SizedBox(height: 20),
                  const Text('PIN de Verificación en pantalla:',
                      style: TextStyle(color: Colors.white70, fontSize: 14)),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.amberAccent.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.amberAccent),
                    ),
                    child: Text(
                      _hostPin,
                      style: const TextStyle(
                        color: Colors.amberAccent,
                        fontSize: 32,
                        letterSpacing: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_hostInfo != null)
                    Text(
                      'Dirección: ${_hostInfo!.ip}:${_hostInfo!.port}',
                      style: const TextStyle(color: Colors.white60, fontSize: 13),
                    ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: _kAccent),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _hostStatus,
                            style: const TextStyle(color: Colors.white70, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.redAccent,
                      side: const BorderSide(color: Colors.redAccent),
                    ),
                    icon: const Icon(Icons.stop),
                    label: const Text('Detener Servidor'),
                    onPressed: _stopHostServer,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildReceiveTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Escanea el código QR del dispositivo origen o ingresa los datos manualmente si estás en Android TV.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 20),

          // Botón Escanear QR
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF262636),
              padding: const EdgeInsets.symmetric(vertical: 14),
              side: const BorderSide(color: Colors.white24),
            ),
            icon: Icon(_isScanning ? Icons.close : Icons.camera_alt, color: Colors.white),
            label: Text(
              _isScanning ? 'Cerrar Escáner' : 'Escanear QR con Cámara',
              style: const TextStyle(color: Colors.white, fontSize: 15),
            ),
            onPressed: () {
              setState(() => _isScanning = !_isScanning);
            },
          ),

          if (_isScanning) ...[
            const SizedBox(height: 16),
            Container(
              height: 260,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _kAccent, width: 2),
              ),
              clipBehavior: Clip.antiAlias,
              child: MobileScanner(
                onDetect: (capture) {
                  final barcodes = capture.barcodes;
                  for (final barcode in barcodes) {
                    final raw = barcode.rawValue;
                    if (raw != null && raw.isNotEmpty) {
                      final info = TransferPayloadInfo.fromQrString(raw, '');
                      if (info != null) {
                        setState(() {
                          _ipController.text = info.ip;
                          _portController.text = info.port.toString();
                          _tokenController.text = info.token;
                          _isScanning = false;
                        });
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('¡QR escaneado! Ingresa el PIN que aparece en pantalla.'),
                            backgroundColor: Colors.green,
                          ),
                        );
                        break;
                      }
                    }
                  }
                },
              ),
            ),
          ],

          const SizedBox(height: 24),
          const Text('Datos de Conexión (Red Local):',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _ipController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'IP Local (ej. 192.168.1.50)',
                    labelStyle: const TextStyle(color: Colors.white60),
                    filled: true,
                    fillColor: const Color(0xFF181822),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _portController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Puerto',
                    labelStyle: const TextStyle(color: Colors.white60),
                    filled: true,
                    fillColor: const Color(0xFF181822),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _tokenController,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              labelText: 'Token UUID',
              labelStyle: const TextStyle(color: Colors.white60),
              filled: true,
              fillColor: const Color(0xFF181822),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pinController,
            keyboardType: TextInputType.number,
            maxLength: 4,
            style: const TextStyle(color: Colors.white, letterSpacing: 6, fontSize: 20),
            decoration: InputDecoration(
              counterText: '',
              labelText: 'PIN de 4 dígitos',
              labelStyle: const TextStyle(color: Colors.white60),
              filled: true,
              fillColor: const Color(0xFF181822),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 20),

          if (_clientStatus.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF181822),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _clientStatus,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ),
            const SizedBox(height: 16),
          ],

          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: _kAccent,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: _isConnecting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : const Icon(Icons.sync_alt, color: Colors.white),
            label: Text(
              _isConnecting ? 'Conectando y transfiriendo...' : 'Conectar y Recibir Datos',
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            onPressed: _isConnecting ? null : _connectClient,
          ),
        ],
      ),
    );
  }
}
