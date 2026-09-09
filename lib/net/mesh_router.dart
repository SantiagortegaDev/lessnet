// ─────────────────────────────────────────────────────────────
// LessNet — mesh router
//
// This replaces the old [MESH:hops:origin] handling, which had two
// defects that made the mesh unusable beyond two devices:
//
//   1. Relaying a [GLOBAL] payload re-wrapped it with a fresh
//      header, resetting the hop count to its maximum. The TTL
//      therefore never reached zero and messages circulated
//      forever in any cyclic topology.
//   2. Deduplication hashed the whole frame *including* the hop
//      count, so the same message arriving by a 2-hop and a 3-hop
//      path produced two different hashes and was delivered twice.
//
// Here, `msgId` is minted once at the origin and is immutable, TTL
// only ever decreases, dedup keys on msgId alone, and there is
// exactly one place in the code that relays a packet.
// ─────────────────────────────────────────────────────────────
import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'link.dart';
import 'packet.dart';

/// Bounded, time-expiring set of packet ids we have already handled.
class _SeenCache {
  final int maxEntries;
  final Duration ttl;
  final LinkedHashMap<String, DateTime> _entries = LinkedHashMap<String, DateTime>();

  _SeenCache({this.maxEntries = 4096, this.ttl = const Duration(minutes: 10)});

  /// Returns true if this id was already seen; otherwise records it.
  bool checkAndAdd(String id) {
    final now = DateTime.now();
    final existing = _entries[id];
    if (existing != null) {
      if (now.isBefore(existing)) return true;
      _entries.remove(id);
    }
    _entries[id] = now.add(ttl);
    if (_entries.length > maxEntries) {
      // LinkedHashMap preserves insertion order, so the first key is
      // the oldest. Trim in a small batch to avoid doing this per packet.
      final drop = _entries.length - maxEntries;
      final it = _entries.keys.take(drop).toList(growable: false);
      for (final k in it) {
        _entries.remove(k);
      }
    }
    return false;
  }

  bool contains(String id) {
    final e = _entries[id];
    return e != null && DateTime.now().isBefore(e);
  }

  void clear() => _entries.clear();

  int get length => _entries.length;
}

/// Result of handing a raw inbound line to the router.
enum RouterOutcome {
  /// Not an LN1 packet — the caller may try the legacy text handler.
  notAPacket,

  /// Recognised and consumed (delivered, relayed, or dropped).
  handled,

  /// Recognised but discarded as a duplicate.
  duplicate,
}

class MeshRouter {
  MeshRouter({
    required this.selfId,
    required Iterable<LnLink> Function() links,
    this.onLog,
  }) : _links = links;

  /// Our own stable user id. Packets originating from us are never
  /// re-processed, which kills the trivial echo loop.
  String selfId;

  final Iterable<LnLink> Function() _links;
  final void Function(String message)? onLog;

  final _SeenCache _seen = _SeenCache(maxEntries: 4096, ttl: const Duration(minutes: 10));
  final Map<String, PeerRoute> _routes = <String, PeerRoute>{};

  final StreamController<LnPacket> _deliver = StreamController<LnPacket>.broadcast();
  final StreamController<void> _routesChanged = StreamController<void>.broadcast();

  /// Packets addressed to us (or broadcast) that the app should act on.
  Stream<LnPacket> get onDeliver => _deliver.stream;

  /// Fires whenever the routing table gains, loses or updates a peer.
  Stream<void> get onRoutesChanged => _routesChanged.stream;

  /// Peers we currently believe are reachable.
  List<PeerRoute> get peers {
    final list = _routes.values.where((r) => !r.isStale).toList();
    list.sort((a, b) {
      final h = a.hops.compareTo(b.hops);
      return h != 0 ? h : a.displayName.compareTo(b.displayName);
    });
    return list;
  }

  PeerRoute? routeTo(String userId) {
    final r = _routes[userId];
    if (r == null || r.isStale) return null;
    return r;
  }

  int get seenCount => _seen.length;

  void _log(String m) => onLog?.call(m);

  // ───────────────────────── inbound ─────────────────────────

  /// Feed one framed line received on [fromLinkId].
  RouterOutcome handleIncoming(String raw, String fromLinkId) {
    final pkt = LnPacket.tryParse(raw);
    if (pkt == null) return RouterOutcome.notAPacket;

    // Our own packet came back to us over another path.
    if (pkt.origin == selfId) return RouterOutcome.duplicate;

    // THE dedup check. Keyed on msgId only — never on hop count,
    // never on payload — so the same message from two paths is one.
    if (_seen.checkAndAdd(pkt.msgId)) {
      return RouterOutcome.duplicate;
    }

    _learnRoute(pkt, fromLinkId);

    final forUs = pkt.dest == selfId;
    final broadcast = pkt.isBroadcast;

    if (forUs || broadcast) {
      _deliver.add(pkt);
    }

    // Relay unless this packet terminates here. A unicast addressed
    // to us is terminal; a broadcast is delivered *and* forwarded.
    if (!forUs) {
      _relay(pkt, fromLinkId);
    }

    return RouterOutcome.handled;
  }

