import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

/// A point on a contour. [cIn] and [cOut] are absolute cubic handles; a null
/// handle means the adjacent segment is straight on that side.
class PathNode {
  PathNode(this.p, {this.cIn, this.cOut});

  Offset p;
  Offset? cIn;
  Offset? cOut;

  bool get isCorner => cIn == null && cOut == null;

  PathNode copy() => PathNode(p, cIn: cIn, cOut: cOut);

  PathNode transformed(Offset Function(Offset) f) => PathNode(
        f(p),
        cIn: cIn == null ? null : f(cIn!),
        cOut: cOut == null ? null : f(cOut!),
      );

  List<double> toJson() => [
        p.dx, p.dy,
        if (cIn != null || cOut != null) ...[
          (cIn ?? p).dx, (cIn ?? p).dy, (cOut ?? p).dx, (cOut ?? p).dy,
        ],
      ];

  factory PathNode.fromJson(List<dynamic> j) {
    final v = j.map((e) => (e as num).toDouble()).toList();
    final p = Offset(v[0], v[1]);
    if (v.length < 6) return PathNode(p);
    final cIn = Offset(v[2], v[3]);
    final cOut = Offset(v[4], v[5]);
    return PathNode(p, cIn: cIn == p ? null : cIn, cOut: cOut == p ? null : cOut);
  }
}

/// One closed (or open) run of nodes.
class Contour {
  Contour(this.nodes, {this.closed = true});

  factory Contour.polyline(Iterable<Offset> pts, {bool closed = true}) =>
      Contour(pts.map((p) => PathNode(p)).toList(), closed: closed);

  final List<PathNode> nodes;
  bool closed;

  int get segmentCount => closed ? nodes.length : math.max(0, nodes.length - 1);

  Contour copy() => Contour(nodes.map((n) => n.copy()).toList(), closed: closed);

  Contour transformed(Offset Function(Offset) f) =>
      Contour(nodes.map((n) => n.transformed(f)).toList(), closed: closed);

  /// Control points of segment [i] (from node i to node i+1).
  (Offset, Offset, Offset, Offset) segment(int i) {
    final a = nodes[i];
    final b = nodes[(i + 1) % nodes.length];
    return (a.p, a.cOut ?? a.p, b.cIn ?? b.p, b.p);
  }

  bool segmentIsLine(int i) {
    final a = nodes[i];
    final b = nodes[(i + 1) % nodes.length];
    return a.cOut == null && b.cIn == null;
  }

  /// Polyline approximation. [tolerance] is the max chord error in local units.
  List<Offset> flatten([double tolerance = 0.05]) {
    if (nodes.isEmpty) return const [];
    final out = <Offset>[nodes.first.p];
    for (var i = 0; i < segmentCount; i++) {
      if (segmentIsLine(i)) {
        out.add(nodes[(i + 1) % nodes.length].p);
        continue;
      }
      final (p0, p1, p2, p3) = segment(i);
      final steps = cubicSteps(p0, p1, p2, p3, tolerance);
      for (var s = 1; s <= steps; s++) {
        out.add(cubicPoint(p0, p1, p2, p3, s / steps));
      }
    }
    if (closed && out.length > 1 && (out.first - out.last).distance < 1e-9) {
      out.removeLast();
    }
    return out;
  }

  Map<String, dynamic> toJson() => {
        'c': closed,
        'n': nodes.map((n) => n.toJson()).toList(),
      };

  factory Contour.fromJson(Map<String, dynamic> j) => Contour(
        (j['n'] as List).map((n) => PathNode.fromJson(n as List)).toList(),
        closed: j['c'] as bool? ?? true,
      );
}

int cubicSteps(Offset p0, Offset p1, Offset p2, Offset p3, double tolerance) {
  // Bound on second difference gives a safe subdivision count.
  final dd = math.max(
    (p0 - p1 * 2 + p2).distance,
    (p1 - p2 * 2 + p3).distance,
  );
  final n = math.sqrt(0.75 * dd / math.max(tolerance, 1e-6));
  return n.ceil().clamp(1, 512);
}

Offset cubicPoint(Offset p0, Offset p1, Offset p2, Offset p3, double t) {
  final mt = 1 - t;
  return p0 * (mt * mt * mt) +
      p1 * (3 * mt * mt * t) +
      p2 * (3 * mt * t * t) +
      p3 * (t * t * t);
}

/// Splits a cubic at [t], returning the two halves' control points.
((Offset, Offset, Offset, Offset), (Offset, Offset, Offset, Offset)) splitCubic(
    Offset p0, Offset p1, Offset p2, Offset p3, double t) {
  Offset lerp(Offset a, Offset b) => a + (b - a) * t;
  final a = lerp(p0, p1), b = lerp(p1, p2), c = lerp(p2, p3);
  final d = lerp(a, b), e = lerp(b, c);
  final f = lerp(d, e);
  return ((p0, a, d, f), (f, e, c, p3));
}

