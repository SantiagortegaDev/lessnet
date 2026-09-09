// ─────────────────────────────────────────────────────────────
// LessNet — persistent outbox (store and forward)
//
// Previously, sending with no peer connected hit `if (!isConnected)
// return;` and the message vanished with no trace and no warning.
// For an app whose whole purpose is communicating when the network
// is gone, that was the wrong behaviour.
//
// Now every outgoing packet is persisted first, then pumped. The
// stored form is the *encoded packet*, so a retry re-sends the byte
// -identical frame with the same msgId — which the receiving mesh
// router silently deduplicates. Retrying is therefore always safe.
// ─────────────────────────────────────────────────────────────
import 'dart:async';

import 'package:sqflite/sqflite.dart';

import '../design/tokens.dart';
import 'packet.dart';

class OutboxEntry {
  final String msgId;
  final String dest;
  final String line;
  final int attempts;
  final DateTime createdAt;
  final DateTime nextAttemptAt;
  final LnMsgStatus status;

  const OutboxEntry({
    required this.msgId,
    required this.dest,
    required this.line,
    required this.attempts,
    required this.createdAt,
    required this.nextAttemptAt,
    required this.status,
  });

  static OutboxEntry fromRow(Map<String, Object?> r) => OutboxEntry(
        msgId: r['msgId'] as String,
        dest: r['dest'] as String,
        line: r['line'] as String,
        attempts: (r['attempts'] as int?) ?? 0,
        createdAt: DateTime.fromMillisecondsSinceEpoch((r['createdAt'] as int?) ?? 0),
        nextAttemptAt: DateTime.fromMillisecondsSinceEpoch((r['nextAttemptAt'] as int?) ?? 0),
        status: LnMsgStatusX.fromName(r['status'] as String?),
      );
}

/// Backoff schedule. Deliberately long-tailed: in a disaster the peer
/// may be out of range for minutes, and we would rather keep the
/// message than burn the battery retrying every second.
const List<int> _kBackoffSeconds = <int>[2, 5, 15, 45, 120, 300, 600];
const int kMaxAttempts = 12;

class Outbox {
  Outbox(this._db);

  final Future<Database> Function() _db;

  Timer? _pump;
  bool _pumping = false;
  Future<bool> Function(String line)? _sender;

  final StreamController<String> _statusChanged = StreamController<String>.broadcast();

  /// Emits the msgId whose delivery status changed.
  Stream<String> get onStatusChanged => _statusChanged.stream;

