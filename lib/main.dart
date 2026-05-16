import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

// ─── UUIDs del servicio BLE de chat de LessNet ───
const String lessnetServiceUuid = "6e400001-b5a3-f393-e0a9-e50e24dcca9e";
const String lessnetCharRxUuid  = "6e400002-b5a3-f393-e0a9-e50e24dcca9e";
const String lessnetCharTxUuid  = "6e400003-b5a3-f393-e0a9-e50e24dcca9e";

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
          style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: const Color(0xFF111111),
          indicatorColor: Colors.white.withOpacity(0.15),
          iconTheme: WidgetStateProperty.all(const IconThemeData(color: Colors.grey)),
          labelTextStyle: WidgetStateProperty.all(const TextStyle(color: Colors.grey, fontSize: 11)),
        ),
      ),
      home: const HomePage(),
    );
  }
}

// ─────────────────────────────────────────────
// BLUETOOTH SERVICE GLOBAL
// ─────────────────────────────────────────────
class BtService {
  static final BtService _instance = BtService._internal();
  factory BtService() => _instance;
  BtService._internal() { _setupPeripheralChannel(); }

  BluetoothDevice? connectedDevice;
  BluetoothCharacteristic? rxChar;
  BluetoothCharacteristic? txChar;
  StreamSubscription? _txSub;
  StreamSubscription? _connSub;
  final List<int> _receiveBuffer = [];
  bool _isConnecting = false;

  static const _peripheralChannel = MethodChannel('com.lessnet.ble_peripheral');
  bool _isPeripheral = false;
  bool _isAdvertising = false;
  bool _peripheralConnected = false;
  String _peripheralDeviceName = '';
  String _advertisingError = '';

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
    if (connectedDevice != null) return connectedDevice!.platformName.isEmpty ? 'Dispositivo' : connectedDevice!.platformName;
    if (_peripheralConnected) return _peripheralDeviceName.isEmpty ? 'Dispositivo' : _peripheralDeviceName;
    return '';
  }

  void _setupPeripheralChannel() {
    _peripheralChannel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onDataReceived':
          final text = call.arguments as String? ?? '';
          if (text.isNotEmpty) { final msg = ChatMessage(text: text, mine: false, time: DateTime.now()); messages.add(msg); _msgController.add(msg); }
          break;
        case 'onDeviceConnected':
          _peripheralConnected = true; _isAdvertising = false;
          _peripheralDeviceName = call.arguments as String? ?? '';
          _advertisingController.add(false); _connectionController.add(true); _statusController.add('Conectado: $_peripheralDeviceName');
          break;
        case 'onDeviceDisconnected':
          _peripheralConnected = false; _peripheralDeviceName = '';
          _connectionController.add(false); _statusController.add('Desconectado');
          break;
        case 'onAdvertiseStatus':
          final success = call.arguments as bool? ?? false;
          if (!success) _advertisingError = 'El dispositivo no pudo iniciar advertising.';
          _isAdvertising = success; _advertisingController.add(success);
          break;
      }
    });
  }

  Future<void> startAdvertising() async {
    _advertisingError = '';
    try { await _peripheralChannel.invokeMethod('startAdvertising'); _isPeripheral = true; _isAdvertising = true; _advertisingController.add(true); }
    catch (e) { _isAdvertising = false; _advertisingError = e.toString().contains('ADV_ERROR') ? 'Este dispositivo NO soporta BLE advertising.' : 'Error: $e'; _advertisingController.add(false); rethrow; }
  }

  Future<void> stopAdvertising() async {
    try { await _peripheralChannel.invokeMethod('stopAdvertising'); } catch (_) {}
    _isAdvertising = false; _isPeripheral = false; _peripheralConnected = false; _advertisingController.add(false);
  }

  Future<void> connectToDevice(BluetoothDevice device) async {
    if (_isConnecting) return;
    _isConnecting = true; _statusController.add('Conectando...');
    try {
      await _cleanupPreConnect();
      await device.connect(timeout: const Duration(seconds: 20));
      connectedDevice = device; _connectionController.add(true);
      try { await device.requestMtu(512); } catch (_) {}
      final services = await device.discoverServices();
      for (final service in services) {
        if (service.uuid.str128.toLowerCase() == lessnetServiceUuid.toLowerCase()) {
          for (final char in service.characteristics) {
            if (char.uuid.str128.toLowerCase() == lessnetCharRxUuid.toLowerCase()) rxChar = char;
            else if (char.uuid.str128.toLowerCase() == lessnetCharTxUuid.toLowerCase()) txChar = char;
          }
        }
      }
      if (txChar != null) {
        _receiveBuffer.clear();
        final notifyOk = await txChar!.setNotifyValue(true);
        if (!notifyOk) { await Future.delayed(const Duration(milliseconds: 200)); await txChar!.setNotifyValue(true); }
        _txSub = txChar!.onValueChangedStream.listen((value) { if (value.isNotEmpty) _handleReceivedData(value); });
      }
      _connSub = device.connectionState.listen((state) { if (state == BluetoothConnectionState.disconnected) { _statusController.add('Desconectado'); _cleanup(); } });
      _statusController.add('Conectado');
    } catch (e) { _statusController.add('Error: $e'); _cleanup(); rethrow; } finally { _isConnecting = false; }
  }

  void _handleReceivedData(List<int> value) {
    int i = 0;
    while (i < value.length) {
      if (value[i] == 0x00) {
        if (_receiveBuffer.isNotEmpty) {
          final text = utf8.decode(_receiveBuffer, allowMalformed: true); _receiveBuffer.clear();
          if (text.isNotEmpty) { final msg = ChatMessage(text: text, mine: false, time: DateTime.now()); messages.add(msg); _msgController.add(msg); }
        }
        i++;
      } else { _receiveBuffer.add(value[i]); i++; }
    }
    if (_receiveBuffer.length > 5000) {
      final text = utf8.decode(_receiveBuffer, allowMalformed: true); _receiveBuffer.clear();
      if (text.isNotEmpty) { final msg = ChatMessage(text: text, mine: false, time: DateTime.now()); messages.add(msg); _msgController.add(msg); }
    }
  }

  Future<void> sendMessage(String text) async {
    if (text.isEmpty) return;
    final msg = ChatMessage(text: text, mine: true, time: DateTime.now()); messages.add(msg); _msgController.add(msg);
    if (_isPeripheral && _peripheralConnected) {
      try { await _peripheralChannel.invokeMethod('sendData', {'data': text}); } catch (e) { rethrow; }
    } else if (rxChar != null) {
      final bytes = utf8.encode(text);
      for (int i = 0; i < bytes.length; i += 20) {
        final end = i + 20 > bytes.length ? bytes.length : i + 20;
        await rxChar!.write(Uint8List.fromList(bytes.sublist(i, end)), withoutResponse: false);
        if (i + 20 < bytes.length) await Future.delayed(const Duration(milliseconds: 10));
      }
      await rxChar!.write(Uint8List.fromList([0x00]), withoutResponse: false);
    }
  }

  Future<void> _cleanupPreConnect() async {
    _txSub?.cancel(); _txSub = null; _connSub?.cancel(); _connSub = null;
    rxChar = null; txChar = null; _receiveBuffer.clear();
    if (connectedDevice != null) { try { await connectedDevice!.disconnect(); } catch (_) {} connectedDevice = null; }
  }

  void _cleanup() { _txSub?.cancel(); _connSub?.cancel(); _txSub = null; _connSub = null; connectedDevice = null; rxChar = null; txChar = null; _receiveBuffer.clear(); _connectionController.add(false); }
  Future<void> disconnect() async { _statusController.add('Desconectando...'); if (connectedDevice != null) { try { await connectedDevice!.disconnect(); } catch (_) {} } if (_isPeripheral) await stopAdvertising(); _cleanup(); }
  void dispose() { _txSub?.cancel(); _connSub?.cancel(); _msgController.close(); _connectionController.close(); _advertisingController.close(); _statusController.close(); }
}

