// ─────────────────────────────────────────────────────────────
// LessNet — Link abstraction
//
// A "link" is one usable path to one remote endpoint over one
// radio. BLE, LAN (TCP over Wi-Fi), Wi-Fi Direct and Hotspot all
// implement the same interface, which is what lets the router
// treat them interchangeably and lets LinkManager score them
// against each other and pick the best one per destination.
// ─────────────────────────────────────────────────────────────
import 'dart:async';
import 'dart:math' as math;

import '../design/tokens.dart';

enum LinkKind { ble, lan, wifiDirect, hotspot }

extension LinkKindX on LinkKind {
  String get label => switch (this) {
        LinkKind.ble => 'Bluetooth LE',
        LinkKind.lan => 'Wi-Fi (LAN)',
        LinkKind.wifiDirect => 'Wi-Fi Direct',
        LinkKind.hotspot => 'Hotspot',
      };

  String get shortLabel => switch (this) {
        LinkKind.ble => 'BLE',
        LinkKind.lan => 'LAN',
        LinkKind.wifiDirect => 'P2P',
        LinkKind.hotspot => 'AP',
      };

  /// Rough capability profile, used by the scorer. These are
  /// deliberately conservative real-world numbers, not spec maxima.
  LinkCaps get caps => switch (this) {
        LinkKind.ble => const LinkCaps(
            maxPayload: 512,
            throughputBps: 12 * 1024,
            typicalLatencyMs: 120,
            powerCost: 1,
          ),
        LinkKind.lan => const LinkCaps(
            maxPayload: 60 * 1024,
            throughputBps: 4 * 1024 * 1024,
            typicalLatencyMs: 12,
            powerCost: 2,
          ),
        LinkKind.wifiDirect => const LinkCaps(
            maxPayload: 60 * 1024,
            throughputBps: 6 * 1024 * 1024,
            typicalLatencyMs: 18,
            powerCost: 3,
          ),
        LinkKind.hotspot => const LinkCaps(
            maxPayload: 60 * 1024,
            throughputBps: 3 * 1024 * 1024,
            typicalLatencyMs: 25,
            powerCost: 4,
          ),
      };
}

class LinkCaps {
  /// Largest payload that can be handed to [LnLink.send] in one call.
  final int maxPayload;
  final int throughputBps;
  final int typicalLatencyMs;

  /// 1 (cheap) … 4 (expensive). Used to break ties in favour of battery.
  final int powerCost;

  const LinkCaps({
    required this.maxPayload,
    required this.throughputBps,
    required this.typicalLatencyMs,
    required this.powerCost,
  });
}

/// Rolling health of a link. Updated by the transport on every
/// send/receive so the scorer works off observed behaviour rather
/// than the static profile alone.
class LinkStats {
  int sent = 0;
  int failed = 0;
  int bytesOut = 0;
  int bytesIn = 0;
  DateTime? lastSuccess;
  DateTime? lastFailure;

  /// Exponentially weighted round-trip estimate, ms.
  double rttMs = 0;

  void recordSuccess({int bytes = 0, int? rtt}) {
    sent++;
    bytesOut += bytes;
    lastSuccess = DateTime.now();
    if (rtt != null && rtt >= 0) {
      rttMs = rttMs == 0 ? rtt.toDouble() : (rttMs * 0.8) + (rtt * 0.2);
    }
  }

  void recordFailure() {
    failed++;
    lastFailure = DateTime.now();
  }

  void recordIncoming(int bytes) {
    bytesIn += bytes;
    lastSuccess = DateTime.now();
  }

  /// 0.0 … 1.0 over the recent window.
  double get successRate {
    final total = sent + failed;
    if (total == 0) return 1.0;
    return sent / total;
  }

  /// True when the link failed recently and has not recovered.
  bool get recentlyFailing {
    final f = lastFailure;
    if (f == null) return false;
    if (DateTime.now().difference(f) > const Duration(seconds: 30)) return false;
    final s = lastSuccess;
    return s == null || s.isBefore(f);
  }
}

/// One path to one peer over one radio.
abstract class LnLink {
  /// Stable within a session; unique per (kind, remote endpoint).
  String get id;

