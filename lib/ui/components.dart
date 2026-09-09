// ─────────────────────────────────────────────────────────────
// LessNet — shared Material 3 components
//
// Pixel-flavoured building blocks: tonal containers instead of
// shadows, generous corner radii, 48dp touch targets, and colour
// pulled from the scheme rather than hardcoded hex.
// ─────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';

import '../core/identity.dart';
import '../design/tokens.dart';
import '../net/link.dart';
import '../net/link_manager.dart';

/// Signal strength as four rising bars, used for every radio.
class LnSignalBars extends StatelessWidget {
  const LnSignalBars({super.key, required this.quality, this.size = 18});

  final LnQuality quality;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final active = quality.color(cs);
    final inactive = cs.onSurfaceVariant.withValues(alpha: 0.25);
    final filled = quality.bars;

    return SizedBox(
      width: size,
      height: size,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List<Widget>.generate(4, (i) {
          final h = size * (0.35 + (i * 0.216));
          return Container(
            width: size * 0.17,
            height: h,
            decoration: BoxDecoration(
              color: i < filled ? active : inactive,
              borderRadius: BorderRadius.circular(size * 0.06),
            ),
          );
        }),
      ),
    );
  }
}

/// Circular avatar built from the peer's emoji + a deterministic tint.
class LnAvatar extends StatelessWidget {
  const LnAvatar({
    super.key,
    required this.userId,
    this.emoji = '🙂',
    this.size = 44,
    this.badge,
  });

  final String userId;
  final String emoji;
  final double size;

  /// Small overlay in the bottom-right corner (e.g. transport chip).
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = LnAvatarColors.forId(userId, cs);

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
            child: Text(emoji, style: TextStyle(fontSize: size * 0.46)),
          ),
          if (badge != null)
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(color: cs.surface, shape: BoxShape.circle),
                child: badge,
              ),
            ),
        ],
      ),
    );
  }
}

/// Small tonal chip naming the radio a peer is reachable over.
class LnTransportChip extends StatelessWidget {
  const LnTransportChip({super.key, required this.kind, this.hops = 1, this.compact = false});

  final LinkKind kind;
  final int hops;
  final bool compact;