class ChatMessage { final String text; final bool mine; final DateTime time; ChatMessage({required this.text, required this.mine, required this.time}); }

// ─────────────────────────────────────────────
// HOME — 4 tabs: Permisos | Dispositivos | Chat | Vault
// ─────────────────────────────────────────────
class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [
          PermissionsPage(),
          ScanPage(),
          ChatPage(),
          VaultHomePage(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: const Color(0xFF111111),
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.shield_outlined), selectedIcon: Icon(Icons.shield), label: 'Permisos'),
          NavigationDestination(icon: Icon(Icons.bluetooth_searching), selectedIcon: Icon(Icons.bluetooth_connected), label: 'Dispositivos'),
          NavigationDestination(icon: Icon(Icons.chat_bubble_outline), selectedIcon: Icon(Icons.chat_bubble), label: 'Chat'),
          NavigationDestination(icon: Icon(Icons.folder_outlined), selectedIcon: Icon(Icons.folder), label: 'Vault'),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// PERMISOS
// ─────────────────────────────────────────────
class PermissionsPage extends StatefulWidget {
  const PermissionsPage({super.key});
  @override
  State<PermissionsPage> createState() => _PermissionsPageState();
}

class _PermissionsPageState extends State<PermissionsPage> {
  final _perms = [
    _PermItem('Ubicacion', Icons.location_on, Permission.locationWhenInUse, 'Requerida para BT scan'),
    _PermItem('Bluetooth Scan', Icons.bluetooth_searching, Permission.bluetoothScan, 'Buscar dispositivos'),
    _PermItem('Bluetooth Connect', Icons.bluetooth_connected, Permission.bluetoothConnect, 'Conectarse a dispositivos'),
    _PermItem('Bluetooth Advertise', Icons.broadcast_on_personal, Permission.bluetoothAdvertise, 'Hacerse visible'),
  ];
  final Map<Permission, PermissionStatus> _statuses = {};
  bool _loading = false;
  bool _btOn = false;

  @override
  void initState() { super.initState(); _checkAll(); _checkBt(); }

  Future<void> _checkBt() async {
    try { final s = await FlutterBluePlus.adapterState.first.timeout(const Duration(seconds: 3), onTimeout: () => BluetoothAdapterState.unknown); if (mounted) setState(() => _btOn = s == BluetoothAdapterState.on); } catch (_) {}
  }

  Future<void> _checkAll() async { for (final p in _perms) { final s = await p.permission.status; if (mounted) setState(() => _statuses[p.permission] = s); } }

  Future<void> _requestAll() async {
    setState(() => _loading = true);
    try { final r = await [Permission.locationWhenInUse, Permission.bluetoothScan, Permission.bluetoothConnect, Permission.bluetoothAdvertise].request(); if (mounted) setState(() => _statuses.addAll(r)); }
    finally { if (mounted) setState(() => _loading = false); }
    _checkBt();
  }

  String _st(PermissionStatus? s) { if (s == null) return '...'; if (s.isGranted) return 'Concedido'; if (s.isDenied) return 'Denegado'; if (s.isPermanentlyDenied) return 'Denegado siempre'; return s.toString(); }

  @override
  Widget build(BuildContext context) {
    return SafeArea(child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _Header('Permisos', Icons.shield, 'Necesarios para Bluetooth'),
      const SizedBox(height: 12),
      Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: (_btOn ? Colors.white : Colors.red).withOpacity(0.06), borderRadius: BorderRadius.circular(10), border: Border.all(color: (_btOn ? Colors.white : Colors.red).withOpacity(0.15))), child: Row(children: [Icon(_btOn ? Icons.bluetooth : Icons.bluetooth_disabled, color: _btOn ? Colors.white : Colors.redAccent, size: 20), const SizedBox(width: 10), Expanded(child: Text(_btOn ? 'Bluetooth ACTIVADO' : 'Bluetooth DESACTIVADO!', style: TextStyle(color: _btOn ? Colors.white : Colors.redAccent, fontWeight: FontWeight.w600, fontSize: 13)))])),
      const SizedBox(height: 6),
      Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.white.withOpacity(0.03), borderRadius: BorderRadius.circular(8)), child: Row(children: [const Icon(Icons.gps_fixed, color: Colors.white38, size: 16), const SizedBox(width: 8), Expanded(child: Text('Activa la UBICACION en ajustes del telefono para buscar BLE.', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11)))])),
      const SizedBox(height: 16),
      Expanded(child: ListView(children: _perms.map((p) { final st = _statuses[p.permission]; final g = st?.isGranted ?? false; return Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.white.withOpacity(0.04), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white.withOpacity(0.06))), child: Row(children: [Icon(p.icon, color: g ? Colors.white : Colors.white38, size: 20), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(p.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)), Text(p.desc, style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 11))])), Icon(g ? Icons.check_circle : Icons.cancel, color: g ? Colors.white : Colors.redAccent, size: 18)])); }).toList())),
      const SizedBox(height: 8),
      SizedBox(width: double.infinity, child: FilledButton.icon(icon: _loading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black)) : const Icon(Icons.done_all), label: Text(_loading ? 'Solicitando...' : 'Solicitar todos'), onPressed: _loading ? null : _requestAll)),
    ])));
  }
}

class _PermItem { final String name; final IconData icon; final Permission permission; final String desc; const _PermItem(this.name, this.icon, this.permission, this.desc); }

