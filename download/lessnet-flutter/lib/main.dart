import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const LessNetApp());
}

// ─────────────────────────────────────────────
// APP ROOT
// ─────────────────────────────────────────────
class LessNetApp extends StatelessWidget {
  const LessNetApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LessNet',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3B82F6),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

// ─────────────────────────────────────────────
// HOME — navegacion entre pantallas
// ─────────────────────────────────────────────
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _index = 0;

  final _pages = const [PermissionsPage(), ScanPage(), ChatPage()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_index],
      bottomNavigationBar: NavigationBar(
        backgroundColor: const Color(0xFF1E293B),
        selectedIndex: _index,
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
    _PermItem(
      'Ubicacion',
      Icons.location_on,
      Colors.orange,
      Permission.locationWhenInUse,
      'Requerida para BT scan en Android < 12',
    ),
    _PermItem(
      'Bluetooth Scan',
      Icons.bluetooth_searching,
      Colors.cyan,
      Permission.bluetoothScan,
      'Buscar dispositivos cercanos (Android 12+)',
    ),
    _PermItem(
      'Bluetooth Connect',
      Icons.bluetooth_connected,
      Colors.blue,
      Permission.bluetoothConnect,
      'Conectarse a dispositivos (Android 12+)',
    ),
    _PermItem(
      'Bluetooth Advertise',
      Icons.broadcast_on_personal,
      Colors.lightBlue,
      Permission.bluetoothAdvertise,
      'Hacerse visible para otros dispositivos',
    ),
  ];

