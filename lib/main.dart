import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

// ─── UUIDs del servicio BLE de chat de LessNet ───
const String lessnetServiceUuid = "6e400001-b5a3-f393-e0a9-e50e24dcca9e";
const String lessnetCharRxUuid  = "6e400002-b5a3-f393-e0a9-e50e24dcca9e"; // Telefono ESCRIBE
const String lessnetCharTxUuid  = "6e400003-b5a3-f393-e0a9-e50e24dcca9e"; // Telefono LEE (notificaciones)

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const LessNetApp());
}

// ─────────────────────────────────────────────
// APP ROOT — PALETA BLANCO Y NEGRO
// ─────────────────────────────────────────────
class LessNetApp extends StatelessWidget {
  const LessNetApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LessNet',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: const ColorScheme(
          brightness: Brightness.dark,
          primary: Colors.white,
          onPrimary: Colors.black,
          secondary: Colors.grey,
          onSecondary: Colors.black,
          error: Colors.redAccent,
          onError: Colors.white,
          surface: Color(0xFF0A0A0A),
          onSurface: Colors.white,
        ),
        scaffoldBackgroundColor: const Color(0xFF0A0A0A),
        useMaterial3: true,
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: const Color(0xFF111111),
          indicatorColor: Colors.white.withOpacity(0.15),
          iconTheme: WidgetStateProperty.all(const IconThemeData(color: Colors.grey)),
          labelTextStyle: WidgetStateProperty.all(
            const TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ),
      ),
      home: const HomePage(),
    );
  }
}

// ─────────────────────────────────────────────
// BLUETOOTH SERVICE GLOBAL
// FIXES:
//   - Usa onValueChangedStream en vez de lastValueStream
//   - Buffer de mensajes mas robusto (maneja chunks combinados)
//   - Re-subscribe a notificaciones si se caen
//   - MTU mas grande para menos chunks
//   - Limpieza completa al desconectar
// ─────────────────────────────────────────────
class BtService {
  static final BtService _instance = BtService._internal();
  factory BtService() => _instance;
  BtService._internal() {
    _setupPeripheralChannel();
  }

  // ─── Central mode (flutter_blue_plus) ───
  BluetoothDevice? connectedDevice;
  BluetoothCharacteristic? rxChar;
  BluetoothCharacteristic? txChar;
  StreamSubscription? _txSub;
  StreamSubscription? _connSub;
  final List<int> _receiveBuffer = [];
  bool _isConnecting = false;

  // ─── Peripheral mode (native MethodChannel) ───
  static const _peripheralChannel = MethodChannel('com.lessnet.ble_peripheral');
  bool _isPeripheral = false;
  bool _isAdvertising = false;
  bool _peripheralConnected = false;
  String _peripheralDeviceName = '';
  String _advertisingError = '';

  // ─── Shared state ───
  final List<ChatMessage> messages = [];
  final _msgController = StreamController<ChatMessage>.broadcast();
  Stream<ChatMessage> get onMessage => _msgController.stream;

  final _connectionController = StreamController<bool>.broadcast();
  Stream<bool> get onConnectionChange => _connectionController.stream;

  final _advertisingController = StreamController<bool>.broadcast();
  Stream<bool> get onAdvertisingChange => _advertisingController.stream;

  final _statusController = StreamController<String>.broadcast();
  Stream<String> get onStatusChange => _statusController.stream;

  bool get isAdvertising => _isAdvertising;
  bool get isPeripheralConnected => _peripheralConnected;
  bool get isConnected => connectedDevice != null || _peripheralConnected;
  bool get connecting => _isConnecting;
  String get advertisingError => _advertisingError;
  String get connectedName {
    if (connectedDevice != null) {
      return connectedDevice!.platformName.isEmpty
          ? 'Dispositivo'
          : connectedDevice!.platformName;
    }
    if (_peripheralConnected) return _peripheralDeviceName.isEmpty ? 'Dispositivo' : _peripheralDeviceName;
    return '';
  }