// ─────────────────────────────────────────────
// SCAN + ADVERTISING + CONECTAR
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
  StreamSubscription? _statusSub;
  int _advSec = 0;
  Timer? _advTimer;

  @override
  void initState() {
    super.initState();
    _connSub = bt.onConnectionChange.listen((_) { if (mounted) setState(() {}); });
    _advSub = bt.onAdvertisingChange.listen((a) { if (mounted) { setState(() {}); if (a) { _advSec = 0; _advTimer?.cancel(); _advTimer = Timer.periodic(const Duration(seconds: 1), (_) { if (mounted) setState(() => _advSec++); }); } else { _advTimer?.cancel(); _advTimer = null; } } });
    _statusSub = bt.onStatusChange.listen((m) { if (mounted) { ScaffoldMessenger.of(context).clearSnackBars(); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), backgroundColor: Colors.grey[800])); } });
  }

  Future<void> _startScan() async {
    if (bt.isAdvertising) await bt.stopAdvertising();
    final st = await [Permission.locationWhenInUse, Permission.bluetoothScan, Permission.bluetoothConnect].request();
    if (!(st[Permission.bluetoothScan]?.isGranted ?? false) || !(st[Permission.bluetoothConnect]?.isGranted ?? false)) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Concede permisos primero'), backgroundColor: Colors.red)); return; }
    try { final a = await FlutterBluePlus.adapterState.first.timeout(const Duration(seconds: 3), onTimeout: () => BluetoothAdapterState.unknown); if (a != BluetoothAdapterState.on) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bluetooth APAGADO!'), backgroundColor: Colors.red, duration: Duration(seconds: 5))); return; } } catch (_) {}
    _results.clear(); setState(() => _scanning = true); _scanSeconds = 0; _scanTimer?.cancel(); _scanTimer = Timer.periodic(const Duration(seconds: 1), (_) { if (mounted) setState(() => _scanSeconds++); });
    try { await FlutterBluePlus.startScan(timeout: const Duration(seconds: 60), androidUsesFineLocation: true); _scanSub = FlutterBluePlus.scanResults.listen((r) { if (mounted) setState(() { _results.clear(); _results.addAll(r); }); }); _scanningSub = FlutterBluePlus.isScanning.listen((s) { if (!s && mounted) { setState(() => _scanning = false); _scanTimer?.cancel(); _scanTimer = null; } }); } catch (_) { if (mounted) { setState(() => _scanning = false); _scanTimer?.cancel(); } }
  }

  Future<void> _stopScan() async { await FlutterBluePlus.stopScan(); _scanSub?.cancel(); _scanningSub?.cancel(); _scanTimer?.cancel(); _scanTimer = null; if (mounted) setState(() => _scanning = false); }

  Future<void> _startAdv() async {
    if (_scanning) await _stopScan();
    try { await bt.startAdvertising(); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Visible! El otro celular debe buscar.'), backgroundColor: Colors.grey)); }
    catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Este celular NO soporta advertising. Usalo para BUSCAR.'), backgroundColor: Colors.red, duration: Duration(seconds: 6))); }
  }

  Future<void> _connect(BluetoothDevice d) async { try { await bt.connectToDevice(d); await _stopScan(); } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red)); } }

  String _fmt(int s) { return '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}'; }

  @override
  void dispose() { _scanSub?.cancel(); _scanningSub?.cancel(); _connSub?.cancel(); _advSub?.cancel(); _statusSub?.cancel(); _advTimer?.cancel(); _scanTimer?.cancel(); FlutterBluePlus.stopScan(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final conn = bt.isConnected;
    final sorted = List<ScanResult>.from(_results)..sort((a, b) { final aL = a.advertisementData.serviceUuids.any((u) => u.str128.toLowerCase() == lessnetServiceUuid.toLowerCase()); final bL = b.advertisementData.serviceUuids.any((u) => u.str128.toLowerCase() == lessnetServiceUuid.toLowerCase()); if (aL && !bL) return -1; if (!aL && bL) return 1; return b.rssi.compareTo(a.rssi); });

    return SafeArea(child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _Header('Dispositivos', Icons.bluetooth_searching, conn ? 'Conectado: ${bt.connectedName}' : bt.isAdvertising ? 'Visible' : 'Sin conexion'),
      const SizedBox(height: 16),
      if (conn) Container(margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: Colors.white.withOpacity(0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white.withOpacity(0.15))), child: Row(children: [const Icon(Icons.bluetooth_connected, color: Colors.white, size: 22), const SizedBox(width: 12), Expanded(child: Text(bt.connectedName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600))), TextButton(onPressed: () => bt.disconnect(), child: const Text('Desconectar', style: TextStyle(color: Colors.redAccent)))])),
      if (bt.isAdvertising && !conn) Container(margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white.withOpacity(0.1))), child: Row(children: [const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54)), const SizedBox(width: 12), Expanded(child: Text('Esperando conexion... ${_fmt(_advSec)}', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13))), TextButton(onPressed: () { bt.stopAdvertising(); _advTimer?.cancel(); _advTimer = null; _advSec = 0; setState(() {}); }, child: const Text('Detener', style: TextStyle(color: Colors.redAccent)))])),
      if (bt.advertisingError.isNotEmpty && !bt.isAdvertising) Container(margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.red.withOpacity(0.05), borderRadius: BorderRadius.circular(10)), child: Text('Advertising no disponible. Usa ESTE celular para BUSCAR.', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12))),
      Row(children: [
        Expanded(child: FilledButton.icon(icon: _scanning ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black)) : const Icon(Icons.search), label: Text(_scanning ? _fmt(_scanSeconds) : 'Buscar', style: const TextStyle(fontSize: 13)), onPressed: _scanning ? _stopScan : (bt.isAdvertising ? null : _startScan), style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12), backgroundColor: _scanning ? Colors.grey : Colors.white))),
        const SizedBox(width: 10),
        Expanded(child: FilledButton.icon(icon: bt.isAdvertising ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black)) : const Icon(Icons.broadcast_on_personal), label: Text(bt.isAdvertising ? _fmt(_advSec) : 'Visible', style: const TextStyle(fontSize: 13)), onPressed: conn ? null : (bt.isAdvertising ? () { bt.stopAdvertising(); _advTimer?.cancel(); _advSec = 0; setState(() {}); } : _startAdv), style: FilledButton.styleFrom(backgroundColor: bt.isAdvertising ? Colors.grey : Colors.white, padding: const EdgeInsets.symmetric(vertical: 12)))),
      ]),
      const SizedBox(height: 16),
      if (_scanning || _results.isNotEmpty) ...[ Row(children: [Text('Encontrados (${_results.length})', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)), const SizedBox(width: 8), if (_scanning) const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white38))]), const SizedBox(height: 8),
        ...sorted.map((r) { final isC = bt.connectedDevice?.remoteId == r.device.remoteId; final isLN = r.advertisementData.serviceUuids.any((u) => u.str128.toLowerCase() == lessnetServiceUuid.toLowerCase()); final name = r.device.platformName.isNotEmpty ? r.device.platformName : 'Desconocido'; final sig = r.rssi > -60 ? Colors.greenAccent : r.rssi > -80 ? Colors.orangeAccent : Colors.redAccent; return Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: isLN ? Colors.white.withOpacity(0.06) : Colors.white.withOpacity(0.02), borderRadius: BorderRadius.circular(12), border: Border.all(color: isLN ? Colors.white.withOpacity(0.12) : Colors.white.withOpacity(0.04))), child: Row(children: [Icon(isLN ? Icons.phone_android : Icons.bluetooth, color: isLN ? Colors.white : Colors.white38, size: 20), const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Expanded(child: Text(name, style: TextStyle(color: isLN ? Colors.white : Colors.white60, fontWeight: FontWeight.w600, fontSize: 13))), if (isLN) Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1), decoration: BoxDecoration(color: Colors.white.withOpacity(0.12), borderRadius: BorderRadius.circular(3)), child: const Text('LessNet', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w700)))]), Text(r.device.remoteId.toString(), style: TextStyle(color: Colors.white.withOpacity(0.25), fontSize: 10))])), Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3), decoration: BoxDecoration(color: sig.withOpacity(0.12), borderRadius: BorderRadius.circular(5)), child: Text('${r.rssi}', style: TextStyle(color: sig, fontSize: 11, fontWeight: FontWeight.w600))), if (!isC) Padding(padding: const EdgeInsets.only(left: 4), child: TextButton(onPressed: () => _connect(r.device), child: const Text('Conectar', style: TextStyle(fontSize: 11))))])); }),
      ] else if (!_scanning && !bt.isAdvertising && !conn) Center(child: Padding(padding: const EdgeInsets.symmetric(vertical: 30), child: Text('Presiona Buscar o Visible\npara empezar', style: TextStyle(color: Colors.white.withOpacity(0.15)), textAlign: TextAlign.center))),
    ])));
  }
}

// ─────────────────────────────────────────────
// CHAT
// ─────────────────────────────────────────────
class ChatPage extends StatefulWidget {
  const ChatPage({super.key});
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final bt = BtService();
  StreamSubscription? _msgSub, _connSub;
  bool _connected = false;

  @override
  void initState() {
    super.initState();
    _connected = bt.isConnected;
    _msgSub = bt.onMessage.listen((_) { if (mounted) setState(() {}); _toBottom(); });
    _connSub = bt.onConnectionChange.listen((_) { if (mounted) setState(() => _connected = bt.isConnected); });
  }

