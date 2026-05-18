import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:open_filex/open_filex.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:vibration/vibration.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:math';

// ─── UUIDs del servicio BLE de LessNet ───
const String lessnetServiceUuid = "6e400001-b5a3-f393-e0a9-e50e24dcca9e";
const String lessnetCharRxUuid = "6e400002-b5a3-f393-e0a9-e50e24dcca9e";
const String lessnetCharTxUuid = "6e400003-b5a3-f393-e0a9-e50e24dcca9e";
const String kGlobalChatId = "__global__";
const String kGitHubOwner = "SantiagortegaDev";
const String kGitHubRepo = "lessnet";
const String kAppVersion = '1.2.0';
const String kHotspotChannel = 'com.lessnet.hotspot';
const String kLocationChannel = 'com.lessnet.location';
const String kLanChannel = 'com.lessnet.lan';
const int kLanPort = 9876;
const String kWifiDirectChannel = 'com.lessnet.wifi_direct';
const int kP2pPort = 9877;

// ─── APP LOGGER (ring buffer for debug mode) ───
class AppLogger {
  static final AppLogger _instance = AppLogger._internal();
  factory AppLogger() => _instance;
  AppLogger._internal();

  static const int _maxEntries = 100;
  final List<String> _logs = [];
  final _logController = StreamController<String>.broadcast();
  Stream<String> get onLog => _logController.stream;
  bool _debugMode = false;
  bool get debugMode => _debugMode;

  static void log(String message) {
    final ts = DateTime.now().toIso8601String().substring(11, 19);
    final entry = '[$ts] $message';
    final inst = AppLogger();
    inst._logs.add(entry);
    if (inst._logs.length > _maxEntries) {
      inst._logs.removeAt(0);
    }
    inst._logController.add(entry);
    debugPrint('[LessNet] $entry');
  }

  static List<String> getLogs() => List.from(AppLogger()._logs);

  static void setDebugMode(bool enabled) {
    AppLogger()._debugMode = enabled;
    log('Debug mode: ${enabled ? "ON" : "OFF"}');
  }

  static bool get isDebugMode => AppLogger()._debugMode;
}

// ─── ENCRYPTION HELPER ───
class LessNetCrypto {
  static final _globalKey = enc.Key.fromUtf8(
    sha256.convert(utf8.encode(lessnetServiceUuid)).toString().substring(0, 32),
  );
  static final _globalIv = enc.IV.fromUtf8(
    sha256.convert(utf8.encode('lessnet-iv-global')).toString().substring(0, 16),
  );

  static enc.Key _deviceKey(String deviceId) {
    final raw = sha256.convert(utf8.encode('lessnet-device-$deviceId')).toString();
    return enc.Key.fromUtf8(raw.substring(0, 32));
  }

  static enc.IV _deviceIv(String deviceId) {
    final raw = sha256.convert(utf8.encode('lessnet-iv-$deviceId')).toString();
    return enc.IV.fromUtf8(raw.substring(0, 16));
  }

  static String encrypt(String plaintext, {String? deviceId}) {
    return plaintext; // Encriptación desactivada — texto plano
  }

  static String decrypt(String ciphertext, {String? deviceId}) {
    return ciphertext; // Encriptación desactivada — texto plano
  }

  static bool isEncrypted(String text) => false; // Encriptación desactivada
}

// ─── DEVICE NAMING HELPER ───
class DeviceNames {
  static const _prefix = 'device_name_';

  static Future<String> getName(String deviceId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('$_prefix$deviceId') ?? '';
  }

  static Future<void> setName(String deviceId, String name) async {
    final prefs = await SharedPreferences.getInstance();
    if (name.trim().isEmpty) {
      await prefs.remove('$_prefix$deviceId');
    } else {
      await prefs.setString('$_prefix$deviceId', name.trim());
    }
  }

  static Future<String> getDisplayName(String deviceId, String fallback) async {
    final custom = await getName(deviceId);
    return custom.isNotEmpty ? custom : fallback;
  }
}

// ─── Notification helper ───
class LessNetNotifications {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _isAppInForeground = true;

  static void setAppForeground(bool foreground) {
    _isAppInForeground = foreground;
  }

  static Future<void> init() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (_) {
        // Bring app to foreground when tapping notification
      },
    );
  }

  static Future<void> showMessageNotification(String deviceName, String text) async {
    // Don't show notifications when the app is in foreground
    if (_isAppInForeground) return;
    const android = AndroidNotificationDetails(
      'lessnet_messages',
      'Mensajes LessNet',
      channelDescription: 'Notificaciones de mensajes recibidos',
      importance: Importance.high,
      priority: Priority.high,
    );
    const details = NotificationDetails(android: android);
    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'Nuevo mensaje de $deviceName',
      text,
      details,
    );
  }

  static Future<void> showConnectionNotification(String deviceName) async {
    const android = AndroidNotificationDetails(
      'lessnet_connections',
      'Conexiones LessNet',
      channelDescription: 'Notificaciones de conexion de dispositivos',
      importance: Importance.high,
      priority: Priority.high,
    );
    const details = NotificationDetails(android: android);
    await _plugin.show(
      9999,
      '$deviceName se ha conectado',
      null,
      details,
    );
  }

  static Future<void> showSOSNotification(String data) async {
    // Parse SOS data: [SOS:latitude:longitude:userId:timestamp]
    final parts = data.replaceAll('[SOS:', '').replaceAll(']', '').split(':');
    final lat = parts.isNotEmpty ? parts[0] : '?';
    final lng = parts.length > 1 ? parts[1] : '?';
    final userId = parts.length > 2 ? parts[2] : 'Desconocido';
    final vibrationPattern = Int64List.fromList([0, 500, 200, 500, 200, 500]);
    final android = AndroidNotificationDetails(
      'lessnet_sos',
      'SOS LessNet',
      channelDescription: 'Alertas de emergencia SOS',
      importance: Importance.max,
      priority: Priority.max,
      fullScreenIntent: true,
      autoCancel: false,
      ongoing: true,
      playSound: true,
      enableVibration: true,
      vibrationPattern: vibrationPattern,
    );
    final details = NotificationDetails(android: android);
    await _plugin.show(
      7777,
      'ALERTA SOS - $userId',
      'Lat: $lat, Lng: $lng - EMERGENCIA',
      details,
    );
  }
}

// ─── Background service top-level callback ───
@pragma('vm:entry-point')
Future<void> onStart(ServiceInstance service) async {
  // This keeps the foreground service alive while advertising
  service.on('stopService').listen((_) {
    service.stopSelf();
  });
}

Future<void> startForegroundService() async {
  final service = FlutterBackgroundService();
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: true,
      isForegroundMode: true,
      initialNotificationTitle: 'LessNet',
      initialNotificationContent: 'Visible y esperando conexion',
    ),
    iosConfiguration: IosConfiguration(),
  );
  await service.startService();
}

Future<void> stopForegroundService() async {
  final service = FlutterBackgroundService();
  service.invoke('stopService');
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LessNetNotifications.init();
  runApp(const LessNetApp());
}

// ─────────────────────────────────────────────
// APP ROOT — PALETA BLANCO Y NEGRO
// ─────────────────────────────────────────────
class LessNetApp extends StatefulWidget {
  const LessNetApp({super.key});

  @override
  State<LessNetApp> createState() => _LessNetAppState();
}

class _LessNetAppState extends State<LessNetApp> with WidgetsBindingObserver {
  bool? _needsPermissions; // null = loading, true = show perms, false = go to main
  bool _updateChecked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    LessNetNotifications.setAppForeground(true);
    _checkPermissionsNeeded();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    LessNetNotifications.setAppForeground(
      state == AppLifecycleState.resumed,
    );
    // Re-check permissions when app comes back to foreground
    if (state == AppLifecycleState.resumed && _needsPermissions == false) {
      _checkPermissionsNeeded();
    }
  }

  /// Returns the list of essential BLE permissions that must be granted
  List<Permission> get _essentialPerms => [
    Permission.locationWhenInUse,
    Permission.bluetoothScan,
    Permission.bluetoothConnect,
    Permission.bluetoothAdvertise,
    Permission.nearbyWifiDevices,
  ];

  Future<void> _checkPermissionsNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final completed = prefs.getBool('permissions_completed') ?? false;

    if (!completed) {
      // First launch — always show permissions
      if (mounted) setState(() => _needsPermissions = true);
      return;
    }

    // Check if any essential permission was revoked
    bool allGranted = true;
    for (final p in _essentialPerms) {
      try {
        final status = await p.status;
        if (!status.isGranted) {
          allGranted = false;
          break;
        }
      } catch (_) {
        // Permission not available on this device, skip
      }
    }

    if (mounted) setState(() => _needsPermissions = !allGranted);
  }

  void _onPermissionsAccepted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('permissions_completed', true);
    if (mounted) setState(() => _needsPermissions = false);
    _checkForUpdate();
  }

  Future<void> _checkForUpdate() async {
    if (_updateChecked) return;
    _updateChecked = true;
    try {
      final response = await http.get(
        Uri.parse('https://api.github.com/repos/$kGitHubOwner/$kGitHubRepo/releases/latest'),
        headers: {'Accept': 'application/vnd.github+json'},
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return;
      final data = json.decode(response.body);
      final tagName = (data['tag_name'] as String? ?? '').replaceFirst('v', '');
      if (tagName.isEmpty) return;
      // Compare versions
      if (_compareVersions(tagName, kAppVersion) <= 0) return;
      // Newer version available
      final htmlUrl = data['html_url'] as String? ?? '';
      final assets = (data['assets'] as List?) ?? [];
      final body = data['body'] as String? ?? '';
      String? apkUrl;
      for (final asset in assets) {
        final name = (asset['name'] as String? ?? '').toLowerCase();
        if (name.endsWith('.apk') || name == 'app-release.apk') {
          apkUrl = asset['browser_download_url'] as String?;
          break;
        }
      }
      if (mounted) {
        _showUpdateDialog(tagName, htmlUrl, apkUrl, body);
      }
    } catch (e) {
      debugPrint('Update check error: $e');
    }
  }

  int _compareVersions(String a, String b) {
    final aParts = a.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    final bParts = b.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    for (int i = 0; i < aParts.length && i < bParts.length; i++) {
      if (aParts[i] != bParts[i]) return aParts[i].compareTo(bParts[i]);
    }
    return aParts.length.compareTo(bParts.length);
  }

  void _showUpdateDialog(String version, String htmlUrl, String? apkUrl, [String? body]) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Actualizacion disponible', style: TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Nueva version v$version disponible (actual: v$kAppVersion).',
                style: const TextStyle(color: Colors.white70),
              ),
              if (apkUrl != null)
                const Text(
                  'Puedes descargar e instalar el APK directamente.',
                  style: TextStyle(color: Colors.white54, fontSize: 13),
                )
              else
                const Text(
                  'Visita GitHub para descargar.',
                  style: TextStyle(color: Colors.white54, fontSize: 13),
                ),
              if (body != null && body.trim().isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text('Cambios en esta version:',
                    style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111111),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF2A2A2A)),
                  ),
                  constraints: const BoxConstraints(maxHeight: 250),
                  child: SingleChildScrollView(
                    child: MarkdownBody(
                      data: body,
                      selectable: true,
                      styleSheet: MarkdownStyleSheet(
                        p: const TextStyle(color: Colors.white60, fontSize: 12, height: 1.5),
                        h2: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                        listBullet: const TextStyle(color: Colors.white60, fontSize: 12),
                        code: const TextStyle(color: Colors.greenAccent, fontSize: 11, backgroundColor: Color(0xFF1A1A1A)),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Mas tarde'),
          ),
          if (apkUrl != null)
            FilledButton(
              onPressed: () async {
                if (ctx.mounted) Navigator.pop(ctx);
                _downloadAndInstallApk(apkUrl);
              },
              style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black),
              child: const Text('Descargar APK'),
            ),
          FilledButton(
            onPressed: () async {
              if (ctx.mounted) Navigator.pop(ctx);
              final uri = Uri.parse(htmlUrl);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black),
            child: const Text('Ver en GitHub'),
          ),
        ],
      ),
    );
  }

  Future<void> _downloadAndInstallApk(String apkUrl) async {
    try {
      AppLogger.log('Descargando APK desde: $apkUrl');
      final response = await http.get(Uri.parse(apkUrl)).timeout(const Duration(minutes: 5));
      if (response.statusCode != 200) {
        AppLogger.log('Error descargando APK: ${response.statusCode}');
        return;
      }
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/lessnet_update.apk');
      await file.writeAsBytes(response.bodyBytes);
      AppLogger.log('APK descargado: ${file.path}');
      await OpenFilex.open(file.path);
    } catch (e) {
      AppLogger.log('Error instalando APK: $e');
    }
  }

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
          tertiary: Color(0xFF444444),
          onTertiary: Colors.white,
          error: Colors.redAccent,
          onError: Colors.white,
          surface: Color(0xFF0A0A0A),
          onSurface: Colors.white,
          surfaceVariant: Color(0xFF111111),
          onSurfaceVariant: Color(0xFF666666),
          outline: Color(0xFF2A2A2A),
          outlineVariant: Color(0xFF1E1E1E),
          shadow: Colors.black,
          scrim: Colors.black,
          inverseSurface: Color(0xFFE0E0E0),
          onInverseSurface: Colors.black,
          surfaceTint: Colors.transparent,
        ),
        scaffoldBackgroundColor: const Color(0xFF0A0A0A),
        useMaterial3: true,
        dividerColor: Colors.transparent,
        dividerTheme: const DividerThemeData(
          color: Colors.transparent,
          thickness: 0,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: const Color(0xFF111111),
          indicatorColor: const Color(0xFF262626), // was withOpacity(0.15) — yellow on AMOLED
          iconTheme: WidgetStateProperty.all(
            const IconThemeData(color: Colors.grey),
          ),
          labelTextStyle: WidgetStateProperty.all(
            const TextStyle(color: Colors.grey, fontSize: 11),
          ),
        ),
        // ─── KILL ALL DEFAULT UNDERLINES GLOBALLY ───
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: Color(0xFF151515),
        ),
      ),
      home: _needsPermissions == null
          ? const _SplashScreen()
          : _needsPermissions!
              ? PermissionsGatePage(onAccepted: _onPermissionsAccepted)
              : const HomePage(),
    );
  }
}

// ─────────────────────────────────────────────
// SPLASH SCREEN — Shows splash_image.png while checking permissions
// ─────────────────────────────────────────────
class _SplashScreen extends StatefulWidget {
  const _SplashScreen();

  @override
  State<_SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<_SplashScreen> {
  @override
  void initState() {
    super.initState();
    _navigate();
  }

  Future<void> _navigate() async {
    // Small delay to show splash
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() {}); // Parent will handle navigation
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Image.asset(
          'assets/splash_image.png',
          fit: BoxFit.contain,
          width: double.infinity,
          height: double.infinity,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// BLUETOOTH SERVICE GLOBAL — PROTOCOLO SIMPLE + RÁPIDO
// ─────────────────────────────────────────────
// Formato: [FILE:TYPE:FILENAME:SIZE:CRC32]base64_data
// Un solo mensaje por archivo. CRC32 verifica integridad.
// Chunks de escritura BLE de 200 bytes (MTU-aware).
// ─────────────────────────────────────────────

const Color _kCardBg = Color(0xFF1A1A1A);       // card background (was white 0.08)
const Color _kCardBgLight = Color(0xFF141414);   // lighter card bg (was white 0.05)
const Color _kCardBgDim = Color(0xFF111111);     // dim card bg (was white 0.03-0.04)
const Color _kBorder = Color(0xFF2A2A2A);        // card border (was white 0.12-0.15)
const Color _kBorderDim = Color(0xFF1E1E1E);     // dim border (was white 0.06-0.08)
const Color _kInputFill = Color(0xFF151515);     // text input fill (was white 0.04)
const Color _kChipBg = Color(0xFF222222);        // chip background
const Color _kChipBgActive = Color(0xFF2E2E2E);  // active chip background

const int _kBleWriteSize = 200; // bytes por write BLE (MTU-safe)
const int _kMaxFileSize = 2 * 1024 * 1024; // 2 MB
const int _kPeripheralNotifyDelayMs = 10; // ms entre notificaciones (peripheral)

// ─────────────────────────────────────────────
// TRANSPORT MANAGER — Abstracción de transporte adaptativo
// Prioridad: BLE > LAN (misma red) > Wi-Fi Direct > offline
// ─────────────────────────────────────────────
enum TransportQuality { excellent, good, weak, lost }

enum TransportType { ble, lan, wifiDirect, none }

abstract class Transport {
  Stream<ChatMessage> get messageStream;
  Future<void> send(ChatMessage msg);
  Future<void> disconnect();
  TransportQuality get quality;
  TransportType get type;
  bool get isConnected;
}

class TransportManager {
  static final TransportManager _instance = TransportManager._internal();
  factory TransportManager() => _instance;
  TransportManager._internal();

  Transport? _activeTransport;
  Transport? get activeTransport => _activeTransport;
  final _transportChangeController = StreamController<TransportType>.broadcast();
  Stream<TransportType> get onTransportChange => _transportChangeController.stream;

  int _lastRssi = -100;
  Timer? _rssiMonitor;
  static const int _rssiCheckIntervalSec = 3;
  static const int _rssiGoodThreshold = -70;
  static const int _rssiWeakThreshold = -85;

  TransportType _currentType = TransportType.none;
  TransportType get currentType => _currentType;

  void setActiveTransport(Transport transport) {
    _activeTransport = transport;
    _currentType = transport.type;
    _transportChangeController.add(_currentType);
    AppLogger.log('TransportManager: transporte activo = $_currentType');
  }

  void clearTransport() {
    _activeTransport = null;
    _currentType = TransportType.none;
    _transportChangeController.add(_currentType);
    AppLogger.log('TransportManager: sin transporte');
  }

  /// Update RSSI from BLE scan results. Monitors quality and suggests upgrades.
  void updateRssi(int rssi) {
    _lastRssi = rssi;
    if (rssi > _rssiGoodThreshold) {
      // BLE quality is good, no need to upgrade
    } else if (rssi > _rssiWeakThreshold && rssi <= _rssiGoodThreshold) {
      AppLogger.log('TransportManager: BLE señal débil (RSSI=$rssi), considere cambiar a Wi-Fi');
    } else if (rssi <= _rssiWeakThreshold) {
      AppLogger.log('TransportManager: BLE señal muy débil (RSSI=$rssi), debería cambiar a Wi-Fi o LAN');
    }
  }

  /// Get quality assessment based on current RSSI
  TransportQuality get bleQuality {
    if (_lastRssi > _rssiGoodThreshold) return TransportQuality.excellent;
    if (_lastRssi > _rssiWeakThreshold) return TransportQuality.good;
    if (_lastRssi > -100) return TransportQuality.weak;
    return TransportQuality.lost;
  }

  /// Get recommended transport based on available options and current quality
  TransportType get recommendedTransport {
    // BLE is preferred if quality is good
    if (bleQuality == TransportQuality.excellent || bleQuality == TransportQuality.good) {
      return TransportType.ble;
    }
    // Try to upgrade if BLE is weak
    if (bleQuality == TransportQuality.weak) {
      // TODO: Check if LAN is available (BUG-5 implementation)
      // TODO: Check if Wi-Fi Direct is available (BUG-4 implementation)
      return TransportType.ble; // Stay on BLE for now
    }
    // BLE is lost
    // TODO: Try LAN, then Wi-Fi Direct
    return TransportType.none;
  }

  /// Start monitoring RSSI periodically
  void startRssiMonitoring(BluetoothDevice device) {
    _rssiMonitor?.cancel();
    _rssiMonitor = Timer.periodic(
      const Duration(seconds: _rssiCheckIntervalSec),
      (_) async {
        try {
          final rssi = await device.readRssi();
          updateRssi(rssi);
        } catch (e) {
          AppLogger.log('TransportManager: Error leyendo RSSI: $e');
        }
      },
    );
  }

  void stopRssiMonitoring() {
    _rssiMonitor?.cancel();
    _rssiMonitor = null;
  }

  void dispose() {
    _rssiMonitor?.cancel();
    _transportChangeController.close();
  }
}

/// Notification type for transport changes in the UI
class TransportNotification {
  final TransportType from;
  final TransportType to;
  final TransportQuality quality;
  const TransportNotification(this.from, this.to, this.quality);
}

// ─── Per-connection data for Central mode ───
class _CentralConnection {
  final BluetoothDevice device;
  BluetoothCharacteristic? rxChar;
  BluetoothCharacteristic? txChar;
  StreamSubscription? txSub;
  StreamSubscription? connSub;
  final List<int> receiveBuffer = [];

  _CentralConnection(this.device);

  String get id => device.platformName.isNotEmpty
      ? device.platformName
      : device.remoteId.toString();

  String get name => device.platformName.isEmpty ? 'Dispositivo' : device.platformName;
}

class BtService {
  static final BtService _instance = BtService._internal();
  factory BtService() => _instance;
  BtService._internal() {
    _setupPeripheralChannel();
  }

  // ─── Multi-connection: Central connections map ───
  final Map<String, _CentralConnection> _centralConnections = {};

  // Keep "active" device = last connected / currently focused
  String _activeDeviceId = '';

  // ─── Legacy single-connection fields (kept for backward compat) ───
  BluetoothDevice? connectedDevice; // points to active device
  BluetoothCharacteristic? rxChar;   // points to active device's rx
  BluetoothCharacteristic? txChar;   // points to active device's tx
  StreamSubscription? _txSub;        // active device tx sub
  StreamSubscription? _connSub;      // active device conn sub
  final List<int> _receiveBuffer = [];
  bool _isConnecting = false;
  bool _isSending = false;
  bool get isSending => _isSending;

  static const _peripheralChannel =
      MethodChannel('com.lessnet.ble_peripheral');
  bool _isPeripheral = false;
  bool _isAdvertising = false;
  bool _peripheralConnected = false;
  String _peripheralDeviceName = '';
  String _advertisingError = '';
  bool _autoConnectEnabled = true;
  Timer? _autoScanTimer;

  // ─── Mesh relay tracking ───
  final Map<String, DateTime> _meshSeen = {}; // content hash -> expiry time
  static const int _kMeshMaxHops = 5;
  static const Duration _kMeshSeenExpiry = Duration(minutes: 5);

  // ─── Data tracking ───
  int _bytesSent = 0;
  int _bytesReceived = 0;
  int get bytesSent => _bytesSent;
  int get bytesReceived => _bytesReceived;

  final List<ChatMessage> messages = [];
  final _msgController = StreamController<ChatMessage>.broadcast();
  Stream<ChatMessage> get onMessage => _msgController.stream;

  final _connectionController = StreamController<bool>.broadcast();
  Stream<bool> get onConnectionChange => _connectionController.stream;

  final _advertisingController = StreamController<bool>.broadcast();
  Stream<bool> get onAdvertisingChange => _advertisingController.stream;

  final _statusController = StreamController<String>.broadcast();
  Stream<String> get onStatusChange => _statusController.stream;

  // Progress tracking
  final _progressController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get onProgress => _progressController.stream;

  bool get isAdvertising => _isAdvertising;
  bool get isPeripheralConnected => _peripheralConnected;
  bool get isConnected =>
      _centralConnections.isNotEmpty || _peripheralConnected;
  bool get connecting => _isConnecting;
  String get advertisingError => _advertisingError;

  // ─── Multi-connection helpers ───
  List<String> get connectedDeviceIds {
    final ids = _centralConnections.keys.toList();
    // Also include peripheral connection
    if (_peripheralConnected) {
      final pName = _peripheralDeviceName.isNotEmpty ? _peripheralDeviceName : 'Dispositivo';
      if (!ids.contains(pName)) {
        ids.add(pName);
      }
    }
    return ids;
  }
  int get centralConnectionCount => connectedDeviceIds.length;
  bool isDeviceConnected(String deviceId) {
    if (_centralConnections.containsKey(deviceId)) return true;
    // Also check peripheral connection
    if (_peripheralConnected) {
      final pName = _peripheralDeviceName.isNotEmpty ? _peripheralDeviceName : 'Dispositivo';
      if (pName == deviceId) return true;
    }
    return false;
  }

  String get activeDeviceId => _activeDeviceId;

  void setActiveDevice(String deviceId) {
    if (_centralConnections.containsKey(deviceId)) {
      _activeDeviceId = deviceId;
      final conn = _centralConnections[deviceId]!;
      connectedDevice = conn.device;
      rxChar = conn.rxChar;
      txChar = conn.txChar;
      _connectionController.add(true);
    } else if (_peripheralConnected && _peripheralDeviceName == deviceId) {
      // Handle peripheral device — no CentralConnection object, just mark active
      _activeDeviceId = deviceId;
      connectedDevice = null;
      rxChar = null;
      txChar = null;
      _connectionController.add(true);
    }
  }

  String get connectedName {
    if (_activeDeviceId.isNotEmpty && _centralConnections.containsKey(_activeDeviceId)) {
      return _centralConnections[_activeDeviceId]!.name;
    }
    if (_peripheralConnected) {
      return _peripheralDeviceName.isEmpty
          ? 'Dispositivo'
          : _peripheralDeviceName;
    }
    return '';
  }

  String get connectedDeviceId {
    if (_activeDeviceId.isNotEmpty) {
      return _activeDeviceId;
    }
    if (_peripheralConnected) {
      return _peripheralDeviceName.isNotEmpty ? _peripheralDeviceName : 'Dispositivo';
    }
    return '';
  }

  String getDeviceName(String deviceId) {
    if (_centralConnections.containsKey(deviceId)) {
      return _centralConnections[deviceId]!.name;
    }
    if (_peripheralConnected) {
      final pName = _peripheralDeviceName.isNotEmpty ? _peripheralDeviceName : 'Dispositivo';
      if (pName == deviceId) {
        return pName;
      }
    }
    return deviceId.isEmpty ? 'General' : deviceId;
  }

  // ─── CRC32 ───
  static int _crc32(List<int> data) {
    int crc = 0xFFFFFFFF;
    for (final byte in data) {
      crc ^= byte;
      for (int i = 0; i < 8; i++) {
        if ((crc & 1) != 0) {
          crc = (crc >> 1) ^ 0xEDB88320;
        } else {
          crc >>= 1;
        }
      }
    }
    return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }

  void _setupPeripheralChannel() {
    _peripheralChannel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onDataReceived':
          final text = call.arguments as String? ?? '';
          if (text.isNotEmpty) {
            _processReceivedText(text);
          }
          break;
        case 'onSendProgress':
          // Progress from Kotlin peripheral send
          final progress = call.arguments as double? ?? 0.0;
          _progressController.add({'progress': progress});
          break;
        case 'onDeviceConnected':
          _peripheralConnected = true;
          _isAdvertising = false;
          _peripheralDeviceName = call.arguments as String? ?? '';
          // Set active device for peripheral so ChatPage knows we're connected
          if (_peripheralDeviceName.isNotEmpty) {
            _activeDeviceId = _peripheralDeviceName;
          } else {
            _activeDeviceId = 'Dispositivo';
            _peripheralDeviceName = 'Dispositivo';
          }
          _advertisingController.add(false);
          _connectionController.add(true);
          _statusController.add('Conectado: $_peripheralDeviceName');
          // Stop foreground service on connection, show connection notification
          try { await stopForegroundService(); } catch (_) {}
          try { await LessNetNotifications.showConnectionNotification(_peripheralDeviceName.isNotEmpty ? _peripheralDeviceName : 'Dispositivo'); } catch (_) {}
          break;
        case 'onDeviceDisconnected':
          _peripheralConnected = false;
          _peripheralDeviceName = '';
          if (_activeDeviceId == _peripheralDeviceName || _activeDeviceId == 'Dispositivo') {
            _activeDeviceId = '';
          }
          _isSending = false;
          _connectionController.add(false);
          _statusController.add('Desconectado');
          break;
        case 'onAdvertiseStatus':
          final success = call.arguments as bool? ?? false;
          if (!success) {
            _advertisingError =
                'El dispositivo no pudo iniciar advertising.';
          }
          _isAdvertising = success;
          _advertisingController.add(success);
          break;
      }
    });
  }

  Future<void> startAdvertising() async {
    _advertisingError = '';
    _isAdvertising = false; // Don't set true until confirmed
    AppLogger.log('Iniciando BLE advertising (UUID: $lessnetServiceUuid)...');
    try {
      await _peripheralChannel.invokeMethod('startAdvertising');
      _isPeripheral = true;
      // Only set true after native confirms success (no exception thrown)
      _isAdvertising = true;
      _advertisingController.add(true);
      AppLogger.log('BLE advertising activo exitosamente');
      // Start foreground service while advertising
      try { await startForegroundService(); } catch (_) {}
    } catch (e) {
      _isAdvertising = false;
      _advertisingError = e.toString().contains('ADV_ERROR')
          ? 'Este dispositivo NO soporta BLE advertising.'
          : 'Error: $e';
      AppLogger.log('BLE advertising FALLÓ: $_advertisingError');
      _advertisingController.add(false);
      rethrow;
    }
  }

