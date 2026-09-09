// ─────────────────────────────────────────────────────────────
// LessNet — Material 3 theme
//
// Builds the full ThemeData from a ColorScheme so every screen
// gets Pixel-style components (rounded, tonal, elevation by
// surface colour rather than shadow) without per-widget styling.
// ─────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tokens.dart';

ThemeData buildLessNetTheme(ColorScheme scheme) {
  final isDark = scheme.brightness == Brightness.dark;
  final base = ThemeData(colorScheme: scheme, useMaterial3: true);
  final text = _typography(base.textTheme, scheme);

  return base.copyWith(
    scaffoldBackgroundColor: scheme.surface,
    textTheme: text,
    splashFactory: InkSparkle.splashFactory,
    visualDensity: VisualDensity.standard,

    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: scheme.surfaceTint,
      elevation: 0,
      scrolledUnderElevation: 3,
      centerTitle: false,
      // Deliberately not setting titleTextStyle: it would override the
      // expanded headline of AppBar.large / AppBar.medium and flatten
      // them back to a small app bar.
      systemOverlayStyle: isDark
          ? SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent)
          : SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent),
    ),

    cardTheme: CardThemeData(
      color: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: const RoundedRectangleBorder(borderRadius: LnShape.rLg),
      clipBehavior: Clip.antiAlias,
    ),

    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      indicatorColor: scheme.secondaryContainer,
      elevation: 0,
      height: 80,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return text.labelMedium?.copyWith(
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          size: 24,
          color: selected ? scheme.onSecondaryContainer : scheme.onSurfaceVariant,
        );
      }),
    ),

    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: scheme.surface,
      indicatorColor: scheme.secondaryContainer,
      selectedIconTheme: IconThemeData(color: scheme.onSecondaryContainer),
      unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 48),
        padding: const EdgeInsets.symmetric(horizontal: LnSpace.xl, vertical: LnSpace.md),
        shape: const RoundedRectangleBorder(borderRadius: LnShape.rFull),
        textStyle: text.labelLarge,
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 48),
        padding: const EdgeInsets.symmetric(horizontal: LnSpace.xl, vertical: LnSpace.md),
        shape: const RoundedRectangleBorder(borderRadius: LnShape.rFull),
        side: BorderSide(color: scheme.outlineVariant),
        textStyle: text.labelLarge,
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 44),
        shape: const RoundedRectangleBorder(borderRadius: LnShape.rFull),
        textStyle: text.labelLarge,
      ),
    ),

    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: const RoundedRectangleBorder(borderRadius: LnShape.rFull),
      ),
    ),

    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primaryContainer,
      foregroundColor: scheme.onPrimaryContainer,
      elevation: 3,
      focusElevation: 3,
      hoverElevation: 4,
      highlightElevation: 3,
      shape: const RoundedRectangleBorder(borderRadius: LnShape.rLg),
      extendedTextStyle: text.labelLarge,
    ),

    chipTheme: ChipThemeData(
      backgroundColor: Colors.transparent,
      selectedColor: scheme.secondaryContainer,
      side: BorderSide(color: scheme.outlineVariant),
      shape: const RoundedRectangleBorder(borderRadius: LnShape.rSm),
      labelStyle: text.labelLarge,
      padding: const EdgeInsets.symmetric(horizontal: LnSpace.md, vertical: LnSpace.sm),
      showCheckmark: true,
      checkmarkColor: scheme.onSecondaryContainer,
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: LnSpace.lg, vertical: LnSpace.lg),
      border: const OutlineInputBorder(
        borderRadius: LnShape.rMd,
        borderSide: BorderSide.none,
      ),
      enabledBorder: const OutlineInputBorder(
        borderRadius: LnShape.rMd,
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: LnShape.rMd,
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: LnShape.rMd,
        borderSide: BorderSide(color: scheme.error, width: 2),
      ),
      hintStyle: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
      labelStyle: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
      prefixIconColor: scheme.onSurfaceVariant,
      suffixIconColor: scheme.onSurfaceVariant,
    ),

    listTileTheme: ListTileThemeData(
      shape: const RoundedRectangleBorder(borderRadius: LnShape.rLg),
      contentPadding: const EdgeInsets.symmetric(horizontal: LnSpace.lg, vertical: LnSpace.xs),
      iconColor: scheme.onSurfaceVariant,
      titleTextStyle: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
      subtitleTextStyle: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
    ),

    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: const RoundedRectangleBorder(borderRadius: LnShape.rXl),
      titleTextStyle: text.headlineSmall,
      contentTextStyle: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
    ),

    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      modalElevation: 0,
      showDragHandle: true,
      dragHandleColor: scheme.onSurfaceVariant.withValues(alpha: 0.4),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(LnShape.xl)),
      ),
    ),

    snackBarTheme: SnackBarThemeData(
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: text.bodyMedium?.copyWith(color: scheme.onInverseSurface),
      actionTextColor: scheme.inversePrimary,
      behavior: SnackBarBehavior.floating,
      shape: const RoundedRectangleBorder(borderRadius: LnShape.rSm),
      insetPadding: const EdgeInsets.all(LnSpace.lg),
    ),

    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      thickness: 1,
      space: 1,
    ),

    switchTheme: SwitchThemeData(
      thumbIcon: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return Icon(Icons.check_rounded, color: scheme.onPrimary, size: 16);
        }
        return null;
      }),
    ),

    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: scheme.secondaryContainer,
        selectedForegroundColor: scheme.onSecondaryContainer,
        side: BorderSide(color: scheme.outlineVariant),
        shape: const RoundedRectangleBorder(borderRadius: LnShape.rFull),
        textStyle: text.labelLarge,
      ),
    ),

    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: scheme.primary,
      linearTrackColor: scheme.surfaceContainerHighest,
      circularTrackColor: scheme.surfaceContainerHighest,
    ),

    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: scheme.inverseSurface,
        borderRadius: LnShape.rXs,
      ),
      textStyle: text.bodySmall?.copyWith(color: scheme.onInverseSurface),
    ),

    pageTransitionsTheme: const PageTransitionsTheme(
      builders: <TargetPlatform, PageTransitionsBuilder>{
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
      },
    ),
  );
}

TextTheme _typography(TextTheme base, ColorScheme scheme) {
  // Roboto/Roboto Flex is the platform default on Android, which is
  // exactly the Pixel look — so we shape the scale rather than the family.
  return base
      .copyWith(
        displaySmall: base.displaySmall?.copyWith(fontWeight: FontWeight.w400, letterSpacing: 0),
        headlineLarge: base.headlineLarge?.copyWith(fontWeight: FontWeight.w400, letterSpacing: 0),
        headlineMedium:
            base.headlineMedium?.copyWith(fontWeight: FontWeight.w400, letterSpacing: 0),
        headlineSmall: base.headlineSmall?.copyWith(fontWeight: FontWeight.w400, letterSpacing: 0),
        titleLarge: base.titleLarge?.copyWith(fontWeight: FontWeight.w500, letterSpacing: 0),
        titleMedium: base.titleMedium?.copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.1),
        bodyLarge: base.bodyLarge?.copyWith(letterSpacing: 0.15, height: 1.4),
        bodyMedium: base.bodyMedium?.copyWith(letterSpacing: 0.2, height: 1.4),
        labelLarge: base.labelLarge?.copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.1),
        labelMedium: base.labelMedium?.copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.4),
      )
      .apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);
}
