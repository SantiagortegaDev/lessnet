// ─────────────────────────────────────────────────────────────
// LessNet — main screens (Material 3)
//
// These are presentational: everything they show arrives through
// the constructor, which keeps them testable and lets the golden
// tests render them without a device or any platform plugin.
// ─────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';

import '../core/identity.dart';
import '../design/tokens.dart';
import '../net/link.dart';
import '../net/link_manager.dart';
import 'components.dart';

/// One row in the chat list.
class ChatSummary {
  final String id;
  final String title;
  final String emoji;
  final String preview;
  final DateTime time;
  final int unread;
  final bool isGroup;
  final LinkKind? via;
  final LnQuality quality;
  final int queued;

  const ChatSummary({
    required this.id,
    required this.title,
    required this.preview,
    required this.time,
    this.emoji = '🙂',
    this.unread = 0,
    this.isGroup = false,
    this.via,
    this.quality = LnQuality.buena,
    this.queued = 0,
  });
}

/// A message as the chat view needs it.
class ChatBubbleData {
  final String id;
  final String text;
  final bool mine;
  final DateTime time;
  final LnMsgStatus status;
  final String? senderId;
  final String? senderName;
  final String? senderEmoji;
  final LinkKind? via;

  const ChatBubbleData({
    required this.id,
    required this.text,
    required this.mine,
    required this.time,
    this.status = LnMsgStatus.enviado,
    this.senderId,
    this.senderName,
    this.senderEmoji,
    this.via,
  });
}

// ─────────────────────────── HOME ───────────────────────────

class LnHomeView extends StatelessWidget {
  const LnHomeView({
    super.key,
    required this.identity,
    required this.peers,
    required this.quality,
    required this.activeKinds,
    required this.queued,
    required this.chats,
    this.onConnect,
    this.onOpenChat,
    this.onSos,
    this.onOpenNetwork,
  });

  final LnIdentity identity;
  final List<LnPeer> peers;
  final LnQuality quality;
  final Set<LinkKind> activeKinds;
  final int queued;
  final List<ChatSummary> chats;
  final VoidCallback? onConnect;
  final void Function(ChatSummary)? onOpenChat;
  final VoidCallback? onSos;
  final VoidCallback? onOpenNetwork;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: <Widget>[
          SliverAppBar.large(
            title: const Text('LessNet'),
            actions: <Widget>[
              IconButton(
                icon: LnAvatar(
                  userId: identity.userId,
                  emoji: identity.avatarEmoji,
                  size: 32,
                ),
                onPressed: onOpenNetwork,
                tooltip: 'Perfil',
              ),
              const SizedBox(width: LnSpace.sm),
            ],
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(LnSpace.lg, 0, LnSpace.lg, LnSpace.lg),
            sliver: SliverList(
              delegate: SliverChildListDelegate(<Widget>[
                LnNetworkCard(
                  peerCount: peers.length,
                  quality: quality,
                  kinds: activeKinds,
                  queued: queued,
                  onTap: onOpenNetwork,
                ),
                const SizedBox(height: LnSpace.lg),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: FilledButton.icon(
                        icon: const Icon(Icons.add_link_rounded),
                        label: const Text('Conectar'),
                        onPressed: onConnect,
                      ),
                    ),
                    const SizedBox(width: LnSpace.md),
                    SizedBox(
                      height: 48,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: LnSemantic.sos,
                          foregroundColor: LnSemantic.sosOn,
                        ),
                        icon: const Icon(Icons.emergency_rounded),
                        label: const Text('SOS'),
                        onPressed: onSos,
                      ),
                    ),
                  ],
                ),
                if (peers.isNotEmpty) ...<Widget>[
                  LnSectionHeader('En la red · ${peers.length}'),
                  Card(
                    child: Column(
                      children: <Widget>[
                        for (var i = 0; i < peers.length; i++) ...<Widget>[
                          if (i > 0) const Divider(height: 1, indent: 72),
                          LnPeerTile(
                            peer: peers[i],
                            quality: quality,
                            kind: activeKinds.isEmpty ? null : activeKinds.first,
                            subtitle: peers[i].isDirect
                                ? 'Directo'
                                : 'A través de ${peers[i].hops} saltos',
                            onTap: onOpenNetwork,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                const LnSectionHeader('Conversaciones'),
                if (chats.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: LnSpace.xxl),
                    child: LnEmptyState(
                      icon: Icons.forum_rounded,
                      title: 'Todavía no hay mensajes',
                      message: 'Conéctate con alguien cerca para empezar a hablar sin internet.',
                      action: FilledButton.icon(
                        icon: const Icon(Icons.add_link_rounded),
                        label: const Text('Conectar'),
                        onPressed: onConnect,
                      ),
                    ),
                  )
                else
                  Card(
                    child: Column(
                      children: <Widget>[
                        for (var i = 0; i < chats.length; i++) ...<Widget>[
                          if (i > 0) const Divider(height: 1, indent: 72),
                          _ChatRow(
                            summary: chats[i],
                            onTap: () => onOpenChat?.call(chats[i]),
                          ),
                        ],
                      ],
                    ),
                  ),
                const SizedBox(height: LnSpace.huge),
              ]),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: onConnect,
        icon: const Icon(Icons.person_add_alt_rounded),
        label: const Text('Nuevo chat'),
      ),
    );
  }
}