  Future<void> stopAdvertising() async {
    try {
      await _peripheralChannel.invokeMethod('stopAdvertising');
    } catch (_) {}
    _isAdvertising = false;
    _isPeripheral = false;
    _peripheralConnected = false;
    _advertisingController.add(false);
    // Stop foreground service when advertising stops
    try { await stopForegroundService(); } catch (_) {}
  }

  Future<void> connectToDevice(BluetoothDevice device) async {
    if (_isConnecting) return;
    _isConnecting = true;
    _statusController.add('Conectando...');

    try {
      final deviceId = device.platformName.isNotEmpty
          ? device.platformName
          : device.remoteId.toString();

      AppLogger.log('Conectando a dispositivo: $deviceId');

      // Check if already connected to this device
      if (_centralConnections.containsKey(deviceId)) {
        _statusController.add('Ya conectado a ${_centralConnections[deviceId]!.name}');
        AppLogger.log('Ya conectado a $deviceId, saltando');
        return;
      }

      // DON'T disconnect existing connections — support multi-connect!
      // Only clean up if connecting to the same device
      if (_centralConnections.containsKey(deviceId)) {
        await _cleanupSingleConnection(deviceId);
      }

      AppLogger.log('Llamando device.connect() para $deviceId...');
      await device.connect(timeout: const Duration(seconds: 20));
      AppLogger.log('Conectado a $deviceId, negociando MTU...');

      try {
        await device.requestMtu(512);
      } catch (e) {
        AppLogger.log('MTU request falló (no crítico): $e');
      }

      AppLogger.log('Descubriendo servicios en $deviceId...');
      final services = await device.discoverServices();
      AppLogger.log('Descubiertos ${services.length} servicios en $deviceId');

      // Re-read device name after discoverServices — it may be available now
      final resolvedName = device.platformName.isNotEmpty
          ? device.platformName
          : (await _tryGetDeviceName(device));
      final resolvedId = resolvedName != device.remoteId.toString()
          ? resolvedName
          : deviceId;

      if (resolvedId != deviceId) {
        AppLogger.log('Nombre resuelto: $deviceId → $resolvedId');
        // Update the connection map key if name resolved
      }
      BluetoothCharacteristic? foundRx;
      BluetoothCharacteristic? foundTx;
      for (final service in services) {
        final serviceUuidStr = service.uuid.str128.toLowerCase();
        AppLogger.log('  Servicio: $serviceUuidStr (${service.characteristics.length} chars)');
        if (serviceUuidStr == lessnetServiceUuid.toLowerCase()) {
          AppLogger.log('  *** LessNet service encontrado! ***');
          for (final char in service.characteristics) {
            final charUuid = char.uuid.str128.toLowerCase();
            AppLogger.log('    Característica: $charUuid props=${char.properties}');
            if (charUuid == lessnetCharRxUuid.toLowerCase()) {
              foundRx = char;
              AppLogger.log('    *** RX characteristic encontrada ***');
            } else if (charUuid == lessnetCharTxUuid.toLowerCase()) {
              foundTx = char;
              AppLogger.log('    *** TX characteristic encontrada ***');
            }
          }
        }
      }

      if (foundRx == null || foundTx == null) {
        AppLogger.log('ADVERTENCIA: RX o TX no encontrados. RX=${foundRx != null}, TX=${foundTx != null}');
      }

      // Store in multi-connection map (use resolved name as key)
      final conn = _CentralConnection(device);
      conn.rxChar = foundRx;
      conn.txChar = foundTx;
      _centralConnections[resolvedId] = conn;

      // Set as active device
      _activeDeviceId = resolvedId;
      connectedDevice = device;
      rxChar = foundRx;
      txChar = foundTx;

      if (foundTx != null) {
        conn.receiveBuffer.clear();
        final notifyOk = await foundTx.setNotifyValue(true);
        if (!notifyOk) {
          await Future.delayed(const Duration(milliseconds: 200));
          await foundTx.setNotifyValue(true);
        }
        conn.txSub = foundTx.onValueChangedStream.listen((value) {
          if (value.isNotEmpty) {
            _handleReceivedDataForDevice(value, deviceId);
          }
        });
      }

      conn.connSub = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _centralConnections.remove(deviceId);
          if (_activeDeviceId == deviceId) {
            _activeDeviceId = _centralConnections.keys.isNotEmpty
                ? _centralConnections.keys.first
                : '';
            if (_activeDeviceId.isNotEmpty) {
              setActiveDevice(_activeDeviceId);
            } else {
              connectedDevice = null;
              rxChar = null;
              txChar = null;
            }
          }
          _statusController.add('Desconectado: ${conn.name}');
          _connectionController.add(isConnected);
        }
      });

      _connectionController.add(true);
      _statusController.add('Conectado: ${conn.name}');

      // Start RSSI monitoring for transport quality assessment
      TransportManager().startRssiMonitoring(device);
    } catch (e) {
      _statusController.add('Error: $e');
      rethrow;
    } finally {
      _isConnecting = false;
    }
  }

  // ─── Auto-connect: scan and connect to nearby LessNet devices ───
  Future<void> startAutoConnect() async {
    if (!_autoConnectEnabled) return;
    _autoScanTimer?.cancel();
    _autoScanTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _autoScanAndConnect();
    });
    // Run immediately
    await _autoScanAndConnect();
  }

  void stopAutoConnect() {
    _autoScanTimer?.cancel();
    _autoScanTimer = null;
  }

  Future<void> _autoScanAndConnect() async {
    try {
      // Verify permissions before scanning
      final scanStatus = await Permission.bluetoothScan.status;
      final connectStatus = await Permission.bluetoothConnect.status;
      if (!scanStatus.isGranted || !connectStatus.isGranted) {
        AppLogger.log('AutoScan: permisos BLE no concedidos (scan=$scanStatus, connect=$connectStatus)');
        return;
      }

      // Check BT is ON
      final a = await FlutterBluePlus.adapterState.first.timeout(
        const Duration(seconds: 3),
        onTimeout: () => BluetoothAdapterState.unknown,
      );
      if (a != BluetoothAdapterState.on) {
        AppLogger.log('AutoScan: Bluetooth no activado (state=$a)');
        return;
      }

      // Don't scan if already scanning or if we're advertising
      if (FlutterBluePlus.isScanningNow) return;
      if (_isAdvertising) return;

      final connectedIds = _centralConnections.keys.toSet();
      AppLogger.log('AutoScan: iniciando escaneo (${connectedIds.length} conectados)');

      // Try with UUID filter first for efficiency
      try {
        await FlutterBluePlus.startScan(
          timeout: const Duration(seconds: 10),
          withServices: [Guid(lessnetServiceUuid)],
          androidUsesFineLocation: false,
        );
      } catch (e) {
        AppLogger.log('AutoScan: filtro UUID falló, reintentando sin filtro: $e');
        await FlutterBluePlus.startScan(
          timeout: const Duration(seconds: 10),
          androidUsesFineLocation: true,
        );
      }

      final sub = FlutterBluePlus.scanResults.listen((results) {
        for (final r in results) {
          // Only auto-connect to LessNet devices
          final isLessNet = r.advertisementData.serviceUuids.any(
            (u) => u.str128.toLowerCase() == lessnetServiceUuid.toLowerCase(),
          );
          if (!isLessNet) continue;

          final deviceId = r.device.platformName.isNotEmpty
              ? r.device.platformName
              : r.device.remoteId.toString();

          // Skip if already connected
          if (connectedIds.contains(deviceId)) continue;
          if (_centralConnections.containsKey(deviceId)) continue;

          // Emit event for user confirmation instead of auto-connecting
          AppLogger.log('AutoScan: dispositivo LessNet encontrado: $deviceId (RSSI=${r.rssi})');
          _statusController.add('AUTO_CONNECT_REQUEST:$deviceId');
        }
      });

      // Stop listening after scan completes
      await Future.delayed(const Duration(seconds: 11));
      await sub.cancel();
    } catch (e) {
      AppLogger.log('AutoScan error: $e');
    }
  }

  void _handleReceivedDataForDevice(List<int> value, String deviceId) {
    final conn = _centralConnections[deviceId];
    if (conn == null) return;
    // Efficient parsing: find null terminators and batch process
    int start = 0;
    for (int i = 0; i < value.length; i++) {
      if (value[i] == 0x00) {
        // Add all bytes before the null terminator to buffer
        if (i > start) {
          conn.receiveBuffer.addAll(value.sublist(start, i));
        }
        // Process complete message
        if (conn.receiveBuffer.isNotEmpty) {
          final text = utf8.decode(conn.receiveBuffer, allowMalformed: true);
          conn.receiveBuffer.clear();
          if (text.isNotEmpty) {
            _bytesReceived += text.length;
            // Temporarily set active device for _processReceivedText
            final prevActive = _activeDeviceId;
            _activeDeviceId = deviceId;
            _processReceivedText(text);
            _activeDeviceId = prevActive.isNotEmpty ? prevActive : _activeDeviceId;
          }
        }
        start = i + 1;
      }
    }
    // Add remaining bytes (no null terminator found yet)
    if (start < value.length) {
      conn.receiveBuffer.addAll(value.sublist(start));
    }
  }

  Future<String> _tryGetDeviceName(BluetoothDevice device) async {
    // El nombre puede llegar con delay — esperar brevemente
    await Future.delayed(const Duration(milliseconds: 500));
    return device.platformName.isNotEmpty
        ? device.platformName
        : device.remoteId.toString();
  }

  Future<void> _cleanupSingleConnection(String deviceId) async {
    final conn = _centralConnections.remove(deviceId);
    if (conn != null) {
      conn.txSub?.cancel();
      conn.connSub?.cancel();
      try {
        await conn.device.disconnect();
      } catch (_) {}
    }
    if (_activeDeviceId == deviceId) {
      _activeDeviceId = _centralConnections.keys.isNotEmpty
          ? _centralConnections.keys.first
          : '';
      if (_activeDeviceId.isNotEmpty) {
        setActiveDevice(_activeDeviceId);
      } else {
        connectedDevice = null;
        rxChar = null;
        txChar = null;
      }
    }
  }

  void _handleReceivedData(List<int> value) {
    for (int i = 0; i < value.length; i++) {
      if (value[i] == 0x00) {
        if (_receiveBuffer.isNotEmpty) {
          final text = utf8.decode(_receiveBuffer, allowMalformed: true);
          _receiveBuffer.clear();
          if (text.isNotEmpty) {
            _processReceivedText(text);
          }
        }
      } else {
        _receiveBuffer.add(value[i]);
      }
    }
  }

  void _processReceivedText(String text) {
    // ─── SOS PROTOCOL ───
    AppLogger.log('Mensaje recibido de $_activeDeviceId (${text.length} chars): ${text.length > 80 ? "${text.substring(0, 80)}..." : text}');
    if (text.startsWith('[SOS:')) {
      AppLogger.log('SOS recibido: $text');
      try { LessNetNotifications.showSOSNotification(text); } catch (_) {}
      // Emitir por el canal de status para que la UI lo muestre
      _statusController.add('SOS_RECEIVED:$text');
      final msg = ChatMessage(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        text: '🆘 ALERTA SOS recibida: ${text.replaceAll('[SOS:', '').replaceAll(']', '').replaceAll(':', ' ')}',
        mine: false,
        time: DateTime.now(),
        deviceId: kGlobalChatId,
      );
      messages.add(msg);
      _msgController.add(msg);
      MessageDB.insert(msg);
      // Relay SOS to other devices
      _relayGlobalMessage(text, _activeDeviceId);
      return;
    }

    // ─── MESH PROTOCOL ───
    // [MESH:hopCount:originId][GLOBAL]payload or [MESH:hopCount:originId]payload
    if (text.startsWith('[MESH:')) {
      final meshHeaderEnd = text.indexOf(']');
      if (meshHeaderEnd > 6) {
        final header = text.substring(6, meshHeaderEnd);
        final headerParts = header.split(':');
        if (headerParts.length >= 2) {
          final hopCount = int.tryParse(headerParts[0]) ?? 0;
          final originId = headerParts.sublist(1).join(':');
          // Check deduplication
          final contentHash = sha256.convert(utf8.encode(text)).toString().substring(0, 16);
          _cleanMeshSeen();
          if (_meshSeen.containsKey(contentHash)) {
            AppLogger.log('Mesh: descartando duplicado de $originId');
            return; // Already seen
          }
          _meshSeen[contentHash] = DateTime.now().add(_kMeshSeenExpiry);
          AppLogger.log('Mesh: mensaje de $originId, hops=$hopCount');

          final innerPayload = text.substring(meshHeaderEnd + 1);
          // Process the inner payload
          _processReceivedText(innerPayload);

          // Relay if hop count > 0
          if (hopCount > 0) {
            final relayPayload = '[MESH:${hopCount - 1}:$originId]$innerPayload';
            AppLogger.log('Mesh: retransmitiendo (hops=${hopCount - 1})');
            _relayGlobalMessage(relayPayload, _activeDeviceId);
          }
          return;
        }
      }
    }

    // ─── GLOBAL CHAT PROTOCOL ───
    // [GLOBAL][ENC]<base64> — encrypted global message
    if (text.startsWith('[GLOBAL]')) {
      final encryptedPayload = text.substring(8); // skip '[GLOBAL]'
      final decrypted = encryptedPayload; // Sin encriptación
      if (decrypted.isNotEmpty && !decrypted.startsWith('[FILE:') && !decrypted.startsWith('[XFR:')) {
        final msg = ChatMessage(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          text: decrypted,
          mine: false,
          time: DateTime.now(),
          deviceId: kGlobalChatId,
        );
        messages.add(msg);
        _msgController.add(msg);
        MessageDB.insert(msg);
        try { LessNetNotifications.showMessageNotification('Chat Global', decrypted); } catch (_) {}
        // Relay to other connected devices (mesh)
        final senderId = _activeDeviceId;
        if (senderId.isNotEmpty) {
          _relayGlobalMessage(text, senderId);
        }
      }
      return;
    }

    // ─── ENCRYPTED PERSONAL MESSAGE (legacy — ya no se genera) ───
    // Los mensajes [ENC] legacy se procesan como texto plano
    if (text.startsWith('[ENC]')) {
      // Si llega un mensaje [ENC] de una versión antigua, intentamos decrypt
      // pero como la encriptación está desactivada, lo pasamos tal cual
      final payload = text.substring(5); // quitar '[ENC]'
      final senderId = _activeDeviceId.isNotEmpty ? _activeDeviceId : connectedDeviceId;
      final decrypted = LessNetCrypto.decrypt(payload, deviceId: senderId);
      if (decrypted.startsWith('[FILE:') || decrypted.startsWith('[IMG:') || decrypted.startsWith('[VID:')) {
        _processReceivedText(decrypted);
      } else {
        final msg = ChatMessage(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          text: decrypted,
          mine: false,
          time: DateTime.now(),
          deviceId: senderId,
        );
        messages.add(msg);
        _msgController.add(msg);
        MessageDB.insert(msg);
        try { LessNetNotifications.showMessageNotification(connectedName, decrypted); } catch (_) {}
      }
      return;
    }

    // ─── FILE TRANSFER PROTOCOL ───
    // [FILE:TYPE:FILENAME:SIZE:CRC32]base64data
    if (text.startsWith('[FILE:')) {
      try {
        final headerEnd = text.indexOf(']');
        if (headerEnd > 5) {
          final header = text.substring(6, headerEnd); // skip '[FILE:'
          final parts = header.split(':');
          // parts: [TYPE, FILENAME, SIZE, CRC32] = 4 parts minimum
          if (parts.length >= 4) {
            final msgType = parts[0].toLowerCase(); // img, vid, file
            final fileName = parts[1];
            final fileSize = int.tryParse(parts[2]) ?? 0;
            final expectedCrc = int.tryParse(parts[3]) ?? 0;
            final b64Data = text.substring(headerEnd + 1);

            final bytes = base64Decode(b64Data);

            // Verify CRC32
            final actualCrc = _crc32(bytes);
            if (actualCrc != expectedCrc) {
              debugPrint('CRC32 mismatch: expected=$expectedCrc actual=$actualCrc for $fileName');
              // Try to save anyway — partial image is better than nothing
            }

            _saveReceivedFile(msgType, fileName, bytes).then((savedPath) {
              final msg = ChatMessage(
                id: DateTime.now().microsecondsSinceEpoch.toString(),
                text: fileName,
                mine: false,
                time: DateTime.now(),
                type: msgType == 'img' ? 'image' : (msgType == 'vid' ? 'video' : 'file'),
                fileName: fileName,
                filePath: savedPath,
                fileSize: fileSize,
                deviceId: connectedDeviceId,
              );
              messages.add(msg);
              _msgController.add(msg);
              MessageDB.insert(msg);
              // Show notification for background message
              try { LessNetNotifications.showMessageNotification(connectedName, fileName); } catch (_) {}
            });
            return;
          }
        }
      } catch (e) {
        debugPrint('Error parsing FILE transfer: $e');
        // Fall through — don't show protocol text as chat message
        // If it looks like a protocol message, silently ignore
        if (text.startsWith('[FILE:') || text.startsWith('[XFR:') ||
            text.startsWith('[CHK:') || text.startsWith('[END:') ||
            text.startsWith('[ACK:') || text.startsWith('[NAK:') ||
            text.startsWith('[RESEND:')) {
          return;
        }
      }
    }

    // ─── SILENTLY IGNORE OTHER PROTOCOL MESSAGES ───
    // Never show internal protocol text as chat messages
    if (text.startsWith('[XFR:') || text.startsWith('[CHK:') ||
        text.startsWith('[END:') || text.startsWith('[ACK:') ||
        text.startsWith('[NAK:') || text.startsWith('[RESEND:')) {
      return;
    }

    // ─── LEGACY PROTOCOL (backward compat) ───
    if (text.startsWith('[IMG:') || text.startsWith('[VID:') || text.startsWith('[FILE:')) {
      try {
        final firstBracket = text.indexOf('[');
        final headerEnd = text.indexOf(']', firstBracket);
        if (firstBracket >= 0 && headerEnd > firstBracket) {
          final header = text.substring(firstBracket + 1, headerEnd);
          final parts = header.split(':');
          final msgType = parts[0].toLowerCase();
          final fileName = parts.length > 1 ? parts[1] : 'file';
          final fileSize = parts.length > 2 ? int.tryParse(parts[2]) ?? 0 : 0;
          final b64Data = text.substring(headerEnd + 1);

          final bytes = base64Decode(b64Data);
          _saveReceivedFile(msgType, fileName, bytes).then((savedPath) {
            final msg = ChatMessage(
              id: DateTime.now().microsecondsSinceEpoch.toString(),
              text: fileName,
              mine: false,
              time: DateTime.now(),
              type: msgType == 'img' ? 'image' : (msgType == 'vid' ? 'video' : 'file'),
              fileName: fileName,
              filePath: savedPath,
              fileSize: fileSize,
              deviceId: connectedDeviceId,
            );
            messages.add(msg);
            _msgController.add(msg);
            MessageDB.insert(msg);
            try { LessNetNotifications.showMessageNotification(connectedName, fileName); } catch (_) {}
          });
          return;
        }
      } catch (e) {
        // If parsing fails and it looks like protocol text, don't show it
        return;
      }
    }

    // ─── Plain text message ───
    final senderDeviceId = _activeDeviceId.isNotEmpty ? _activeDeviceId : connectedDeviceId;
    final msg = ChatMessage(id: DateTime.now().microsecondsSinceEpoch.toString(), text: text, mine: false, time: DateTime.now(), deviceId: senderDeviceId);
    messages.add(msg);
    _msgController.add(msg);
    MessageDB.insert(msg);
    // Show notification for background message
    try { LessNetNotifications.showMessageNotification(connectedName, text); } catch (_) {}
  }

  // ─── Relay global message to other connected devices (mesh) ───
  Future<void> _relayGlobalMessage(String payload, String excludeDeviceId) async {
    // Wrap in mesh protocol if not already wrapped
    final meshPayload = payload.startsWith('[MESH:') ? payload
        : '[MESH:$_kMeshMaxHops:${connectedDeviceId.isNotEmpty ? connectedDeviceId : "self"}]$payload';
    AppLogger.log('Mesh relay: retransmitiendo a ${_centralConnections.length} centrales (excluyendo $excludeDeviceId)');
    final futures = <Future>[];
    for (final devId in _centralConnections.keys.toList()) {
      if (devId != excludeDeviceId) {
        futures.add(_sendRawMessage(meshPayload, deviceId: devId));
      }
    }
    // Also relay to peripheral if connected and not the sender
    if (_isPeripheral && _peripheralConnected && _peripheralDeviceName != excludeDeviceId) {
      futures.add(_sendRawMessage(meshPayload));
    }
    await Future.wait(futures);
  }

  void _cleanMeshSeen() {
    final now = DateTime.now();
    _meshSeen.removeWhere((_, expiry) => now.isAfter(expiry));
  }

  Future<String> _saveReceivedFile(String type, String fileName, List<int> bytes) async {
    final dir = await getApplicationDocumentsDirectory();
    final lessnetDir = Directory('${dir.path}/lessnet_files');
    if (!await lessnetDir.exists()) {
      await lessnetDir.create(recursive: true);
    }
    final ext = fileName.contains('.') ? '' : (type == 'img' ? '.jpg' : (type == 'vid' ? '.mp4' : '.bin'));
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final savedName = '${timestamp}_$fileName$ext';
    final file = File('${lessnetDir.path}/$savedName');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  // ─── Send raw BLE message with MTU-aware chunks ───
  Future<void> _sendRawMessage(String text, {String? deviceId}) async {
    final bytes = utf8.encode(text);
    _bytesSent += bytes.length;
    final targetId = deviceId ?? _activeDeviceId;
    AppLogger.log('Enviando ${bytes.length} bytes a $targetId (peripheral=$_isPeripheral, peripheralConn=$_peripheralConnected)');
    if (_isPeripheral && _peripheralConnected) {
      // Peripheral: send via Kotlin (handles notifications internally)
      await _peripheralChannel.invokeMethod('sendData', {'data': text});
    } else {
      // Central: find the right connection
      final targetId = deviceId ?? _activeDeviceId;
      final conn = _centralConnections[targetId];
      if (conn?.rxChar != null) {
        for (int i = 0; i < bytes.length; i += _kBleWriteSize) {
          final end = i + _kBleWriteSize > bytes.length ? bytes.length : i + _kBleWriteSize;
          final chunk = bytes.sublist(i, end);
          await conn!.rxChar!.write(Uint8List.fromList(chunk), withoutResponse: false);
        }
        // Null terminator
        await conn!.rxChar!.write(Uint8List.fromList([0x00]), withoutResponse: false);
      }
    }

    // Fallback LAN: si hay dispositivos LAN conocidos, enviar también por TCP
    final lanDevices = LanService().devices;
    if (lanDevices.isNotEmpty) {
      for (final d in lanDevices) {
        LanService().sendMessage(d.host, port: d.port, message: text)
            .catchError((e) => AppLogger.log('LAN send error: $e'));
      }
    }

    // Fallback P2P: si hay conexión Wi-Fi Direct activa
    if (WifiDirectService().connected) {
      WifiDirectService().sendMessage(message: text)
          .catchError((e) => AppLogger.log('P2P send error: $e'));
    }
  }

  Future<void> sendMessage(String text, {String? deviceId}) async {
    if (text.isEmpty) return;
    final targetId = deviceId ?? _activeDeviceId;

    // Check if we are actually connected before sending
    if (targetId == kGlobalChatId) {
      // Global chat: need at least one connection
      if (!isConnected) return;
    } else if (targetId.isNotEmpty) {
      // Personal chat: need connection to that specific device
      if (!isDeviceConnected(targetId) && !_isPeripheral) return;
    }

    final msg = ChatMessage(id: DateTime.now().microsecondsSinceEpoch.toString(), text: text, mine: true, time: DateTime.now(), deviceId: targetId);
    messages.add(msg);
    _msgController.add(msg);
    MessageDB.insert(msg);

    // Sin encriptación — texto plano
    final isGlobal = targetId == kGlobalChatId;
    final payload = isGlobal ? '[GLOBAL]$text' : text;

    if (isGlobal) {
      // Broadcast to ALL connected devices simultaneously
      AppLogger.log('Chat Global: enviando a ${_centralConnections.length} centrales + peripheral=$_peripheralConnected');
      final futures = <Future>[];
      for (final devId in _centralConnections.keys.toList()) {
        futures.add(_sendRawMessage(payload, deviceId: devId));
      }
      // Also send via peripheral if connected
      if (_isPeripheral && _peripheralConnected) {
        futures.add(_sendRawMessage(payload));
      }
      await Future.wait(futures);
      AppLogger.log('Chat Global: broadcast completado');
    } else {
      await _sendRawMessage(payload, deviceId: deviceId);
    }
  }

  // ─── File send — simple protocol, one message, MTU-aware ───
  Future<void> sendFile({
    required String localPath,
    required String msgType, // 'image', 'video', 'file'
    required String fileName,
    String? deviceId,
  }) async {
    final file = File(localPath);
    final bytes = await file.readAsBytes();
    final fileSize = bytes.length;
    final fileCrc = _crc32(bytes);
    final b64 = base64Encode(bytes);
    final typeCode = msgType == 'image' ? 'img' : (msgType == 'video' ? 'vid' : 'file');

    final msgId = DateTime.now().microsecondsSinceEpoch.toString();
    final targetId = deviceId ?? _activeDeviceId;

    // Create local message
    final msg = ChatMessage(
      id: msgId,
      text: fileName,
      mine: true,
      time: DateTime.now(),
      type: msgType,
      fileName: fileName,
      filePath: localPath,
      fileSize: fileSize,
      deviceId: targetId,
    );
    messages.add(msg);
    _msgController.add(msg);
    MessageDB.insert(msg);

    _isSending = true;
    _progressController.add({'progress': 0.0, 'msgId': msgId, 'fileName': fileName});

    try {
      // Build the full payload: [FILE:TYPE:FILENAME:SIZE:CRC32]base64data
      final filePayload = '[FILE:$typeCode:$fileName:$fileSize:$fileCrc]$b64';

      // Sin encriptación — file payload en texto plano
      final isGlobal = targetId == kGlobalChatId;
      final payload = isGlobal ? '[GLOBAL]$filePayload' : filePayload;
      final payloadBytes = utf8.encode(payload);

      if (_isPeripheral && _peripheralConnected) {
        // Peripheral: use Kotlin sendData (handles notifications + progress)
        await _peripheralChannel.invokeMethod('sendFile', {'data': payload});
      } else if (isGlobal) {
        // Global: broadcast to ALL connected devices
        for (final devId in _centralConnections.keys.toList()) {
          final conn = _centralConnections[devId];
          if (conn?.rxChar != null) {
            for (int i = 0; i < payloadBytes.length; i += _kBleWriteSize) {
              final end = i + _kBleWriteSize > payloadBytes.length ? payloadBytes.length : i + _kBleWriteSize;
              final chunk = payloadBytes.sublist(i, end);
              await conn!.rxChar!.write(Uint8List.fromList(chunk), withoutResponse: false);
            }
            await conn!.rxChar!.write(Uint8List.fromList([0x00]), withoutResponse: false);
          }
        }
      } else {
        // Central: find the right connection
        final conn = _centralConnections[targetId];
        if (conn?.rxChar != null) {
          final totalWrites = (payloadBytes.length / _kBleWriteSize).ceil() + 1;
          int writesDone = 0;

          for (int i = 0; i < payloadBytes.length; i += _kBleWriteSize) {
            final end = i + _kBleWriteSize > payloadBytes.length ? payloadBytes.length : i + _kBleWriteSize;
            final chunk = payloadBytes.sublist(i, end);
            await conn!.rxChar!.write(Uint8List.fromList(chunk), withoutResponse: false);
            writesDone++;
            if (writesDone % 5 == 0 || i + _kBleWriteSize >= payloadBytes.length) {
              final progress = (i + _kBleWriteSize) / payloadBytes.length;
              _progressController.add({'progress': progress.clamp(0.0, 1.0), 'msgId': msgId, 'fileName': fileName});
            }
          }

          // Null terminator
          await conn!.rxChar!.write(Uint8List.fromList([0x00]), withoutResponse: false);
          _progressController.add({'progress': 1.0, 'msgId': msgId, 'fileName': fileName});
        }
      }
    } catch (e) {
      _progressController.add({'progress': -1.0, 'msgId': msgId, 'fileName': fileName, 'error': e.toString()});
      rethrow;
    } finally {
      _isSending = false;
    }
  }

  Future<void> _cleanupPreConnect() async {
    // Clean up legacy single-connection subscriptions only
    _txSub?.cancel();
    _txSub = null;
    _connSub?.cancel();
    _connSub = null;
    rxChar = null;
    txChar = null;
    _receiveBuffer.clear();
    _isSending = false;
    // DON'T disconnect existing central connections here
  }

  void _cleanup() {
    _txSub?.cancel();
    _connSub?.cancel();
    _txSub = null;
    _connSub = null;
    connectedDevice = null;
    rxChar = null;
    txChar = null;
    _receiveBuffer.clear();
    _isSending = false;
    _connectionController.add(isConnected);
  }

  Future<void> disconnectDevice(String deviceId) async {
    await _cleanupSingleConnection(deviceId);
    _connectionController.add(isConnected);
  }

  Future<void> disconnect() async {
    _statusController.add('Desconectando...');
    // Disconnect all central connections
    for (final deviceId in _centralConnections.keys.toList()) {
      await _cleanupSingleConnection(deviceId);
    }
    if (_isPeripheral) await stopAdvertising();
    _connectionController.add(false);
  }

  void dispose() {
    _txSub?.cancel();
    _connSub?.cancel();
    _msgController.close();
    _connectionController.close();
    _advertisingController.close();
    _statusController.close();
    _progressController.close();
  }
}

