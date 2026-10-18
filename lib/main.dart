import 'package:flutter/material.dart';

import 'storage/project_store.dart';
import 'text/font_registry.dart';
import 'ui/editor_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await ProjectStore.open();
  final fonts = FontRegistry();
  // Fonts load in the background; text appears as soon as they're ready.
  fonts.init();
  runApp(OpenDesignSpaceApp(store: store, fonts: fonts));
}

class OpenDesignSpaceApp extends StatelessWidget {
  const OpenDesignSpaceApp({super.key, required this.store, required this.fonts});
  final ProjectStore store;
  final FontRegistry fonts;

  static ThemeData _theme(Brightness b) {
    final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF12A594), brightness: b);
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      visualDensity: VisualDensity.compact,
      appBarTheme: AppBarTheme(backgroundColor: scheme.surface, surfaceTintColor: Colors.transparent, scrolledUnderElevation: 0),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      tooltipTheme: const TooltipThemeData(waitDuration: Duration(milliseconds: 400)),
    );
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Open Design Space',
        debugShowCheckedModeBanner: false,
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        // Straight to a blank canvas; the library is one click away.
        home: EditorScreen(project: store.create('Untitled project'), store: store, fonts: fonts, isNew: true),
      );
}