  void _toBottom() { WidgetsBinding.instance.addPostFrameCallback((_) { if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 200), curve: Curves.easeOut); }); }

  Future<void> _send() async {
    final t = _ctrl.text.trim(); if (t.isEmpty) return; _ctrl.clear();
    try { await bt.sendMessage(t); } catch (_) {} if (mounted) setState(() {}); _toBottom();
  }

  String _fmt(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  void dispose() { _msgSub?.cancel(); _connSub?.cancel(); _ctrl.dispose(); _scroll.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final msgs = bt.messages;
    return SafeArea(child: Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(20, 20, 20, 8), child: _Header('Chat', Icons.chat_bubble, _connected ? 'Conectado por Bluetooth' : 'Sin conexion')),
      if (_connected) Container(margin: const EdgeInsets.symmetric(horizontal: 20), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5), decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(8)), child: Row(children: [const Icon(Icons.bluetooth_connected, color: Colors.white, size: 14), const SizedBox(width: 6), Text('Conectado a ${bt.connectedName}', style: const TextStyle(color: Colors.white, fontSize: 11))])),
      Expanded(child: msgs.isEmpty ? Center(child: Text(_connected ? 'Escribe un mensaje' : 'Conecta un dispositivo primero', style: TextStyle(color: Colors.white.withOpacity(0.15)), textAlign: TextAlign.center)) : ListView.builder(controller: _scroll, padding: const EdgeInsets.symmetric(horizontal: 20), itemCount: msgs.length, itemBuilder: (_, i) { final m = msgs[i]; return Align(alignment: m.mine ? Alignment.centerRight : Alignment.centerLeft, child: Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), constraints: const BoxConstraints(maxWidth: 280), decoration: BoxDecoration(color: m.mine ? Colors.white : Colors.white.withOpacity(0.08), borderRadius: BorderRadius.only(topLeft: const Radius.circular(14), topRight: const Radius.circular(14), bottomLeft: Radius.circular(m.mine ? 14 : 4), bottomRight: Radius.circular(m.mine ? 4 : 14))), child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [Text(m.text, style: TextStyle(color: m.mine ? Colors.black : Colors.white, fontSize: 14)), const SizedBox(height: 4), Text(_fmt(m.time), style: TextStyle(color: m.mine ? Colors.black38 : Colors.white.withOpacity(0.25), fontSize: 10))])); })),
      Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), child: Row(children: [Expanded(child: TextField(controller: _ctrl, style: const TextStyle(color: Colors.white), decoration: InputDecoration(hintText: _connected ? 'Mensaje...' : 'Sin conexion', hintStyle: TextStyle(color: Colors.white.withOpacity(0.15)), filled: true, fillColor: Colors.white.withOpacity(0.04), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white24))), onSubmitted: (_) => _send())), const SizedBox(width: 8), FilledButton(onPressed: _connected ? _send : null, style: FilledButton.styleFrom(padding: const EdgeInsets.all(14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), disabledBackgroundColor: Colors.white12), child: const Icon(Icons.send, size: 20))])),
    ]));
  }
}

// ─────────────────────────────────────────────
// VAULT HOME — 6 secciones con acceso directo
// ─────────────────────────────────────────────
class VaultHomePage extends StatelessWidget {
  const VaultHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final sections = [
      _VaultSection(Icons.local_hospital, 'Primeros Auxilios', '12 protocolos de emergencia', Colors.redAccent, const FirstAidPage()),
      _VaultSection(Icons.terrain, 'Guias de Supervivencia', '15 guias esenciales', Colors.orangeAccent, const GuidesPage()),
      _VaultSection(Icons.book, 'Diccionario', '298 terminos medicos', Colors.purpleAccent, const DictionaryPage()),
      _VaultSection(Icons.article, 'Wikipedia Offline', '61 articulos en 6 categorias', Colors.tealAccent, const WikipediaPage()),
      _VaultSection(Icons.map, 'Mapa de Emergencias', '54 puntos en Colombia', Colors.greenAccent, const EmergencyMapPage()),
      _VaultSection(Icons.translate, 'Traductor Offline', '9 idiomas disponibles', Colors.blueAccent, const TranslatorPage()),
    ];

    return SafeArea(child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _Header('Vault', Icons.folder, 'Recursos offline'),
      const SizedBox(height: 8),
      Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.white.withOpacity(0.03), borderRadius: BorderRadius.circular(8)), child: Row(children: [const Icon(Icons.cloud_off, color: Colors.white24, size: 16), const SizedBox(width: 8), Expanded(child: Text('Todo el contenido funciona sin internet. Datos guardados en tu telefono.', style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11)))])),
      const SizedBox(height: 16),
      ...sections.map((s) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        child: Material(color: Colors.white.withOpacity(0.04), borderRadius: BorderRadius.circular(14), child: InkWell(borderRadius: BorderRadius.circular(14), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => s.page)), child: Padding(padding: const EdgeInsets.all(16), child: Row(children: [
          Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: s.color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)), child: Icon(s.icon, color: s.color, size: 24)),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(s.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)), const SizedBox(height: 2), Text(s.subtitle, style: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 12))])),
          const Icon(Icons.chevron_right, color: Colors.white24, size: 22),
        ])))),
      )),
      const SizedBox(height: 16),
      const _VaultSearchButton(),
    ])));
  }
}

class _VaultSection { final IconData icon; final String title; final String subtitle; final Color color; final Widget page; const _VaultSection(this.icon, this.title, this.subtitle, this.color, this.page); }

class _VaultSearchButton extends StatelessWidget {
  const _VaultSearchButton();
  @override
  Widget build(BuildContext context) {
    return SizedBox(width: double.infinity, child: OutlinedButton.icon(
      icon: const Icon(Icons.search, color: Colors.white54),
      label: const Text('Busqueda Global', style: TextStyle(color: Colors.white70, fontSize: 14)),
      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const VaultSearchPage())),
      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), side: BorderSide(color: Colors.white.withOpacity(0.1)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
    ));
  }
}

// ─────────────────────────────────────────────
// PRIMEROS AUXILIOS
// ─────────────────────────────────────────────
class FirstAidPage extends StatefulWidget { const FirstAidPage({super.key}); @override State<FirstAidPage> createState() => _FirstAidPageState(); }

class _FirstAidPageState extends State<FirstAidPage> {
  List<dynamic> _items = []; bool _loading = true;
  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async { try { final s = await rootBundle.loadString('assets/vault/first_aid/primeros_auxilios.json'); final d = json.decode(s); setState(() { _items = d['protocolos'] ?? []; _loading = false; }); } catch (_) { if (mounted) setState(() => _loading = false); } }

  Color _pColor(String? p) => p?.toLowerCase() == 'critica' ? Colors.redAccent : p?.toLowerCase() == 'alta' ? Colors.orangeAccent : Colors.white38;

  @override
  Widget build(BuildContext context) {
    return Scaffold(backgroundColor: const Color(0xFF0A0A0A), appBar: AppBar(backgroundColor: const Color(0xFF111111), title: const Text('Primeros Auxilios', style: TextStyle(color: Colors.white)), iconTheme: const IconThemeData(color: Colors.white)),
      body: _loading ? const Center(child: CircularProgressIndicator(color: Colors.white)) : ListView.builder(padding: const EdgeInsets.all(16), itemCount: _items.length, itemBuilder: (_, i) { final it = _items[i] as Map<String, dynamic>; final p = it['prioridad'] ?? ''; return Container(margin: const EdgeInsets.only(bottom: 8), child: Material(color: Colors.white.withOpacity(0.04), borderRadius: BorderRadius.circular(12), child: ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6), leading: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: _pColor(p).withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: Icon(Icons.local_hospital, color: _pColor(p), size: 20)), title: Text(it['titulo'] ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)), subtitle: Text(it['resumen'] ?? '', style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 11), maxLines: 2, overflow: TextOverflow.ellipsis), trailing: p.isNotEmpty ? Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1), decoration: BoxDecoration(color: _pColor(p).withOpacity(0.15), borderRadius: BorderRadius.circular(3)), child: Text(p.toUpperCase(), style: TextStyle(color: _pColor(p), fontSize: 8, fontWeight: FontWeight.w700))) : null, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _DetailPage(title: it['titulo'] ?? '', item: it)))))); }));
  }
}