class _ChatRow extends StatelessWidget {
  const _ChatRow({required this.summary, this.onTap});

  final ChatSummary summary;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;

    return ListTile(
      onTap: onTap,
      leading: summary.isGroup
          ? CircleAvatar(
              radius: 22,
              backgroundColor: cs.tertiaryContainer,
              child: Icon(Icons.public_rounded, color: cs.onTertiaryContainer, size: 22),
            )
          : LnAvatar(userId: summary.id, emoji: summary.emoji),
      title: Text(summary.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Row(
        children: <Widget>[
          if (summary.queued > 0) ...<Widget>[
            Icon(Icons.schedule_rounded, size: 13, color: LnSemantic.warn(cs)),
            const SizedBox(width: LnSpace.xs),
          ] else if (summary.via != null) ...<Widget>[
            LnTransportChip(kind: summary.via!, compact: true),
            const SizedBox(width: LnSpace.xs),
          ],
          Expanded(
            child: Text(summary.preview, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Text(
            '${summary.time.hour.toString().padLeft(2, '0')}:'
            '${summary.time.minute.toString().padLeft(2, '0')}',
            style: t.labelSmall?.copyWith(
              color: summary.unread > 0 ? cs.primary : cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: LnSpace.xs),
          if (summary.unread > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(color: cs.primary, borderRadius: LnShape.rFull),
              constraints: const BoxConstraints(minWidth: 20),
              child: Text(
                '${summary.unread}',
                textAlign: TextAlign.center,
                style: t.labelSmall?.copyWith(
                  color: cs.onPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          else
            const SizedBox(height: 18),
        ],
      ),
    );
  }
}

// ─────────────────────────── CHAT ───────────────────────────

class LnChatView extends StatelessWidget {
  const LnChatView({
    super.key,
    required this.title,
    required this.messages,
    required this.quality,
    this.subtitle,
    this.emoji = '🙂',
    this.peerId = '',
    this.via,
    this.isGroup = false,
    this.queued = 0,
    this.composer,
    this.transfer,
    this.onAttach,
    this.onSend,
    this.onBack,
  });

  final String title;
  final String? subtitle;
  final String emoji;
  final String peerId;
  final List<ChatBubbleData> messages;
  final LnQuality quality;
  final LinkKind? via;
  final bool isGroup;
  final int queued;
  final TextEditingController? composer;
  final Widget? transfer;
  final VoidCallback? onAttach;
  final VoidCallback? onSend;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        leading: onBack == null
            ? null
            : IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: onBack),
        titleSpacing: 0,
        title: Row(
          children: <Widget>[
            isGroup
                ? CircleAvatar(
                    radius: 18,
                    backgroundColor: cs.tertiaryContainer,
                    child: Icon(Icons.public_rounded,
                        color: cs.onTertiaryContainer, size: 18),
                  )
                : LnAvatar(userId: peerId, emoji: emoji, size: 36),
            const SizedBox(width: LnSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Text(title, style: t.titleMedium, overflow: TextOverflow.ellipsis),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: t.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: LnSpace.sm),
            child: Center(child: LnSignalBars(quality: quality, size: 20)),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          if (queued > 0)
            Container(
              width: double.infinity,
              color: LnSemantic.warnContainer(cs),
              padding: const EdgeInsets.symmetric(
                  horizontal: LnSpace.lg, vertical: LnSpace.sm),
              child: Row(
                children: <Widget>[
                  Icon(Icons.schedule_rounded, size: 16, color: LnSemantic.warn(cs)),
                  const SizedBox(width: LnSpace.sm),
                  Expanded(
                    child: Text(
                      '$queued ${queued == 1 ? 'mensaje' : 'mensajes'} en cola. '
                      'Se entregan solos al reconectar.',
                      style: t.labelMedium?.copyWith(color: LnSemantic.warn(cs)),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: messages.isEmpty
                ? const LnEmptyState(
                    icon: Icons.chat_bubble_outline_rounded,
                    title: 'Sin mensajes aún',
                    message: 'Todo lo que escribas viaja directo entre los teléfonos, '
                        'sin pasar por internet.',
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: LnSpace.md),
                    itemCount: messages.length,
                    itemBuilder: (context, i) {
                      final m = messages[i];
                      return LnMessageBubble(
                        text: m.text,
                        mine: m.mine,
                        time: m.time,
                        status: m.status,
                        senderId: m.mine ? null : m.senderId,
                        senderName: isGroup && !m.mine ? m.senderName : null,
                        senderEmoji: m.senderEmoji,
                        viaKind: m.via,
                      );
                    },
                  ),
          ),
          if (transfer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  LnSpace.lg, 0, LnSpace.lg, LnSpace.sm),
              child: transfer!,
            ),
          _Composer(controller: composer, onAttach: onAttach, onSend: onSend),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({this.controller, this.onAttach, this.onSend});

  final TextEditingController? controller;
  final VoidCallback? onAttach;
  final VoidCallback? onSend;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            LnSpace.md, LnSpace.sm, LnSpace.md, LnSpace.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            IconButton.filledTonal(
              icon: const Icon(Icons.add_rounded),
              onPressed: onAttach,
              tooltip: 'Adjuntar',
            ),
            const SizedBox(width: LnSpace.sm),
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Mensaje',
                  contentPadding: EdgeInsets.symmetric(
                      horizontal: LnSpace.lg, vertical: LnSpace.md),
                  border: OutlineInputBorder(
                    borderRadius: LnShape.rXl,
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: LnShape.rXl,
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: LnSpace.sm),
            IconButton.filled(
              icon: const Icon(Icons.send_rounded),
              onPressed: onSend,
              tooltip: 'Enviar',
              style: IconButton.styleFrom(
                backgroundColor: cs.primary,
                foregroundColor: cs.onPrimary,
                minimumSize: const Size(48, 48),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ────────────────────── NETWORK DIAGNOSTICS ──────────────────

/// Shows every live link, its score, and which one is carrying
/// traffic — so "por qué va lento" has an answer in the app.
class LnNetworkView extends StatelessWidget {
  const LnNetworkView({
    super.key,
    required this.ranked,
    required this.preference,
    required this.onPreferenceChanged,
    this.activeLinkId,
    this.onBack,
  });

  final List<({LnLink link, double score})> ranked;
  final TransportPreference preference;
  final ValueChanged<TransportPreference> onPreferenceChanged;
  final String? activeLinkId;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        leading: onBack == null
            ? null
            : IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: onBack),
        title: const Text('Red'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(LnSpace.lg),
        children: <Widget>[
          const LnSectionHeader('Medio de conexión'),
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
            selected: <TransportPreference>{preference},
            onSelectionChanged: (s) => onPreferenceChanged(s.first),
          ),
          const SizedBox(height: LnSpace.md),
          Text(
            preference.description,
            style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          const LnSectionHeader('Enlaces activos'),
          if (ranked.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: LnSpace.xxl),
              child: LnEmptyState(
                icon: Icons.link_off_rounded,
                title: 'Sin enlaces activos',
                message: 'Conéctate con alguien para ver aquí la calidad de cada medio.',
              ),
            )
          else
            Card(
              child: Column(
                children: <Widget>[
                  for (var i = 0; i < ranked.length; i++) ...<Widget>[
                    if (i > 0) const Divider(height: 1, indent: LnSpace.lg),
                    _LinkRow(
                      entry: ranked[i],
                      active: ranked[i].link.id == activeLinkId,
                      best: i == 0,
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({required this.entry, required this.active, required this.best});

  final ({LnLink link, double score}) entry;
  final bool active;
  final bool best;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final link = entry.link;

    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? cs.primaryContainer : cs.surfaceContainerHighest,
          borderRadius: LnShape.rMd,
        ),
        child: Icon(
          switch (link.kind) {
            LinkKind.ble => Icons.bluetooth_rounded,
            LinkKind.lan => Icons.wifi_rounded,
            LinkKind.wifiDirect => Icons.wifi_tethering_rounded,
            LinkKind.hotspot => Icons.router_rounded,
          },
          size: 20,
          color: active ? cs.onPrimaryContainer : cs.onSurfaceVariant,
        ),
      ),
      title: Row(
        children: <Widget>[
          Text(link.kind.label),
          if (active) ...<Widget>[
            const SizedBox(width: LnSpace.sm),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: LnSpace.sm, vertical: 1),
              decoration: BoxDecoration(
                color: LnSemantic.okContainer(cs),
                borderRadius: LnShape.rFull,
              ),
              child: Text(
                'EN USO',
                style: t.labelSmall?.copyWith(
                  color: LnSemantic.ok(cs),
                  fontWeight: FontWeight.w700,
                  fontSize: 10,
                ),
              ),
            ),
          ],
        ],
      ),
      subtitle: Text(
        '${link.remoteName} · ${link.quality.label} · '
        'puntaje ${entry.score.toStringAsFixed(0)}',
      ),
      trailing: LnSignalBars(quality: link.quality),
    );
  }
}