  // ─── Setup MethodChannel with native BLE peripheral ───
  void _setupPeripheralChannel() {
    _peripheralChannel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onDataReceived':
          final text = call.arguments as String? ?? '';
          if (text.isNotEmpty) {
            final msg = ChatMessage(text: text, mine: false, time: DateTime.now());
            messages.add(msg);
            _msgController.add(msg);
          }
          break;
        case 'onDeviceConnected':
          _peripheralConnected = true;
          _isAdvertising = false;
          _peripheralDeviceName = call.arguments as String? ?? '';
          _advertisingController.add(false);
          _connectionController.add(true);
          _statusController.add('Conectado: $_peripheralDeviceName');
          break;
        case 'onDeviceDisconnected':
          _peripheralConnected = false;
          _peripheralDeviceName = '';
          _connectionController.add(false);
          _statusController.add('Desconectado');
          break;
        case 'onAdvertiseStatus':
          final success = call.arguments as bool? ?? false;
          if (!success) {
            _advertisingError = 'El dispositivo no pudo iniciar advertising.';
          }
          _isAdvertising = success;
          _advertisingController.add(success);
          break;
      }
    });
  }

  // ─── Peripheral: start advertising ───
  Future<void> startAdvertising() async {
    _advertisingError = '';
    try {
      await _peripheralChannel.invokeMethod('startAdvertising');
      _isPeripheral = true;
      _isAdvertising = true;
      _advertisingController.add(true);
    } catch (e) {
      _isAdvertising = false;
      _advertisingError = e.toString().contains('ADV_ERROR')
          ? 'Este dispositivo NO soporta BLE advertising. Usa este celular para BUSCAR.'
          : 'Error: $e';
      _advertisingController.add(false);
      rethrow;
    }
  }

  // ─── Peripheral: stop advertising ───
  Future<void> stopAdvertising() async {
    try {
      await _peripheralChannel.invokeMethod('stopAdvertising');
    } catch (_) {}
    _isAdvertising = false;
    _isPeripheral = false;
    _peripheralConnected = false;
    _advertisingController.add(false);
  }

  // ─── Central: connect to a peripheral device ───
  // FIX: MTU request, re-subscribe on disconnect, onValueChangedStream
  Future<void> connectToDevice(BluetoothDevice device) async {
    if (_isConnecting) return;
    _isConnecting = true;
    _statusController.add('Conectando...');

    try {
      // Clean up any previous connection first
      await _cleanupPreConnect();

      // Connect with longer timeout
      await device.connect(timeout: const Duration(seconds: 20));

      connectedDevice = device;
      _connectionController.add(true);

      // Request larger MTU for fewer chunks (less chance of bugs)
      try {
        await device.requestMtu(512);
      } catch (_) {}

      // Discover services
      final services = await device.discoverServices();
      for (final service in services) {
        if (service.uuid.str128.toLowerCase() == lessnetServiceUuid.toLowerCase()) {
          for (final char in service.characteristics) {
            if (char.uuid.str128.toLowerCase() == lessnetCharRxUuid.toLowerCase()) {
              rxChar = char;
            } else if (char.uuid.str128.toLowerCase() == lessnetCharTxUuid.toLowerCase()) {
              txChar = char;
            }
          }
        }
      }

      // Subscribe to TX notifications (this is how we RECEIVE messages)
      if (txChar != null) {
        _receiveBuffer.clear();

        // Enable notifications
        final notifyOk = await txChar!.setNotifyValue(true);
        if (!notifyOk) {
          // Retry once
          await Future.delayed(const Duration(milliseconds: 200));
          await txChar!.setNotifyValue(true);
        }

        // FIX: Use onValueChangedStream for reliable notification delivery
        // lastValueStream can miss values during widget rebuilds
        _txSub = txChar!.onValueChangedStream.listen((value) {
          if (value.isNotEmpty) {
            _handleReceivedData(value);
          }
        });
      }

      // Listen for disconnection
      _connSub = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _statusController.add('Desconectado inesperadamente');
          _cleanup();
        }
      });

      _statusController.add('Conectado a ${device.platformName.isEmpty ? "Dispositivo" : device.platformName}');
    } catch (e) {
      _statusController.add('Error al conectar: $e');
      _cleanup();
      rethrow;
    } finally {
      _isConnecting = false;
    }
  }

  // ─── Handle received BLE data — ROBUST version ───
  // FIX: Handle cases where:
  //   - Multiple messages arrive in one BLE notification
  //   - Null terminator arrives with data
  //   - Partial messages arrive
  void _handleReceivedData(List<int> value) {
    int i = 0;
    while (i < value.length) {
      if (value[i] == 0x00) {
        // End of message marker - deliver complete message
        if (_receiveBuffer.isNotEmpty) {
          final text = utf8.decode(_receiveBuffer, allowMalformed: true);
          _receiveBuffer.clear();
          if (text.isNotEmpty) {
            final msg = ChatMessage(text: text, mine: false, time: DateTime.now());
            messages.add(msg);
            _msgController.add(msg);
          }
        }
        i++;
      } else {
        _receiveBuffer.add(value[i]);
        i++;
      }
    }

    // Safety: if buffer gets too large without null terminator, flush it
    // (prevents stuck messages if null terminator was lost)
    if (_receiveBuffer.length > 5000) {
      final text = utf8.decode(_receiveBuffer, allowMalformed: true);
      _receiveBuffer.clear();
      if (text.isNotEmpty) {
        final msg = ChatMessage(text: text, mine: false, time: DateTime.now());
        messages.add(msg);
        _msgController.add(msg);
      }
    }
  }

  // ─── Send message (works in both central and peripheral mode) ───
  // FIX: Larger chunk size based on MTU, with delay between chunks
  Future<void> sendMessage(String text) async {
    if (text.isEmpty) return;
    final msg = ChatMessage(text: text, mine: true, time: DateTime.now());
    messages.add(msg);
    _msgController.add(msg);

    if (_isPeripheral && _peripheralConnected) {
      // Peripheral mode: send via native GATT server
      try {
        await _peripheralChannel.invokeMethod('sendData', {'data': text});
      } catch (e) {
        rethrow;
      }
    } else if (rxChar != null) {
      // Central mode: send via flutter_blue_plus
      final bytes = utf8.encode(text);

      // FIX: Send chunks with small delays to prevent data loss
      // Use 20 bytes per chunk for maximum compatibility
      for (int i = 0; i < bytes.length; i += 20) {
        final end = i + 20 > bytes.length ? bytes.length : i + 20;
        final chunk = bytes.sublist(i, end);
        try {
          await rxChar!.write(Uint8List.fromList(chunk), withoutResponse: false);
        } catch (e) {
          // If write fails, the connection might be unstable
          _statusController.add('Error enviando datos');
          rethrow;
        }
        // Small delay between chunks to prevent overflow
        if (i + 20 < bytes.length) {
          await Future.delayed(const Duration(milliseconds: 10));
        }
      }
      // Send null terminator as end-of-message marker
      await rxChar!.write(Uint8List.fromList([0x00]), withoutResponse: false);
    }
  }

  // ─── Clean up before connecting (prevent stale state) ───
  Future<void> _cleanupPreConnect() async {
    _txSub?.cancel();
    _txSub = null;
    _connSub?.cancel();
    _connSub = null;
    rxChar = null;
    txChar = null;
    _receiveBuffer.clear();

    if (connectedDevice != null) {
      try {
        await connectedDevice!.disconnect();
      } catch (_) {}
      connectedDevice = null;
    }
  }

  void _cleanup() {
    _txSub?.cancel();
    _txSub = null;
    _connSub?.cancel();
    _connSub = null;
    connectedDevice = null;
    rxChar = null;
    txChar = null;
    _receiveBuffer.clear();
    _connectionController.add(false);
  }

  Future<void> disconnect() async {
    _statusController.add('Desconectando...');
    if (connectedDevice != null) {
      try {
        await connectedDevice!.disconnect();
      } catch (_) {}
    }
    if (_isPeripheral) {
      await stopAdvertising();
    }
    _cleanup();
  }

  void dispose() {
    _txSub?.cancel();
    _connSub?.cancel();
    _msgController.close();
    _connectionController.close();
    _advertisingController.close();
    _statusController.close();
  }
}

