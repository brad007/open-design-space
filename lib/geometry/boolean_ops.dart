import 'dart:ui';

import 'package:clipper2/clipper2.dart';

import '../model/geometry.dart';

typedef Polys = List<List<Offset>>;

const _precision = 4;

PathsD _toPaths(Polys polys) => [
      for (final p in polys)
        if (p.length > 2) [for (final o in p) PointD(o.dx, o.dy)],
    ];

Polys _fromPaths(PathsD paths) => [
      for (final p in paths)
        if (p.length > 2) [for (final pt in p) Offset(pt.x, pt.y)],
    ];

/// Normalizes each object's own fill (even-odd) before combining, so holes in
/// letters and shapes behave the same way they render.
Polys _normalize(Polys p) =>
    _fromPaths(Clipper.unionD(subject: _toPaths(p), clip: const [], fillRule: FillRule.evenOdd, precision: _precision));

/// Normalized shapes share an orientation, so a non-zero union of all of
/// them at once merges overlaps without cancelling holes.
Polys union(List<Polys> shapes) => _fromPaths(Clipper.unionD(
      subject: _toPaths([for (final s in shapes) ..._normalize(s)]),
      clip: const [],
      fillRule: FillRule.nonZero,
      precision: _precision,
    ));

Polys intersect(Polys a, Polys b) => _fromPaths(Clipper.intersectD(
      subject: _toPaths(_normalize(a)),
      clip: _toPaths(_normalize(b)),
      fillRule: FillRule.nonZero,
      precision: _precision,
    ));

Polys difference(Polys a, Polys b) => _fromPaths(Clipper.differenceD(
      subject: _toPaths(_normalize(a)),
      clip: _toPaths(_normalize(b)),
      fillRule: FillRule.nonZero,
      precision: _precision,
    ));

/// Grows (positive [distance]) or shrinks a filled shape.
Polys offsetPolys(Polys p, double distance, {bool rounded = true}) => _fromPaths(Clipper.inflatePathsD(
      paths: _toPaths(_normalize(p)),
      delta: distance,
      joinType: rounded ? JoinType.round : JoinType.miter,
      endType: EndType.polygon,
      miterLimit: 4,
      arcTolerance: 0.02,
      precision: _precision,
    ));

/// Outline of an open stroke, used by the eraser brush.
Polys strokeOutline(List<Offset> stroke, double width) {
  if (stroke.length == 1) stroke = [stroke.first, stroke.first + const Offset(0.01, 0)];
  return _fromPaths(Clipper.inflatePathsD(
    paths: [
      [for (final o in stroke) PointD(o.dx, o.dy)],
    ],
    delta: width / 2,
    joinType: JoinType.round,
    endType: EndType.round,
    arcTolerance: 0.02,
    precision: _precision,
  ));
}

/// Converts boolean output back into editable contours, dropping slivers and
/// thinning near-collinear points.
List<Contour> polysToContours(Polys polys, {double simplify = 0.01, double minArea = 0.01}) => [
      for (final p in polys)
        if (polygonArea(p).abs() >= minArea)
          Contour.polyline(simplifyPolyline([...p, p.first], simplify)..removeLast()),
    ];
