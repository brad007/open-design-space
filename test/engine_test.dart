import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_design_space/export/plotter_export.dart';
import 'package:open_design_space/export/svg_export.dart';
import 'package:open_design_space/geometry/boolean_ops.dart';
import 'package:open_design_space/geometry/node_ops.dart';
import 'package:open_design_space/geometry/shapes.dart';
import 'package:open_design_space/geometry/svg_import.dart';
import 'package:open_design_space/geometry/trace.dart';
import 'package:open_design_space/mat/mat_planner.dart';
import 'package:open_design_space/model/geometry.dart';
import 'package:open_design_space/model/objects.dart';
import 'package:open_design_space/model/project.dart';
import 'package:open_design_space/platform/platform.dart';
import 'package:open_design_space/storage/project_store.dart';
import 'package:open_design_space/text/text_layout.dart';
import 'package:open_design_space/text/ttf.dart';

double areaOf(Polys p) => p.fold(0.0, (a, e) => a + polygonArea(e));

PathObject square(String id, double cx, double cy, double size, {int color = 0xFFFF0000}) => PathObject(
      id: id,
      name: id,
      contours: buildShape(ShapeKind.square, size: size),
      color: color,
      xform: Xform(tx: cx, ty: cy),
    );

void main() {
  group('geometry', () {
    test('circle flattening stays on the radius', () {
      final pts = buildShape(ShapeKind.circle, size: 100).first.flatten(0.01);
      for (final p in pts) {
        expect(p.distance, closeTo(50, 0.05));
      }
    });

    test('xform round-trips', () {
      const x = Xform(tx: 10, ty: -5, rotation: 0.7, sx: 2, sy: 0.5);
      const p = Offset(3, 4);
      final q = x.invert(x.apply(p));
      expect(q.dx, closeTo(p.dx, 1e-9));
      expect(q.dy, closeTo(p.dy, 1e-9));
    });

    test('union, intersect, difference areas', () {
      final a = square('a', 0, 0, 10).worldPolylines();
      final b = square('b', 5, 0, 10).worldPolylines();
      expect(areaOf(union([a, b])).abs(), closeTo(150, 0.01));
      expect(areaOf(intersect(a, b)).abs(), closeTo(50, 0.01));
      expect(areaOf(difference(a, b)).abs(), closeTo(50, 0.01));
    });

    test('offset grows a square', () {
      final a = square('a', 0, 0, 10).worldPolylines();
      final grown = offsetPolys(a, 1, rounded: false);
      expect(areaOf(grown).abs(), closeTo(144, 0.1));
    });

    test('inserting a node keeps a curve in place', () {
      final c = buildShape(ShapeKind.circle, size: 20).first;
      final before = cubicPoint(c.segment(0).$1, c.segment(0).$2, c.segment(0).$3, c.segment(0).$4, 0.5);
      insertNode(c, 0, 0.5);
      expect(c.nodes.length, 5);
      expect((c.nodes[1].p - before).distance, lessThan(1e-9));
    });

    test('trace finds a filled square with a hole', () {
      const w = 20, h = 20;
      final px = Uint8List(w * h * 4);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final on = x >= 4 && x < 16 && y >= 4 && y < 16 && !(x >= 8 && x < 12 && y >= 8 && y < 12);
          final i = (y * w + x) * 4;
          px[i] = px[i + 1] = px[i + 2] = on ? 0 : 255;
          px[i + 3] = 255;
        }
      }
      final loops = traceImage(px, w, h, simplify: 0.1);
      expect(loops.length, 2);
      final areas = loops.map((l) => polygonArea(l).abs()).toList()..sort();
      expect(areas, [16, 144]);
    });
  });

  group('svg import', () {
    test('reads shapes, transforms and units', () {
      const svg = '''
<svg xmlns="http://www.w3.org/2000/svg" width="100mm" height="50mm" viewBox="0 0 200 100">
  <g transform="translate(10 0)" fill="#00ff00">
    <rect x="0" y="0" width="20" height="20"/>
    <path d="M 50 50 L 70 50 L 70 70 Z" fill="red"/>
  </g>
  <circle cx="150" cy="50" r="10" style="fill:#123456"/>
</svg>''';
      final shapes = importSvg(svg);
      expect(shapes.length, 3);
      final rect = boundsOfContours(shapes[0].contours);
      expect(rect.left, closeTo(5, 1e-6));
      expect(rect.width, closeTo(10, 1e-6));
      expect(shapes[0].color, 0xFF00FF00);
      expect(shapes[1].color, 0xFFFF0000);
      expect(shapes[2].color, 0xFF123456);
      expect(boundsOfContours(shapes[2].contours).width, closeTo(10, 0.01));
    });

    test('exported design SVG imports back to the same geometry', () {
      final p = Project(meta: ProjectMeta(id: 'x', name: 'x', created: DateTime(2026), updated: DateTime(2026)));
      p.objects.add(square('s', 30, 40, 20));
      final back = importSvg(exportDesignSvg(p));
      final b = boundsOfContours(back.single.contours);
      expect(b.width, closeTo(20, 0.01));
    });
  });

  group('fonts', () {
    final arial = File('/System/Library/Fonts/Supplemental/Arial.ttf');
    final helvetica = File('/System/Library/Fonts/Helvetica.ttc');

    test('parses a TrueType font and lays out text', () {
      final font = TrueTypeFont(arial.readAsBytesSync());
      expect(font.family, 'Arial');
      expect(font.glyphIndex('A'.codeUnitAt(0)), greaterThan(0));
      final t = TextObject(id: 't', name: 't', text: 'Hello\nWorld', fontFamily: 'Arial', size: 10);
      final outline = layoutText(t, font);
      expect(outline, isNotEmpty);
      final b = boundsOfContours(outline);
      expect(b.center.distance, lessThan(0.01));
      expect(b.width, greaterThan(20));
      // 'o' has an inner counter, so there are more contours than letters.
      expect(outline.length, greaterThan(10));
    }, skip: !arial.existsSync());

    test('letter spacing and curve change the layout', () {
      final font = TrueTypeFont(arial.readAsBytesSync());
      TextObject mk({double ls = 0, double curve = 0}) =>
          TextObject(id: 't', name: 't', text: 'ABCDEFG', fontFamily: 'Arial', size: 10, letterSpacing: ls, curve: curve);
      final plain = boundsOfContours(layoutText(mk(), font));
      final wide = boundsOfContours(layoutText(mk(ls: 0.5), font));
      final arched = boundsOfContours(layoutText(mk(curve: 180), font));
      expect(wide.width, greaterThan(plain.width + 20));
      expect(arched.height, greaterThan(plain.height * 2));
    }, skip: !arial.existsSync());

    test('bundled Roboto parses and lays out on every platform', () {
      final font = TrueTypeFont(File('assets/fonts/Roboto-Regular.ttf').readAsBytesSync());
      expect(font.family, 'Roboto');
      final t = TextObject(id: 't', name: 't', text: 'Cut me', fontFamily: 'Roboto', size: 10);
      expect(layoutText(t, font), isNotEmpty);
    });

    test('reads faces from a collection', () {
      final bytes = helvetica.readAsBytesSync();
      expect(fontFaceCount(bytes), greaterThan(1));
      final names = TrueTypeFont.probe(bytes, 1);
      expect(names?.$1, 'Helvetica');
    }, skip: !helvetica.existsSync());
  });

  group('project', () {
    test('json round trip', () {
      final p = Project(meta: ProjectMeta(id: 'p', name: 'Test', created: DateTime(2026), updated: DateTime(2026)));
      p.objects.add(square('s', 1, 2, 3)..groupId = 'g');
      p.objects.add(TextObject(id: 't', name: 'T', text: 'Hi', fontFamily: 'Arial', curve: 45)
        ..outline = buildShape(ShapeKind.circle));
      p.assets['a'] = Asset('image/png', [1, 2, 3]);
      p.objects.add(ImageObject(id: 'i', name: 'I', assetId: 'a', width: 10, height: 5, crop: const Rect.fromLTRB(-1, -1, 1, 1)));
      p.mat.placements['s'] = MatPlacement('c:FF0000#1', const Offset(5, 6));
      final back = Project.decode(p.encode());
      expect(back.objects.length, 3);
      expect(back.objects[0].groupId, 'g');
      expect((back.objects[1] as TextObject).curve, 45);
      expect((back.objects[1] as TextObject).outline.length, 1);
      expect((back.objects[2] as ImageObject).crop, const Rect.fromLTRB(-1, -1, 1, 1));
      expect(back.assets['a']!.bytes, [1, 2, 3]);
      expect(back.mat.placements['s']!.offset, const Offset(5, 6));
      expect(jsonDecode(back.encode())['format'], projectFormat);
    });

    test('store saves, snapshots, trashes and restores', () async {
      final dir = await Directory.systemTemp.createTemp('ods');
      setDataDirForTesting(dir.path);
      final store = await ProjectStore.open();
      final p = store.create('One')..objects.add(square('s', 0, 0, 10));
      await store.save(p);
      await store.snapshot(p);
      expect((await store.list()).single.name, 'One');
      expect(await store.snapshots(p.meta.id), hasLength(1));
      await store.trash(p.meta.id);
      expect(await store.list(), isEmpty);
      expect((await store.list(trash: true)).single.id, p.meta.id);
      await store.restore(p.meta.id);
      expect((await store.load(p.meta.id))!.objects.single.id, 's');
      await dir.delete(recursive: true);
    });
  });

  group('mats', () {
    Project withSquares() {
      final p = Project(meta: ProjectMeta(id: 'p', name: 'p', created: DateTime(2026), updated: DateTime(2026)));
      p.objects
        ..add(square('r1', 0, 0, 50))
        ..add(square('r2', 200, 200, 50))
        ..add(square('b1', 0, 0, 30, color: 0xFF0000FF));
      return p;
    }

    test('splits by color and packs', () {
      final mats = planMats(withSquares());
      expect(mats.length, 2);
      final red = mats.firstWhere((m) => m.baseKey == 'c:FF0000');
      expect(red.items.length, 2);
      final usable = red.usable(MatSettings());
      for (final it in red.items) {
        expect(usable.inflate(1e-6).contains(it.rect.topLeft), isTrue);
      }
      expect(red.items[0].rect.overlaps(red.items[1].rect), isFalse);
    });

    test('keeps canvas arrangement when auto-pack is off', () {
      final p = withSquares()..mat.autoPack = false;
      final red = planMats(p).firstWhere((m) => m.baseKey == 'c:FF0000');
      final d = red.items[1].offset - red.items[0].offset;
      expect(d.dx.abs(), closeTo(200, 1e-6));
    });

    test('respects manual placement and mat order', () {
      final p = withSquares();
      p.mat.placements['r1'] = MatPlacement('c:FF0000#1', const Offset(100, 100));
      p.mat.order = ['c:0000FF#1'];
      final mats = planMats(p);
      expect(mats.first.baseKey, 'c:0000FF');
      final r1 = mats.last.items.firstWhere((i) => i.key == 'r1');
      expect(r1.offset, const Offset(100, 100));
    });

    test('oversized items go on their own mat with a warning', () {
      final p = withSquares()..objects.add(square('huge', 0, 0, 400));
      final red = planMats(p).where((m) => m.baseKey == 'c:FF0000').toList();
      expect(red.length, 2);
      expect(red.any((m) => m.warnings.isNotEmpty), isTrue);
    });

    test('plotter exports', () {
      final mat = planMats(withSquares()).first;
      final dxf = exportMatDxf(mat);
      expect(dxf, contains('POLYLINE'));
      expect(dxf.trim().endsWith('EOF'), isTrue);
      final hpgl = exportMatHpgl(mat);
      expect(hpgl, startsWith('IN;'));
      expect(RegExp('PD').allMatches(hpgl).length, mat.items.length);
      expect(exportMatSvg(mat, MatSettings()), contains('<path'));
    });
  });
}
