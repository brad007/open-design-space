import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
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

import 'editor_test.dart' show makeEditor;
import 'layout_test.dart' show sample;

final _arial = File('/System/Library/Fonts/Supplemental/Arial.ttf');

const _center = Offset(100, 100);

/// A circle of radius [r], drawn counter-clockwise on screen so the path has
/// to reorient itself to keep text outside.
TextPath circlePath(double r, {int steps = 720}) => TextPath(
      [for (var i = 0; i < steps; i++) _center + Offset(math.cos(-i * 2 * math.pi / steps), math.sin(-i * 2 * math.pi / steps)) * r],
      closed: true,
    );

void main() {
  group('placeAlongPath', () {
    test('glyphs on a straight line sit at their arc length above it', () {
      final line = TextPath(const [Offset(0, 50), Offset(40, 50), Offset(100, 50)], closed: false);
      expect(line.length, closeTo(100, 1e-9));
      final placed = placeAlongPath(line, [5, 40, 75], halfWidths: [2, 2, 2], normalOffset: 3);
      for (final (i, x) in [5.0, 40.0, 75.0].indexed) {
        expect(placed[i].position.dx, closeTo(x, 1e-9));
        // Above the line on screen (y points down).
        expect(placed[i].position.dy, closeTo(47, 1e-9));
        expect(placed[i].angle, closeTo(0, 1e-9));
      }
    });

    test('an open path continues straight past its ends', () {
      final line = TextPath(const [Offset(0, 0), Offset(0, 10)], closed: false);
      final placed = placeAlongPath(line, [-5, 15]);
      expect(placed[0].position, offsetMoreOrLessEquals(const Offset(0, -5)));
      expect(placed[1].position, offsetMoreOrLessEquals(const Offset(0, 15)));
      expect(placed[1].angle, closeTo(math.pi / 2, 1e-9));
    });

    test('glyphs on a circle sit outside it, tangent, evenly spaced', () {
      const r = 50.0, offset = 2.0;
      final circle = circlePath(r);
      expect(circle.length, closeTo(2 * math.pi * r, 0.01));
      final centers = [for (var i = 0; i < 12; i++) i * circle.length / 12];
      final placed = placeAlongPath(circle, centers, halfWidths: List.filled(12, 3), normalOffset: offset);
      for (final g in placed) {
        final radial = g.position - _center;
        expect(radial.distance, closeTo(r + offset, 0.01));
        // The baseline runs along the tangent: perpendicular to the radius.
        final dir = Offset(math.cos(g.angle), math.sin(g.angle));
        expect((dir.dx * radial.dx + dir.dy * radial.dy) / radial.distance, closeTo(0, 1e-3));
        // Text stands upright away from the center: its "up" is outward.
        final up = Offset(math.sin(g.angle), -math.cos(g.angle));
        expect((up.dx * radial.dx + up.dy * radial.dy) / radial.distance, closeTo(1, 1e-3));
      }
      // Equal arc lengths make equal angles between neighbours.
      for (var i = 0; i < placed.length; i++) {
        final a = placed[i].position - _center, b = placed[(i + 1) % placed.length].position - _center;
        final between = math.acos(((a.dx * b.dx + a.dy * b.dy) / (a.distance * b.distance)).clamp(-1.0, 1.0));
        expect(between, closeTo(2 * math.pi / 12, 1e-3));
      }
    });

    test('a reversed circle puts text on the inside, at the mirrored arc length', () {
      final circle = circlePath(40);
      final back = circle.reversed();
      expect(back.length, closeTo(circle.length, 1e-6));
      expect(back.pointAt(back.length - 30), offsetMoreOrLessEquals(circle.pointAt(30), epsilon: 1e-6));
      final g = placeAlongPath(back, [10], normalOffset: 2).single;
      expect((g.position - _center).distance, closeTo(38, 0.01));
    });

    test('top of a closed path', () {
      final circle = circlePath(40);
      expect(circle.pointAt(circle.topFraction * circle.length), offsetMoreOrLessEquals(const Offset(100, 60), epsilon: 0.01));
    });
  });

  group('layoutTextOnPath', () {
    final font = _arial.existsSync() ? TrueTypeFont(_arial.readAsBytesSync()) : null;
    final skip = font == null ? 'Arial not installed' : null;

    test('glyph outlines follow a circle', () {
      final t = TextObject(id: 't', name: 't', text: 'HELLO WORLD', fontFamily: 'Arial', size: 10)
        ..pathId = 'p'
        ..pathOffset = 1;
      final out = layoutTextOnPath(t, font!, circlePath(50));
      expect(out, isNotEmpty);
      for (final p in out.expand((c) => c.flatten(0.05))) {
        // Between the baseline (minus descenders' wiggle) and cap height.
        expect((p - _center).distance, inInclusiveRange(50.5, 51 + 10));
      }
      // Flipped, the same text hangs inside the circle.
      t.pathFlip = true;
      for (final p in layoutTextOnPath(t, font, circlePath(50)).expand((c) => c.flatten(0.05))) {
        expect((p - _center).distance, inInclusiveRange(49 - 10, 49.5));
      }
    }, skip: skip);

    test('glyph outlines on a straight line match plain layout', () {
      final t = TextObject(id: 't', name: 't', text: 'Ag', fontFamily: 'Arial', size: 20, align: TextAlign2.left);
      final plain = boundsOfContours(layoutText(t, font!));
      t.pathId = 'p';
      final onLine = boundsOfContours(layoutTextOnPath(t, font, TextPath(const [Offset(0, 0), Offset(200, 0)], closed: false)));
      expect(onLine.width, closeTo(plain.width, 0.01));
      expect(onLine.height, closeTo(plain.height, 0.01));
      // The baseline is the line: ascenders above, descender of "g" below.
      expect(onLine.top, lessThan(-10));
      expect(onLine.bottom, inExclusiveRange(0, 6));
    }, skip: skip);
  });

  group('editor', () {
    test('text put on a shape follows it, saves and undoes', () async {
      if (!_arial.existsSync()) return markTestSkipped('Arial not installed');
      final (ed, dir) = await makeEditor();
      ed.insertionPoint = const Offset(100, 100);
      ed.addShape(ShapeKind.circle);
      final circle = ed.project.objects.last as PathObject;
      ed.addText('ROUND');
      final t = ed.project.objects.last as TextObject;
      ed.select([circle.id, t.id]);
      expect(ed.textAndPath, isNotNull);
      ed.putTextOnPath();
      expect(t.pathId, circle.id);
      expect(t.groupId, isNotNull);
      expect(t.groupId, circle.groupId);
      // Centered at the top of the circle, rising above it.
      final b = t.worldBounds();
      expect(b.center.dx, closeTo(100, 1));
      expect(b.top, lessThan(100 - 25.4 - 10));

      // Moving the shape brings the text along.
      ed.select([circle.id], expandGroups: false);
      ed.nudge(const Offset(20, 0));
      expect(t.worldBounds().center.dx, closeTo(120, 1));

      // Moving the text alone snaps it back onto the path.
      ed.select([t.id], expandGroups: false);
      ed.nudge(const Offset(0, 30));
      expect(t.worldBounds().center.dy, closeTo(b.center.dy, 0.01));

      // Saved and reloaded.
      final json = t.toJson();
      expect(json['onPath'], containsPair('id', circle.id));
      final back = DesignObject.fromJson(json) as TextObject;
      expect(back.pathId, circle.id);
      expect(back.pathStart, t.pathStart);

      // Duplicating text with its shape links the copies.
      ed.select([circle.id]);
      ed.duplicate();
      final copies = ed.selected;
      final copyText = copies.whereType<TextObject>().single;
      expect(copyText.pathId, copies.whereType<PathObject>().single.id);

      ed.undo();
      ed.undo();
      ed.undo();
      ed.undo();
      expect((ed.project.byId(t.id) as TextObject).pathId, isNull);
      ed.dispose();
      await dir.delete(recursive: true);
    });

    test('older text without a path still loads', () {
      final legacy = {
        'kind': 'text',
        'id': 'x',
        'name': 'Old',
        'xf': const Xform(tx: 5, ty: 5).toJson(),
        'text': 'Hi',
        'font': 'Arial',
        'size': 10,
      };
      final t = DesignObject.fromJson(legacy) as TextObject;
      expect(t.pathId, isNull);
      expect(t.toJson().containsKey('onPath'), isFalse);
    });
  });

  testWidgets('Put on path in the text row needs a text and a shape', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = (await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('ods-textpath');
      addTearDown(() => dir.delete(recursive: true));
      setDataDirForTesting(dir.path);
      return ProjectStore.open();
    }))!;
    final p = sample(store);
    await tester.pumpWidget(MaterialApp(home: EditorScreen(project: p, store: store, fonts: FontRegistry())));
    final ed = (tester.state(find.byType(EditorScreen)) as dynamic).ed;
    ed.select(['t']);
    await tester.pump();
    final button = find.widgetWithText(TextButton, 'Put on path');
    expect(tester.widget<TextButton>(button).onPressed, isNull);
    ed.select(['t', 'a']);
    await tester.pump();
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();
    expect((p.byId('t') as TextObject).pathId, 'a');
    expect(find.text('Release from path'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
