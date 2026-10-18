import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_design_space/geometry/shapes.dart';
import 'package:open_design_space/model/geometry.dart';
import 'package:open_design_space/model/objects.dart';
import 'package:open_design_space/platform/platform.dart';
import 'package:open_design_space/state/editor.dart';
import 'package:open_design_space/storage/project_store.dart';
import 'package:open_design_space/text/font_registry.dart';
import 'package:open_design_space/text/ttf.dart';
import 'package:open_design_space/ui/canvas_view.dart';
import 'package:open_design_space/ui/editor_screen.dart';

final _arial = File('/System/Library/Fonts/Supplemental/Arial.ttf');

Future<(EditorController, Directory)> makeEditor() async {
  final dir = await Directory.systemTemp.createTemp('ods-editor');
  setDataDirForTesting(dir.path);
  final store = await ProjectStore.open();
  final fonts = FontRegistry();
  if (_arial.existsSync()) fonts.addLoaded(TrueTypeFont(_arial.readAsBytesSync()));
  final ed = EditorController(project: store.create('Test'), store: store, fonts: fonts, onDisk: false);
  return (ed, dir);
}

double areaOf(DesignObject o) => o.worldPolylines(0.01).fold(0.0, (a, p) => a + polygonArea(p));

void main() {
  test('undo and redo restore objects', () async {
    final (ed, dir) = await makeEditor();
    ed.addShape(ShapeKind.square);
    ed.addShape(ShapeKind.circle);
    expect(ed.project.objects.length, 2);
    ed.undo();
    expect(ed.project.objects.length, 1);
    ed.redo();
    expect(ed.project.objects.length, 2);
    ed.dispose();
    await dir.delete(recursive: true);
  });

  test('weld merges overlapping shapes and is undoable', () async {
    final (ed, dir) = await makeEditor();
    ed.insertionPoint = const Offset(100, 100);
    ed.addShape(ShapeKind.square);
    ed.insertionPoint = const Offset(125, 100);
    ed.addShape(ShapeKind.square);
    ed.selectAll();
    ed.weld();
    expect(ed.project.objects.length, 1);
    final s = 50.8;
    expect(areaOf(ed.project.objects.single).abs(), closeTo(s * s * 2 - s * (s - 25), 0.5));
    ed.undo();
    expect(ed.project.objects.length, 2);
    ed.dispose();
    await dir.delete(recursive: true);
  });

  test('slice yields three pieces for two overlapping shapes', () async {
    final (ed, dir) = await makeEditor();
    ed.insertionPoint = const Offset(100, 100);
    ed.addShape(ShapeKind.circle);
    ed.insertionPoint = const Offset(120, 100);
    ed.addShape(ShapeKind.circle);
    ed.selectAll();
    ed.slice();
    expect(ed.project.objects.length, 3);
    ed.dispose();
    await dir.delete(recursive: true);
  });

  test('group selects together; flip mirrors', () async {
    final (ed, dir) = await makeEditor();
    ed.insertionPoint = const Offset(50, 50);
    ed.addShape(ShapeKind.square);
    ed.insertionPoint = const Offset(150, 50);
    ed.addShape(ShapeKind.triangle);
    ed.selectAll();
    ed.group();
    final first = ed.project.objects.first.id;
    ed.select([first]);
    expect(ed.selection.length, 2);
    final axis = ed.selectionBounds()!.center.dx;
    final before = ed.project.objects.first.worldBounds().center;
    ed.flip(horizontal: true);
    final after = ed.project.objects.first.worldBounds().center;
    expect(after.dx, closeTo(2 * axis - before.dx, 0.01));
    expect(ed.project.objects.first.xform.sx, -1);
    ed.dispose();
    await dir.delete(recursive: true);
  });

  test('text converts to outlines and keeps the original hidden', () async {
    final (ed, dir) = await makeEditor();
    ed.addText('Hi');
    final t = ed.single as TextObject;
    expect(t.outline, isNotEmpty);
    ed.textToOutlines();
    expect(ed.project.objects.length, 2);
    expect(t.visible, isFalse);
    expect(ed.single, isA<PathObject>());
    ed.dispose();
    await dir.delete(recursive: true);
  }, skip: !_arial.existsSync());

  test('eraser removes area; crop trims to rectangle', () async {
    final (ed, dir) = await makeEditor();
    ed.insertionPoint = const Offset(100, 100);
    ed.addShape(ShapeKind.square);
    final before = areaOf(ed.single!).abs();
    ed.eraserWidth = 10;
    ed.erase([const Offset(80, 100), const Offset(120, 100)]);
    final mid = areaOf(ed.project.objects.single).abs();
    expect(mid, lessThan(before - 300));
    ed.select([ed.project.objects.single.id]);
    ed.cropTo(const Rect.fromLTWH(100, 60, 50, 80));
    final b = ed.project.objects.single.worldBounds();
    expect(b.left, closeTo(100, 0.05));
    ed.dispose();
    await dir.delete(recursive: true);
  });

  test('offset adds an outline behind the original', () async {
    final (ed, dir) = await makeEditor();
    ed.addShape(ShapeKind.circle);
    final id = ed.single!.id;
    ed.offsetSelected(5);
    expect(ed.project.objects.length, 2);
    expect(ed.project.objects.last.id, id);
    final grown = ed.project.objects.first.worldBounds();
    expect(grown.width, closeTo(50.8 + 10, 0.2));
    ed.dispose();
    await dir.delete(recursive: true);
  });

  test('autosave writes non-empty projects only', () async {
    final (ed, dir) = await makeEditor();
    await ed.save();
    expect(await ed.store.list(), isEmpty);
    ed.addShape(ShapeKind.heart);
    await ed.save();
    final list = await ed.store.list();
    expect(list.single.objectCount, 1);
    ed.dispose();
    await dir.delete(recursive: true);
  });

  testWidgets('editor screen builds and adds a shape from the keyboard', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late Directory dir;
    late ProjectStore store;
    await tester.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('ods-ui');
      setDataDirForTesting(dir.path);
      store = await ProjectStore.open();
    });
    final fonts = FontRegistry();
    await tester.pumpWidget(MaterialApp(home: EditorScreen(project: store.create('UI'), store: store, fonts: fonts, isNew: true)));
    await tester.pump();
    expect(find.text('Make it'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.pump();
    expect(find.text('Square 1'), findsOneWidget);
    expect(find.text('Weld'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => dir.delete(recursive: true));
  });

  testWidgets('two-finger pinch zooms the canvas without moving objects', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late Directory dir;
    late ProjectStore store;
    await tester.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('ods-touch');
      setDataDirForTesting(dir.path);
      store = await ProjectStore.open();
    });
    final p = store.create('Touch');
    await tester.pumpWidget(MaterialApp(home: EditorScreen(project: p, store: store, fonts: FontRegistry(), isNew: true)));
    await tester.pump();
    final state = tester.state(find.byType(EditorScreen)) as dynamic;
    final EditorController ed = state.ed;
    ed.addShape(ShapeKind.square);
    await tester.pump();
    final before = ed.project.objects.single.xform;
    final canvas = tester.getCenter(find.byType(CanvasView));
    final zoom0 = state.vp.zoom as double;
    // First finger lands on the selected shape, second finger starts a pinch.
    final a = await tester.startGesture(canvas, pointer: 1, kind: PointerDeviceKind.touch);
    await tester.pump();
    final b = await tester.startGesture(canvas + const Offset(60, 0), pointer: 2, kind: PointerDeviceKind.touch);
    await tester.pump();
    for (var i = 1; i <= 10; i++) {
      await a.moveTo(canvas - Offset(6.0 * i, 0));
      await b.moveTo(canvas + Offset(60 + 6.0 * i, 0));
      await tester.pump();
    }
    await a.up();
    await b.up();
    await tester.pump();
    expect(state.vp.zoom as double, greaterThan(zoom0 * 1.5));
    expect(ed.project.objects.single.xform.tx, before.tx);
    expect(ed.project.objects.single.xform.ty, before.ty);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => dir.delete(recursive: true));
  });
}
