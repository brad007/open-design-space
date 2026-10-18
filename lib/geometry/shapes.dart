import 'dart:math' as math;
import 'dart:ui';

import '../model/geometry.dart';

enum ShapeKind {
  square('Square'),
  circle('Circle'),
  triangle('Triangle'),
  polygon('Hexagon'),
  star('Star'),
  heart('Heart'),
  line('Score line');

  const ShapeKind(this.label);
  final String label;
}

/// Shapes are built centered on the origin, [size] millimetres across.
List<Contour> buildShape(ShapeKind kind, {double size = 50}) {
  final h = size / 2;
  switch (kind) {
    case ShapeKind.square:
      return [rectContour(Rect.fromCenter(center: Offset.zero, width: size, height: size))];
    case ShapeKind.circle:
      return [ellipseContour(Rect.fromCenter(center: Offset.zero, width: size, height: size))];
    case ShapeKind.triangle:
      return [regularPolygon(3, h)];
    case ShapeKind.polygon:
      return [regularPolygon(6, h)];
    case ShapeKind.star:
      return [star(5, h, h * 0.42)];
    case ShapeKind.heart:
      return [heart(size)];
    case ShapeKind.line:
      return [Contour.polyline([Offset(-h, 0), Offset(h, 0)], closed: false)];
  }
}

Contour rectContour(Rect r) =>
    Contour.polyline([r.topLeft, r.topRight, r.bottomRight, r.bottomLeft]);

Contour ellipseContour(Rect r) {
  const k = 0.5522847498;
  final c = r.center;
  final rx = r.width / 2, ry = r.height / 2;
  final kx = rx * k, ky = ry * k;
  return Contour([
    PathNode(c + Offset(0, -ry), cIn: c + Offset(-kx, -ry), cOut: c + Offset(kx, -ry)),
    PathNode(c + Offset(rx, 0), cIn: c + Offset(rx, -ky), cOut: c + Offset(rx, ky)),
    PathNode(c + Offset(0, ry), cIn: c + Offset(kx, ry), cOut: c + Offset(-kx, ry)),
    PathNode(c + Offset(-rx, 0), cIn: c + Offset(-rx, ky), cOut: c + Offset(-rx, -ky)),
  ]);
}

Contour regularPolygon(int sides, double radius) => Contour.polyline([
      for (var i = 0; i < sides; i++)
        Offset.fromDirection(-math.pi / 2 + i * 2 * math.pi / sides, radius),
    ]);

Contour star(int points, double outer, double inner) => Contour.polyline([
      for (var i = 0; i < points * 2; i++)
        Offset.fromDirection(-math.pi / 2 + i * math.pi / points, i.isEven ? outer : inner),
    ]);

Contour heart(double size) {
  final s = size / 100;
  Offset p(double x, double y) => Offset(x * s, y * s);
  return Contour([
    PathNode(p(0, -22), cIn: p(-10, -50), cOut: p(10, -50)),
    PathNode(p(50, -18), cIn: p(48, -50), cOut: p(52, 10)),
    PathNode(p(0, 45), cIn: p(18, 30), cOut: p(-18, 30)),
    PathNode(p(-50, -18), cIn: p(-52, 10), cOut: p(-48, -50)),
  ]);
}
