import 'package:flutter/material.dart';

/// Night glass: a deep-navy sky, translucent surfaces, one sans (Inter) with
/// tabular figures, one blue accent plus a tint per kind of event.
abstract final class LookUpColors {
  /// Page base, and the bottom of the sky gradient.
  static const black = Color(0xFF04060B);

  /// Top of the sky gradient.
  static const night = Color(0xFF0B1328);

  /// Opaque surfaces: sheets, dialogs, menus.
  static const panel = Color(0xFF10141D);
  static const panelRaised = Color(0xFF181D29);

  /// Translucent surfaces over the sky.
  static const glass = Color(0x0FFFFFFF);
  static const glassStrong = Color(0x1CFFFFFF);

  /// Hairlines and dividers.
  static const line = Color(0x17FFFFFF);

  static const white = Color(0xFFF4F6FA);
  static const grey = Color(0xFFA0A8B8);
  static const greyDim = Color(0xFF687083);

  static const blue = Color(0xFF5AA2FF);

  /// The accent for text on light fills (white buttons).
  static const blueInk = Color(0xFF1F6FE0);
  static const warn = Color(0xFFF5B544);
  static const good = Color(0xFF3DD68C);

  // Event tints (see kit/event_style.dart).
  static const violet = Color(0xFFA78BFA);
  static const orange = Color(0xFFFF9F5A);
  static const gold = Color(0xFFF5C76B);
  static const red = Color(0xFFFF7A6B);
  static const cyan = Color(0xFF52D1E8);
}

/// Corner radii. Everything is rounded; nothing is boxy.
abstract final class Radii {
  static const sm = 10.0;
  static const md = 14.0;
  static const lg = 22.0;
  static const sheet = 28.0;
}

const _family = 'Inter';

/// Inter's stylistic set 1 gives open digits; tnum keeps times from jiggling.
const _numericFeatures = [FontFeature.tabularFigures(), FontFeature('ss01')];

