import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
        backgroundColor: const Color(0xFF1E293B),
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
        backgroundColor: const Color(0xFF1E293B),
        child: SafeArea(
          child: Column(
            children: [
              const DrawerHeader(
                decoration: BoxDecoration(color: Color(0xFF0F172A)),
                child: Row(
                  children: [
                    Icon(Icons.hub, color: Color(0xFF60A5FA), size: 32),
                    SizedBox(width: 12),
                    Text('LessNet Vault',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              _drawerItem(Icons.local_hospital, 'Primeros Auxilios', 3,
                  Colors.redAccent),
              _drawerItem(Icons.terrain, 'Guias de Supervivencia', 4,
                  Colors.orangeAccent),
              _drawerItem(
                  Icons.search, 'Vault / Buscar', 5, Colors.blueAccent),
              const Divider(color: Colors.white10),
              _drawerItem(
                  Icons.shield, 'Permisos', 0, Colors.greenAccent),
              _drawerItem(
                  Icons.bluetooth, 'Dispositivos', 1, Colors.blueAccent),
              _drawerItem(
                  Icons.chat, 'Chat', 2, Colors.cyanAccent),
              const Spacer(),
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Contenido offline para emergencias',
                    style: TextStyle(color: Colors.white38, fontSize: 11)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _drawerItem(IconData icon, String title, int pageIdx, Color color) {
    return ListTile(
      leading: Icon(icon, color: color, size: 22),
      title: Text(title,
          style: const TextStyle(color: Colors.white, fontSize: 14)),
      onTap: () {
        setState(() => _index = pageIdx);
        Navigator.pop(context);
      },
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
    _PermItem('Ubicacion', Icons.location_on, Colors.orange,
        Permission.locationWhenInUse, 'Requerida para BT scan en Android < 12'),
    _PermItem('Bluetooth Scan', Icons.bluetooth_searching, Colors.cyan,
        Permission.bluetoothScan, 'Buscar dispositivos cercanos (Android 12+)'),
    _PermItem('Bluetooth Connect', Icons.bluetooth_connected, Colors.blue,
        Permission.bluetoothConnect, 'Conectarse a dispositivos (Android 12+)'),
    _PermItem('Bluetooth Advertise', Icons.broadcast_on_personal,
        Colors.lightBlue, Permission.bluetoothAdvertise,
        'Hacerse visible para otros dispositivos'),
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
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
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
                Text(item.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                Text(item.desc, style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11)),
                const SizedBox(height: 4),
                Row(children: [
                  Icon(granted ? Icons.check_circle : Icons.cancel, color: granted ? Colors.greenAccent : Colors.redAccent, size: 14),
                  const SizedBox(width: 4),
                  Text(statusText, style: TextStyle(color: granted ? Colors.greenAccent : Colors.redAccent, fontSize: 11, fontWeight: FontWeight.w600)),
                ]),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (status == null)
            const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
          else if (granted)
            const Icon(Icons.check_circle, color: Colors.greenAccent, size: 24)
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
  StreamSubscription? _connectionSub;

  Future<void> _startScan() async {
    final statuses = await [
      Permission.locationWhenInUse,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();
    if (!statuses.values.every((s) => s.isGranted)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Concede los permisos primero'), backgroundColor: Colors.red),
        );
      }
      return;
    }
    _results.clear();
    setState(() => _scanning = true);
    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 8));
      _scanSub = FlutterBluePlus.scanResults.listen((results) {
        if (mounted) setState(() { _results..clear()..addAll(results); });
      });
      _scanningSub = FlutterBluePlus.isScanning.listen((scanning) {
        if (!scanning && mounted) setState(() => _scanning = false);
      });
    } catch (e) {
      if (mounted) { setState(() => _scanning = false); }
    }
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    try {
      await device.connect(timeout: const Duration(seconds: 10));
      _connectionSub = device.connectionState.listen((state) {
        if (mounted && state == BluetoothConnectionState.disconnected) {
          setState(() => _connectedDevice = null);
        }
      });
      if (mounted) {
        setState(() => _connectedDevice = device);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Conectado a ${device.platformName}'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al conectar: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  void dispose() {
    _scanSub?.cancel(); _scanningSub?.cancel(); _connectionSub?.cancel();
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
            _Header('Dispositivos', Icons.bluetooth_searching,
              _connectedDevice != null ? 'Conectado: ${_connectedDevice!.platformName}' : '${_results.length} encontrados'),
            const SizedBox(height: 16),
            if (_connectedDevice != null)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green.withOpacity(0.3))),
                child: Row(children: [
                  const Icon(Icons.bluetooth_connected, color: Colors.greenAccent, size: 22),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_connectedDevice!.platformName.isEmpty ? 'Dispositivo' : _connectedDevice!.platformName,
                        style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.w600, fontSize: 14)),
                    Text(_connectedDevice!.remoteId.toString(), style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11)),
                  ])),
                  TextButton(onPressed: () async { await _connectedDevice?.disconnect(); setState(() => _connectedDevice = null); },
                    child: const Text('Desconectar', style: TextStyle(color: Colors.redAccent))),
                ]),
              ),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: _scanning
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.search),
                label: Text(_scanning ? 'Buscando...' : 'Buscar dispositivos'),
                onPressed: _scanning ? null : _startScan,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _results.isEmpty
                  ? Center(child: Text(_scanning ? 'Buscando dispositivos cercanos...' : 'Presiona Buscar para escanear',
                      style: TextStyle(color: Colors.white.withOpacity(0.4)), textAlign: TextAlign.center))
                  : ListView.builder(itemCount: _results.length,
                      itemBuilder: (_, i) {
                        final r = _results[i];
                        final isConn = _connectedDevice?.remoteId == r.device.remoteId;
                        final rssi = r.rssi;
                        final sig = rssi > -60 ? Colors.greenAccent : rssi > -80 ? Colors.orangeAccent : Colors.redAccent;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(color: isConn ? Colors.green.withOpacity(0.08) : Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: isConn ? Colors.green.withOpacity(0.3) : Colors.white.withOpacity(0.08))),
                          child: Row(children: [
                            Icon(isConn ? Icons.bluetooth_connected : Icons.bluetooth, color: isConn ? Colors.greenAccent : Colors.blue, size: 22),
                            const SizedBox(width: 12),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(r.device.platformName.isEmpty ? 'Desconocido' : r.device.platformName,
                                  style: TextStyle(color: isConn ? Colors.greenAccent : Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                              Text(r.device.remoteId.toString(), style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11)),
                            ])),
                            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(color: sig.withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
                              child: Text('$rssi dBm', style: TextStyle(color: sig, fontSize: 12, fontWeight: FontWeight.w600))),
                            if (!isConn) TextButton(onPressed: () => _connectToDevice(r.device),
                              child: const Text('Conectar', style: TextStyle(fontSize: 12))),
                          ]),
                        );
                      }),
            ),
          ],
        ),
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
    setState(() { _messages.add(_Message(text: text, mine: true, time: DateTime.now())); _controller.clear(); });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(_scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  String _fmt(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  void dispose() { _controller.dispose(); _scrollController.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
          child: _Header('Chat', Icons.chat_bubble, 'Via Bluetooth local')),
        Expanded(
          child: _messages.isEmpty
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.bluetooth_disabled, size: 48, color: Colors.white.withOpacity(0.15)),
                  const SizedBox(height: 12),
                  Text('Conectate a un dispositivo\ny empieza a chatear',
                      style: TextStyle(color: Colors.white.withOpacity(0.3)), textAlign: TextAlign.center),
                ]))
              : ListView.builder(controller: _scrollController, padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: _messages.length, itemBuilder: (_, i) {
                    final m = _messages[i];
                    return Align(alignment: m.mine ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        constraints: const BoxConstraints(maxWidth: 280),
                        decoration: BoxDecoration(color: m.mine ? const Color(0xFF1D4ED8) : Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(14), topRight: const Radius.circular(14),
                            bottomLeft: Radius.circular(m.mine ? 14 : 4), bottomRight: Radius.circular(m.mine ? 4 : 14))),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Text(m.text, style: const TextStyle(color: Colors.white, fontSize: 14)),
                          const SizedBox(height: 4),
                          Text(_fmt(m.time), style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 10)),
                        ])));
                  }),
        ),
        Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Row(children: [
            Expanded(child: TextField(controller: _controller, style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(hintText: 'Escribe un mensaje...',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                filled: true, fillColor: Colors.white.withOpacity(0.07),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
              onSubmitted: (_) => _send())),
            const SizedBox(width: 8),
            IconButton.filled(icon: const Icon(Icons.send_rounded), onPressed: _send),
          ])),
      ]),
    );
  }
}