  LinkKind get kind;

  /// Remote LessNet user id. Empty until the peer's `hello` arrives.
  String get remoteUserId;

  /// Human-readable name for the UI.
  String get remoteName;

  bool get isUp;

  /// Raw radio signal: RSSI in dBm for BLE, 0–100 for Wi-Fi family.
  int get signal;

  LinkStats get stats;

  LinkCaps get caps => kind.caps;

  /// Framed inbound lines, one encoded packet each.
  Stream<String> get incoming;

  /// Returns true when the line was handed to the radio successfully.
  Future<bool> send(String line);

  Future<void> close();

  /// Normalised quality bucket, shared across radios so the UI can
  /// render every link the same way.
  LnQuality get quality {
    if (!isUp) return LnQuality.perdida;
    final bySignal = switch (kind) {
      LinkKind.ble => _bleQuality(signal),
      _ => _wifiQuality(signal),
    };
    if (!stats.recentlyFailing) return bySignal;
    // A link that just failed is never reported as better than weak,
    // but a link whose signal is already worse keeps the worse value.
    final worst = bySignal.index > LnQuality.debil.index ? bySignal.index : LnQuality.debil.index;
    return LnQuality.values[worst];
  }

  static LnQuality _bleQuality(int rssi) {
    if (rssi == 0) return LnQuality.buena; // unknown but connected
    if (rssi > -65) return LnQuality.excelente;
    if (rssi > -80) return LnQuality.buena;
    if (rssi > -95) return LnQuality.debil;
    return LnQuality.perdida;
  }

  static LnQuality _wifiQuality(int pct) {
    if (pct == 0) return LnQuality.buena;
    if (pct >= 70) return LnQuality.excelente;
    if (pct >= 45) return LnQuality.buena;
    if (pct >= 20) return LnQuality.debil;
    return LnQuality.perdida;
  }
}

/// How good is this link for reaching a peer that is [hops] away?
///
/// Higher is better. The weights are chosen so that:
///  * a Wi-Fi-family link always beats BLE while its signal holds,
///  * a degraded Wi-Fi link loses to a solid BLE link,
///  * extra hops cost more than a one-step radio downgrade,
///  * a link that just failed is heavily penalised but not banned,
///  * ties break toward the cheaper radio.
double scoreLink(LnLink link, {int hops = 1, bool incumbent = false}) {
  if (!link.isUp) return double.negativeInfinity;

  // Throughput headroom, compressed logarithmically: the jump from
  // BLE to Wi-Fi matters far more than LAN vs Wi-Fi Direct.
  final caps = link.caps;
  var score = 6.0 * _log2(caps.throughputBps / 1024).clamp(0.0, 14.0);

  // Latency: cheaper links win, but it is a secondary term.
  score -= caps.typicalLatencyMs * 0.08;

  // Observed signal quality.
  score += switch (link.quality) {
    LnQuality.excelente => 24.0,
    LnQuality.buena => 12.0,
    LnQuality.debil => -18.0,
    LnQuality.perdida => -70.0,
  };

  // Every extra hop adds latency and a failure point.
  score -= (hops - 1) * 16.0;

  // Observed reliability.
  score -= (1.0 - link.stats.successRate) * 40.0;
  if (link.stats.recentlyFailing) score -= 35.0;

  // Battery, as a tie-breaker only.
  score -= caps.powerCost * 1.5;

  // Hysteresis: the link already in use must be beaten by a clear
  // margin, otherwise the app flaps between radios every few seconds.
  if (incumbent) score += 10.0;

  return score;
}

double _log2(num x) => x <= 1 ? 0 : math.log(x) / math.ln2;

/// What the router knows about how to reach a peer.
class PeerRoute {
  final String userId;
  String displayName;

  /// Link the peer was last heard on.
  String linkId;

  /// Hops away (1 = direct neighbour).
  int hops;

  DateTime lastSeen;

  PeerRoute({
    required this.userId,
    required this.displayName,
    required this.linkId,
    required this.hops,
    required this.lastSeen,
  });

  bool get isStale => DateTime.now().difference(lastSeen) > const Duration(minutes: 3);
  bool get isDirect => hops <= 1;
}
