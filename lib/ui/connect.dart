// ─────────────────────────────────────────────────────────────
// LessNet — connect flow
//
// Replaces "abre Buscar, mira una lista de MACs, intenta varias
// veces" with a sheet of concrete methods ordered by how fast they
// actually get you talking, plus the two that need no list at all:
// a shared 6-character code and a QR.
// ─────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/identity.dart';
import '../design/tokens.dart';
import '../net/link.dart';
import '../net/link_manager.dart';
import '../pairing/pair_code.dart';
import 'components.dart';

/// A peer as surfaced by discovery, before a link exists.
class DiscoveredPeer {
  final LnPeer peer;
  final LinkKind kind;
  final LnQuality quality;
  final int signal;
  final bool sameCode;

  const DiscoveredPeer({
    required this.peer,
    required this.kind,
    required this.quality,
    this.signal = 0,
    this.sameCode = false,
  });

  /// Rough distance band from RSSI, for the "cerca de mí" list.
  String get proximity {
    if (kind != LinkKind.ble) return 'En la red';
    if (signal == 0) return 'Cerca';
    if (signal > -55) return 'Muy cerca (~1 m)';
    if (signal > -68) return 'Cerca (~3 m)';
    if (signal > -80) return 'A la vista (~10 m)';
    return 'Lejos (>10 m)';
  }
}

/// Bottom sheet listing every way to connect, fastest first.
class ConnectSheet extends StatelessWidget {
  const ConnectSheet({
    super.key,
    required this.methods,
    required this.onPick,
    this.bluetoothOn = true,
    this.wifiOn = true,
  });

  final List<ConnectMethod> methods;
  final void Function(ConnectMethod) onPick;
  final bool bluetoothOn;
  final bool wifiOn;

  bool _enabled(ConnectMethod m) => switch (m.producesKind) {
        LinkKind.ble => bluetoothOn,
        LinkKind.lan || LinkKind.wifiDirect => wifiOn,
        LinkKind.hotspot => true,
      };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(LnSpace.lg, 0, LnSpace.lg, LnSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Conectar con alguien', style: t.headlineSmall),
            const SizedBox(height: LnSpace.xs),
            Text(
              'LessNet elige el mejor medio automáticamente. '
              'Estos son los caminos más rápidos para empezar.',
              style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: LnSpace.xl),
            for (final m in methods) ...<Widget>[
              LnMethodTile(
                method: m,
                enabled: _enabled(m),
                onTap: () => onPick(m),
                trailing: _enabled(m)
                    ? Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant)
                    : Tooltip(
                        message: m.producesKind == LinkKind.ble
                            ? 'Activa el Bluetooth'
                            : 'Activa el Wi-Fi',
                        child: Icon(Icons.info_outline_rounded, color: cs.onSurfaceVariant),
                      ),
              ),
              const SizedBox(height: LnSpace.md),
            ],
          ],
        ),
      ),
    );
  }
}

/// Screen that shows *our* code and QR, and accepts the other side's code.
class PairCodePage extends StatefulWidget {
  const PairCodePage({
    super.key,
    required this.code,
    required this.identity,
    required this.onJoin,
    this.onScanQr,
    this.status,
  });

  final PairCode code;
  final LnIdentity identity;

  /// Called when the user submits a valid code from the other device.
  final void Function(PairCode code) onJoin;
  final VoidCallback? onScanQr;

  /// Live status line ("Buscando por Bluetooth y Wi-Fi…").
  final String? status;

  @override
  State<PairCodePage> createState() => _PairCodePageState();
}

class _PairCodePageState extends State<PairCodePage> {
  final TextEditingController _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final parsed = PairCode.tryParse(_controller.text);
    if (parsed == null) {
      setState(() => _error = 'Código inválido. Son 6 caracteres, sin O, I, L, U ni 0/1.');
      return;
    }
    setState(() => _error = null);
    widget.onJoin(parsed);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;

