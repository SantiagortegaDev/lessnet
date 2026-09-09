// ─────────────────────────────────────────────────────────────
// LessNet — link manager
//
// Holds every live link, scores them, and answers the question the
// old code never really asked: "given who I want to reach right
// now, which radio should carry this?"
//
// The previous implementation broadcast every message over BLE *and*
// LAN *and* Wi-Fi Direct at once, once per BLE peer — so with N BLE
// peers each LAN device received the same text N times. Here a
// destination resolves to exactly one link, with automatic failover
// and hysteresis so the app does not flap between radios.
// ─────────────────────────────────────────────────────────────
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../design/tokens.dart';
import 'link.dart';
import 'mesh_router.dart';

/// User-facing preference for which radio to use.
enum TransportPreference { automatico, bluetooth, wifi }

extension TransportPreferenceX on TransportPreference {
  String get label => switch (this) {
        TransportPreference.automatico => 'Automático',
        TransportPreference.bluetooth => 'Solo Bluetooth',
        TransportPreference.wifi => 'Preferir Wi-Fi',
      };

  String get description => switch (this) {
        TransportPreference.automatico =>
          'LessNet elige el mejor medio en cada momento según señal, velocidad y batería.',
        TransportPreference.bluetooth =>
          'Máximo alcance y mínimo consumo. Más lento para archivos.',
        TransportPreference.wifi =>
          'Mucho más rápido para fotos y videos. Consume más batería.',
      };
}

/// One way of getting two devices talking, as presented in the UI.
enum ConnectMethod { codigo, qr, cerca, wifiDirect, lan, hotspot }

extension ConnectMethodX on ConnectMethod {
  String get title => switch (this) {
        ConnectMethod.codigo => 'Código de 6 dígitos',
        ConnectMethod.qr => 'Escanear QR',
        ConnectMethod.cerca => 'Cerca de mí',
        ConnectMethod.wifiDirect => 'Wi-Fi Direct',
        ConnectMethod.lan => 'Misma red Wi-Fi',
        ConnectMethod.hotspot => 'Crear punto de acceso',
      };

  String get subtitle => switch (this) {
        ConnectMethod.codigo => 'Ambos escriben el mismo código. Sin listas ni MACs.',
        ConnectMethod.qr => 'Lo más rápido: apunta la cámara y listo.',
        ConnectMethod.cerca => 'Detecta automáticamente quién está a menos de ~10 m.',
        ConnectMethod.wifiDirect => 'Rápido y sin router. Ideal para archivos grandes.',
        ConnectMethod.lan => 'Si ya comparten Wi-Fi, es instantáneo y el más veloz.',
        ConnectMethod.hotspot => 'Cuando no hay red: un teléfono la crea para el resto.',
      };

  /// Typical seconds from tapping to a usable link. Drives the ordering
  /// in the connect sheet — fastest first.
  int get typicalSetupSeconds => switch (this) {
        ConnectMethod.qr => 3,
        ConnectMethod.lan => 4,
        ConnectMethod.cerca => 6,
        ConnectMethod.codigo => 8,
        ConnectMethod.wifiDirect => 12,
        ConnectMethod.hotspot => 20,
      };

  LinkKind get producesKind => switch (this) {
        ConnectMethod.codigo => LinkKind.ble,
        ConnectMethod.qr => LinkKind.ble,
        ConnectMethod.cerca => LinkKind.ble,
        ConnectMethod.wifiDirect => LinkKind.wifiDirect,
        ConnectMethod.lan => LinkKind.lan,
        ConnectMethod.hotspot => LinkKind.hotspot,
      };
}

/// Which link is currently carrying traffic to a given peer.
class ActiveChoice {
  final String dest;
  final String linkId;
  final LinkKind kind;
  final double score;
  final int hops;

  const ActiveChoice({
    required this.dest,
    required this.linkId,
    required this.kind,
    required this.score,
    required this.hops,
  });
}

class LinkManager extends ChangeNotifier {
  LinkManager({this.onLog});

  final void Function(String message)? onLog;

  final Map<String, LnLink> _links = <String, LnLink>{};
  final Map<String, StreamSubscription<String>> _subs =
      <String, StreamSubscription<String>>{};

  /// Last chosen link per destination, for hysteresis.
  final Map<String, String> _incumbent = <String, String>{};

  TransportPreference _preference = TransportPreference.automatico;

  MeshRouter? _router;

  final StreamController<String> _rawIncoming = StreamController<String>.broadcast();

  /// Raw framed lines from every link, tagged with the link id.
  final StreamController<({String line, String linkId})> _tagged =
      StreamController<({String line, String linkId})>.broadcast();

  Stream<({String line, String linkId})> get onLine => _tagged.stream;
  Stream<String> get onRawLine => _rawIncoming.stream;

  TransportPreference get preference => _preference;

  set preference(TransportPreference p) {
    if (p == _preference) return;
    _preference = p;
    _incumbent.clear();
    notifyListeners();
  }

  void attachRouter(MeshRouter router) => _router = router;

  List<LnLink> get links => _links.values.toList(growable: false);

  List<LnLink> get liveLinks => _links.values.where((l) => l.isUp).toList(growable: false);

  bool get hasAnyLink => _links.values.any((l) => l.isUp);

  int get liveCount => liveLinks.length;

  /// Radios currently carrying at least one live link.
  Set<LinkKind> get activeKinds => liveLinks.map((l) => l.kind).toSet();

