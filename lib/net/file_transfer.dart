// ─────────────────────────────────────────────────────────────
// LessNet — chunked file transfer
//
// The old path base64-encoded the whole file into ONE message
// ([FILE:type:name:size:crc]<base64>), wrote it in fixed 200-byte
// pieces regardless of the negotiated MTU, and had no per-chunk
// acknowledgement — so a 2 MB photo was ~13 600 confirmed writes
// and a single lost piece destroyed the entire transfer.
//
// This version:
//   * sizes chunks from the link's real capability (MTU on BLE,
//     tens of KB on Wi-Fi), so Wi-Fi is hundreds of times faster;
//   * numbers every chunk and lets the receiver ask for exactly the
//     ones it is missing, so a transfer resumes instead of restarting;
//   * verifies the whole file with CRC32 before handing it over.
// ─────────────────────────────────────────────────────────────
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'link.dart';
import 'packet.dart';

/// Overhead of the packet envelope plus base64 expansion, so a chunk
/// still fits the link's MTU after encoding.
const double _kBase64Expansion = 4 / 3;
const int _kHeaderOverhead = 96;

/// Hard ceiling regardless of link — keeps memory bounded.
const int kMaxChunkBytes = 32 * 1024;

/// Files above this are refused with a clear message rather than
/// silently attempted. Wi-Fi links raise it; BLE keeps it low.
int maxFileBytesFor(LinkKind kind) => switch (kind) {
      LinkKind.ble => 4 * 1024 * 1024,
      _ => 64 * 1024 * 1024,
    };

/// Payload size that makes best use of this link.
///
/// This targets one encoded frame per radio packet, which is where
/// the throughput win comes from. It is a *target*, not a hard
/// guarantee: below roughly a 185-byte MTU the envelope alone does
/// not fit, so the floor below wins and the link layer fragments the
/// encoded frame. Dropping under the floor is not worth it — the
/// per-chunk overhead would exceed the payload.
int chunkSizeFor(LinkKind kind, {int? negotiatedMtu}) {
  final raw = kind == LinkKind.ble
      ? ((negotiatedMtu ?? 247) - 3) // ATT header
      : kind.caps.maxPayload;
  final usable = ((raw - _kHeaderOverhead) / _kBase64Expansion).floor();
  return usable.clamp(64, kMaxChunkBytes);
}

enum TransferState { preparando, enviando, recibiendo, verificando, completado, fallido, cancelado }

class TransferProgress {
  final String transferId;
  final String fileName;
  final int totalBytes;
  final int doneBytes;
  final int totalChunks;
  final int doneChunks;
  final TransferState state;
  final bool incoming;
  final String? error;
  final String? localPath;

  const TransferProgress({
    required this.transferId,
    required this.fileName,
    required this.totalBytes,
    required this.doneBytes,
    required this.totalChunks,
    required this.doneChunks,
    required this.state,
    required this.incoming,
    this.error,
    this.localPath,
  });

  double get fraction => totalChunks == 0 ? 0 : (doneChunks / totalChunks).clamp(0.0, 1.0);
  bool get isFinished =>
      state == TransferState.completado ||
      state == TransferState.fallido ||
      state == TransferState.cancelado;
}

class _Outgoing {
  final String id;
  final String dest;
  final String fileName;
  final String msgType;
  final Uint8List bytes;
  final int chunkSize;
  final int chunkCount;
  final Set<int> acked = <int>{};
  int round = 0;
  bool cancelled = false;

  _Outgoing({
    required this.id,
    required this.dest,
    required this.fileName,
    required this.msgType,
    required this.bytes,
    required this.chunkSize,
  }) : chunkCount = (bytes.length / chunkSize).ceil();

  Uint8List chunk(int i) {
    final start = i * chunkSize;
    final end = math.min(start + chunkSize, bytes.length);
    return Uint8List.sublistView(bytes, start, end);
  }

