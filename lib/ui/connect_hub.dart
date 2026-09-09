// ─────────────────────────────────────────────────────────────
// LessNet — "Red" tab
//
// The single place where a user answers "how do I get connected?"
// and "why is it slow?". It wires the presentational screens in
// connect.dart / screens.dart to the live stack.
// ─────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/identity.dart';
import '../design/tokens.dart';
import '../net/link.dart';
import '../net/link_manager.dart';
import '../net/stack.dart';
import '../pairing/pair_code.dart';
import 'components.dart';
import 'connect.dart';
import 'qr_scan.dart';

class ConnectHubPage extends StatefulWidget {
  const ConnectHubPage({super.key});

  @override
  State<ConnectHubPage> createState() => _ConnectHubPageState();
}

class _ConnectHubPageState extends State<ConnectHubPage> {
  static const _kCodeKey = 'ln_pair_code';

  final LessNetStack _stack = LessNetStack.instance;
  PairCode? _code;
  int _queued = 0;

  @override
  void initState() {
    super.initState();
    _loadCode();
    _stack.links.addListener(_refresh);
    _refreshQueue();
  }

  @override
  void dispose() {
    _stack.links.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _refreshQueue() async {
    if (!_stack.isReady) return;
    final n = await _stack.queuedCount();
    if (mounted) setState(() => _queued = n);
  }

  /// The pairing code is stable per install so a group keeps working
  /// across restarts; "Nuevo código" rotates it deliberately.
  Future<void> _loadCode() async {
    final prefs = await SharedPreferences.getInstance();
    var code = PairCode.tryParse(prefs.getString(_kCodeKey) ?? '');
    if (code == null) {
      code = PairCode.random();
      await prefs.setString(_kCodeKey, code.code);
    }
    if (mounted) setState(() => _code = code);
  }

  Future<void> _rotateCode() async {
    final prefs = await SharedPreferences.getInstance();
    final code = PairCode.random();
    await prefs.setString(_kCodeKey, code.code);
    if (mounted) setState(() => _code = code);
  }

  void _openSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        maxChildSize: 0.95,
        builder: (_, controller) => SingleChildScrollView(
          controller: controller,
          child: ConnectSheet(
            methods: _stack.links.suggestedMethods(wifiOn: true, bluetoothOn: true),
            onPick: (m) {
              Navigator.of(ctx).pop();
              _handleMethod(m);
            },
          ),
        ),
      ),
    );
  }

  void _handleMethod(ConnectMethod method) {
    final code = _code;
    if (code == null) return;

    switch (method) {
      case ConnectMethod.qr:
        _openScanner();
      case ConnectMethod.codigo:
        Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => PairCodePage(
            code: code,
            identity: LnIdentity.instance,
            status: 'Buscando por Bluetooth y Wi-Fi al mismo tiempo…',
            onJoin: _joinCode,
            onScanQr: _openScanner,
          ),
        ));
      case ConnectMethod.cerca:
        Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => NearbyPage(
            peers: const <DiscoveredPeer>[],
            scanning: true,
            onConnect: (_) {},
          ),
        ));
      case ConnectMethod.lan:
      case ConnectMethod.wifiDirect:
      case ConnectMethod.hotspot:
        _showDerivedCredentials(method, code);
    }
  }

  void _openScanner() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => QrScanPage(
        onInvite: (invite) {
          Navigator.of(context).pop();
          _joinInvite(invite);
        },
      ),
    ));
  }

  Future<void> _joinInvite(PairInvite invite) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kCodeKey, invite.code.code);
    if (!mounted) return;
    setState(() => _code = invite.code);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Conectando con ${invite.displayName}…')),
    );
  }

  Future<void> _joinCode(PairCode code) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kCodeKey, code.code);
    if (!mounted) return;
    setState(() => _code = code);
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Buscando el grupo ${code.pretty}…')),
    );
  }

  void _showDerivedCredentials(ConnectMethod method, PairCode code) {
    final cs = Theme.of(context).colorScheme;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(method.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(method.subtitle),
            const SizedBox(height: LnSpace.lg),
            _kv(ctx, 'Grupo', code.pretty),
            if (method == ConnectMethod.hotspot) ...<Widget>[
              _kv(ctx, 'Red (SSID)', code.hotspotSsid),
              _kv(ctx, 'Contraseña', code.hotspotPassword),
            ],
            if (method == ConnectMethod.lan) _kv(ctx, 'Servicio', code.lanServiceName),
            if (method != ConnectMethod.hotspot) _kv(ctx, 'Puerto', '${code.lanPort}'),
            const SizedBox(height: LnSpace.lg),
            Text(
              'Estos datos se derivan del código, así que el otro '
              'teléfono los calcula solo. No viajan por el aire.',
              style: Theme.of(ctx)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Widget _kv(BuildContext ctx, String k, String v) {
    final t = Theme.of(ctx).textTheme;
    final cs = Theme.of(ctx).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: LnSpace.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 110,
            child: Text(k, style: t.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
          ),
          Expanded(
            child: SelectableText(
              v,
              style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ready = _stack.isReady;
    final peers = ready ? _stack.peers : const <LnPeer>[];
    final ranked = ready
        ? _stack.links.ranked()
        : const <({LnLink link, double score})>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Red'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.autorenew_rounded),
            tooltip: 'Nuevo código',
            onPressed: _rotateCode,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _refreshQueue();
          _refresh();
        },
        child: ListView(
          padding: const EdgeInsets.all(LnSpace.lg),
          children: <Widget>[
            LnNetworkCard(
              peerCount: peers.length,
              quality: ready ? _stack.quality : LnQuality.perdida,
              kinds: ready ? _stack.activeKinds : const <LinkKind>{},
              queued: _queued,
              onTap: _openSheet,
            ),
            const SizedBox(height: LnSpace.lg),
            FilledButton.icon(
              icon: const Icon(Icons.add_link_rounded),
              label: const Text('Conectar con alguien'),
              onPressed: _openSheet,
            ),
            if (_code != null) ...<Widget>[
              const LnSectionHeader('Tu código de grupo'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: LnSpace.xl),
                  child: Column(
                    children: <Widget>[
                      LnCodeDisplay(code: _code!.code, size: 38),
                      const SizedBox(height: LnSpace.md),
                      Text(
                        'Quien escriba este código te encuentra por cualquier medio',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (peers.isNotEmpty) ...<Widget>[
              LnSectionHeader('Dispositivos alcanzables · ${peers.length}'),
              Card(
                child: Column(
                  children: <Widget>[
                    for (var i = 0; i < peers.length; i++) ...<Widget>[
                      if (i > 0) const Divider(height: 1, indent: 72),
                      LnPeerTile(
                        peer: peers[i],
                        quality: _stack.quality,
                        kind: _stack.activeKinds.isEmpty ? null : _stack.activeKinds.first,
                        subtitle: peers[i].isDirect
                            ? 'Directo'
                            : '${peers[i].hops} saltos de distancia',
                      ),
                    ],
                  ],
                ),
              ),
            ],
            const LnSectionHeader('Calidad de cada medio'),
            if (ranked.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(LnSpace.xl),
                  child: Text(
                    'Sin enlaces activos todavía. Conéctate con alguien para '
                    'ver aquí qué medio está usando LessNet y por qué.',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
              )
            else
              Card(
                child: Column(
                  children: <Widget>[
                    for (final e in ranked)
                      ListTile(
                        leading: Icon(switch (e.link.kind) {
                          LinkKind.ble => Icons.bluetooth_rounded,
                          LinkKind.lan => Icons.wifi_rounded,
                          LinkKind.wifiDirect => Icons.wifi_tethering_rounded,
                          LinkKind.hotspot => Icons.router_rounded,
                        }),
                        title: Text(e.link.kind.label),
                        subtitle: Text(
                          '${e.link.remoteName} · ${e.link.quality.label} · '
                          'puntaje ${e.score.toStringAsFixed(0)}',
                        ),
                        trailing: LnSignalBars(quality: e.link.quality),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: LnSpace.xl),
            SegmentedButton<TransportPreference>(
              segments: const <ButtonSegment<TransportPreference>>[
                ButtonSegment<TransportPreference>(
                  value: TransportPreference.automatico,
                  label: Text('Auto'),
                  icon: Icon(Icons.auto_awesome_rounded),
                ),
                ButtonSegment<TransportPreference>(
                  value: TransportPreference.bluetooth,
                  label: Text('BT'),
                  icon: Icon(Icons.bluetooth_rounded),
                ),
                ButtonSegment<TransportPreference>(
                  value: TransportPreference.wifi,
                  label: Text('Wi-Fi'),
                  icon: Icon(Icons.wifi_rounded),
                ),
              ],
              selected: <TransportPreference>{
                ready ? _stack.links.preference : TransportPreference.automatico,
              },
              onSelectionChanged: (s) {
                if (!ready) return;
                setState(() => _stack.links.preference = s.first);
              },
            ),
            const SizedBox(height: LnSpace.sm),
            Text(
              (ready ? _stack.links.preference : TransportPreference.automatico)
                  .description,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: LnSpace.huge),
          ],
        ),
      ),
    );
  }
}