    final invite = PairInvite(
      code: widget.code,
      userId: widget.identity.userId,
      name: widget.identity.displayName,
      emoji: widget.identity.avatarEmoji,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Conectar con un código'),
        actions: <Widget>[
          if (widget.onScanQr != null)
            IconButton(
              icon: const Icon(Icons.qr_code_scanner_rounded),
              tooltip: 'Escanear QR',
              onPressed: widget.onScanQr,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(LnSpace.lg),
        children: <Widget>[
          Card(
            color: cs.surfaceContainerHigh,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                vertical: LnSpace.xl,
                horizontal: LnSpace.lg,
              ),
              child: Column(
                children: <Widget>[
                  Text('Tu código', style: t.titleMedium),
                  const SizedBox(height: LnSpace.xs),
                  Text(
                    'Dícelo en voz alta o muéstralo. Sirve para cualquier medio.',
                    style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: LnSpace.xl),
                  LnCodeDisplay(code: widget.code.code),
                  const SizedBox(height: LnSpace.xl),
                  Container(
                    padding: const EdgeInsets.all(LnSpace.md),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: LnShape.rMd,
                    ),
                    child: QrImageView(
                      data: invite.toUri(),
                      size: 168,
                      backgroundColor: Colors.white,
                      // Fixed dark-on-white: a QR must keep its contrast
                      // regardless of the app theme or it stops scanning.
                      eyeStyle: const QrEyeStyle(
                        eyeShape: QrEyeShape.square,
                        color: Color(0xFF000000),
                      ),
                      dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: Color(0xFF000000),
                      ),
                    ),
                  ),
                  const SizedBox(height: LnSpace.lg),
                  TextButton.icon(
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: const Text('Copiar código'),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: widget.code.code));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Código copiado')),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          if (widget.status != null) ...<Widget>[
            const SizedBox(height: LnSpace.lg),
            Row(
              children: <Widget>[
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
                ),
                const SizedBox(width: LnSpace.md),
                Expanded(
                  child: Text(widget.status!,
                      style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                ),
              ],
            ),
          ],
          const LnSectionHeader('O escribe el código del otro equipo'),
          TextField(
            controller: _controller,
            autocorrect: false,
            textCapitalization: TextCapitalization.characters,
            maxLength: 8,
            style: t.headlineSmall?.copyWith(letterSpacing: 6),
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              hintText: 'K7M2QX',
              errorText: _error,
              counterText: '',
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: LnSpace.lg),
          FilledButton.icon(
            icon: const Icon(Icons.link_rounded),
            label: const Text('Conectar'),
            onPressed: _submit,
          ),
        ],
      ),
    );
  }
}

/// "Cerca de mí" — live proximity list, sorted by signal.
class NearbyPage extends StatelessWidget {
  const NearbyPage({
    super.key,
    required this.peers,
    required this.scanning,
    required this.onConnect,
    this.onRescan,
  });

  final List<DiscoveredPeer> peers;
  final bool scanning;
  final void Function(DiscoveredPeer) onConnect;
  final VoidCallback? onRescan;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;

    final sorted = List<DiscoveredPeer>.from(peers)
      ..sort((a, b) {
        if (a.sameCode != b.sameCode) return a.sameCode ? -1 : 1;
        return b.signal.compareTo(a.signal);
      });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cerca de mí'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: onRescan,
            tooltip: 'Buscar otra vez',
          ),
        ],
        bottom: scanning
            ? const PreferredSize(
                preferredSize: Size.fromHeight(3),
                child: LinearProgressIndicator(minHeight: 3),
              )
            : null,
      ),
      body: sorted.isEmpty
          ? LnEmptyState(
              icon: Icons.sensors_rounded,
              title: scanning ? 'Buscando dispositivos…' : 'Nadie cerca todavía',
              message: scanning
                  ? 'LessNet busca por Bluetooth y Wi-Fi al mismo tiempo.'
                  : 'Pide a la otra persona que abra LessNet y deje la pantalla encendida.',
              action: scanning
                  ? null
                  : FilledButton.icon(
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Buscar otra vez'),
                      onPressed: onRescan,
                    ),
            )
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: LnSpace.sm),
              children: <Widget>[
                if (sorted.any((p) => p.sameCode))
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                        LnSpace.lg, LnSpace.sm, LnSpace.lg, LnSpace.sm),
                    child: Text(
                      'CON TU MISMO CÓDIGO',
                      style: t.labelMedium?.copyWith(
                        color: cs.primary,
                        letterSpacing: 0.8,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                for (final p in sorted)
                  LnPeerTile(
                    peer: p.peer,
                    quality: p.quality,
                    kind: p.kind,
                    subtitle: p.proximity,
                    onTap: () => onConnect(p),
                    trailing: FilledButton.tonal(
                      onPressed: () => onConnect(p),
                      child: const Text('Conectar'),
                    ),
                  ),
              ],
            ),
    );
  }
}
