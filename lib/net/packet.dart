// ─────────────────────────────────────────────────────────────
// LessNet — wire packet
//
// One line per packet, pipe-delimited header + base64 payload:
//
//   LN1|type|msgId|ttl|origin|dest|seq|payloadB64
//
// Every header field is restricted to [A-Za-z0-9_.*-] and the
// payload is base64, so '|' is never ambiguous and a packet can
// be framed with a single '\n'.
//
// The critical invariant, and the reason the old [MESH:] format
// looped: `msgId` is generated once at the origin and is NEVER
// rewritten by a relay. Deduplication keys on msgId alone, so the
// same message arriving over two different paths — with different
// hop counts — is still recognised as one message.
// ─────────────────────────────────────────────────────────────
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

/// Protocol magic + version. Bump on breaking changes.
const String kPacketMagic = 'LN1';

/// Broadcast destination (global chat, presence, SOS).
const String kBroadcastDest = '*';

/// Default hop limit. 6 covers a realistic crowd/building deployment
/// without letting a partitioned segment flood forever.
const int kDefaultTtl = 6;

/// Maximum bytes of a single encoded packet we will accept.
const int kMaxPacketBytes = 64 * 1024;

enum PacketType {
  /// Chat message (text). Payload = UTF-8 text.
  msg,

  /// Delivery acknowledgement. Payload = the acknowledged msgId.
  ack,

  /// Periodic identity/capability announcement. Payload = JSON.
  hello,

  /// Emergency broadcast. Payload = JSON with lat/lon/user/ts.
  sos,

  /// File header. Payload = JSON describing the transfer.
  fmeta,

  /// File chunk. Payload = raw chunk bytes, `seq` = chunk index.
  fchunk,

  /// Per-chunk / per-transfer acknowledgement. Payload = JSON.
  fack,

  /// Typing indicator, read receipts, name changes. Payload = JSON.
  meta,
}

PacketType? _typeFromCode(String code) {
  for (final t in PacketType.values) {
    if (t.name == code) return t;
  }
  return null;
}

final RegExp _headerField = RegExp(r'^[A-Za-z0-9_.*-]{0,64}$');

/// A parsed LessNet packet.
class LnPacket {
  final PacketType type;

  /// Stable across every hop. Dedup key.
  final String msgId;

  /// Remaining hops. Decremented by each relay, never increased.
  final int ttl;

  /// Stable user id of the original sender.
  final String origin;

  /// Stable user id of the intended recipient, or [kBroadcastDest].
  final String dest;

  /// Chunk index for [PacketType.fchunk]; 0 otherwise.
  final int seq;

  /// Decoded payload bytes.
  final Uint8List payload;

  const LnPacket({
    required this.type,
    required this.msgId,
    required this.ttl,
    required this.origin,
    required this.dest,
    required this.payload,
    this.seq = 0,
  });

  bool get isBroadcast => dest == kBroadcastDest;

  /// Payload interpreted as UTF-8 text.
  String get text => utf8.decode(payload, allowMalformed: true);

  /// Payload interpreted as a JSON object. Returns an empty map on failure.
  Map<String, dynamic> get json {
    try {
      final v = jsonDecode(text);
      return v is Map<String, dynamic> ? v : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  /// A copy with one hop consumed. Returns null when the packet has
  /// reached the end of its life, which is what stops relay loops.
  LnPacket? decremented() {
    if (ttl <= 1) return null;
    return LnPacket(
      type: type,
      msgId: msgId,
      ttl: ttl - 1,
      origin: origin,
      dest: dest,
      seq: seq,
      payload: payload,
    );
  }

  String encode() {
    final b = StringBuffer()
      ..write(kPacketMagic)
      ..write('|')
      ..write(type.name)
      ..write('|')
      ..write(msgId)
      ..write('|')
      ..write(ttl)
      ..write('|')
      ..write(origin)
      ..write('|')
      ..write(dest)
      ..write('|')
      ..write(seq)
      ..write('|')
      ..write(base64Encode(payload));
    return b.toString();
  }

  /// Parse a single encoded packet. Returns null if it is not a
  /// well-formed LN1 packet, so callers can fall back to the legacy
  /// plain-text handler during the migration window.
  static LnPacket? tryParse(String raw) {
    final line = raw.trim();
    if (line.length > kMaxPacketBytes) return null;
    if (!line.startsWith('$kPacketMagic|')) return null;

    final parts = line.split('|');
    if (parts.length != 8) return null;

    final type = _typeFromCode(parts[1]);
    if (type == null) return null;

    final msgId = parts[2];
    final origin = parts[4];
    final dest = parts[5];
    if (msgId.isEmpty || origin.isEmpty || dest.isEmpty) return null;
    if (!_headerField.hasMatch(msgId) ||
        !_headerField.hasMatch(origin) ||
        !_headerField.hasMatch(dest)) {
      return null;
    }

    final ttl = int.tryParse(parts[3]);
    final seq = int.tryParse(parts[6]);
    if (ttl == null || seq == null) return null;
    if (ttl < 0 || ttl > kDefaultTtl * 4) return null;
    if (seq < 0) return null;

    Uint8List payload;
    try {
      payload = base64Decode(parts[7]);
    } catch (_) {
      return null;
    }

    return LnPacket(
      type: type,
      msgId: msgId,
      ttl: ttl,
      origin: origin,
      dest: dest,
      seq: seq,
      payload: payload,
    );
  }

  /// Build an outgoing packet, minting a fresh id.
  factory LnPacket.outgoing({
    required PacketType type,
    required String origin,
    required String dest,
    required Uint8List payload,
    int ttl = kDefaultTtl,
    int seq = 0,
    String? msgId,
  }) {
    return LnPacket(
      type: type,
      msgId: msgId ?? newMsgId(),
      ttl: ttl,
      origin: origin,
      dest: dest,
      seq: seq,
      payload: payload,
    );
  }

  factory LnPacket.textOutgoing({
    required PacketType type,
    required String origin,
    required String dest,
    required String body,
    int ttl = kDefaultTtl,
    int seq = 0,
    String? msgId,
  }) {
    return LnPacket.outgoing(
      type: type,
      origin: origin,
      dest: dest,
      payload: Uint8List.fromList(utf8.encode(body)),
      ttl: ttl,
      seq: seq,
      msgId: msgId,
    );
  }

  @override
  String toString() =>
      'LnPacket(${type.name} id=$msgId ttl=$ttl $origin→$dest seq=$seq ${payload.length}B)';
}

const String _idAlphabet = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';
final Random _rng = Random.secure();

/// 16-char base62 id — ~95 bits of entropy, collision-free in
/// practice for any crowd size this app will see, and short enough
/// that the header stays cheap over BLE.
String newMsgId() {
  final b = StringBuffer();
  for (var i = 0; i < 16; i++) {
    b.write(_idAlphabet[_rng.nextInt(_idAlphabet.length)]);
  }
  return b.toString();
}

/// Stable, URL-safe short id for a device/user.
String newUserId() {
  final b = StringBuffer();
  for (var i = 0; i < 10; i++) {
    b.write(_idAlphabet[_rng.nextInt(_idAlphabet.length)]);
  }
  return b.toString();
}
