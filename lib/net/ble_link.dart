// ─────────────────────────────────────────────────────────────
// LessNet — BLE link adapter
//
// Wraps one BLE connection (central→peripheral, or the peripheral
// side of an inbound connection) in the [LnLink] interface, so the
// mesh router and the link manager can treat Bluetooth exactly like
// LAN or Wi-Fi Direct and score it against them.
//
// Deliberately thin: it owns no GATT logic. Writing bytes and
// surfacing inbound text stay in BtService, which already handles
// chunking, the null terminator and reconnection; this adapter just
// exposes them under the common interface.
// ─────────────────────────────────────────────────────────────
import 'dart:async';

import 'link.dart';

/// Sends one already-framed line over a specific BLE connection.
/// Returns true when the radio accepted it.
typedef BleWriter = Future<bool> Function(String line);

class BleLink extends LnLink {
  BleLink({
    required String linkId,
    required String remoteName,
    required BleWriter writer,
    String remoteUserId = '',
    int rssi = 0,
  })  : _id = linkId,
        _remoteName = remoteName,
        _writer = writer,
        _remoteUserId = remoteUserId,
        _rssi = rssi;

  final String _id;
  final BleWriter _writer;
  final LinkStats _stats = LinkStats();
  final StreamController<String> _incoming = StreamController<String>.broadcast();

  String _remoteName;
  String _remoteUserId;
  int _rssi;
  bool _up = true;

  @override
  String get id => _id;

  @override
  LinkKind get kind => LinkKind.ble;

  @override
  String get remoteUserId => _remoteUserId;

  @override
  String get remoteName => _remoteName;

  @override
  bool get isUp => _up;

  @override
  int get signal => _rssi;

  @override
  LinkStats get stats => _stats;

  @override
  Stream<String> get incoming => _incoming.stream;

  @override
  Future<bool> send(String line) async {
    if (!_up) return false;
    try {
      return await _writer(line);
    } catch (_) {
      // The caller records the failure; swallowing here keeps a dead
      // connection from taking down the whole broadcast.
      return false;
    }
  }

  @override
  Future<void> close() async {
    _up = false;
    if (!_incoming.isClosed) await _incoming.close();
  }

  // ── Fed by BtService as the connection lives ──

  /// Push an inbound framed line up to the router.
  void deliver(String line) {
    if (_incoming.isClosed) return;
    _stats.recordIncoming(line.length);
    _incoming.add(line);
  }

  /// Latest RSSI reading, so link scoring reflects real signal.
  void updateRssi(int rssi) => _rssi = rssi;

  /// Learned from the peer's `hello` packet.
  void bindUser(String userId, String name) {
    if (userId.isNotEmpty) _remoteUserId = userId;
    if (name.isNotEmpty) _remoteName = name;
  }

  void markDown() => _up = false;
}
