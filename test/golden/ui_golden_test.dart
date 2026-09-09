// Renders the real widget tree to PNG files so the new Material 3
// design can be reviewed without a device. Run with:
//
//   flutter test --update-goldens test/golden/ui_golden_test.dart
//
// These are review artefacts, not regression assertions: fonts differ
// between machines, so they are excluded from the normal test run.
@Tags(<String>['golden'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lessnet/core/identity.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lessnet/design/theme.dart';
import 'package:lessnet/design/tokens.dart';
import 'package:lessnet/net/link.dart';
import 'package:lessnet/net/link_manager.dart';
import 'package:lessnet/pairing/pair_code.dart';
import 'package:lessnet/ui/components.dart';
import 'package:lessnet/ui/connect.dart';
import 'package:lessnet/ui/screens.dart';

const Size kPhone = Size(412, 892); // Pixel 8 logical size

Future<void> _loadFonts() async {
  const materialFonts = '/opt/flutter/bin/cache/artifacts/material_fonts';
  const emojiPath = '/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf';

  Future<void> load(String family, List<String> paths) async {
    final present = paths.where((p) => File(p).existsSync()).toList();
    if (present.isEmpty) return;
    final loader = FontLoader(family);
    for (final p in present) {
      loader.addFont(
        Future<ByteData>.value(File(p).readAsBytesSync().buffer.asByteData()),
      );
    }
    await loader.load();
  }

  // The real Material icon set, not the subset fixture — otherwise
  // every icon renders as a tofu box.
  await load('MaterialIcons', <String>['$materialFonts/MaterialIcons-Regular.otf']);

  // Roboto is the actual Pixel/Android system font, so the render
  // matches what ships on device.
  await load('Roboto', <String>[
    '$materialFonts/Roboto-Regular.ttf',
    '$materialFonts/Roboto-Medium.ttf',
    '$materialFonts/Roboto-Bold.ttf',
  ]);

  await load('Noto Color Emoji', <String>[emojiPath]);
}

class _FakeLink extends LnLink {
  _FakeLink(this.id, this.kind, this.remoteName, this._signal);

  @override
  final String id;
  @override
  final LinkKind kind;
  @override
  final String remoteName;
  final int _signal;
  final LinkStats _stats = LinkStats();

  @override
  String get remoteUserId => remoteName;
  @override
  bool get isUp => true;
  @override
  int get signal => _signal;
  @override
  LinkStats get stats => _stats;
  @override
  Stream<String> get incoming => const Stream<String>.empty();
  @override
  Future<bool> send(String line) async => true;
  @override
  Future<void> close() async {}
}

LnIdentity _identity() {
  final id = LnIdentity.instance;
  return id;
}

Widget _wrap(Widget child, {Brightness brightness = Brightness.light, Color? seed}) {
  final scheme = ColorScheme.fromSeed(
    seedColor: seed ?? LnSeeds.azul,
    brightness: brightness,
  );
  final theme = buildLessNetTheme(scheme);
  return MediaQuery(
    data: const MediaQueryData(size: kPhone, devicePixelRatio: 1),
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme.copyWith(
        // On device Android resolves these automatically; the test
        // runner needs them named explicitly.
        textTheme: theme.textTheme.apply(
          fontFamily: 'Roboto',
          fontFamilyFallback: const <String>['Noto Color Emoji'],
        ),
      ),
      home: child,
    ),
  );
}

final DateTime _t = DateTime(2026, 9, 8, 14, 32);

List<ChatSummary> _chats() => <ChatSummary>[
      ChatSummary(
        id: '__global__',
        title: 'Chat Global',
        preview: 'Camila: llegamos al punto de encuentro',
        time: _t,
        unread: 3,
        isGroup: true,
        via: LinkKind.wifiDirect,
      ),
      ChatSummary(
        id: 'Kd8fQ2mX1a',
        title: 'Camila Restrepo',
        emoji: '🦊',
        preview: 'Te mando la foto del mapa',
        time: _t.subtract(const Duration(minutes: 8)),
        unread: 1,
        via: LinkKind.lan,
      ),
      ChatSummary(
        id: 'Zt4bN9pR7c',
        title: 'Andrés Gómez',
        emoji: '🧭',
        preview: 'Voy en camino, sin señal aquí',
        time: _t.subtract(const Duration(minutes: 41)),
        via: LinkKind.ble,
      ),
      ChatSummary(
        id: 'Wq2vC5hL8d',
        title: 'Puesto de salud',
        emoji: '🚑',
        preview: 'Copiado, esperamos',
        time: _t.subtract(const Duration(hours: 2)),
        queued: 2,
      ),
    ];

List<LnPeer> _peers() => const <LnPeer>[
      LnPeer(userId: 'Kd8fQ2mX1a', name: 'Camila Restrepo', emoji: '🦊'),
      LnPeer(userId: 'Zt4bN9pR7c', name: 'Andrés Gómez', emoji: '🧭', hops: 2),
      LnPeer(userId: 'Wq2vC5hL8d', name: 'Puesto de salud', emoji: '🚑', hops: 3),
    ];

List<ChatBubbleData> _messages() => <ChatBubbleData>[
      ChatBubbleData(
        id: '1',
        text: '¿Ya llegaron al puente? Aquí no hay señal de celular.',
        mine: false,
        time: _t.subtract(const Duration(minutes: 12)),
        senderId: 'Kd8fQ2mX1a',
        senderName: 'Camila',
        senderEmoji: '🦊',
        via: LinkKind.lan,
      ),
      ChatBubbleData(
        id: '2',
        text: 'Sí, estamos en el puente. Vamos hacia el puesto de salud.',
        mine: true,
        time: _t.subtract(const Duration(minutes: 11)),
        status: LnMsgStatus.entregado,
        via: LinkKind.lan,
      ),
      ChatBubbleData(
        id: '3',
        text: 'Te paso la ubicación exacta y la foto del mapa.',
        mine: true,
        time: _t.subtract(const Duration(minutes: 10)),
        status: LnMsgStatus.entregado,
        via: LinkKind.lan,
      ),
      ChatBubbleData(
        id: '4',
        text: 'Perfecto. Andrés viene detrás, va por Bluetooth nada más.',
        mine: false,
        time: _t.subtract(const Duration(minutes: 4)),
        senderId: 'Kd8fQ2mX1a',
        senderName: 'Camila',
        senderEmoji: '🦊',
        via: LinkKind.ble,
      ),
      ChatBubbleData(
        id: '5',
        text: 'Copiado. Salimos en 5 minutos.',
        mine: true,
        time: _t,
        status: LnMsgStatus.pendiente,
      ),
    ];

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'ln_user_id': 'Nv7pR2kT9m',
      'ln_display_name': 'Santiago Ortega',
      'ln_avatar_emoji': '🛰️',
    });
    await _loadFonts();
    await _identity().load();
  });

  /// [settle] must be false for screens containing an indeterminate
  /// progress indicator: those animate forever, so pumpAndSettle never
  /// returns. Fixed pumps give a deterministic frame instead.
  Future<void> shoot(
    WidgetTester tester,
    Widget w,
    String name, {
    bool settle = true,
  }) async {
    tester.view.physicalSize = kPhone;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(w);
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('shots/' + name + '.png'));
  }

  testWidgets('home (claro)', (t) async {
    await shoot(
      t,
      _wrap(LnHomeView(
        identity: _identity(),
        peers: _peers(),
        quality: LnQuality.excelente,
        activeKinds: const <LinkKind>{LinkKind.wifiDirect, LinkKind.ble},
        queued: 2,
        chats: _chats(),
        onConnect: () {},
        onSos: () {},
        onOpenNetwork: () {},
        onOpenChat: (_) {},
      )),
      'home_light',
    );
  });

  testWidgets('home (oscuro)', (t) async {
    await shoot(
      t,
      _wrap(
        LnHomeView(
          identity: _identity(),
          peers: _peers(),
          quality: LnQuality.excelente,
          activeKinds: const <LinkKind>{LinkKind.wifiDirect, LinkKind.ble},
          queued: 2,
          chats: _chats(),
          onConnect: () {},
          onSos: () {},
          onOpenNetwork: () {},
          onOpenChat: (_) {},
        ),
        brightness: Brightness.dark,
      ),
      'home_dark',
    );
  });

  testWidgets('conectar — métodos', (t) async {
    await shoot(
      t,
      _wrap(Scaffold(
        appBar: AppBar(title: const Text('Conectar')),
        body: SingleChildScrollView(
          child: ConnectSheet(
            methods: const <ConnectMethod>[
              ConnectMethod.qr,
              ConnectMethod.lan,
              ConnectMethod.cerca,
              ConnectMethod.codigo,
              ConnectMethod.wifiDirect,
              ConnectMethod.hotspot,
            ],
            onPick: (_) {},
          ),
        ),
      )),
      'connect_methods',
    );
  });

  testWidgets('código y QR', (t) async {
    await shoot(
      t,
      _wrap(PairCodePage(
        code: PairCode.tryParse('K7M2QX')!,
        identity: _identity(),
        onJoin: (_) {},
        onScanQr: () {},
        status: 'Buscando por Bluetooth y Wi-Fi al mismo tiempo…',
      )),
      'pair_code',
      settle: false,
    );
  });

  testWidgets('chat', (t) async {
    await shoot(
      t,
      _wrap(LnChatView(
        title: 'Camila Restrepo',
        subtitle: 'Wi-Fi (LAN) · directo',
        emoji: '🦊',
        peerId: 'Kd8fQ2mX1a',
        messages: _messages(),
        quality: LnQuality.excelente,
        via: LinkKind.lan,
        queued: 1,
        onBack: () {},
        onAttach: () {},
        onSend: () {},
        transfer: const LnTransferTile(
          fileName: 'mapa-ruta-norte.jpg',
          fraction: 0.62,
          incoming: false,
          detail: '1,2 MB de 1,9 MB · Wi-Fi Direct · 38 s restantes',
        ),
      )),
      'chat',
    );
  });

  testWidgets('chat (oscuro)', (t) async {
    await shoot(
      t,
      _wrap(
        LnChatView(
          title: 'Chat Global',
          subtitle: '4 dispositivos · mejor medio: Wi-Fi Direct',
          isGroup: true,
          messages: _messages(),
          quality: LnQuality.buena,
          via: LinkKind.wifiDirect,
          onBack: () {},
          onAttach: () {},
          onSend: () {},
        ),
        brightness: Brightness.dark,
      ),
      'chat_dark',
    );
  });

  testWidgets('red — enlaces y puntajes', (t) async {
    final links = <_FakeLink>[
      _FakeLink('lan-1', LinkKind.lan, 'Camila Restrepo', 88),
      _FakeLink('p2p-1', LinkKind.wifiDirect, 'Andrés Gómez', 61),
      _FakeLink('ble-1', LinkKind.ble, 'Puesto de salud', -74),
    ];
    final ranked = links
        .map((l) => (link: l as LnLink, score: scoreLink(l)))
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    await shoot(
      t,
      _wrap(LnNetworkView(
        ranked: ranked,
        preference: TransportPreference.automatico,
        onPreferenceChanged: (_) {},
        activeLinkId: ranked.first.link.id,
        onBack: () {},
      )),
      'network',
    );
  });

  testWidgets('cerca de mí', (t) async {
    await shoot(
      t,
      _wrap(NearbyPage(
        scanning: true,
        onConnect: (_) {},
        onRescan: () {},
        peers: const <DiscoveredPeer>[
          DiscoveredPeer(
            peer: LnPeer(userId: 'Kd8fQ2mX1a', name: 'Camila Restrepo', emoji: '🦊'),
            kind: LinkKind.ble,
            quality: LnQuality.excelente,
            signal: -48,
            sameCode: true,
          ),
          DiscoveredPeer(
            peer: LnPeer(userId: 'Zt4bN9pR7c', name: 'Andrés Gómez', emoji: '🧭'),
            kind: LinkKind.ble,
            quality: LnQuality.buena,
            signal: -71,
          ),
          DiscoveredPeer(
            peer: LnPeer(userId: 'Wq2vC5hL8d', name: 'Puesto de salud', emoji: '🚑'),
            kind: LinkKind.lan,
            quality: LnQuality.excelente,
            signal: 90,
          ),
        ],
      )),
      'nearby',
      settle: false,
    );
  });

  // One wide canvas with the key screens side by side, for sharing.
  testWidgets('showcase', (tester) async {
    const shot = Size(412, 892);
    const gap = 28.0;
    const pad = 36.0;
    const label = 54.0;
    final panels = <String, Widget>{
      'Inicio': LnHomeView(
        identity: _identity(),
        peers: _peers(),
        quality: LnQuality.excelente,
        activeKinds: const <LinkKind>{LinkKind.wifiDirect, LinkKind.ble},
        queued: 2,
        chats: _chats(),
        onConnect: () {},
        onSos: () {},
        onOpenNetwork: () {},
        onOpenChat: (_) {},
      ),
      'Conectar — 6 métodos': Scaffold(
        appBar: AppBar(title: const Text('Conectar')),
        body: SingleChildScrollView(
          child: ConnectSheet(
            methods: const <ConnectMethod>[
              ConnectMethod.qr,
              ConnectMethod.lan,
              ConnectMethod.cerca,
              ConnectMethod.codigo,
              ConnectMethod.wifiDirect,
              ConnectMethod.hotspot,
            ],
            onPick: (_) {},
          ),
        ),
      ),
      'Código + QR': PairCodePage(
        code: PairCode.tryParse('K7M2QX')!,
        identity: _identity(),
        onJoin: (_) {},
        onScanQr: () {},
      ),
      'Chat': LnChatView(
        title: 'Camila Restrepo',
        subtitle: 'Wi-Fi (LAN) · directo',
        emoji: '🦊',
        peerId: 'Kd8fQ2mX1a',
        messages: _messages(),
        quality: LnQuality.excelente,
        via: LinkKind.lan,
        queued: 1,
        onBack: () {},
        onAttach: () {},
        onSend: () {},
        transfer: const LnTransferTile(
          fileName: 'mapa-ruta-norte.jpg',
          fraction: 0.62,
          incoming: false,
          detail: '1,2 MB de 1,9 MB · Wi-Fi Direct · 38 s restantes',
        ),
      ),
      'Red — mejor medio': LnNetworkView(
        ranked: <({LnLink link, double score})>[
          for (final l in <_FakeLink>[
            _FakeLink('lan-1', LinkKind.lan, 'Camila Restrepo', 88),
            _FakeLink('p2p-1', LinkKind.wifiDirect, 'Andrés Gómez', 61),
            _FakeLink('ble-1', LinkKind.ble, 'Puesto de salud', -74),
          ])
            (link: l as LnLink, score: scoreLink(l)),
        ]..sort((a, b) => b.score.compareTo(a.score)),
        preference: TransportPreference.automatico,
        onPreferenceChanged: (_) {},
        activeLinkId: 'p2p-1',
        onBack: () {},
      ),
    };

    final scheme = ColorScheme.fromSeed(seedColor: LnSeeds.azul);
    final theme = buildLessNetTheme(scheme).copyWith(
      textTheme: buildLessNetTheme(scheme).textTheme.apply(
            fontFamily: 'Roboto',
            fontFamilyFallback: const <String>['Noto Color Emoji'],
          ),
    );

    final width = pad * 2 + shot.width * panels.length + gap * (panels.length - 1);
    final height = pad * 2 + shot.height + label;
    final canvas = Size(width, height);

    tester.view.physicalSize = canvas;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(size: canvas, devicePixelRatio: 1),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Container(
            color: scheme.surfaceContainerLowest,
            padding: const EdgeInsets.all(pad),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                for (final e in panels.entries) ...<Widget>[
                  if (e.key != panels.keys.first) const SizedBox(width: gap),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14, left: 4),
                        child: Text(
                          e.key,
                          style: TextStyle(
                            fontFamily: 'Roboto',
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: scheme.onSurface,
                          ),
                        ),
                      ),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(28),
                        child: SizedBox(
                          width: shot.width,
                          height: shot.height,
                          child: MediaQuery(
                            data: const MediaQueryData(size: shot, devicePixelRatio: 1),
                            child: MaterialApp(
                              debugShowCheckedModeBanner: false,
                              theme: theme,
                              home: e.value,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await expectLater(
      find.byType(Directionality).first,
      matchesGoldenFile('shots/showcase.png'),
    );
  });
}
