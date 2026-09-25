import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/foundation.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:nsd/nsd.dart';
import 'package:uuid/uuid.dart';
import '../storage/app_database.dart';

class DiscoveredFilmoticDevice {
  final String name;
  final String ip;
  final int port;
  final String? pin;
  final String? token;
  final Service rawService;

  DiscoveredFilmoticDevice({
    required this.name,
    required this.ip,
    required this.port,
    this.pin,
    this.token,
    required this.rawService,
  });
}

class TransferPayloadInfo {
  final String ip;
  final int port;
  final String token;
  final String pin;

  TransferPayloadInfo({
    required this.ip,
    required this.port,
    required this.token,
    required this.pin,
  });

  String toQrString() {
    return jsonEncode({
      'ip': ip,
      'port': port,
      'token': token,
    });
  }

  static TransferPayloadInfo? fromQrString(String raw, String pin) {
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final ip = map['ip']?.toString() ?? '';
      final port = int.tryParse(map['port']?.toString() ?? '') ?? 0;
      final token = map['token']?.toString() ?? '';
      if (ip.isNotEmpty && port > 0 && token.isNotEmpty) {
        return TransferPayloadInfo(
          ip: ip,
          port: port,
          token: token,
          pin: pin,
        );
      }
    } catch (_) {}
    return null;
  }
}

class TransferService {
  TransferService._();
  static final TransferService instance = TransferService._();

  ServerSocket? _serverSocket;
  Registration? _registration;
  Discovery? _activeDiscovery;

  bool get isServerRunning => _serverSocket != null;

