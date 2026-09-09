// ─────────────────────────────────────────────────────────────
// LessNet — the networking stack, assembled
//
// One object that owns identity, links, routing, the outbox and
// file transfer, and exposes the small surface the UI needs:
//
//   stack.sendText(dest, body)   → queued, routed, retried
//   stack.onChat                 → messages to display
//   stack.peers                  → who is reachable, and how far
//   stack.chooseFor(dest)        → which radio is carrying it
//
// The old code had this logic spread across BtService, LanService,
// WifiDirectService and the widgets themselves, which is why the
// same message could be sent N times over LAN and why a message
// sent with no link simply disappeared.
// ─────────────────────────────────────────────────────────────
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';

import '../core/identity.dart';
import '../design/tokens.dart';
import 'file_transfer.dart';
import 'link.dart';
import 'link_manager.dart';
import 'mesh_router.dart';
import 'outbox.dart';
import 'packet.dart';

/// A chat message as it reaches the UI, transport-agnostic.
class IncomingChat {
  final String msgId;
  final String fromUserId;
  final String fromName;
  final String text;
  final bool broadcast;
  final DateTime time;
  final LinkKind? via;

  const IncomingChat({
    required this.msgId,
    required this.fromUserId,
    required this.fromName,
    required this.text,
    required this.broadcast,
    required this.time,
    this.via,
  });
}

class LessNetStack {
  LessNetStack._();

  static final LessNetStack instance = LessNetStack._();

  late final LinkManager links = LinkManager(onLog: _log);
  late final MeshRouter router;
  late final Outbox outbox;
  late final FileTransferManager files;

  final LnIdentity identity = LnIdentity.instance;

  final StreamController<IncomingChat> _chat = StreamController<IncomingChat>.broadcast();
  final StreamController<String> _logs = StreamController<String>.broadcast();

  Stream<IncomingChat> get onChat => _chat.stream;
  Stream<String> get onLog => _logs.stream;

  /// Peers known to the router, enriched with names learned from hellos.
  final Map<String, LnPeer> _peerInfo = <String, LnPeer>{};

  Timer? _hello;
  bool _started = false;

  /// True once [start] has run, so callers can safely touch [router].
  bool get isReady => _started;
  void Function(String)? externalLogger;

  void _log(String m) {
    if (!_logs.isClosed) _logs.add(m);
    externalLogger?.call(m);
  }

  List<LnPeer> get peers {
    return router.peers.map((r) {
      final info = _peerInfo[r.userId];
      return LnPeer(
        userId: r.userId,
        name: info?.name ?? r.displayName,
        emoji: info?.emoji ?? '🙂',
        hops: r.hops,
      );
    }).toList();
  }

  LnQuality get quality => links.overallQuality;

  Set<LinkKind> get activeKinds => links.activeKinds;

  ActiveChoice? chooseFor(String? dest) => links.chooseFor(dest);

  /// Wire everything together. [db] provides the app's sqflite handle,
  /// [saveFile] persists a received file and returns its path.
  Future<void> start({
    required Future<Database> Function() db,
    required FileSaver saveFile,
  }) async {
    if (_started) return;
    _started = true;

    if (!identity.isLoaded) await identity.load();

    router = MeshRouter(
      selfId: identity.userId,
      links: () => links.liveLinks,
      onLog: _log,
    );
    links.attachRouter(router);

    outbox = Outbox(db);
    files = FileTransferManager(
      selfId: identity.userId,
      send: (pkt) => router.send(pkt),
      save: saveFile,
      onLog: _log,
    );

    // Every framed line from any link goes through the router first.
    links.onLine.listen((e) {
      router.handleIncoming(e.line, e.linkId);
    });

    router.onDeliver.listen(_onDeliver);

    outbox.start((line) async {
      final pkt = LnPacket.tryParse(line);
      if (pkt == null) return false;
      return router.send(pkt);
    });

    files.start();

    // Announce ourselves periodically so peers learn our name and so
    // routes stay fresh without any user action.
    _hello = Timer.periodic(const Duration(seconds: 25), (_) => announce());
    await announce();

    identity.addListener(_onIdentityChanged);
  }

  void _onIdentityChanged() {
    router.selfId = identity.userId;
    files.selfId = identity.userId;
    unawaited(announce());
  }

  Future<void> announce() async {
    if (!links.hasAnyLink) return;
    await router.sendHello(identity.toProfile());
  }

  // ───────────────────────── inbound ─────────────────────────

