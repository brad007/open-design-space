import 'package:flutter/material.dart';

/// The app's look in light and dark. [fontFamily] lets tests pin a font.
ThemeData appTheme(Brightness b, {String? fontFamily}) {
  final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF12A594), brightness: b);
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    fontFamily: fontFamily,
    visualDensity: VisualDensity.compact,
    appBarTheme: AppBarTheme(backgroundColor: scheme.surface, surfaceTintColor: Colors.transparent, scrolledUnderElevation: 0),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant.withValues(alpha: 0.6)),
    tooltipTheme: const TooltipThemeData(waitDuration: Duration(milliseconds: 400)),
  );
}