  static Future<void> createTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS outbox (
        msgId TEXT PRIMARY KEY,
        dest TEXT NOT NULL,
        line TEXT NOT NULL,
        attempts INTEGER NOT NULL DEFAULT 0,
        createdAt INTEGER NOT NULL,
        nextAttemptAt INTEGER NOT NULL,
        status TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_outbox_next ON outbox(status, nextAttemptAt)',
    );
  }

  /// Persist a packet before any radio is touched.
  Future<void> enqueue(LnPacket packet) async {
    final db = await _db();
    final now = DateTime.now();
    await db.insert(
      'outbox',
      <String, Object?>{
        'msgId': packet.msgId,
        'dest': packet.dest,
        'line': packet.encode(),
        'attempts': 0,
        'createdAt': now.millisecondsSinceEpoch,
        'nextAttemptAt': now.millisecondsSinceEpoch,
        'status': LnMsgStatus.pendiente.name,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _statusChanged.add(packet.msgId);
    unawaited(pumpNow());
  }

  /// Called when an `ack` for [msgId] arrives.
  Future<void> markDelivered(String msgId) async {
    final db = await _db();
    final n = await db.update(
      'outbox',
      <String, Object?>{'status': LnMsgStatus.entregado.name},
      where: 'msgId = ?',
      whereArgs: <Object?>[msgId],
    );
    if (n > 0) _statusChanged.add(msgId);
    // Delivered entries no longer need retrying.
    await db.delete('outbox', where: 'msgId = ? AND status = ?', whereArgs: <Object?>[
      msgId,
      LnMsgStatus.entregado.name,
    ]);
  }

  Future<LnMsgStatus?> statusOf(String msgId) async {
    final db = await _db();
    final rows = await db.query('outbox',
        columns: <String>['status'], where: 'msgId = ?', whereArgs: <Object?>[msgId], limit: 1);
    if (rows.isEmpty) return null;
    return LnMsgStatusX.fromName(rows.first['status'] as String?);
  }

  Future<List<OutboxEntry>> pending() async {
    final db = await _db();
    final rows = await db.query(
      'outbox',
      where: 'status IN (?, ?, ?)',
      whereArgs: <Object?>[
        LnMsgStatus.pendiente.name,
        LnMsgStatus.enviando.name,
        LnMsgStatus.fallido.name,
      ],
      orderBy: 'createdAt ASC',
    );
    return rows.map(OutboxEntry.fromRow).toList();
  }

  Future<int> pendingCount() async {
    final db = await _db();
    final r = await db.rawQuery(
      'SELECT COUNT(*) c FROM outbox WHERE status IN (?, ?)',
      <Object?>[LnMsgStatus.pendiente.name, LnMsgStatus.fallido.name],
    );
    return (r.first['c'] as int?) ?? 0;
  }

  /// Wire the pump to a transport. [sender] returns true when at
  /// least one link accepted the frame.
  void start(Future<bool> Function(String line) sender) {
    _sender = sender;
    _pump?.cancel();
    _pump = Timer.periodic(const Duration(seconds: 5), (_) => pumpNow());
    unawaited(pumpNow());
  }

  void stop() {
    _pump?.cancel();
    _pump = null;
  }

  /// Try every entry whose backoff has elapsed.
  Future<void> pumpNow() async {
    final sender = _sender;
    if (sender == null || _pumping) return;
    _pumping = true;
    try {
      final db = await _db();
      final now = DateTime.now().millisecondsSinceEpoch;
      final rows = await db.query(
        'outbox',
        where: 'status IN (?, ?) AND nextAttemptAt <= ?',
        whereArgs: <Object?>[LnMsgStatus.pendiente.name, LnMsgStatus.fallido.name, now],
        orderBy: 'createdAt ASC',
        limit: 25,
      );

      for (final row in rows) {
        final e = OutboxEntry.fromRow(row);
        final ok = await sender(e.line);
        final attempts = e.attempts + 1;

        if (ok) {
          // Sent onto the mesh. For a broadcast that is as far as
          // certainty goes; a unicast upgrades to `entregado` when
          // its ack comes back.
          final isBroadcast = e.dest == kBroadcastDest;
          await db.update(
            'outbox',
            <String, Object?>{'status': LnMsgStatus.enviado.name, 'attempts': attempts},
            where: 'msgId = ?',
            whereArgs: <Object?>[e.msgId],
          );
          if (isBroadcast) {
            await db.delete('outbox', where: 'msgId = ?', whereArgs: <Object?>[e.msgId]);
          }
          _statusChanged.add(e.msgId);
          continue;
        }

        if (attempts >= kMaxAttempts) {
          await db.update(
            'outbox',
            <String, Object?>{'status': LnMsgStatus.fallido.name, 'attempts': attempts},
            where: 'msgId = ?',
            whereArgs: <Object?>[e.msgId],
          );
          _statusChanged.add(e.msgId);
          continue;
        }

        final delay = _kBackoffSeconds[
            (attempts - 1).clamp(0, _kBackoffSeconds.length - 1)];
        await db.update(
          'outbox',
          <String, Object?>{
            'status': LnMsgStatus.pendiente.name,
            'attempts': attempts,
            'nextAttemptAt':
                DateTime.now().add(Duration(seconds: delay)).millisecondsSinceEpoch,
          },
          where: 'msgId = ?',
          whereArgs: <Object?>[e.msgId],
        );
        _statusChanged.add(e.msgId);
      }
    } finally {
      _pumping = false;
    }
  }

  /// Drop everything for a conversation (used by "borrar chat").
  Future<void> clearFor(String dest) async {
    final db = await _db();
    await db.delete('outbox', where: 'dest = ?', whereArgs: <Object?>[dest]);
  }

  Future<void> clearAll() async {
    final db = await _db();
    await db.delete('outbox');
  }

  void dispose() {
    stop();
    _statusChanged.close();
  }
}
