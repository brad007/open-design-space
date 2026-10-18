// Times the canvas with a large design: 300 shapes plus a long run of curved
// text. Prints milliseconds per frame (debug mode, so slower than a release
// build). The limits are loose so slow CI machines pass; they catch big
// regressions, not small ones.
import 'dart:io';
import 'dart:math' as math;

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
import 'package:open_design_space/text/text_layout.dart';
import 'package:open_design_space/text/ttf.dart';
import 'package:open_design_space/ui/canvas_view.dart';
import 'package:open_design_space/ui/editor_screen.dart';

final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? '${Platform.environment['HOME']}/develop/flutter';
final roboto = '$flutterRoot/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf';

Project bigDesign(ProjectStore store, FontRegistry fonts) {
  final p = store.create('Big design')..units = Units.mm;
  final kinds = ShapeKind.values.where((k) => k != ShapeKind.line).toList();
  for (var i = 0; i < 300; i++) {
    p.objects.add(PathObject(
      id: 's$i',
      name: 'Shape $i',
      contours: buildShape(kinds[i % kinds.length], size: 12),
      color: [0xFFE5484D, 0xFF2F6FED, 0xFF30A46C][i % 3],
      operation: i % 10 == 0 ? Operation.score : Operation.cut,
      xform: Xform(tx: 10 + (i % 20) * 14.0, ty: 10 + (i ~/ 20) * 14.0, rotation: i * 0.1),
    ));
  }
  if (fonts.families.isNotEmpty) {
    final t = TextObject(
      id: 'text',
      name: 'Curved text',
      text: 'The quick brown fox jumps over the lazy dog. ' * 6,
      fontFamily: fonts.families.first,
      size: 3,
      curve: 360,
      xform: const Xform(tx: 150, ty: 150),
    );
    TextEngine(fonts).refresh(t);
    p.objects.add(t);
  }
  return p;
}

void main() {
  testWidgets('canvas keeps up with a large design', (tester) async {
    late ProjectStore store;
    final fonts = FontRegistry();
    await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('ods-perf');
      setDataDirForTesting(dir.path);
      store = await ProjectStore.open();
      if (File(roboto).existsSync()) fonts.addLoaded(TrueTypeFont(File(roboto).readAsBytesSync()), path: roboto);
      fonts.ready = true;
    });
    final p = bigDesign(store, fonts);
    final nodes = p.objects.fold(0, (n, o) => n + o.localContours.fold(0, (m, c) => m + c.nodes.length));

    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: EditorScreen(project: p, store: store, fonts: fonts)));
    await tester.pump();
    final state = tester.state(find.byType(EditorScreen)) as dynamic;
    final ed = state.ed as EditorController;

    Future<double> time(String what, Future<void> Function(int i) frame, {int frames = 60}) async {
      await frame(0); // warm up
      final sw = Stopwatch()..start();
      for (var i = 1; i <= frames; i++) {
        await frame(i);
      }
      final ms = sw.elapsedMicroseconds / 1000 / frames;
      // ignore: avoid_print
      print('${what.padRight(36)} ${ms.toStringAsFixed(2)} ms/frame');
      return ms;
    }

    // ignore: avoid_print
    print('${p.objects.length} objects, $nodes path nodes');

    final pan = await time('pan, nothing selected', (i) async {
      state.vp.panBy(Offset(math.sin(i / 5) * 4, 1));
      await tester.pump();
    });

    ed.selectAll();
    await tester.pump();
    final panAll = await time('pan, everything selected', (i) async {
      state.vp.panBy(Offset(math.sin(i / 5) * 4, 1));
      await tester.pump();
    });

    // Drag one shape across the others with snapping on, like lining things up.
    Future<double> dragged(String id) async {
      ed.select([id]);
      await tester.pump();
      final o = p.byId(id)!;
      // Grab the first glyph or the shape itself, not the empty middle of the arc.
      final grab = boundsOfContours([o.worldContours().first]).center;
      final vp = state.vp as CanvasViewport;
      vp.panBy(vp.size.center(Offset.zero) - vp.toScreen(grab));
      await tester.pump();
      final start = tester.getTopLeft(find.byType(CanvasView)) + vp.toScreen(grab);
      final before = o.xform;
      var moved = false;
      final g = await tester.startGesture(start);
      final ms = await time('drag $id with snapping', (i) async {
        await g.moveBy(Offset(i.isEven ? 3 : -2, 1));
        await tester.pump();
        moved |= o.xform != before;
      });
      await g.up();
      await tester.pump();
      expect(moved, isTrue);
      return ms;
    }

    final drag = await dragged('s21');
    final dragText = fonts.families.isEmpty ? 0.0 : await dragged('text');

    expect(tester.takeException(), isNull);
    expect(pan, lessThan(40));
    expect(panAll, lessThan(60));
    expect(drag, lessThan(40));
    expect(dragText, lessThan(60));
    await tester.pumpWidget(const SizedBox());
  });
}