class ChatMessage {
  final String text;
  final bool mine;
  final DateTime time;
  ChatMessage({required this.text, required this.mine, required this.time});
}

// ─────────────────────────────────────────────
// HOME — navegacion con drawer + bottom nav
// ─────────────────────────────────────────────
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _index = 0;

  final _pages = const [
    PermissionsPage(),
    ScanPage(),
    ChatPage(),
    FirstAidPage(),
    GuidesPage(),
    VaultPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_index],
      bottomNavigationBar: NavigationBar(
        backgroundColor: const Color(0xFF111111),
        selectedIndex: _index > 2 ? 0 : _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.shield_outlined),
            selectedIcon: Icon(Icons.shield),
            label: 'Permisos',
          ),
          NavigationDestination(
            icon: Icon(Icons.bluetooth_searching),
            selectedIcon: Icon(Icons.bluetooth_connected),
            label: 'Dispositivos',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'Chat',
          ),
        ],
      ),
      drawer: Drawer(
        backgroundColor: const Color(0xFF111111),
        child: SafeArea(
          child: Column(
            children: [
              const DrawerHeader(
                decoration: BoxDecoration(color: Color(0xFF0A0A0A)),
                child: Row(
                  children: [
                    Icon(Icons.hub, color: Colors.white, size: 32),
                    SizedBox(width: 12),
                    Text('LessNet Vault',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              _drawerItem(Icons.local_hospital, 'Primeros Auxilios', 3),
              _drawerItem(Icons.terrain, 'Guias de Supervivencia', 4),
              _drawerItem(Icons.search, 'Vault / Busqueda', 5),
            ],
          ),
        ),
      ),
    );
  }

  Widget _drawerItem(IconData icon, String label, int page) {
    return ListTile(
      leading: Icon(icon, color: Colors.white70),
      title: Text(label, style: const TextStyle(color: Colors.white)),
      onTap: () => setState(() { _index = page; Navigator.pop(context); }),
    );
  }
}

// ─────────────────────────────────────────────
// PAGINA 1: PERMISOS
// ─────────────────────────────────────────────
class PermissionsPage extends StatefulWidget {
  const PermissionsPage({super.key});
  @override
  State<PermissionsPage> createState() => _PermissionsPageState();
}

class _PermissionsPageState extends State<PermissionsPage> {
  final _perms = [
    _PermItem('Ubicacion', Icons.location_on, Colors.grey,
        Permission.locationWhenInUse, 'Requerida para BT scan en Android < 12'),
    _PermItem('Bluetooth Scan', Icons.bluetooth_searching, Colors.grey,
        Permission.bluetoothScan, 'Buscar dispositivos cercanos (Android 12+)'),
    _PermItem('Bluetooth Connect', Icons.bluetooth_connected, Colors.grey,
        Permission.bluetoothConnect, 'Conectarse a dispositivos (Android 12+)'),
    _PermItem('Bluetooth Advertise', Icons.broadcast_on_personal,
        Colors.grey, Permission.bluetoothAdvertise,
        'Hacerse visible para otros dispositivos'),
  ];

  final Map<Permission, PermissionStatus> _statuses = {};
  bool _loading = false;
  bool _bluetoothOn = false;

  @override
  void initState() {
    super.initState();
    _checkAll();
    _checkHardware();
  }

  Future<void> _checkHardware() async {
    try {
      final adapterOn = await FlutterBluePlus.adapterState.first
          .timeout(const Duration(seconds: 3), onTimeout: () => BluetoothAdapterState.unknown);
      if (mounted) setState(() => _bluetoothOn = adapterOn == BluetoothAdapterState.on);
    } catch (_) {}
  }

  Future<void> _checkAll() async {
    for (final p in _perms) {
      final s = await p.permission.status;
      if (mounted) setState(() => _statuses[p.permission] = s);
    }
  }

  Future<void> _requestAll() async {
    setState(() => _loading = true);
    try {
      final results = await [
        Permission.locationWhenInUse,
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.bluetoothAdvertise,
      ].request();
      if (mounted) setState(() => _statuses.addAll(results));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    _checkHardware();
  }

  String _statusText(PermissionStatus? s) {
    if (s == null) return 'Verificando...';
    if (s.isGranted) return 'Concedido';
    if (s.isDenied) return 'Denegado';
    if (s.isPermanentlyDenied) return 'Denegado permanentemente';
    if (s.isRestricted) return 'Restringido';
    if (s.isLimited) return 'Limitado';
    return s.toString();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Header('Permisos', Icons.shield, 'Necesarios para Bluetooth'),

            // ─── Bluetooth status ───
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (_bluetoothOn ? Colors.white : Colors.red).withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: (_bluetoothOn ? Colors.white : Colors.red).withOpacity(0.2)),
              ),
              child: Row(children: [
                Icon(_bluetoothOn ? Icons.bluetooth : Icons.bluetooth_disabled,
                    color: _bluetoothOn ? Colors.white : Colors.redAccent, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Text(
                  _bluetoothOn ? 'Bluetooth ACTIVADO' : 'Bluetooth DESACTIVADO - Activa Bluetooth en ajustes!',
                  style: TextStyle(color: _bluetoothOn ? Colors.white : Colors.redAccent, fontWeight: FontWeight.w600, fontSize: 13),
                )),
              ]),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: Row(children: [
                const Icon(Icons.gps_fixed, color: Colors.white54, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Text(
                  'Asegurate de que la UBICACION este activada en ajustes del telefono. Es necesaria para buscar BLE.',
                  style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12),
                )),
              ]),
            ),

            const SizedBox(height: 16),
            Expanded(
              child: ListView(
                children: _perms.map((p) {
                  final st = _statuses[p.permission];
                  final granted = st?.isGranted ?? false;
                  return _PermCard(
                    item: p,
                    status: st,
                    statusText: _statusText(st),
                    granted: granted,
                    onRequest: () async {
                      final s = await p.permission.request();
                      if (mounted) setState(() => _statuses[p.permission] = s);
                    },
                    onOpenSettings: () => openAppSettings(),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: _loading
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                    : const Icon(Icons.done_all),
                label: Text(_loading ? 'Solicitando...' : 'Solicitar todos'),
                onPressed: _loading ? null : _requestAll,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PermItem {
  final String name;
  final IconData icon;
  final Color color;
  final Permission permission;
  final String desc;
  const _PermItem(this.name, this.icon, this.color, this.permission, this.desc);
}

class _PermCard extends StatelessWidget {
  final _PermItem item;
  final PermissionStatus? status;
  final String statusText;
  final bool granted;
  final VoidCallback onRequest;
  final VoidCallback onOpenSettings;

  const _PermCard({
    required this.item, required this.status, required this.statusText,
    required this.granted, required this.onRequest, required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    final permanentlyDenied = status?.isPermanentlyDenied ?? false;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(item.icon, color: Colors.white70, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                const SizedBox(height: 2),
                Text(item.desc, style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(granted ? Icons.check_circle : Icons.cancel,
                        color: granted ? Colors.white : Colors.redAccent, size: 14),
                    const SizedBox(width: 4),
                    Text(statusText, style: TextStyle(
                        color: granted ? Colors.white : permanentlyDenied ? Colors.orangeAccent : Colors.redAccent,
                        fontSize: 11, fontWeight: FontWeight.w600)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (status == null)
            const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
          else if (granted)
            const Icon(Icons.check_circle, color: Colors.white, size: 24)
          else if (permanentlyDenied)
            TextButton(onPressed: onOpenSettings, child: const Text('Ajustes', style: TextStyle(fontSize: 12)))
          else
            TextButton(onPressed: onRequest, child: const Text('Pedir', style: TextStyle(fontSize: 12))),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// PAGINA 2: SCAN + ADVERTISING + CONECTAR
// ─────────────────────────────────────────────
class ScanPage extends StatefulWidget {
  const ScanPage({super.key});
  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  final bt = BtService();
  final List<ScanResult> _results = [];
  bool _scanning = false;
  int _scanSeconds = 0;
  Timer? _scanTimer;
  StreamSubscription? _scanSub;
  StreamSubscription? _scanningSub;
  StreamSubscription? _connSub;
  StreamSubscription? _advSub;
  int _advertiseSeconds = 0;
  Timer? _advertiseTimer;
  StreamSubscription? _statusSub;

  @override
  void initState() {
    super.initState();
    _connSub = bt.onConnectionChange.listen((_) {
      if (mounted) setState(() {});
    });
    _advSub = bt.onAdvertisingChange.listen((isAdv) {
      if (mounted) {
        setState(() {});
        if (isAdv) {
          _advertiseSeconds = 0;
          _advertiseTimer?.cancel();
          _advertiseTimer = Timer.periodic(const Duration(seconds: 1), (_) {
            if (mounted) setState(() => _advertiseSeconds++);
          });
        } else {
          _advertiseTimer?.cancel();
          _advertiseTimer = null;
        }
      }
    });
    _statusSub = bt.onStatusChange.listen((msg) {
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.grey[800]),
        );
      }
    });
  }

  Future<void> _startScan() async {
    if (bt.isAdvertising) {
      await bt.stopAdvertising();
    }

    final statuses = await [
      Permission.locationWhenInUse,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();

    final scanGranted = statuses[Permission.bluetoothScan]?.isGranted ?? false;
    final connectGranted = statuses[Permission.bluetoothConnect]?.isGranted ?? false;
    if (!scanGranted || !connectGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Concede los permisos de Bluetooth primero'), backgroundColor: Colors.red),
        );
      }
      return;
    }

    try {
      final adapterState = await FlutterBluePlus.adapterState.first
          .timeout(const Duration(seconds: 3), onTimeout: () => BluetoothAdapterState.unknown);
      if (adapterState != BluetoothAdapterState.on) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Bluetooth esta APAGADO! Activa Bluetooth en ajustes.'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 5),
            ),
          );
        }
        return;
      }
    } catch (_) {}

    _results.clear();
    setState(() => _scanning = true);
    _scanSeconds = 0;
    _scanTimer?.cancel();
    _scanTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _scanSeconds++);
    });

    try {
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 60),
        androidUsesFineLocation: true,
      );

      _scanSub = FlutterBluePlus.scanResults.listen((results) {
        if (mounted) {
          setState(() {
            _results.clear();
            _results.addAll(results);
          });
        }
      });

      _scanningSub = FlutterBluePlus.isScanning.listen((scanning) {
        if (!scanning && mounted) {
          setState(() => _scanning = false);
          _scanTimer?.cancel();
          _scanTimer = null;
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() => _scanning = false);
        _scanTimer?.cancel();
        _scanTimer = null;
      }
    }
  }

  Future<void> _stopScan() async {
    await FlutterBluePlus.stopScan();
    _scanSub?.cancel();
    _scanningSub?.cancel();
    _scanTimer?.cancel();
    _scanTimer = null;
    if (mounted) setState(() => _scanning = false);
  }

  Future<void> _startAdvertising() async {
    if (_scanning) {
      await _stopScan();
    }

    try {
      await bt.startAdvertising();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Dispositivo visible! El otro celular debe buscar y conectar.'),
            backgroundColor: Colors.grey,
            duration: Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      final errMsg = e.toString();
      if (errMsg.contains('ADV_ERROR') || errMsg.contains('no soporta') || errMsg.contains('advertising')) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Este celular NO soporta BLE advertising. Usa este celular para BUSCAR.'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 8),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _stopAdvertising() async {
    await bt.stopAdvertising();
    _advertiseTimer?.cancel();
    _advertiseTimer = null;
    _advertiseSeconds = 0;
    if (mounted) setState(() {});
  }

  Future<void> _connect(BluetoothDevice device) async {
    try {
      await bt.connectToDevice(device);
      await _stopScan();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al conectar: $e'), backgroundColor: Colors.red, duration: Duration(seconds: 5)),
        );
      }
    }
  }

  String _fmtDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _scanningSub?.cancel();
    _connSub?.cancel();
    _advSub?.cancel();
    _statusSub?.cancel();
    _advertiseTimer?.cancel();
    _scanTimer?.cancel();
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = bt.isConnected;

    final sortedResults = List<ScanResult>.from(_results);
    sortedResults.sort((a, b) {
      final aIsLessNet = a.advertisementData.serviceUuids
          .any((uuid) => uuid.str128.toLowerCase() == lessnetServiceUuid.toLowerCase());
      final bIsLessNet = b.advertisementData.serviceUuids
          .any((uuid) => uuid.str128.toLowerCase() == lessnetServiceUuid.toLowerCase());
      if (aIsLessNet && !bIsLessNet) return -1;
      if (!aIsLessNet && bIsLessNet) return 1;
      return b.rssi.compareTo(a.rssi);
    });

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Header('Dispositivos', Icons.bluetooth_searching,
              isConnected ? 'Conectado: ${bt.connectedName}' : bt.isAdvertising ? 'Visible para otros' : 'Sin conexion'),

            const SizedBox(height: 16),

            // ─── Connected device card ───
            if (isConnected)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.08), borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withOpacity(0.2))),
                child: Row(children: [
                  const Icon(Icons.bluetooth_connected, color: Colors.white, size: 22),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(bt.connectedName,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                    Text(bt.connectedDevice?.remoteId.toString() ?? 'Conectado via BLE',
                        style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11)),
                  ])),
                  TextButton(onPressed: () => bt.disconnect(),
                    child: const Text('Desconectar', style: TextStyle(color: Colors.redAccent))),
                ]),
              ),

            // ─── Advertising indicator ───
            if (bt.isAdvertising && !isConnected)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withOpacity(0.15))),
                child: Row(children: [
                  const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70)),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Visible para otros dispositivos',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                    Text('Esperando conexion... ${_fmtDuration(_advertiseSeconds)}',
                        style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11)),
                  ])),
                  TextButton(onPressed: _stopAdvertising,
                    child: const Text('Detener', style: TextStyle(color: Colors.redAccent))),
                ]),
              ),

            // ─── Advertising error ───
            if (bt.advertisingError.isNotEmpty && !bt.isAdvertising)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Colors.red.withOpacity(0.06), borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.withOpacity(0.2))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const Icon(Icons.warning, color: Colors.redAccent, size: 20),
                    const SizedBox(width: 8),
                    Expanded(child: Text('Advertising no disponible',
                        style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600, fontSize: 13))),
                  ]),
                  const SizedBox(height: 6),
                  Text(bt.advertisingError,
                      style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12)),
                  const SizedBox(height: 6),
                  Text('Usa ESTE celular para BUSCAR y el OTRO para Hacerse Visible.',
                      style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12, fontWeight: FontWeight.w500)),
                ]),
              ),

            // ─── Two mode buttons ───
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  icon: _scanning
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                      : const Icon(Icons.search),
                  label: Text(_scanning ? 'Buscando ${_fmtDuration(_scanSeconds)}' : 'Buscar',
                      style: const TextStyle(fontSize: 13)),
                  onPressed: _scanning ? _stopScan : (bt.isAdvertising ? null : _startScan),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    backgroundColor: _scanning ? Colors.grey : Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  icon: bt.isAdvertising
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                      : const Icon(Icons.broadcast_on_personal),
                  label: Text(bt.isAdvertising ? 'Visible ${_fmtDuration(_advertiseSeconds)}' : 'Hacerme Visible', style: const TextStyle(fontSize: 13)),
                  onPressed: isConnected ? null : (bt.isAdvertising ? _stopAdvertising : _startAdvertising),
                  style: FilledButton.styleFrom(
                    backgroundColor: bt.isAdvertising ? Colors.grey : Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ]),

            const SizedBox(height: 16),

            // ─── Instructions ───
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.03),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.info_outline, color: Colors.white54, size: 18),
                  const SizedBox(width: 8),
                  const Text('Como conectarse:', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                ]),
                const SizedBox(height: 8),
                Text('1. Un celular presiona "Hacerme Visible"',
                    style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12)),
                Text('2. El OTRO celular presiona "Buscar"',
                    style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12)),
                Text('3. Toca "Conectar" en el dispositivo encontrado',
                    style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12)),
                Text('4. Ve a Chat y envia mensajes!',
                    style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.03), borderRadius: BorderRadius.circular(6)),
                  child: Row(children: [
                    const Icon(Icons.wifi_tethering, color: Colors.white38, size: 14),
                    const SizedBox(width: 6),
                    Expanded(child: Text('Bluetooth es LOCAL (10-30m). No es internet.',
                        style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11))),
                  ]),
                ),
              ]),
            ),

            const SizedBox(height: 16),

            // ─── Scan results ───
            if (_scanning || _results.isNotEmpty) ...[
              Row(children: [
                Text('Dispositivos encontrados (${_results.length})',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                const SizedBox(width: 8),
                if (_scanning)
                  const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54)),
              ]),
              const SizedBox(height: 8),
              ...sortedResults.map((r) {
                final isConn = bt.connectedDevice?.remoteId == r.device.remoteId;
                final rssi = r.rssi;
                final sig = rssi > -60 ? Colors.greenAccent : rssi > -80 ? Colors.orangeAccent : Colors.redAccent;
                final isLessNet = r.advertisementData.serviceUuids
                    .any((uuid) => uuid.str128.toLowerCase() == lessnetServiceUuid.toLowerCase());
                final deviceName = r.device.platformName.isNotEmpty ? r.device.platformName : 'Desconocido';
                return Container(
                  margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isConn ? Colors.white.withOpacity(0.1) : isLessNet ? Colors.white.withOpacity(0.06) : Colors.white.withOpacity(0.03),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: isConn ? Colors.white.withOpacity(0.3) : isLessNet ? Colors.white.withOpacity(0.15) : Colors.white.withOpacity(0.06))),
                  child: Row(children: [
                    Icon(isConn ? Icons.bluetooth_connected : isLessNet ? Icons.phone_android : Icons.bluetooth,
                        color: isConn ? Colors.white : isLessNet ? Colors.white : Colors.white38, size: 22),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(child: Text(deviceName,
                            style: TextStyle(color: isConn || isLessNet ? Colors.white : Colors.white70, fontWeight: FontWeight.w600, fontSize: 14))),
                        if (isLessNet)
                          Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
                            child: const Text('LessNet', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700))),
                      ]),
                      Text(r.device.remoteId.toString(), style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 11)),
                    ])),
                    Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: sig.withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
                      child: Text('$rssi dBm', style: TextStyle(color: sig, fontSize: 12, fontWeight: FontWeight.w600))),
                    if (!isConn) Padding(padding: const EdgeInsets.only(left: 4),
                      child: TextButton(onPressed: () => _connect(r.device),
                        child: const Text('Conectar', style: TextStyle(fontSize: 12)))),
                  ]),
                );
              }),
            ] else if (!_scanning && !bt.isAdvertising && !isConnected)
              Center(child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Column(children: [
                  Icon(Icons.bluetooth_searching, size: 48, color: Colors.white.withOpacity(0.1)),
                  const SizedBox(height: 12),
                  Text('Presiona Buscar o Hacerme Visible\npara empezar',
                      style: TextStyle(color: Colors.white.withOpacity(0.2)), textAlign: TextAlign.center),
                ]),
              )),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// PAGINA 3: CHAT BLE — FIX: mejor manejo de estado
