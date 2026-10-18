// Draws the app icon and writes the source images into assets/icon/.
// Run with: flutter test test/app_icon_test.dart --dart-define=ICON=true
// then: dart run flutter_launcher_icons
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_design_space/geometry/shapes.dart';
import 'package:open_design_space/model/geometry.dart';
import 'package:open_design_space/ui/render.dart';

const enabled = bool.fromEnvironment('ICON');
const teal = Color(0xFF12A594);
const tealDark = Color(0xFF0B7A6E);
const coral = Color(0xFFFF7A59);

/// The mark: a white heart (the design) inside a dashed outline (the cut
/// path), with a small blade on the line. [box] is the square it fills.
void paintMark(Canvas canvas, Rect box, {Color heartColor = Colors.white, Color bladeColor = coral, Color lineColor = Colors.white}) {
  final s = box.width;
  final heart = buildShape(ShapeKind.heart, size: s * 0.56).first;
  final center = box.center + Offset(0, s * 0.02);
  final heartPath = contoursToPath([heart], map: (p) => p + center);
  canvas.drawPath(heartPath, Paint()..color = heartColor);

  // Cut line: the heart grown outward, drawn dashed.
  final cut = buildShape(ShapeKind.heart, size: s * 0.80).first;
  final cutPath = contoursToPath([cut], map: (p) => p + center + Offset(0, -s * 0.012));
  drawDashed(
    canvas,
    cutPath,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.028
      ..strokeCap = StrokeCap.round
      ..color = lineColor.withValues(alpha: 0.9),
    s * 0.05,
    s * 0.035,
  );

  // Blade riding on the cut line, lower right.
  final metric = cutPath.computeMetrics().first;
  final t = metric.getTangentForOffset(metric.length * 0.36)!;
  canvas.save();
  canvas.translate(t.position.dx, t.position.dy);
  canvas.rotate(-t.angle + math.pi / 2);
  final r = s * 0.075;
  final blade = Path()
    ..moveTo(0, r * 1.2)
    ..lineTo(-r * 0.75, -r * 0.6)
    ..quadraticBezierTo(0, -r * 1.05, r * 0.75, -r * 0.6)
    ..close();
  canvas.drawShadow(blade, Colors.black, s * 0.01, true);
  canvas.drawPath(blade, Paint()..color = bladeColor);
  canvas.restore();
}

void paintBackground(Canvas canvas, RRect shape) {
  canvas.drawRRect(
    shape,
    Paint()
      ..shader = ui.Gradient.linear(shape.outerRect.topLeft, shape.outerRect.bottomRight, [const Color(0xFF1CC2AC), tealDark]),
  );
}

Future<void> writePng(String path, int size, void Function(Canvas) draw) async {
  final rec = ui.PictureRecorder();
  draw(Canvas(rec));
  final img = await rec.endRecording().toImage(size, size);
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(data!.buffer.asUint8List());
}

void main() {
  test('render app icon sources', () async {
    const n = 1024.0;
    const full = Rect.fromLTWH(0, 0, n, n);

    // iOS, Windows, web, Android legacy: full-bleed square (the OS rounds it).
    await writePng('assets/icon/icon.png', 1024, (c) {
      paintBackground(c, RRect.fromRectAndRadius(full, Radius.zero));
      paintMark(c, full.deflate(n * 0.08));
    });

    // macOS: the rounded square sits inside the canvas with a soft shadow,
    // matching the system icon grid (824 px body on a 1024 canvas).
    await writePng('assets/icon/icon_macos.png', 1024, (c) {
      final body = Rect.fromCenter(center: const Offset(n / 2, n / 2 - 6), width: 824, height: 824);
      final rr = RRect.fromRectAndRadius(body, const Radius.circular(185));
      c.drawRRect(rr.shift(const Offset(0, 10)), Paint()
        ..color = Colors.black.withValues(alpha: 0.28)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14));
      paintBackground(c, rr);
      paintMark(c, body.deflate(824 * 0.08));
    });

    // iOS dark appearance: the system draws its own dark tile behind this.
    await writePng('assets/icon/icon_ios_dark.png', 1024, (c) => paintMark(c, full.deflate(n * 0.08), heartColor: const Color(0xFF1CC2AC)));

    // iOS tinted appearance: grayscale; the system applies the user's tint.
    await writePng('assets/icon/icon_ios_tinted.png', 1024, (c) {
      c.drawRect(full, Paint()..color = Colors.black);
      paintMark(c, full.deflate(n * 0.08), bladeColor: const Color(0xFFBDBDBD), lineColor: const Color(0xFFDDDDDD));
    });

    // Android adaptive foreground: keep the mark inside the 66% safe zone.
    await writePng('assets/icon/foreground.png', 1024, (c) => paintMark(c, full.deflate(n * 0.22)));

    // Preview of how it reads at small sizes.
    await writePng('build/icon_preview.png', 512, (c) {
      c.drawRect(const Rect.fromLTWH(0, 0, 512, 512), Paint()..color = const Color(0xFFF2F4F3));
      var x = 16.0;
      for (final size in [256.0, 128.0, 64.0, 32.0]) {
        final r = Rect.fromLTWH(x, 128, size, size);
        paintBackground(c, RRect.fromRectAndRadius(r, Radius.circular(size * 0.22)));
        paintMark(c, r.deflate(size * 0.08));
        x += size + 12;
      }
    });
  }, skip: !enabled);
}
