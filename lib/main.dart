import 'package:flutter/material.dart';

import 'storage/project_store.dart';
import 'text/font_registry.dart';
import 'ui/editor_screen.dart';
import 'ui/theme.dart';

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

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Open Design Space',
        debugShowCheckedModeBanner: false,
        theme: appTheme(Brightness.light),
        darkTheme: appTheme(Brightness.dark),
        // Straight to a blank canvas; the library is one click away.
        home: EditorScreen(project: store.create('Untitled project'), store: store, fonts: fonts, isNew: true),
      );
}
