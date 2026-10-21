import 'package:flutter/material.dart';

/// SpaceX / Starlink-inspired: pure black, white, cool grays, one electric
/// blue accent, tight corners, uppercase tracked labels. No brand assets.
abstract final class LookUpColors {
  static const black = Color(0xFF000000);
  static const panel = Color(0xFF0E0F11);
  static const panelRaised = Color(0xFF161719);
  static const line = Color(0xFF2A2C30);
  static const white = Color(0xFFFFFFFF);
  static const grey = Color(0xFFA7ACB3);
  static const greyDim = Color(0xFF6B7078);
  static const blue = Color(0xFF3C9DFF); // SpaceX blue, lifted for black
  static const blueDeep = Color(0xFF005288);
  static const warn = Color(0xFFE6B450);
}

ThemeData buildLookUpTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.dark,
    primary: LookUpColors.blue,
    onPrimary: LookUpColors.black,
    secondary: LookUpColors.grey,
    onSecondary: LookUpColors.black,
    error: Color(0xFFFF5C5C),
    onError: LookUpColors.black,
    surface: LookUpColors.panel,
    onSurface: LookUpColors.white,
    surfaceContainerHighest: LookUpColors.panelRaised,
    outline: LookUpColors.line,
    outlineVariant: LookUpColors.line,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: Brightness.dark);
  final tt = base.textTheme;
  const radius = BorderRadius.all(Radius.circular(6));
  return base.copyWith(
    scaffoldBackgroundColor: LookUpColors.black,
    canvasColor: LookUpColors.black,
    appBarTheme: AppBarTheme(
      backgroundColor: LookUpColors.black,
      foregroundColor: LookUpColors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: tt.titleMedium?.copyWith(
        color: LookUpColors.white,
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: 2.5,
      ),
    ),
    cardTheme: const CardThemeData(
      color: LookUpColors.panel,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: LookUpColors.line)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: LookUpColors.panel,
      dragHandleColor: LookUpColors.greyDim,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: LookUpColors.black,
      indicatorColor: LookUpColors.panelRaised,
      indicatorShape: const RoundedRectangleBorder(borderRadius: radius),
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
          color: s.contains(WidgetState.selected) ? LookUpColors.white : LookUpColors.greyDim)),
      labelTextStyle: WidgetStateProperty.resolveWith((s) => tt.labelSmall!.copyWith(
          fontSize: 11,
          letterSpacing: 1.5,
          fontWeight: FontWeight.w600,
          color: s.contains(WidgetState.selected) ? LookUpColors.white : LookUpColors.greyDim)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: LookUpColors.white,
        foregroundColor: LookUpColors.black,
        shape: const RoundedRectangleBorder(borderRadius: radius),
        textStyle: tt.labelLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 1.2),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: LookUpColors.white,
        side: const BorderSide(color: LookUpColors.line),
        shape: const RoundedRectangleBorder(borderRadius: radius),
        textStyle: tt.labelLarge?.copyWith(fontWeight: FontWeight.w600, letterSpacing: 1.2),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: LookUpColors.blue),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: LookUpColors.white,
        selectedForegroundColor: LookUpColors.black,
        foregroundColor: LookUpColors.grey,
        side: const BorderSide(color: LookUpColors.line),
        shape: const RoundedRectangleBorder(borderRadius: radius),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? LookUpColors.black : LookUpColors.grey),
      trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? LookUpColors.white : LookUpColors.panelRaised),
      trackOutlineColor: const WidgetStatePropertyAll(LookUpColors.line),
    ),
    listTileTheme: ListTileThemeData(
      textColor: LookUpColors.white,
      subtitleTextStyle: tt.bodyMedium?.copyWith(color: LookUpColors.grey, fontSize: 13),
      iconColor: LookUpColors.grey,
    ),
    dividerColor: LookUpColors.line,
    dialogTheme: const DialogThemeData(
      backgroundColor: LookUpColors.panel,
      shape: RoundedRectangleBorder(borderRadius: radius),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: LookUpColors.line)),
      enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: LookUpColors.line)),
      focusedBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: LookUpColors.blue)),
    ),
    textTheme: base.textTheme.apply(bodyColor: LookUpColors.white, displayColor: LookUpColors.white),
  );
}

/// Small uppercase tracked label, the SpaceX webcast style.
class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key, this.color = LookUpColors.grey});
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: color, fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 2.2),
      );
}