class _Message {
  final String text; final bool mine; final DateTime time;
  _Message({required this.text, required this.mine, required this.time});
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
  List<dynamic> _protocols = [];
  bool _loading = true;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final jsonStr = await rootBundle.loadString('assets/vault/first_aid/primeros_auxilios.json');
      final data = json.decode(jsonStr);
      setState(() { _protocols = data['protocolos'] ?? []; _loading = false; });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  List<dynamic> get _filtered {
    if (_search.isEmpty) return _protocols;
    return _protocols.where((p) =>
      p['titulo'].toString().toLowerCase().contains(_search.toLowerCase()) ||
      p['categoria'].toString().toLowerCase().contains(_search.toLowerCase())
    ).toList();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: const _Header('Primeros Auxilios', Icons.local_hospital, '12 protocolos de emergencia')),
        Padding(padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: TextField(style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(hintText: 'Buscar protocolo...',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
              prefixIcon: Icon(Icons.search, color: Colors.white.withOpacity(0.4)),
              filled: true, fillColor: Colors.white.withOpacity(0.07),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)),
            onChanged: (v) => setState(() => _search = v))),
        const SizedBox(height: 12),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _filtered.isEmpty
                  ? Center(child: Text('Sin resultados', style: TextStyle(color: Colors.white.withOpacity(0.4))))
                  : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: _filtered.length,
                      itemBuilder: (_, i) => _ProtocolCard(_filtered[i])),
        ),
      ]),
    );
  }
}

