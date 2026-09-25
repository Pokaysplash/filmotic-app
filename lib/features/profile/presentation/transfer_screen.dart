import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../core/network/transfer_service.dart';

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
  bool _isSearchingMdns = false;
  List<DiscoveredFilmoticDevice> _discoveredDevices = [];
  String _clientStatus = '';

  final _sixDigitController = TextEditingController();
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
    // Generar código de 6 dígitos para mayor seguridad y conveniencia mDNS
    final p = (100000 + rand.nextInt(900000)).toString();
    setState(() => _hostPin = p);
  }

  @override
  void dispose() {
    TransferService.instance.stopServer();
    TransferService.instance.stopDiscoveryDevices();
    _tabController.dispose();
    _sixDigitController.dispose();
    _ipController.dispose();
    _portController.dispose();
    _tokenController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _startHostServer() async {
    setState(() {
      _isHosting = true;
      _hostStatus = 'Iniciando servidor de transferencia y anunciando mDNS...';
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

  // ── Modos de Recepción (Destino) ──

  Future<void> _startMdnsSearch() async {
    setState(() {
      _isSearchingMdns = true;
      _discoveredDevices = [];
      _clientStatus = 'Buscando dispositivos Filmotic en tu red Wi-Fi...';
    });

    await TransferService.instance.startDiscoveryDevices(
      onUpdate: (devices) {
        if (!mounted) return;
        setState(() {
          _discoveredDevices = devices;
          if (devices.isNotEmpty) {
            _clientStatus = 'Se encontraron ${devices.length} dispositivo(s).';
          }
        });
      },
    );
  }

  Future<void> _stopMdnsSearch() async {
    await TransferService.instance.stopDiscoveryDevices();
    if (mounted) {
      setState(() => _isSearchingMdns = false);
    }
  }

  Future<void> _connectToDiscoveredDevice(DiscoveredFilmoticDevice device, [String? explicitPin]) async {
    final pin = explicitPin ?? device.pin ?? '';
    if (pin.isEmpty) {
      final enteredPin = await _promptPinDialog(device.name);
      if (enteredPin == null || enteredPin.isEmpty) return;
      return _connectToDiscoveredDevice(device, enteredPin);
    }

    setState(() {
      _isConnecting = true;
      _clientStatus = 'Conectando a ${device.name} (${device.ip}:${device.port})...';
    });

    final success = await TransferService.instance.connectAndImport(
      ip: device.ip,
      port: device.port,
      token: device.token ?? '',
      pin: pin,
      onStatus: (status) {
        if (mounted) setState(() => _clientStatus = status);
      },
    );

    if (!mounted) return;
    setState(() => _isConnecting = false);
    _handleTransferResult(success);
  }

  Future<void> _connectWith6DigitCode() async {
    final code = _sixDigitController.text.trim();
    if (code.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ingresa un código de 6 dígitos válido.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isConnecting = true;
      _clientStatus = 'Buscando dispositivo con código $code en la red...';
    });

    // 1. Revisar si ya está en la lista de descubiertos
    DiscoveredFilmoticDevice? matched;
    for (final d in _discoveredDevices) {
      if (d.pin == code || d.name.contains(code)) {
        matched = d;
        break;
      }
    }

    // 2. Si no, iniciar descubrimiento rápido
    if (matched == null) {
      final completer = Completer<DiscoveredFilmoticDevice?>();
      await TransferService.instance.startDiscoveryDevices(
        onUpdate: (devices) {
          for (final d in devices) {
            if (d.pin == code || d.name.contains(code)) {
              if (!completer.isCompleted) completer.complete(d);
              break;
            }
          }
        },
      );

      matched = await completer.future.timeout(
        const Duration(seconds: 6),
        onTimeout: () => null,
      );
    }

    if (matched != null) {
      await _connectToDiscoveredDevice(matched, code);
    } else {
      if (!mounted) return;
      setState(() => _isConnecting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se encontró ningún dispositivo con código $code. Asegúrate de estar en la misma red Wi-Fi o usa el código QR.'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _connectManualClient() async {
    final ip = _ipController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? 0;
    final token = _tokenController.text.trim();
    final pin = _pinController.text.trim();

    if (ip.isEmpty || port <= 0 || token.isEmpty || (pin.length != 4 && pin.length != 6)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor completa todos los campos (IP, Puerto, Token y PIN).'),
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
    _handleTransferResult(success);
  }

  Future<String?> _promptPinDialog(String deviceName) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1c1c24),
        title: Text('PIN para $deviceName', style: const TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Ingresa el código PIN de 6 dígitos que aparece en la pantalla del emisor:',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              maxLength: 6,
              style: const TextStyle(color: Colors.white, fontSize: 24, letterSpacing: 8),
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                counterText: '',
                hintText: '000000',
                hintStyle: const TextStyle(color: Colors.white24),
                filled: true,
                fillColor: const Color(0xFF121218),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _kAccent),
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Conectar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _handleTransferResult(bool success) {
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
            'Transfiere tus perfiles a otro dispositivo en la misma red Wi-Fi o LAN sin depender de la nube.',
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
                    'Código PIN generado: $_hostPin',
                    style: const TextStyle(color: Colors.amberAccent, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Se anunciará como servicio Filmotic en la red local y con código QR.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white54, fontSize: 12),
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
                  const Text('Código PIN de 6 dígitos:',
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
                        letterSpacing: 8,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_hostInfo != null)
                    Text(
                      'Dirección: ${_hostInfo!.ip}:${_hostInfo!.port} (mDNS activo)',
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
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Recibe perfiles desde otro dispositivo en tu misma red local o mediante código QR.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 20),

          // ── 1. BOTÓN PRINCIPAL: Buscar dispositivos en mi red (mDNS) ──
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF181822),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _kAccent.withOpacity(0.4), width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _kAccent.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.wifi_find, color: _kAccent, size: 28),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Descubrimiento Automático',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          Text(
                            'Encuentra dispositivos en la misma red sin escribir IPs',
                            style: TextStyle(color: Colors.white54, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isSearchingMdns ? Colors.redAccent : _kAccent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: _isSearchingMdns
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Icon(Icons.search, color: Colors.white),
                  label: Text(
                    _isSearchingMdns ? 'Detener Búsqueda' : 'Buscar dispositivos en mi red',
                    style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  onPressed: _isConnecting
                      ? null
                      : (_isSearchingMdns ? _stopMdnsSearch : _startMdnsSearch),
                ),

                // Lista de dispositivos encontrados
                if (_discoveredDevices.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text('Dispositivos Filmotic disponibles:',
                      style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  ..._discoveredDevices.map((dev) => Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF222230),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.phonelink, color: _kAccent, size: 24),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(dev.name,
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                                  Text('${dev.ip}:${dev.port}',
                                      style: const TextStyle(color: Colors.white54, fontSize: 12)),
                                ],
                              ),
                            ),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _kAccent,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              onPressed: _isConnecting ? null : () => _connectToDiscoveredDevice(dev),
                              child: const Text('Conectar', style: TextStyle(color: Colors.white, fontSize: 12)),
                            ),
                          ],
                        ),
                      )),
                ] else if (_isSearchingMdns) ...[
                  const SizedBox(height: 14),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: _kAccent)),
                      SizedBox(width: 10),
                      Text('Rastreando dispositivos Filmotic (mDNS)...',
                          style: TextStyle(color: Colors.white54, fontSize: 12)),
                    ],
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── 2. OPCIÓN SECUNDARIA: Escanear QR ──
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              backgroundColor: const Color(0xFF181822),
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white24),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: Icon(_isScanning ? Icons.close : Icons.qr_code_scanner, color: _kAccent),
            label: Text(
              _isScanning ? 'Cerrar Escáner QR' : 'Escanear QR (Fallback si mDNS falla)',
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
            onPressed: () {
              setState(() => _isScanning = !_isScanning);
            },
          ),

          if (_isScanning) ...[
            const SizedBox(height: 14),
            Container(
              height: 250,
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
                            content: Text('¡QR detectado! Ingresa el PIN y confirma la conexión.'),
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

          const SizedBox(height: 16),

          // ── 3. OPCIÓN TERCIARIA: Introducir código de 6 dígitos ──
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF181822),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Row(
                  children: [
                    Icon(Icons.pin, color: Colors.amberAccent, size: 22),
                    SizedBox(width: 8),
                    Text(
                      'Introducir código de 6 dígitos',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'El dispositivo emisor muestra un PIN numérico. Ingrésalo para enlazar directamente.',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _sixDigitController,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: 20, letterSpacing: 6, fontWeight: FontWeight.bold),
                        decoration: InputDecoration(
                          counterText: '',
                          hintText: '123456',
                          hintStyle: const TextStyle(color: Colors.white24, letterSpacing: 6),
                          filled: true,
                          fillColor: const Color(0xFF121218),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          contentPadding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amberAccent.shade700,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: _isConnecting ? null : _connectWith6DigitCode,
                      child: const Text('Conectar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── Estado de Conexión ──
          if (_clientStatus.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF181822),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                children: [
                  if (_isConnecting) ...[
                    const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: _kAccent)),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Text(
                      _clientStatus,
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // ── Fallback Avanzado / Manual ──
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              leading: const Icon(Icons.settings_ethernet, color: Colors.white38, size: 20),
              title: const Text(
                'Ingreso Manual (IP / Puerto / Token)',
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
              children: [
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _ipController,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          labelText: 'IP Local',
                          labelStyle: const TextStyle(color: Colors.white60, fontSize: 12),
                          filled: true,
                          fillColor: const Color(0xFF181822),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _portController,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          labelText: 'Puerto',
                          labelStyle: const TextStyle(color: Colors.white60, fontSize: 12),
                          filled: true,
                          fillColor: const Color(0xFF181822),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _tokenController,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  decoration: InputDecoration(
                    labelText: 'Token UUID',
                    labelStyle: const TextStyle(color: Colors.white60, fontSize: 12),
                    filled: true,
                    fillColor: const Color(0xFF181822),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _pinController,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  style: const TextStyle(color: Colors.white, letterSpacing: 4, fontSize: 16),
                  decoration: InputDecoration(
                    counterText: '',
                    labelText: 'PIN de Verificación',
                    labelStyle: const TextStyle(color: Colors.white60, fontSize: 12),
                    filled: true,
                    fillColor: const Color(0xFF181822),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2a2a38),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.sync_alt, color: Colors.white70, size: 18),
                  label: const Text('Conectar Manualmente', style: TextStyle(color: Colors.white)),
                  onPressed: _isConnecting ? null : _connectManualClient,
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
