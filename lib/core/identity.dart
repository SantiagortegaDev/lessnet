// ─────────────────────────────────────────────────────────────
// LessNet — device / user identity
//
// Until now the app identified peers by BLE MAC or advertised
// name, which changes between sessions and cannot survive a
// transport switch. A LessNet user now has one stable id that is
// the same over BLE, LAN, Wi-Fi Direct and hotspot, so a chat
// thread follows the person rather than the radio.
// ─────────────────────────────────────────────────────────────
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../net/packet.dart';

const List<String> kAvatarEmojis = <String>[
  '🙂', '😎', '🦊', '🐺', '🦉', '🐢', '🐝', '🌵',
  '⛰️', '🌊', '🔥', '⚡', '🧭', '🎒', '🛰️', '📡',
];

class LnIdentity extends ChangeNotifier {
  LnIdentity._();

  static final LnIdentity instance = LnIdentity._();

  static const _kUserId = 'ln_user_id';
  static const _kName = 'ln_display_name';
  static const _kEmoji = 'ln_avatar_emoji';
  static const _kSeed = 'ln_seed_name';
  static const _kThemeMode = 'ln_theme_mode';
  static const _kDynamicColor = 'ln_dynamic_color';

  String _userId = '';
  String _displayName = '';
  String _avatarEmoji = '🙂';
  String _seedName = 'azul';
  ThemeMode _themeMode = ThemeMode.system;
  bool _dynamicColor = true;
  bool _loaded = false;

  String get userId => _userId;
  String get displayName => _displayName.isEmpty ? 'Usuario $_shortId' : _displayName;
  String get rawDisplayName => _displayName;
  String get avatarEmoji => _avatarEmoji;
  String get seedName => _seedName;
  ThemeMode get themeMode => _themeMode;
  bool get dynamicColor => _dynamicColor;
  bool get isLoaded => _loaded;

  String get _shortId => _userId.isEmpty ? '?' : _userId.substring(0, 4);

  /// Short, human-quotable form of the id, shown in Profile and used
  /// to disambiguate two people with the same display name.
  String get shortCode => _userId.isEmpty ? '----' : _userId.substring(0, 4).toUpperCase();

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    _userId = p.getString(_kUserId) ?? '';
    if (_userId.isEmpty) {
      _userId = newUserId();
      await p.setString(_kUserId, _userId);
    }
    _displayName = p.getString(_kName) ?? '';
    _avatarEmoji = p.getString(_kEmoji) ?? kAvatarEmojis.first;
    _seedName = p.getString(_kSeed) ?? 'azul';
    _dynamicColor = p.getBool(_kDynamicColor) ?? true;
    _themeMode = switch (p.getString(_kThemeMode)) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    _loaded = true;
    notifyListeners();
  }

  Future<void> setDisplayName(String name) async {
    final trimmed = name.trim();
    if (trimmed == _displayName) return;
    _displayName = trimmed;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kName, trimmed);
    notifyListeners();
  }

  Future<void> setAvatarEmoji(String emoji) async {
    if (emoji == _avatarEmoji) return;
    _avatarEmoji = emoji;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kEmoji, emoji);
    notifyListeners();
  }

  Future<void> setSeedName(String name) async {
    if (name == _seedName) return;
    _seedName = name;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kSeed, name);
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (mode == _themeMode) return;
    _themeMode = mode;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kThemeMode, mode.name);
    notifyListeners();
  }

  Future<void> setDynamicColor(bool enabled) async {
    if (enabled == _dynamicColor) return;
    _dynamicColor = enabled;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kDynamicColor, enabled);
    notifyListeners();
  }

  /// Payload broadcast in `hello` packets and embedded in pairing QRs.
  Map<String, dynamic> toProfile() => <String, dynamic>{
        'id': _userId,
        'name': displayName,
        'emoji': _avatarEmoji,
        'v': 1,
      };
}

/// A peer as the UI knows it: identity plus how we can reach them.
class LnPeer {
  final String userId;
  final String name;
  final String emoji;
  final int hops;
  final String? linkKindLabel;

  const LnPeer({
    required this.userId,
    required this.name,
    this.emoji = '🙂',
    this.hops = 1,
    this.linkKindLabel,
  });

  String get shortCode => userId.length >= 4 ? userId.substring(0, 4).toUpperCase() : userId;

  bool get isDirect => hops <= 1;

  static LnPeer fromProfile(Map<String, dynamic> m, {int hops = 1, String? via}) {
    final id = (m['id'] as String?) ?? '';
    return LnPeer(
      userId: id,
      name: (m['name'] as String?)?.trim().isNotEmpty == true
          ? (m['name'] as String).trim()
          : 'Usuario ${id.isEmpty ? '?' : id.substring(0, id.length.clamp(0, 4))}',
      emoji: (m['emoji'] as String?) ?? '🙂',
      hops: hops,
      linkKindLabel: via,
    );
  }
}