// ─────────────────────────────────────────────
// GUIAS DE SUPERVIVENCIA
// ─────────────────────────────────────────────
class GuidesPage extends StatefulWidget { const GuidesPage({super.key}); @override State<GuidesPage> createState() => _GuidesPageState(); }

class _GuidesPageState extends State<GuidesPage> {
  List<dynamic> _items = []; bool _loading = true;
  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async { try { final s = await rootBundle.loadString('assets/vault/guides/supervivencia.json'); final d = json.decode(s); setState(() { _items = d['guias'] ?? []; _loading = false; }); } catch (_) { if (mounted) setState(() => _loading = false); } }

  @override
  Widget build(BuildContext context) {
    return Scaffold(backgroundColor: const Color(0xFF0A0A0A), appBar: AppBar(backgroundColor: const Color(0xFF111111), title: const Text('Guias de Supervivencia', style: TextStyle(color: Colors.white)), iconTheme: const IconThemeData(color: Colors.white)),
      body: _loading ? const Center(child: CircularProgressIndicator(color: Colors.white)) : ListView.builder(padding: const EdgeInsets.all(16), itemCount: _items.length, itemBuilder: (_, i) { final it = _items[i] as Map<String, dynamic>; final cat = it['categoria'] ?? ''; return Container(margin: const EdgeInsets.only(bottom: 8), child: Material(color: Colors.white.withOpacity(0.04), borderRadius: BorderRadius.circular(12), child: ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6), leading: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(8)), child: Icon(Icons.terrain, color: Colors.white54, size: 20)), title: Text(it['titulo'] ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)), subtitle: Text(it['resumen'] ?? '', style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 11), maxLines: 2, overflow: TextOverflow.ellipsis), trailing: cat.isNotEmpty ? Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1), decoration: BoxDecoration(color: Colors.white.withOpacity(0.08), borderRadius: BorderRadius.circular(3)), child: Text(cat.toUpperCase(), style: const TextStyle(color: Colors.white54, fontSize: 8, fontWeight: FontWeight.w600))) : null, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _DetailPage(title: it['titulo'] ?? '', item: it)))))); }));
  }
}

// ─────────────────────────────────────────────
// DICCIONARIO
// ─────────────────────────────────────────────
class DictionaryPage extends StatefulWidget { const DictionaryPage({super.key}); @override State<DictionaryPage> createState() => _DictionaryPageState(); }

class _DictionaryPageState extends State<DictionaryPage> {
  List<dynamic> _all = []; List<dynamic> _filtered = []; bool _loading = true; final _searchCtrl = TextEditingController();

  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async { try { final s = await rootBundle.loadString('assets/vault/dictionary/diccionario_index.json'); final d = json.decode(s); setState(() { _all = d['terminos'] ?? []; _filtered = _all; _loading = false; }); } catch (_) { if (mounted) setState(() => _loading = false); } }

  void _filter(String q) { setState(() { _filtered = q.isEmpty ? _all : _all.where((t) { final m = t as Map<String, dynamic>; return (m['palabra'] ?? '').toString().toLowerCase().contains(q.toLowerCase()) || (m['definicion'] ?? '').toString().toLowerCase().contains(q.toLowerCase()); }).toList(); }); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(backgroundColor: const Color(0xFF0A0A0A), appBar: AppBar(backgroundColor: const Color(0xFF111111), title: const Text('Diccionario', style: TextStyle(color: Colors.white)), iconTheme: const IconThemeData(color: Colors.white)),
      body: Column(children: [
        Padding(padding: const EdgeInsets.all(12), child: TextField(controller: _searchCtrl, style: const TextStyle(color: Colors.white), onChanged: _filter, decoration: InputDecoration(hintText: 'Buscar termino...', hintStyle: TextStyle(color: Colors.white.withOpacity(0.2)), prefixIcon: const Icon(Icons.search, color: Colors.white38), filled: true, fillColor: Colors.white.withOpacity(0.04), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white24))))),
        Expanded(child: _loading ? const Center(child: CircularProgressIndicator(color: Colors.white)) : _filtered.isEmpty ? Center(child: Text('Sin resultados', style: TextStyle(color: Colors.white24))) : ListView.builder(itemCount: _filtered.length, itemBuilder: (_, i) { final it = _filtered[i] as Map<String, dynamic>; return Container(margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3), child: Material(color: Colors.white.withOpacity(0.04), borderRadius: BorderRadius.circular(10), child: ListTile(dense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), title: Text(it['palabra'] ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)), subtitle: Text(it['definicion'] ?? '', style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11), maxLines: 2, overflow: TextOverflow.ellipsis), trailing: Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1), decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(3)), child: Text((it['categoria'] ?? '').toString().toUpperCase(), style: const TextStyle(color: Colors.white38, fontSize: 8, fontWeight: FontWeight.w600))), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _DictDetail(item: it)))))); })),
      ]),
    );
  }
}

class _DictDetail extends StatelessWidget {
  final Map<String, dynamic> item;
  const _DictDetail({required this.item});
  @override
  Widget build(BuildContext context) {
    return Scaffold(backgroundColor: const Color(0xFF0A0A0A), appBar: AppBar(backgroundColor: const Color(0xFF111111), title: Text(item['palabra'] ?? '', style: const TextStyle(color: Colors.white)), iconTheme: const IconThemeData(color: Colors.white)),
      body: SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(item['palabra'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        Text(item['definicion'] ?? '', style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 14, height: 1.6)),
        if ((item['sinonimos'] as List?)?.isNotEmpty ?? false) ...[ const SizedBox(height: 16), const Text('Sinonimos:', style: TextStyle(color: Colors.white54, fontWeight: FontWeight.w600)), const SizedBox(height: 6), Wrap(spacing: 6, children: (item['sinonimos'] as List).map((s) => Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(6)), child: Text(s.toString(), style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12)))).toList())],
      ])),
    );
  }
}

// ─────────────────────────────────────────────
// WIKIPEDIA OFFLINE
// ─────────────────────────────────────────────
class WikipediaPage extends StatefulWidget { const WikipediaPage({super.key}); @override State<WikipediaPage> createState() => _WikipediaPageState(); }

class _WikipediaPageState extends State<WikipediaPage> {
  Map<String, dynamic> _data = {}; List<dynamic> _articles = []; bool _loading = true; String? _selectedCat;

  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async { try { final s = await rootBundle.loadString('assets/vault/wikipedia/wikipedia_offline.json'); final d = json.decode(s); setState(() { _data = d; _loading = false; _selectCat(null); }); } catch (_) { if (mounted) setState(() => _loading = false); } }