  Future<void> _onDeliver(LnPacket p) async {
    switch (p.type) {
      case PacketType.hello:
        final peer = LnPeer.fromProfile(p.json, hops: router.routeTo(p.origin)?.hops ?? 1);
        if (peer.userId.isNotEmpty) {
          _peerInfo[peer.userId] = peer;
          router.notePeerName(peer.userId, peer.name);
        }
        return;

      case PacketType.ack:
        await outbox.markDelivered(p.text);
        return;

      case PacketType.msg:
      case PacketType.sos:
        final info = _peerInfo[p.origin];
        _chat.add(IncomingChat(
          msgId: p.msgId,
          fromUserId: p.origin,
          fromName: info?.name ?? router.routeTo(p.origin)?.displayName ?? p.origin,
          text: p.text,
          broadcast: p.isBroadcast,
          time: DateTime.now(),
          via: links.chooseFor(p.origin)?.kind,
        ));
        // Unicast gets a real delivery receipt.
        if (!p.isBroadcast) await router.sendAck(p);
        return;

      case PacketType.fmeta:
      case PacketType.fchunk:
      case PacketType.fack:
        await files.handlePacket(p);
        return;

      case PacketType.meta:
        return;
    }
  }

  // ───────────────────────── outbound ────────────────────────

  /// Queue a chat message. Returns the packet id so the UI can track
  /// its delivery state. Never throws and never silently drops: with
  /// no link available it stays in the outbox until one appears.
  Future<String> sendText({required String dest, required String body}) async {
    final pkt = LnPacket.textOutgoing(
      type: PacketType.msg,
      origin: identity.userId,
      dest: dest,
      body: body,
    );
    await outbox.enqueue(pkt);
    return pkt.msgId;
  }

  /// Broadcast an SOS to the whole mesh.
  Future<String> sendSos({
    required double lat,
    required double lon,
  }) async {
    final pkt = LnPacket.textOutgoing(
      type: PacketType.sos,
      origin: identity.userId,
      dest: kBroadcastDest,
      body: jsonEncode(<String, dynamic>{
        'lat': lat,
        'lon': lon,
        'user': identity.displayName,
        'ts': DateTime.now().millisecondsSinceEpoch,
      }),
    );
    await outbox.enqueue(pkt);
    return pkt.msgId;
  }

  /// Send a file over whichever radio is currently best for [dest].
  Future<String?> sendFile({
    required File file,
    required String dest,
    required String msgType,
    int? negotiatedMtu,
  }) async {
    final choice = links.chooseFor(dest);
    if (choice == null) {
      _log('No hay enlace para enviar ${file.path}');
      return null;
    }
    return files.sendFile(
      file: file,
      dest: dest,
      msgType: msgType,
      overLink: choice.kind,
      negotiatedMtu: negotiatedMtu,
    );
  }

  Future<int> queuedCount() => outbox.pendingCount();

  Future<void> dispose() async {
    _hello?.cancel();
    identity.removeListener(_onIdentityChanged);
    files.dispose();
    outbox.dispose();
    router.dispose();
    links.dispose();
    await _chat.close();
    await _logs.close();
    _started = false;
  }
}

/// Bridges a raw byte-oriented transport (a BLE characteristic, a TCP
/// socket) to the line-framed [LnLink] the router expects.
///
/// Frames are newline-delimited; the encoder guarantees no payload
/// contains a newline because everything is base64.
class LineFramer {
  LineFramer({this.maxLineBytes = kMaxPacketBytes});

  final int maxLineBytes;
  final StringBuffer _buffer = StringBuffer();

  /// Feed raw bytes; returns any complete lines.
  List<String> addBytes(List<int> bytes) {
    return addString(utf8.decode(bytes, allowMalformed: true));
  }

  List<String> addString(String chunk) {
    final out = <String>[];
    for (final ch in chunk.split('')) {
      if (ch == '\n') {
        final line = _buffer.toString();
        _buffer.clear();
        if (line.trim().isNotEmpty) out.add(line);
      } else {
        if (_buffer.length >= maxLineBytes) {
          // Runaway frame — drop it rather than growing without bound.
          _buffer.clear();
          continue;
        }
        _buffer.write(ch);
      }
    }
    return out;
  }

  void reset() => _buffer.clear();
}

/// Encode a packet line for the wire, newline-terminated.
Uint8List frameLine(String line) =>
    Uint8List.fromList(utf8.encode('$line\n'));