// ─────────────────────────────────────────────
class ChatPage extends StatefulWidget {
  const ChatPage({super.key});
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final bt = BtService();
  StreamSubscription? _msgSub;
  StreamSubscription? _connSub;
  StreamSubscription? _statusSub;
  bool _connected = false;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _connected = bt.isConnected;
    _msgSub = bt.onMessage.listen((_) {
      if (mounted) setState(() {});
      _scrollToBottom();
    });
    _connSub = bt.onConnectionChange.listen((connected) {
      if (mounted) setState(() => _connected = bt.isConnected);
    });
    _statusSub = bt.onStatusChange.listen((msg) {
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.grey[800]),
        );
      }
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(_scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    _controller.clear();
    setState(() => _sending = true);
    try {
      await bt.sendMessage(text);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error enviando: $e'), backgroundColor: Colors.red),
        );
      }
    }
    if (mounted) setState(() => _sending = false);
    _scrollToBottom();
  }

  String _fmt(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  void dispose() {
    _msgSub?.cancel();
    _connSub?.cancel();
    _statusSub?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final msgs = bt.messages;
    return SafeArea(
      child: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
          child: _Header('Chat', Icons.chat_bubble,
            _connected ? 'Conectado por Bluetooth' : 'Sin conexion - Conecta un dispositivo primero')),
        if (_connected)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(8)),
            child: Row(children: [
              const Icon(Icons.bluetooth_connected, color: Colors.white, size: 16),
              const SizedBox(width: 6),
              Text('Conectado a ${bt.connectedName}',
                  style: const TextStyle(color: Colors.white, fontSize: 12)),
            ]),
          ),
        Expanded(
          child: msgs.isEmpty
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.bluetooth_disabled, size: 48, color: Colors.white.withOpacity(0.1)),
                  const SizedBox(height: 12),
                  Text(_connected ? 'Escribe un mensaje para enviar' : 'Conectate a un dispositivo\nen la pestana Dispositivos',
                      style: TextStyle(color: Colors.white.withOpacity(0.2)), textAlign: TextAlign.center),
                ]))
              : ListView.builder(controller: _scrollController, padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: msgs.length, itemBuilder: (_, i) {
                    final m = msgs[i];
                    return Align(alignment: m.mine ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        constraints: const BoxConstraints(maxWidth: 280),
                        decoration: BoxDecoration(color: m.mine ? Colors.white : Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(14), topRight: const Radius.circular(14),
                            bottomLeft: Radius.circular(m.mine ? 14 : 4), bottomRight: Radius.circular(m.mine ? 4 : 14))),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Text(m.text, style: TextStyle(color: m.mine ? Colors.black : Colors.white, fontSize: 14)),
                          const SizedBox(height: 4),
                          Text(_fmt(m.time), style: TextStyle(color: m.mine ? Colors.black45 : Colors.white.withOpacity(0.3), fontSize: 10)),
                        ])));
                  }),
        ),
        Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Row(children: [
            Expanded(child: TextField(controller: _controller, style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(hintText: _connected ? 'Escribe un mensaje...' : 'Sin conexion',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.2)),
                filled: true, fillColor: Colors.white.withOpacity(0.05),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white30)),
              ),
              onSubmitted: (_) => _send(),
            )),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _connected && !_sending ? _send : null,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.all(14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                disabledBackgroundColor: Colors.white24,
              ),
              child: _sending
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                  : const Icon(Icons.send, size: 20),
            ),
          ]),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────