  /// Best single link overall — what the status bar shows.
  LnLink? get primaryLink {
    final candidates = _eligible();
    if (candidates.isEmpty) return null;
    candidates.sort((a, b) => scoreLink(b).compareTo(scoreLink(a)));
    return candidates.first;
  }

  LnQuality get overallQuality => primaryLink?.quality ?? LnQuality.perdida;

  void addLink(LnLink link) {
    if (_links.containsKey(link.id)) return;
    _links[link.id] = link;
    _subs[link.id] = link.incoming.listen(
      (line) {
        link.stats.recordIncoming(line.length);
        _tagged.add((line: line, linkId: link.id));
        _rawIncoming.add(line);
      },
      onError: (Object e) {
        link.stats.recordFailure();
        onLog?.call('Error en enlace ${link.id}: $e');
      },
    );
    onLog?.call('Enlace añadido: ${link.kind.shortLabel} ${link.id}');
    notifyListeners();
  }

  Future<void> removeLink(String id) async {
    final link = _links.remove(id);
    await _subs.remove(id)?.cancel();
    if (link != null) {
      try {
        await link.close();
      } catch (_) {
        // Closing a link that is already gone is not an error.
      }
      onLog?.call('Enlace cerrado: ${link.kind.shortLabel} $id');
      _incumbent.removeWhere((_, v) => v == id);
      notifyListeners();
    }
  }

  Future<void> removeLinksOfKind(LinkKind kind) async {
    final ids = _links.values.where((l) => l.kind == kind).map((l) => l.id).toList();
    for (final id in ids) {
      await removeLink(id);
    }
  }

  List<LnLink> _eligible() {
    return _links.values.where((l) {
      if (!l.isUp) return false;
      return switch (_preference) {
        TransportPreference.automatico => true,
        TransportPreference.bluetooth => l.kind == LinkKind.ble,
        // "Prefer Wi-Fi" still allows BLE as a fallback; it only
        // changes the scoring bias, applied in scoreFor below.
        TransportPreference.wifi => true,
      };
    }).toList();
  }

  double _scoreFor(LnLink link, {required int hops, required bool incumbent}) {
    var s = scoreLink(link, hops: hops, incumbent: incumbent);
    if (_preference == TransportPreference.wifi && link.kind != LinkKind.ble) {
      s += 25; // strong nudge, still loses if the link is actually broken
    }
    return s;
  }

  /// The single best link for reaching [dest], or null if unreachable.
  ///
  /// [dest] is a LessNet user id; pass null for "anything live".
  ActiveChoice? chooseFor(String? dest) {
    final candidates = _eligible();
    if (candidates.isEmpty) return null;

    final route = dest == null ? null : _router?.routeTo(dest);
    final incumbentId = dest == null ? null : _incumbent[dest];

    LnLink? best;
    var bestScore = double.negativeInfinity;
    var bestHops = 1;

    for (final link in candidates) {
      // Hop count: a direct link to the destination is 1 hop; if the
      // router knows a route through this link, use its hop count.
      var hops = 1;
      if (dest != null) {
        if (link.remoteUserId == dest) {
          hops = 1;
        } else if (route != null && route.linkId == link.id) {
          hops = route.hops;
        } else if (route != null) {
          // This link is not on the known route; treat it as a longer
          // speculative path so the known route wins ties.
          hops = route.hops + 1;
        }
      }

      final s = _scoreFor(link, hops: hops, incumbent: link.id == incumbentId);
      if (s > bestScore) {
        bestScore = s;
        best = link;
        bestHops = hops;
      }
    }

    if (best == null || bestScore == double.negativeInfinity) return null;

    if (dest != null && _incumbent[dest] != best.id) {
      final previous = _incumbent[dest];
      _incumbent[dest] = best.id;
      if (previous != null) {
        onLog?.call('Cambio de medio para $dest: → ${best.kind.shortLabel}');
        notifyListeners();
      }
    }

    return ActiveChoice(
      dest: dest ?? '*',
      linkId: best.id,
      kind: best.kind,
      score: bestScore,
      hops: bestHops,
    );
  }

  /// Ranked view of every link, for the diagnostics screen.
  List<({LnLink link, double score})> ranked({String? dest}) {
    final route = dest == null ? null : _router?.routeTo(dest);
    final list = _eligible().map((l) {
      final hops = (dest != null && route != null && route.linkId == l.id) ? route.hops : 1;
      return (link: l, score: _scoreFor(l, hops: hops, incumbent: _incumbent[dest] == l.id));
    }).toList();
    list.sort((a, b) => b.score.compareTo(a.score));
    return list;
  }

  /// Which connect methods make sense right now, fastest first.
  List<ConnectMethod> suggestedMethods({required bool wifiOn, required bool bluetoothOn}) {
    final out = <ConnectMethod>[];
    if (bluetoothOn) out.addAll([ConnectMethod.qr, ConnectMethod.cerca, ConnectMethod.codigo]);
    if (wifiOn) out.addAll([ConnectMethod.lan, ConnectMethod.wifiDirect]);
    out.add(ConnectMethod.hotspot);
    out.sort((a, b) => a.typicalSetupSeconds.compareTo(b.typicalSetupSeconds));
    return out;
  }

  @override
  void dispose() {
    for (final s in _subs.values) {
      s.cancel();
    }
    _subs.clear();
    for (final l in _links.values) {
      l.close();
    }
    _links.clear();
    _tagged.close();
    _rawIncoming.close();
    super.dispose();
  }
}
