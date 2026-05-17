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

// ─── UUIDs del servicio BLE de LessNet ───
const String lessnetServiceUuid = "6e400001-b5a3-f393-e0a9-e50e24dcca9e";
const String lessnetCharRxUuid = "6e400002-b5a3-f393-e0a9-e50e24dcca9e";
const String lessnetCharTxUuid = "6e400003-b5a3-f393-e0a9-e50e24dcca9e";

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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    LessNetNotifications.setAppForeground(true);
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
          iconTheme: WidgetStateProperty.all(
            const IconThemeData(color: Colors.grey),
          ),
          labelTextStyle: WidgetStateProperty.all(
            const TextStyle(color: Colors.grey, fontSize: 11),
          ),
        ),
      ),
      home: const HomePage(),
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

const int _kBleWriteSize = 200; // bytes por write BLE (MTU-safe)
const int _kMaxFileSize = 2 * 1024 * 1024; // 2 MB
const int _kPeripheralNotifyDelayMs = 10; // ms entre notificaciones (peripheral)

class BtService {
  static final BtService _instance = BtService._internal();
  factory BtService() => _instance;
  BtService._internal() {
    _setupPeripheralChannel();
  }

  BluetoothDevice? connectedDevice;
  BluetoothCharacteristic? rxChar;
  BluetoothCharacteristic? txChar;
  StreamSubscription? _txSub;
  StreamSubscription? _connSub;
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
      connectedDevice != null || _peripheralConnected;
  bool get connecting => _isConnecting;
  String get advertisingError => _advertisingError;

  String get connectedName {
    if (connectedDevice != null) {
      return connectedDevice!.platformName.isEmpty
          ? 'Dispositivo'
          : connectedDevice!.platformName;
    }
    if (_peripheralConnected) {
      return _peripheralDeviceName.isEmpty
          ? 'Dispositivo'
          : _peripheralDeviceName;
    }
    return '';
  }