class _ProtocolCard extends StatelessWidget {
  final Map<String, dynamic> protocol;
  const _ProtocolCard(this.protocol);

  Color _priorityColor(String? p) {
    if (p == 'critica') return Colors.redAccent;
    if (p == 'alta') return Colors.orangeAccent;
    return Colors.blueAccent;
  }

  @override
  Widget build(BuildContext context) {
    final color = _priorityColor(protocol['prioridad']);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Card(
        color: Colors.white.withOpacity(0.05),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: color.withOpacity(0.3))),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => Navigator.push(context, MaterialPageRoute(
            builder: (_) => _ProtocolDetailPage(protocol))),
          child: Padding(padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
                  child: Text(protocol['prioridad']?.toString().toUpperCase() ?? '',
                      style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700))),
                const SizedBox(width: 8),
                Expanded(child: Text(protocol['titulo'] ?? '',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15))),
              ]),
              const SizedBox(height: 6),
              Text(protocol['resumen'] ?? '', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12),
                maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 6),
              Text('${(protocol['pasos'] as List?)?.length ?? 0} pasos',
                  style: TextStyle(color: color.withOpacity(0.7), fontSize: 11, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _ProtocolDetailPage extends StatelessWidget {
  final Map<String, dynamic> protocol;
  const _ProtocolDetailPage(this.protocol);

  @override
  Widget build(BuildContext context) {
    final pasos = (protocol['pasos'] as List?) ?? [];
    final advertencias = (protocol['advertencias'] as List?) ?? [];
    final referencias = (protocol['referencias'] as List?) ?? [];
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(backgroundColor: const Color(0xFF1E293B), title: Text(protocol['titulo'] ?? '', style: const TextStyle(fontSize: 16))),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Text(protocol['resumen'] ?? '', style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 14)),
        const SizedBox(height: 20),
        const Text('PASOS', style: TextStyle(color: Color(0xFF60A5FA), fontWeight: FontWeight.w700, fontSize: 14)),
        const SizedBox(height: 8),
        ...pasos.map((p) => Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(10)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              CircleAvatar(radius: 14, backgroundColor: const Color(0xFF3B82F6),
                child: Text('${p['numero']}', style: const TextStyle(color: Colors.white, fontSize: 12))),
              const SizedBox(width: 10),
              Expanded(child: Text(p['titulo'] ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14))),
            ]),
            const SizedBox(height: 8),
            Text(p['descripcion'] ?? '', style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13)),
            if (p['advertencia'] != null) ...[
              const SizedBox(height: 6),
              Container(padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.amber.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.warning_amber, color: Colors.amber, size: 16),
                  const SizedBox(width: 6),
                  Expanded(child: Text(p['advertencia'], style: const TextStyle(color: Colors.amber, fontSize: 11))),
                ])),
            ],
          ]),
        )),
        if (advertencias.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text('ADVERTENCIAS', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 8),
          ...advertencias.map((a) => Padding(padding: const EdgeInsets.only(bottom: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('• ', style: TextStyle(color: Colors.redAccent)),
              Expanded(child: Text(a.toString(), style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12))),
            ]))),
        ],
        if (referencias.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text('REFERENCIAS', style: TextStyle(color: Colors.white38, fontWeight: FontWeight.w700, fontSize: 12)),
          ...referencias.map((r) => Text('• $r', style: const TextStyle(color: Colors.white38, fontSize: 11))),
        ],
      ]),
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
  List<dynamic> _guides = [];
  bool _loading = true;
  String _search = '';

  @override
  void initState() { super.initState(); _loadData(); }

  Future<void> _loadData() async {
    try {
      final jsonStr = await rootBundle.loadString('assets/vault/guides/supervivencia.json');
      final data = json.decode(jsonStr);
      setState(() { _guides = data['guias'] ?? []; _loading = false; });
    } catch (e) { setState(() => _loading = false); }
  }

  List<dynamic> get _filtered {
    if (_search.isEmpty) return _guides;
    return _guides.where((g) =>
      g['titulo'].toString().toLowerCase().contains(_search.toLowerCase()) ||
      g['categoria'].toString().toLowerCase().contains(_search.toLowerCase())
    ).toList();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: const _Header('Guias de Supervivencia', Icons.terrain, '15 guias para emergencias')),
        Padding(padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: TextField(style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(hintText: 'Buscar guia...',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
              prefixIcon: Icon(Icons.search, color: Colors.white.withOpacity(0.4)),
              filled: true, fillColor: Colors.white.withOpacity(0.07),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)),
            onChanged: (v) => setState(() => _search = v))),
        const SizedBox(height: 12),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _filtered.isEmpty
                  ? Center(child: Text('Sin resultados', style: TextStyle(color: Colors.white.withOpacity(0.4))))
                  : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: _filtered.length,
                      itemBuilder: (_, i) => _GuideCard(_filtered[i])),
        ),
      ]),
    );
  }
}