  final Map<Permission, PermissionStatus> _statuses = {};
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _checkAll();
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
  }

  String _statusText(PermissionStatus? status) {
    if (status == null) return 'Verificando...';
    if (status.isGranted) return 'Concedido';
    if (status.isDenied) return 'Denegado';
    if (status.isPermanentlyDenied) return 'Denegado permanentemente';
    if (status.isRestricted) return 'Restringido';
    if (status.isLimited) return 'Limitado';
    return status.toString();
  }

  IconData _statusIcon(PermissionStatus? status) {
    if (status == null) return Icons.hourglass_empty;
    if (status.isGranted) return Icons.check_circle;
    if (status.isPermanentlyDenied) return Icons.lock;
    return Icons.cancel;
  }

  Color _statusColor(PermissionStatus? status) {
    if (status == null) return Colors.grey;
    if (status.isGranted) return Colors.greenAccent;
    if (status.isPermanentlyDenied) return Colors.redAccent;
    return Colors.redAccent;
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
            const SizedBox(height: 16),
            Expanded(
              child: ListView(
                children: _perms
                    .map((p) => _PermCard(
                          item: p,
                          status: _statuses[p.permission],
                          statusText: _statusText(_statuses[p.permission]),
                          statusIcon: _statusIcon(_statuses[p.permission]),
                          statusColor: _statusColor(_statuses[p.permission]),
                          onRequest: () async {
                            final s = await p.permission.request();
                            if (mounted) {
                              setState(() => _statuses[p.permission] = s);
                            }
                          },
                          onOpenSettings: () => openAppSettings(),
                        ))
                    .toList(),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: _loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
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
  final IconData statusIcon;
  final Color statusColor;
  final VoidCallback onRequest;
  final VoidCallback onOpenSettings;

  const _PermCard({
    required this.item,
    required this.status,
    required this.statusText,
    required this.statusIcon,
    required this.statusColor,
    required this.onRequest,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    final granted = status?.isGranted ?? false;
    final permanentlyDenied = status?.isPermanentlyDenied ?? false;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: item.color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(item.icon, color: item.color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14)),
                Text(item.desc,
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.5), fontSize: 11)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(statusIcon, color: statusColor, size: 14),
                    const SizedBox(width: 4),
                    Text(statusText,
                        style: TextStyle(
                            color: statusColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (status == null)
            const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2))
          else if (granted)
            const Icon(Icons.check_circle, color: Colors.greenAccent, size: 24)
          else if (permanentlyDenied)
            TextButton(
              onPressed: onOpenSettings,
              child: const Text('Ajustes', style: TextStyle(fontSize: 12)),
            )
          else
            TextButton(
              onPressed: onRequest,
              child: const Text('Pedir', style: TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// PAGINA 2: SCAN BLUETOOTH
// ─────────────────────────────────────────────
class ScanPage extends StatefulWidget {
  const ScanPage({super.key});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  final List<ScanResult> _results = [];
  bool _scanning = false;
  StreamSubscription? _scanSub;
  StreamSubscription? _scanningSub;
  BluetoothDevice? _connectedDevice;
  BluetoothConnectionState _connectionState =
      BluetoothConnectionState.disconnected;
  StreamSubscription? _connectionSub;

  Future<void> _startScan() async {
    // Verificar permisos primero
    final statuses = await [
      Permission.locationWhenInUse,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();

    final allGranted = statuses.values.every((s) => s.isGranted);
    if (!allGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Concede los permisos primero'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    _results.clear();
    setState(() => _scanning = true);

    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 8));

      _scanSub = FlutterBluePlus.scanResults.listen((results) {
        if (mounted) {
          setState(() {
            _results
              ..clear()
              ..addAll(results);
          });
        }
      });

      _scanningSub = FlutterBluePlus.isScanning.listen((scanning) {
        if (!scanning && mounted) {
          setState(() => _scanning = false);
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() => _scanning = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al escanear: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    try {
      await device.connect(timeout: const Duration(seconds: 10));
      _connectionSub = device.connectionState.listen((state) {
        if (mounted) {
          setState(() => _connectionState = state);
          if (state == BluetoothConnectionState.disconnected) {
            setState(() => _connectedDevice = null);
          }
        }
      });
      if (mounted) {
        setState(() {
          _connectedDevice = device;
          _connectionState = BluetoothConnectionState.connected;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Conectado a ${device.platformName}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al conectar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _disconnect() async {
    try {
      await _connectedDevice?.disconnect();
      if (mounted) {
        setState(() {
          _connectedDevice = null;
          _connectionState = BluetoothConnectionState.disconnected;
        });
      }
    } catch (e) {
      // ignore
    }
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _scanningSub?.cancel();
    _connectionSub?.cancel();
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Header(
              'Dispositivos',
              Icons.bluetooth_searching,
              _connectedDevice != null
                  ? 'Conectado: ${_connectedDevice!.platformName}'
                  : '${_results.length} encontrados',
            ),
            const SizedBox(height: 16),
            if (_connectedDevice != null)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.bluetooth_connected,
                        color: Colors.greenAccent, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _connectedDevice!.platformName.isEmpty
                                ? 'Dispositivo'
                                : _connectedDevice!.platformName,
                            style: const TextStyle(
                                color: Colors.greenAccent,
                                fontWeight: FontWeight.w600,
                                fontSize: 14),
                          ),
                          Text(
                            _connectedDevice!.remoteId.toString(),
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.5),
                                fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: _disconnect,
                      child: const Text('Desconectar',
                          style: TextStyle(color: Colors.redAccent)),
                    ),
                  ],
                ),
              ),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: _scanning
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.search),
                label:
                    Text(_scanning ? 'Buscando...' : 'Buscar dispositivos'),
                onPressed: _scanning ? null : _startScan,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _results.isEmpty
                  ? Center(
                      child: Text(
                        _scanning
                            ? 'Buscando dispositivos cercanos...'
                            : 'Presiona Buscar para escanear',
                        style: TextStyle(color: Colors.white.withOpacity(0.4)),
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.builder(
                      itemCount: _results.length,
                      itemBuilder: (_, i) => _DeviceCard(
                        _results[i],
                        isConnected: _connectedDevice?.remoteId ==
                            _results[i].device.remoteId,
                        onConnect: () =>
                            _connectToDevice(_results[i].device),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  final ScanResult result;
  final bool isConnected;
  final VoidCallback onConnect;

  const _DeviceCard(this.result,
      {required this.isConnected, required this.onConnect});

  @override
  Widget build(BuildContext context) {
    final name = result.device.platformName.isEmpty
        ? 'Dispositivo desconocido'
        : result.device.platformName;
    final rssi = result.rssi;
    final signalColor = rssi > -60
        ? Colors.greenAccent
        : rssi > -80
            ? Colors.orangeAccent
            : Colors.redAccent;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isConnected
            ? Colors.green.withOpacity(0.08)
            : Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: isConnected
                ? Colors.green.withOpacity(0.3)
                : Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        children: [
          Icon(
            isConnected ? Icons.bluetooth_connected : Icons.bluetooth,
            color: isConnected ? Colors.greenAccent : Colors.blue,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: TextStyle(
                        color:
                            isConnected ? Colors.greenAccent : Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14)),
                Text(result.device.remoteId.toString(),
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.4), fontSize: 11)),
              ],
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: signalColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text('$rssi dBm',
                style: TextStyle(
                    color: signalColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 8),
          if (!isConnected)
            TextButton(
              onPressed: onConnect,
              child: const Text('Conectar',
                  style: TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// PAGINA 3: CHAT
// ─────────────────────────────────────────────
class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final List<_Message> _messages = [];

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _messages.add(_Message(text: text, mine: true, time: DateTime.now()));
      _controller.clear();
    });
    // TODO: enviar por Bluetooth con flutter_blue_plus
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: _Header('Chat', Icons.chat_bubble, 'Via Bluetooth local'),
          ),
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.bluetooth_disabled,
                            size: 48,
                            color: Colors.white.withOpacity(0.15)),
                        const SizedBox(height: 12),
                        Text(
                          'Conectate a un dispositivo\ny empieza a chatear',
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.3)),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: _messages.length,
                    itemBuilder: (_, i) => _Bubble(
                      _messages[i],
                      formatTime: _formatTime,
                    ),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Escribe un mensaje...',
                      hintStyle:
                          TextStyle(color: Colors.white.withOpacity(0.3)),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.07),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  icon: const Icon(Icons.send_rounded),
                  onPressed: _send,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Message {
  final String text;
  final bool mine;
  final DateTime time;
  _Message({required this.text, required this.mine, required this.time});
}

class _Bubble extends StatelessWidget {
  final _Message msg;
  final String Function(DateTime) formatTime;

  const _Bubble(this.msg, {required this.formatTime});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: msg.mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: const BoxConstraints(maxWidth: 280),
        decoration: BoxDecoration(
          color: msg.mine
              ? const Color(0xFF1D4ED8)
              : Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(msg.mine ? 14 : 4),
            bottomRight: Radius.circular(msg.mine ? 4 : 14),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(msg.text,
                style: const TextStyle(color: Colors.white, fontSize: 14)),
            const SizedBox(height: 4),
            Text(formatTime(msg.time),
                style: TextStyle(
                    color: Colors.white.withOpacity(0.4), fontSize: 10)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// WIDGET REUTILIZABLE: HEADER DE PAGINA
// ─────────────────────────────────────────────
class _Header extends StatelessWidget {
  final String title;
  final IconData icon;
  final String subtitle;

  const _Header(this.title, this.icon, this.subtitle);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF60A5FA), size: 28),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700)),
            Text(subtitle,
                style: TextStyle(
                    color: Colors.white.withOpacity(0.5), fontSize: 12)),
          ],
        ),
      ],
    );
  }
}