/// Affine placement of an object: scale, then rotate, then translate.
class Xform {
  const Xform({
    this.tx = 0,
    this.ty = 0,
    this.rotation = 0,
    this.sx = 1,
    this.sy = 1,
  });

  final double tx, ty;

  /// Radians, clockwise on screen (y points down).
  final double rotation;
  final double sx, sy;

  Offset get translation => Offset(tx, ty);

  Offset apply(Offset p) {
    final x = p.dx * sx, y = p.dy * sy;
    final c = math.cos(rotation), s = math.sin(rotation);
    return Offset(x * c - y * s + tx, x * s + y * c + ty);
  }

  Offset invert(Offset p) {
    final x = p.dx - tx, y = p.dy - ty;
    final c = math.cos(-rotation), s = math.sin(-rotation);
    return Offset((x * c - y * s) / sx, (x * s + y * c) / sy);
  }

  Xform copyWith({double? tx, double? ty, double? rotation, double? sx, double? sy}) => Xform(
        tx: tx ?? this.tx,
        ty: ty ?? this.ty,
        rotation: rotation ?? this.rotation,
        sx: sx ?? this.sx,
        sy: sy ?? this.sy,
      );

  Xform translated(Offset d) => copyWith(tx: tx + d.dx, ty: ty + d.dy);

  Float64List toMatrix4() {
    final c = math.cos(rotation), s = math.sin(rotation);
    return Float64List.fromList([
      c * sx, s * sx, 0, 0,
      -s * sy, c * sy, 0, 0,
      0, 0, 1, 0,
      tx, ty, 0, 1,
    ]);
  }

  Map<String, dynamic> toJson() => {'x': tx, 'y': ty, 'r': rotation, 'sx': sx, 'sy': sy};

  factory Xform.fromJson(Map<String, dynamic> j) => Xform(
        tx: (j['x'] as num).toDouble(),
        ty: (j['y'] as num).toDouble(),
        rotation: (j['r'] as num? ?? 0).toDouble(),
        sx: (j['sx'] as num? ?? 1).toDouble(),
        sy: (j['sy'] as num? ?? 1).toDouble(),
      );
}

Rect boundsOfPoints(Iterable<Offset> pts) {
  var l = double.infinity, t = double.infinity;
  var r = double.negativeInfinity, b = double.negativeInfinity;
  for (final p in pts) {
    if (p.dx < l) l = p.dx;
    if (p.dy < t) t = p.dy;
    if (p.dx > r) r = p.dx;
    if (p.dy > b) b = p.dy;
  }
  if (l == double.infinity) return Rect.zero;
  return Rect.fromLTRB(l, t, r, b);
}

Rect boundsOfContours(List<Contour> contours) =>
    boundsOfPoints(contours.expand((c) => c.flatten(0.2)));

Path contoursToPath(List<Contour> contours, {Offset Function(Offset)? map}) {
  final f = map ?? (Offset o) => o;
  final path = Path()..fillType = PathFillType.evenOdd;
  for (final c in contours) {
    if (c.nodes.isEmpty) continue;
    final s = f(c.nodes.first.p);
    path.moveTo(s.dx, s.dy);
    for (var i = 0; i < c.segmentCount; i++) {
      final (_, p1, p2, p3) = c.segment(i);
      if (c.segmentIsLine(i)) {
        final q = f(p3);
        path.lineTo(q.dx, q.dy);
      } else {
        final a = f(p1), b = f(p2), q = f(p3);
        path.cubicTo(a.dx, a.dy, b.dx, b.dy, q.dx, q.dy);
      }
    }
    if (c.closed) path.close();
  }
  return path;
}

/// Ramer–Douglas–Peucker simplification of a closed or open polyline.
List<Offset> simplifyPolyline(List<Offset> pts, double epsilon) {
  if (pts.length < 4) return List.of(pts);
  final keep = List<bool>.filled(pts.length, false);
  keep[0] = keep[pts.length - 1] = true;
  final stack = <(int, int)>[(0, pts.length - 1)];
  while (stack.isNotEmpty) {
    final (a, b) = stack.removeLast();
    var maxD = 0.0;
    var idx = -1;
    for (var i = a + 1; i < b; i++) {
      final d = distanceToSegment(pts[i], pts[a], pts[b]);
      if (d > maxD) {
        maxD = d;
        idx = i;
      }
    }
    if (idx >= 0 && maxD > epsilon) {
      keep[idx] = true;
      stack
        ..add((a, idx))
        ..add((idx, b));
    }
  }
  return [for (var i = 0; i < pts.length; i++) if (keep[i]) pts[i]];
}

double distanceToSegment(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
  if (len2 == 0) return (p - a).distance;
  final t = (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len2).clamp(0.0, 1.0);
  return (p - (a + ab * t)).distance;
}

double polygonArea(List<Offset> pts) {
  var a = 0.0;
  for (var i = 0; i < pts.length; i++) {
    final p = pts[i], q = pts[(i + 1) % pts.length];
    a += p.dx * q.dy - q.dx * p.dy;
  }
  return a / 2;
}