  List<int> get missing =>
      List<int>.generate(chunkCount, (i) => i).where((i) => !acked.contains(i)).toList();
}

class _Incoming {
  final String id;
  final String from;
  final String fileName;
  final String msgType;
  final int totalBytes;
  final int chunkSize;
  final int chunkCount;
  final int crc;
  final Map<int, Uint8List> chunks = <int, Uint8List>{};
  DateTime lastActivity = DateTime.now();

  _Incoming({
    required this.id,
    required this.from,
    required this.fileName,
    required this.msgType,
    required this.totalBytes,
    required this.chunkSize,
    required this.chunkCount,
    required this.crc,
  });

  bool get complete => chunks.length >= chunkCount;

  List<int> get missing =>
      List<int>.generate(chunkCount, (i) => i).where((i) => !chunks.containsKey(i)).toList();

  Uint8List assemble() {
    final out = BytesBuilder(copy: false);
    for (var i = 0; i < chunkCount; i++) {
      out.add(chunks[i] ?? Uint8List(0));
    }
    return out.toBytes();
  }
}

typedef PacketSender = Future<bool> Function(LnPacket packet);
typedef FileSaver = Future<String> Function(String fileName, Uint8List bytes);

class FileTransferManager {
  FileTransferManager({
    required this.selfId,
    required PacketSender send,
    required FileSaver save,
    this.onLog,
  })  : _send = send,
        _save = save;

  String selfId;
  final PacketSender _send;
  final FileSaver _save;
  final void Function(String)? onLog;

  final Map<String, _Outgoing> _out = <String, _Outgoing>{};
  final Map<String, _Incoming> _in = <String, _Incoming>{};

  final StreamController<TransferProgress> _progress =
      StreamController<TransferProgress>.broadcast();

  Stream<TransferProgress> get onProgress => _progress.stream;

  Timer? _sweeper;

  void start() {
    _sweeper?.cancel();
    _sweeper = Timer.periodic(const Duration(seconds: 4), (_) => _sweep());
  }

  void stop() {
    _sweeper?.cancel();
    _sweeper = null;
  }

  // ───────────────────────── sending ─────────────────────────

  /// Begin sending [file] to [dest]. Returns the transfer id, or null
  /// when the file is refused (too large for the available link).
  Future<String?> sendFile({
    required File file,
    required String dest,
    required String msgType,
    required LinkKind overLink,
    int? negotiatedMtu,
    String? transferId,
  }) async {
    final bytes = await file.readAsBytes();
    final limit = maxFileBytesFor(overLink);
    if (bytes.length > limit) {
      _emit(TransferProgress(
        transferId: transferId ?? newMsgId(),
        fileName: _baseName(file.path),
        totalBytes: bytes.length,
        doneBytes: 0,
        totalChunks: 0,
        doneChunks: 0,
        state: TransferState.fallido,
        incoming: false,
        error: 'El archivo supera el máximo de '
            '${(limit / 1024 / 1024).toStringAsFixed(0)} MB por ${overLink.shortLabel}.',
      ));
      return null;
    }

    final id = transferId ?? newMsgId();
    final chunkSize = chunkSizeFor(overLink, negotiatedMtu: negotiatedMtu);
    final job = _Outgoing(
      id: id,
      dest: dest,
      fileName: _baseName(file.path),
      msgType: msgType,
      bytes: bytes,
      chunkSize: chunkSize,
    );
    _out[id] = job;

    onLog?.call(
      'Envío $id: ${job.fileName} ${bytes.length}B en ${job.chunkCount} trozos de $chunkSize B '
      'por ${overLink.shortLabel}',
    );

    await _send(LnPacket.textOutgoing(
      type: PacketType.fmeta,
      origin: selfId,
      dest: dest,
      body: jsonEncode(<String, dynamic>{
        't': id,
        'n': job.fileName,
        'k': msgType,
        's': bytes.length,
        'c': job.chunkCount,
        'z': chunkSize,
        'crc': crc32(bytes),
      }),
    ));

    unawaited(_pumpOutgoing(job));
    return id;
  }

