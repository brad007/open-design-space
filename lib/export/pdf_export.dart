import 'dart:typed_data';
import 'dart:ui';

import 'package:pdf/pdf.dart';
import 'package:vector_math/vector_math_64.dart' show Matrix4;

import '../mat/mat_planner.dart';
import '../model/geometry.dart';
import '../model/objects.dart';
import '../model/project.dart';
import 'svg_export.dart';

const _pt = 72 / 25.4;

PdfColor _color(int c) => PdfColor.fromInt(c | 0xFF000000);

class _Page {
  _Page(this.doc, this.widthMm, this.heightMm, this.origin)
      : page = PdfPage(doc, pageFormat: PdfPageFormat(widthMm * _pt, heightMm * _pt)) {
    g = page.getGraphics();
  }

  final PdfDocument doc;
  final double widthMm, heightMm;

  /// Design point that lands at the page's top-left.
  final Offset origin;
  final PdfPage page;
  late final PdfGraphics g;

  Offset map(Offset p) => Offset((p.dx - origin.dx) * _pt, (heightMm - (p.dy - origin.dy)) * _pt);

  void tracePath(List<Contour> contours, Offset Function(Offset) toDesign) {
    for (final c in contours) {
      if (c.nodes.isEmpty) continue;
      final s = map(toDesign(c.nodes.first.p));
      g.moveTo(s.dx, s.dy);
      for (var i = 0; i < c.segmentCount; i++) {
        final (_, p1, p2, p3) = c.segment(i);
        final q = map(toDesign(p3));
        if (c.segmentIsLine(i)) {
          g.lineTo(q.dx, q.dy);
        } else {
          final a = map(toDesign(p1)), b = map(toDesign(p2));
          g.curveTo(a.dx, a.dy, b.dx, b.dy, q.dx, q.dy);
        }
      }
      if (c.closed) g.closePath();
    }
  }

  void polylines(List<List<Offset>> polys, {bool closed = false}) {
    for (final p in polys) {
      if (p.isEmpty) continue;
      final s = map(p.first);
      g.moveTo(s.dx, s.dy);
      for (final q in p.skip(1)) {
        final m = map(q);
        g.lineTo(m.dx, m.dy);
      }
      if (closed) g.closePath();
    }
  }

  /// Draws an image object, with [shift] moving it from canvas to page space.
  void image(ImageObject o, Asset asset, Offset shift) {
    final img = PdfImage.file(doc, bytes: Uint8List.fromList(asset.bytes));
    final x = o.xform.translated(shift - origin);
    final m = x.toMatrix4();
    // Page transform (mm, y-down) → points, y-up.
    final page = Matrix4.identity()
      ..translateByDouble(0, heightMm * _pt, 0, 1)
      ..scaleByDouble(_pt, -_pt, 1, 1);
    final local = Matrix4.fromFloat64List(m);
    g.saveContext();
    g.setTransform(page * local);
    final vis = o.visibleRect;
    g.drawRect(vis.left, vis.top, vis.width, vis.height);
    g.clipPath();
    final full = o.fullRect;
    // Flip back so the image is upright in this y-down space.
    g.setTransform(Matrix4.identity()
      ..translateByDouble(full.left, full.bottom, 0, 1)
      ..scaleByDouble(1, -1, 1, 1));
    g.drawImage(img, 0, 0, full.width, full.height);
    g.restoreContext();
  }

  void fillObject(DesignObject o, Offset shift) {
    final closed = o.localContours.every((c) => c.closed);
    tracePath(o.localContours, (p) => o.xform.apply(p) + shift);
    if (closed && o.operation != Operation.score && o.operation != Operation.draw) {
      g.setFillColor(_color(o.color));
      g.fillPath(evenOdd: true);
    } else {
      g.setStrokeColor(_color(o.color));
      g.setLineWidth(0.5 * _pt);
      g.strokePath();
    }
  }
}

/// The whole design as a vector PDF at actual size.
Future<Uint8List> exportDesignPdf(Project p) async {
  final r = designBounds(p).inflate(2);
  final doc = PdfDocument();
  final page = _Page(doc, r.width, r.height, r.topLeft);
  for (final o in p.objects) {
    if (!o.visible) continue;
    if (o is ImageObject) {
      final a = p.assets[o.assetId];
      if (a != null) page.image(o, a, Offset.zero);
    } else {
      page.fillObject(o, Offset.zero);
    }
  }
  return doc.save();
}

/// The printable sheet for a Print then Cut mat: artwork plus registration
/// marks, at actual size. Print with scaling turned off.
Future<Uint8List> exportPrintSheetPdf(Mat mat, Project p) async {
  final doc = PdfDocument();
  final page = _Page(doc, mat.size.width, mat.size.height, Offset.zero);
  for (final it in mat.items) {
    final shift = it.offset - it.origin;
    for (final o in it.objects) {
      if (o is ImageObject) {
        final a = p.assets[o.assetId];
        if (a != null) page.image(o, a, shift);
      } else {
        page.fillObject(o, shift);
      }
    }
  }
  page.g.setStrokeColor(PdfColors.black);
  page.g.setLineWidth(0.5 * _pt);
  final marks = registrationMarks(mat, p.mat);
  page.g.setFillColor(PdfColors.black);
  page.polylines([marks.first], closed: true);
  page.g.fillPath();
  page.polylines(marks.sublist(1));
  page.g.strokePath();
  return doc.save();
}