class _GuideCard extends StatelessWidget {
  final Map<String, dynamic> guide;
  const _GuideCard(this.guide);

  Color _catColor(String? c) {
    switch (c) {
      case 'supervivencia': return Colors.orangeAccent;
      case 'tecnologia': return Colors.blueAccent;
      default: return Colors.greenAccent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _catColor(guide['categoria']);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Card(
        color: Colors.white.withOpacity(0.05),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: color.withOpacity(0.3))),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => Navigator.push(context, MaterialPageRoute(
            builder: (_) => _GuideDetailPage(guide))),
          child: Padding(padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(guide['titulo'] ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
              const SizedBox(height: 4),
              Text(guide['resumen'] ?? '', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12),
                maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 6),
              Row(children: [
                Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
                  child: Text(guide['categoria'] ?? '', style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600))),
                const SizedBox(width: 8),
                Text('${(guide['pasos'] as List?)?.length ?? 0} pasos',
                    style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11)),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

class _GuideDetailPage extends StatelessWidget {
  final Map<String, dynamic> guide;
  const _GuideDetailPage(this.guide);

  @override
  Widget build(BuildContext context) {
    final pasos = (guide['pasos'] as List?) ?? [];
    final advertencias = (guide['advertencias'] as List?) ?? [];
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(backgroundColor: const Color(0xFF1E293B), title: Text(guide['titulo'] ?? '', style: const TextStyle(fontSize: 16))),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Text(guide['resumen'] ?? '', style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 14)),
        const SizedBox(height: 20),
        ...pasos.map((p) => Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(10)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              CircleAvatar(radius: 14, backgroundColor: Colors.orange,
                child: Text('${p['numero']}', style: const TextStyle(color: Colors.white, fontSize: 12))),
              const SizedBox(width: 10),
              Expanded(child: Text(p['titulo'] ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14))),
            ]),
            const SizedBox(height: 8),
            Text(p['descripcion'] ?? '', style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13)),
            if (p['advertencia'] != null) ...[
              const SizedBox(height: 6),
              Container(padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.amber.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.warning_amber, color: Colors.amber, size: 16),
                  const SizedBox(width: 6),
                  Expanded(child: Text(p['advertencia'], style: const TextStyle(color: Colors.amber, fontSize: 11))),
                ])),
            ],
          ]),
        )),
        if (advertencias.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text('ADVERTENCIAS', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 8),
          ...advertencias.map((a) => Padding(padding: const EdgeInsets.only(bottom: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('• ', style: TextStyle(color: Colors.redAccent)),
              Expanded(child: Text(a.toString(), style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12))),
            ]))),
        ],
      ]),
    );
  }
}