  void _learnRoute(LnPacket pkt, String fromLinkId) {
    // TTL starts at kDefaultTtl and drops by one per relay, so the
    // remaining TTL tells us how far the packet travelled.
    final hops = (kDefaultTtl - pkt.ttl + 1).clamp(1, kDefaultTtl);
    final existing = _routes[pkt.origin];

    if (existing == null) {
      _routes[pkt.origin] = PeerRoute(
        userId: pkt.origin,
        displayName: pkt.origin,
        linkId: fromLinkId,
        hops: hops,
        lastSeen: DateTime.now(),
      );
      _log('Ruta nueva: ${pkt.origin} vía $fromLinkId ($hops saltos)');
      _routesChanged.add(null);
      return;
    }

    // Prefer a shorter path; otherwise just refresh liveness.
    final improved = hops < existing.hops || existing.isStale;
    existing.lastSeen = DateTime.now();
    if (improved) {
      existing.hops = hops;
      existing.linkId = fromLinkId;
      _log('Ruta mejorada: ${pkt.origin} vía $fromLinkId ($hops saltos)');
      _routesChanged.add(null);
    }
  }

  /// Record a peer's friendly name, learned from a `hello` packet.
  void notePeerName(String userId, String name) {
    final r = _routes[userId];
    if (r != null && name.isNotEmpty && r.displayName != name) {
      r.displayName = name;
      _routesChanged.add(null);
    }
  }

  // ───────────────────────── outbound ────────────────────────

  /// Send a packet we originated. Returns true if at least one link
  /// accepted it.
  Future<bool> send(LnPacket pkt) async {
    // Remember our own ids so an echo cannot come back at us.
    _seen.checkAndAdd(pkt.msgId);
    return _dispatch(pkt, excludeLinkId: null);
  }

  /// The one and only relay point.
  Future<bool> _relay(LnPacket pkt, String fromLinkId) async {
    final next = pkt.decremented();
    if (next == null) {
      _log('TTL agotado, no se retransmite ${pkt.msgId}');
      return false;
    }
    return _dispatch(next, excludeLinkId: fromLinkId);
  }

  Future<bool> _dispatch(LnPacket pkt, {required String? excludeLinkId}) async {
    final all = _links().where((l) => l.isUp && l.id != excludeLinkId).toList();
    if (all.isEmpty) return false;

    final line = pkt.encode();

    // Unicast with a known route: forward on the single best link
    // instead of flooding the whole mesh.
    if (!pkt.isBroadcast) {
      final route = routeTo(pkt.dest);
      if (route != null) {
        final direct = all.where((l) => l.id == route.linkId).toList();
        if (direct.isNotEmpty) {
          final ok = await _sendOn(direct.first, line);
          if (ok) return true;
          // Route went bad — drop it and fall through to flooding.
          _routes.remove(pkt.dest);
          _routesChanged.add(null);
        }
      }
      // Also try any link whose peer *is* the destination.
      final peerLinks = all.where((l) => l.remoteUserId == pkt.dest).toList();
      for (final l in peerLinks) {
        if (await _sendOn(l, line)) return true;
      }
    }

    // Broadcast, or unicast with no known route: flood.
    var any = false;
    await Future.wait(all.map((l) async {
      if (await _sendOn(l, line)) any = true;
    }));
    return any;
  }

  Future<bool> _sendOn(LnLink link, String line) async {
    try {
      final ok = await link.send(line);
      if (ok) {
        link.stats.recordSuccess(bytes: line.length);
      } else {
        link.stats.recordFailure();
      }
      return ok;
    } catch (e) {
      link.stats.recordFailure();
      _log('Error enviando por ${link.id}: $e');
      return false;
    }
  }

  // ───────────────────────── helpers ─────────────────────────

  /// Acknowledge a unicast message back to its sender.
  Future<void> sendAck(LnPacket original) async {
    if (original.isBroadcast) return;
    if (original.origin == selfId) return;
    await send(LnPacket.textOutgoing(
      type: PacketType.ack,
      origin: selfId,
      dest: original.origin,
      body: original.msgId,
    ));
  }

  /// Announce who we are to the whole mesh.
  Future<void> sendHello(Map<String, dynamic> profile) async {
    await send(LnPacket.outgoing(
      type: PacketType.hello,
      origin: selfId,
      dest: kBroadcastDest,
      payload: Uint8List.fromList(utf8.encode(jsonEncode(profile))),
      ttl: 3, // presence does not need to cross the whole mesh
    ));
  }

  void pruneRoutes() {
    final before = _routes.length;
    _routes.removeWhere((_, r) => r.isStale);
    if (_routes.length != before) _routesChanged.add(null);
  }

  void dispose() {
    _deliver.close();
    _routesChanged.close();
    _seen.clear();
    _routes.clear();
  }
}
