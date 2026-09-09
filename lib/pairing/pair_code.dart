// ─────────────────────────────────────────────────────────────
// LessNet — pairing codes
//
// The old flow was: open Scan, wait for a list of MAC addresses,
// guess which one is your friend, tap, hope. This replaces it with
// a short shared code that both devices already agree on, so every
// transport can be keyed to it deterministically:
//
//   code ──┬─ BLE service-data tag  (filter the scan to your group)
//          ├─ NSD service name      (find each other on the LAN)
//          ├─ Hotspot SSID          (LessNet-K7M2QX)
//          └─ Hotspot password      (derived, never transmitted)
//
// Because everything is derived, two phones that share the code can
// meet on whichever radio comes up first — no list, no MAC, no
// "intenta varias veces" as the README currently advises.
// ─────────────────────────────────────────────────────────────
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Crockford-style alphabet: no 0/O, no 1/I/L, no U. Every character
/// survives being read aloud over a noisy radio or shouted across a
/// shelter, which is the actual use case.
const String kCodeAlphabet = '23456789ABCDEFGHJKMNPQRSTVWXYZ';
const int kCodeLength = 6;

final Random _rng = Random.secure();

/// A pairing code plus everything derived from it.
class PairCode {
  final String code;

  const PairCode._(this.code);

  /// Generate a fresh random code.
  factory PairCode.random() {
    final b = StringBuffer();
    for (var i = 0; i < kCodeLength; i++) {
      b.write(kCodeAlphabet[_rng.nextInt(kCodeAlphabet.length)]);
    }
    return PairCode._(b.toString());
  }

  /// Normalise and validate user input. Returns null if it cannot be
  /// read as a code, so the UI can show a precise error.
  static PairCode? tryParse(String input) {
    final cleaned = normalise(input);
    if (cleaned.length != kCodeLength) return null;
    for (final ch in cleaned.split('')) {
      if (!kCodeAlphabet.contains(ch)) return null;
    }
    return PairCode._(cleaned);
  }

  /// Upper-cases and strips the separators people naturally type
  /// ("k7m 2qx", "K7M-2QX"). Characters outside the alphabet are kept
  /// so that [tryParse] can reject them: silently dropping a stray
  /// character would turn a wrong code into a plausible one.
  static String normalise(String input) {
    final buf = StringBuffer();
    for (final ch in input.toUpperCase().split('')) {
      if (ch == ' ' || ch == '-' || ch == '_' || ch == '.') continue;
      buf.write(ch);
    }
    return buf.toString();
  }

  /// Formatted for display: "K7M-2QX".
  String get pretty => '${code.substring(0, 3)}-${code.substring(3)}';

  List<int> get _digest => sha256.convert(utf8.encode('lessnet-pair-$code')).bytes;

  /// Two bytes advertised in BLE service data. Scanning devices can
  /// filter on this locally and only surface peers in the same group,
  /// which is what makes "cerca de mí" instant instead of a guessing game.
  List<int> get bleTag => <int>[_digest[0], _digest[1]];

  /// Hex form of [bleTag], for the platform channel and for logs.
  String get bleTagHex => bleTag.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  /// mDNS/NSD instance name so LAN discovery finds only this group.
  String get lanServiceName => 'lessnet-${code.toLowerCase()}';

  /// Hotspot SSID. Visible in the Android Wi-Fi picker, so it is
  /// deliberately human-recognisable.
  String get hotspotSsid => 'LessNet-$code';

  /// Hotspot passphrase, derived rather than transmitted. Both sides
  /// compute it from the code, so it never travels over the air.
  String get hotspotPassword {
    final d = sha256.convert(utf8.encode('lessnet-ap-$code')).bytes;
    final b = StringBuffer();
    for (var i = 0; i < 12; i++) {
      b.write(kCodeAlphabet[d[i] % kCodeAlphabet.length]);
    }
    return b.toString();
  }

  /// Deterministic TCP port in the ephemeral range, so two devices in
  /// the same group agree without negotiating.
  int get lanPort => 20000 + ((_digest[2] << 8 | _digest[3]) % 20000);

  @override
  String toString() => code;

  @override
  bool operator ==(Object other) => other is PairCode && other.code == code;

  @override
  int get hashCode => code.hashCode;
}

/// The payload encoded into a pairing QR.
class PairInvite {
  final PairCode code;
  final String userId;
  final String name;
  final String emoji;

  const PairInvite({
    required this.code,
    required this.userId,
    required this.name,
    required this.emoji,
  });

  static const String scheme = 'lessnet';

  /// `lessnet://join?c=K7M2QX&id=...&n=...&e=...`
  String toUri() {
    final u = Uri(
      scheme: scheme,
      host: 'join',
      queryParameters: <String, String>{
        'c': code.code,
        'id': userId,
        'n': name,
        'e': emoji,
      },
    );
    return u.toString();
  }

  static PairInvite? tryParse(String raw) {
    Uri u;
    try {
      u = Uri.parse(raw.trim());
    } catch (_) {
      return null;
    }
    if (u.scheme != scheme) return null;
    if (u.host != 'join') return null;

    final code = PairCode.tryParse(u.queryParameters['c'] ?? '');
    if (code == null) return null;

    final id = u.queryParameters['id'] ?? '';
    if (id.isEmpty) return null;

    return PairInvite(
      code: code,
      userId: id,
      name: (u.queryParameters['n'] ?? '').trim(),
      emoji: (u.queryParameters['e'] ?? '🙂'),
    );
  }

  String get displayName => name.isEmpty ? 'Usuario ${userId.substring(0, userId.length.clamp(0, 4))}' : name;
}
