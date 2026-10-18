// Renders every main screen at desktop, tablet and phone sizes, in light and
// dark, for design review. Images go to build/design_review/.
// Run with: flutter test test/design_review_test.dart --dart-define=SCREENSHOTS=true
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_design_space/geometry/shapes.dart';
import 'package:open_design_space/model/geometry.dart';
import 'package:open_design_space/model/objects.dart';
import 'package:open_design_space/model/project.dart';
import 'package:open_design_space/platform/platform.dart';
import 'package:open_design_space/state/editor.dart';
import 'package:open_design_space/storage/project_store.dart';
import 'package:open_design_space/text/font_registry.dart';
import 'package:open_design_space/text/text_layout.dart';
import 'package:open_design_space/text/ttf.dart';
import 'package:open_design_space/ui/editor_screen.dart';
import 'package:open_design_space/ui/image_cache.dart';
import 'package:open_design_space/ui/library_screen.dart';
import 'package:open_design_space/ui/mat_screen.dart';
import 'package:open_design_space/ui/theme.dart';
import 'package:open_design_space/ui/ui_scale.dart';

const enabled = bool.fromEnvironment('SCREENSHOTS');
const outDir = String.fromEnvironment('SHOT_DIR', defaultValue: 'build/design_review');
final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? '${Platform.environment['HOME']}/develop/flutter';
final materialFonts = '$flutterRoot/bin/cache/artifacts/material_fonts';

const devices = {
  'desktop': Size(1440, 900),
  'tablet': Size(820, 1180),
  'phone': Size(390, 844),
};

Future<void> loadFont(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final f in files) {
    loader.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
  }
  await loader.load();
}

Future<void> capture(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('shot')));
  await tester.runAsync(() async {
    final img = await boundary.toImage(pixelRatio: 1);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    File('$outDir/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(data!.buffer.asUint8List());
  });
}

Project sampleDesign(ProjectStore store, FontRegistry fonts) {
  final p = store.create('Birthday banner');
  final engine = TextEngine(fonts);
  final title = TextObject(id: 'title', name: 'Title', text: 'Happy Birthday', fontFamily: 'Georgia', size: 26, curve: 70, color: 0xFFD6409F, xform: const Xform(tx: 152, ty: 95));
  final sub = TextObject(id: 'name', name: 'Name', text: 'MAYA', fontFamily: 'Arial', fontStyle: 'Bold', size: 40, letterSpacing: 0.15, align: TextAlign2.center, color: 0xFF2F6FED, xform: const Xform(tx: 152, ty: 150));
  engine.refresh(title);
  engine.refresh(sub);
  p.objects.addAll([
    PathObject(id: 'heart', name: 'Heart', contours: buildShape(ShapeKind.heart, size: 60), color: 0xFFE5484D, xform: const Xform(tx: 70, ty: 225, rotation: -0.25)),
    PathObject(id: 'star', name: 'Star', contours: buildShape(ShapeKind.star, size: 55), color: 0xFFF5A524, xform: const Xform(tx: 235, ty: 225, rotation: 0.2)),
    PathObject(id: 'fold', name: 'Fold line', contours: buildShape(ShapeKind.line, size: 180), color: 0xFF6B7280, operation: Operation.score, xform: const Xform(tx: 152, ty: 185)),
    title,
    sub,
  ]);
  return p;
}