  void _selectCat(String? cat) {
    _selectedCat = cat;
    if (cat == null) { _articles = []; for (final c in (_data['categorias'] as Map<String, dynamic>).values) { final arts = (c as Map<String, dynamic>)['articulos'] as List? ?? []; _articles.addAll(arts); } }
    else { final c = (_data['categorias'] as Map<String, dynamic>)[cat] as Map<String, dynamic>?; _articles = c?['articulos'] as List? ?? []; }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final cats = (_data['categorias'] as Map<String, dynamic>?)?.keys.toList() ?? [];
    return Scaffold(backgroundColor: const Color(0xFF0A0A0A), appBar: AppBar(backgroundColor: const Color(0xFF111111), title: const Text('Wikipedia Offline', style: TextStyle(color: Colors.white)), iconTheme: const IconThemeData(color: Colors.white)),
      body: _loading ? const Center(child: CircularProgressIndicator(color: Colors.white)) : Column(children: [
        SizedBox(height: 44, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), children: [
          Padding(padding: const EdgeInsets.only(right: 6), child: FilterChip(label: const Text('Todo'), selected: _selectedCat == null, onSelected: (_) => _selectCat(null), backgroundColor: Colors.white.withOpacity(0.05), selectedColor: Colors.white.withOpacity(0.15), labelStyle: TextStyle(color: _selectedCat == null ? Colors.white : Colors.white54, fontSize: 12))),
          ...cats.map((c) => Padding(padding: const EdgeInsets.only(right: 6), child: FilterChip(label: Text(c[0].toUpperCase() + c.substring(1)), selected: _selectedCat == c, onSelected: (_) => _selectCat(c), backgroundColor: Colors.white.withOpacity(0.05), selectedColor: Colors.white.withOpacity(0.15), labelStyle: TextStyle(color: _selectedCat == c ? Colors.white : Colors.white54, fontSize: 12)))),
        ]),
        Expanded(child: _articles.isEmpty ? Center(child: Text('Sin articulos', style: TextStyle(color: Colors.white24))) : ListView.builder(itemCount: _articles.length, itemBuilder: (_, i) { final it = _articles[i] as Map<String, dynamic>; return Container(margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3), child: Material(color: Colors.white.withOpacity(0.04), borderRadius: BorderRadius.circular(10), child: ListTile(dense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), title: Text(it['titulo'] ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)), subtitle: Text(it['resumen'] ?? '', style: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 11), maxLines: 2, overflow: TextOverflow.ellipsis), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _WikiDetail(item: it)))))); })),
      ]),
    );
  }
}

class _WikiDetail extends StatelessWidget {
  final Map<String, dynamic> item;
  const _WikiDetail({required this.item});
  @override
  Widget build(BuildContext context) {
    final sections = item['secciones'] as List? ?? [];
    return Scaffold(backgroundColor: const Color(0xFF0A0A0A), appBar: AppBar(backgroundColor: const Color(0xFF111111), title: Text(item['titulo'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 16)), iconTheme: const IconThemeData(color: Colors.white)),
      body: SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(item['resumen'] ?? '', style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 14, height: 1.6)),
        ...sections.map((s) { final sec = s as Map<String, dynamic>; return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [ const SizedBox(height: 16), Text(sec['titulo'] ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)), const SizedBox(height: 6), Text(sec['contenido'] ?? '', style: TextStyle(color: Colors.white.withOpacity(0.65), fontSize: 13, height: 1.5)) ]; }); }),
      ])),
    );
  }
}

// ─────────────────────────────────────────────
// MAPA DE EMERGENCIAS
// ─────────────────────────────────────────────
class EmergencyMapPage extends StatefulWidget { const EmergencyMapPage({super.key}); @override State<EmergencyMapPage> createState() => _EmergencyMapPageState(); }

class _EmergencyMapPageState extends State<EmergencyMapPage> {
  List<dynamic> _features = []; bool _loading = true; String _filter = 'all';

  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async { try { final s = await rootBundle.loadString('assets/vault/maps/colombia_emergencias.geojson'); final d = json.decode(s); setState(() { _features = d['features'] ?? []; _loading = false; }); } catch (_) { if (mounted) setState(() => _loading = false); } }

  IconData _typeIcon(String? t) { switch (t) { case 'capital_nacional': return Icons.location_city; case 'capital_departamento': return Icons.location_city; case 'ciudad_principal': return Icons.location_on; case 'hospital_referencia': return Icons.local_hospital; default: return Icons.place; } }
  Color _typeColor(String? t) { switch (t) { case 'capital_nacional': return Colors.white; case 'capital_departamento': return Colors.grey; case 'hospital_referencia': return Colors.redAccent; default: return Colors.white54; } }

  List<dynamic> get _filtered => _filter == 'all' ? _features : _features.where((f) { final p = (f as Map<String, dynamic>)['properties'] as Map<String, dynamic>?; final t = p?['tipo'] ?? ''; if (_filter == 'capitales') return t == 'capital_nacional' || t == 'capital_departamento'; if (_filter == 'hospitales') return t == 'hospital_referencia'; return true; }).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(backgroundColor: const Color(0xFF0A0A0A), appBar: AppBar(backgroundColor: const Color(0xFF111111), title: const Text('Emergencias Colombia', style: TextStyle(color: Colors.white)), iconTheme: const IconThemeData(color: Colors.white)),
      body: _loading ? const Center(child: CircularProgressIndicator(color: Colors.white)) : Column(children: [
        SizedBox(height: 44, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), children: [
          _mapFilter('Todo', 'all'), _mapFilter('Capitales', 'capitales'), _mapFilter('Hospitales', 'hospitales'), _mapFilter('Ciudades', 'ciudades'),
        ])),
        Expanded(child: _filtered.isEmpty ? Center(child: Text('Sin resultados', style: TextStyle(color: Colors.white24))) : ListView.builder(itemCount: _filtered.length, itemBuilder: (_, i) { final f = _filtered[i] as Map<String, dynamic>; final p = f['properties'] as Map<String, dynamic>? ?? {}; final t = p['tipo'] ?? ''; return Container(margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3), child: Material(color: Colors.white.withOpacity(0.04), borderRadius: BorderRadius.circular(10), child: ListTile(dense: true, leading: Icon(_typeIcon(t), color: _typeColor(t), size: 20), title: Text(p['nombre'] ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)), subtitle: Text('${p['departamento'] ?? ''} - ${p['descripcion'] ?? ''}', style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis), trailing: p['emergencia'] != null ? Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1), decoration: BoxDecoration(color: Colors.red.withOpacity(0.12), borderRadius: BorderRadius.circular(3)), child: Text('${p['emergencia']}', style: const TextStyle(color: Colors.redAccent, fontSize: 9, fontWeight: FontWeight.w700))) : null, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _MapDetailPage(props: p)))))); })),
      ]),
    );
  }

  Widget _mapFilter(String label, String val) => Padding(padding: const EdgeInsets.only(right: 6), child: FilterChip(label: Text(label), selected: _filter == val, onSelected: (_) => setState(() => _filter = val), backgroundColor: Colors.white.withOpacity(0.05), selectedColor: Colors.white.withOpacity(0.15), labelStyle: TextStyle(color: _filter == val ? Colors.white : Colors.white54, fontSize: 12)));
}