class ChatMessage {
  final String id;
  final String text;
  final bool mine;
  final DateTime time;
  final String type; // 'text', 'image', 'video', 'file'
  final String? fileName;
  final String? filePath; // local file path for received/sent files
  final int? fileSize;
  final String deviceId; // remote device identifier
  final bool read; // read receipt

  ChatMessage({
    required this.id,
    required this.text,
    required this.mine,
    required this.time,
    this.type = 'text',
    this.fileName,
    this.filePath,
    this.fileSize,
    this.deviceId = '',
    this.read = false,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'text': text,
    'mine': mine ? 1 : 0,
    'time': time.millisecondsSinceEpoch,
    'type': type,
    'fileName': fileName,
    'filePath': filePath,
    'fileSize': fileSize,
    'deviceId': deviceId,
    'read': read ? 1 : 0,
  };

  factory ChatMessage.fromMap(Map<String, dynamic> m) => ChatMessage(
    id: m['id'] as String,
    text: m['text'] as String,
    mine: (m['mine'] as int) == 1,
    time: DateTime.fromMillisecondsSinceEpoch(m['time'] as int),
    type: m['type'] as String? ?? 'text',
    fileName: m['fileName'] as String?,
    filePath: m['filePath'] as String?,
    fileSize: m['fileSize'] as int?,
    deviceId: m['deviceId'] as String? ?? '',
    read: (m['read'] as int?) == 1,
  );
}

// ─── MESSAGE DATABASE ───
class MessageDB {
  static Database? _db;

  static Future<Database> get db async {
    if (_db != null) return _db!;
    _db = await _init();
    return _db!;
  }