  /// Obtiene la IP local en la red WiFi o LAN
  Future<String?> getLocalIp() async {
    try {
      final wifiIp = await NetworkInfo().getWifiIP();
      if (wifiIp != null && wifiIp.isNotEmpty && wifiIp != '0.0.0.0') {
        return wifiIp;
      }
    } catch (e) {
      debugPrint('Error obteniendo wifi IP: $e');
    }

    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback && addr.address.contains('.')) {
            return addr.address;
          }
        }
      }
    } catch (e) {
      debugPrint('Error obteniendo interfaces de red: $e');
    }
    return '127.0.0.1';
  }

  /// Cifra datos con AES usando clave derivada de token + pin
  String _encryptData(String plainText, String keySeed) {
    try {
      final keyBytes = sha256.convert(utf8.encode(keySeed)).bytes;
      final key = enc.Key(Uint8List.fromList(keyBytes));
      // IV fijo de 16 bytes para compatibilidad sencilla en transferencia local
      final iv = enc.IV(Uint8List.fromList(keyBytes.sublist(0, 16)));
      final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
      return encrypter.encrypt(plainText, iv: iv).base64;
    } catch (e) {
      debugPrint('Error cifrando datos: $e');
      return plainText;
    }
  }

  /// Descifra datos con AES
  String _decryptData(String cipherText, String keySeed) {
    try {
      final keyBytes = sha256.convert(utf8.encode(keySeed)).bytes;
      final key = enc.Key(Uint8List.fromList(keyBytes));
      final iv = enc.IV(Uint8List.fromList(keyBytes.sublist(0, 16)));
      final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
      return encrypter.decrypt64(cipherText, iv: iv);
    } catch (e) {
      debugPrint('Error descifrando datos: $e');
      return cipherText;
    }
  }

  static String? _getTxtString(Map<String, Uint8List?>? txt, String key) {
    if (txt == null) return null;
    final val = txt[key];
    if (val == null || val.isEmpty) return null;
    try {
      return utf8.decode(val);
    } catch (_) {
      return null;
    }
  }

  // ══════════════════════════════════════════════════════════════
  // DISPOSITIVO ORIGEN (Servidor TCP + mDNS)
  // ══════════════════════════════════════════════════════════════

  Future<TransferPayloadInfo?> startServer({
    required String pin,
    required void Function(String status) onStatus,
    required void Function(bool success, String message) onCompleted,
  }) async {
    await stopServer();

    final ip = await getLocalIp();
    if (ip == null || ip == '127.0.0.1') {
      onCompleted(false, 'No se pudo detectar la IP de red local.');
      return null;
    }

    final token = const Uuid().v4();

    try {
      // Puerto 0 para que el SO asigne un puerto libre automáticamente
      _serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
      final port = _serverSocket!.port;

      onStatus('Servidor iniciado en $ip:$port. Publicando en red local...');

      // Publicar servicio mDNS _filmotic._tcp con TXT records (PIN, token, IP)
      try {
        _registration = await register(
          Service(
            name: 'Filmotic-$pin',
            type: '_filmotic._tcp',
            port: port,
            txt: {
              'pin': Uint8List.fromList(utf8.encode(pin)),
              'token': Uint8List.fromList(utf8.encode(token)),
              'ip': Uint8List.fromList(utf8.encode(ip)),
            },
          ),
        );
        debugPrint('Servicio mDNS _filmotic._tcp publicado con éxito en puerto $port.');
      } catch (e) {
        debugPrint('Aviso: No se pudo publicar mDNS (se usará QR): $e');
      }

      onStatus('Listo en $ip:$port. Esperando conexión del receptor...');

      _serverSocket!.listen(
        (socket) async {
          onStatus('Dispositivo conectado desde ${socket.remoteAddress.address}. Verificando...');

          final buffer = <int>[];
          socket.listen(
            (data) {
              buffer.addAll(data);
              // Si recibimos salto de línea, procesamos el mensaje de handshake
              if (data.contains(10)) {
                _handleClientHandshake(
                  socket: socket,
                  receivedBytes: Uint8List.fromList(buffer),
                  expectedToken: token,
                  expectedPin: pin,
                  onStatus: onStatus,
                  onCompleted: onCompleted,
                );
                buffer.clear();
              }
            },
            onError: (err) {
              debugPrint('Error en socket cliente: $err');
              onCompleted(false, 'Error en conexión: $err');
            },
          );
        },
        onError: (err) {
          debugPrint('Error en ServerSocket: $err');
          onCompleted(false, 'Error en el servidor: $err');
        },
      );

      return TransferPayloadInfo(
        ip: ip,
        port: port,
        token: token,
        pin: pin,
      );
    } catch (e) {
      onCompleted(false, 'Error al iniciar servidor: $e');
      return null;
    }
  }

  Future<void> _handleClientHandshake({
    required Socket socket,
    required Uint8List receivedBytes,
    required String expectedToken,
    required String expectedPin,
    required void Function(String status) onStatus,
    required void Function(bool success, String message) onCompleted,
  }) async {
    try {
      final msg = utf8.decode(receivedBytes).trim();
      final handshake = jsonDecode(msg) as Map<String, dynamic>;

      final clientToken = handshake['token']?.toString() ?? '';
      final clientPin = handshake['pin']?.toString() ?? '';

      if (clientToken != expectedToken) {
        socket.write(jsonEncode({'status': 'error', 'message': 'Token UUID inválido.'}) + '\n');
        await socket.flush();
        await socket.close();
        onCompleted(false, 'Conexión rechazada: Token UUID no coincide.');
        return;
      }

      if (clientPin != expectedPin) {
        socket.write(jsonEncode({'status': 'error', 'message': 'Código PIN incorrecto.'}) + '\n');
        await socket.flush();
        await socket.close();
        onCompleted(false, 'Conexión rechazada: PIN incorrecto.');
        return;
      }

      onStatus('Autenticación correcta. Exportando y transmitiendo datos Sembast...');

      // Exportar datos de Sembast
      final data = await AppDatabase.instance.exportDataForTransfer();
      final jsonRaw = jsonEncode(data);

      // Cifrado AES con token+pin
      final encrypted = _encryptData(jsonRaw, '${expectedToken}_$expectedPin');

      final response = jsonEncode({
        'status': 'ok',
        'encrypted': true,
        'payload': encrypted,
      });

      socket.write(response + '\n');
      await socket.flush();
      await socket.close();

      onStatus('¡Transferencia completada con éxito!');
      onCompleted(true, 'Datos transferidos al dispositivo receptor exitosamente.');
    } catch (e) {
      socket.write(jsonEncode({'status': 'error', 'message': 'Error interno: $e'}) + '\n');
      await socket.flush();
      await socket.close();
      onCompleted(false, 'Error procesando solicitud: $e');
    }
  }

  Future<void> stopServer() async {
    if (_registration != null) {
      try {
        await unregister(_registration!);
      } catch (e) {
        debugPrint('Error desregistrando mDNS: $e');
      }
      _registration = null;
    }
    if (_serverSocket != null) {
      await _serverSocket!.close();
      _serverSocket = null;
    }
  }

  // ══════════════════════════════════════════════════════════════
  // DISPOSITIVO DESTINO (Cliente TCP + mDNS Discovery)
  // ══════════════════════════════════════════════════════════════

  Future<Discovery?> startDiscoveryDevices({
    required void Function(List<DiscoveredFilmoticDevice> devices) onUpdate,
  }) async {
    await stopDiscoveryDevices();
    try {
      final discovery = await startDiscovery(
        '_filmotic._tcp',
        autoResolve: true,
        ipLookupType: IpLookupType.v4,
      );
      _activeDiscovery = discovery;

      void updateList() {
        final list = <DiscoveredFilmoticDevice>[];
        for (final s in discovery.services) {
          final pin = _getTxtString(s.txt, 'pin');
          final token = _getTxtString(s.txt, 'token');
          String? ip = _getTxtString(s.txt, 'ip');
          if (ip == null || ip.isEmpty) {
            if (s.addresses != null && s.addresses!.isNotEmpty) {
              ip = s.addresses!.first.address;
            } else if (s.host != null && !s.host!.endsWith('.local')) {
              ip = s.host;
            }
          }
          final port = s.port ?? 0;
          final name = s.name ?? 'Filmotic';

          if (ip != null && ip.isNotEmpty && port > 0) {
            list.add(DiscoveredFilmoticDevice(
              name: name,
              ip: ip,
              port: port,
              pin: pin,
              token: token,
              rawService: s,
            ));
          }
        }
        onUpdate(list);
      }

      discovery.addListener(updateList);
      updateList();
      return discovery;
    } catch (e) {
      debugPrint('Error iniciando mDNS discovery: $e');
      return null;
    }
  }

  Future<void> stopDiscoveryDevices() async {
    if (_activeDiscovery != null) {
      try {
        await stopDiscovery(_activeDiscovery!);
      } catch (e) {
        debugPrint('Error deteniendo mDNS discovery: $e');
      }
      _activeDiscovery = null;
    }
  }

  Future<bool> connectAndImport({
    required String ip,
    required int port,
    required String token,
    required String pin,
    required void Function(String status) onStatus,
  }) async {
    Socket? socket;
    try {
      onStatus('Conectando a $ip:$port...');
      socket = await Socket.connect(
        ip,
        port,
        timeout: const Duration(seconds: 8),
      );

      onStatus('Conectado. Enviando token y PIN...');
      final handshake = jsonEncode({
        'token': token,
        'pin': pin,
      });
      socket.write(handshake + '\n');
      await socket.flush();

      onStatus('Esperando respuesta del origen...');
      final completer = Completer<bool>();
      final buffer = <int>[];

      socket.listen(
        (data) {
          buffer.addAll(data);
          if (data.contains(10)) {
            // Fin de línea recibido
            final raw = utf8.decode(buffer).trim();
            try {
              final res = jsonDecode(raw) as Map<String, dynamic>;
              if (res['status'] == 'ok') {
                onStatus('Datos recibidos. Descifrando e importando a Sembast...');
                final isEncrypted = res['encrypted'] == true;
                final payloadRaw = res['payload']?.toString() ?? '';

                Map<String, dynamic> finalData;
                if (isEncrypted) {
                  final decrypted = _decryptData(payloadRaw, '${token}_$pin');
                  finalData = jsonDecode(decrypted) as Map<String, dynamic>;
                } else {
                  finalData = jsonDecode(payloadRaw) as Map<String, dynamic>;
                }

                AppDatabase.instance.importTransferData(finalData).then((_) {
                  onStatus('¡Importación completada con éxito!');
                  if (!completer.isCompleted) completer.complete(true);
                }).catchError((err) {
                  onStatus('Error al guardar datos: $err');
                  if (!completer.isCompleted) completer.complete(false);
                });
              } else {
                onStatus('Error del origen: ${res['message']}');
                if (!completer.isCompleted) completer.complete(false);
              }
            } catch (e) {
              onStatus('Error procesando respuesta: $e');
              if (!completer.isCompleted) completer.complete(false);
            }
          }
        },
        onError: (err) {
          onStatus('Error de conexión: $err');
          if (!completer.isCompleted) completer.complete(false);
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete(false);
        },
      );

      final result = await completer.future.timeout(
        const Duration(seconds: 25),
        onTimeout: () {
          onStatus('Tiempo de espera agotado.');
          return false;
        },
      );

      return result;
    } catch (e) {
      onStatus('No se pudo conectar: $e');
      return false;
    } finally {
      await socket?.close();
    }
  }
}