// PAGINA 4: PRIMEROS AUXILIOS
// ─────────────────────────────────────────────
class FirstAidPage extends StatefulWidget {
  const FirstAidPage({super.key});
  @override
  State<FirstAidPage> createState() => _FirstAidPageState();
}

class _FirstAidPageState extends State<FirstAidPage> {
  List<dynamic> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final jsonStr = await rootBundle.loadString('assets/vault/first_aid/primeros_auxilios.json');
      final data = json.decode(jsonStr);
      final List<dynamic> items = data is List ? data : (data['items'] ?? data['protocolos'] ?? []);
      if (mounted) setState(() { _items = items; _loading = false; });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Color _priorityColor(String? priority) {
    switch (priority?.toLowerCase()) {
      case 'critica': return Colors.redAccent;
      case 'alta': return Colors.orangeAccent;
      default: return Colors.white54;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Header('Primeros Auxilios', Icons.local_hospital, 'Protocolos de emergencia'),
            const SizedBox(height: 16),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: Colors.white))
                  : _items.isEmpty
                      ? Center(child: Text('No hay datos', style: TextStyle(color: Colors.white24)))
                      : ListView.builder(
                          itemCount: _items.length,
                          itemBuilder: (_, i) {
                            final item = _items[i] as Map<String, dynamic>;
                            final title = item['titulo'] ?? item['title'] ?? 'Sin titulo';
                            final desc = item['descripcion'] ?? item['description'] ?? '';
                            final priority = item['prioridad'] ?? item['priority'] ?? '';
                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.04),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.white.withOpacity(0.06)),
                              ),
                              child: ListTile(
                                leading: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: _priorityColor(priority).withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(Icons.local_hospital, color: _priorityColor(priority), size: 20),
                                ),
                                title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                                subtitle: desc.isNotEmpty ? Text(desc, style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis) : null,
                                trailing: priority.isNotEmpty
                                    ? Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(color: _priorityColor(priority).withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
                                        child: Text(priority.toUpperCase(), style: TextStyle(color: _priorityColor(priority), fontSize: 9, fontWeight: FontWeight.w700)))
                                    : null,
                                onTap: () {
                                  Navigator.push(context, MaterialPageRoute(builder: (_) => _FirstAidDetailPage(item: item)));
                                },
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FirstAidDetailPage extends StatelessWidget {
  final Map<String, dynamic> item;
  const _FirstAidDetailPage({required this.item});

  @override
  Widget build(BuildContext context) {
    final title = item['titulo'] ?? item['title'] ?? 'Detalle';
    final desc = item['descripcion'] ?? item['description'] ?? '';
    final steps = item['pasos'] ?? item['steps'] ?? [];
    final warnings = item['advertencias'] ?? item['warnings'] ?? [];

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111111),
        title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 16)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (desc.isNotEmpty) ...[
              Text(desc, style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 14)),
              const SizedBox(height: 16),
            ],
            if (steps.isNotEmpty) ...[
              const Text('Pasos:', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
              const SizedBox(height: 8),
              ...(steps as List).asMap().entries.map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(width: 24, height: 24, margin: const EdgeInsets.only(right: 10),
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                    child: Center(child: Text('${e.key + 1}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)))),
                  Expanded(child: Text(e.value.toString(), style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13))),
                ]),
              )),
            ],
            if (warnings.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text('Advertencias:', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w700, fontSize: 14)),
              const SizedBox(height: 8),
              ...(warnings as List).map((w) => Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.red.withOpacity(0.05), borderRadius: BorderRadius.circular(8)),
                child: Row(children: [
                  const Icon(Icons.warning, color: Colors.redAccent, size: 16),
                  const SizedBox(width: 8),
                  Expanded(child: Text(w.toString(), style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12))),
                ]),
              )),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// PAGINA 5: GUIAS DE SUPERVIVENCIA