ThemeData buildLookUpTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.dark,
    primary: LookUpColors.blue,
    onPrimary: LookUpColors.black,
    secondary: LookUpColors.grey,
    onSecondary: LookUpColors.black,
    error: Color(0xFFFF6B6B),
    onError: LookUpColors.black,
    surface: LookUpColors.panel,
    onSurface: LookUpColors.white,
    surfaceContainerHighest: LookUpColors.panelRaised,
    outline: LookUpColors.line,
    outlineVariant: LookUpColors.line,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: Brightness.dark, fontFamily: _family);
  final tt = base.textTheme.apply(bodyColor: LookUpColors.white, displayColor: LookUpColors.white);
  const pill = StadiumBorder();
  const buttonText = TextStyle(fontFamily: _family, fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: -0.2);
  const field = OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(Radii.md)), borderSide: BorderSide.none);
  return base.copyWith(
    scaffoldBackgroundColor: LookUpColors.black,
    canvasColor: LookUpColors.black,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: LookUpColors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    cardTheme: const CardThemeData(
      color: LookUpColors.glass,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(Radii.lg)),
        side: BorderSide(color: LookUpColors.line),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: LookUpColors.panel,
      modalBackgroundColor: LookUpColors.panel,
      dragHandleColor: Color(0x40FFFFFF),
      dragHandleSize: Size(36, 5),
      showDragHandle: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.sheet))),
      clipBehavior: Clip.antiAlias,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: LookUpColors.white,
        foregroundColor: LookUpColors.black,
        disabledBackgroundColor: LookUpColors.glassStrong,
        minimumSize: const Size(64, 52),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        shape: pill,
        textStyle: buttonText,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: LookUpColors.white,
        backgroundColor: LookUpColors.glass,
        side: const BorderSide(color: LookUpColors.line),
        minimumSize: const Size(64, 52),
        padding: const EdgeInsets.symmetric(horizontal: 22),
        shape: pill,
        textStyle: buttonText,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: LookUpColors.blue, shape: pill, textStyle: buttonText.copyWith(fontSize: 15)),
    ),
    iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(foregroundColor: LookUpColors.white)),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        backgroundColor: LookUpColors.glass,
        selectedBackgroundColor: LookUpColors.glassStrong,
        selectedForegroundColor: LookUpColors.white,
        foregroundColor: LookUpColors.grey,
        side: const BorderSide(color: LookUpColors.line),
        shape: pill,
        textStyle: const TextStyle(fontFamily: _family, fontSize: 14, fontWeight: FontWeight.w600),
        visualDensity: VisualDensity.compact,
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: const WidgetStatePropertyAll(Colors.white),
      trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? LookUpColors.blue : LookUpColors.glassStrong),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      // An (empty) icon keeps the thumb full-size when off, like iOS.
      thumbIcon: const WidgetStatePropertyAll(Icon(null)),
    ),
    listTileTheme: ListTileThemeData(
      textColor: LookUpColors.white,
      titleTextStyle: tt.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
      subtitleTextStyle: tt.bodyMedium?.copyWith(color: LookUpColors.grey, fontSize: 13.5),
      iconColor: LookUpColors.grey,
    ),
    expansionTileTheme: const ExpansionTileThemeData(
      shape: Border(),
      collapsedShape: Border(),
      iconColor: LookUpColors.grey,
      collapsedIconColor: LookUpColors.grey,
    ),
    dividerTheme: const DividerThemeData(color: LookUpColors.line, thickness: 1, space: 1),
    dividerColor: LookUpColors.line,
    dialogTheme: const DialogThemeData(
      backgroundColor: LookUpColors.panel,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(Radii.sheet))),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: LookUpColors.panelRaised,
      contentTextStyle: tt.bodyMedium?.copyWith(color: LookUpColors.white),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(Radii.md))),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: LookUpColors.blue, strokeCap: StrokeCap.round),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: LookUpColors.glass,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: field,
      enabledBorder: field.copyWith(borderSide: const BorderSide(color: LookUpColors.line)),
      focusedBorder: field.copyWith(borderSide: const BorderSide(color: LookUpColors.blue)),
      hintStyle: const TextStyle(color: LookUpColors.greyDim),
    ),
    textTheme: tt.copyWith(
      bodyLarge: tt.bodyLarge?.copyWith(fontSize: 16, height: 1.45, letterSpacing: -0.15),
      bodyMedium: tt.bodyMedium?.copyWith(fontSize: 14.5, height: 1.45, letterSpacing: -0.1),
      bodySmall: tt.bodySmall?.copyWith(fontSize: 12.5, height: 1.4, letterSpacing: 0, color: LookUpColors.grey),
      titleMedium: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.2),
      labelSmall: tt.labelSmall?.copyWith(letterSpacing: 0),
    ),
  );
}

/// Headlines and big numbers: Inter at its display optical size, tracked
/// tight. Numbers are tabular so a countdown never shifts sideways.
TextStyle display(double size, {FontWeight weight = FontWeight.w600, Color? color, double? height}) => TextStyle(
      fontFamily: _family,
      fontSize: size,
      fontWeight: weight,
      fontVariations: [FontVariation('wght', weight.value.toDouble()), const FontVariation('opsz', 32)],
      fontFeatures: _numericFeatures,
      color: color ?? LookUpColors.white,
      height: height ?? 1.1,
      letterSpacing: size >= 28 ? -0.025 * size : -0.015 * size,
    );

/// Times, degrees and counts inside running UI: same face, tabular figures.
TextStyle numeric({double size = 14, FontWeight weight = FontWeight.w500, Color? color}) => TextStyle(
      fontFamily: _family,
      fontSize: size,
      fontWeight: weight,
      fontVariations: [FontVariation('wght', weight.value.toDouble())],
      fontFeatures: _numericFeatures,
      color: color ?? LookUpColors.white,
      letterSpacing: -0.1,
    );

/// Night-vision filter: maps luminance to deep red so eyes stay
/// dark-adapted outdoors (rod cells are nearly blind to red).
const nightVisionMatrix = <double>[
  0.30, 0.59, 0.11, 0, 0, //
  0.00, 0.00, 0.00, 0, 0,
  0.00, 0.00, 0.00, 0, 0,
  0.00, 0.00, 0.00, 1, 0,
];

class NightVision extends StatelessWidget {
  const NightVision({super.key, required this.enabled, required this.child});
  final bool enabled;
  final Widget child;
  @override
  Widget build(BuildContext context) =>
      enabled ? ColorFiltered(colorFilter: const ColorFilter.matrix(nightVisionMatrix), child: child) : child;
}