class _MapDetailPage extends StatelessWidget {
  final Map<String, dynamic> props;
  const _MapDetailPage({required this.props});
  @override
  Widget build(BuildContext context) {
    return Scaffold(backgroundColor: const Color(0xFF0A0A0A), appBar: AppBar(backgroundColor: const Color(0xFF111111), title: Text(props['nombre'] ?? '', style: const TextStyle(color: Colors.white)), iconTheme: const IconThemeData(color: Colors.white)),
      body: SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(props['nombre'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        if (props['departamento'] != null) Text(props['departamento'], style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 14)),
        const SizedBox(height: 12),
        Text(props['descripcion'] ?? '', style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 14, height: 1.6)),
        const SizedBox(height: 16),
        _infoRow(Icons.location_on, 'Tipo', props['tipo'] ?? ''),
        if (props['poblacion'] != null) _infoRow(Icons.people, 'Poblacion', '${props['poblacion']}'),
        if (props['altitud'] != null) _infoRow(Icons.terrain, 'Altitud', '${props['altitud']}m'),
        if (props['aeropuerto'] == true) _infoRow(Icons.flight, 'Aeropuerto', 'Si'),
        if (props['hospital'] == true) _infoRow(Icons.local_hospital, 'Hospital', 'Si'),
        if (props['emergencia'] != null) _infoRow(Icons.phone, 'Emergencias', '${props['emergencia']}'),
      ])),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(children: [Icon(icon, color: Colors.white38, size: 18), const SizedBox(width: 10), Text(label, style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 13)), const SizedBox(width: 8), Expanded(child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)))]));
}

// ─────────────────────────────────────────────
// TRADUCTOR OFFLINE
// ─────────────────────────────────────────────
class TranslatorPage extends StatefulWidget { const TranslatorPage({super.key}); @override State<TranslatorPage> createState() => _TranslatorPageState(); }

class _TranslatorPageState extends State<TranslatorPage> {
  Map<String, dynamic> _config = {}; Map<String, dynamic> _langPacks = {}; bool _loading = true;
  String _srcLang = 'es'; String _tgtLang = 'en'; final _inputCtrl = TextEditingController(); String _output = '';

  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    try {
      final s = await rootBundle.loadString('assets/vault/translator/translator_config.json');
      final d = json.decode(s);
      final Map<String, dynamic> packs = {};
      for (final code in ['es', 'en', 'pt', 'fr', 'de', 'it', 'ru', 'zh', 'ja', 'ko']) {
        try { final ps = await rootBundle.loadString('assets/vault/translator/lang_packs/$code.json'); packs[code] = json.decode(ps); } catch (_) {}
      }
      setState(() { _config = d; _langPacks = packs; _loading = false; });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  String _langName(String code) { final pack = _langPacks[code] as Map<String, dynamic>?; return pack?['nombre'] ?? code.toUpperCase(); }

  void _translate() {
    final input = _inputCtrl.text.trim().toLowerCase();
    if (input.isEmpty) { setState(() => _output = ''); return; }

    final srcPack = _langPacks[_srcLang] as Map<String, dynamic>?;
    final tgtPack = _langPacks[_tgtLang] as Map<String, dynamic>?;

    if (srcPack == null || tgtPack == null) { setState(() => _output = 'Paquete de idioma no disponible'); return; }

    // Simple dictionary lookup from source lang
    final phrases = srcPack['frases'] as Map<String, dynamic>? ?? {};
    final tgtPhrases = tgtPack['frases'] as Map<String, dynamic>? ?? {};

    // Find matching key in source
    String? foundKey;
    for (final entry in phrases.entries) {
      if (entry.value.toString().toLowerCase() == input) { foundKey = entry.key; break; }
    }

    if (foundKey != null && tgtPhrases.containsKey(foundKey)) {
      setState(() => _output = tgtPhrases[foundKey]);
    } else {
      // Try partial match
      for (final entry in phrases.entries) {
        if (entry.value.toString().toLowerCase().contains(input) || input.contains(entry.value.toString().toLowerCase())) {
          final k = entry.key;
          if (tgtPhrases.containsKey(k)) { setState(() => _output = tgtPhrases[k] ?? 'No encontrado'); return; }
        }
      }
      setState(() => _output = 'Traduccion no disponible para: "$input"\n\nNota: El traductor completo requiere el modelo NLLB-200 (350MB). Esta version incluye frases basicas offline.');
    }
  }

  @override
  void dispose() { _inputCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final langCodes = _langPacks.keys.toList();
    return Scaffold(backgroundColor: const Color(0xFF0A0A0A), appBar: AppBar(backgroundColor: const Color(0xFF111111), title: const Text('Traductor Offline', style: TextStyle(color: Colors.white)), iconTheme: const IconThemeData(color: Colors.white)),
      body: _loading ? const Center(child: CircularProgressIndicator(color: Colors.white)) : SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(children: [
        // Info
        Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.white.withOpacity(0.03), borderRadius: BorderRadius.circular(8)), child: Row(children: [const Icon(Icons.info_outline, color: Colors.white24, size: 16), const SizedBox(width: 8), Expanded(child: Text('Traductor offline con frases basicas. Modelo completo NLLB-200 (${_config['modelo_unificado']?['tamano_mb'] ?? 350}MB) disponible para descarga.', style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11)))])),
        const SizedBox(height: 16),
        // Language selectors
        Row(children: [
          Expanded(child: _langDropdown('De:', _srcLang, (v) => setState(() => _srcLang = v!))),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: IconButton(onPressed: () { setState(() { final tmp = _srcLang; _srcLang = _tgtLang; _tgtLang = tmp; }); }, icon: const Icon(Icons.swap_horiz, color: Colors.white54))),
          Expanded(child: _langDropdown('A:', _tgtLang, (v) => setState(() => _tgtLang = v!))),
        ]),
        const SizedBox(height: 16),
        // Input
        TextField(controller: _inputCtrl, style: const TextStyle(color: Colors.white), maxLines: 3, decoration: InputDecoration(hintText: 'Escribe texto para traducir...', hintStyle: TextStyle(color: Colors.white.withOpacity(0.2)), filled: true, fillColor: Colors.white.withOpacity(0.04), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white24)))),
        const SizedBox(height: 12),
        SizedBox(width: double.infinity, child: FilledButton.icon(icon: const Icon(Icons.translate), label: const Text('Traducir'), onPressed: _translate)),
        const SizedBox(height: 16),
        // Output
        if (_output.isNotEmpty) Container(width: double.infinity, padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white.withOpacity(0.1))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(_output, style: const TextStyle(color: Colors.white, fontSize: 15)), const SizedBox(height: 8), Row(mainAxisAlignment: MainAxisAlignment.end, children: [TextButton.icon(onPressed: () { Clipboard.setData(ClipboardData(text: _output)); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copiado!'), backgroundColor: Colors.grey)); }, icon: const Icon(Icons.copy, size: 14), label: const Text('Copiar', style: TextStyle(fontSize: 11)))]))])),
      ])),
    );
  }

  Widget _langDropdown(String label, String value, ValueChanged<String?> onChanged) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11)), const SizedBox(height: 4), Container(padding: const EdgeInsets.symmetric(horizontal: 12), decoration: BoxDecoration(color: Colors.white.withOpacity(0.04), borderRadius: BorderRadius.circular(8)), child: DropdownButton<String>(value: value, isExpanded: true, underline: const SizedBox(), dropdownColor: const Color(0xFF111111), style: const TextStyle(color: Colors.white, fontSize: 13), items: _langPacks.keys.map((c) => DropdownMenuItem(value: c, child: Text(_langName(c)))).toList(), onChanged: onChanged))]);
  }
}

// ─────────────────────────────────────────────
// BUSQUEDA GLOBAL DEL VAULT
// ─────────────────────────────────────────────
class VaultSearchPage extends StatefulWidget { const VaultSearchPage({super.key}); @override State<VaultSearchPage> createState() => _VaultSearchPageState(); }

class _VaultSearchPageState extends State<VaultSearchPage> {
  final _searchCtrl = TextEditingController(); List<Map<String, dynamic>> _results = []; bool _searched = false; bool _searching = false;