  static Future<Database> _init() async {
    final path = await getDatabasesPath();
    return openDatabase(
      '$path/lessnet_messages.db',
      version: 3,
      onCreate: (db, ver) async {
        await db.execute('''
          CREATE TABLE messages (
            id TEXT PRIMARY KEY,
            text TEXT,
            mine INTEGER,
            time INTEGER,
            type TEXT,
            fileName TEXT,
            filePath TEXT,
            fileSize INTEGER,
            deviceId TEXT DEFAULT ''
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE messages ADD COLUMN deviceId TEXT DEFAULT \'\'');
        }
        if (oldVersion < 3) {
          await db.execute('ALTER TABLE messages ADD COLUMN read INTEGER DEFAULT 0');
        }
      },
    );
  }

  static Future<void> insert(ChatMessage msg) async {
    final d = await db;
    await d.insert('messages', msg.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<List<ChatMessage>> getAll() async {
    final d = await db;
    final rows = await d.query('messages', orderBy: 'time ASC');
    return rows.map((m) => ChatMessage.fromMap(m)).toList();
  }

  static Future<void> deleteAll() async {
    final d = await db;
    await d.delete('messages');
  }

  static Future<void> deleteMessage(String id) async {
    final d = await db;
    await d.delete('messages', where: 'id = ?', whereArgs: [id]);
  }

  static Future<List<ChatMessage>> getByDevice(String deviceId) async {
    final d = await db;
    final rows = await d.query(
      'messages',
      where: 'deviceId = ?',
      whereArgs: [deviceId],
      orderBy: 'time ASC',
    );
    return rows.map((m) => ChatMessage.fromMap(m)).toList();
  }

  static Future<void> deleteByDevice(String deviceId) async {
    final d = await db;
    await d.delete('messages', where: 'deviceId = ?', whereArgs: [deviceId]);
  }

  static Future<List<DeviceConversation>> getDeviceList() async {
    final d = await db;
    final rows = await d.rawQuery('''
      SELECT deviceId,
             MAX(time) as lastTime,
             (SELECT text FROM messages m2 WHERE m2.deviceId = m.deviceId ORDER BY time DESC LIMIT 1) as lastMessage,
             (SELECT COUNT(*) FROM messages m3 WHERE m3.deviceId = m.deviceId AND m3.mine = 0 AND m3.id NOT IN (
               SELECT id FROM messages WHERE mine = 0 ORDER BY time DESC LIMIT 0
             )) as unreadCount
      FROM messages m
      WHERE deviceId IS NOT NULL AND deviceId != ''
      GROUP BY deviceId
      ORDER BY lastTime DESC
    ''');
    // Also check for messages with empty deviceId ("General")
    final generalRows = await d.rawQuery(
      'SELECT COUNT(*) as cnt FROM messages WHERE deviceId = \'\' OR deviceId IS NULL',
    );
    final result = <DeviceConversation>[];
    for (final row in rows) {
      final did = row['deviceId'] as String? ?? '';
      result.add(DeviceConversation(
        deviceId: did,
        lastMessage: row['lastMessage'] as String? ?? '',
        lastTime: DateTime.fromMillisecondsSinceEpoch(
          (row['lastTime'] as int?) ?? 0,
        ),
        unreadCount: 0, // Simplified: we'll count unread via a separate approach
      ));
    }
    // Add "General" conversation if there are messages without deviceId
    if ((generalRows.first['cnt'] as int? ?? 0) > 0) {
      final lastGeneral = await d.query(
        'messages',
        where: 'deviceId = \'\' OR deviceId IS NULL',
        orderBy: 'time DESC',
        limit: 1,
      );
      if (lastGeneral.isNotEmpty) {
        result.add(DeviceConversation(
          deviceId: '',
          lastMessage: (lastGeneral.first['text'] as String?) ?? '',
          lastTime: DateTime.fromMillisecondsSinceEpoch(
            (lastGeneral.first['time'] as int?) ?? 0,
          ),
          unreadCount: 0,
        ));
      }
    }
    result.sort((a, b) => b.lastTime.compareTo(a.lastTime));
    return result;
  }
}

class DeviceConversation {
  final String deviceId;
  final String lastMessage;
  final DateTime lastTime;
  final int unreadCount;

  const DeviceConversation({
    required this.deviceId,
    required this.lastMessage,
    required this.lastTime,
    this.unreadCount = 0,
  });

  String get displayName {
    if (deviceId == kGlobalChatId) return 'Chat Global';
    if (deviceId.isEmpty) return 'General';
    return deviceId;
  }
}

// ─── LAN SERVICE — NSD discovery + TCP chat ───
class LanDevice {
  final String name;
  final String host;
  final int port;
  const LanDevice({required this.name, required this.host, required this.port});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LanDevice && runtimeType == other.runtimeType && host == other.host && port == other.port;

  @override
  int get hashCode => host.hashCode ^ port.hashCode;
}

class LanService {
  static final LanService _instance = LanService._internal();
  factory LanService() => _instance;
  LanService._internal() {
    _setupChannel();
  }

  static const _channel = MethodChannel(kLanChannel);
  final List<LanDevice> _discoveredDevices = [];
  final _deviceController = StreamController<List<LanDevice>>.broadcast();
  Stream<List<LanDevice>> get onDevicesChanged => _deviceController.stream;
  List<LanDevice> get devices => List.unmodifiable(_discoveredDevices);

  bool _isRegistered = false;
  bool _isDiscovering = false;
  bool _tcpServerRunning = false;
  String _localIp = '';

  bool get isRegistered => _isRegistered;
  bool get isDiscovering => _isDiscovering;
  bool get tcpServerRunning => _tcpServerRunning;
  String get localIp => _localIp;

  void _setupChannel() {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onServiceFound':
          final info = call.arguments as Map;
          final device = LanDevice(
            name: info['name'] as String? ?? 'Unknown',
            host: info['host'] as String? ?? '',
            port: info['port'] as int? ?? kLanPort,
          );
          if (device.host.isNotEmpty && !_discoveredDevices.any((d) => d.host == device.host)) {
            _discoveredDevices.add(device);
            AppLogger.log('LAN: dispositivo encontrado: ${device.name} @ ${device.host}:${device.port}');
            _deviceController.add(List.from(_discoveredDevices));
          }
          break;
        case 'onServiceLost':
          final name = call.arguments as String? ?? '';
          _discoveredDevices.removeWhere((d) => d.name == name);
          AppLogger.log('LAN: dispositivo perdido: $name');
          _deviceController.add(List.from(_discoveredDevices));
          break;
        case 'onServiceRegistered':
          AppLogger.log('LAN: servicio NSD registrado: ${call.arguments}');
          break;
        case 'onRegistrationFailed':
          AppLogger.log('LAN: registro NSD fallido: errorCode=${call.arguments}');
          break;
        case 'onTcpMessage':
          final message = call.arguments as String? ?? '';
          if (message.isNotEmpty) {
            AppLogger.log('LAN: mensaje TCP recibido (${message.length} chars)');
            // Feed into BtService's message processing
            BtService()._processReceivedText(message);
          }
          break;
      }
    });
  }

  Future<void> registerService({String serviceName = 'LessNet'}) async {
    try {
      await _channel.invokeMethod('registerService', {
        'port': kLanPort,
        'serviceName': serviceName,
      });
      _isRegistered = true;
      AppLogger.log('LAN: servicio registrado en puerto $kLanPort');
    } catch (e) {
      AppLogger.log('LAN: error registrando servicio: $e');
    }
  }

  Future<void> unregisterService() async {
    try {
      await _channel.invokeMethod('unregisterService');
      _isRegistered = false;
    } catch (e) {
      AppLogger.log('LAN: error desregistrando servicio: $e');
    }
  }

  Future<void> discoverServices() async {
    if (_isDiscovering) return;
    try {
      _discoveredDevices.clear();
      await _channel.invokeMethod('discoverServices');
      _isDiscovering = true;
      AppLogger.log('LAN: descubrimiento NSD iniciado');
    } catch (e) {
      AppLogger.log('LAN: error iniciando descubrimiento: $e');
    }
  }

  Future<void> stopDiscovery() async {
    try {
      await _channel.invokeMethod('stopDiscovery');
      _isDiscovering = false;
    } catch (e) {
      AppLogger.log('LAN: error deteniendo descubrimiento: $e');
    }
  }

  Future<void> startTcpServer() async {
    try {
      await _channel.invokeMethod('startTcpServer');
      _tcpServerRunning = true;
      AppLogger.log('LAN: servidor TCP iniciado');
    } catch (e) {
      AppLogger.log('LAN: error iniciando servidor TCP: $e');
    }
  }

  Future<void> stopTcpServer() async {
    try {
      await _channel.invokeMethod('stopTcpServer');
      _tcpServerRunning = false;
    } catch (e) {
      AppLogger.log('LAN: error deteniendo servidor TCP: $e');
    }
  }

  Future<void> sendMessage(String host, {int port = kLanPort, required String message}) async {
    try {
      await _channel.invokeMethod('sendTcpMessage', {
        'host': host,
        'port': port,
        'message': message,
      });
      AppLogger.log('LAN: mensaje enviado a $host:$port');
    } catch (e) {
      AppLogger.log('LAN: error enviando mensaje: $e');
      rethrow;
    }
  }

  Future<String> getLocalIp() async {
    try {
      _localIp = await _channel.invokeMethod('getLocalIp') ?? '';
      return _localIp;
    } catch (e) {
      AppLogger.log('LAN: error obteniendo IP local: $e');
      return '';
    }
  }

  /// Start full LAN service: register NSD + start TCP server
  Future<void> startFullService() async {
    await getLocalIp();
    await registerService();
    await startTcpServer();
    await discoverServices();
    AppLogger.log('LAN: servicio completo iniciado (IP=$_localIp)');
  }

  /// Stop full LAN service
  Future<void> stopFullService() async {
    await stopDiscovery();
    await stopTcpServer();
    await unregisterService();
    _discoveredDevices.clear();
    AppLogger.log('LAN: servicio completo detenido');
  }

  void dispose() {
    _deviceController.close();
  }
}

// ─── WI-FI DIRECT SERVICE ───
class P2pPeer {
  final String name;
  final String address;
  final bool isGroupOwner;
  const P2pPeer({required this.name, required this.address, this.isGroupOwner = false});
}

class WifiDirectService {
  static final WifiDirectService _instance = WifiDirectService._internal();
  factory WifiDirectService() => _instance;
  WifiDirectService._internal() {
    _setupChannel();
  }

  static const _channel = MethodChannel(kWifiDirectChannel);
  final List<P2pPeer> _peers = [];
  final _peerController = StreamController<List<P2pPeer>>.broadcast();
  Stream<List<P2pPeer>> get onPeersChanged => _peerController.stream;
  List<P2pPeer> get peers => List.unmodifiable(_peers);

  bool _connected = false;
  bool _isGroupOwner = false;
  String _groupOwnerAddress = '';
  bool _p2pEnabled = false;

  bool get connected => _connected;
  bool get isGroupOwner => _isGroupOwner;
  String get groupOwnerAddress => _groupOwnerAddress;
  bool get p2pEnabled => _p2pEnabled;

  void _setupChannel() {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onP2pStateChanged':
          _p2pEnabled = call.arguments as bool? ?? false;
          AppLogger.log('WiFi Direct: estado ${_p2pEnabled ? "HABILITADO" : "DESHABILITADO"}');
          break;
        case 'onPeersChanged':
          _peers.clear();
          final peerList = call.arguments as List? ?? [];
          for (final p in peerList) {
            final map = p as Map;
            _peers.add(P2pPeer(
              name: map['name'] as String? ?? 'Unknown',
              address: map['address'] as String? ?? '',
              isGroupOwner: map['isGroupOwner'] == 'true',
            ));
          }
          AppLogger.log('WiFi Direct: ${_peers.length} peers encontrados');
          _peerController.add(List.from(_peers));
          break;
        case 'onConnectionChanged':
          final info = call.arguments as Map? ?? {};
          _connected = info['connected'] as bool? ?? false;
          _isGroupOwner = info['isGroupOwner'] as bool? ?? false;
          _groupOwnerAddress = info['groupOwnerAddress'] as String? ?? '';
          AppLogger.log('WiFi Direct: conexion=$_connected, owner=$_isGroupOwner, addr=$_groupOwnerAddress');
          break;
        case 'onP2pMessage':
          final message = call.arguments as String? ?? '';
          if (message.isNotEmpty) {
            AppLogger.log('WiFi Direct: mensaje recibido (${message.length} chars)');
            BtService()._processReceivedText(message);
          }
          break;
      }
    });
  }

  Future<bool> initialize() async {
    try {
      await _channel.invokeMethod('initialize');
      return true;
    } catch (e) {
      AppLogger.log('WiFi Direct: error inicializando: $e');
      return false;
    }
  }

  Future<bool> discoverPeers() async {
    try {
      await _channel.invokeMethod('discoverPeers');
      AppLogger.log('WiFi Direct: descubrimiento iniciado');
      return true;
    } catch (e) {
      AppLogger.log('WiFi Direct: error descubriendo: $e');
      return false;
    }
  }

  Future<void> stopDiscovery() async {
    try {
      await _channel.invokeMethod('stopDiscovery');
    } catch (e) {
      AppLogger.log('WiFi Direct: error deteniendo descubrimiento: $e');
    }
  }

  Future<bool> connect(String address) async {
    try {
      await _channel.invokeMethod('connect', {'address': address});
      AppLogger.log('WiFi Direct: conectando a $address...');
      return true;
    } catch (e) {
      AppLogger.log('WiFi Direct: error conectando: $e');
      return false;
    }
  }

  Future<void> disconnect() async {
    try {
      await _channel.invokeMethod('disconnect');
      _connected = false;
      _isGroupOwner = false;
      _groupOwnerAddress = '';
    } catch (e) {
      AppLogger.log('WiFi Direct: error desconectando: $e');
    }
  }

  Future<bool> startP2pServer() async {
    try {
      await _channel.invokeMethod('startP2pServer');
      AppLogger.log('WiFi Direct: servidor TCP P2P iniciado');
      return true;
    } catch (e) {
      AppLogger.log('WiFi Direct: error iniciando servidor: $e');
      return false;
    }
  }

  Future<void> stopP2pServer() async {
    try {
      await _channel.invokeMethod('stopP2pServer');
    } catch (e) {
      AppLogger.log('WiFi Direct: error deteniendo servidor: $e');
    }
  }

  Future<bool> sendMessage({String? host, required String message}) async {
    try {
      await _channel.invokeMethod('sendP2pMessage', {
        'host': host ?? _groupOwnerAddress,
        'message': message,
      });
      return true;
    } catch (e) {
      AppLogger.log('WiFi Direct: error enviando mensaje: $e');
      return false;
    }
  }

  void dispose() {
    _peerController.close();
  }
}

// ─── VAULT BOOKMARKS (SharedPreferences) ───
class VaultBookmarks {
  static const _key = 'vault_bookmarks';

  static Future<List<String>> getAll() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_key) ?? [];
  }

  static Future<void> add(String bookmarkId) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? [];
    if (!list.contains(bookmarkId)) {
      list.add(bookmarkId);
      await prefs.setStringList(_key, list);
    }
  }

  static Future<void> remove(String bookmarkId) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? [];
    list.remove(bookmarkId);
    await prefs.setStringList(_key, list);
  }

  static Future<bool> isBookmarked(String bookmarkId) async {
    final list = await getAll();
    return list.contains(bookmarkId);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}

// ─────────────────────────────────────────────
// HOME — 3 tabs: Dispositivos | Chat | Vault
// ─────────────────────────────────────────────
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _index = 0;
  final bt = BtService();
  bool _showSOSOverlay = false;

  @override
  void initState() {
    super.initState();
    // Start auto-connect to nearby LessNet devices
    WidgetsBinding.instance.addPostFrameCallback((_) {
      bt.startAutoConnect();

      // Iniciar LAN automáticamente (misma red WiFi)
      LanService().startFullService().catchError((e) {
        AppLogger.log('LAN autostart error: $e');
      });

      // Iniciar Wi-Fi Direct automáticamente
      WifiDirectService().initialize().then((ok) {
        if (ok) {
          WifiDirectService().discoverPeers().catchError((e) {
            AppLogger.log('P2P discover error: $e');
          });
          WifiDirectService().startP2pServer().catchError((e) {
            AppLogger.log('P2P server error: $e');
          });
        }
      }).catchError((e) {
        AppLogger.log('P2P init error: $e');
      });
    });
  }

  @override
  void dispose() {
    bt.stopAutoConnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(
            index: _index,
            children: const [
              ScanPage(),
              ChatListPage(),
              VaultHomePage(),
              ProfilePage(),
            ],
          ),
          // SOS FAB - always visible
          if (_index != 3)
            Positioned(
              right: 16,
              bottom: 90,
              child: FloatingActionButton(
                onPressed: () {
                  setState(() => _showSOSOverlay = true);
                },
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                mini: false,
                child: const Text('SOS', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
              ),
            ),
          // SOS Overlay
          if (_showSOSOverlay)
            SOSOverlay(
              onCancel: () => setState(() => _showSOSOverlay = false),
              onSend: (sosData) {
                setState(() => _showSOSOverlay = false);
                bt.sendMessage(sosData, deviceId: kGlobalChatId);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('SOS enviado a todos los dispositivos'),
                    backgroundColor: Colors.redAccent,
                    duration: Duration(seconds: 3),
                  ),
                );
              },
            ),
          // Debug overlay
          if (AppLogger.isDebugMode)
            const Positioned(
              left: 8,
              top: 60,
              right: 8,
              child: DebugOverlay(),
            ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: const Color(0xFF111111),
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
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
          NavigationDestination(
            icon: Icon(Icons.folder_outlined),
            selectedIcon: Icon(Icons.folder),
            label: 'Vault',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Perfil',
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// PERMISOS GATE — Full-screen, shown only on first launch
// or when essential permissions are revoked
// ─────────────────────────────────────────────
class PermissionsGatePage extends StatefulWidget {
  final VoidCallback onAccepted;
  const PermissionsGatePage({super.key, required this.onAccepted});

  @override
  State<PermissionsGatePage> createState() => _PermissionsGatePageState();
}

class _PermissionsGatePageState extends State<PermissionsGatePage> {
  List<_PermItem> get _perms => [
    _PermItem('Ubicacion', Icons.location_on,
        Permission.locationWhenInUse, 'Requerida para BT scan'),
    _PermItem('Bluetooth Scan', Icons.bluetooth_searching,
        Permission.bluetoothScan, 'Buscar dispositivos'),
    _PermItem('Bluetooth Connect', Icons.bluetooth_connected,
        Permission.bluetoothConnect, 'Conectarse a dispositivos'),
    _PermItem('Bluetooth Advertise', Icons.broadcast_on_personal,
        Permission.bluetoothAdvertise, 'Hacerse visible'),
    _PermItem('WiFi Cercano', Icons.wifi_tethering,
        Permission.nearbyWifiDevices, 'Hotspot y WiFi Direct'),
    _PermItem('Fotos y Videos', Icons.photo_camera,
        _mediaPermission, 'Enviar imagenes y videos'),
    _PermItem('Notificaciones', Icons.notifications,
        Permission.notification, 'Alertas de mensajes y SOS'),
  ];

  Permission get _mediaPermission {
    // On Android 33+ use granular media permissions
    // On older versions use storage
    try {
      if (Platform.isAndroid) {
        // permission_handler handles this internally
        // Permission.photos works on Android 33+
        // We'll request both and handle gracefully
        return Permission.photos;
      }
    } catch (_) {}
    return Permission.storage;
  }

  List<Permission> get _extraMediaPerms {
    try {
      if (Platform.isAndroid) {
        return [Permission.videos, Permission.storage];
      }
    } catch (_) {}
    return [];
  }

  final Map<Permission, PermissionStatus> _statuses = {};
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _checkAll();
  }

  Future<void> _checkAll() async {
    for (final p in _perms) {
      try {
        final s = await p.permission.status;
        if (mounted) setState(() => _statuses[p.permission] = s);
      } catch (_) {
        if (mounted) setState(() => _statuses[p.permission] = PermissionStatus.denied);
      }
    }
  }

  Future<void> _requestAll() async {
    setState(() => _loading = true);
    try {
      final permsToRequest = <Permission>[];
      for (final p in _perms) {
        try {
          final status = await p.permission.status;
          if (!status.isGranted) {
            permsToRequest.add(p.permission);
          } else {
            if (mounted) setState(() => _statuses[p.permission] = status);
          }
        } catch (_) {}
      }
      // Also request extra media perms for Android
      for (final p in _extraMediaPerms) {
        try {
          final status = await p.status;
          if (!status.isGranted) {
            permsToRequest.add(p);
          }
        } catch (_) {}
      }
      if (permsToRequest.isNotEmpty) {
        final r = await permsToRequest.request();
        if (mounted) setState(() => _statuses.addAll(r));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _allEssentialGranted {
    for (final p in _perms) {
      final st = _statuses[p.permission];
      if (st == null || !st.isGranted) return false;
    }
    return true;
  }

  void _onAccept() {
    if (_allEssentialGranted) {
      widget.onAccepted();
    } else {
      _requestAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            children: [
              // ─── Close / X button top center ───
              Align(
                alignment: Alignment.topCenter,
                child: Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _kCardBgLight,
                    shape: BoxShape.circle,
                  ),
                  child: GestureDetector(
                    onTap: _allEssentialGranted ? widget.onAccepted : null,
                    child: Icon(
                      Icons.close,
                      color: _allEssentialGranted ? Colors.white : Colors.white24,
                      size: 22,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              // ─── Title ───
              const Text(
                'Aceptar permisos\nrequeridos',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 28),
              // ─── Permission cards ───
              Expanded(
                child: ListView.separated(
                  itemCount: _perms.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, index) {
                    final p = _perms[index];
                    final st = _statuses[p.permission];
                    final granted = st?.isGranted ?? false;
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: _kCardBg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(p.icon,
                              color: granted ? Colors.white : Colors.white38,
                              size: 22),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(p.name,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    )),
                                const SizedBox(height: 2),
                                Text(p.desc,
                                    style: TextStyle(
                                      color: Color(0x66FFFFFF),
                                      fontSize: 12,
                                    )),
                              ],
                            ),
                          ),
                          Icon(
                            granted ? Icons.check_circle : Icons.check_circle_outline,
                            color: granted ? Colors.white : Colors.white24,
                            size: 22,
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              // ─── Accept button ───
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  icon: _loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black,
                          ),
                        )
                      : const Icon(Icons.check, size: 20),
                  label: Text(
                    _loading
                        ? 'Solicitando...'
                        : (_allEssentialGranted ? 'Aceptar' : 'Solicitar permisos'),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onPressed: _loading ? null : _onAccept,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // ─── Continue without permissions button ───
              TextButton(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: const Color(0xFF1A1A1A),
                      title: const Text('Continuar sin permisos?',
                          style: TextStyle(color: Colors.white)),
                      content: const Text(
                        'Algunas funciones de la app pueden no funcionar correctamente sin los permisos necesarios. '
                        'Por ejemplo, no podras buscar dispositivos Bluetooth, enviar mensajes o usar el GPS.\n\n'
                        'Puedes otorgar los permisos mas tarde desde la configuracion del sistema.',
                        style: TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Cancelar'),
                        ),
                        FilledButton(
                          onPressed: () {
                            Navigator.pop(ctx);
                            widget.onAccepted();
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.redAccent,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Continuar sin permisos'),
                        ),
                      ],
                    ),
                  );
                },
                child: const Text(
                  'Continuar sin permisos',
                  style: TextStyle(
                    color: Color(0xFF666666),
                    fontSize: 13,
                    decoration: TextDecoration.underline,
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

class _PermItem {
  final String name;
  final IconData icon;
  final Permission permission;
  final String desc;
  const _PermItem(this.name, this.icon, this.permission, this.desc);
}

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

  // ─── LAN & P2P state ───
  StreamSubscription? _lanSub;
  StreamSubscription? _p2pSub;
  List<LanDevice> _lanDevices = [];
  List<P2pPeer> _p2pPeers = [];

  // ─── Hotspot state ───
  static const _hotspotChannel = MethodChannel(kHotspotChannel);
  bool _hotspotEnabled = false;
  int _hotspotClients = 0;
  String _hotspotSsid = 'LessNet';
  String _hotspotError = '';

  @override
  void initState() {
    super.initState();
    _connSub = bt.onConnectionChange.listen((_) {
      if (mounted) setState(() {});
    });
    _advSub = bt.onAdvertisingChange.listen((a) {
      if (mounted) {
        setState(() {});
        if (a) {
          _advSec = 0;
          _advTimer?.cancel();
          _advTimer = Timer.periodic(const Duration(seconds: 1),
              (_) {
            if (mounted) setState(() => _advSec++);
          });
        } else {
          _advTimer?.cancel();
          _advTimer = null;
        }
      }
    });
    _statusSub = bt.onStatusChange.listen((m) {
      if (!mounted) return;
      // Detect auto-connect request
      if (m.startsWith('AUTO_CONNECT_REQUEST:')) {
        final devId = m.substring('AUTO_CONNECT_REQUEST:'.length);
        _showAutoConnectDialog(devId);
        return;
      }
      // Detect SOS received
      if (m.startsWith('SOS_RECEIVED:')) {
        final sosData = m.substring('SOS_RECEIVED:'.length);
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🆘 ALERTA SOS: $sosData'),
            backgroundColor: Colors.red[900],
            duration: const Duration(seconds: 10),
          ),
        );
        return;
      }
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(m),
          backgroundColor: Colors.grey[800],
        ),
      );
    });

    // LAN device discovery
    _lanSub = LanService().onDevicesChanged.listen((devices) {
      if (mounted) setState(() => _lanDevices = devices);
    });

    // Wi-Fi Direct peer discovery
    _p2pSub = WifiDirectService().onPeersChanged.listen((peers) {
      if (mounted) setState(() => _p2pPeers = peers);
    });
  }

  Future<void> _startScan() async {
    // Don't restart if already scanning
    if (_scanning) return;

    if (bt.isAdvertising) await bt.stopAdvertising();

    // Request permissions — BLUETOOTH_SCAN with neverForLocation on Android 12+
    // means we don't strictly need location, but we request it anyway for
    // Android < 12 compatibility and for location features (SOS, map).
    final st = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();

    AppLogger.log('Permisos: scan=${st[Permission.bluetoothScan]?.isGranted}, '
        'connect=${st[Permission.bluetoothConnect]?.isGranted}, '
        'location=${st[Permission.locationWhenInUse]?.isGranted}');

    if (!(st[Permission.bluetoothScan]?.isGranted ?? false) ||
        !(st[Permission.bluetoothConnect]?.isGranted ?? false)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Concede permisos de Bluetooth primero'),
          backgroundColor: Colors.red,
        ));
      }
      return;
    }

    // Check BT is ON
    try {
      final a = await FlutterBluePlus.adapterState.first.timeout(
        const Duration(seconds: 3),
        onTimeout: () => BluetoothAdapterState.unknown,
      );
      AppLogger.log('Bluetooth adapter state: $a');
      if (a != BluetoothAdapterState.on) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Bluetooth APAGADO! Enciende Bluetooth primero.'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 5),
          ));
        }
        return;
      }
    } catch (e) {
      AppLogger.log('Error checking BT adapter: $e');
    }

    _results.clear();
    setState(() => _scanning = true);
    _scanSeconds = 0;
    _scanTimer?.cancel();
    _scanTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _scanSeconds++);
    });

    try {
      // Try scan with UUID filter first for efficient discovery.
      // Some devices (OPPO/Realme) may not support 128-bit UUID scan filters,
      // so we fall back to unfiltered scan if no results appear.
      AppLogger.log('Iniciando escaneo BLE con filtro UUID...');
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 60),
        withServices: [Guid(lessnetServiceUuid)],
        androidUsesFineLocation: false,
      );
      _scanSub = FlutterBluePlus.scanResults.listen((r) {
        if (mounted) {
          setState(() {
            _results.clear();
            _results.addAll(r);
          });
          if (r.isNotEmpty) {
            AppLogger.log('Scan: ${r.length} resultados LessNet encontrados');
          }
        }
      });
      // After 10 seconds, if no LessNet devices found with UUID filter,
      // automatically fall back to unfiltered scan (some devices with
      // advertising legacy without name don't appear in UUID-filtered scan)
      Timer(const Duration(seconds: 10), () {
        if (!mounted || !_scanning) return;
        final lessNetResults = _results.where((r) {
          return r.advertisementData.serviceUuids.any(
            (u) => u.str128.toLowerCase() == lessnetServiceUuid.toLowerCase(),
          );
        }).toList();
        if (lessNetResults.isEmpty && _scanning) {
          AppLogger.log('Sin resultados con filtro UUID despues de 10s, '
              'reintentando sin filtro...');
          _startUnfilteredScan();
        }
      });
      _scanningSub = FlutterBluePlus.isScanning.listen((s) {
        if (!s && mounted) {
          // Check if we found any LessNet devices with the UUID filter
          final lessNetResults = _results.where((r) {
            return r.advertisementData.serviceUuids.any(
              (u) => u.str128.toLowerCase() == lessnetServiceUuid.toLowerCase(),
            );
          }).toList();
          // If no LessNet devices found with filter, retry without filter
          if (_results.isEmpty || lessNetResults.isEmpty) {
            AppLogger.log('Sin resultados con filtro UUID, '
                'reintentando sin filtro...');
            _startUnfilteredScan();
          } else {
            setState(() => _scanning = false);
            _scanTimer?.cancel();
          }
        }
      });
    } catch (e) {
      AppLogger.log('Error en escaneo con filtro: $e, intentando sin filtro...');
      // Fallback: scan without UUID filter
      try {
        await _startUnfilteredScan();
      } catch (e2) {
        AppLogger.log('Error en escaneo sin filtro: $e2');
        if (mounted) {
          setState(() => _scanning = false);
          _scanTimer?.cancel();
        }
      }
    }
  }

  /// Fallback scan without UUID filter for devices that don't support 128-bit UUID filters.
  Future<void> _startUnfilteredScan() async {
    await FlutterBluePlus.stopScan();
    await FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 60),
      androidUsesFineLocation: true,
    );
    _scanSub?.cancel();
    _scanSub = FlutterBluePlus.scanResults.listen((r) {
      if (mounted) {
        setState(() {
          _results.clear();
          _results.addAll(r);
        });
      }
    });
    _scanningSub?.cancel();
    _scanningSub = FlutterBluePlus.isScanning.listen((s) {
      if (!s && mounted) {
        setState(() => _scanning = false);
        _scanTimer?.cancel();
        _scanTimer = null;
        AppLogger.log('Scan sin filtro completo: ${_results.length} resultados totales');
      }
    });
  }

  Future<void> _stopScan() async {
    await FlutterBluePlus.stopScan();
    _scanSub?.cancel();
    _scanningSub?.cancel();
    _scanTimer?.cancel();
    _scanTimer = null;
    if (mounted) setState(() => _scanning = false);
  }

  Future<void> _startAdv() async {
    if (_scanning) await _stopScan();

    // Request BLUETOOTH_ADVERTISE permission on Android 12+
    try {
      final advStatus = await Permission.bluetoothAdvertise.status;
      if (!advStatus.isGranted) {
        final result = await Permission.bluetoothAdvertise.request();
        if (!result.isGranted) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Se requiere permiso de Bluetooth Advertise para ser visible'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 4),
            ));
          }
          return;
        }
      }
    } catch (_) {}

    try {
      await bt.startAdvertising();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Visible! El otro celular debe buscar.'),
          backgroundColor: Colors.grey,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Este celular NO soporta advertising. Usalo para BUSCAR.'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 6),
        ));
      }
    }
  }

  Future<void> _connect(BluetoothDevice d) async {
    try {
      await bt.connectToDevice(d);
      await _stopScan();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  Future<void> _showAutoConnectDialog(String deviceId) async {
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Dispositivo encontrado',
            style: TextStyle(color: Colors.white)),
        content: Text(
          'Se encontró "$deviceId" cerca. ¿Conectar?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Ignorar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: Colors.white, foregroundColor: Colors.black),
            child: const Text('Conectar'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      // Search for the device in current scan results
      try {
        final scanResult = _results.firstWhere(
          (r) => (r.device.platformName.isNotEmpty
              ? r.device.platformName
              : r.device.remoteId.toString()) == deviceId,
          orElse: () => _results.isNotEmpty ? _results.first : throw StateError('no results'),
        );
        await _connect(scanResult.device);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('No se pudo encontrar el dispositivo para conectar'),
            backgroundColor: Colors.orange,
          ));
        }
      }
    }
  }

  String _fmt(int s) {
    return '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
  }

  Future<void> _renameDevice(String deviceId) async {
    final currentName = await DeviceNames.getName(deviceId);
    final fallbackName = bt.getDeviceName(deviceId);
    final ctrl = TextEditingController(text: currentName.isNotEmpty ? currentName : '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text('Renombrar $fallbackName', style: const TextStyle(color: Colors.white)),
        content: TextField(
          controller: ctrl,
          style: const TextStyle(color: Colors.white),
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Nombre personalizado...',
            hintStyle: const TextStyle(color: Color(0xFF3A3A3A)),
            filled: true,
            fillColor: const Color(0xFF151515),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (result != null) {
      await DeviceNames.setName(deviceId, result);
      if (mounted) setState(() {});
    }
  }

  Future<void> _toggleHotspot() async {
    if (_hotspotEnabled) {
      try {
        await _hotspotChannel.invokeMethod('stopHotspot');
        if (mounted) setState(() { _hotspotEnabled = false; _hotspotClients = 0; _hotspotError = ''; });
        AppLogger.log('Hotspot detenido');
      } catch (e) {
        if (mounted) setState(() => _hotspotError = 'Error al detener: $e');
      }
    } else {
      try {
        // Request NEARBY_WIFI_DEVICES permission (required on Android 13+ for hotspot)
        final nearbyStatus = await Permission.nearbyWifiDevices.request();
        if (!nearbyStatus.isGranted) {
          // Fall back to location permission on older Android
          final locStatus = await Permission.locationWhenInUse.request();
          if (!locStatus.isGranted) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Se requiere permiso de WiFi cercano o ubicacion para el hotspot'),
                backgroundColor: Colors.redAccent,
              ));
            }
            return;
          }
        }

        final ssidCtrl = TextEditingController(text: _hotspotSsid);
        final ssid = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1A1A1A),
            title: const Text('Iniciar Hotspot', style: TextStyle(color: Colors.white)),
            content: TextField(
              controller: ssidCtrl,
              style: const TextStyle(color: Colors.white),
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Nombre del hotspot...',
                hintStyle: TextStyle(color: Color(0xFF3A3A3A)),
              ),
              onSubmitted: (v) => Navigator.pop(ctx, v),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, null),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, ssidCtrl.text),
                style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black),
                child: const Text('Iniciar'),
              ),
            ],
          ),
        );
        if (ssid == null || ssid.isEmpty) return;
        _hotspotSsid = ssid;
        await _hotspotChannel.invokeMethod('startHotspot', {'ssid': ssid, 'password': 'lessnet123'});
        if (mounted) setState(() { _hotspotEnabled = true; _hotspotError = ''; });
        AppLogger.log('Hotspot iniciado: $ssid');
      } catch (e) {
        if (mounted) setState(() { _hotspotEnabled = false; _hotspotError = 'Hotspot no disponible: $e'; });
        AppLogger.log('Error hotspot: $e');
      }
    }
  }

  Future<void> _connectToWifi(String ssid) async {
    try {
      await _hotspotChannel.invokeMethod('connectToWifi', {'ssid': ssid, 'password': 'lessnet123'});
      AppLogger.log('Conectando a WiFi: $ssid');
    } catch (e) {
      AppLogger.log('Error WiFi: $e');
    }
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _scanningSub?.cancel();
    _connSub?.cancel();
    _advSub?.cancel();
    _statusSub?.cancel();
    _lanSub?.cancel();
    _p2pSub?.cancel();
    _advTimer?.cancel();
    _scanTimer?.cancel();
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Filter to only show LessNet devices
    final lessNetResults = _results.where((r) {
      return r.advertisementData.serviceUuids.any(
        (u) => u.str128.toLowerCase() == lessnetServiceUuid.toLowerCase(),
      );
    }).toList();

    final sorted = List<ScanResult>.from(lessNetResults)..sort((a, b) {
      return b.rssi.compareTo(a.rssi);
    });

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Header(
              'Dispositivos',
              Icons.bluetooth_searching,
              bt.centralConnectionCount > 0
                  ? '${bt.centralConnectionCount} conectado${bt.centralConnectionCount > 1 ? 's' : ''}'
                  : bt.isAdvertising
                      ? 'Visible y esperando'
                      : bt.advertisingError.isNotEmpty
                          ? 'Sin conexion'
                          : 'Sin conexion',
              subtitleColor: bt.isConnected ? Colors.greenAccent : (bt.isAdvertising ? Colors.blueAccent : Colors.white38),
            ),
            const SizedBox(height: 16),

            // Connected devices cards (show all)
            ...bt.connectedDeviceIds.map((devId) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _kCardBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: devId == bt.activeDeviceId
                        ? Color(0x4D69F0AE)
                        : _kBorder),
              ),
              child: Row(
                children: [
                  Icon(
                    devId == bt.activeDeviceId
                        ? Icons.bluetooth_connected
                        : Icons.bluetooth,
                    color: devId == bt.activeDeviceId ? Colors.greenAccent : Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FutureBuilder<String>(
                      future: DeviceNames.getDisplayName(devId, bt.getDeviceName(devId)),
                      builder: (_, snap) {
                        final displayName = snap.data ?? bt.getDeviceName(devId);
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(displayName,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: devId == bt.activeDeviceId ? FontWeight.w600 : FontWeight.w400,
                                )),
                            if (displayName != bt.getDeviceName(devId))
                              Text(bt.getDeviceName(devId),
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.3),
                                    fontSize: 10,
                                  )),
                          ],
                        );
                      },
                    ),
                  ),
                  IconButton(
                    onPressed: () => _renameDevice(devId),
                    icon: const Icon(Icons.edit, color: Colors.white38, size: 16),
                    tooltip: 'Renombrar',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                  TextButton(
                    onPressed: () => bt.disconnectDevice(devId),
                    child: const Text('Desconectar',
                        style: TextStyle(color: Colors.redAccent)),
                  ),
                ],
              ),
            )),

            // Advertising indicator
            if (bt.isAdvertising && !bt.isConnected)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _kCardBgLight,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: _kBorder),
                ),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white54,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Esperando conexion... ${_fmt(_advSec)}',
                        style: TextStyle(
                          color: Color(0x99FFFFFF),
                          fontSize: 13,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        bt.stopAdvertising();
                        _advTimer?.cancel();
                        _advTimer = null;
                        _advSec = 0;
                        setState(() {});
                      },
                      child: const Text('Detener',
                          style:
                              TextStyle(color: Colors.redAccent)),
                    ),
                  ],
                ),
              ),

            // Advertising error
            if (bt.advertisingError.isNotEmpty &&
                !bt.isAdvertising)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Color(0x0DF44336),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Advertising no disponible. Usa ESTE celular para BUSCAR.',
                  style: TextStyle(
                    color: Color(0x99FFFFFF),
                    fontSize: 12,
                  ),
                ),
              ),

            // Two mode buttons
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    icon: _scanning
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.black,
                            ),
                          )
                        : const Icon(Icons.search),
                    label: Text(
                      _scanning ? _fmt(_scanSeconds) : 'Buscar',
                      style: const TextStyle(fontSize: 13),
                    ),
                    onPressed: _scanning
                        ? _stopScan
                        : (bt.isAdvertising ? null : _startScan),
                    style: FilledButton.styleFrom(
                      padding:
                          const EdgeInsets.symmetric(vertical: 12),
                      backgroundColor:
                          _scanning ? Colors.grey : Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    icon: bt.isAdvertising
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.black,
                            ),
                          )
                        : const Icon(Icons.broadcast_on_personal),
                    label: Text(
                      bt.isAdvertising
                          ? _fmt(_advSec)
                          : 'Visible',
                      style: const TextStyle(fontSize: 13),
                    ),
                    onPressed: bt.isPeripheralConnected
                        ? null
                        : (bt.isAdvertising
                            ? () {
                                bt.stopAdvertising();
                                _advTimer?.cancel();
                                _advSec = 0;
                                setState(() {});
                              }
                            : _startAdv),
                    style: FilledButton.styleFrom(
                      backgroundColor: bt.isAdvertising
                          ? Colors.grey
                          : Colors.white,
                      padding:
                          const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),

            // Hotspot toggle
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: Icon(
                  _hotspotEnabled ? Icons.wifi : Icons.wifi_off,
                  color: _hotspotEnabled ? Colors.greenAccent : Colors.white38,
                  size: 18,
                ),
                label: Text(
                  _hotspotEnabled
                      ? 'Hotspot: $_hotspotSsid ($_hotspotClients clientes)'
                      : 'Iniciar Hotspot WiFi',
                  style: TextStyle(
                    color: _hotspotEnabled ? Colors.greenAccent : Colors.white54,
                    fontSize: 13,
                  ),
                ),
                onPressed: _toggleHotspot,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  side: BorderSide(
                    color: _hotspotEnabled ? Colors.greenAccent.withOpacity(0.3) : const Color(0x1AFFFFFF),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            if (_hotspotError.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 6),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0x0DF44336),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_hotspotError,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 11)),
              ),

            // Buscar por Wi-Fi Direct button
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.wifi_tethering, color: Colors.white38, size: 18),
                label: const Text('Buscar por Wi-Fi Direct',
                    style: TextStyle(color: Colors.white54, fontSize: 13)),
                onPressed: () async {
                  final ok = await WifiDirectService().discoverPeers();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(ok ? 'Buscando por Wi-Fi Direct...' : 'Wi-Fi Direct no disponible'),
                      backgroundColor: Colors.grey[800],
                    ));
                  }
                },
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  side: const BorderSide(color: Color(0x1AFFFFFF)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Scan results
            if (_scanning || lessNetResults.isNotEmpty) ...[
              Row(
                children: [
                  Text(
                    'Dispositivos LessNet (${lessNetResults.length})',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (_scanning)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white38,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              ...sorted.map((r) {
                final isC = bt.connectedDevice?.remoteId ==
                    r.device.remoteId;
                final name = r.device.platformName.isNotEmpty
                    ? r.device.platformName
                    : 'Desconocido';
                final sig = r.rssi > -60
                    ? Colors.greenAccent
                    : r.rssi > -80
                        ? Colors.orangeAccent
                        : Colors.redAccent;
                final deviceId = r.device.platformName.isNotEmpty
                    ? r.device.platformName
                    : r.device.remoteId.toString();

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _kCardBgLight,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _kBorder),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.phone_android,
                        color: Colors.white,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FutureBuilder<String>(
                          future: DeviceNames.getDisplayName(deviceId, name),
                          builder: (_, snap) {
                            final displayName = snap.data ?? name;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(displayName,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    )),
                                Container(
                                  padding: const EdgeInsets
                                      .symmetric(
                                      horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: Color(0x1FFFFFFF),
                                    borderRadius:
                                        BorderRadius.circular(3),
                                  ),
                                  child: const Text('LessNet',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 8,
                                        fontWeight: FontWeight.w700,
                                      )),
                                ),
                                Text(
                                  r.device.remoteId.toString(),
                                  style: const TextStyle(
                                    color: Color(0x40FFFFFF),
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: Color.fromARGB(31, sig.red, sig.green, sig.blue),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text('${r.rssi}',
                            style: TextStyle(
                              color: sig,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            )),
                      ),
                      if (!isC)
                        Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: TextButton(
                            onPressed: () => _connect(r.device),
                            child: const Text('Conectar',
                                style: TextStyle(fontSize: 11)),
                          ),
                        ),
                    ],
                  ),
                );
              }),
            // Dispositivos LAN (misma red WiFi)
            if (_lanDevices.isNotEmpty) ...[
              const SizedBox(height: 16),
              Row(children: [
                const Icon(Icons.wifi, color: Colors.white38, size: 16),
                const SizedBox(width: 8),
                Text('Misma red WiFi (${_lanDevices.length})',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
              ]),
              const SizedBox(height: 8),
              ..._lanDevices.map((d) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _kCardBgLight,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _kBorder),
                ),
                child: Row(children: [
                  const Icon(Icons.wifi, color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(d.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                      Text('${d.host}:${d.port}', style: const TextStyle(color: Colors.white38, fontSize: 10)),
                    ],
                  )),
                  TextButton(
                    onPressed: () {
                      bt.setActiveDevice(d.name);
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => ChatPage(deviceId: d.name),
                      ));
                    },
                    child: const Text('Chat', style: TextStyle(fontSize: 11)),
                  ),
                ]),
              )),
            ],

            // Dispositivos Wi-Fi Direct
            if (_p2pPeers.isNotEmpty) ...[
              const SizedBox(height: 16),
              Row(children: [
                const Icon(Icons.wifi_tethering, color: Colors.white38, size: 16),
                const SizedBox(width: 8),
                Text('Wi-Fi Direct (${_p2pPeers.length})',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
              ]),
              const SizedBox(height: 8),
              ..._p2pPeers.map((p) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _kCardBgLight,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _kBorder),
                ),
                child: Row(children: [
                  const Icon(Icons.wifi_tethering, color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                      Text(p.address, style: const TextStyle(color: Colors.white38, fontSize: 10)),
                    ],
                  )),
                  TextButton(
                    onPressed: () async {
                      final ok = await WifiDirectService().connect(p.address);
                      if (ok && mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Conectando a ${p.name}...'), backgroundColor: Colors.grey[800]),
                        );
                      }
                    },
                    child: const Text('Conectar', style: TextStyle(fontSize: 11)),
                  ),
                ]),
              )),
            ],
          ] else if (!_scanning &&
                !bt.isAdvertising &&
                !bt.isConnected)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 30),
                  child: Text(
                    'Presiona Buscar o Visible\npara empezar',
                    style:
                        const TextStyle(color: Color(0xFF2F2F2F)),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// CHAT LIST — List of device conversations
// ─────────────────────────────────────────────
class ChatListPage extends StatefulWidget {
  const ChatListPage({super.key});

  @override
  State<ChatListPage> createState() => _ChatListPageState();
}

class _ChatListPageState extends State<ChatListPage> {
  final bt = BtService();
  List<DeviceConversation> _conversations = [];
  bool _loading = true;
  StreamSubscription? _msgSub;
  StreamSubscription? _connSub;
  StreamSubscription? _scanSub;
  StreamSubscription? _scanningSub;
  StreamSubscription? _statusSub;
  List<ScanResult> _searchResults = [];
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _loadConversations();
    _msgSub = bt.onMessage.listen((_) {
      if (mounted) _loadConversations();
    });
    _connSub = bt.onConnectionChange.listen((_) {
      if (mounted) _loadConversations();
    });
    _statusSub = bt.onStatusChange.listen((m) {
      if (!mounted) return;
      if (m.startsWith('SOS_RECEIVED:')) {
        final sosData = m.substring('SOS_RECEIVED:'.length);
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🆘 ALERTA SOS: $sosData'),
            backgroundColor: Colors.red[900],
            duration: const Duration(seconds: 10),
          ),
        );
      }
    });
  }

  Future<void> _loadConversations() async {
    try {
      final convs = await MessageDB.getDeviceList();
      if (mounted) setState(() {
        _conversations = convs;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _fmtTime(DateTime t) {
    final now = DateTime.now();
    final diff = now.difference(t);
    if (diff.inDays == 0) {
      return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    } else if (diff.inDays == 1) {
      return 'Ayer';
    } else if (diff.inDays < 7) {
      const days = ['Lun', 'Mar', 'Mie', 'Jue', 'Vie', 'Sab', 'Dom'];
      return days[t.weekday - 1];
    } else {
      return '${t.day}/${t.month}';
    }
  }

  Future<void> _deleteConversation(String deviceId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Eliminar chat', style: TextStyle(color: Colors.white)),
        content: Text(
          'Seguro que quieres eliminar la conversacion con ${deviceId.isEmpty ? "General" : deviceId}? Esta accion no se puede deshacer.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await MessageDB.deleteByDevice(deviceId);
      bt.messages.removeWhere((m) => m.deviceId == deviceId);
      _loadConversations();
    }
  }

  @override
  void dispose() {
    _msgSub?.cancel();
    _connSub?.cancel();
    _scanSub?.cancel();
    _scanningSub?.cancel();
    _statusSub?.cancel();
    super.dispose();
  }

  Future<void> _searchForDevice() async {
    setState(() { _searching = true; _searchResults.clear(); });

    try {
      final st = await [
        Permission.locationWhenInUse,
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
      ].request();

      if (!(st[Permission.bluetoothScan]?.isGranted ?? false)) {
        if (mounted) {
          setState(() => _searching = false);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Concede permisos de Bluetooth'),
            backgroundColor: Colors.red,
          ));
        }
        return;
      }

      // Stop any existing scan first (auto-connect or other) to avoid conflicts
      try {
        await FlutterBluePlus.stopScan();
        await Future.delayed(const Duration(milliseconds: 500));
      } catch (_) {}

      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 15),
        androidUsesFineLocation: true,
      );

      _scanSub = FlutterBluePlus.scanResults.listen((results) {
        if (mounted) {
          setState(() {
            _searchResults = results.where((r) {
              return r.advertisementData.serviceUuids.any(
                (u) => u.str128.toLowerCase() == lessnetServiceUuid.toLowerCase(),
              );
            }).toList();
          });
        }
      });

      _scanningSub = FlutterBluePlus.isScanning.listen((s) {
        if (!s && mounted) {
          setState(() => _searching = false);
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() => _searching = false);
      }
    }
  }

  void _stopSearch() {
    FlutterBluePlus.stopScan();
    _scanSub?.cancel();
    _scanningSub?.cancel();
    if (mounted) setState(() { _searching = false; _searchResults.clear(); });
  }

  Future<void> _connectAndOpenChat(BluetoothDevice device) async {
    _stopSearch();
    try {
      await bt.connectToDevice(device);
      final deviceId = device.platformName.isNotEmpty
          ? device.platformName
          : device.remoteId.toString();
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChatPage(deviceId: deviceId),
          ),
        ).then((_) => _loadConversations());
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error al conectar: $e'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentDeviceId = bt.activeDeviceId;

    // Show conversation list always (even when connected, for multi-device navigation)
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: Row(
              children: [
                Expanded(
                  child: _Header(
                    'Chat',
                    Icons.chat_bubble,
                    _conversations.isEmpty
                        ? 'Sin conversaciones'
                        : bt.centralConnectionCount > 0
                            ? '${bt.centralConnectionCount} dispositivo${bt.centralConnectionCount > 1 ? 's' : ''} conectado${bt.centralConnectionCount > 1 ? 's' : ''}'
                            : '${_conversations.length} conversacion${_conversations.length > 1 ? 'es' : ''}',
                    subtitleColor: bt.isConnected ? Colors.greenAccent : Colors.white38,
                  ),
                ),
                // New chat button
                IconButton(
                  onPressed: _searching ? _stopSearch : _searchForDevice,
                  icon: _searching
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.add_circle_outline, color: Colors.white),
                  tooltip: _searching ? 'Detener busqueda' : 'Nuevo chat personal',
                ),
              ],
            ),
          ),

          // Global chat entry (always visible)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: _kCardBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _kBorder),
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ChatPage(deviceId: kGlobalChatId),
                    ),
                  ).then((_) => _loadConversations());
                },
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.greenAccent.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.public, color: Colors.greenAccent, size: 20),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Chat Global',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                )),
                            Text('Enviar a todos los dispositivos cercanos',
                                style: TextStyle(color: Color(0xFF595959), fontSize: 11)),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right, color: Colors.white24, size: 20),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Device search results (when searching)
          if (_searching || _searchResults.isNotEmpty) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text('Buscando dispositivos LessNet...',
                      style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12)),
                  const SizedBox(width: 8),
                  if (_searching)
                    const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white38)),
                ],
              ),
            ),
            const SizedBox(height: 4),
            ..._searchResults.map((r) {
              final deviceId = r.device.platformName.isNotEmpty
                  ? r.device.platformName
                  : r.device.remoteId.toString();
              final name = r.device.platformName.isNotEmpty ? r.device.platformName : 'Desconocido';
              final isAlreadyConnected = bt.isDeviceConnected(deviceId);
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                decoration: BoxDecoration(
                  color: _kCardBgLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: ListTile(
                  dense: true,
                  leading: Icon(
                    isAlreadyConnected ? Icons.bluetooth_connected : Icons.phone_android,
                    color: isAlreadyConnected ? Colors.greenAccent : Colors.white54,
                    size: 18,
                  ),
                  title: FutureBuilder<String>(
                    future: DeviceNames.getDisplayName(deviceId, name),
                    builder: (_, snap) => Text(snap.data ?? name,
                        style: const TextStyle(color: Colors.white, fontSize: 13)),
                  ),
                  trailing: isAlreadyConnected
                      ? const Text('Conectado', style: TextStyle(color: Colors.greenAccent, fontSize: 11))
                      : const Text('Conectar', style: TextStyle(color: Colors.white, fontSize: 11)),
                  onTap: isAlreadyConnected
                      ? () {
                          _stopSearch();
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ChatPage(deviceId: deviceId),
                            ),
                          ).then((_) => _loadConversations());
                        }
                      : () => _connectAndOpenChat(r.device),
                ),
              );
            }),
          ],
          // Show currently connected devices as quick-access chips
          if (bt.centralConnectionCount > 0)
            Container(
              height: 44,
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: bt.connectedDeviceIds.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final devId = bt.connectedDeviceIds[i];
                  final isActive = devId == currentDeviceId;
                  return ActionChip(
                    label: Text(bt.getDeviceName(devId)),
                    onPressed: () {
                      bt.setActiveDevice(devId);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChatPage(deviceId: devId),
                        ),
                      ).then((_) => _loadConversations());
                    },
                    backgroundColor: isActive ? _kChipBgActive : _kCardBgLight,
                    labelStyle: TextStyle(
                      color: isActive ? Colors.white : Colors.white60,
                      fontSize: 12,
                      fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
                    ),
                    side: BorderSide(
                      color: isActive ? _kBorder : _kBorderDim,
                    ),
                  );
                },
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: Colors.white))
                : _conversations.isEmpty
                    ? Center(
                        child: Text(
                          'Conecta un dispositivo para chatear',
                          style: const TextStyle(color: Color(0xFF2F2F2F)),
                          textAlign: TextAlign.center,
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadConversations,
                        color: Colors.white,
                        backgroundColor: Colors.grey[800],
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _conversations.length,
                          itemBuilder: (_, i) {
                            final conv = _conversations[i];
                            final isActive = conv.deviceId == currentDeviceId;
                            return Dismissible(
                              key: Key(conv.deviceId + conv.lastTime.millisecondsSinceEpoch.toString()),
                              direction: DismissDirection.endToStart,
                              background: Container(
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 20),
                                margin: const EdgeInsets.only(bottom: 6),
                                decoration: BoxDecoration(
                                  color: Color(0x26F44336),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(Icons.delete, color: Colors.redAccent),
                              ),
                              confirmDismiss: (_) => _deleteConversation(conv.deviceId).then((_) => false),
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 6),
                                child: Container(
                                  decoration: isActive
                                      ? BoxDecoration(
                                          color: _kCardBg,
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: _kBorder),
                                        )
                                      : BoxDecoration(
                                          color: _kCardBgDim,
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                  child: Material(
                                    color: Colors.transparent,
                                    borderRadius: BorderRadius.circular(12),
                                    child: InkWell(
                                    borderRadius: BorderRadius.circular(12),
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => ChatPage(deviceId: conv.deviceId),
                                        ),
                                      ).then((_) => _loadConversations());
                                    },
                                    onLongPress: () => _deleteConversation(conv.deviceId),
                                    child: Padding(
                                      padding: const EdgeInsets.all(14),
                                      child: Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(10),
                                            decoration: BoxDecoration(
                                              color: conv.deviceId == kGlobalChatId
                                                  ? Colors.greenAccent.withOpacity(0.1)
                                                  : isActive
                                                      ? const Color(0xFF1A1A1A)
                                                      : _kCardBgLight,
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                            child: Icon(
                                              conv.deviceId == kGlobalChatId
                                                  ? Icons.public
                                                  : (isActive ? Icons.bluetooth_connected : Icons.phone_android),
                                              color: conv.deviceId == kGlobalChatId
                                                  ? Colors.greenAccent
                                                  : (isActive ? Colors.white : Colors.white38),
                                              size: 20,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: FutureBuilder<String>(
                                              future: conv.deviceId == kGlobalChatId
                                                  ? Future.value('Chat Global')
                                                  : DeviceNames.getDisplayName(conv.deviceId, conv.displayName),
                                              builder: (_, snap) {
                                                final name = snap.data ?? conv.displayName;
                                                return Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(name,
                                                        style: TextStyle(
                                                          color: isActive ? Colors.white : Colors.white70,
                                                          fontWeight: FontWeight.w600,
                                                          fontSize: 14,
                                                        )),
                                                    const SizedBox(height: 2),
                                                    Text(conv.lastMessage,
                                                        style: const TextStyle(
                                                          color: Color(0xFF595959),
                                                          fontSize: 12,
                                                        ),
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis),
                                                  ],
                                                );
                                              },
                                            ),
                                          ),
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.end,
                                            children: [
                                              Text(
                                                _fmtTime(conv.lastTime),
                                                style: TextStyle(
                                                  color: const Color(0xFF404040),
                                                  fontSize: 11,
                                                ),
                                              ),
                                              if (conv.unreadCount > 0)
                                                Container(
                                                  margin: const EdgeInsets.only(top: 4),
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: Colors.white,
                                                    borderRadius: BorderRadius.circular(10),
                                                  ),
                                                  child: Text(
                                                    '${conv.unreadCount}',
                                                    style: const TextStyle(
                                                      color: Colors.black,
                                                      fontSize: 10,
                                                      fontWeight: FontWeight.w700,
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// CHAT — Conversation with a specific device
// ─────────────────────────────────────────────
class ChatPage extends StatefulWidget {
  final String deviceId;
  const ChatPage({super.key, this.deviceId = ''});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final bt = BtService();
  final _transportMgr = TransportManager();
  StreamSubscription? _msgSub;
  StreamSubscription? _connSub;
  StreamSubscription? _progressSub;
  StreamSubscription? _statusSub;
  StreamSubscription? _transportSub;
  bool _connected = false;
  double _sendProgress = 0;
  bool _sending = false;
  bool _loadingHistory = true;
  String _sendingFileName = '';
  TransportType _currentTransport = TransportType.ble;
  Timer? _sendTimeout;

  @override
  void initState() {
    super.initState();
    _connected = _checkConnected();
    _loadHistory();
    _msgSub = bt.onMessage.listen((_) {
      if (mounted) setState(() {});
      _toBottom();
    });
    _connSub = bt.onConnectionChange.listen((_) {
      if (mounted) setState(() => _connected = _checkConnected());
    });
    // Also listen for status changes (peripheral connect/disconnect)
    _statusSub = bt.onStatusChange.listen((_) {
      if (mounted) setState(() => _connected = _checkConnected());
    });
    // Listen for transport changes
    _transportSub = _transportMgr.onTransportChange.listen((type) {
      if (mounted) setState(() => _currentTransport = type);
    });
    // Set active device when entering chat
    if (widget.deviceId.isNotEmpty) {
      bt.setActiveDevice(widget.deviceId);
    }
    _progressSub = bt.onProgress.listen((p) {
      if (mounted && p.containsKey('progress')) {
        setState(() {
          _sendProgress = (p['progress'] as num).toDouble();
          if (p.containsKey('fileName')) {
            _sendingFileName = p['fileName'] as String;
          }
          // Update _sending based on actual BtService state
          _sending = bt.isSending;
          if (_sendProgress >= 1.0) {
            _sendProgress = 0;
            _sendingFileName = '';
            _sendTimeout?.cancel();
            _sendTimeout = null;
          }
          if (_sendProgress < 0) {
            // Error occurred
            _sendProgress = 0;
            _sendingFileName = '';
            _sendTimeout?.cancel();
            _sendTimeout = null;
          }
        });
      }
    });
  }

  /// Check if THIS chat is connected.
  /// For global chat: connected if any device is connected.
  /// For peripheral: always connected if a Central is linked to us.
  /// For central: connected if the specific device is in our connection map.
  bool _checkConnected() {
    // Global chat needs at least one connection
    if (widget.deviceId == kGlobalChatId) return bt.isConnected;
    // If this is a peripheral-side chat, just check if peripheral is connected
    if (bt.isPeripheralConnected) return true;
    // Otherwise check if the specific device is connected
    return bt.isDeviceConnected(widget.deviceId);
  }

  String _transportLabel() {
    switch (_currentTransport) {
      case TransportType.ble:
        final quality = _transportMgr.bleQuality;
        final qualityLabel = quality == TransportQuality.excellent ? ''
            : quality == TransportQuality.good ? ' (señal buena)'
            : quality == TransportQuality.weak ? ' (señal débil!)'
            : ' (sin señal!)';
        return 'BLE$qualityLabel';
      case TransportType.lan:
        return 'WiFi LAN';
      case TransportType.wifiDirect:
        return 'WiFi Direct';
      case TransportType.none:
        return 'Sin transporte';
    }
  }

  void _startSendTimeout() {
    _sendTimeout?.cancel();
    _sendTimeout = Timer(const Duration(minutes: 5), () {
      if (mounted && _sending) {
        setState(() {
          _sending = false;
          _sendProgress = 0;
          _sendingFileName = '';
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Envio cancelado: tiempo de espera agotado'),
          backgroundColor: Colors.red,
        ));
      }
    });
  }

  Future<void> _loadHistory() async {
    try {
      final saved = await MessageDB.getAll();
      if (saved.isNotEmpty && bt.messages.isEmpty) {
        bt.messages.addAll(saved);
      }
      // Also load device-specific history from DB
      if (widget.deviceId.isNotEmpty) {
        final deviceMsgs = await MessageDB.getByDevice(widget.deviceId);
        // Merge any DB messages not already in memory
        for (final m in deviceMsgs) {
          if (!bt.messages.any((e) => e.id == m.id)) {
            bt.messages.add(m);
          }
        }
        bt.messages.sort((a, b) => a.time.compareTo(b.time));
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingHistory = false);
    _toBottom();
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final t = _ctrl.text.trim();
    if (t.isEmpty) return;

    // Check connection before sending
    if (widget.deviceId == kGlobalChatId) {
      if (!bt.isConnected) return;
    } else {
      if (!_connected) return;
    }

    _ctrl.clear();
    try {
      await bt.sendMessage(t, deviceId: widget.deviceId);
    } catch (_) {}
    if (mounted) setState(() {});
    _toBottom();
  }

  Future<void> _pickImage() async {
    if (bt.isSending) return; // Prevenir doble envio
    try {
      final picker = ImagePicker();
      final xfile = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 50,
      );
      if (xfile == null) return;
      final size = await xfile.length();
      if (size > _kMaxFileSize) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Imagen muy grande (${(size / 1024 / 1024).toStringAsFixed(1)} MB). Max ${_kMaxFileSize ~/ (1024 * 1024)} MB para BLE.'),
            backgroundColor: Colors.red[900],
          ));
        }
        return;
      }
      setState(() { _sending = true; _sendingFileName = xfile.name; _sendProgress = 0; });
      _startSendTimeout();
      await bt.sendFile(
        localPath: xfile.path,
        msgType: 'image',
        fileName: xfile.name,
        deviceId: widget.deviceId,
      );
      // _sending is reset by BtService.isSending via progress listener
      if (mounted) setState(() { _sending = bt.isSending; });
      _sendTimeout?.cancel();
      _toBottom();
    } catch (e) {
      if (mounted) {
        setState(() { _sending = false; _sendProgress = 0; _sendingFileName = ''; });
        _sendTimeout?.cancel();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red[900],
        ));
      }
    }
  }

  Future<void> _pickVideo() async {
    if (bt.isSending) return;
    try {
      final picker = ImagePicker();
      final xfile = await picker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(seconds: 120),
      );
      if (xfile == null) return;
      final size = await xfile.length();
      if (size > _kMaxFileSize) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Video muy grande (${(size / 1024 / 1024).toStringAsFixed(1)} MB). Max ${_kMaxFileSize ~/ (1024 * 1024)} MB para BLE.'),
            backgroundColor: Colors.red[900],
          ));
        }
        return;
      }
      setState(() { _sending = true; _sendingFileName = xfile.name; _sendProgress = 0; });
      _startSendTimeout();
      await bt.sendFile(
        localPath: xfile.path,
        msgType: 'video',
        fileName: xfile.name,
        deviceId: widget.deviceId,
      );
      if (mounted) setState(() { _sending = bt.isSending; });
      _sendTimeout?.cancel();
      _toBottom();
    } catch (e) {
      if (mounted) {
        setState(() { _sending = false; _sendProgress = 0; _sendingFileName = ''; });
        _sendTimeout?.cancel();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red[900],
        ));
      }
    }
  }

  Future<void> _pickFile() async {
    if (bt.isSending) return;
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      if (file.path == null) return;
      final size = file.size;
      if (size > _kMaxFileSize) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Archivo muy grande (${(size / 1024 / 1024).toStringAsFixed(1)} MB). Max ${_kMaxFileSize ~/ (1024 * 1024)} MB para BLE.'),
            backgroundColor: Colors.red[900],
          ));
        }
        return;
      }
      setState(() { _sending = true; _sendingFileName = file.name; _sendProgress = 0; });
      _startSendTimeout();
      await bt.sendFile(
        localPath: file.path!,
        msgType: 'file',
        fileName: file.name,
        deviceId: widget.deviceId,
      );
      if (mounted) setState(() { _sending = bt.isSending; });
      _sendTimeout?.cancel();
      _toBottom();
    } catch (e) {
      if (mounted) {
        setState(() { _sending = false; _sendProgress = 0; _sendingFileName = ''; });
        _sendTimeout?.cancel();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red[900],
        ));
      }
    }
  }

  String _fmt(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  String _fmtSize(int? bytes) {
    if (bytes == null) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  @override
  void dispose() {
    _msgSub?.cancel();
    _connSub?.cancel();
    _progressSub?.cancel();
    _statusSub?.cancel();
    _transportSub?.cancel();
    _sendTimeout?.cancel();
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final msgs = widget.deviceId == kGlobalChatId
        ? bt.messages.where((m) => m.deviceId == kGlobalChatId).toList()
        : (widget.deviceId.isNotEmpty
            ? bt.messages.where((m) => m.deviceId == widget.deviceId).toList()
            : bt.messages);
    return PopScope(
      canPop: !bt.isSending,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        // Warn user about active transfer
        final shouldLeave = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1A1A1A),
            title: const Text('Transferencia en progreso', style: TextStyle(color: Colors.white)),
            content: const Text(
              'Si sales ahora la transferencia se cancelara. Seguro que quieres salir?',
              style: TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Quedarme'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Salir', style: TextStyle(color: Colors.redAccent)),
              ),
            ],
          ),
        );
        if (shouldLeave == true && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: Row(
              children: [
                Expanded(
                  child: _Header(
                    widget.deviceId == kGlobalChatId ? 'Chat Global' : 'Chat',
                    widget.deviceId == kGlobalChatId ? Icons.public : Icons.chat_bubble,
                    _connected
                        ? (widget.deviceId == kGlobalChatId
                            ? '${bt.centralConnectionCount} dispositivo${bt.centralConnectionCount > 1 ? 's' : ''} conectado${bt.centralConnectionCount > 1 ? 's' : ''}'
                            : 'Conectado via ${_transportLabel()}')
                        : 'Sin conexion',
                    subtitleColor: _connected
                        ? (widget.deviceId == kGlobalChatId ? Colors.greenAccent : Colors.greenAccent)
                        : Colors.white38,
                  ),
                ),
                if (widget.deviceId.isNotEmpty && widget.deviceId != kGlobalChatId)
                  IconButton(
                    onPressed: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          backgroundColor: const Color(0xFF1A1A1A),
                          title: const Text('Eliminar chat', style: TextStyle(color: Colors.white)),
                          content: Text(
                            'Seguro que quieres eliminar la conversacion con ${widget.deviceId.isEmpty ? "General" : widget.deviceId}? Esta accion no se puede deshacer.',
                            style: const TextStyle(color: Colors.white70),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('Cancelar'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('Eliminar', style: TextStyle(color: Colors.redAccent)),
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true) {
                        await MessageDB.deleteByDevice(widget.deviceId);
                        bt.messages.removeWhere((m) => m.deviceId == widget.deviceId);
                        if (mounted) Navigator.of(context).pop();
                      }
                    },
                    icon: const Icon(Icons.delete_outline, color: Colors.white38, size: 20),
                    tooltip: 'Eliminar chat',
                  ),
                // Rename device button
                if (widget.deviceId.isNotEmpty && widget.deviceId != kGlobalChatId)
                  FutureBuilder<String>(
                    future: DeviceNames.getName(widget.deviceId),
                    builder: (_, snap) {
                      return IconButton(
                        onPressed: () async {
                          final currentName = snap.data ?? '';
                          final fallbackName = bt.getDeviceName(widget.deviceId);
                          final ctrl = TextEditingController(text: currentName.isNotEmpty ? currentName : '');
                          final result = await showDialog<String>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              backgroundColor: const Color(0xFF1A1A1A),
                              title: Text('Renombrar $fallbackName', style: const TextStyle(color: Colors.white)),
                              content: TextField(
                                controller: ctrl,
                                style: const TextStyle(color: Colors.white),
                                autofocus: true,
                                decoration: InputDecoration(
                                  hintText: 'Nombre personalizado...',
                                  hintStyle: const TextStyle(color: Color(0xFF3A3A3A)),
                                  filled: true,
                                  fillColor: const Color(0xFF151515),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                                onSubmitted: (v) => Navigator.pop(ctx, v),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, null),
                                  child: const Text('Cancelar'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(ctx, ctrl.text),
                                  style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black),
                                  child: const Text('Guardar'),
                                ),
                              ],
                            ),
                          );
                          if (result != null) {
                            await DeviceNames.setName(widget.deviceId, result);
                            if (mounted) setState(() {});
                          }
                        },
                        icon: const Icon(Icons.edit, color: Colors.white38, size: 18),
                        tooltip: 'Renombrar dispositivo',
                      );
                    },
                  ),
              ],
            ),
          ),
          if (_connected)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: _kCardBgLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    widget.deviceId == kGlobalChatId ? Icons.public : Icons.bluetooth_connected,
                    color: widget.deviceId == kGlobalChatId ? Colors.greenAccent : Colors.white,
                    size: 14,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    widget.deviceId == kGlobalChatId
                        ? 'Conectado a ${bt.centralConnectionCount} dispositivo${bt.centralConnectionCount != 1 ? 's' : ''}'
                        : 'Conectado a ${bt.connectedName}',
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                  ),
                ],
              ),
            ),
          // Send progress bar with percentage
          if (_sending)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: _sendProgress > 0 ? _sendProgress : null,
                      backgroundColor: Colors.white12,
                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _sendProgress > 0
                        ? 'Enviando ${_sendingFileName.isNotEmpty ? _sendingFileName : "archivo"}... ${(_sendProgress * 100).toStringAsFixed(0)}%'
                        : 'Enviando ${_sendingFileName.isNotEmpty ? _sendingFileName : "archivo"}...',
                    style: const TextStyle(color: Color(0xFF808080), fontSize: 10),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _loadingHistory
                ? const Center(child: CircularProgressIndicator(color: Colors.white))
                : msgs.isEmpty
                    ? Center(
                        child: Text(
                          _connected
                              ? (widget.deviceId == kGlobalChatId
                                  ? 'Escribe un mensaje global\npara todos los dispositivos cercanos'
                                  : 'Escribe un mensaje')
                              : (widget.deviceId == kGlobalChatId
                                  ? 'Conecta un dispositivo para chatear globalmente'
                                  : 'Conecta un dispositivo primero'),
                          style: const TextStyle(color: Color(0xFF2F2F2F)),
                          textAlign: TextAlign.center,
                        ),
                      )
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        itemCount: msgs.length,
                        itemBuilder: (_, i) {
                          final m = msgs[i];
                          return _buildMessage(m);
                        },
                      ),
          ),
          // Input area with multimedia buttons
          Container(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
            child: Column(
              children: [
                Row(
                  children: [
                    // Attach buttons
                    if (_connected) ...[
                      IconButton(
                        onPressed: _sending ? null : _pickImage,
                        icon: const Icon(Icons.photo, size: 22),
                        style: IconButton.styleFrom(
                          foregroundColor: Colors.white54,
                        ),
                        tooltip: 'Foto',
                      ),
                      IconButton(
                        onPressed: _sending ? null : _pickVideo,
                        icon: const Icon(Icons.videocam, size: 22),
                        style: IconButton.styleFrom(
                          foregroundColor: Colors.white54,
                        ),
                        tooltip: 'Video',
                      ),
                      IconButton(
                        onPressed: _sending ? null : _pickFile,
                        icon: const Icon(Icons.attach_file, size: 22),
                        style: IconButton.styleFrom(
                          foregroundColor: Colors.white54,
                        ),
                        tooltip: 'Archivo',
                      ),
                    ],
                    Expanded(
                      child: TextField(
                        controller: _ctrl,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: _connected
                              ? (widget.deviceId == kGlobalChatId ? 'Mensaje global...' : 'Mensaje...')
                              : 'Sin conexion',
                          hintStyle: const TextStyle(color: Color(0xFF3A3A3A)),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onSubmitted: (_) {
                          if (_connected) _send();
                        },
                      ),
                    ),
                    const SizedBox(width: 6),
                    FilledButton(
                      onPressed: _connected ? _send : null,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.all(10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        disabledBackgroundColor: Colors.white12,
                      ),
                      child: const Icon(Icons.send, size: 18),
                    ),
                  ],
                ),
                if (_connected)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Max ${_kMaxFileSize ~/ (1024 * 1024)} MB por archivo (BLE)',
                      style: const TextStyle(color: Color(0xFF333333), fontSize: 10),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      ), // SafeArea
    ); // PopScope
  }

  Widget _buildMessage(ChatMessage m) {
    return Align(
      alignment: m.mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Material(
        color: Colors.transparent,
        textStyle: const TextStyle(decoration: TextDecoration.none),
        child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: const BoxConstraints(maxWidth: 280),
        decoration: BoxDecoration(
          color: m.mine ? Colors.white : _kCardBg,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(m.mine ? 14 : 4),
            bottomRight: Radius.circular(m.mine ? 4 : 14),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Media content
            if (m.type == 'image' && m.filePath != null)
              _buildImageContent(m),
            if (m.type == 'video' && m.filePath != null)
              _buildVideoContent(m),
            if (m.type == 'file' && m.fileName != null)
              _buildFileContent(m),
            // Text content (for text messages or caption)
            if (m.type == 'text')
              Text(m.text,
                  style: TextStyle(
                    color: m.mine ? Colors.black : Colors.white,
                    fontSize: 14,
                    decoration: TextDecoration.none, // Kill yellow underline
                  )),
            const SizedBox(height: 4),
            // Time + size indicator
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_fmt(m.time),
                    style: TextStyle(
                      color: m.mine ? Colors.black38 : const Color(0xFF404040),
                      fontSize: 10,
                      decoration: TextDecoration.none,
                    )),
                if (m.fileSize != null) ...[
                  const SizedBox(width: 6),
                  Text(_fmtSize(m.fileSize),
                      style: TextStyle(
                        color: m.mine ? Colors.black38 : const Color(0xFF404040),
                        fontSize: 10,
                        decoration: TextDecoration.none,
                      )),
                ],
              ],
            ),
          ],
        ),
        ),
      ),
    );
  }

  Widget _buildImageContent(ChatMessage m) {
    final file = File(m.filePath!);
    return GestureDetector(
      onTap: () => _showImagePreview(m.filePath!),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: FutureBuilder<bool>(
          future: file.exists(),
          builder: (_, snap) {
            if (snap.data == true) {
              return Image.file(
                file,
                width: 240,
                height: 180,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _buildMediaPlaceholder(Icons.broken_image, m.fileName ?? 'Imagen'),
              );
            }
            return _buildMediaPlaceholder(Icons.image, m.fileName ?? 'Imagen');
          },
        ),
      ),
    );
  }

  Widget _buildVideoContent(ChatMessage m) {
    return GestureDetector(
      onTap: () => _showVideoPlayer(m.filePath!, m.fileName ?? 'Video'),
      child: Container(
        width: 240,
        height: 160,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Video thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: _VideoThumbnail(filePath: m.filePath!),
            ),
            // Semi-transparent overlay
            Container(
              decoration: BoxDecoration(
                color: Color(0x59000000),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            // Play button centered
            Center(
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: const Color(0xFF333333),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.play_arrow, color: Colors.white, size: 32),
              ),
            ),
            // Filename at bottom
            Positioned(
              left: 8,
              right: 8,
              bottom: 8,
              child: Row(
                children: [
                  const Icon(Icons.videocam, color: Colors.white70, size: 12),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(m.fileName ?? 'Video',
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500),
                        overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFileContent(ChatMessage m) {
    return GestureDetector(
      onTap: () => _openFile(m.filePath),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: m.mine ? const Color(0xFF0F0F0F) : const Color(0xFF141414),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.insert_drive_file, color: m.mine ? Colors.black54 : Colors.white54, size: 24),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(m.fileName ?? 'Archivo',
                      style: TextStyle(
                        color: m.mine ? Colors.black87 : Colors.white,
                        fontSize: 13,
                      ),
                      overflow: TextOverflow.ellipsis),
                  if (m.fileSize != null)
                    Text(_fmtSize(m.fileSize),
                        style: TextStyle(
                          color: m.mine ? Colors.black38 : const Color(0xFF666666),
                          fontSize: 10,
                        )),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.download, color: m.mine ? Colors.black38 : Colors.white38, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildMediaPlaceholder(IconData icon, String label) {
    return Container(
      width: 240,
      height: 120,
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.white38, size: 32),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: Colors.white38, fontSize: 11)),
        ],
      ),
    );
  }

  void _showImagePreview(String path) {
    Navigator.push(context, MaterialPageRoute(builder: (_) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: Center(
          child: InteractiveViewer(
            child: Image.file(File(path), fit: BoxFit.contain),
          ),
        ),
      );
    }));
  }

  void _showVideoPlayer(String path, String title) {
    Navigator.push(context, MaterialPageRoute(builder: (_) {
      return _VideoPlayerPage(filePath: path, title: title);
    }));
  }

  Future<void> _openFile(String? path) async {
    if (path == null) return;
    final file = File(path);
    if (!await file.exists()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Archivo no encontrado: $path'),
          backgroundColor: Colors.red[900],
        ));
      }
      return;
    }
    try {
      await OpenFilex.open(path);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('No se pudo abrir el archivo: $e'),
          backgroundColor: Colors.grey[800],
        ));
      }
    }
  }
}

// ─────────────────────────────────────────────
// VIDEO PLAYER PAGE — Full-screen playback
// ─────────────────────────────────────────────
class _VideoPlayerPage extends StatefulWidget {
  final String filePath;
  final String title;
  const _VideoPlayerPage({required this.filePath, required this.title});

  @override
  State<_VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<_VideoPlayerPage> {
  late VideoPlayerController _controller;
  bool _initialized = false;
  bool _hasError = false;
  String _errorMessage = '';
  bool _showControls = true;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(File(widget.filePath))
      ..initialize().then((_) {
        if (mounted) {
          setState(() => _initialized = true);
          _controller.play();
        }
      }).catchError((e) {
        if (mounted) {
          setState(() {
            _hasError = true;
            _errorMessage = e.toString();
          });
        }
      });
    _controller.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          widget.title,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_new, color: Colors.white70),
            onPressed: () async {
              try {
                await OpenFilex.open(widget.filePath);
              } catch (_) {}
            },
            tooltip: 'Abrir con otra app',
          ),
        ],
      ),
      body: _hasError
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
                    const SizedBox(height: 16),
                    const Text(
                      'No se pudo reproducir el video',
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _errorMessage,
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: () async {
                        try {
                          await OpenFilex.open(widget.filePath);
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text('No se pudo abrir: $e'),
                              backgroundColor: Colors.red[900],
                            ));
                          }
                        }
                      },
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Abrir con otra app'),
                    ),
                  ],
                ),
              ),
            )
          : !_initialized
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(color: Colors.white),
                      SizedBox(height: 16),
                      Text('Cargando video...', style: TextStyle(color: Colors.white54, fontSize: 14)),
                    ],
                  ),
                )
              : GestureDetector(
                  onTap: () => setState(() => _showControls = !_showControls),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Video
                      Center(
                        child: AspectRatio(
                          aspectRatio: _controller.value.aspectRatio,
                          child: VideoPlayer(_controller),
                        ),
                      ),
                      // Controls overlay
                      if (_showControls)
                        Container(
                          color: Colors.black26,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              // Play/Pause + progress
                              const Spacer(),
                              GestureDetector(
                                onTap: () {
                                  if (_controller.value.isPlaying) {
                                    _controller.pause();
                                  } else {
                                    _controller.play();
                                  }
                                },
                                child: Icon(
                                  _controller.value.isPlaying ? Icons.pause_circle : Icons.play_circle,
                                  color: Colors.white,
                                  size: 64,
                                ),
                              ),
                              const Spacer(),
                              // Progress bar
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                child: Column(
                                  children: [
                                    VideoProgressIndicator(
                                      _controller,
                                      allowScrubbing: true,
                                      colors: const VideoProgressColors(
                                        playedColor: Colors.white,
                                        bufferedColor: Colors.white24,
                                        backgroundColor: Colors.white12,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          _formatDuration(_controller.value.position),
                                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                                        ),
                                        Text(
                                          _formatDuration(_controller.value.duration),
                                          style: const TextStyle(color: Colors.white54, fontSize: 12),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }
}

// ─────────────────────────────────────────────
// VIDEO THUMBNAIL — Generates thumbnail from video file
// ─────────────────────────────────────────────
class _VideoThumbnail extends StatefulWidget {
  final String filePath;
  const _VideoThumbnail({required this.filePath});

  @override
  State<_VideoThumbnail> createState() => _VideoThumbnailState();
}

class _VideoThumbnailState extends State<_VideoThumbnail> {
  VideoPlayerController? _controller;
  bool _initialized = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(File(widget.filePath))
      ..initialize().then((_) {
        if (mounted) {
          setState(() => _initialized = true);
          // Seek to 1 second to get a better thumbnail (not black first frame)
          _controller!.seekTo(const Duration(seconds: 1));
        }
      }).catchError((_) {
        if (mounted) setState(() => _hasError = true);
      });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError || !_initialized || _controller == null) {
      return Container(
        width: 240,
        height: 160,
        color: Colors.black26,
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.videocam, color: Colors.white38, size: 36),
            SizedBox(height: 4),
            Text('Video', style: TextStyle(color: Colors.white38, fontSize: 11)),
          ],
        ),
      );
    }
    return SizedBox(
      width: 240,
      height: 160,
      child: FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: _controller!.value.size.width,
          height: _controller!.value.size.height,
          child: VideoPlayer(_controller!),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// VAULT HOME — 6 secciones con acceso directo
// ─────────────────────────────────────────────
class VaultHomePage extends StatefulWidget {
  const VaultHomePage({super.key});

  @override
  State<VaultHomePage> createState() => _VaultHomePageState();
}

class _VaultHomePageState extends State<VaultHomePage> {
  List<String> _bookmarks = [];

  @override
  void initState() {
    super.initState();
    _loadBookmarks();
  }

  Future<void> _loadBookmarks() async {
    final b = await VaultBookmarks.getAll();
    if (mounted) setState(() => _bookmarks = b);
  }

  void _openBookmark(String title, String type) {
    // Navigate to the appropriate section and find the item
    if (type == 'first_aid') {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const FirstAidPage()));
    } else if (type == 'guide') {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const GuidesPage()));
    } else if (type == 'dict') {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const DictionaryPage()));
    } else if (type == 'wiki') {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const WikipediaPage()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final sections = [
      _VaultSection(
        Icons.local_hospital,
        'Primeros Auxilios',
        '12 protocolos de emergencia',
        Colors.redAccent,
        const FirstAidPage(),
      ),
      _VaultSection(
        Icons.terrain,
        'Guias de Supervivencia',
        '15 guias esenciales',
        Colors.orangeAccent,
        const GuidesPage(),
      ),
      _VaultSection(
        Icons.book,
        'Diccionario',
        '298 terminos medicos',
        Colors.purpleAccent,
        const DictionaryPage(),
      ),
      _VaultSection(
        Icons.article,
        'Wikipedia Offline',
        '61 articulos en 6 categorias',
        Colors.tealAccent,
        const WikipediaPage(),
      ),
      _VaultSection(
        Icons.map,
        'Mapa de Emergencias',
        '74 puntos en Colombia (incluye hospitales)',
        Colors.greenAccent,
        const EmergencyMapPage(),
      ),
      _VaultSection(
        Icons.translate,
        'Traductor Offline',
        'Traduccion con IA, descarga modelos',
        Colors.blueAccent,
        const TranslatorPage(),
      ),
      _VaultSection(
        Icons.flashlight_on,
        'Codigo Morse',
        'Señal de luz con linterna',
        Colors.amberAccent,
        const MorseCodePage(),
      ),
      _VaultSection(
        Icons.link,
        'Cargar desde URL',
        'Obtener contenido JSON externo',
        Colors.cyanAccent,
        const VaultUrlPage(),
      ),
    ];

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Header('Vault', Icons.folder, 'Recursos offline'),
            const SizedBox(height: 8),
            // Offline info banner
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _kCardBgDim,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.cloud_off,
                      color: Colors.white24, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Todo el contenido funciona sin internet. Datos guardados en tu telefono.',
                      style: TextStyle(
                        color: Color(0x66FFFFFF),
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Favorites section
            if (_bookmarks.isNotEmpty) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  const Icon(Icons.bookmark, color: Colors.white38, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    'Favoritos (${_bookmarks.length})',
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                constraints: const BoxConstraints(maxHeight: 120),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _bookmarks.take(8).map((b) {
                    final parts = b.split('||');
                    final title = parts.isNotEmpty ? parts[0] : b;
                    final type = parts.length > 1 ? parts[1] : '';
                    return GestureDetector(
                      onTap: () => _openBookmark(title, type),
                      child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: _kCardBgLight,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _kBorderDim),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            type == 'first_aid' ? Icons.local_hospital :
                            type == 'guide' ? Icons.terrain :
                            type == 'dict' ? Icons.book :
                            type == 'wiki' ? Icons.article : Icons.bookmark,
                            color: Colors.white38,
                            size: 12,
                          ),
                          const SizedBox(width: 4),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 100),
                            child: Text(title,
                                style: const TextStyle(color: Colors.white, fontSize: 11),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                            ),
                          ),
                        ],
                      ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
            const SizedBox(height: 16),
            // Vault sections
            ...sections.map((s) => Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: Material(
                    color: _kCardBgDim,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => s.page),
                      ).then((_) => _loadBookmarks()),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Color.fromARGB(26, s.color.red, s.color.green, s.color.blue),
                                borderRadius:
                                    BorderRadius.circular(12),
                              ),
                              child: Icon(s.icon,
                                  color: s.color, size: 24),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(s.title,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 15,
                                      )),
                                  const SizedBox(height: 2),
                                  Text(s.subtitle,
                                      style: TextStyle(
                                        color: Color(0x59FFFFFF),
                                        fontSize: 12,
                                      )),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right,
                                color: Colors.white24, size: 22),
                          ],
                        ),
                      ),
                    ),
                  ),
                )),
            const SizedBox(height: 16),
            const _VaultSearchButton(),
          ],
        ),
      ),
    );
  }
}

class _VaultSection {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final Widget page;
  const _VaultSection(
      this.icon, this.title, this.subtitle, this.color, this.page);
}

class _VaultSearchButton extends StatelessWidget {
  const _VaultSearchButton();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        icon: const Icon(Icons.search, color: Colors.white54),
        label: const Text('Busqueda Global',
            style: TextStyle(color: Colors.white70, fontSize: 14)),
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => const VaultSearchPage()),
        ),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          side: BorderSide(color: Color(0x1AFFFFFF)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// PRIMEROS AUXILIOS
// ─────────────────────────────────────────────
class FirstAidPage extends StatefulWidget {
  const FirstAidPage({super.key});

  @override
  State<FirstAidPage> createState() => _FirstAidPageState();
}

class _FirstAidPageState extends State<FirstAidPage> {
  List<dynamic> _items = [];
  List<dynamic> _filtered = [];
  bool _loading = true;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await rootBundle.loadString(
          'assets/vault/first_aid/primeros_auxilios.json');
      final d = json.decode(s);
      setState(() {
        _items = d['protocolos'] ?? [];
        _filtered = _items;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _filter(String q) {
    setState(() {
      _filtered = q.isEmpty
          ? _items
          : _items.where((t) {
              final m = t as Map<String, dynamic>;
              return (m['titulo'] ?? '').toString().toLowerCase().contains(q.toLowerCase()) ||
                  (m['resumen'] ?? '').toString().toLowerCase().contains(q.toLowerCase());
            }).toList();
    });
  }

  Color _pColor(String? p) {
    if (p?.toLowerCase() == 'critica') return Colors.redAccent;
    if (p?.toLowerCase() == 'alta') return Colors.orangeAccent;
    return Colors.white38;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111111),
        title: const Text('Primeros Auxilios',
            style: TextStyle(color: Colors.white)),
        iconTheme:
            const IconThemeData(color: Colors.white),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.white))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                  child: TextField(
                    controller: _searchCtrl,
                    style: const TextStyle(color: Colors.white),
                    onChanged: _filter,
                    decoration: InputDecoration(
                      hintText: 'Buscar protocolo...',
                      hintStyle: const TextStyle(color: Color(0xFF3A3A3A)),
                      prefixIcon: const Icon(Icons.search, color: Colors.white38),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: _filtered.isEmpty
                      ? Center(child: Text('Sin resultados', style: TextStyle(color: Colors.white24)))
                      : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _filtered.length,
              itemBuilder: (_, i) {
                final it = _filtered[i] as Map<String, dynamic>;
                final p = it['prioridad'] ?? '';
                final pc = _pColor(p);
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: _kCardBgDim,
                    borderRadius: BorderRadius.circular(12),
                    child: ListTile(
                      contentPadding:
                          const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 6),
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Color.fromARGB(26, pc.red, pc.green, pc.blue),
                          borderRadius:
                              BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.local_hospital,
                            color: _pColor(p), size: 20),
                      ),
                      title: Text(it['titulo'] ?? '',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          )),
                      subtitle: Text(it['resumen'] ?? '',
                          style: TextStyle(
                            color:
                                Color(0x4DFFFFFF),
                            fontSize: 11,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                      trailing: p.isNotEmpty
                          ? Container(
                              padding:
                                  const EdgeInsets.symmetric(
                                      horizontal: 5,
                                      vertical: 1),
                              decoration: BoxDecoration(
                                color: Color.fromARGB(38, pc.red, pc.green, pc.blue),
                                borderRadius:
                                    BorderRadius.circular(3),
                              ),
                              child: Text(p.toUpperCase(),
                                  style: TextStyle(
                                    color: _pColor(p),
                                    fontSize: 8,
                                    fontWeight: FontWeight.w700,
                                  )),
                            )
                          : null,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => _DetailPage(
                            title: it['titulo'] ?? '',
                            item: it,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
                ),
              ],
            ),
    );
  }
}

// ─────────────────────────────────────────────
// GUIAS DE SUPERVIVENCIA
// ─────────────────────────────────────────────
class GuidesPage extends StatefulWidget {
  const GuidesPage({super.key});

  @override
  State<GuidesPage> createState() => _GuidesPageState();
}

class _GuidesPageState extends State<GuidesPage> {
  List<dynamic> _items = [];
  List<dynamic> _filtered = [];
  bool _loading = true;
  String? _selectedCat;
  Set<String> _categories = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await rootBundle.loadString(
          'assets/vault/guides/supervivencia.json');
      final d = json.decode(s);
      setState(() {
        _items = d['guias'] ?? [];
        _categories = _items.map((g) => (g as Map<String, dynamic>)['categoria'] as String? ?? '').where((c) => c.isNotEmpty).toSet();
        _filtered = _items;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _selectCat(String? cat) {
    _selectedCat = cat;
    _filtered = cat == null ? _items : _items.where((g) {
      return (g as Map<String, dynamic>)['categoria'] == cat;
    }).toList();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111111),
        title: const Text('Guias de Supervivencia',
            style: TextStyle(color: Colors.white)),
        iconTheme:
            const IconThemeData(color: Colors.white),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.white))
          : Column(
              children: [
                if (_categories.isNotEmpty)
                  SizedBox(
                    height: 44,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: FilterChip(
                            label: const Text('Todo'),
                            selected: _selectedCat == null,
                            onSelected: (_) => _selectCat(null),
                            backgroundColor: _kCardBgLight,
                            selectedColor: _kChipBgActive,
                            labelStyle: TextStyle(
                              color: _selectedCat == null ? Colors.white : Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        ..._categories.map((c) => Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: FilterChip(
                            label: Text(c[0].toUpperCase() + c.substring(1)),
                            selected: _selectedCat == c,
                            onSelected: (_) => _selectCat(c),
                            backgroundColor: _kCardBgLight,
                            selectedColor: _kChipBgActive,
                            labelStyle: TextStyle(
                              color: _selectedCat == c ? Colors.white : Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                        )),
                      ],
                    ),
                  ),
                Expanded(
                  child: _filtered.isEmpty
                      ? Center(child: Text('Sin resultados', style: TextStyle(color: Colors.white24)))
                      : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _filtered.length,
              itemBuilder: (_, i) {
                final it = _filtered[i] as Map<String, dynamic>;
                final cat = it['categoria'] ?? '';
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: _kCardBgDim,
                    borderRadius: BorderRadius.circular(12),
                    child: ListTile(
                      contentPadding:
                          const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 6),
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _kCardBgLight,
                          borderRadius:
                              BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.terrain,
                            color: Colors.white54, size: 20),
                      ),
                      title: Text(it['titulo'] ?? '',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          )),
                      subtitle: Text(it['resumen'] ?? '',
                          style: TextStyle(
                            color:
                                Color(0x4DFFFFFF),
                            fontSize: 11,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                      trailing: cat.isNotEmpty
                          ? Container(
                              padding:
                                  const EdgeInsets.symmetric(
                                      horizontal: 5,
                                      vertical: 1),
                              decoration: BoxDecoration(
                                color: _kCardBg,
                                borderRadius:
                                    BorderRadius.circular(3),
                              ),
                              child: Text(cat.toUpperCase(),
                                  style: const TextStyle(
                                    color: Colors.white54,
                                    fontSize: 8,
                                    fontWeight: FontWeight.w600,
                                  )),
                            )
                          : null,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => _DetailPage(
                            title: it['titulo'] ?? '',
                            item: it,
                            bookmarkType: 'guide',
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
                ),
              ],
            ),
    );
  }
}

// ─────────────────────────────────────────────
// DICCIONARIO
// ─────────────────────────────────────────────
class DictionaryPage extends StatefulWidget {
  const DictionaryPage({super.key});

  @override
  State<DictionaryPage> createState() => _DictionaryPageState();
}

class _DictionaryPageState extends State<DictionaryPage> {
  List<dynamic> _all = [];
  List<dynamic> _filtered = [];
  bool _loading = true;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await rootBundle.loadString(
          'assets/vault/dictionary/diccionario_index.json');
      final d = json.decode(s);
      setState(() {
        _all = d['terminos'] ?? [];
        _filtered = _all;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _filter(String q) {
    setState(() {
      _filtered = q.isEmpty
          ? _all
          : _all.where((t) {
              final m = t as Map<String, dynamic>;
              return (m['palabra'] ?? '')
                      .toString()
                      .toLowerCase()
                      .contains(q.toLowerCase()) ||
                  (m['definicion'] ?? '')
                      .toString()
                      .toLowerCase()
                      .contains(q.toLowerCase());
            }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111111),
        title: const Text('Diccionario',
            style: TextStyle(color: Colors.white)),
        iconTheme:
            const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchCtrl,
              style: const TextStyle(color: Colors.white),
              onChanged: _filter,
              decoration: InputDecoration(
                hintText: 'Buscar termino...',
                hintStyle: const TextStyle(color: Color(0xFF3A3A3A)),
                prefixIcon: const Icon(Icons.search,
                    color: Colors.white38),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(
                        color: Colors.white))
                : _filtered.isEmpty
                    ? Center(
                        child: Text('Sin resultados',
                            style: TextStyle(
                                color: Colors.white24)))
                    : ListView.builder(
                        itemCount: _filtered.length,
                        itemBuilder: (_, i) {
                          final it = _filtered[i]
                              as Map<String, dynamic>;
                          return Container(
                            margin: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 3),
                            child: Material(
                              color:
                                  _kCardBgDim,
                              borderRadius:
                                  BorderRadius.circular(10),
                              child: ListTile(
                                dense: true,
                                contentPadding:
                                    const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 4),
                                title: Text(it['palabra'] ?? '',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    )),
                                subtitle: Text(
                                    it['definicion'] ?? '',
                                    style: TextStyle(
                                      color: Color(0x66FFFFFF),
                                      fontSize: 11,
                                    ),
                                    maxLines: 2,
                                    overflow:
                                        TextOverflow.ellipsis),
                                trailing: Container(
                                  padding: const EdgeInsets
                                      .symmetric(
                                      horizontal: 5,
                                      vertical: 1),
                                  decoration: BoxDecoration(
                                    color: _kCardBgLight,
                                    borderRadius:
                                        BorderRadius.circular(3),
                                  ),
                                  child: Text(
                                    (it['categoria'] ?? '')
                                        .toString()
                                        .toUpperCase(),
                                    style: const TextStyle(
                                      color: Colors.white38,
                                      fontSize: 8,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        _DictDetail(item: it),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _DictDetail extends StatefulWidget {
  final Map<String, dynamic> item;
  const _DictDetail({required this.item});

  @override
  State<_DictDetail> createState() => _DictDetailState();
}

class _DictDetailState extends State<_DictDetail> {
  bool _isBookmarked = false;

  @override
  void initState() {
    super.initState();
    _checkBookmark();
  }

  String get _bookmarkId => '${widget.item['palabra'] ?? ''}||dict';

  Future<void> _checkBookmark() async {
    final b = await VaultBookmarks.isBookmarked(_bookmarkId);
    if (mounted) setState(() => _isBookmarked = b);
  }

  Future<void> _toggleBookmark() async {
    if (_isBookmarked) {
      await VaultBookmarks.remove(_bookmarkId);
    } else {
      await VaultBookmarks.add(_bookmarkId);
    }
    if (mounted) setState(() => _isBookmarked = !_isBookmarked);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111111),
        title: Text(widget.item['palabra'] ?? '',
            style: const TextStyle(color: Colors.white)),
        iconTheme:
            const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            onPressed: _toggleBookmark,
            icon: Icon(
              _isBookmarked ? Icons.bookmark : Icons.bookmark_border,
              color: _isBookmarked ? Colors.white : Colors.white38,
            ),
            tooltip: _isBookmarked ? 'Quitar de favoritos' : 'Agregar a favoritos',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.item['palabra'] ?? '',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                )),
            const SizedBox(height: 12),
            Text(widget.item['definicion'] ?? '',
                style: TextStyle(
                  color: Color(0xB3FFFFFF),
                  fontSize: 14,
                  height: 1.6,
                )),
            if ((widget.item['sinonimos'] as List?)?.isNotEmpty ??
                false) ...[
              const SizedBox(height: 16),
              const Text('Sinonimos:',
                  style: TextStyle(
                    color: Colors.white54,
                    fontWeight: FontWeight.w600,
                  )),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                children: (widget.item['sinonimos'] as List)
                    .map((s) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _kCardBgLight,
                            borderRadius:
                                BorderRadius.circular(6),
                          ),
                          child: Text(s.toString(),
                              style: TextStyle(
                                color:
                                    Color(0x99FFFFFF),
                                fontSize: 12,
                              )),
                        ))
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// WIKIPEDIA OFFLINE
// ─────────────────────────────────────────────
class WikipediaPage extends StatefulWidget {
  const WikipediaPage({super.key});

  @override
  State<WikipediaPage> createState() => _WikipediaPageState();
}

class _WikipediaPageState extends State<WikipediaPage> {
  Map<String, dynamic> _data = {};
  List<dynamic> _articles = [];
  List<dynamic> _filteredArticles = [];
  bool _loading = true;
  String? _selectedCat;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await rootBundle.loadString(
          'assets/vault/wikipedia/wikipedia_offline.json');
      final d = json.decode(s);
      setState(() {
        _data = d;
        _loading = false;
        _selectCat(null);
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _selectCat(String? cat) {
    _selectedCat = cat;
    if (cat == null) {
      _articles = [];
      for (final c
          in (_data['categorias'] as Map<String, dynamic>)
              .values) {
        final arts =
            (c as Map<String, dynamic>)['articulos'] as List? ??
                [];
        _articles.addAll(arts);
      }
    } else {
      final c =
          (_data['categorias'] as Map<String, dynamic>)[cat]
              as Map<String, dynamic>?;
      _articles = c?['articulos'] as List? ?? [];
    }
    _applySearchFilter();
    setState(() {});
  }

  void _applySearchFilter() {
    final q = _searchCtrl.text.toLowerCase().trim();
    if (q.isEmpty) {
      _filteredArticles = _articles;
    } else {
      _filteredArticles = _articles.where((a) {
        final m = a as Map<String, dynamic>;
        return (m['titulo'] ?? '').toString().toLowerCase().contains(q) ||
            (m['resumen'] ?? '').toString().toLowerCase().contains(q);
      }).toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cats =
        (_data['categorias'] as Map<String, dynamic>?)
            ?.keys
            .toList() ??
            [];
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111111),
        title: const Text('Wikipedia Offline',
            style: TextStyle(color: Colors.white)),
        iconTheme:
            const IconThemeData(color: Colors.white),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.white))
          : Column(
              children: [
                // Search bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  child: TextField(
                    controller: _searchCtrl,
                    style: const TextStyle(color: Colors.white),
                    onChanged: (_) => _applySearchFilter(),
                    decoration: InputDecoration(
                      hintText: 'Buscar articulo...',
                      hintStyle: const TextStyle(color: Color(0xFF3A3A3A)),
                      prefixIcon: const Icon(Icons.search, color: Colors.white38),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  height: 44,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    children: [
                      Padding(
                        padding:
                            const EdgeInsets.only(right: 6),
                        child: FilterChip(
                          label: const Text('Todo'),
                          selected: _selectedCat == null,
                          onSelected: (_) => _selectCat(null),
                          backgroundColor: _kCardBgLight,
                          selectedColor: _kChipBgActive,
                          labelStyle: TextStyle(
                            color: _selectedCat == null
                                ? Colors.white
                                : Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      ...cats.map((c) => Padding(
                            padding:
                                const EdgeInsets.only(right: 6),
                            child: FilterChip(
                              label: Text(c[0].toUpperCase() +
                                  c.substring(1)),
                              selected: _selectedCat == c,
                              onSelected: (_) => _selectCat(c),
                              backgroundColor: _kCardBgLight,
                              selectedColor: _kChipBgActive,
                              labelStyle: TextStyle(
                                color: _selectedCat == c
                                    ? Colors.white
                                    : Colors.white54,
                                fontSize: 12,
                              ),
                            ),
                          )),
                    ],
                  ),
                ),
                Expanded(
                  child: _filteredArticles.isEmpty
                      ? Center(
                          child: Text('Sin articulos',
                              style:
                                  TextStyle(color: Colors.white24)))
                      : ListView.builder(
                          itemCount: _filteredArticles.length,
                          itemBuilder: (_, i) {
                            final it = _filteredArticles[i]
                                as Map<String, dynamic>;
                            return Container(
                              margin:
                                  const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 3),
                              child: Material(
                                color: Color(0x0AFFFFFF),
                                borderRadius:
                                    BorderRadius.circular(10),
                                child: ListTile(
                                  dense: true,
                                  contentPadding:
                                      const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 4),
                                  title: Text(
                                      it['titulo'] ?? '',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                      )),
                                  subtitle: Text(
                                      it['resumen'] ?? '',
                                      style: TextStyle(
                                        color: Color(0x59FFFFFF),
                                        fontSize: 11,
                                      ),
                                      maxLines: 2,
                                      overflow:
                                          TextOverflow.ellipsis),
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          _WikiDetail(item: it),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

class _WikiDetail extends StatefulWidget {
  final Map<String, dynamic> item;
  const _WikiDetail({required this.item});

  @override
  State<_WikiDetail> createState() => _WikiDetailState();
}

class _WikiDetailState extends State<_WikiDetail> {
  bool _isBookmarked = false;

  @override
  void initState() {
    super.initState();
    _checkBookmark();
  }

  String get _bookmarkId => '${widget.item['titulo'] ?? ''}||wiki';

  Future<void> _checkBookmark() async {
    final b = await VaultBookmarks.isBookmarked(_bookmarkId);
    if (mounted) setState(() => _isBookmarked = b);
  }

  Future<void> _toggleBookmark() async {
    if (_isBookmarked) {
      await VaultBookmarks.remove(_bookmarkId);
    } else {
      await VaultBookmarks.add(_bookmarkId);
    }
    if (mounted) setState(() => _isBookmarked = !_isBookmarked);
  }

  @override
  Widget build(BuildContext context) {
    final sections = widget.item['secciones'] as List? ?? [];
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111111),
        title: Text(widget.item['titulo'] ?? '',
            style: const TextStyle(
                color: Colors.white, fontSize: 16)),
        iconTheme:
            const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            onPressed: _toggleBookmark,
            icon: Icon(
              _isBookmarked ? Icons.bookmark : Icons.bookmark_border,
              color: _isBookmarked ? Colors.white : Colors.white38,
            ),
            tooltip: _isBookmarked ? 'Quitar de favoritos' : 'Agregar a favoritos',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.item['resumen'] ?? '',
                style: TextStyle(
                  color: Color(0xB3FFFFFF),
                  fontSize: 14,
                  height: 1.6,
                )),
            ...sections.map((s) {
              final sec = s as Map<String, dynamic>;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  Text(sec['titulo'] ?? '',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      )),
                  const SizedBox(height: 6),
                  Text(sec['contenido'] ?? '',
                      style: TextStyle(
                        color: Color(0xA6FFFFFF),
                        fontSize: 13,
                        height: 1.5,
                      )),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// MAPA DE EMERGENCIAS
// ─────────────────────────────────────────────
class EmergencyMapPage extends StatefulWidget {
  const EmergencyMapPage({super.key});

  @override
  State<EmergencyMapPage> createState() => _EmergencyMapPageState();
}

class _EmergencyMapPageState extends State<EmergencyMapPage> {
  List<dynamic> _features = [];
  bool _loading = true;
  String _filter = 'all';
  bool _showMap = true;
  int? _selectedIdx;
  MapController? _mapController;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await rootBundle.loadString(
          'assets/vault/maps/colombia_emergencias.geojson');
      final d = json.decode(s);
      setState(() {
        _features = d['features'] ?? [];
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  IconData _typeIcon(String? t) {
    switch (t) {
      case 'capital_nacional':
        return Icons.location_city;
      case 'capital_departamento':
        return Icons.location_city;
      case 'ciudad_principal':
        return Icons.location_on;
      case 'hospital_referencia':
        return Icons.local_hospital;
      default:
        return Icons.place;
    }
  }

  Color _typeColor(String? t) {
    switch (t) {
      case 'capital_nacional':
        return Colors.white;
      case 'capital_departamento':
        return Colors.grey;
      case 'hospital_referencia':
        return Colors.redAccent;
      default:
        return Colors.white54;
    }
  }

  List<dynamic> get _filtered => _filter == 'all'
      ? _features
      : _features.where((f) {
          final p = (f as Map<String, dynamic>)['properties']
              as Map<String, dynamic>?;
          final t = p?['tipo'] ?? '';
          if (_filter == 'capitales') {
            return t == 'capital_nacional' ||
                t == 'capital_departamento';
          }
          if (_filter == 'hospitales') {
            return t == 'hospital_referencia' || (p?['hospital'] == true);
          }
          if (_filter == 'ciudades') {
            return t == 'municipio' || t == 'ciudad_principal';
          }
          return true;
        }).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111111),
        title: const Text('Mapa Colombia',
            style: TextStyle(color: Colors.white)),
        iconTheme:
            const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            onPressed: () => setState(() => _showMap = !_showMap),
            icon: Icon(_showMap ? Icons.list : Icons.map, color: Colors.white),
            tooltip: _showMap ? 'Vista lista' : 'Vista mapa',
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.white))
          : Column(
              children: [
                SizedBox(
                  height: 44,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    children: [
                      _mapFilter('Todo', 'all'),
                      _mapFilter('Capitales', 'capitales'),
                      _mapFilter('Hospitales', 'hospitales'),
                      _mapFilter('Ciudades', 'ciudades'),
                    ],
                  ),
                ),
                Expanded(
                  child: _showMap ? _buildMapView() : _buildListView(),
                ),
              ],
            ),
    );
  }

  Widget _buildMapView() {
    final filtered = _filtered;
    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: LatLng(4.5, -74.0),
            initialZoom: 5.0,
            minZoom: 3.0,
            maxZoom: 18.0,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all,
            ),
            onTap: (tapPosition, point) {
              // Find closest feature
              int? closest;
              double minDist = 0.05; // ~5km
              for (int i = 0; i < filtered.length; i++) {
                final f = filtered[i] as Map<String, dynamic>;
                final geom = f['geometry'] as Map<String, dynamic>?;
                final coords = geom?['coordinates'] as List?;
                if (coords == null || coords.length < 2) continue;
                final lng = (coords[0] as num).toDouble();
                final lat = (coords[1] as num).toDouble();
                final dist = _haversine(point.latitude, point.longitude, lat, lng);
                if (dist < minDist) {
                  minDist = dist;
                  closest = i;
                }
              }
              setState(() => _selectedIdx = closest);
            },
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.lessnet.app',
              maxNativeZoom: 19,
            ),
            MarkerLayer(
              markers: filtered.asMap().entries.map((entry) {
                final i = entry.key;
                final f = entry.value as Map<String, dynamic>;
                final geom = f['geometry'] as Map<String, dynamic>?;
                final coords = geom?['coordinates'] as List?;
                if (coords == null || coords.length < 2) return null;
                final lng = (coords[0] as num).toDouble();
                final lat = (coords[1] as num).toDouble();
                final p = f['properties'] as Map<String, dynamic>? ?? {};
                final t = p['tipo'] ?? '';
                final isSelected = _selectedIdx == i;
                return Marker(
                  point: LatLng(lat, lng),
                  width: isSelected ? 40 : 28,
                  height: isSelected ? 40 : 28,
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedIdx = i),
                    child: Container(
                      decoration: BoxDecoration(
                        color: _typeColor(t).withOpacity(0.9),
                        shape: BoxShape.circle,
                        border: isSelected
                            ? Border.all(color: Colors.white, width: 3)
                            : null,
                        boxShadow: isSelected
                            ? [BoxShadow(color: _typeColor(t), blurRadius: 8)]
                            : null,
                      ),
                      child: Icon(_typeIcon(t), color: Colors.black, size: isSelected ? 20 : 14),
                    ),
                  ),
                );
              }).whereType<Marker>().toList(),
            ),
          ],
        ),
        // Selected point info
        if (_selectedIdx != null && _selectedIdx! < filtered.length)
          Positioned(
            left: 12,
            bottom: 12,
            right: 12,
            child: _MapPointCard(
              feature: filtered[_selectedIdx!] as Map<String, dynamic>,
              onTap: () {
                final f = filtered[_selectedIdx!] as Map<String, dynamic>;
                final p = f['properties'] as Map<String, dynamic>? ?? {};
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => _MapDetailPage(props: p),
                  ),
                );
              },
            ),
          ),
        // Legend
        Positioned(
          right: 8,
          top: 8,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Color(0xDD000000),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _legendDot(Colors.white, 'Capital'),
                const SizedBox(height: 4),
                _legendDot(Colors.grey, 'Cap. Depto'),
                const SizedBox(height: 4),
                _legendDot(Colors.redAccent, 'Hospital'),
                const SizedBox(height: 4),
                _legendDot(Colors.greenAccent, 'Ciudad'),
              ],
            ),
          ),
        ),
      ],
    );
  }

  double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371;
    final dLat = _toRad(lat2 - lat1);
    final dLon = _toRad(lon2 - lon1);
    final a = (dLat / 2) * (dLat / 2) +
        _toRad(lat1) * _toRad(lat2) * (dLon / 2) * (dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  double _toRad(double deg) => deg * pi / 180;

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10)),
      ],
    );
  }

  Widget _buildListView() {
    final filtered = _filtered;
    return filtered.isEmpty
        ? Center(
            child: Text('Sin resultados',
                style: TextStyle(color: Colors.white24)))
        : ListView.builder(
            itemCount: filtered.length,
            itemBuilder: (_, i) {
              final f = filtered[i] as Map<String, dynamic>;
              final p = f['properties'] as Map<String, dynamic>? ?? {};
              final t = p['tipo'] ?? '';
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                child: Material(
                  color: Color(0x0AFFFFFF),
                  borderRadius: BorderRadius.circular(10),
                  child: ListTile(
                    dense: true,
                    leading: Icon(_typeIcon(t), color: _typeColor(t), size: 20),
                    title: Text(p['nombre'] ?? '',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        )),
                    subtitle: Text(
                      '${p['departamento'] ?? ''} - ${p['descripcion'] ?? ''}',
                      style: TextStyle(
                        color: Color(0x4DFFFFFF),
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: p['emergencia'] != null
                        ? Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: Color(0x1FF44336),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              '${p['emergencia']}',
                              style: const TextStyle(
                                color: Colors.redAccent,
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          )
                        : null,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => _MapDetailPage(props: p),
                      ),
                    ),
                  ),
                ),
              );
            },
          );
  }

  Widget _mapFilter(String label, String val) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        label: Text(label),
        selected: _filter == val,
        onSelected: (_) => setState(() { _filter = val; _selectedIdx = null; }),
        backgroundColor: _kCardBgLight,
        selectedColor: _kChipBgActive,
        labelStyle: TextStyle(
          color: _filter == val ? Colors.white : Colors.white54,
          fontSize: 12,
        ),
      ),
    );
  }
}

// ─── Custom painter for Colombia map ───
// ColombiaMapPainter removed — replaced by flutter_map + OpenStreetMap

// ─── Map point info card ───
class _MapPointCard extends StatelessWidget {
  final Map<String, dynamic> feature;
  final VoidCallback onTap;

  const _MapPointCard({required this.feature, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = feature['properties'] as Map<String, dynamic>? ?? {};
    final t = p['tipo'] ?? '';
    final isHospital = t == 'hospital_referencia' || p['hospital'] == true;

    return Material(
      color: const Color(0xDD111111),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isHospital
                      ? const Color(0x1FF44336)
                      : const Color(0x1AFFFFFF),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  isHospital ? Icons.local_hospital : Icons.location_city,
                  color: isHospital ? Colors.redAccent : Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(p['nombre'] ?? '',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        )),
                    const SizedBox(height: 2),
                    Text(
                      '${p['departamento'] ?? ''}${p['descripcion'] != null ? ' - ${p['descripcion']}' : ''}',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (p['emergencia'] != null)
                      Text(
                        'Emergencia: ${p['emergencia']}',
                        style: const TextStyle(
                          color: Colors.redAccent,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white24),
            ],
          ),
        ),
      ),
    );
  }
}

class _MapDetailPage extends StatelessWidget {
  final Map<String, dynamic> props;
  const _MapDetailPage({required this.props});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111111),
        title: Text(props['nombre'] ?? '',
            style: const TextStyle(color: Colors.white)),
        iconTheme:
            const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(props['nombre'] ?? '',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                )),
            const SizedBox(height: 8),
            if (props['departamento'] != null)
              Text(props['departamento'],
                  style: TextStyle(
                    color: Color(0x80FFFFFF),
                    fontSize: 14,
                  )),
            const SizedBox(height: 12),
            Text(props['descripcion'] ?? '',
                style: TextStyle(
                  color: Color(0xB3FFFFFF),
                  fontSize: 14,
                  height: 1.6,
                )),
            const SizedBox(height: 16),
            _infoRow(
                Icons.location_on, 'Tipo', props['tipo'] ?? ''),
            if (props['poblacion'] != null)
              _infoRow(Icons.people, 'Poblacion',
                  '${props['poblacion']}'),
            if (props['altitud'] != null)
              _infoRow(
                  Icons.terrain, 'Altitud', '${props['altitud']}m'),
            if (props['aeropuerto'] == true)
              _infoRow(Icons.flight, 'Aeropuerto', 'Si'),
            if (props['hospital'] == true)
              _infoRow(Icons.local_hospital, 'Hospital', 'Si'),
            if (props['emergencia'] != null)
              _infoRow(Icons.phone, 'Emergencias',
                  '${props['emergencia']}'),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, color: Colors.white38, size: 18),
          const SizedBox(width: 10),
          Text(label,
              style: TextStyle(
                color: Color(0x66FFFFFF),
                fontSize: 13,
              )),
          const SizedBox(width: 8),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                )),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// TRADUCTOR OFFLINE
// ─────────────────────────────────────────────
class TranslatorPage extends StatefulWidget {
  const TranslatorPage({super.key});

  @override
  State<TranslatorPage> createState() => _TranslatorPageState();
}

class _TranslatorPageState extends State<TranslatorPage> {
  String _srcLang = 'es';
  String _tgtLang = 'en';
  final _inputCtrl = TextEditingController();
  String _output = '';
  bool _translating = false;

  // Model management
  Map<String, String> _modelStatus = {}; // code -> 'downloaded' | 'not_downloaded' | 'downloading' | 'needs_update'
  Map<String, double> _downloadProgress = {}; // code -> 0.0-1.0

  static const List<Map<String, String>> _supportedLangs = [
    {'code': 'es', 'name': 'Espanol', 'flag': '🇪🇸'},
    {'code': 'en', 'name': 'Ingles', 'flag': '🇬🇧'},
    {'code': 'pt', 'name': 'Portugues', 'flag': '🇧🇷'},
    {'code': 'fr', 'name': 'Frances', 'flag': '🇫🇷'},
    {'code': 'de', 'name': 'Aleman', 'flag': '🇩🇪'},
    {'code': 'it', 'name': 'Italiano', 'flag': '🇮🇹'},
    {'code': 'ru', 'name': 'Ruso', 'flag': '🇷🇺'},
    {'code': 'zh', 'name': 'Chino', 'flag': '🇨🇳'},
    {'code': 'ja', 'name': 'Japones', 'flag': '🇯🇵'},
    {'code': 'ko', 'name': 'Coreano', 'flag': '🇰🇷'},
    {'code': 'ar', 'name': 'Arabe', 'flag': '🇸🇦'},
    {'code': 'hi', 'name': 'Hindi', 'flag': '🇮🇳'},
    {'code': 'tr', 'name': 'Turco', 'flag': '🇹🇷'},
    {'code': 'nl', 'name': 'Holandes', 'flag': '🇳🇱'},
    {'code': 'pl', 'name': 'Polaco', 'flag': '🇵🇱'},
    {'code': 'th', 'name': 'Tailandes', 'flag': '🇹🇭'},
    {'code': 'vi', 'name': 'Vietnamita', 'flag': '🇻🇳'},
    {'code': 'id', 'name': 'Indonesio', 'flag': '🇮🇩'},
  ];

  TranslateLanguage _codeToLang(String code) {
    const map = {
      'es': TranslateLanguage.spanish,
      'en': TranslateLanguage.english,
      'pt': TranslateLanguage.portuguese,
      'fr': TranslateLanguage.french,
      'de': TranslateLanguage.german,
      'it': TranslateLanguage.italian,
      'ru': TranslateLanguage.russian,
      'zh': TranslateLanguage.chinese,
      'ja': TranslateLanguage.japanese,
      'ko': TranslateLanguage.korean,
      'ar': TranslateLanguage.arabic,
      'hi': TranslateLanguage.hindi,
      'tr': TranslateLanguage.turkish,
      'nl': TranslateLanguage.dutch,
      'pl': TranslateLanguage.polish,
      'th': TranslateLanguage.thai,
      'vi': TranslateLanguage.vietnamese,
      'id': TranslateLanguage.indonesian,
    };
    return map[code] ?? TranslateLanguage.english;
  }

  String _langName(String code) {
    final lang = _supportedLangs.firstWhere(
      (l) => l['code'] == code,
      orElse: () => {'name': code.toUpperCase()},
    );
    return '${lang['flag']} ${lang['name']}';
  }

  String _langNameShort(String code) {
    final lang = _supportedLangs.firstWhere(
      (l) => l['code'] == code,
      orElse: () => {'name': code.toUpperCase()},
    );
    return lang['name'] ?? code.toUpperCase();
  }

  @override
  void initState() {
    super.initState();
    // Delay model check to avoid blocking startup
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkModels();
    });
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkModels() async {
    final Map<String, String> statuses = {};
    final manager = OnDeviceTranslatorModelManager();
    for (final lang in _supportedLangs) {
      final code = lang['code']!;
      try {
        final bcpCode = _codeToLang(code).bcpCode;
        final isDownloaded = await manager.isModelDownloaded(bcpCode);
        statuses[code] = isDownloaded ? 'downloaded' : 'not_downloaded';
      } catch (e) {
        statuses[code] = 'not_downloaded';
      }
    }
    if (mounted) {
      setState(() => _modelStatus = statuses);
    }
  }

  Future<void> _downloadModel(String code) async {
    setState(() {
      _modelStatus[code] = 'downloading';
      _downloadProgress[code] = 0.0;
    });

    try {
      final bcpCode = _codeToLang(code).bcpCode;
      final manager = OnDeviceTranslatorModelManager();
      await manager.downloadModel(bcpCode, isWifiRequired: false);
      if (mounted) {
        setState(() {
          _modelStatus[code] = 'downloaded';
          _downloadProgress.remove(code);
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Modelo de ${_langNameShort(code)} descargado!'),
          backgroundColor: Colors.grey[800],
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _modelStatus[code] = 'not_downloaded';
          _downloadProgress.remove(code);
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error al descargar: ${e.toString()}'),
          backgroundColor: Colors.red[900],
        ));
      }
    }
  }

  Future<void> _deleteModel(String code) async {
    try {
      final bcpCode = _codeToLang(code).bcpCode;
      final manager = OnDeviceTranslatorModelManager();
      await manager.deleteModel(bcpCode);
      if (mounted) {
        setState(() => _modelStatus[code] = 'not_downloaded');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Modelo de ${_langNameShort(code)} eliminado'),
          backgroundColor: Colors.grey[800],
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error al eliminar: ${e.toString()}'),
          backgroundColor: Colors.red[900],
        ));
      }
    }
  }

  Future<void> _translate() async {
    final input = _inputCtrl.text.trim();
    if (input.isEmpty) {
      setState(() => _output = '');
      return;
    }

    // Check if both models are downloaded
    final srcStatus = _modelStatus[_srcLang];
    final tgtStatus = _modelStatus[_tgtLang];

    if (srcStatus != 'downloaded' || tgtStatus != 'downloaded') {
      final missing = <String>[];
      if (srcStatus != 'downloaded') missing.add(_langNameShort(_srcLang));
      if (tgtStatus != 'downloaded') missing.add(_langNameShort(_tgtLang));
      setState(() {
        _output = 'Faltan modelos: ${missing.join(', ')}.\n'
            'Ve a "Gestionar Modelos" para descargarlos primero.';
      });
      return;
    }

    setState(() => _translating = true);

    try {
      final translator = OnDeviceTranslator(
        sourceLanguage: _codeToLang(_srcLang),
        targetLanguage: _codeToLang(_tgtLang),
      );
      final result = await translator.translateText(input);
      translator.close();
      if (mounted) {
        setState(() {
          _output = result;
          _translating = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _output = 'Error de traduccion: ${e.toString()}\n\n'
              'Asegurate de que los modelos esten descargados.';
          _translating = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111111),
        title: const Text('Traductor Offline',
            style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => _ModelManagerPage(
                          modelStatus: _modelStatus,
                          onDownload: _downloadModel,
                          onDelete: _deleteModel,
                          onRefresh: _checkModels,
                          langName: _langName,
                          langNameShort: _langNameShort,
                          downloadProgress: _downloadProgress,
                        )),
              ).then((_) => _checkModels());
            },
            icon: const Icon(Icons.download_for_offline, color: Colors.white),
            tooltip: 'Gestionar Modelos',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Info
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _kCardBgDim,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline,
                      color: Colors.white24, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Traductor offline con IA. Descarga los modelos de idioma primero tocando el icono de descarga arriba.',
                      style: TextStyle(
                        color: Color(0x66FFFFFF),
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Model status warning
            if (_modelStatus[_srcLang] != 'downloaded' ||
                _modelStatus[_tgtLang] != 'downloaded')
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Color(0x1AFF9800),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Color(0x4DFF9800)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber, color: Colors.orange, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Faltan modelos de idioma. Toca el icono de descarga arriba para descargarlos.',
                        style: TextStyle(
                          color: Color(0xCCFF9800),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            // Language selectors
            Row(
              children: [
                Expanded(
                  child: _langDropdown('De:', _srcLang,
                      (v) => setState(() => _srcLang = v!)),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: IconButton(
                    onPressed: () {
                      setState(() {
                        final tmp = _srcLang;
                        _srcLang = _tgtLang;
                        _tgtLang = tmp;
                      });
                    },
                    icon: const Icon(Icons.swap_horiz, color: Colors.white54),
                  ),
                ),
                Expanded(
                  child: _langDropdown('A:', _tgtLang,
                      (v) => setState(() => _tgtLang = v!)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Input
            TextField(
              controller: _inputCtrl,
              style: const TextStyle(color: Colors.white),
              maxLines: 4,
              decoration: InputDecoration(
                hintText: 'Escribe texto para traducir...',
                hintStyle: const TextStyle(color: Color(0xFF3A3A3A)),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: _translating
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          color: Colors.black,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.translate),
                label: Text(_translating ? 'Traduciendo...' : 'Traducir'),
                onPressed: _translating ? null : _translate,
              ),
            ),
            const SizedBox(height: 16),
            // Output
            if (_output.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _kCardBgLight,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _kBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Traduccion:',
                        style: TextStyle(
                          color: Color(0x66FFFFFF),
                          fontSize: 11,
                        )),
                    const SizedBox(height: 6),
                    Text(_output,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          height: 1.4,
                        )),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton.icon(
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: _output));
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                              content: Text('Copiado!'),
                              backgroundColor: Colors.grey,
                            ));
                          },
                          icon: const Icon(Icons.copy, size: 14),
                          label: const Text('Copiar',
                              style: TextStyle(fontSize: 11)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _langDropdown(
      String label, String value, ValueChanged<String?> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
              color: Color(0x66FFFFFF),
              fontSize: 11,
            )),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: _kCardBgDim,
            borderRadius: BorderRadius.circular(8),
            border: _modelStatus[value] == 'downloaded'
                ? Border.all(color: Colors.white12)
                : Border.all(color: Color(0x4DFF9800)),
          ),
          child: DropdownButton<String>(
            value: value,
            isExpanded: true,
            underline: const SizedBox(),
            dropdownColor: const Color(0xFF111111),
            style: const TextStyle(color: Colors.white, fontSize: 13),
            items: _supportedLangs
                .map((l) => DropdownMenuItem(
                      value: l['code'],
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(l['flag'] ?? '', style: const TextStyle(fontSize: 14)),
                          const SizedBox(width: 6),
                          Text(l['name'] ?? ''),
                          const SizedBox(width: 4),
                          if (_modelStatus[l['code']] == 'downloaded')
                            const Icon(Icons.cloud_done, size: 12, color: Colors.greenAccent),
                          if (_modelStatus[l['code']] == 'not_downloaded')
                            const Icon(Icons.cloud_off, size: 12, color: Colors.orangeAccent),
                        ],
                      ),
                    ))
                .toList(),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

// ─── MODEL MANAGER PAGE ───
class _ModelManagerPage extends StatelessWidget {
  final Map<String, String> modelStatus;
  final Future<void> Function(String) onDownload;
  final Future<void> Function(String) onDelete;
  final Future<void> Function() onRefresh;
  final String Function(String) langName;
  final String Function(String) langNameShort;
  final Map<String, double> downloadProgress;

  const _ModelManagerPage({
    required this.modelStatus,
    required this.onDownload,
    required this.onDelete,
    required this.onRefresh,
    required this.langName,
    required this.langNameShort,
    required this.downloadProgress,
  });

  @override
  Widget build(BuildContext context) {
    final downloaded = modelStatus.entries
        .where((e) => e.value == 'downloaded')
        .length;
    final total = modelStatus.length;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111111),
        title: const Text('Modelos de Traduccion',
            style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh, color: Colors.white),
            tooltip: 'Actualizar',
          ),
        ],
      ),
      body: Column(
        children: [
          // Summary
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _kCardBgDim,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.storage, color: Colors.white54),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Modelos descargados',
                          style: TextStyle(color: Colors.white, fontSize: 14)),
                      Text('$downloaded de $total idiomas disponibles',
                          style: TextStyle(
                            color: Color(0x66FFFFFF),
                            fontSize: 12,
                          )),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: downloaded > 0 ? Color(0x334CAF50) : Color(0x33FF9800),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$downloaded/$total',
                    style: TextStyle(
                      color: downloaded > 0 ? Colors.greenAccent : Colors.orangeAccent,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // List of models
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: modelStatus.length,
              itemBuilder: (context, index) {
                final code = modelStatus.keys.elementAt(index);
                final status = modelStatus[code] ?? 'not_downloaded';
                final progress = downloadProgress[code];
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _kCardBgDim,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: status == 'downloaded'
                          ? _kBorderDim
                          : status == 'downloading'
                              ? Color(0x4D2196F3)
                              : _kCardBgDim,
                    ),
                  ),
                  child: Row(
                    children: [
                      // Status icon
                      if (status == 'downloaded')
                        const Icon(Icons.cloud_done, color: Colors.greenAccent, size: 22)
                      else if (status == 'downloading')
                        SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            value: progress,
                            color: Colors.blueAccent,
                            strokeWidth: 2.5,
                          ),
                        )
                      else
                        const Icon(Icons.cloud_download_outlined, color: Colors.white24, size: 22),
                      const SizedBox(width: 12),
                      // Language name
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              langName(code),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                              ),
                            ),
                            if (status == 'downloaded')
                              Text(
                                'Listo para traducir',
                                style: TextStyle(
                                  color: Color(0x9969F0AE),
                                  fontSize: 11,
                                ),
                              )
                            else if (status == 'downloading')
                              Text(
                                'Descargando... ${(progress != null ? (progress * 100).toStringAsFixed(0) : '0')}%',
                                style: TextStyle(
                                  color: Color(0xCC448AFF),
                                  fontSize: 11,
                                ),
                              )
                            else
                              Text(
                                'Toca para descargar (~30 MB)',
                                style: TextStyle(
                                  color: Color(0x4DFFFFFF),
                                  fontSize: 11,
                                ),
                              ),
                          ],
                        ),
                      ),
                      // Action button
                      if (status == 'downloaded')
                        IconButton(
                          onPressed: () => onDelete(code),
                          icon: const Icon(Icons.delete_outline, color: Colors.white24, size: 20),
                          tooltip: 'Eliminar modelo',
                        )
                      else if (status == 'downloading')
                        const SizedBox(
                          width: 40,
                          height: 40,
                          child: Center(
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        )
                      else
                        FilledButton(
                          onPressed: () => onDownload(code),
                          style: FilledButton.styleFrom(
                            backgroundColor: Color(0x1AFFFFFF),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text('Descargar', style: TextStyle(fontSize: 12)),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// BUSQUEDA GLOBAL DEL VAULT
// ─────────────────────────────────────────────
class VaultSearchPage extends StatefulWidget {
  const VaultSearchPage({super.key});

  @override
  State<VaultSearchPage> createState() => _VaultSearchPageState();
}

class _VaultSearchPageState extends State<VaultSearchPage> {
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  bool _searched = false;
  bool _searching = false;

  Future<void> _search(String q) async {
    if (q.trim().isEmpty) {
      setState(() {
        _results = [];
        _searched = false;
      });
      return;
    }
    setState(() => _searching = true);
    final ql = q.toLowerCase();
    final List<Map<String, dynamic>> found = [];

    try {
      final s = await rootBundle.loadString(
          'assets/vault/first_aid/primeros_auxilios.json');
      final d = json.decode(s);
      for (final it in (d['protocolos'] ?? [])) {
        final m = it as Map<String, dynamic>;
        if ((m['titulo'] ?? '').toString().toLowerCase().contains(ql) ||
            (m['resumen'] ?? '').toString().toLowerCase().contains(ql)) {
          found.add({...m, '_type': 'first_aid'});
        }
      }
    } catch (_) {}

    try {
      final s = await rootBundle.loadString(
          'assets/vault/guides/supervivencia.json');
      final d = json.decode(s);
      for (final it in (d['guias'] ?? [])) {
        final m = it as Map<String, dynamic>;
        if ((m['titulo'] ?? '').toString().toLowerCase().contains(ql) ||
            (m['resumen'] ?? '').toString().toLowerCase().contains(ql)) {
          found.add({...m, '_type': 'guide'});
        }
      }
    } catch (_) {}

    try {
      final s = await rootBundle.loadString(
          'assets/vault/dictionary/diccionario_index.json');
      final d = json.decode(s);
      for (final it in (d['terminos'] ?? [])) {
        final m = it as Map<String, dynamic>;
        if ((m['palabra'] ?? '').toString().toLowerCase().contains(ql) ||
            (m['definicion'] ?? '').toString().toLowerCase().contains(ql)) {
          found.add({...m, '_type': 'dict'});
        }
      }
    } catch (_) {}

    try {
      final s = await rootBundle.loadString(
          'assets/vault/wikipedia/wikipedia_offline.json');
      final d = json.decode(s);
      for (final cat
          in (d['categorias'] as Map<String, dynamic>).values) {
        for (final it
            in (cat as Map<String, dynamic>)['articulos']
                    as List? ??
                []) {
          final m = it as Map<String, dynamic>;
          if ((m['titulo'] ?? '').toString().toLowerCase().contains(ql) ||
              (m['resumen'] ?? '').toString().toLowerCase().contains(ql)) {
            found.add({...m, '_type': 'wiki'});
          }
        }
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _results = found;
        _searched = true;
        _searching = false;
      });
    }
  }

  IconData _tIcon(String t) {
    if (t == 'first_aid') return Icons.local_hospital;
    if (t == 'guide') return Icons.terrain;
    if (t == 'dict') return Icons.book;
    return Icons.article;
  }

  String _tLabel(String t) {
    if (t == 'first_aid') return 'Auxilio';
    if (t == 'guide') return 'Guia';
    if (t == 'dict') return 'Diccionario';
    return 'Wiki';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111111),
        title: const Text('Busqueda Vault',
            style: TextStyle(color: Colors.white)),
        iconTheme:
            const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchCtrl,
              style: const TextStyle(color: Colors.white),
              onSubmitted: _search,
              decoration: InputDecoration(
                hintText: 'Buscar en todo el vault...',
                hintStyle: const TextStyle(color: Color(0xFF3A3A3A)),
                prefixIcon: _searching
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white38,
                        ),
                      )
                    : const Icon(Icons.search,
                        color: Colors.white38),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_forward,
                      color: Colors.white38),
                  onPressed: () => _search(_searchCtrl.text),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: !_searched
                ? Center(
                    child: Text('Escribe para buscar',
                        style: TextStyle(color: Colors.white24)))
                : _results.isEmpty
                    ? Center(
                        child: Text('Sin resultados',
                            style:
                                TextStyle(color: Colors.white24)))
                    : ListView.builder(
                        itemCount: _results.length,
                        itemBuilder: (_, i) {
                          final r = _results[i];
                          final type =
                              r['_type'] as String? ?? '';
                          final title = r['titulo'] ??
                              r['palabra'] ??
                              'Sin titulo';
                          final sub = r['resumen'] ??
                              r['definicion'] ??
                              '';
                          return Container(
                            margin: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 3),
                            child: Material(
                              color:
                                  _kCardBgDim,
                              borderRadius:
                                  BorderRadius.circular(10),
                              child: ListTile(
                                dense: true,
                                leading: Icon(_tIcon(type),
                                    color: Colors.white54,
                                    size: 18),
                                title: Text(title,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    )),
                                subtitle: Text(sub,
                                    style: TextStyle(
                                      color: Color(0x4DFFFFFF),
                                      fontSize: 11,
                                    ),
                                    maxLines: 1,
                                    overflow:
                                        TextOverflow.ellipsis),
                                trailing: Container(
                                  padding: const EdgeInsets
                                      .symmetric(
                                      horizontal: 5,
                                      vertical: 1),
                                  decoration: BoxDecoration(
                                    color: _kCardBgLight,
                                    borderRadius:
                                        BorderRadius.circular(3),
                                  ),
                                  child: Text(_tLabel(type),
                                      style: const TextStyle(
                                        color: Colors.white38,
                                        fontSize: 8,
                                        fontWeight: FontWeight.w600,
                                      )),
                                ),
                                onTap: () {
                                  if (type == 'first_aid' ||
                                      type == 'guide') {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            _DetailPage(
                                          title: title,
                                          item: r,
                                          bookmarkType: type == 'first_aid' ? 'first_aid' : 'guide',
                                        ),
                                      ),
                                    );
                                  } else if (type == 'dict') {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            _DictDetail(item: r),
                                      ),
                                    );
                                  } else if (type == 'wiki') {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            _WikiDetail(item: r),
                                      ),
                                    );
                                  }
                                },
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// DETAIL PAGE GENERIC (Primeros Auxilios + Guias)
// ─────────────────────────────────────────────
class _DetailPage extends StatefulWidget {
  final String title;
  final Map<String, dynamic> item;
  final String bookmarkType;
  const _DetailPage({required this.title, required this.item, this.bookmarkType = 'first_aid'});

  @override
  State<_DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<_DetailPage> {
  bool _isBookmarked = false;

  @override
  void initState() {
    super.initState();
    _checkBookmark();
  }

  String get _bookmarkId => '${widget.title}||${widget.bookmarkType}';

  Future<void> _checkBookmark() async {
    final b = await VaultBookmarks.isBookmarked(_bookmarkId);
    if (mounted) setState(() => _isBookmarked = b);
  }

  Future<void> _toggleBookmark() async {
    if (_isBookmarked) {
      await VaultBookmarks.remove(_bookmarkId);
    } else {
      await VaultBookmarks.add(_bookmarkId);
    }
    if (mounted) setState(() => _isBookmarked = !_isBookmarked);
  }

  @override
  Widget build(BuildContext context) {
    final steps = widget.item['pasos'] as List? ?? [];
    final warnings = widget.item['advertencias'] as List? ?? [];
    final references = widget.item['referencias'] as List? ?? [];
    final help = widget.item['cuando_buscar_ayuda'] ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111111),
        title: Text(widget.title,
            style: const TextStyle(
                color: Colors.white, fontSize: 16)),
        iconTheme:
            const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            onPressed: _toggleBookmark,
            icon: Icon(
              _isBookmarked ? Icons.bookmark : Icons.bookmark_border,
              color: _isBookmarked ? Colors.white : Colors.white38,
            ),
            tooltip: _isBookmarked ? 'Quitar de favoritos' : 'Agregar a favoritos',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.item['resumen'] != null) ...[
              Text(widget.item['resumen'],
                  style: TextStyle(
                    color: Color(0xB3FFFFFF),
                    fontSize: 14,
                    height: 1.6,
                  )),
              const SizedBox(height: 16),
            ],
            if (steps.isNotEmpty) ...[
              const Text('Pasos:',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  )),
              const SizedBox(height: 8),
              ...steps.asMap().entries.map((e) {
                    final step = e.value;
                    final stepNum = step is Map ? (step['numero'] ?? e.key + 1) : e.key + 1;
                    final stepTitle = step is Map ? (step['titulo'] ?? '') : '';
                    final stepDesc = step is Map ? (step['descripcion'] ?? step.toString()) : step.toString();
                    final stepWarning = step is Map ? (step['advertencia'] ?? '') : '';
                    return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 24,
                              height: 24,
                              margin: const EdgeInsets.only(right: 10),
                              decoration: BoxDecoration(
                                color: _kCardBg,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Center(
                                child: Text('$stepNum',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    )),
                              ),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (stepTitle.isNotEmpty)
                                    Text(stepTitle,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        )),
                                  const SizedBox(height: 2),
                                  Text(stepDesc,
                                      style: TextStyle(
                                        color: Color(0xB3FFFFFF),
                                        fontSize: 13,
                                      )),
                                  if (stepWarning.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: const Color(0x1AFF9800),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.warning, color: Colors.orange, size: 14),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(stepWarning,
                                                style: const TextStyle(color: Colors.orange, fontSize: 11)),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                  }),
            ],
            if (warnings.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text('Advertencias:',
                  style: TextStyle(
                    color: Colors.redAccent,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  )),
              const SizedBox(height: 8),
              ...warnings.map((w) => Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Color(0x0AF44336),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning,
                            color: Colors.redAccent, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(w.toString(),
                              style: TextStyle(
                                color:
                                    Color(0x99FFFFFF),
                                fontSize: 12,
                              )),
                        ),
                      ],
                    ),
                  )),
            ],
            if (help.toString().isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text('Cuando buscar ayuda:',
                  style: TextStyle(
                    color: Colors.orangeAccent,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  )),
              const SizedBox(height: 6),
              Text(help.toString(),
                  style: TextStyle(
                    color: Color(0x99FFFFFF),
                    fontSize: 13,
                    height: 1.5,
                  )),
            ],
            if (references.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text('Referencias:',
                  style: TextStyle(
                    color: Colors.white54,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  )),
              const SizedBox(height: 4),
              ...references.map((r) => Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text('- $r',
                        style: TextStyle(
                          color:
                              Color(0x59FFFFFF),
                          fontSize: 11,
                        )),
                  )),
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
  final Color? subtitleColor;
  const _Header(this.title, this.icon, this.subtitle, {this.subtitleColor});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _kCardBgLight,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: Colors.white, size: 24),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  )),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: TextStyle(
                    color: subtitleColor ?? const Color(0xFF595959),
                    fontSize: 12,
                  )),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// MORSE CODE — LINTERNA
// ─────────────────────────────────────────────
class MorseCodePage extends StatefulWidget {
  const MorseCodePage({super.key});

  @override
  State<MorseCodePage> createState() => _MorseCodePageState();
}

class _MorseCodePageState extends State<MorseCodePage> {
  static const _torchChannel = MethodChannel('com.lessnet.torch');
  final _controller = TextEditingController();
  String _morseOutput = '';
  bool _isTransmitting = false;
  bool _hasTorch = true;
  double _progress = 0.0;

  // Morse code map
  static const _morseMap = {
    'A': '.-', 'B': '-...', 'C': '-.-.', 'D': '-..', 'E': '.', 'F': '..-.',
    'G': '--.', 'H': '....', 'I': '..', 'J': '.---', 'K': '-.-', 'L': '.-..',
    'M': '--', 'N': '-.', 'O': '---', 'P': '.--.', 'Q': '--.-', 'R': '.-.',
    'S': '...', 'T': '-', 'U': '..-', 'V': '...-', 'W': '.--', 'X': '-..-',
    'Y': '-.--', 'Z': '--..', '0': '-----', '1': '.----', '2': '..---',
    '3': '...--', '4': '....-', '5': '.....', '6': '-....', '7': '--...',
    '8': '---..', '9': '----.', '.': '.-.-.-', ',': '--..--', '?': '..--..',
    '!': '-.-.--', '/': '-..-.', '(': '-.--.', ')': '-.--.-', '&': '.-...',
    ':': '---...', ';': '-.-.-.', '=': '-...-', '+': '.-.-.', '-': '-....-',
    '_': '..--.-', '"': '.-..-.', '\$': '...-..-', '@': '.--.-.', "'": '.----.',
  };

  @override
  void initState() {
    super.initState();
    _checkTorch();
  }

  Future<void> _checkTorch() async {
    try {
      final has = await _torchChannel.invokeMethod<bool>('hasTorch') ?? false;
      if (mounted) setState(() => _hasTorch = has);
    } catch (_) {
      if (mounted) setState(() => _hasTorch = false);
    }
  }

  String _textToMorse(String text) {
    return text.toUpperCase().split('').map((c) {
      if (c == ' ') return '/';
      return _morseMap[c] ?? '';
    }).where((m) => m.isNotEmpty).join(' ');
  }

  Future<void> _transmit() async {
    if (_isTransmitting || _controller.text.isEmpty) return;
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _isTransmitting = true;
      _progress = 0.0;
    });

    final morse = _textToMorse(text);
    setState(() => _morseOutput = morse);

    // Timing: dot = 200ms, dash = 600ms, symbol gap = 200ms, letter gap = 600ms, word gap = 1400ms
    const dotMs = 200;
    const dashMs = 600;
    const symbolGapMs = 200;
    const letterGapMs = 600;
    const wordGapMs = 1400;

    final symbols = morse.split('');
    final totalSymbols = symbols.length;
    int completed = 0;

    for (int i = 0; i < symbols.length; i++) {
      if (!mounted || !_isTransmitting) break;

      final s = symbols[i];
      if (s == '.') {
        try { await _torchChannel.invokeMethod('on'); } catch (_) {}
        await Future.delayed(const Duration(milliseconds: dotMs));
        try { await _torchChannel.invokeMethod('off'); } catch (_) {}
      } else if (s == '-') {
        try { await _torchChannel.invokeMethod('on'); } catch (_) {}
        await Future.delayed(const Duration(milliseconds: dashMs));
        try { await _torchChannel.invokeMethod('off'); } catch (_) {}
      } else if (s == ' ') {
        // Letter gap
        await Future.delayed(const Duration(milliseconds: letterGapMs));
      } else if (s == '/') {
        // Word gap
        await Future.delayed(const Duration(milliseconds: wordGapMs));
      }

      completed++;
      if (mounted) {
        setState(() => _progress = completed / totalSymbols);
      }

      // Symbol gap (after dot or dash)
      if (s == '.' || s == '-') {
        await Future.delayed(const Duration(milliseconds: symbolGapMs));
      }
    }

    // Ensure torch is off
    try { await _torchChannel.invokeMethod('off'); } catch (_) {}

    if (mounted) {
      setState(() {
        _isTransmitting = false;
        _progress = 1.0;
      });
    }
  }

  void _stop() {
    setState(() => _isTransmitting = false);
    try { _torchChannel.invokeMethod('off'); } catch (_) {}
  }

  @override
  void dispose() {
    _controller.dispose();
    try { _torchChannel.invokeMethod('off'); } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111111),
        title: const Text('Codigo Morse',
            style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Torch status
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _hasTorch ? const Color(0x1A4CAF50) : const Color(0x1AF44336),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(
                    _hasTorch ? Icons.flashlight_on : Icons.flashlight_off,
                    color: _hasTorch ? Colors.greenAccent : Colors.redAccent,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _hasTorch
                        ? 'Linterna disponible'
                        : 'Este dispositivo no tiene linterna',
                    style: TextStyle(
                      color: _hasTorch ? Colors.greenAccent : Colors.redAccent,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // Input
            Text('Escribe tu mensaje:',
                style: TextStyle(
                  color: Color(0xB3FFFFFF),
                  fontSize: 13,
                )),
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              style: const TextStyle(color: Colors.white, fontSize: 16),
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'Escribe algo para transmitir...',
                hintStyle: TextStyle(color: Color(0x4DFFFFFF)),
              ),
              onChanged: (_) {
                if (mounted) {
                  setState(() {
                    _morseOutput = _textToMorse(_controller.text);
                  });
                }
              },
            ),
            const SizedBox(height: 16),
            // Morse output
            if (_morseOutput.isNotEmpty) ...[
              Text('Codigo Morse:',
                  style: TextStyle(
                    color: Color(0xB3FFFFFF),
                    fontSize: 13,
                  )),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF151515),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Color(0xFF2A2A2A)),
                ),
                child: Text(
                  _morseOutput,
                  style: TextStyle(
                    color: Colors.amberAccent,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            // Progress
            if (_isTransmitting) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _progress,
                  backgroundColor: const Color(0xFF222222),
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.amberAccent),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Transmitiendo... ${(_progress * 100).toStringAsFixed(0)}%',
                style: const TextStyle(
                  color: Colors.amberAccent,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 16),
            ],
            // Buttons
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _isTransmitting || !_hasTorch ? null : _transmit,
                    icon: const Icon(Icons.flashlight_on, size: 18),
                    label: Text(_isTransmitting ? 'Transmitiendo...' : 'Transmitir'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.amberAccent,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                if (_isTransmitting) ...[
                  const SizedBox(width: 10),
                  IconButton(
                    onPressed: _stop,
                    icon: const Icon(Icons.stop, color: Colors.redAccent, size: 28),
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0x1AF44336),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 24),
            // Reference table
            Text('Referencia Morse:',
                style: TextStyle(
                  color: Color(0x99FFFFFF),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                )),
            const SizedBox(height: 8),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: _morseMap.entries.take(26).map((e) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF151515),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Color(0xFF1E1E1E)),
                  ),
                  child: Text(
                    '${e.key} ${e.value}',
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 10,
                      fontFamily: 'monospace',
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            // Timing info
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF111111),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Tiempos:',
                      style: TextStyle(
                        color: Color(0x99FFFFFF),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      )),
                  const SizedBox(height: 4),
                  _timingRow('.', 'Punto', '200ms'),
                  _timingRow('-', 'Raya', '600ms'),
                  _timingRow('  ', 'Entre simbolos', '200ms'),
                  _timingRow('   ', 'Entre letras', '600ms'),
                  _timingRow('/', 'Entre palabras', '1400ms'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _timingRow(String symbol, String label, String time) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Text(symbol,
                style: TextStyle(
                  color: Colors.amberAccent,
                  fontSize: 12,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w700,
                )),
          ),
          Expanded(
            child: Text(label,
                style: TextStyle(
                  color: Color(0x80FFFFFF),
                  fontSize: 11,
                )),
          ),
          Text(time,
              style: TextStyle(
                color: Color(0x66FFFFFF),
                fontSize: 10,
              )),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// SOS OVERLAY — Full-screen red overlay with countdown
// ─────────────────────────────────────────────
class SOSOverlay extends StatefulWidget {
  final VoidCallback onCancel;
  final void Function(String sosData) onSend;
  const SOSOverlay({super.key, required this.onCancel, required this.onSend});

  @override
  State<SOSOverlay> createState() => _SOSOverlayState();
}

class _SOSOverlayState extends State<SOSOverlay> {
  int _countdown = 5;
  Timer? _timer;
  String _location = '0.0:0.0';
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _flashlightOn = false;
  static const _kFlashlightChannel = MethodChannel('com.lessnet.flashlight');

  @override
  void initState() {
    super.initState();
    _getLocation();
    _startAlerts();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (mounted) {
        setState(() => _countdown--);
        if (_countdown <= 0) {
          t.cancel();
          _sendSOS();
        }
      }
    });
  }

  Future<void> _startAlerts() async {
    // Start continuous vibration pattern (repeat indefinitely)
    try {
      final hasVibrator = await Vibration.hasVibrator() ?? false;
      if (hasVibrator) {
        // Pattern: wait 0ms, vibrate 500ms, pause 200ms, vibrate 500ms, pause 200ms...
        // repeat: -1 means repeat indefinitely until Vibration.cancel()
        await Vibration.vibrate(
          pattern: [0, 500, 200, 500, 200, 500],
          repeat: -1,
        );
      }
    } catch (_) {}

    // Play alarm sound (loop) — try system alarm first, fallback to URL
    try {
      await _audioPlayer.setReleaseMode(ReleaseMode.loop);
      await _audioPlayer.setVolume(1.0);
      // Try system alarm sound first (works offline)
      try {
        await _audioPlayer.play(DeviceFileSource('/system/media/audio/alarms/Alarm_Beep_03.ogg'));
      } catch (_) {
        // Fallback to another common system alarm
        try {
          await _audioPlayer.play(DeviceFileSource('/system/media/audio/ringtones/Ring_Synth_04.ogg'));
        } catch (_) {
          // Last resort: remote URL (requires internet)
          await _audioPlayer.play(UrlSource('https://cdn.freesound.org/previews/331/331912_3248244-lq.mp3'));
        }
      }
    } catch (_) {}

    // Turn on flashlight
    try {
      await _kFlashlightChannel.invokeMethod('turnOn');
      _flashlightOn = true;
    } catch (_) {}
  }

  Future<void> _getLocation() async {
    try {
      final channel = MethodChannel(kLocationChannel);
      final loc = await channel.invokeMethod<Map>('getLocation');
      if (loc != null) {
        _location = '${loc['latitude'] ?? 0.0}:${loc['longitude'] ?? 0.0}';
      }
    } catch (_) {
      _location = '0.0:0.0';
    }
  }

  void _sendSOS() {
    final userId = BtService().connectedDeviceId.isNotEmpty
        ? BtService().connectedDeviceId : 'unknown';
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final sosData = '[SOS:$_location:$userId:$timestamp]';
    AppLogger.log('SOS enviado: $sosData');
    widget.onSend(sosData);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _audioPlayer.stop();
    _audioPlayer.dispose();
    Vibration.cancel();
    // Turn off flashlight
    if (_flashlightOn) {
      try { _kFlashlightChannel.invokeMethod('turnOff'); } catch (_) {}
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.red.withOpacity(0.9),
      child: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.warning, color: Colors.white, size: 64),
              const SizedBox(height: 24),
              const Text('SOS',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 64,
                    fontWeight: FontWeight.w900,
                  )),
              const SizedBox(height: 16),
              Text('Enviando en $_countdown...',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                  )),
              const SizedBox(height: 48),
              SizedBox(
                width: 200,
                height: 60,
                child: FilledButton(
                  onPressed: () {
                    _timer?.cancel();
                    _audioPlayer.stop();
                    Vibration.cancel();
                    if (_flashlightOn) {
                      try { _kFlashlightChannel.invokeMethod('turnOff'); } catch (_) {}
                      _flashlightOn = false;
                    }
                    widget.onCancel();
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.red,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text('CANCELAR',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      )),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// DEBUG OVERLAY — Small draggable overlay with log messages
// ─────────────────────────────────────────────
class DebugOverlay extends StatefulWidget {
  const DebugOverlay({super.key});

  @override
  State<DebugOverlay> createState() => _DebugOverlayState();
}

class _DebugOverlayState extends State<DebugOverlay> {
  final _scrollController = ScrollController();
  StreamSubscription? _logSub;

  @override
  void initState() {
    super.initState();
    _logSub = AppLogger().onLog.listen((_) {
      if (mounted) setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeOut,
          );
        }
      });
    });
  }

  @override
  void dispose() {
    _logSub?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final logs = AppLogger.getLogs();
    return Container(
      constraints: const BoxConstraints(maxHeight: 150),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.85),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: const BoxDecoration(
              color: Color(0xFF1A1A1A),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(8),
                topRight: Radius.circular(8),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.bug_report, color: Colors.greenAccent, size: 12),
                const SizedBox(width: 6),
                const Text('Debug', style: TextStyle(color: Colors.greenAccent, fontSize: 10, fontWeight: FontWeight.w700)),
                const Spacer(),
                GestureDetector(
                  onTap: () => AppLogger.setDebugMode(false),
                  child: const Icon(Icons.close, color: Colors.white38, size: 12),
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView.builder(
              controller: _scrollController,
              shrinkWrap: true,
              padding: const EdgeInsets.all(4),
              itemCount: logs.length,
              itemBuilder: (_, i) {
                return Text(logs[i],
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 9,
                      fontFamily: 'monospace',
                    ));
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// PROFILE PAGE — Settings and status
// ─────────────────────────────────────────────
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final bt = BtService();
  String _userName = '';
  bool _debugMode = false;
  bool _internetConnected = false;
  String _coordinates = 'No disponible';
  String _hotspotStatus = 'Desconocido';
  bool _bleEnabled = true;
  StreamSubscription? _connSub;
  StreamSubscription? _bleStateSub;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _checkInternet();
    _checkBleState();
    _connSub = bt.onConnectionChange.listen((_) {
      if (mounted) setState(() {});
    });
    _bleStateSub = FlutterBluePlus.adapterState.listen((state) {
      if (mounted) setState(() => _bleEnabled = state == BluetoothAdapterState.on);
    });
  }

  @override
  void dispose() {
    _connSub?.cancel();
    _bleStateSub?.cancel();
    super.dispose();
  }

  Future<void> _checkBleState() async {
    try {
      final state = await FlutterBluePlus.adapterState.first
          .timeout(const Duration(seconds: 5));
      if (mounted) setState(() => _bleEnabled = state == BluetoothAdapterState.on);
    } catch (_) {
      // If we can't determine the state, assume BLE is available
      // (most devices have BLE). Don't show "Desactivado" unless confirmed.
      if (mounted) setState(() => _bleEnabled = true);
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() {
      _userName = prefs.getString('user_name') ?? '';
      _debugMode = prefs.getBool('debug_mode') ?? false;
    });
  }

  Future<void> _checkInternet() async {
    try {
      final response = await http.get(
        Uri.parse('https://www.google.com'),
      ).timeout(const Duration(seconds: 5));
      if (mounted) setState(() => _internetConnected = response.statusCode == 200);
    } catch (_) {
      if (mounted) setState(() => _internetConnected = false);
    }
  }

  Future<void> _getCoordinates() async {
    try {
      final channel = MethodChannel(kLocationChannel);
      final loc = await channel.invokeMethod<Map>('getLocation');
      if (loc != null && mounted) {
        setState(() {
          _coordinates = '${loc['latitude']?.toStringAsFixed(4) ?? "?"}, ${loc['longitude']?.toStringAsFixed(4) ?? "?"}';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _coordinates = 'No disponible');
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Header('Perfil', Icons.person, 'Configuracion y estado'),
            const SizedBox(height: 20),

            // User name
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _kCardBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _kBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Nombre de usuario',
                      style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(_userName.isEmpty ? 'Sin nombre' : _userName,
                            style: TextStyle(
                              color: _userName.isEmpty ? Colors.white24 : Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            )),
                      ),
                      IconButton(
                        onPressed: () async {
                          final ctrl = TextEditingController(text: _userName);
                          final result = await showDialog<String>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              backgroundColor: const Color(0xFF1A1A1A),
                              title: const Text('Tu nombre', style: TextStyle(color: Colors.white)),
                              content: TextField(
                                controller: ctrl,
                                style: const TextStyle(color: Colors.white),
                                autofocus: true,
                                decoration: const InputDecoration(
                                  hintText: 'Escribe tu nombre...',
                                  hintStyle: TextStyle(color: Color(0xFF3A3A3A)),
                                ),
                                onSubmitted: (v) => Navigator.pop(ctx, v),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, null),
                                  child: const Text('Cancelar'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(ctx, ctrl.text),
                                  style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black),
                                  child: const Text('Guardar'),
                                ),
                              ],
                            ),
                          );
                          if (result != null) {
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.setString('user_name', result);
                            if (mounted) setState(() => _userName = result);
                          }
                        },
                        icon: const Icon(Icons.edit, color: Colors.white38, size: 18),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Debug mode toggle
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _kCardBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _kBorder),
              ),
              child: Row(
                children: [
                  const Icon(Icons.bug_report, color: Colors.white38, size: 20),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Modo Debug',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                        Text('Muestra overlay con logs',
                            style: TextStyle(color: Colors.white38, fontSize: 11)),
                      ],
                    ),
                  ),
                  Switch(
                    value: _debugMode,
                    onChanged: (v) async {
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setBool('debug_mode', v);
                      AppLogger.setDebugMode(v);
                      if (mounted) setState(() => _debugMode = v);
                    },
                    activeColor: Colors.white,
                    activeTrackColor: Colors.white38,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Status panel
            const Text('Estado',
                style: TextStyle(color: Colors.white38, fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            _statusRow(Icons.wifi, 'Internet', _internetConnected ? 'Conectado' : 'Sin conexion',
                _internetConnected ? Colors.greenAccent : Colors.redAccent),
            _statusRow(Icons.bluetooth, 'Dispositivos', '${bt.centralConnectionCount} conectado${bt.centralConnectionCount != 1 ? "s" : ""}',
                bt.isConnected ? Colors.greenAccent : Colors.white38),
            _statusRow(Icons.location_on, 'Coordenadas', _coordinates, Colors.white38),
            _statusRow(Icons.upload, 'Datos enviados', _fmtBytes(bt.bytesSent), Colors.white38),
            _statusRow(Icons.download, 'Datos recibidos', _fmtBytes(bt.bytesReceived), Colors.white38),
            _statusRow(Icons.bluetooth_connected, 'BLE', _bleEnabled ? 'Activado' : 'Verificando...',
                _bleEnabled ? Colors.greenAccent : Colors.orangeAccent),
            _statusRow(Icons.info, 'Version', 'v$kAppVersion', Colors.white38),
            _statusRow(Icons.wifi_tethering, 'Hotspot', _hotspotStatus, Colors.white38),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () { _checkInternet(); _getCoordinates(); },
                    icon: const Icon(Icons.refresh, color: Colors.white38, size: 16),
                    label: const Text('Actualizar', style: TextStyle(color: Colors.white54, fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0x1AFFFFFF)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _showChangelog,
                    icon: const Icon(Icons.article_outlined, color: Colors.white38, size: 16),
                    label: const Text('Changelog', style: TextStyle(color: Colors.white54, fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0x1AFFFFFF)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusRow(IconData icon, String label, String value, Color valueColor) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _kCardBgDim,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white38, size: 16),
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 13)),
          const Spacer(),
          Text(value, style: TextStyle(color: valueColor, fontSize: 13, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  String _fmtBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  Future<void> _showChangelog() async {
    showDialog(
      context: context,
      builder: (_) => const AlertDialog(
        backgroundColor: Color(0xFF1A1A1A),
        title: Text('Changelog', style: TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Descargando releases...', style: TextStyle(color: Colors.white54)),
            ],
          ),
        ),
      ),
    );
    try {
      final response = await http.get(
        Uri.parse('https://api.github.com/repos/$kGitHubOwner/$kGitHubRepo/releases?per_page=10'),
        headers: {'Accept': 'application/vnd.github+json'},
      ).timeout(const Duration(seconds: 10));
      if (mounted) Navigator.of(context).pop();
      if (response.statusCode != 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Error al obtener changelog'), backgroundColor: Colors.redAccent),
          );
        }
        return;
      }
      final List releases = json.decode(response.body);
      if (releases.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No hay releases disponibles'), backgroundColor: Colors.orange),
          );
        }
        return;
      }
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx2) => AlertDialog(
            backgroundColor: const Color(0xFF1A1A1A),
            title: const Text('Changelog', style: TextStyle(color: Colors.white)),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: releases.length,
                itemBuilder: (_, index) {
                  final release = releases[index];
                  final tag = release['tag_name'] ?? '?';
                  final name = release['name'] ?? tag;
                  final body = release['body'] ?? '';
                  final isCurrent = tag.replaceFirst('v', '') == kAppVersion;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF111111),
                      borderRadius: BorderRadius.circular(8),
                      border: isCurrent
                          ? Border.all(color: Colors.greenAccent.withOpacity(0.5))
                          : Border.all(color: const Color(0xFF2A2A2A)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(name,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                            if (isCurrent) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.greenAccent.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text('ACTUAL',
                                    style: TextStyle(color: Colors.greenAccent, fontSize: 10, fontWeight: FontWeight.w600)),
                              ),
                            ],
                          ],
                        ),
                        if (body.trim().isNotEmpty) ...[
                          const SizedBox(height: 8),
                          MarkdownBody(
                            data: body,
                            selectable: true,
                            styleSheet: MarkdownStyleSheet(
                              p: const TextStyle(color: Colors.white54, fontSize: 12, height: 1.5),
                              h2: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                              h3: const TextStyle(color: Colors.white60, fontSize: 12, fontWeight: FontWeight.w600),
                              listBullet: const TextStyle(color: Colors.white54, fontSize: 12),
                              code: const TextStyle(color: Colors.greenAccent, fontSize: 11, backgroundColor: Color(0xFF1A1A1A)),
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx2),
                child: const Text('Cerrar'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted && ModalRoute.of(context)?.isCurrent != true) {
        Navigator.pop(context);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }
}

// ─────────────────────────────────────────────
// VAULT URL PAGE — Fetch and display JSON from URL
// ─────────────────────────────────────────────
class VaultUrlPage extends StatefulWidget {
  const VaultUrlPage({super.key});

  @override
  State<VaultUrlPage> createState() => _VaultUrlPageState();
}

class _VaultUrlPageState extends State<VaultUrlPage> {
  final _urlCtrl = TextEditingController();
  bool _loading = false;
  String _error = '';
  String _content = '';
  List<String> _recentUrls = [];

  @override
  void initState() {
    super.initState();
    _loadRecentUrls();
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadRecentUrls() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() {
      _recentUrls = prefs.getStringList('vault_recent_urls') ?? [];
    });
  }

  Future<void> _fetchUrl() async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) return;
    setState(() { _loading = true; _error = ''; _content = ''; });
    try {
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        setState(() { _error = 'Error: ${response.statusCode}'; _loading = false; });
        return;
      }
      final data = json.decode(response.body);
      // Save to recent
      final prefs = await SharedPreferences.getInstance();
      final recent = prefs.getStringList('vault_recent_urls') ?? [];
      if (!recent.contains(url)) {
        recent.insert(0, url);
        if (recent.length > 10) recent.removeLast();
        await prefs.setStringList('vault_recent_urls', recent);
      }
      if (mounted) setState(() {
        _content = _formatJson(data);
        _loading = false;
        _recentUrls = recent;
      });
    } catch (e) {
      if (mounted) setState(() { _error = 'Error: $e'; _loading = false; });
    }
  }

  String _formatJson(dynamic data, [int indent = 0]) {
    final prefix = '  ' * indent;
    if (data is Map) {
      if (data.isEmpty) return '{}';
      final buf = StringBuffer('{\n');
      int i = 0;
      for (final key in data.keys) {
        buf.write('$prefix  "$key": ${_formatJson(data[key], indent + 1)}');
        if (i < data.length - 1) buf.write(',');
        buf.write('\n');
        i++;
      }
      buf.write('$prefix}');
      return buf.toString();
    } else if (data is List) {
      if (data.isEmpty) return '[]';
      final buf = StringBuffer('[\n');
      for (int i = 0; i < data.length; i++) {
        buf.write('$prefix  ${_formatJson(data[i], indent + 1)}');
        if (i < data.length - 1) buf.write(',');
        buf.write('\n');
      }
      buf.write('$prefix]');
      return buf.toString();
    } else if (data is String) {
      return '"${data.replaceAll('"', '\\"')}"';
    } else {
      return data.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111111),
        title: const Text('Cargar desde URL', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _kCardBgDim,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Colors.white24, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Ingresa una URL que devuelva JSON. El contenido se mostrara formateado.',
                        style: TextStyle(color: Color(0x66FFFFFF), fontSize: 11)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _urlCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'https://ejemplo.com/datos.json',
                hintStyle: const TextStyle(color: Color(0xFF3A3A3A)),
                prefixIcon: const Icon(Icons.link, color: Colors.white38),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_forward, color: Colors.white38),
                  onPressed: _fetchUrl,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (_) => _fetchUrl(),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: _loading
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                    : const Icon(Icons.download),
                label: Text(_loading ? 'Cargando...' : 'Obtener'),
                onPressed: _loading ? null : _fetchUrl,
              ),
            ),
            if (_recentUrls.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text('URLs recientes',
                  style: TextStyle(color: Colors.white38, fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              ..._recentUrls.take(5).map((url) => Container(
                margin: const EdgeInsets.only(bottom: 4),
                child: Material(
                  color: _kCardBgDim,
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () {
                      _urlCtrl.text = url;
                      _fetchUrl();
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Row(
                        children: [
                          const Icon(Icons.history, color: Colors.white24, size: 14),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(url,
                                style: const TextStyle(color: Colors.white54, fontSize: 11),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              )),
            ],
            if (_error.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0x0DF44336),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_error, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
              ),
            ],
            if (_content.isNotEmpty) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  const Text('Contenido',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _content));
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Copiado!'), backgroundColor: Colors.grey));
                    },
                    icon: const Icon(Icons.copy, size: 14),
                    label: const Text('Copiar', style: TextStyle(fontSize: 11)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D0D0D),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _kBorder),
                ),
                constraints: const BoxConstraints(maxHeight: 500),
                child: SingleChildScrollView(
                  child: MarkdownBody(
                    data: '```json\n$_content\n```',
                    selectable: true,
                    styleSheet: MarkdownStyleSheet(
                      code: const TextStyle(
                        color: Colors.greenAccent,
                        fontSize: 11,
                        fontFamily: 'monospace',
                        height: 1.4,
                        backgroundColor: Color(0xFF111111),
                      ),
                      p: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
