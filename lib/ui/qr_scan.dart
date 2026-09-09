// ─────────────────────────────────────────────────────────────
// LessNet — QR scanner
//
// The fastest path from "two phones" to "two phones talking":
// point the camera, and the invite carries the group code plus the
// other person's identity, so no list and no typing are involved.
// ─────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../design/tokens.dart';
import '../pairing/pair_code.dart';

class QrScanPage extends StatefulWidget {
  const QrScanPage({super.key, required this.onInvite});

  /// Called once with the first valid LessNet invite seen.
  final void Function(PairInvite invite) onInvite;

  @override
  State<QrScanPage> createState() => _QrScanPageState();
}

class _QrScanPageState extends State<QrScanPage> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const <BarcodeFormat>[BarcodeFormat.qrCode],
  );

  bool _handled = false;
  String? _rejected;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null || raw.isEmpty) continue;

      final invite = PairInvite.tryParse(raw);
      if (invite == null) {
        // Show why rather than silently ignoring a scanned code.
        if (mounted) setState(() => _rejected = 'Ese QR no es de LessNet.');
        continue;
      }

      _handled = true;
      widget.onInvite(invite);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: const Text('Escanear QR'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.flashlight_on_rounded),
            tooltip: 'Linterna',
            onPressed: () => _controller.toggleTorch(),
          ),
          IconButton(
            icon: const Icon(Icons.cameraswitch_rounded),
            tooltip: 'Cambiar cámara',
            onPressed: () => _controller.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(LnSpace.xxl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(Icons.no_photography_rounded, size: 40, color: cs.error),
                    const SizedBox(height: LnSpace.lg),
                    Text(
                      'No se pudo abrir la cámara.\n'
                      'Puedes conectarte escribiendo el código de 6 dígitos.',
                      textAlign: TextAlign.center,
                      style: t.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Viewfinder
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white.withValues(alpha: 0.9), width: 3),
                borderRadius: LnShape.rXl,
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 48,
            child: Column(
              children: <Widget>[
                if (_rejected != null) ...<Widget>[
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: LnSpace.xl),
                    padding: const EdgeInsets.symmetric(
                        horizontal: LnSpace.lg, vertical: LnSpace.md),
                    decoration: BoxDecoration(
                      color: cs.errorContainer,
                      borderRadius: LnShape.rFull,
                    ),
                    child: Text(
                      _rejected!,
                      textAlign: TextAlign.center,
                      style: t.bodyMedium?.copyWith(color: cs.onErrorContainer),
                    ),
                  ),
                  const SizedBox(height: LnSpace.lg),
                ],
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: LnSpace.xl),
                  padding: const EdgeInsets.symmetric(
                      horizontal: LnSpace.lg, vertical: LnSpace.md),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: LnShape.rFull,
                  ),
                  child: Text(
                    'Apunta al código que muestra el otro teléfono',
                    textAlign: TextAlign.center,
                    style: t.bodyMedium?.copyWith(color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
