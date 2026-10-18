import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_design_space/geometry/shapes.dart';
import 'package:open_design_space/model/geometry.dart';
import 'package:open_design_space/model/objects.dart';
import 'package:open_design_space/model/project.dart';
import 'package:open_design_space/platform/platform.dart';
import 'package:open_design_space/state/editor.dart';
import 'package:open_design_space/storage/project_store.dart';
import 'package:open_design_space/text/font_registry.dart';
import 'package:open_design_space/ui/editor_screen.dart';
import 'package:open_design_space/ui/image_cache.dart';
import 'package:open_design_space/ui/library_screen.dart';
import 'package:open_design_space/ui/mat_screen.dart';

/// Phone portrait, phone landscape, tablet portrait, small and large desktop.
const sizes = {
  'phone': Size(390, 844),
  'phone landscape': Size(844, 390),
  'tablet': Size(820, 1180),
  'small desktop': Size(1024, 700),
  'desktop': Size(1600, 1000),
};

Project sample(ProjectStore store) {
  final p = store.create('A long project name that should not overflow the bar');
  p.objects
    ..add(PathObject(id: 'a', name: 'Square', contours: buildShape(ShapeKind.square), xform: const Xform(tx: 60, ty: 60)))
    ..add(PathObject(id: 'b', name: 'Star', contours: buildShape(ShapeKind.star), color: 0xFFE5484D, xform: const Xform(tx: 150, ty: 60)))
    ..add(TextObject(id: 't', name: 'Text', text: 'Hello', fontFamily: 'Missing font')..outline = buildShape(ShapeKind.circle));
  return p;
}

void main() {
  late Directory dir;
  late ProjectStore store;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('ods-layout');
    setDataDirForTesting(dir.path);
    store = await ProjectStore.open();
  });
  tearDownAll(() => dir.delete(recursive: true));

  for (final MapEntry(key: name, value: size) in sizes.entries) {
    testWidgets('editor lays out on $name', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final p = sample(store);
      await tester.pumpWidget(MaterialApp(home: EditorScreen(project: p, store: store, fonts: FontRegistry())));
      await tester.pump();
      expect(tester.takeException(), isNull);
      // Narrow layouts move Layers into a drawer; it must still open.
      if (size.width <= 900) {
        await tester.tap(find.byTooltip('Layers'));
        await tester.pumpAndSettle();
        expect(find.text('Star'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('editor with a selection lays out on $name', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final p = sample(store);
      await tester.pumpWidget(MaterialApp(home: EditorScreen(project: p, store: store, fonts: FontRegistry())));
      await tester.pump();
      final state = tester.state(find.byType(EditorScreen));
      // Reach the controller through the screen to select the text object.
      (state as dynamic).ed.select(['t']);
      await tester.pump();
      expect(tester.takeException(), isNull);
      (state as dynamic).ed.setTool(Tool.node);
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('mats screen lays out on $name', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final p = sample(store);
      final ed = EditorController(project: p, store: store, fonts: FontRegistry());
      await tester.pumpWidget(MaterialApp(home: MatScreen(ed: ed, images: AssetImages(p))));
      await tester.pump();
      expect(tester.takeException(), isNull);
      // Narrow layouts must still reach the mat settings.
      if (size.width <= 900) {
        await tester.tap(find.byTooltip('Mat settings'));
        await tester.pumpAndSettle();
        expect(find.text('Pack to save material'), findsOneWidget);
      }
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('library lays out on $name', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.runAsync(() => store.save(sample(store)));
      await tester.pumpWidget(MaterialApp(home: LibraryScreen(store: store, fonts: FontRegistry())));
      for (var i = 0; i < 40 && find.byType(CircularProgressIndicator).evaluate().isNotEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));
        await tester.pump();
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
