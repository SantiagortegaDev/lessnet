// ─────────────────────────────────────────────────────────────
// LessNet — Design tokens (Material 3 / Material You)
//
// Single source of truth for shape, spacing, motion and the
// semantic colours that are not part of the generated
// ColorScheme (link quality, message status, SOS).
// ─────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';

/// Seed colours offered in Profile → Apariencia.
/// Material You derives the whole scheme from one of these
/// (or from the wallpaper when dynamic colour is available).
class LnSeeds {
  const LnSeeds._();

  static const Color azul = Color(0xFF1B6EF3);
  static const Color verde = Color(0xFF106B45);
  static const Color naranja = Color(0xFFB0501B);
  static const Color violeta = Color(0xFF6750A4);
  static const Color rojo = Color(0xFFAB2B2B);
  static const Color cian = Color(0xFF00696E);

  static const Map<String, Color> all = <String, Color>{
    'azul': azul,
    'verde': verde,
    'naranja': naranja,
    'violeta': violeta,
    'rojo': rojo,
    'cian': cian,
  };

  static const Color fallback = azul;

  static Color byName(String? name) => all[name] ?? fallback;
}

/// MD3 shape scale.
class LnShape {
  const LnShape._();

  static const double none = 0;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 28;
  static const double full = 999;

  static const BorderRadius rXs = BorderRadius.all(Radius.circular(xs));
  static const BorderRadius rSm = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius rMd = BorderRadius.all(Radius.circular(md));
  static const BorderRadius rLg = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius rXl = BorderRadius.all(Radius.circular(xl));
  static const BorderRadius rFull = BorderRadius.all(Radius.circular(full));
}

/// 4dp spacing grid.
class LnSpace {
  const LnSpace._();

  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double huge = 48;
}

/// MD3 motion — emphasized easing set.
class LnMotion {
  const LnMotion._();

  static const Duration short = Duration(milliseconds: 150);
  static const Duration medium = Duration(milliseconds: 300);
  static const Duration long = Duration(milliseconds: 450);

  static const Curve emphasized = Cubic(0.2, 0.0, 0.0, 1.0);
  static const Curve emphasizedDecelerate = Cubic(0.05, 0.7, 0.1, 1.0);
  static const Curve emphasizedAccelerate = Cubic(0.3, 0.0, 0.8, 0.15);
  static const Curve standard = Cubic(0.2, 0.0, 0.0, 1.0);
}

/// Quality buckets shared by every transport, so the UI can render
/// signal strength the same way regardless of the underlying radio.
enum LnQuality { excelente, buena, debil, perdida }

extension LnQualityX on LnQuality {
  String get label => switch (this) {
        LnQuality.excelente => 'Excelente',
        LnQuality.buena => 'Buena',
        LnQuality.debil => 'Débil',
        LnQuality.perdida => 'Sin señal',
      };

  /// 0–4 filled bars.
  int get bars => switch (this) {
        LnQuality.excelente => 4,
        LnQuality.buena => 3,
        LnQuality.debil => 2,
        LnQuality.perdida => 0,
      };

  Color color(ColorScheme cs) => switch (this) {
        LnQuality.excelente => LnSemantic.ok(cs),
        LnQuality.buena => LnSemantic.ok(cs),
        LnQuality.debil => LnSemantic.warn(cs),
        LnQuality.perdida => cs.error,
      };
}

/// Semantic colours that MD3 does not generate for us.
/// Each one is derived from the active scheme so it stays legible
/// in light and dark, and against any seed the user picks.
class LnSemantic {
  const LnSemantic._();

  static Color ok(ColorScheme cs) =>
      cs.brightness == Brightness.dark ? const Color(0xFF7FD98F) : const Color(0xFF1B6B32);

  static Color okContainer(ColorScheme cs) =>
      cs.brightness == Brightness.dark ? const Color(0xFF12351C) : const Color(0xFFD5F3D9);

  static Color warn(ColorScheme cs) =>
      cs.brightness == Brightness.dark ? const Color(0xFFF2C15B) : const Color(0xFF7A5300);

  static Color warnContainer(ColorScheme cs) =>
      cs.brightness == Brightness.dark ? const Color(0xFF3A2E10) : const Color(0xFFFCEBC4);

  /// SOS is deliberately fixed — it must read as an alarm no matter
  /// which seed colour the user chose.
  static const Color sos = Color(0xFFD93025);
  static const Color sosOn = Color(0xFFFFFFFF);

  static Color sosContainer(ColorScheme cs) =>
      cs.brightness == Brightness.dark ? const Color(0xFF4A1310) : const Color(0xFFFFDAD5);
}

/// Delivery state of a chat message, surfaced in the bubble.
enum LnMsgStatus { pendiente, enviando, enviado, entregado, fallido }

extension LnMsgStatusX on LnMsgStatus {
  IconData get icon => switch (this) {
        LnMsgStatus.pendiente => Icons.schedule_rounded,
        LnMsgStatus.enviando => Icons.arrow_upward_rounded,
        LnMsgStatus.enviado => Icons.check_rounded,
        LnMsgStatus.entregado => Icons.done_all_rounded,
        LnMsgStatus.fallido => Icons.error_outline_rounded,
      };

  String get label => switch (this) {
        LnMsgStatus.pendiente => 'En cola',
        LnMsgStatus.enviando => 'Enviando',
        LnMsgStatus.enviado => 'Enviado',
        LnMsgStatus.entregado => 'Entregado',
        LnMsgStatus.fallido => 'Falló',
      };

  static LnMsgStatus fromName(String? v) =>
      LnMsgStatus.values.firstWhere((e) => e.name == v, orElse: () => LnMsgStatus.enviado);
}

/// Deterministic avatar colour for a user id, drawn from the
/// active scheme's tonal range so avatars never clash with the theme.
class LnAvatarColors {
  const LnAvatarColors._();

  static const List<int> _hues = <int>[0, 40, 90, 140, 190, 240, 280, 320];

  static Color forId(String id, ColorScheme cs) {
    if (id.isEmpty) return cs.primaryContainer;
    var h = 0;
    for (final unit in id.codeUnits) {
      h = (h * 31 + unit) & 0x7fffffff;
    }
    final hue = _hues[h % _hues.length].toDouble();
    final hsl = HSLColor.fromAHSL(
      1,
      hue,
      cs.brightness == Brightness.dark ? 0.32 : 0.45,
      cs.brightness == Brightness.dark ? 0.34 : 0.76,
    );
    return hsl.toColor();
  }

  static Color onColor(Color background) =>
      ThemeData.estimateBrightnessForColor(background) == Brightness.dark
          ? Colors.white
          : Colors.black87;
}