void main() {
  testWidgets('design review screenshots', (tester) async {
    late ProjectStore store;
    late FontRegistry fonts;
    await tester.runAsync(() async {
      await loadFont('Roboto', ['$materialFonts/Roboto-Regular.ttf', '$materialFonts/Roboto-Medium.ttf', '$materialFonts/Roboto-Bold.ttf']);
      await loadFont('MaterialIcons', ['$materialFonts/MaterialIcons-Regular.otf']);
      final dir = await Directory.systemTemp.createTemp('ods-review');
      setDataDirForTesting(dir.path);
      store = await ProjectStore.open();
      fonts = FontRegistry();
      for (final f in ['/System/Library/Fonts/Supplemental/Georgia.ttf', '/System/Library/Fonts/Supplemental/Arial.ttf', '/System/Library/Fonts/Supplemental/Arial Bold.ttf']) {
        if (File(f).existsSync()) fonts.addLoaded(TrueTypeFont(File(f).readAsBytesSync()), path: f);
      }
      fonts.ready = true;
      final p = sampleDesign(store, fonts);
      await store.save(p);
      await store.save(store.create('Gift tags')..objects.add(PathObject(id: 'tag', name: 'Tag', contours: buildShape(ShapeKind.polygon), color: 0xFF30A46C)));
    });

    Future<void> show(Widget home, Size size, Brightness b, {bool settle = true, double scale = 1}) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(RepaintBoundary(
        key: const ValueKey('shot'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: appTheme(Brightness.light, fontFamily: 'Roboto'),
          darkTheme: appTheme(Brightness.dark, fontFamily: 'Roboto'),
          themeMode: b == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
          builder: (context, child) => UiScaleHost.wrap(UiScale(scale), child),
          home: KeyedSubtree(key: UniqueKey(), child: home),
        ),
      ));
      settle ? await tester.pumpAndSettle() : await tester.pump();
    }

    for (final MapEntry(key: device, value: size) in devices.entries) {
      for (final b in [Brightness.light, if (device != 'tablet') Brightness.dark]) {
        final tag = '$device-${b.name}';

        await show(EditorScreen(project: store.create('Untitled project'), store: store, fonts: fonts, isNew: true), size, b);
        await capture(tester, '$tag-1-editor-empty');

        final design = sampleDesign(store, fonts);
        await show(EditorScreen(project: design, store: store, fonts: fonts), size, b);
        await capture(tester, '$tag-2-editor-design');
        final ed = (tester.state(find.byType(EditorScreen)) as dynamic).ed as EditorController;
        ed.select(['title']);
        await tester.pumpAndSettle();
        await capture(tester, '$tag-3-editor-text');
        ed.select(['heart']);
        await tester.pumpAndSettle();
        await capture(tester, '$tag-4-editor-shape');

        final matEd = EditorController(project: design, store: store, fonts: fonts);
        await show(MatScreen(ed: matEd, images: AssetImages(design)), size, b);
        await capture(tester, '$tag-5-mats');

        await show(LibraryScreen(store: store, fonts: fonts), size, b, settle: false);
        for (var i = 0; i < 40 && find.byType(CircularProgressIndicator).evaluate().isNotEmpty; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));
          await tester.pump();
        }
        await tester.pumpAndSettle();
        await capture(tester, '$tag-6-library');
      }

      // The largest interface size, for people who need bigger text and icons.
      const big = 1.5;
      final tag = '$device-light-150';
      final design = sampleDesign(store, fonts);
      await show(EditorScreen(project: design, store: store, fonts: fonts), size, Brightness.light, scale: big);
      await capture(tester, '$tag-2-editor-design');
      final ed = (tester.state(find.byType(EditorScreen)) as dynamic).ed as EditorController;
      ed.select(['title']);
      await tester.pumpAndSettle();
      await capture(tester, '$tag-3-editor-text');
      ed.select(['heart']);
      await tester.pumpAndSettle();
      await capture(tester, '$tag-4-editor-shape');
      final matEd = EditorController(project: design, store: store, fonts: fonts);
      await show(MatScreen(ed: matEd, images: AssetImages(design)), size, Brightness.light, scale: big);
      await capture(tester, '$tag-5-mats');
      await show(LibraryScreen(store: store, fonts: fonts), size, Brightness.light, settle: false, scale: big);
      for (var i = 0; i < 40 && find.byType(CircularProgressIndicator).evaluate().isNotEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));
        await tester.pump();
      }
      await tester.pumpAndSettle();
      await capture(tester, '$tag-6-library');
    }
    await tester.pumpWidget(const SizedBox());
    tester.view.reset();
  }, skip: !enabled);
}