  Future<void> _search(String q) async {
    if (q.trim().isEmpty) { setState(() { _results = []; _searched = false; }); return; }
    setState(() => _searching = true);
    final ql = q.toLowerCase(); final List<Map<String, dynamic>> found = [];

    try { final s = await rootBundle.loadString('assets/vault/first_aid/primeros_auxilios.json'); final d = json.decode(s); for (final it in (d['protocolos'] ?? [])) { final m = it as Map<String, dynamic>; if ((m['titulo'] ?? '').toString().toLowerCase().contains(ql) || (m['resumen'] ?? '').toString().toLowerCase().contains(ql)) found.add({...m, '_type': 'first_aid'}); } } catch (_) {}
    try { final s = await rootBundle.loadString('assets/vault/guides/supervivencia.json'); final d = json.decode(s); for (final it in (d['guias'] ?? [])) { final m = it as Map<String, dynamic>; if ((m['titulo'] ?? '').toString().toLowerCase().contains(ql) || (m['resumen'] ?? '').toString().toLowerCase().contains(ql)) found.add({...m, '_type': 'guide'}); } } catch (_) {}
    try { final s = await rootBundle.loadString('assets/vault/dictionary/diccionario_index.json'); final d = json.decode(s); for (final it in (d['terminos'] ?? [])) { final m = it as Map<String, dynamic>; if ((m['palabra'] ?? '').toString().toLowerCase().contains(ql) || (m['definicion'] ?? '').toString().toLowerCase().contains(ql)) found.add({...m, '_type': 'dict'}); } } catch (_) {}
    try { final s = await rootBundle.loadString('assets/vault/wikipedia/wikipedia_offline.json'); final d = json.decode(s); for (final cat in (d['categorias'] as Map<String, dynamic>).values) { for (final it in (cat as Map<String, dynamic>)['articulos'] as List? ?? []) { final m = it as Map<String, dynamic>; if ((m['titulo'] ?? '').toString().toLowerCase().contains(ql) || (m['resumen'] ?? '').toString().toLowerCase().contains(ql)) found.add({...m, '_type': 'wiki'}); } } } catch (_) {}

    if (mounted) setState(() { _results = found; _searched = true; _searching = false; });
  }

  IconData _tIcon(String t) => t == 'first_aid' ? Icons.local_hospital : t == 'guide' ? Icons.terrain : t == 'dict' ? Icons.book : Icons.article;
  String _tLabel(String t) => t == 'first_aid' ? 'Auxilio' : t == 'guide' ? 'Guia' : t == 'dict' ? 'Diccionario' : 'Wiki';

  @override
  Widget build(BuildContext context) {
    return Scaffold(backgroundColor: const Color(0xFF0A0A0A), appBar: AppBar(backgroundColor: const Color(0xFF111111), title: const Text('Busqueda Vault', style: TextStyle(color: Colors.white)), iconTheme: const IconThemeData(color: Colors.white)),
      body: Column(children: [
        Padding(padding: const EdgeInsets.all(12), child: TextField(controller: _searchCtrl, style: const TextStyle(color: Colors.white), onSubmitted: _search, decoration: InputDecoration(hintText: 'Buscar en todo el vault...', hintStyle: TextStyle(color: Colors.white.withOpacity(0.2)), prefixIcon: _searching ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white38)) : const Icon(Icons.search, color: Colors.white38), suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward, color: Colors.white38), onPressed: () => _search(_searchCtrl.text)), filled: true, fillColor: Colors.white.withOpacity(0.04), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white24))))),
        Expanded(child: !_searched ? Center(child: Text('Escribe para buscar', style: TextStyle(color: Colors.white24))) : _results.isEmpty ? Center(child: Text('Sin resultados', style: TextStyle(color: Colors.white24))) : ListView.builder(itemCount: _results.length, itemBuilder: (_, i) { final r = _results[i]; final type = r['_type'] as String? ?? ''; final title = r['titulo'] ?? r['palabra'] ?? 'Sin titulo'; final sub = r['resumen'] ?? r['definicion'] ?? ''; return Container(margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3), child: Material(color: Colors.white.withOpacity(0.04), borderRadius: BorderRadius.circular(10), child: ListTile(dense: true, leading: Icon(_tIcon(type), color: Colors.white54, size: 18), title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)), subtitle: Text(sub, style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis), trailing: Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1), decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(3)), child: Text(_tLabel(type), style: const TextStyle(color: Colors.white38, fontSize: 8, fontWeight: FontWeight.w600))), onTap: () { if (type == 'first_aid' || type == 'guide') Navigator.push(context, MaterialPageRoute(builder: (_) => _DetailPage(title: title, item: r))); else if (type == 'dict') Navigator.push(context, MaterialPageRoute(builder: (_) => _DictDetail(item: r))); else if (type == 'wiki') Navigator.push(context, MaterialPageRoute(builder: (_) => _WikiDetail(item: r))); }))); })),
      ]),
    );
  }
}

// ─────────────────────────────────────────────
// DETAIL PAGE GENERIC (Primeros Auxilios + Guias)
// ─────────────────────────────────────────────
class _DetailPage extends StatelessWidget {
  final String title; final Map<String, dynamic> item;
  const _DetailPage({required this.title, required this.item});

  @override
  Widget build(BuildContext context) {
    final steps = item['pasos'] as List? ?? [];
    final warnings = item['advertencias'] as List? ?? [];
    final references = item['referencias'] as List? ?? [];
    final help = item['cuando_buscar_ayuda'] ?? '';

    return Scaffold(backgroundColor: const Color(0xFF0A0A0A), appBar: AppBar(backgroundColor: const Color(0xFF111111), title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 16)), iconTheme: const IconThemeData(color: Colors.white)),
      body: SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (item['resumen'] != null) ...[ Text(item['resumen'], style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 14, height: 1.6)), const SizedBox(height: 16) ],
        if (steps.isNotEmpty) ...[ const Text('Pasos:', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)), const SizedBox(height: 8), ...steps.asMap().entries.map((e) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Container(width: 24, height: 24, margin: const EdgeInsets.only(right: 10), decoration: BoxDecoration(color: Colors.white.withOpacity(0.08), borderRadius: BorderRadius.circular(12)), child: Center(child: Text('${e.key + 1}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)))), Expanded(child: Text(e.value.toString(), style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13)))]))) ],
        if (warnings.isNotEmpty) ...[ const SizedBox(height: 16), const Text('Advertencias:', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w700, fontSize: 14)), const SizedBox(height: 8), ...warnings.map((w) => Container(margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.red.withOpacity(0.04), borderRadius: BorderRadius.circular(8)), child: Row(children: [const Icon(Icons.warning, color: Colors.redAccent, size: 16), const SizedBox(width: 8), Expanded(child: Text(w.toString(), style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12)))]))) ],
        if (help.toString().isNotEmpty) ...[ const SizedBox(height: 16), const Text('Cuando buscar ayuda:', style: TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.w700, fontSize: 14)), const SizedBox(height: 6), Text(help.toString(), style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13, height: 1.5)) ],
        if (references.isNotEmpty) ...[ const SizedBox(height: 16), const Text('Referencias:', style: TextStyle(color: Colors.white54, fontWeight: FontWeight.w600, fontSize: 13)), const SizedBox(height: 4), ...references.map((r) => Padding(padding: const EdgeInsets.only(bottom: 2), child: Text('- $r', style: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 11)))) ],
      ])),
    );
  }
}

// ─────────────────────────────────────────────
// REUSABLE HEADER
// ─────────────────────────────────────────────
class _Header extends StatelessWidget {
  final String title; final IconData icon; final String subtitle;
  const _Header(this.title, this.icon, this.subtitle);
  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: Colors.white, size: 24)),
      const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)), const SizedBox(height: 2), Text(subtitle, style: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 12))])),
    ]);
  }
}
