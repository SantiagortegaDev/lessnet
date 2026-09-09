import 'package:flutter_test/flutter_test.dart';
import 'package:lessnet/net/file_transfer.dart';
import 'package:lessnet/net/link.dart';
import 'package:lessnet/pairing/pair_code.dart';

void main() {
  group('PairCode', () {
    test('generates codes only from the unambiguous alphabet', () {
      for (var i = 0; i < 200; i++) {
        final c = PairCode.random();
        expect(c.code.length, kCodeLength);
        for (final ch in c.code.split('')) {
          expect(kCodeAlphabet.contains(ch), isTrue, reason: '$ch is ambiguous');
        }
        // The characters people confuse must never appear.
        expect(c.code, isNot(matches(RegExp('[01OILU]'))));
      }
    });

    test('accepts the separators people actually type', () {
      final c = PairCode.random();
      final spaced = '${c.code.substring(0, 3)} ${c.code.substring(3)}';
      final dashed = c.pretty;
      expect(PairCode.tryParse(spaced), c);
      expect(PairCode.tryParse(dashed), c);
      expect(PairCode.tryParse(c.code.toLowerCase()), c);
    });

    test('rejects malformed codes instead of silently repairing them', () {
      expect(PairCode.tryParse(''), isNull);
      expect(PairCode.tryParse('ABC'), isNull, reason: 'too short');
      expect(PairCode.tryParse('ABCDEFGH'), isNull, reason: 'too long');
      expect(PairCode.tryParse('ABC0EF'), isNull, reason: '0 is not in the alphabet');
      expect(PairCode.tryParse('ABCIEF'), isNull, reason: 'I is not in the alphabet');
    });

    test('derives every transport parameter deterministically', () {
      final a = PairCode.tryParse('K7M2QX')!;
      final b = PairCode.tryParse('k7m-2qx')!;

      expect(a.bleTagHex, b.bleTagHex);
      expect(a.lanServiceName, b.lanServiceName);
      expect(a.hotspotSsid, b.hotspotSsid);
      expect(a.hotspotPassword, b.hotspotPassword);
      expect(a.lanPort, b.lanPort);

      expect(a.hotspotSsid, 'LessNet-K7M2QX');
      expect(a.bleTag.length, 2);
      expect(a.lanPort, inInclusiveRange(20000, 40000));
      expect(a.hotspotPassword.length, 12);
    });

    test('different codes derive different parameters', () {
      final a = PairCode.tryParse('K7M2QX')!;
      final c = PairCode.tryParse('B9N4TZ')!;
      expect(a.bleTagHex, isNot(c.bleTagHex));
      expect(a.hotspotPassword, isNot(c.hotspotPassword));
      expect(a.lanServiceName, isNot(c.lanServiceName));
    });
  });

  group('PairInvite', () {
    test('round-trips through the QR payload', () {
      final invite = PairInvite(
        code: PairCode.tryParse('K7M2QX')!,
        userId: 'abc123XYZ0',
        name: 'María José',
        emoji: '🦊',
      );
      final parsed = PairInvite.tryParse(invite.toUri());
      expect(parsed, isNotNull);
      expect(parsed!.code, invite.code);
      expect(parsed.userId, 'abc123XYZ0');
      expect(parsed.name, 'María José');
      expect(parsed.emoji, '🦊');
    });

    test('rejects foreign QR codes', () {
      expect(PairInvite.tryParse('https://example.com'), isNull);
      expect(PairInvite.tryParse('lessnet://other?c=K7M2QX&id=x'), isNull);
      expect(PairInvite.tryParse('lessnet://join?id=x'), isNull, reason: 'no code');
      expect(PairInvite.tryParse('lessnet://join?c=K7M2QX'), isNull, reason: 'no id');
      expect(PairInvite.tryParse('random text'), isNull);
    });
  });

  group('file transfer sizing', () {
    test('scales the chunk to the link, not a fixed 200 bytes', () {
      final ble = chunkSizeFor(LinkKind.ble, negotiatedMtu: 247);
      final bleBig = chunkSizeFor(LinkKind.ble, negotiatedMtu: 517);
      final lan = chunkSizeFor(LinkKind.lan);

      // A larger negotiated MTU must actually be used.
      expect(bleBig, greaterThan(ble));
      // Wi-Fi carries far more per packet than BLE.
      expect(lan, greaterThan(bleBig * 10));
      expect(lan, lessThanOrEqualTo(kMaxChunkBytes));
    });

    test('fills one radio packet at realistic Android MTUs', () {
      // Android negotiates 247+ in practice; at those sizes the whole
      // encoded frame must fit in a single write.
      for (final mtu in <int>[247, 320, 517]) {
        final size = chunkSizeFor(LinkKind.ble, negotiatedMtu: mtu);
        expect((size * 4 / 3) + 96, lessThanOrEqualTo(mtu.toDouble()),
            reason: 'encoded frame must fit MTU \$mtu');
      }
    });

    test('stays positive and bounded even at the BLE minimum MTU', () {
      // Below ~185 bytes the envelope alone exceeds the MTU, so the
      // floor applies and the link layer fragments. It must still
      // return a usable, bounded value rather than zero or negative.
      for (final mtu in <int>[23, 64, 128]) {
        final size = chunkSizeFor(LinkKind.ble, negotiatedMtu: mtu);
        expect(size, greaterThan(0));
        expect(size, lessThanOrEqualTo(kMaxChunkBytes));
      }
    });

    test('chunk size never decreases as the MTU grows', () {
      var previous = 0;
      for (final mtu in <int>[23, 64, 128, 185, 247, 320, 517]) {
        final size = chunkSizeFor(LinkKind.ble, negotiatedMtu: mtu);
        expect(size, greaterThanOrEqualTo(previous));
        previous = size;
      }
    });

    test('raises the file ceiling on Wi-Fi links', () {
      expect(maxFileBytesFor(LinkKind.lan), greaterThan(maxFileBytesFor(LinkKind.ble)));
      expect(maxFileBytesFor(LinkKind.ble), greaterThan(2 * 1024 * 1024),
          reason: 'the old 2 MB BLE cap was the tightest limit in the app');
    });
  });

  group('crc32', () {
    test('matches known IEEE 802.3 vectors', () {
      expect(crc32('123456789'.codeUnits), 0xCBF43926);
      expect(crc32(<int>[]), 0);
      expect(crc32('The quick brown fox jumps over the lazy dog'.codeUnits), 0x414FA339);
    });

    test('detects a single flipped bit', () {
      final a = List<int>.generate(4096, (i) => i % 256);
      final b = List<int>.from(a)..[2000] ^= 0x01;
      expect(crc32(a), isNot(crc32(b)));
    });
  });
}
