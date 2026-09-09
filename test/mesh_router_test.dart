import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lessnet/net/link.dart';
import 'package:lessnet/net/mesh_router.dart';
import 'package:lessnet/net/packet.dart';

/// In-memory link used to wire fake devices together in tests.
class FakeLink extends LnLink {
  FakeLink(this._id, this._remoteUserId, {this.kind = LinkKind.ble});

  final String _id;
  final String _remoteUserId;

  @override
  final LinkKind kind;

  final StreamController<String> _in = StreamController<String>.broadcast();
  final LinkStats _stats = LinkStats();

  /// Every line handed to send(), in order.
  final List<String> outbox = <String>[];

  /// Set by the test harness to deliver into the peer's router.
  void Function(String line)? peer;

  bool up = true;
  int rssi = -50;

  @override
  String get id => _id;
  @override
  String get remoteUserId => _remoteUserId;
  @override
  String get remoteName => _remoteUserId;
  @override
  bool get isUp => up;
  @override
  int get signal => rssi;
  @override
  LinkStats get stats => _stats;
  @override
  Stream<String> get incoming => _in.stream;

  @override
  Future<bool> send(String line) async {
    outbox.add(line);
    peer?.call(line);
    return true;
  }

  @override
  Future<void> close() async {
    up = false;
    await _in.close();
  }
}

/// A fake device: one router plus the links hanging off it.
class Node {
  Node(this.id) {
    router = MeshRouter(selfId: id, links: () => links);
    router.onDeliver.listen(delivered.add);
  }

  final String id;
  final List<FakeLink> links = <FakeLink>[];
  late final MeshRouter router;
  final List<LnPacket> delivered = <LnPacket>[];

  void receive(String line, String viaLinkId) => router.handleIncoming(line, viaLinkId);
}

/// Connect two nodes with a bidirectional pair of links.
void connect(Node a, Node b) {
  final la = FakeLink('${a.id}->${b.id}', b.id);
  final lb = FakeLink('${b.id}->${a.id}', a.id);
  la.peer = (line) => b.receive(line, lb.id);
  lb.peer = (line) => a.receive(line, la.id);
  a.links.add(la);
  b.links.add(lb);
}