// ─────────────────────────────────────────────
// PAGINA 6: VAULT / BUSQUEDA GLOBAL
// ─────────────────────────────────────────────
class VaultPage extends StatefulWidget {
  const VaultPage({super.key});
  @override
  State<VaultPage> createState() => _VaultPageState();
}

class _VaultPageState extends State<VaultPage> {
  String _search = '';
  List<_VaultResult> _results = [];
  bool _searching = false;

  List<dynamic> _firstAid = [];
  List<dynamic> _guides = [];
  List<dynamic> _wiki = [];
  List<dynamic> _dict = [];

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    try {
      final faStr = await rootBundle.loadString('assets/vault/first_aid/primeros_auxilios.json');
      _firstAid = (json.decode(faStr)['protocolos'] as List?) ?? [];
    } catch (_) {}
    try {
      final gStr = await rootBundle.loadString('assets/vault/guides/supervivencia.json');
      _guides = (json.decode(gStr)['guias'] as List?) ?? [];
    } catch (_) {}
    try {
      final wStr = await rootBundle.loadString('assets/vault/wikipedia/wikipedia_offline.json');
      final wData = json.decode(wStr);
      _wiki = [];
      for (final cat in (wData['categorias'] as Map?)?.values ?? []) {
        if (cat is Map && cat.containsKey('articulos')) {
          _wiki.addAll(cat['articulos'] as List);
        }
      }
    } catch (_) {}
    try {
      final dStr = await rootBundle.loadString('assets/vault/dictionary/diccionario_index.json');
      _dict = (json.decode(dStr) as List?) ?? [];
    } catch (_) {}
  }

  void _doSearch(String q) {
    if (q.length < 2) { setState(() { _results = []; _searching = false; }); return; }
    setState(() => _searching = true);
    final qLower = q.toLowerCase();
    final results = <_VaultResult>[];

    for (final p in _firstAid) {
      if (_match(p, qLower, ['titulo', 'resumen', 'categoria'])) {
        results.add(_VaultResult(type: 'Primeros Auxilios', title: p['titulo'] ?? '', subtitle: p['resumen'] ?? '',
          icon: Icons.local_hospital, color: Colors.redAccent, data: p, pageType: 'first_aid'));
      }
    }
    for (final g in _guides) {
      if (_match(g, qLower, ['titulo', 'resumen', 'categoria'])) {
        results.add(_VaultResult(type: 'Supervivencia', title: g['titulo'] ?? '', subtitle: g['resumen'] ?? '',
          icon: Icons.terrain, color: Colors.orangeAccent, data: g, pageType: 'guide'));
      }
    }
    for (final w in _wiki) {
      if (_match(w, qLower, ['titulo', 'resumen'])) {
        results.add(_VaultResult(type: 'Wikipedia', title: w['titulo'] ?? '', subtitle: w['resumen'] ?? '',
          icon: Icons.book, color: Colors.blueAccent, data: w, pageType: 'wiki'));
      }
    }
    for (final d in _dict) {
      if (_match(d, qLower, ['termino', 'definicion', 'categoria'])) {
        results.add(_VaultResult(type: 'Diccionario', title: d['termino'] ?? '', subtitle: d['definicion'] ?? '',
          icon: Icons.translate, color: Colors.purpleAccent, data: d, pageType: 'dict'));
      }
    }

    setState(() { _results = results; _searching = false; });
  }

  bool _match(Map<String, dynamic> item, String q, List<String> fields) {
    for (final f in fields) {
      if (item[f]?.toString().toLowerCase().contains(q) ?? false) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: _Header('Vault', Icons.search, 'Busqueda offline en todo el contenido')),
        Padding(padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: TextField(style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(hintText: 'Buscar en todo el vault...',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
              prefixIcon: Icon(Icons.search, color: Colors.white.withOpacity(0.4)),
              filled: true, fillColor: Colors.white.withOpacity(0.07),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)),
            onChanged: (v) { _search = v; _doSearch(v); })),
        const SizedBox(height: 12),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(children: [
            _vaultChip('Primeros Auxilios', '${_firstAid.length}', Icons.local_hospital, Colors.redAccent),
            const SizedBox(width: 8),
            _vaultChip('Guias', '${_guides.length}', Icons.terrain, Colors.orangeAccent),
            const SizedBox(width: 8),
            _vaultChip('Wiki', '${_wiki.length}', Icons.book, Colors.blueAccent),
            const SizedBox(width: 8),
            _vaultChip('Dict', '${_dict.length}', Icons.translate, Colors.purpleAccent),
          ])),
        const SizedBox(height: 12),
        Expanded(
          child: _searching
              ? const Center(child: CircularProgressIndicator())
              : _search.length < 2
                  ? Center(child: Text('Escribe al menos 2 letras para buscar',
                      style: TextStyle(color: Colors.white.withOpacity(0.4))))
                  : _results.isEmpty
                      ? Center(child: Text('Sin resultados para "$_search"',
                          style: TextStyle(color: Colors.white.withOpacity(0.4))))
                      : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 20),
                          itemCount: _results.length,
                          itemBuilder: (_, i) => _VaultResultCard(_results[i], context)),
        ),
      ]),
    );
  }

  Widget _vaultChip(String label, String count, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
        child: Column(children: [
          Icon(icon, color: color, size: 16),
          Text(count, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
          Text(label, style: TextStyle(color: color.withOpacity(0.7), fontSize: 8), textAlign: TextAlign.center),
        ]),
      ),
    );
  }
}