  String get connectedDeviceId {
    if (connectedDevice != null) {
      return connectedDevice!.platformName.isNotEmpty
          ? connectedDevice!.platformName
          : connectedDevice!.remoteId.toString();
    }
    if (_peripheralConnected && _peripheralDeviceName.isNotEmpty) {
      return _peripheralDeviceName;
    }
    return '';
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
    try {
      await _peripheralChannel.invokeMethod('startAdvertising');
      _isPeripheral = true;
      _isAdvertising = true;
      _advertisingController.add(true);
      // Start foreground service while advertising
      try { await startForegroundService(); } catch (_) {}
    } catch (e) {
      _isAdvertising = false;
      _advertisingError = e.toString().contains('ADV_ERROR')
          ? 'Este dispositivo NO soporta BLE advertising.'
          : 'Error: $e';
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
      await _cleanupPreConnect();
      await device.connect(timeout: const Duration(seconds: 20));
      connectedDevice = device;
      _connectionController.add(true);

      try {
        await device.requestMtu(512);
      } catch (_) {}

      final services = await device.discoverServices();
      for (final service in services) {
        if (service.uuid.str128.toLowerCase() ==
            lessnetServiceUuid.toLowerCase()) {
          for (final char in service.characteristics) {
            if (char.uuid.str128.toLowerCase() ==
                lessnetCharRxUuid.toLowerCase()) {
              rxChar = char;
            } else if (char.uuid.str128.toLowerCase() ==
                lessnetCharTxUuid.toLowerCase()) {
              txChar = char;
            }
          }
        }
      }

      if (txChar != null) {
        _receiveBuffer.clear();
        final notifyOk = await txChar!.setNotifyValue(true);
        if (!notifyOk) {
          await Future.delayed(const Duration(milliseconds: 200));
          await txChar!.setNotifyValue(true);
        }
        _txSub = txChar!.onValueChangedStream.listen((value) {
          if (value.isNotEmpty) {
            _handleReceivedData(value);
          }
        });
      }

      _connSub = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _statusController.add('Desconectado');
          _cleanup();
        }
      });

      _statusController.add('Conectado');
    } catch (e) {
      _statusController.add('Error: $e');
      _cleanup();
      rethrow;
    } finally {
      _isConnecting = false;
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
    final msg = ChatMessage(id: DateTime.now().microsecondsSinceEpoch.toString(), text: text, mine: false, time: DateTime.now(), deviceId: connectedDeviceId);
    messages.add(msg);
    _msgController.add(msg);
    MessageDB.insert(msg);
    // Show notification for background message
    try { LessNetNotifications.showMessageNotification(connectedName, text); } catch (_) {}
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
  Future<void> _sendRawMessage(String text) async {
    final bytes = utf8.encode(text);
    if (_isPeripheral && _peripheralConnected) {
      // Peripheral: send via Kotlin (handles notifications internally)
      await _peripheralChannel.invokeMethod('sendData', {'data': text});
    } else if (rxChar != null) {
      // Central: write in 200-byte chunks, no delay needed
      // (withoutResponse: false blocks until ACK from peripheral)
      for (int i = 0; i < bytes.length; i += _kBleWriteSize) {
        final end = i + _kBleWriteSize > bytes.length ? bytes.length : i + _kBleWriteSize;
        final chunk = bytes.sublist(i, end);
        await rxChar!.write(Uint8List.fromList(chunk), withoutResponse: false);
      }
      // Null terminator
      await rxChar!.write(Uint8List.fromList([0x00]), withoutResponse: false);
    }
  }

  Future<void> sendMessage(String text) async {
    if (text.isEmpty) return;
    final msg = ChatMessage(id: DateTime.now().microsecondsSinceEpoch.toString(), text: text, mine: true, time: DateTime.now(), deviceId: connectedDeviceId);
    messages.add(msg);
    _msgController.add(msg);
    MessageDB.insert(msg);

    await _sendRawMessage(text);
  }

  // ─── File send — simple protocol, one message, MTU-aware ───
  Future<void> sendFile({
    required String localPath,
    required String msgType, // 'image', 'video', 'file'
    required String fileName,
  }) async {
    final file = File(localPath);
    final bytes = await file.readAsBytes();
    final fileSize = bytes.length;
    final fileCrc = _crc32(bytes);
    final b64 = base64Encode(bytes);
    final typeCode = msgType == 'image' ? 'img' : (msgType == 'video' ? 'vid' : 'file');

    final msgId = DateTime.now().microsecondsSinceEpoch.toString();

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
      deviceId: connectedDeviceId,
    );
    messages.add(msg);
    _msgController.add(msg);
    MessageDB.insert(msg);

    _isSending = true;
    _progressController.add({'progress': 0.0, 'msgId': msgId, 'fileName': fileName});

    try {
      // Build the full payload: [FILE:TYPE:FILENAME:SIZE:CRC32]base64data
      final payload = '[FILE:$typeCode:$fileName:$fileSize:$fileCrc]$b64';
      final payloadBytes = utf8.encode(payload);

      if (_isPeripheral && _peripheralConnected) {
        // Peripheral: use Kotlin sendData (handles notifications + progress)
        await _peripheralChannel.invokeMethod('sendFile', {'data': payload});
      } else if (rxChar != null) {
        // Central: write in 200-byte chunks
        // withoutResponse: false = write request = blocks until ACK = reliable
        final totalWrites = (payloadBytes.length / _kBleWriteSize).ceil() + 1; // +1 for null term
        int writesDone = 0;

        for (int i = 0; i < payloadBytes.length; i += _kBleWriteSize) {
          final end = i + _kBleWriteSize > payloadBytes.length ? payloadBytes.length : i + _kBleWriteSize;
          final chunk = payloadBytes.sublist(i, end);
          await rxChar!.write(Uint8List.fromList(chunk), withoutResponse: false);
          writesDone++;
          // Report progress every 5 writes to avoid UI spam
          if (writesDone % 5 == 0 || i + _kBleWriteSize >= payloadBytes.length) {
            final progress = (i + _kBleWriteSize) / payloadBytes.length;
            _progressController.add({'progress': progress.clamp(0.0, 1.0), 'msgId': msgId, 'fileName': fileName});
          }
        }

        // Null terminator
        await rxChar!.write(Uint8List.fromList([0x00]), withoutResponse: false);
        _progressController.add({'progress': 1.0, 'msgId': msgId, 'fileName': fileName});
      }
    } catch (e) {
      _progressController.add({'progress': -1.0, 'msgId': msgId, 'fileName': fileName, 'error': e.toString()});
      rethrow;
    } finally {
      _isSending = false;
    }
  }

  Future<void> _cleanupPreConnect() async {
    _txSub?.cancel();
    _txSub = null;
    _connSub?.cancel();
    _connSub = null;
    rxChar = null;
    txChar = null;
    _receiveBuffer.clear();
    _isSending = false;
    if (connectedDevice != null) {
      try {
        await connectedDevice!.disconnect();
      } catch (_) {}
      connectedDevice = null;
    }
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
    _connectionController.add(false);
  }

  Future<void> disconnect() async {
    _statusController.add('Desconectando...');
    if (connectedDevice != null) {
      try {
        await connectedDevice!.disconnect();
      } catch (_) {}
    }
    if (_isPeripheral) await stopAdvertising();
    _cleanup();
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
      version: 2,
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

  String get displayName => deviceId.isEmpty ? 'General' : deviceId;
}

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
          ChatListPage(),
          VaultHomePage(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: const Color(0xFF111111),
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
          NavigationDestination(
            icon: Icon(Icons.folder_outlined),
            selectedIcon: Icon(Icons.folder),
            label: 'Vault',
          ),
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
  List<_PermItem> get _perms {
    final items = [
      _PermItem('Ubicacion', Icons.location_on,
          Permission.locationWhenInUse, 'Requerida para BT scan'),
      _PermItem('Bluetooth Scan', Icons.bluetooth_searching,
          Permission.bluetoothScan, 'Buscar dispositivos'),
      _PermItem('Bluetooth Connect', Icons.bluetooth_connected,
          Permission.bluetoothConnect, 'Conectarse a dispositivos'),
      _PermItem('Bluetooth Advertise', Icons.broadcast_on_personal,
          Permission.bluetoothAdvertise, 'Hacerse visible'),
    ];
    // Android 13+ uses photos/videos, older uses storage
    items.add(_PermItem('Fotos', Icons.photo_library,
        Permission.photos, 'Acceder a la galeria'));
    items.add(_PermItem('Videos', Icons.videocam,
        Permission.videos, 'Acceder a videos'));
    items.add(_PermItem('Almacenamiento', Icons.folder,
        Permission.storage, 'Archivos (Android 12 o menor)'));
    items.add(_PermItem('Notificaciones', Icons.notifications,
        Permission.notification, 'Alertas de mensajes'));
    return items;
  }

  final Map<Permission, PermissionStatus> _statuses = {};
  bool _loading = false;
  bool _btOn = false;

  @override
  void initState() {
    super.initState();
    _checkAll();
    _checkBt();
  }

  Future<void> _checkBt() async {
    try {
      final s = await FlutterBluePlus.adapterState.first.timeout(
        const Duration(seconds: 3),
        onTimeout: () => BluetoothAdapterState.unknown,
      );
      if (mounted) {
        setState(() => _btOn = s == BluetoothAdapterState.on);
      }
    } catch (_) {}
  }

  Future<void> _checkAll() async {
    for (final p in _perms) {
      try {
        final s = await p.permission.status;
        if (mounted) setState(() => _statuses[p.permission] = s);
      } catch (_) {
        // Some permissions (photos, videos) don't exist on Android < 13
        if (mounted) setState(() => _statuses[p.permission] = PermissionStatus.denied);
      }
    }
  }

  Future<void> _requestAll() async {
    setState(() => _loading = true);
    try {
      // Build list dynamically — skip permissions that don't exist on this device
      final permsToRequest = <Permission>[];
      for (final p in _perms) {
        try {
          final status = await p.permission.status;
          if (!status.isGranted) {
            permsToRequest.add(p.permission);
          } else {
            if (mounted) setState(() => _statuses[p.permission] = status);
          }
        } catch (_) {
          // Permission not available on this Android version, skip
        }
      }
      if (permsToRequest.isNotEmpty) {
        final r = await permsToRequest.request();
        if (mounted) setState(() => _statuses.addAll(r));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    _checkBt();
  }

  String _st(PermissionStatus? s) {
    if (s == null) return '...';
    if (s.isGranted) return 'Concedido';
    if (s.isDenied) return 'Denegado';
    if (s.isPermanentlyDenied) return 'Denegado siempre';
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
            const _Header('Permisos', Icons.shield,
                'Necesarios para Bluetooth'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (_btOn ? Colors.white : Colors.red)
                    .withOpacity(0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: (_btOn ? Colors.white : Colors.red)
                      .withOpacity(0.15),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _btOn ? Icons.bluetooth : Icons.bluetooth_disabled,
                    color: _btOn ? Colors.white : Colors.redAccent,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _btOn
                          ? 'Bluetooth ACTIVADO'
                          : 'Bluetooth DESACTIVADO!',
                      style: TextStyle(
                        color:
                            _btOn ? Colors.white : Colors.redAccent,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.03),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.gps_fixed,
                      color: Colors.white38, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Activa la UBICACION en ajustes del telefono para buscar BLE.',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView(
                children: _perms.map((p) {
                  final st = _statuses[p.permission];
                  final g = st?.isGranted ?? false;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: Colors.white.withOpacity(0.06)),
                    ),
                    child: Row(
                      children: [
                        Icon(p.icon,
                            color: g ? Colors.white : Colors.white38,
                            size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text(p.name,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  )),
                              Text(p.desc,
                                  style: TextStyle(
                                    color:
                                        Colors.white.withOpacity(0.3),
                                    fontSize: 11,
                                  )),
                            ],
                          ),
                        ),
                        Icon(
                          g ? Icons.check_circle : Icons.cancel,
                          color: g ? Colors.white : Colors.redAccent,
                          size: 18,
                        ),
                      ],
                    ),
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
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.black,
                        ),
                      )
                    : const Icon(Icons.done_all),
                label: Text(_loading
                    ? 'Solicitando...'
                    : 'Solicitar todos'),
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
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(m),
            backgroundColor: Colors.grey[800],
          ),
        );
      }
    });
  }

  Future<void> _startScan() async {
    if (bt.isAdvertising) await bt.stopAdvertising();

    final st = await [
      Permission.locationWhenInUse,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();

    if (!(st[Permission.bluetoothScan]?.isGranted ?? false) ||
        !(st[Permission.bluetoothConnect]?.isGranted ?? false)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Concede permisos primero'),
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
      if (a != BluetoothAdapterState.on) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Bluetooth APAGADO!'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 5),
          ));
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
      // NO withServices filter — OPPO can't handle 128-bit UUID filters
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 60),
        androidUsesFineLocation: true,
      );
      _scanSub = FlutterBluePlus.scanResults.listen((r) {
        if (mounted) {
          setState(() {
            _results.clear();
            _results.addAll(r);
          });
        }
      });
      _scanningSub = FlutterBluePlus.isScanning.listen((s) {
        if (!s && mounted) {
          setState(() => _scanning = false);
          _scanTimer?.cancel();
          _scanTimer = null;
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() => _scanning = false);
        _scanTimer?.cancel();
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

  Future<void> _startAdv() async {
    if (_scanning) await _stopScan();
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

  String _fmt(int s) {
    return '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _scanningSub?.cancel();
    _connSub?.cancel();
    _advSub?.cancel();
    _statusSub?.cancel();
    _advTimer?.cancel();
    _scanTimer?.cancel();
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final conn = bt.isConnected;
    final sorted = List<ScanResult>.from(_results)..sort((a, b) {
      final aL = a.advertisementData.serviceUuids.any(
          (u) => u.str128.toLowerCase() == lessnetServiceUuid.toLowerCase());
      final bL = b.advertisementData.serviceUuids.any(
          (u) => u.str128.toLowerCase() == lessnetServiceUuid.toLowerCase());
      if (aL && !bL) return -1;
      if (!aL && bL) return 1;
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
              conn
                  ? 'Conectado: ${bt.connectedName}'
                  : bt.isAdvertising
                      ? 'Visible'
                      : 'Sin conexion',
              subtitleColor: conn ? Colors.greenAccent : (bt.isAdvertising ? Colors.blueAccent : Colors.white38),
            ),
            const SizedBox(height: 16),

            // Connected device card
            if (conn)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: Colors.white.withOpacity(0.15)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.bluetooth_connected,
                        color: Colors.white, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(bt.connectedName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          )),
                    ),
                    TextButton(
                      onPressed: () => bt.disconnect(),
                      child: const Text('Desconectar',
                          style: TextStyle(color: Colors.redAccent)),
                    ),
                  ],
                ),
              ),

            // Advertising indicator
            if (bt.isAdvertising && !conn)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: Colors.white.withOpacity(0.1)),
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
                          color: Colors.white.withOpacity(0.6),
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
                  color: Colors.red.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Advertising no disponible. Usa ESTE celular para BUSCAR.',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
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
                    onPressed: conn
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

            const SizedBox(height: 16),

            // Scan results
            if (_scanning || _results.isNotEmpty) ...[
              Row(
                children: [
                  Text(
                    'Encontrados (${_results.length})',
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
                final isLN = r.advertisementData.serviceUuids.any(
                    (u) => u.str128.toLowerCase() ==
                        lessnetServiceUuid.toLowerCase());
                final name = r.device.platformName.isNotEmpty
                    ? r.device.platformName
                    : 'Desconocido';
                final sig = r.rssi > -60
                    ? Colors.greenAccent
                    : r.rssi > -80
                        ? Colors.orangeAccent
                        : Colors.redAccent;

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isLN
                        ? Colors.white.withOpacity(0.06)
                        : Colors.white.withOpacity(0.02),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isLN
                          ? Colors.white.withOpacity(0.12)
                          : Colors.white.withOpacity(0.04),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isLN ? Icons.phone_android : Icons.bluetooth,
                        color: isLN ? Colors.white : Colors.white38,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(name,
                                      style: TextStyle(
                                        color: isLN
                                            ? Colors.white
                                            : Colors.white60,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                      )),
                                ),
                                if (isLN)
                                  Container(
                                    padding: const EdgeInsets
                                        .symmetric(
                                        horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: Colors.white
                                          .withOpacity(0.12),
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
                              ],
                            ),
                            Text(
                              r.device.remoteId.toString(),
                              style: TextStyle(
                                color:
                                    Colors.white.withOpacity(0.25),
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: sig.withOpacity(0.12),
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
            ] else if (!_scanning &&
                !bt.isAdvertising &&
                !conn)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 30),
                  child: Text(
                    'Presiona Buscar o Visible\npara empezar',
                    style:
                        TextStyle(color: Colors.white.withOpacity(0.15)),
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentDeviceId = bt.connectedDeviceId;

    // If connected, open the chat for that device directly
    if (bt.isConnected && currentDeviceId.isNotEmpty) {
      return ChatPage(deviceId: currentDeviceId);
    }

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: _Header(
              'Chat',
              Icons.chat_bubble,
              _conversations.isEmpty
                  ? 'Sin conversaciones'
                  : '${_conversations.length} conversacion${_conversations.length > 1 ? 'es' : ''}',
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: Colors.white))
                : _conversations.isEmpty
                    ? Center(
                        child: Text(
                          'Conecta un dispositivo para chatear',
                          style: TextStyle(color: Colors.white.withOpacity(0.15)),
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
                                  color: Colors.red.withOpacity(0.15),
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
                                          color: Colors.white.withOpacity(0.08),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: Colors.white.withOpacity(0.12)),
                                        )
                                      : BoxDecoration(
                                          color: Colors.white.withOpacity(0.03),
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
                                              color: isActive
                                                  ? Colors.white.withOpacity(0.1)
                                                  : Colors.white.withOpacity(0.05),
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                            child: Icon(
                                              isActive ? Icons.bluetooth_connected : Icons.phone_android,
                                              color: isActive ? Colors.white : Colors.white38,
                                              size: 20,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  conv.displayName,
                                                  style: TextStyle(
                                                    color: isActive ? Colors.white : Colors.white70,
                                                    fontWeight: FontWeight.w600,
                                                    fontSize: 14,
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  conv.lastMessage,
                                                  style: TextStyle(
                                                    color: Colors.white.withOpacity(0.35),
                                                    fontSize: 12,
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ],
                                            ),
                                          ),
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.end,
                                            children: [
                                              Text(
                                                _fmtTime(conv.lastTime),
                                                style: TextStyle(
                                                  color: Colors.white.withOpacity(0.25),
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
  StreamSubscription? _msgSub;
  StreamSubscription? _connSub;
  StreamSubscription? _progressSub;
  bool _connected = false;
  double _sendProgress = 0;
  bool _sending = false;
  bool _loadingHistory = true;
  String _sendingFileName = '';
  Timer? _sendTimeout;

  @override
  void initState() {
    super.initState();
    _connected = bt.isConnected;
    _loadHistory();
    _msgSub = bt.onMessage.listen((_) {
      if (mounted) setState(() {});
      _toBottom();
    });
    _connSub = bt.onConnectionChange.listen((_) {
      if (mounted) setState(() => _connected = bt.isConnected);
    });
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
    _ctrl.clear();
    try {
      await bt.sendMessage(t);
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
    _sendTimeout?.cancel();
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final msgs = widget.deviceId.isNotEmpty
        ? bt.messages.where((m) => m.deviceId == widget.deviceId || (widget.deviceId.isEmpty && m.deviceId.isEmpty)).toList()
        : bt.messages;
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
                    'Chat',
                    Icons.chat_bubble,
                    _connected
                        ? 'Conectado por Bluetooth'
                        : 'Sin conexion',
                    subtitleColor: _connected ? Colors.greenAccent : Colors.white38,
                  ),
                ),
                if (widget.deviceId.isNotEmpty)
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
              ],
            ),
          ),
          if (_connected)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.bluetooth_connected, color: Colors.white, size: 14),
                  const SizedBox(width: 6),
                  Text(
                    'Conectado a ${bt.connectedName}',
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
                    style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 10),
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
                              ? 'Escribe un mensaje'
                              : 'Conecta un dispositivo primero',
                          style: TextStyle(color: Colors.white.withOpacity(0.15)),
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
                          hintText: _connected ? 'Mensaje...' : 'Sin conexion',
                          hintStyle: TextStyle(color: Colors.white.withOpacity(0.15)),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.04),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Colors.white24),
                          ),
                        ),
                        onSubmitted: (_) => _send(),
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
                      style: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 10),
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
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: const BoxConstraints(maxWidth: 280),
        decoration: BoxDecoration(
          color: m.mine ? Colors.white : Colors.white.withOpacity(0.08),
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
                  )),
            const SizedBox(height: 4),
            // Time + size
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_fmt(m.time),
                    style: TextStyle(
                      color: m.mine ? Colors.black38 : Colors.white.withOpacity(0.25),
                      fontSize: 10,
                    )),
                if (m.fileSize != null) ...[
                  const SizedBox(width: 6),
                  Text(_fmtSize(m.fileSize),
                      style: TextStyle(
                        color: m.mine ? Colors.black38 : Colors.white.withOpacity(0.25),
                        fontSize: 10,
                      )),
                ],
              ],
            ),
          ],
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
                color: Colors.black.withOpacity(0.35),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            // Play button centered
            Center(
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
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
          color: (m.mine ? Colors.black : Colors.white).withOpacity(0.06),
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
                          color: m.mine ? Colors.black38 : Colors.white.withOpacity(0.4),
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
class VaultHomePage extends StatelessWidget {
  const VaultHomePage({super.key});

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
        '54 puntos en Colombia',
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
    ];

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Header('Vault', Icons.folder, 'Recursos offline'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.03),
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
                        color: Colors.white.withOpacity(0.4),
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ...sections.map((s) => Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: Material(
                    color: Colors.white.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => s.page),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: s.color.withOpacity(0.1),
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
                                        color: Colors.white
                                            .withOpacity(0.35),
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
          side: BorderSide(color: Colors.white.withOpacity(0.1)),
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
  bool _loading = true;

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
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
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
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _items.length,
              itemBuilder: (_, i) {
                final it = _items[i] as Map<String, dynamic>;
                final p = it['prioridad'] ?? '';
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: Colors.white.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(12),
                    child: ListTile(
                      contentPadding:
                          const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 6),
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _pColor(p).withOpacity(0.1),
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
                                Colors.white.withOpacity(0.3),
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
                                color: _pColor(p)
                                    .withOpacity(0.15),
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
  bool _loading = true;

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
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
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
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _items.length,
              itemBuilder: (_, i) {
                final it = _items[i] as Map<String, dynamic>;
                final cat = it['categoria'] ?? '';
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: Colors.white.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(12),
                    child: ListTile(
                      contentPadding:
                          const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 6),
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.06),
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
                                Colors.white.withOpacity(0.3),
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
                                color: Colors.white
                                    .withOpacity(0.08),
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
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
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
                hintStyle: TextStyle(
                    color: Colors.white.withOpacity(0.2)),
                prefixIcon: const Icon(Icons.search,
                    color: Colors.white38),
                filled: true,
                fillColor: Colors.white.withOpacity(0.04),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                      color: Colors.white24),
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
                                  Colors.white.withOpacity(0.04),
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
                                      color: Colors.white
                                          .withOpacity(0.4),
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
                                    color: Colors.white
                                        .withOpacity(0.06),
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

class _DictDetail extends StatelessWidget {
  final Map<String, dynamic> item;
  const _DictDetail({required this.item});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111111),
        title: Text(item['palabra'] ?? '',
            style: const TextStyle(color: Colors.white)),
        iconTheme:
            const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item['palabra'] ?? '',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                )),
            const SizedBox(height: 12),
            Text(item['definicion'] ?? '',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 14,
                  height: 1.6,
                )),
            if ((item['sinonimos'] as List?)?.isNotEmpty ??
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
                children: (item['sinonimos'] as List)
                    .map((s) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color:
                                Colors.white.withOpacity(0.05),
                            borderRadius:
                                BorderRadius.circular(6),
                          ),
                          child: Text(s.toString(),
                              style: TextStyle(
                                color:
                                    Colors.white.withOpacity(0.6),
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
  bool _loading = true;
  String? _selectedCat;

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
    setState(() {});
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
                          backgroundColor:
                              Colors.white.withOpacity(0.05),
                          selectedColor:
                              Colors.white.withOpacity(0.15),
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
                              backgroundColor:
                                  Colors.white.withOpacity(0.05),
                              selectedColor:
                                  Colors.white.withOpacity(0.15),
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
                  child: _articles.isEmpty
                      ? Center(
                          child: Text('Sin articulos',
                              style:
                                  TextStyle(color: Colors.white24)))
                      : ListView.builder(
                          itemCount: _articles.length,
                          itemBuilder: (_, i) {
                            final it = _articles[i]
                                as Map<String, dynamic>;
                            return Container(
                              margin:
                                  const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 3),
                              child: Material(
                                color: Colors.white
                                    .withOpacity(0.04),
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
                                        color: Colors.white
                                            .withOpacity(0.35),
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

class _WikiDetail extends StatelessWidget {
  final Map<String, dynamic> item;
  const _WikiDetail({required this.item});

  @override
  Widget build(BuildContext context) {
    final sections = item['secciones'] as List? ?? [];
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111111),
        title: Text(item['titulo'] ?? '',
            style: const TextStyle(
                color: Colors.white, fontSize: 16)),
        iconTheme:
            const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item['resumen'] ?? '',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
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
                        color: Colors.white.withOpacity(0.65),
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

  @override
  void initState() {
    super.initState();
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
            return t == 'hospital_referencia';
          }
          return true;
        }).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111111),
        title: const Text('Emergencias Colombia',
            style: TextStyle(color: Colors.white)),
        iconTheme:
            const IconThemeData(color: Colors.white),
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
                  child: _filtered.isEmpty
                      ? Center(
                          child: Text('Sin resultados',
                              style: TextStyle(
                                  color: Colors.white24)))
                      : ListView.builder(
                          itemCount: _filtered.length,
                          itemBuilder: (_, i) {
                            final f = _filtered[i]
                                as Map<String, dynamic>;
                            final p = f['properties']
                                    as Map<String, dynamic>? ??
                                {};
                            final t = p['tipo'] ?? '';
                            return Container(
                              margin:
                                  const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 3),
                              child: Material(
                                color: Colors.white
                                    .withOpacity(0.04),
                                borderRadius:
                                    BorderRadius.circular(10),
                                child: ListTile(
                                  dense: true,
                                  leading: Icon(_typeIcon(t),
                                      color: _typeColor(t),
                                      size: 20),
                                  title: Text(p['nombre'] ?? '',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                      )),
                                  subtitle: Text(
                                    '${p['departamento'] ?? ''} - ${p['descripcion'] ?? ''}',
                                    style: TextStyle(
                                      color: Colors.white
                                          .withOpacity(0.3),
                                      fontSize: 11,
                                    ),
                                    maxLines: 1,
                                    overflow:
                                        TextOverflow.ellipsis,
                                  ),
                                  trailing: p['emergencia'] !=
                                          null
                                      ? Container(
                                          padding:
                                              const EdgeInsets
                                                  .symmetric(
                                                  horizontal: 5,
                                                  vertical: 1),
                                          decoration:
                                              BoxDecoration(
                                            color: Colors.red
                                                .withOpacity(0.12),
                                            borderRadius:
                                                BorderRadius
                                                    .circular(3),
                                          ),
                                          child: Text(
                                            '${p['emergencia']}',
                                            style:
                                                const TextStyle(
                                              color:
                                                  Colors.redAccent,
                                              fontSize: 9,
                                              fontWeight:
                                                  FontWeight.w700,
                                            ),
                                          ),
                                        )
                                      : null,
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          _MapDetailPage(
                                              props: p),
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

  Widget _mapFilter(String label, String val) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        label: Text(label),
        selected: _filter == val,
        onSelected: (_) => setState(() => _filter = val),
        backgroundColor: Colors.white.withOpacity(0.05),
        selectedColor: Colors.white.withOpacity(0.15),
        labelStyle: TextStyle(
          color: _filter == val ? Colors.white : Colors.white54,
          fontSize: 12,
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
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 14,
                  )),
            const SizedBox(height: 12),
            Text(props['descripcion'] ?? '',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
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
                color: Colors.white.withOpacity(0.4),
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
                color: Colors.white.withOpacity(0.03),
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
                        color: Colors.white.withOpacity(0.4),
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
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber, color: Colors.orange, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Faltan modelos de idioma. Toca el icono de descarga arriba para descargarlos.',
                        style: TextStyle(
                          color: Colors.orange.withOpacity(0.8),
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
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.2)),
                filled: true,
                fillColor: Colors.white.withOpacity(0.04),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white24),
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
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Traduccion:',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.4),
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
              color: Colors.white.withOpacity(0.4),
              fontSize: 11,
            )),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.04),
            borderRadius: BorderRadius.circular(8),
            border: _modelStatus[value] == 'downloaded'
                ? Border.all(color: Colors.white12)
                : Border.all(color: Colors.orange.withOpacity(0.3)),
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
              color: Colors.white.withOpacity(0.04),
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
                            color: Colors.white.withOpacity(0.4),
                            fontSize: 12,
                          )),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: downloaded > 0 ? Colors.green.withOpacity(0.2) : Colors.orange.withOpacity(0.2),
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
                    color: Colors.white.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: status == 'downloaded'
                          ? Colors.white.withOpacity(0.08)
                          : status == 'downloading'
                              ? Colors.blue.withOpacity(0.3)
                              : Colors.white.withOpacity(0.04),
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
                                  color: Colors.greenAccent.withOpacity(0.6),
                                  fontSize: 11,
                                ),
                              )
                            else if (status == 'downloading')
                              Text(
                                'Descargando... ${(progress != null ? (progress * 100).toStringAsFixed(0) : '0')}%',
                                style: TextStyle(
                                  color: Colors.blueAccent.withOpacity(0.8),
                                  fontSize: 11,
                                ),
                              )
                            else
                              Text(
                                'Toca para descargar (~30 MB)',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.3),
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
                            backgroundColor: Colors.white.withOpacity(0.1),
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
                hintStyle: TextStyle(
                    color: Colors.white.withOpacity(0.2)),
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
                filled: true,
                fillColor: Colors.white.withOpacity(0.04),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                      color: Colors.white24),
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
                                  Colors.white.withOpacity(0.04),
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
                                      color: Colors.white
                                          .withOpacity(0.3),
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
                                    color: Colors.white
                                        .withOpacity(0.06),
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
class _DetailPage extends StatelessWidget {
  final String title;
  final Map<String, dynamic> item;
  const _DetailPage({required this.title, required this.item});