  IconData get _icon => switch (kind) {
        LinkKind.ble => Icons.bluetooth_rounded,
        LinkKind.lan => Icons.wifi_rounded,
        LinkKind.wifiDirect => Icons.wifi_tethering_rounded,
        LinkKind.hotspot => Icons.router_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;

    if (compact) {
      return Icon(_icon, size: 14, color: cs.onSurfaceVariant);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: LnSpace.sm, vertical: 3),
      decoration: BoxDecoration(
        color: cs.secondaryContainer,
        borderRadius: LnShape.rSm,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(_icon, size: 13, color: cs.onSecondaryContainer),
          const SizedBox(width: LnSpace.xs),
          Text(
            hops > 1 ? '${kind.shortLabel} · $hops saltos' : kind.shortLabel,
            style: t.labelSmall?.copyWith(
              color: cs.onSecondaryContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// The persistent network status banner shown at the top of Home.
class LnNetworkCard extends StatelessWidget {
  const LnNetworkCard({
    super.key,
    required this.peerCount,
    required this.quality,
    required this.kinds,
    required this.queued,
    this.onTap,
  });

  final int peerCount;
  final LnQuality quality;
  final Set<LinkKind> kinds;
  final int queued;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final connected = peerCount > 0;

    final bg = connected ? LnSemantic.okContainer(cs) : cs.surfaceContainerHighest;
    final fg = connected ? LnSemantic.ok(cs) : cs.onSurfaceVariant;

    return Card(
      color: bg,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(LnSpace.lg),
          child: Row(
            children: <Widget>[
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: fg.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  connected ? Icons.hub_rounded : Icons.cloud_off_rounded,
                  color: fg,
                  size: 22,
                ),
              ),
              const SizedBox(width: LnSpace.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      connected
                          ? '$peerCount ${peerCount == 1 ? 'dispositivo' : 'dispositivos'} en la red'
                          : 'Sin dispositivos cerca',
                      style: t.titleMedium?.copyWith(color: cs.onSurface),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      connected
                          ? kinds.map((k) => k.shortLabel).join(' · ')
                          : 'Toca para conectar',
                      style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                    if (queued > 0) ...<Widget>[
                      const SizedBox(height: LnSpace.sm),
                      Row(
                        children: <Widget>[
                          Icon(Icons.schedule_rounded, size: 14, color: LnSemantic.warn(cs)),
                          const SizedBox(width: LnSpace.xs),
                          Text(
                            '$queued en cola, se enviarán al reconectar',
                            style: t.labelSmall?.copyWith(color: LnSemantic.warn(cs)),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (connected) LnSignalBars(quality: quality, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

/// Large tappable tile for one connection method.
class LnMethodTile extends StatelessWidget {
  const LnMethodTile({
    super.key,
    required this.method,
    required this.onTap,
    this.enabled = true,
    this.trailing,
  });

  final ConnectMethod method;
  final VoidCallback onTap;
  final bool enabled;
  final Widget? trailing;

  IconData get _icon => switch (method) {
        ConnectMethod.qr => Icons.qr_code_scanner_rounded,
        ConnectMethod.codigo => Icons.dialpad_rounded,
        ConnectMethod.cerca => Icons.sensors_rounded,
        ConnectMethod.lan => Icons.wifi_rounded,
        ConnectMethod.wifiDirect => Icons.wifi_tethering_rounded,
        ConnectMethod.hotspot => Icons.router_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;

    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Card(
        color: cs.surfaceContainerHigh,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.all(LnSpace.lg),
            child: Row(
              children: <Widget>[
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: LnShape.rMd,
                  ),
                  child: Icon(_icon, color: cs.onPrimaryContainer, size: 22),
                ),
                const SizedBox(width: LnSpace.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Flexible(
                            child: Text(method.title,
                                style: t.titleMedium?.copyWith(color: cs.onSurface)),
                          ),
                          const SizedBox(width: LnSpace.sm),
                          _SpeedPill(seconds: method.typicalSetupSeconds),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        method.subtitle,
                        style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SpeedPill extends StatelessWidget {
  const _SpeedPill({required this.seconds});

  final int seconds;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final fast = seconds <= 6;
    final color = fast ? LnSemantic.ok(cs) : cs.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: LnSpace.sm, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: LnShape.rFull,
      ),
      child: Text(
        '~${seconds}s',
        style: t.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// One row in the peer list.
class LnPeerTile extends StatelessWidget {
  const LnPeerTile({
    super.key,
    required this.peer,
    required this.quality,
    this.kind,
    this.subtitle,
    this.onTap,
    this.trailing,
  });

  final LnPeer peer;
  final LnQuality quality;
  final LinkKind? kind;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;

    return ListTile(
      onTap: onTap,
      leading: LnAvatar(userId: peer.userId, emoji: peer.emoji),
      title: Row(
        children: <Widget>[
          Flexible(child: Text(peer.name, overflow: TextOverflow.ellipsis)),
          const SizedBox(width: LnSpace.sm),
          Text(
            '#${peer.shortCode}',
            style: t.labelSmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
      subtitle: Row(
        children: <Widget>[
          if (kind != null) ...<Widget>[
            LnTransportChip(kind: kind!, hops: peer.hops),
            const SizedBox(width: LnSpace.sm),
          ],
          if (subtitle != null)
            Flexible(
              child: Text(subtitle!, overflow: TextOverflow.ellipsis),
            ),
        ],
      ),
      trailing: trailing ?? LnSignalBars(quality: quality),
    );
  }
}

/// Empty-state block with an icon, a headline and an optional action.
class LnEmptyState extends StatelessWidget {
  const LnEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(LnSpace.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 72,
              height: 72,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 32, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: LnSpace.lg),
            Text(title, style: t.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: LnSpace.sm),
            Text(
              message,
              style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            if (action != null) ...<Widget>[
              const SizedBox(height: LnSpace.xl),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Section label above a group of tiles.
class LnSectionHeader extends StatelessWidget {
  const LnSectionHeader(this.label, {super.key, this.trailing});

  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(LnSpace.xs, LnSpace.xl, LnSpace.xs, LnSpace.sm),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label.toUpperCase(),
              style: t.labelMedium?.copyWith(
                color: cs.primary,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// The six-character pairing code, rendered as separate digit cells.
class LnCodeDisplay extends StatelessWidget {
  const LnCodeDisplay({super.key, required this.code, this.size = 44});

  final String code;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        for (var i = 0; i < code.length; i++) ...<Widget>[
          if (i == 3) SizedBox(width: size * 0.32),
          Container(
            width: size,
            height: size * 1.24,
            margin: EdgeInsets.symmetric(horizontal: size * 0.05),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: LnShape.rMd,
            ),
            child: Text(
              code[i],
              style: t.headlineSmall?.copyWith(
                color: cs.onPrimaryContainer,
                fontWeight: FontWeight.w700,
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Chat bubble with MD3 tonal colours and a delivery-status footer.
class LnMessageBubble extends StatelessWidget {
  const LnMessageBubble({
    super.key,
    required this.text,
    required this.mine,
    required this.time,
    this.status,
    this.senderName,
    this.senderEmoji,
    this.senderId,
    this.viaKind,
    this.child,
  });

  final String text;
  final bool mine;
  final DateTime time;
  final LnMsgStatus? status;
  final String? senderName;
  final String? senderEmoji;
  final String? senderId;
  final LinkKind? viaKind;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;

    final bg = mine ? cs.primary : cs.surfaceContainerHigh;
    final fg = mine ? cs.onPrimary : cs.onSurface;
    final meta = mine
        ? cs.onPrimary.withValues(alpha: 0.75)
        : cs.onSurfaceVariant;

    final bubble = Container(
      constraints: const BoxConstraints(maxWidth: 300),
      padding: const EdgeInsets.symmetric(horizontal: LnSpace.lg, vertical: LnSpace.md),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(LnShape.lg),
          topRight: const Radius.circular(LnShape.lg),
          bottomLeft: Radius.circular(mine ? LnShape.lg : LnShape.xs),
          bottomRight: Radius.circular(mine ? LnShape.xs : LnShape.lg),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (!mine && senderName != null) ...<Widget>[
            Text(
              senderName!,
              style: t.labelMedium?.copyWith(
                color: LnAvatarColors.forId(senderId ?? senderName!, cs),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
          ],
          if (child != null) child!,
          if (child != null && text.isNotEmpty) const SizedBox(height: LnSpace.sm),
          if (text.isNotEmpty)
            Text(text, style: t.bodyLarge?.copyWith(color: fg)),
          const SizedBox(height: LnSpace.xs),
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              if (viaKind != null) ...<Widget>[
                Icon(
                  switch (viaKind!) {
                    LinkKind.ble => Icons.bluetooth_rounded,
                    LinkKind.lan => Icons.wifi_rounded,
                    LinkKind.wifiDirect => Icons.wifi_tethering_rounded,
                    LinkKind.hotspot => Icons.router_rounded,
                  },
                  size: 11,
                  color: meta,
                ),
                const SizedBox(width: LnSpace.xs),
              ],
              Text(
                '${time.hour.toString().padLeft(2, '0')}:'
                '${time.minute.toString().padLeft(2, '0')}',
                style: t.labelSmall?.copyWith(color: meta),
              ),
              if (mine && status != null) ...<Widget>[
                const SizedBox(width: LnSpace.xs),
                Icon(
                  status!.icon,
                  size: 13,
                  color: status == LnMsgStatus.fallido ? cs.errorContainer : meta,
                ),
              ],
            ],
          ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: LnSpace.xs, horizontal: LnSpace.lg),
      child: Row(
        mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          if (!mine && senderId != null) ...<Widget>[
            LnAvatar(userId: senderId!, emoji: senderEmoji ?? '🙂', size: 28),
            const SizedBox(width: LnSpace.sm),
          ],
          Flexible(child: bubble),
        ],
      ),
    );
  }
}

/// Inline progress row for a file being sent or received.
class LnTransferTile extends StatelessWidget {
  const LnTransferTile({
    super.key,
    required this.fileName,
    required this.fraction,
    required this.incoming,
    required this.detail,
    this.onCancel,
  });

  final String fileName;
  final double fraction;
  final bool incoming;
  final String detail;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;

    return Card(
      color: cs.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(LnSpace.md),
        child: Row(
          children: <Widget>[
            Icon(
              incoming ? Icons.download_rounded : Icons.upload_rounded,
              color: cs.primary,
              size: 20,
            ),
            const SizedBox(width: LnSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(fileName,
                      style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: LnSpace.xs),
                  ClipRRect(
                    borderRadius: LnShape.rFull,
                    child: LinearProgressIndicator(value: fraction, minHeight: 5),
                  ),
                  const SizedBox(height: LnSpace.xs),
                  Text(detail, style: t.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                ],
              ),
            ),
            if (onCancel != null)
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: onCancel,
                tooltip: 'Cancelar',
              ),
          ],
        ),
      ),
    );
  }
}