  Future<void> _pumpOutgoing(_Outgoing job) async {
    final missing = job.missing;
    if (missing.isEmpty || job.cancelled) return;

    job.round++;
    for (final i in missing) {
      if (job.cancelled) return;
      final ok = await _send(LnPacket.outgoing(
        type: PacketType.fchunk,
        origin: selfId,
        dest: job.dest,
        payload: job.chunk(i),
        seq: i,
        // Chunks are point-to-point; a long TTL would flood the mesh
        // with megabytes of relay traffic.
        ttl: 3,
      ));
      if (!ok) break;
      _emitOutgoing(job);
    }
    _emitOutgoing(job);
  }

  // ──────────────────────── receiving ────────────────────────

  /// Feed every delivered packet here. Returns true when the packet
  /// belonged to a file transfer and was consumed.
  Future<bool> handlePacket(LnPacket p) async {
    switch (p.type) {
      case PacketType.fmeta:
        await _onMeta(p);
        return true;
      case PacketType.fchunk:
        await _onChunk(p);
        return true;
      case PacketType.fack:
        await _onAck(p);
        return true;
      default:
        return false;
    }
  }

  Future<void> _onMeta(LnPacket p) async {
    final m = p.json;
    final id = (m['t'] as String?) ?? '';
    if (id.isEmpty) return;

    final job = _Incoming(
      id: id,
      from: p.origin,
      fileName: (m['n'] as String?) ?? 'archivo',
      msgType: (m['k'] as String?) ?? 'file',
      totalBytes: (m['s'] as num?)?.toInt() ?? 0,
      chunkSize: (m['z'] as num?)?.toInt() ?? 512,
      chunkCount: (m['c'] as num?)?.toInt() ?? 0,
      crc: (m['crc'] as num?)?.toInt() ?? 0,
    );
    _in[id] = job;
    onLog?.call('Recepción $id: ${job.fileName} en ${job.chunkCount} trozos');
    _emitIncoming(job, TransferState.recibiendo);
  }

  Future<void> _onChunk(LnPacket p) async {
    // The transfer id is not in the chunk packet (it would cost bytes
    // on every chunk); chunks are matched by sender, which is safe
    // because a peer sends one file at a time.
    final job = _in.values
        .where((j) => j.from == p.origin && !j.complete)
        .fold<_Incoming?>(null, (best, j) => best ?? j);
    if (job == null) return;

    job.chunks[p.seq] = p.payload;
    job.lastActivity = DateTime.now();
    _emitIncoming(job, TransferState.recibiendo);

    if (job.complete) {
      await _finishIncoming(job);
    } else if (job.chunks.length % 16 == 0) {
      await _sendAck(job, done: false);
    }
  }

  Future<void> _finishIncoming(_Incoming job) async {
    _emitIncoming(job, TransferState.verificando);
    final bytes = job.assemble();

    if (job.totalBytes > 0 && bytes.length != job.totalBytes) {
      _emitIncoming(job, TransferState.fallido, error: 'Tamaño incorrecto');
      await _sendAck(job, done: false);
      return;
    }
    if (job.crc != 0 && crc32(bytes) != job.crc) {
      _emitIncoming(job, TransferState.fallido, error: 'Verificación CRC falló');
      // Ask for everything again rather than saving a corrupt file.
      job.chunks.clear();
      await _sendAck(job, done: false);
      return;
    }

    String path;
    try {
      path = await _save(job.fileName, bytes);
    } catch (e) {
      _emitIncoming(job, TransferState.fallido, error: 'No se pudo guardar: $e');
      return;
    }

    await _sendAck(job, done: true);
    _emitIncoming(job, TransferState.completado, localPath: path);
    _in.remove(job.id);
  }