  @override
  Widget build(BuildContext context) {
    final steps = item['pasos'] as List? ?? [];
    final warnings = item['advertencias'] as List? ?? [];
    final references = item['referencias'] as List? ?? [];
    final help = item['cuando_buscar_ayuda'] ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111111),
        title: Text(title,
            style: const TextStyle(
                color: Colors.white, fontSize: 16)),
        iconTheme:
            const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (item['resumen'] != null) ...[
              Text(item['resumen'],
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
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
              ...steps.asMap().entries.map((e) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          margin: const EdgeInsets.only(right: 10),
                          decoration: BoxDecoration(
                            color:
                                Colors.white.withOpacity(0.08),
                            borderRadius:
                                BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: Text('${e.key + 1}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                )),
                          ),
                        ),
                        Expanded(
                          child: Text(e.value.toString(),
                              style: TextStyle(
                                color:
                                    Colors.white.withOpacity(0.7),
                                fontSize: 13,
                              )),
                        ),
                      ],
                    ),
                  )),
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
                      color: Colors.red.withOpacity(0.04),
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
                                    Colors.white.withOpacity(0.6),
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
                    color: Colors.white.withOpacity(0.6),
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
                              Colors.white.withOpacity(0.35),
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
            color: Colors.white.withOpacity(0.06),
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
                    color: subtitleColor ?? Colors.white.withOpacity(0.35),
                    fontSize: 12,
                  )),
            ],
          ),
        ),
      ],
    );
  }
}