class _VaultResult {
  final String type;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final Map<String, dynamic> data;
  final String pageType;
  _VaultResult({required this.type, required this.title, required this.subtitle,
    required this.icon, required this.color, required this.data, required this.pageType});
}

class _VaultResultCard extends StatelessWidget {
  final _VaultResult r;
  final BuildContext ctx;
  const _VaultResultCard(this.r, this.ctx);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Card(
        color: Colors.white.withOpacity(0.05),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: r.color.withOpacity(0.2))),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            if (r.pageType == 'first_aid') {
              Navigator.push(ctx, MaterialPageRoute(builder: (_) => _ProtocolDetailPage(r.data)));
            } else if (r.pageType == 'guide') {
              Navigator.push(ctx, MaterialPageRoute(builder: (_) => _GuideDetailPage(r.data)));
            } else if (r.pageType == 'wiki') {
              Navigator.push(ctx, MaterialPageRoute(builder: (_) => _WikiDetailPage(r.data)));
            } else if (r.pageType == 'dict') {
              Navigator.push(ctx, MaterialPageRoute(builder: (_) => _DictDetailPage(r.data)));
            }
          },
          child: Padding(padding: const EdgeInsets.all(12),
            child: Row(children: [
              Icon(r.icon, color: r.color, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                Text(r.subtitle, style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              ])),
              Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: r.color.withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
                child: Text(r.type, style: TextStyle(color: r.color, fontSize: 9, fontWeight: FontWeight.w600))),
            ]),
          ),
        ),
      ),
    );
  }
}