  Future<void> _sendAck(_Incoming job, {required bool done}) async {
    await _send(LnPacket.textOutgoing(
      type: PacketType.fack,
      origin: selfId,
      dest: job.from,
      ttl: 3,
      body: jsonEncode(<String, dynamic>{
        't': job.id,
        'd': done,
        // Bounded so a very lossy transfer cannot produce a huge packet.
        'm': job.missing.take(256).toList(),
      }),
    ));
  }

  Future<void> _onAck(LnPacket p) async {
    final m = p.json;
    final id = (m['t'] as String?) ?? '';
    final job = _out[id];
    if (job == null) return;

    final done = (m['d'] as bool?) ?? false;
    if (done) {
      job.acked.addAll(List<int>.generate(job.chunkCount, (i) => i));
      _emitOutgoing(job, state: TransferState.completado);
      _out.remove(id);
      return;
    }

    final missing = ((m['m'] as List?) ?? const <dynamic>[])
        .map((e) => (e as num).toInt())
        .toSet();
    job.acked
      ..clear()
      ..addAll(List<int>.generate(job.chunkCount, (i) => i).where((i) => !missing.contains(i)));
    _emitOutgoing(job);

    if (missing.isNotEmpty && !job.cancelled) {
      // Resend only the gaps.
      unawaited(_pumpOutgoing(job));
    }
  }

  // ───────────────────────── plumbing ────────────────────────

  void cancel(String transferId) {
    final o = _out[transferId];
    if (o != null) {
      o.cancelled = true;
      _emitOutgoing(o, state: TransferState.cancelado);
      _out.remove(transferId);
    }
    final i = _in.remove(transferId);
    if (i != null) _emitIncoming(i, TransferState.cancelado);
  }

  void _sweep() {
    final now = DateTime.now();
    for (final job in _in.values.toList()) {
      if (now.difference(job.lastActivity) > const Duration(seconds: 20)) {
        // Nudge the sender with the current gap list.
        unawaited(_sendAck(job, done: false));
        job.lastActivity = now;
      }
    }
    for (final job in _out.values.toList()) {
      if (job.missing.isNotEmpty && !job.cancelled) {
        unawaited(_pumpOutgoing(job));
      }
    }
  }

  void _emitOutgoing(_Outgoing job, {TransferState? state}) {
    _emit(TransferProgress(
      transferId: job.id,
      fileName: job.fileName,
      totalBytes: job.bytes.length,
      doneBytes: math.min(job.acked.length * job.chunkSize, job.bytes.length),
      totalChunks: job.chunkCount,
      doneChunks: job.acked.length,
      state: state ?? TransferState.enviando,
      incoming: false,
    ));
  }

  void _emitIncoming(_Incoming job, TransferState state, {String? error, String? localPath}) {
    _emit(TransferProgress(
      transferId: job.id,
      fileName: job.fileName,
      totalBytes: job.totalBytes,
      doneBytes: math.min(job.chunks.length * job.chunkSize, job.totalBytes),
      totalChunks: job.chunkCount,
      doneChunks: job.chunks.length,
      state: state,
      incoming: true,
      error: error,
      localPath: localPath,
    ));
  }

  void _emit(TransferProgress p) {
    if (!_progress.isClosed) _progress.add(p);
  }

  void dispose() {
    stop();
    _progress.close();
    _out.clear();
    _in.clear();
  }
}

String _baseName(String path) {
  final i = path.lastIndexOf(Platform.pathSeparator);
  return i < 0 ? path : path.substring(i + 1);
}

// ─── CRC32 (IEEE 802.3), table-driven ───
final List<int> _crcTable = _buildCrcTable();

List<int> _buildCrcTable() {
  final t = List<int>.filled(256, 0);
  for (var i = 0; i < 256; i++) {
    var c = i;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1);
    }
    t[i] = c;
  }
  return t;
}

int crc32(List<int> data) {
  var crc = 0xFFFFFFFF;
  for (final b in data) {
    crc = _crcTable[(crc ^ b) & 0xFF] ^ (crc >> 8);
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}