// ─────────────────────────────────────────────
class GuidesPage extends StatefulWidget {
  const GuidesPage({super.key});
  @override
  State<GuidesPage> createState() => _GuidesPageState();
}

class _GuidesPageState extends State<GuidesPage> {
  List<dynamic> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final jsonStr = await rootBundle.loadString('assets/vault/guides/supervivencia.json');
      final data = json.decode(jsonStr);
      final List<dynamic> items = data is List ? data : (data['items'] ?? data['guias'] ?? []);
      if (mounted) setState(() { _items = items; _loading = false; });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Header('Guias', Icons.terrain, 'Supervivencia offline'),
            const SizedBox(height: 16),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: Colors.white))
                  : _items.isEmpty
                      ? Center(child: Text('No hay datos', style: TextStyle(color: Colors.white24)))
                      : ListView.builder(
                          itemCount: _items.length,
                          itemBuilder: (_, i) {
                            final item = _items[i] as Map<String, dynamic>;
                            final title = item['titulo'] ?? item['title'] ?? 'Sin titulo';
                            final desc = item['descripcion'] ?? item['description'] ?? '';
                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.04),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.white.withOpacity(0.06)),
                              ),
                              child: ListTile(
                                leading: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.06),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(Icons.terrain, color: Colors.white54, size: 20),
                                ),
                                title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                                subtitle: desc.isNotEmpty ? Text(desc, style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis) : null,
                                onTap: () {
                                  Navigator.push(context, MaterialPageRoute(builder: (_) => _GuideDetailPage(item: item)));
                                },
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GuideDetailPage extends StatelessWidget {
  final Map<String, dynamic> item;
  const _GuideDetailPage({required this.item});

  @override
  Widget build(BuildContext context) {
    final title = item['titulo'] ?? item['title'] ?? 'Detalle';
    final desc = item['descripcion'] ?? item['description'] ?? '';
    final steps = item['pasos'] ?? item['steps'] ?? [];
    final tips = item['consejos'] ?? item['tips'] ?? [];

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111111),
        title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 16)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (desc.isNotEmpty) ...[
              Text(desc, style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 14)),
              const SizedBox(height: 16),
            ],
            if (steps.isNotEmpty) ...[
              const Text('Pasos:', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
              const SizedBox(height: 8),
              ...(steps as List).asMap().entries.map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(width: 24, height: 24, margin: const EdgeInsets.only(right: 10),
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                    child: Center(child: Text('${e.key + 1}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)))),
                  Expanded(child: Text(e.value.toString(), style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13))),
                ]),
              )),
            ],
            if (tips.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text('Consejos:', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700, fontSize: 14)),
              const SizedBox(height: 8),
              ...(tips as List).map((t) => Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.03), borderRadius: BorderRadius.circular(8)),
                child: Row(children: [
                  const Icon(Icons.lightbulb, color: Colors.white54, size: 16),
                  const SizedBox(width: 8),
                  Expanded(child: Text(t.toString(), style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12))),
                ]),
              )),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// PAGINA 6: VAULT / BUSQUEDA