// Wikipedia detail
class _WikiDetailPage extends StatelessWidget {
  final Map<String, dynamic> article;
  const _WikiDetailPage(this.article);

  @override
  Widget build(BuildContext context) {
    final sections = (article['secciones'] as List?) ?? [];
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(backgroundColor: const Color(0xFF1E293B), title: Text(article['titulo'] ?? '', style: const TextStyle(fontSize: 16))),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Text(article['resumen'] ?? '', style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 14)),
        const SizedBox(height: 16),
        ...sections.map((s) => Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(10)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s['titulo'] ?? '', style: const TextStyle(color: Color(0xFF60A5FA), fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 6),
            Text(s['contenido'] ?? '', style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13)),
          ]),
        )),
      ]),
    );
  }
}

// Dictionary detail
class _DictDetailPage extends StatelessWidget {
  final Map<String, dynamic> entry;
  const _DictDetailPage(this.entry);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(backgroundColor: const Color(0xFF1E293B), title: Text(entry['termino'] ?? '', style: const TextStyle(fontSize: 16))),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        if (entry['categoria'] != null)
          Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: Colors.purple.withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
            child: Text(entry['categoria'], style: const TextStyle(color: Colors.purpleAccent, fontSize: 12))),
        const SizedBox(height: 16),
        Text(entry['definicion'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 15)),
        if (entry['ejemplo'] != null) ...[
          const SizedBox(height: 16),
          const Text('EJEMPLO', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.w700, fontSize: 12)),
          const SizedBox(height: 4),
          Text(entry['ejemplo'], style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13, fontStyle: FontStyle.italic)),
        ],
        if (entry['sinonimos'] != null) ...[
          const SizedBox(height: 16),
          const Text('SINONIMOS', style: TextStyle(color: Colors.white38, fontWeight: FontWeight.w700, fontSize: 12)),
          Text(entry['sinonimos'].toString(), style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13)),
        ],
      ]),
    );
  }
}

// ─────────────────────────────────────────────
// WIDGET REUTILIZABLE: HEADER
// ─────────────────────────────────────────────
class _Header extends StatelessWidget {
  final String title;
  final IconData icon;
  final String subtitle;
  const _Header(this.title, this.icon, this.subtitle);

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, color: const Color(0xFF60A5FA), size: 28),
      const SizedBox(width: 10),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
        Text(subtitle, style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12)),
      ]),
    ]);
  }
}