void main() {
  group('LnPacket', () {
    test('round-trips through encode/parse', () {
      final p = LnPacket.textOutgoing(
        type: PacketType.msg,
        origin: 'alice',
        dest: 'bob',
        body: 'hola | mundo\nsegunda línea',
      );
      final parsed = LnPacket.tryParse(p.encode());
      expect(parsed, isNotNull);
      expect(parsed!.type, PacketType.msg);
      expect(parsed.origin, 'alice');
      expect(parsed.dest, 'bob');
      expect(parsed.msgId, p.msgId);
      expect(parsed.text, 'hola | mundo\nsegunda línea');
    });

    test('rejects malformed input instead of throwing', () {
      expect(LnPacket.tryParse(''), isNull);
      expect(LnPacket.tryParse('hola mundo'), isNull);
      expect(LnPacket.tryParse('LN1|msg|abc'), isNull);
      expect(LnPacket.tryParse('LN1|nope|a|6|x|y|0|aGk='), isNull);
      expect(LnPacket.tryParse('LN1|msg|a|no|x|y|0|aGk='), isNull);
      expect(LnPacket.tryParse('LN1|msg|a|6|x|y|0|!!!not base64!!!'), isNull);
    });

    test('msgId is stable across hops and ttl only decreases', () {
      var p = LnPacket.textOutgoing(
        type: PacketType.msg,
        origin: 'a',
        dest: kBroadcastDest,
        body: 'x',
      );
      final id = p.msgId;
      final seen = <int>[p.ttl];
      while (true) {
        final next = p.decremented();
        if (next == null) break;
        p = next;
        seen.add(p.ttl);
        expect(p.msgId, id, reason: 'msgId must never be rewritten by a relay');
      }
      // Strictly decreasing, and it terminates.
      for (var i = 1; i < seen.length; i++) {
        expect(seen[i], lessThan(seen[i - 1]));
      }
      expect(seen.last, 1);
    });
  });

  group('MeshRouter', () {
    test('delivers a broadcast to a direct neighbour exactly once', () async {
      final a = Node('a');
      final b = Node('b');
      connect(a, b);

      await a.router.send(LnPacket.textOutgoing(
        type: PacketType.msg,
        origin: 'a',
        dest: kBroadcastDest,
        body: 'hola',
      ));

      expect(b.delivered.length, 1);
      expect(b.delivered.single.text, 'hola');
      expect(a.delivered, isEmpty, reason: 'sender must not deliver to itself');
    });

    test('relays a broadcast across three hops, once per node', () async {
      final a = Node('a');
      final b = Node('b');
      final c = Node('c');
      final d = Node('d');
      connect(a, b);
      connect(b, c);
      connect(c, d);

      await a.router.send(LnPacket.textOutgoing(
        type: PacketType.msg,
        origin: 'a',
        dest: kBroadcastDest,
        body: 'multi-hop',
      ));

      for (final n in [b, c, d]) {
        expect(n.delivered.length, 1, reason: '${n.id} should receive it once');
        expect(n.delivered.single.text, 'multi-hop');
      }
    });

    test('a cyclic topology does not loop or duplicate', () async {
      // A—B, B—C, C—A. Under the old protocol this circulated forever
      // because relaying reset the hop count.
      final a = Node('a');
      final b = Node('b');
      final c = Node('c');
      connect(a, b);
      connect(b, c);
      connect(c, a);

      await a.router.send(LnPacket.textOutgoing(
        type: PacketType.msg,
        origin: 'a',
        dest: kBroadcastDest,
        body: 'ciclo',
      ));

      expect(b.delivered.length, 1);
      expect(c.delivered.length, 1);
      expect(a.delivered, isEmpty);

      // Bounded total traffic: without dedup + monotonic TTL this
      // number grows without limit.
      final totalSent = [a, b, c]
          .expand((n) => n.links)
          .fold<int>(0, (sum, l) => sum + l.outbox.length);
      expect(totalSent, lessThan(12), reason: 'traffic must stay bounded');
    });

    test('the same message arriving by two paths is delivered once', () async {
      // Diamond: A—B, A—C, B—D, C—D. D hears it twice, once per branch.
      final a = Node('a');
      final b = Node('b');
      final c = Node('c');
      final d = Node('d');
      connect(a, b);
      connect(a, c);
      connect(b, d);
      connect(c, d);

      await a.router.send(LnPacket.textOutgoing(
        type: PacketType.msg,
        origin: 'a',
        dest: kBroadcastDest,
        body: 'diamante',
      ));

      expect(d.delivered.length, 1,
          reason: 'dedup keys on msgId, so both branches collapse to one');
    });

    test('unicast is delivered only to its destination and is not relayed on', () async {
      final a = Node('a');
      final b = Node('b');
      final c = Node('c');
      connect(a, b);
      connect(b, c);

      await a.router.send(LnPacket.textOutgoing(
        type: PacketType.msg,
        origin: 'a',
        dest: 'b',
        body: 'privado',
      ));

      expect(b.delivered.length, 1);
      expect(c.delivered, isEmpty, reason: 'a unicast terminates at its destination');
    });

    test('unicast reaches a two-hop destination', () async {
      final a = Node('a');
      final b = Node('b');
      final c = Node('c');
      connect(a, b);
      connect(b, c);

      await a.router.send(LnPacket.textOutgoing(
        type: PacketType.msg,
        origin: 'a',
        dest: 'c',
        body: 'lejos',
      ));

      expect(c.delivered.length, 1);
      expect(b.delivered, isEmpty, reason: 'b forwards but does not consume it');
    });

    test('learns routes and hop counts from received traffic', () async {
      final a = Node('a');
      final b = Node('b');
      final c = Node('c');
      connect(a, b);
      connect(b, c);

      await a.router.send(LnPacket.textOutgoing(
        type: PacketType.msg,
        origin: 'a',
        dest: kBroadcastDest,
        body: 'presencia',
      ));

      expect(b.router.routeTo('a')?.hops, 1);
      expect(c.router.routeTo('a')?.hops, 2);
      expect(c.router.routeTo('a')?.isDirect, isFalse);
    });

    test('a packet a node originated is ignored if it echoes back', () {
      final a = Node('a');
      final line = LnPacket.textOutgoing(
        type: PacketType.msg,
        origin: 'a',
        dest: kBroadcastDest,
        body: 'eco',
      ).encode();

      expect(a.router.handleIncoming(line, 'whatever'), RouterOutcome.duplicate);
      expect(a.delivered, isEmpty);
    });

    test('non-LN1 text is reported so legacy handling can take over', () {
      final a = Node('a');
      expect(a.router.handleIncoming('[GLOBAL]mensaje viejo', 'l1'),
          RouterOutcome.notAPacket);
    });

    test('a duplicate msgId is rejected on the second sighting', () async {
      final a = Node('a');
      final line = LnPacket.textOutgoing(
        type: PacketType.msg,
        origin: 'z',
        dest: kBroadcastDest,
        body: 'x',
      ).encode();

      expect(a.router.handleIncoming(line, 'l1'), RouterOutcome.handled);
      expect(a.router.handleIncoming(line, 'l2'), RouterOutcome.duplicate);
      await Future<void>.delayed(Duration.zero); // let the broadcast stream flush
      expect(a.delivered.length, 1);
    });
  });

  group('scoreLink', () {
    test('prefers Wi-Fi over BLE when both are healthy', () {
      final ble = FakeLink('ble', 'p', kind: LinkKind.ble)..rssi = -50;
      final lan = FakeLink('lan', 'p', kind: LinkKind.lan)..rssi = 90;
      expect(scoreLink(lan), greaterThan(scoreLink(ble)));
    });

    test('prefers a solid BLE link over a failing Wi-Fi link', () {
      final ble = FakeLink('ble', 'p', kind: LinkKind.ble)..rssi = -50;
      final lan = FakeLink('lan', 'p', kind: LinkKind.lan)..rssi = 5;
      lan.stats.recordFailure();
      expect(scoreLink(ble), greaterThan(scoreLink(lan)));
    });

    test('penalises extra hops', () {
      final l = FakeLink('lan', 'p', kind: LinkKind.lan)..rssi = 90;
      expect(scoreLink(l, hops: 1), greaterThan(scoreLink(l, hops: 3)));
    });

    test('gives the incumbent hysteresis so the radio does not flap', () {
      final l = FakeLink('lan', 'p', kind: LinkKind.lan)..rssi = 90;
      expect(scoreLink(l, incumbent: true), greaterThan(scoreLink(l)));
    });

    test('a down link is never selectable', () {
      final l = FakeLink('lan', 'p', kind: LinkKind.lan)..up = false;
      expect(scoreLink(l), double.negativeInfinity);
    });
  });
}