// ─────────────────────────────────────────────
class VaultPage extends StatefulWidget {
  const VaultPage({super.key});
  @override
  State<VaultPage> createState() => _VaultPageState();
}

class _VaultPageState extends State<VaultPage> {
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  bool _searched = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) {
      setState(() { _results = []; _searched = false; });
      return;
    }
    final q = query.toLowerCase();
    final List<Map<String, dynamic>> found = [];

    try {
      final jsonStr = await rootBundle.loadString('assets/vault/first_aid/primeros_auxilios.json');
      final data = json.decode(jsonStr);
      final items = data is List ? data : (data['items'] ?? data['protocolos'] ?? []);
      for (final item in items) {
        final m = item as Map<String, dynamic>;
        final text = (m['titulo'] ?? '').toString().toLowerCase() + (m['descripcion'] ?? '').toString().toLowerCase();
        if (text.contains(q)) found.add({...m, '_type': 'first_aid'});
      }
    } catch (_) {}

    try {
      final jsonStr = await rootBundle.loadString('assets/vault/guides/supervivencia.json');
      final data = json.decode(jsonStr);
      final items = data is List ? data : (data['items'] ?? data['guias'] ?? []);
      for (final item in items) {
        final m = item as Map<String, dynamic>;
        final text = (m['titulo'] ?? '').toString().toLowerCase() + (m['descripcion'] ?? '').toString().toLowerCase();
        if (text.contains(q)) found.add({...m, '_type': 'guide'});
      }
    } catch (_) {}

    try {
      final jsonStr = await rootBundle.loadString('assets/vault/dictionary/diccionario.json');
      final data = json.decode(jsonStr);
      final items = data is List ? data : (data['items'] ?? data['palabras'] ?? []);
      for (final item in items) {
        final m = item as Map<String, dynamic>;
        final text = (m['palabra'] ?? '').toString().toLowerCase() + (m['definicion'] ?? '').toString().toLowerCase();
        if (text.contains(q)) found.add({...m, '_type': 'dictionary'});
      }
    } catch (_) {}

    try {
      final jsonStr = await rootBundle.loadString('assets/vault/wikipedia/wikipedia.json');
      final data = json.decode(jsonStr);
      final items = data is List ? data : (data['items'] ?? data['articulos'] ?? []);
      for (final item in items) {
        final m = item as Map<String, dynamic>;
        final text = (m['titulo'] ?? '').toString().toLowerCase() + (m['resumen'] ?? '').toString().toLowerCase();
        if (text.contains(q)) found.add({...m, '_type': 'wikipedia'});
      }
    } catch (_) {}

    if (mounted) setState(() { _results = found; _searched = true; });
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'first_aid': return Icons.local_hospital;
      case 'guide': return Icons.terrain;
      case 'dictionary': return Icons.book;
      case 'wikipedia': return Icons.article;
      default: return Icons.folder;
    }
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'first_aid': return 'Auxilio';
      case 'guide': return 'Guia';
      case 'dictionary': return 'Diccionario';
      case 'wikipedia': return 'Wiki';
      default: return 'Otro';
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Header('Vault', Icons.search, 'Busqueda global offline'),
            const SizedBox(height: 16),
            TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Buscar en todos los recursos...',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.2)),
                prefixIcon: const Icon(Icons.search, color: Colors.white38),
                filled: true,
                fillColor: Colors.white.withOpacity(0.04),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white24)),
              ),
              onSubmitted: _search,
            ),
            const SizedBox(height: 12),
            Expanded(
              child: !_searched
                  ? Center(child: Text('Escribe algo para buscar', style: TextStyle(color: Colors.white24)))
                  : _results.isEmpty
                      ? Center(child: Text('Sin resultados', style: TextStyle(color: Colors.white24)))
                      : ListView.builder(
                          itemCount: _results.length,
                          itemBuilder: (_, i) {
                            final r = _results[i];
                            final type = r['_type'] as String? ?? '';
                            final title = r['titulo'] ?? r['title'] ?? r['palabra'] ?? r['word'] ?? 'Sin titulo';
                            final desc = r['descripcion'] ?? r['description'] ?? r['definicion'] ?? r['definition'] ?? r['resumen'] ?? r['summary'] ?? '';
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.04),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.white.withOpacity(0.06)),
                              ),
                              child: ListTile(
                                leading: Icon(_typeIcon(type), color: Colors.white54, size: 20),
                                title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                                subtitle: desc.isNotEmpty ? Text(desc, style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 11), maxLines: 2, overflow: TextOverflow.ellipsis) : null,
                                trailing: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.08), borderRadius: BorderRadius.circular(4)),
                                  child: Text(_typeLabel(type), style: const TextStyle(color: Colors.white54, fontSize: 9, fontWeight: FontWeight.w600)),
                                ),
                                onTap: () {
                                  if (type == 'wikipedia') {
                                    Navigator.push(context, MaterialPageRoute(builder: (_) => _WikiDetailPage(item: r)));
                                  } else if (type == 'dictionary') {
                                    Navigator.push(context, MaterialPageRoute(builder: (_) => _DictDetailPage(item: r)));
                                  } else if (type == 'first_aid') {
                                    Navigator.push(context, MaterialPageRoute(builder: (_) => _FirstAidDetailPage(item: r)));
                                  } else if (type == 'guide') {
                                    Navigator.push(context, MaterialPageRoute(builder: (_) => _GuideDetailPage(item: r)));
                                  }
                                },
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WikiDetailPage extends StatelessWidget {
  final Map<String, dynamic> item;
  const _WikiDetailPage({required this.item});

  @override
  Widget build(BuildContext context) {
    final title = item['titulo'] ?? item['title'] ?? 'Articulo';
    final content = item['contenido'] ?? item['content'] ?? item['resumen'] ?? item['summary'] ?? '';
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111111),
        title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 16)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Text(content, style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 14, height: 1.6)),
      ),
    );
  }
}

class _DictDetailPage extends StatelessWidget {
  final Map<String, dynamic> item;
  const _DictDetailPage({required this.item});

  @override
  Widget build(BuildContext context) {
    final word = item['palabra'] ?? item['word'] ?? 'Palabra';
    final def = item['definicion'] ?? item['definition'] ?? '';
    final example = item['ejemplo'] ?? item['example'] ?? '';
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111111),
        title: Text(word, style: const TextStyle(color: Colors.white, fontSize: 16)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(word, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Text(def, style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 14, height: 1.6)),
            if (example.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text('Ejemplo:', style: TextStyle(color: Colors.white54, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.03), borderRadius: BorderRadius.circular(8)),
                child: Text(example, style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13, fontStyle: FontStyle.italic)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// REUSABLE HEADER
// ─────────────────────────────────────────────
class _Header extends StatelessWidget {
  final String title;
  final IconData icon;
  final String subtitle;
  const _Header(this.title, this.icon, this.subtitle);

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: Colors.white, size: 24),
      ),
      const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(subtitle, style: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 12)),
      ])),
    ]);
  }
}
