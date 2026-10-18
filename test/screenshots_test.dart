// Renders real screenshots of the app into docs/screenshots.
// Run with: flutter test test/screenshots_test.dart --dart-define=SCREENSHOTS=true
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_design_space/geometry/shapes.dart';
import 'package:open_design_space/model/geometry.dart';
import 'package:open_design_space/model/objects.dart';
import 'package:open_design_space/platform/platform.dart';
import 'package:open_design_space/storage/project_store.dart';
import 'package:open_design_space/text/font_registry.dart';
import 'package:open_design_space/text/text_layout.dart';
import 'package:open_design_space/text/ttf.dart';
import 'package:open_design_space/ui/editor_screen.dart';
import 'package:open_design_space/state/editor.dart';
import 'package:open_design_space/ui/image_cache.dart';
import 'package:open_design_space/ui/library_screen.dart';
import 'package:open_design_space/ui/mat_screen.dart';

const enabled = bool.fromEnvironment('SCREENSHOTS');
final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? '${Platform.environment['HOME']}/develop/flutter';
final materialFonts = '$flutterRoot/bin/cache/artifacts/material_fonts';

Future<void> loadFont(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final f in files) {
    final bytes = File(f).readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

ThemeData theme() {
  final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF12A594));
  return ThemeData(
    colorScheme: scheme,
    fontFamily: 'Roboto',
    visualDensity: VisualDensity.compact,
    appBarTheme: AppBarTheme(backgroundColor: scheme.surface, surfaceTintColor: Colors.transparent),
  );
}

Future<void> capture(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('shot')));
  await tester.runAsync(() async {
    final img = await boundary.toImage(pixelRatio: 1);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    final f = File('docs/screenshots/$name.png')..createSync(recursive: true);
    f.writeAsBytesSync(data!.buffer.asUint8List());
  });
}

void main() {
  testWidgets('screenshots', (tester) async {
    tester.view.physicalSize = const Size(1600, 980);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    late ProjectStore store;
    late FontRegistry fonts;
    await tester.runAsync(() async {
      await loadFont('Roboto', ['$materialFonts/Roboto-Regular.ttf', '$materialFonts/Roboto-Medium.ttf', '$materialFonts/Roboto-Bold.ttf']);
      await loadFont('MaterialIcons', ['$materialFonts/MaterialIcons-Regular.otf']);
      final dir = await Directory.systemTemp.createTemp('ods-shots');
      setDataDirForTesting(dir.path);
      store = await ProjectStore.open();
      fonts = FontRegistry();
      for (final f in ['/System/Library/Fonts/Supplemental/Georgia.ttf', '/System/Library/Fonts/Supplemental/Arial.ttf']) {
        fonts.addLoaded(TrueTypeFont(File(f).readAsBytesSync()), path: f);
      }
      fonts.ready = true;
    });

    // A small sample design.
    final p = store.create('Birthday banner');
    final engine = TextEngine(fonts);
    final title = TextObject(id: newId(), name: 'Title', text: 'Happy Birthday', fontFamily: 'Georgia', size: 26, curve: 70, color: 0xFFD6409F, xform: const Xform(tx: 152, ty: 95));
    final sub = TextObject(id: newId(), name: 'Name', text: 'MAYA', fontFamily: 'Arial', fontStyle: 'Bold', size: 40, letterSpacing: 0.15, align: TextAlign2.center, color: 0xFF2F6FED, xform: const Xform(tx: 152, ty: 150));
    engine.refresh(title);
    engine.refresh(sub);
    p.objects.addAll([
      PathObject(id: newId(), name: 'Heart', contours: buildShape(ShapeKind.heart, size: 60), color: 0xFFE5484D, xform: const Xform(tx: 70, ty: 225, rotation: -0.25)),
      PathObject(id: newId(), name: 'Star', contours: buildShape(ShapeKind.star, size: 55), color: 0xFFF5A524, xform: const Xform(tx: 235, ty: 225, rotation: 0.2)),
      PathObject(id: newId(), name: 'Fold line', contours: buildShape(ShapeKind.line, size: 180), color: 0xFF6B7280, operation: Operation.score, xform: const Xform(tx: 152, ty: 185)),
      title,
      sub,
    ]);
    await tester.runAsync(() => store.save(p));

    await tester.pumpWidget(RepaintBoundary(
      key: const ValueKey('shot'),
      child: MaterialApp(debugShowCheckedModeBanner: false, theme: theme(), home: EditorScreen(project: p, store: store, fonts: fonts)),
    ));
    await tester.pumpAndSettle();
    // Select the curved title to show the edit bar.
    await tester.tap(find.text('Title'));
    await tester.pumpAndSettle();
    await capture(tester, 'editor');

    final ed = EditorController(project: p, store: store, fonts: fonts);
    final images = AssetImages(p);
    await tester.pumpWidget(RepaintBoundary(
      key: const ValueKey('shot'),
      child: MaterialApp(debugShowCheckedModeBanner: false, theme: theme(), home: MatScreen(ed: ed, images: images)),
    ));
    await tester.pumpAndSettle();
    await capture(tester, 'mats');

    final p2 = store.create('Gift tags')..objects.add(PathObject(id: newId(), name: 'Tag', contours: buildShape(ShapeKind.polygon), color: 0xFF30A46C));
    await tester.runAsync(() => store.save(p2));
    await tester.pumpWidget(RepaintBoundary(
      key: const ValueKey('shot'),
      child: MaterialApp(debugShowCheckedModeBanner: false, theme: theme(), home: LibraryScreen(store: store, fonts: fonts)),
    ));
    // The library reads the real file system; give it real time to finish.
    for (var i = 0; i < 40 && find.byType(CircularProgressIndicator).evaluate().isNotEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    await capture(tester, 'library');
    await tester.pumpWidget(const SizedBox());
  }, skip: !enabled);
}
