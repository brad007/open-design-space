import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../model/geometry.dart';
import '../model/objects.dart';
import '../model/project.dart';
import '../state/editor.dart';
import 'image_cache.dart';
import 'render.dart';

/// Maps millimetres to screen pixels.
class CanvasViewport extends ChangeNotifier {
  double zoom = 2.5;
  Offset pan = const Offset(40, 40);
  Size size = Size.zero;

  Offset toScreen(Offset w) => w * zoom + pan;
  Offset toWorld(Offset s) => (s - pan) / zoom;

  void zoomAt(Offset screen, double factor) {
    final before = toWorld(screen);
    zoom = (zoom * factor).clamp(0.2, 80.0);
    pan = screen - before * zoom;
    notifyListeners();
  }

  void panBy(Offset d) {
    pan += d;
    notifyListeners();
  }

  void fit(Rect world, {double padding = 40}) {
    if (size.isEmpty || world.isEmpty) return;
    zoom = math
        .min((size.width - padding * 2) / world.width, (size.height - padding * 2) / world.height)
        .clamp(0.2, 80.0);
    pan = Offset(size.width / 2, size.height / 2) - world.center * zoom;
    notifyListeners();
  }

  Offset get worldCenter => toWorld(Offset(size.width / 2, size.height / 2));
}

enum _Handle { tl, t, tr, r, br, b, bl, l, rotate }

enum _Drag { none, pan, pinch, move, scale, rotate, marquee, node, handleIn, handleOut, pen, eraser, crop }

class CanvasView extends StatefulWidget {
  const CanvasView({
    super.key,
    required this.editor,
    required this.images,
    required this.viewport,
    required this.lockRatio,
    this.onEditText,
    this.onCursor,
  });

  final EditorController editor;
  final AssetImages images;
  final CanvasViewport viewport;
  final ValueNotifier<bool> lockRatio;
  final void Function(TextObject)? onEditText;
  final void Function(Offset world)? onCursor;

  @override
  State<CanvasView> createState() => _CanvasViewState();
}

class _CanvasViewState extends State<CanvasView> {
  EditorController get ed => widget.editor;
  CanvasViewport get vp => widget.viewport;

  final focus = FocusNode(debugLabel: 'canvas');
  _Drag drag = _Drag.none;
  _Handle? handle;
  Offset startScreen = Offset.zero, startWorld = Offset.zero;
  Rect? startBounds;
  Map<String, Xform> startXforms = {};
  Rect? marquee;
  List<Offset> stroke = [];
  Offset? cursorWorld;
  List<(Offset, Offset)> guides = [];
  DateTime lastTap = DateTime(0);
  Offset lastTapPos = Offset.zero;
  (int, int)? dragNode;
  double startAngle = 0;

  /// Active pointers, for two-finger pinch and pan.
  final pointers = <int, Offset>{};
  bool _touch = false;
  Offset _pinchCenter = Offset.zero;
  double _pinchDistance = 1;

  /// Fingers need bigger targets than a mouse.
  double get _hitRadius => _touch ? 16 : 7;

  (Offset, double) _pinchState() {
    final pts = pointers.values.take(2).toList();
    return ((pts[0] + pts[1]) / 2, math.max((pts[0] - pts[1]).distance, 1));
  }

  /// A second finger cancels whatever the first one started and begins a
  /// pinch: zoom with the spread, pan with the midpoint.
  void _startPinch() {
    switch (drag) {
      case _Drag.move || _Drag.scale || _Drag.rotate:
        _restoreStart();
        ed.endGesture();
      case _Drag.node || _Drag.handleIn || _Drag.handleOut:
        // Keep the point where the first finger left it.
        ed.endGesture();
      default:
        break;
    }
    stroke = [];
    marquee = null;
    guides = [];
    drag = _Drag.pinch;
    final (c, d) = _pinchState();
    _pinchCenter = c;
    _pinchDistance = d;
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    ed.addListener(_repaint);
    vp.addListener(_repaint);
    widget.images.addListener(_repaint);
  }

  @override
  void dispose() {
    ed.removeListener(_repaint);
    vp.removeListener(_repaint);
    widget.images.removeListener(_repaint);
    focus.dispose();
    super.dispose();
  }

  void _repaint() => setState(() {});

  bool get _shift => HardwareKeyboard.instance.isShiftPressed;
  bool get _space => HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.space);

  Rect? get _selScreen {
    final b = ed.selectionBounds();
    if (b == null) return null;
    return Rect.fromPoints(vp.toScreen(b.topLeft), vp.toScreen(b.bottomRight));
  }

  Map<_Handle, Offset> _handles(Rect r) => {
    _Handle.tl: r.topLeft,
    _Handle.t: r.topCenter,
    _Handle.tr: r.topRight,
    _Handle.r: r.centerRight,
    _Handle.br: r.bottomRight,
    _Handle.b: r.bottomCenter,
    _Handle.bl: r.bottomLeft,
    _Handle.l: r.centerLeft,
    _Handle.rotate: r.topCenter - const Offset(0, 28),
  };

  _Handle? _hitHandle(Offset s) {
    final r = _selScreen;
    if (r == null || ed.tool != Tool.select || ed.selected.every((o) => o.locked)) return null;
    for (final e in _handles(r).entries) {
      if ((e.value - s).distance <= _hitRadius + 2) return e.key;
    }
    return null;
  }

  /// Hit test node-tool targets in screen space.
  (_Drag, int, int)? _hitNode(Offset s) {
    final o = ed.nodeTarget;
    if (o == null) return null;
    for (var ci = 0; ci < o.contours.length; ci++) {
      final c = o.contours[ci];
      for (var ni = 0; ni < c.nodes.length; ni++) {
        final n = c.nodes[ni];
        if (ed.activeNode == (ci, ni)) {
          if (n.cIn != null && (vp.toScreen(o.xform.apply(n.cIn!)) - s).distance <= _hitRadius) return (_Drag.handleIn, ci, ni);
          if (n.cOut != null && (vp.toScreen(o.xform.apply(n.cOut!)) - s).distance <= _hitRadius) {
            return (_Drag.handleOut, ci, ni);
          }
        }
        if ((vp.toScreen(o.xform.apply(n.p)) - s).distance <= _hitRadius) return (_Drag.node, ci, ni);
      }
    }
    return null;
  }

  void _captureStart() {
    startXforms = {for (final o in ed.selected) o.id: o.xform};
    startBounds = ed.selectionBounds();
  }

  void _restoreStart() {
    for (final o in ed.selected) {
      final x = startXforms[o.id];
      if (x != null) o.xform = x;
    }
  }

  void _onDown(PointerDownEvent e) {
    focus.requestFocus();
    pointers[e.pointer] = e.localPosition;
    _touch = e.kind == PointerDeviceKind.touch || e.kind == PointerDeviceKind.stylus;
    if (pointers.length >= 2) return _startPinch();
    if (drag == _Drag.pinch) return;
    final s = e.localPosition;
    final w = vp.toWorld(s);
    startScreen = s;
    startWorld = w;
    guides = [];
    if (e.buttons == kMiddleMouseButton || _space) {
      drag = _Drag.pan;
      return;
    }
    if (e.buttons == kSecondaryMouseButton) return;

    final now = DateTime.now();
    final isDouble = now.difference(lastTap) < const Duration(milliseconds: 350) && (s - lastTapPos).distance < 6;
    lastTap = now;
    lastTapPos = s;
    final tol = (_touch ? 10 : 4) / vp.zoom;

    switch (ed.tool) {
      case Tool.pen:
        drag = _Drag.pen;
        stroke = [w];
      case Tool.eraser:
        drag = _Drag.eraser;
        stroke = [w];
      case Tool.crop:
        drag = _Drag.crop;
        marquee = Rect.fromPoints(w, w);
      case Tool.node:
        final hit = _hitNode(s);
        if (hit != null) {
          ed.beginGesture();
          drag = hit.$1;
          dragNode = (hit.$2, hit.$3);
          ed.activeNode = dragNode;
          ed.updateGesture();
          return;
        }
        final o = ed.hitTest(w, tol);
        if (isDouble && o != null && o.id == ed.nodeTarget?.id) {
          ed.insertNodeAt(w);
          return;
        }
        if (o != null) {
          ed.select([o.id], expandGroups: false);
        } else {
          ed.clearSelection();
        }
      case Tool.select:
        final h = _hitHandle(s);
        if (h != null) {
          ed.beginGesture();
          _captureStart();
          handle = h;
          drag = h == _Handle.rotate ? _Drag.rotate : _Drag.scale;
          if (drag == _Drag.rotate) {
            final c = startBounds!.center;
            startAngle = math.atan2(w.dy - c.dy, w.dx - c.dx);
          }
          return;
        }
        final o = ed.hitTest(w, tol);
        if (o == null) {
          if (!_shift) ed.clearSelection();
          drag = _Drag.marquee;
          marquee = Rect.fromPoints(w, w);
          return;
        }
        if (isDouble) {
          if (o is TextObject) {
            ed.select([o.id], expandGroups: false);
            widget.onEditText?.call(o);
          } else if (o is PathObject) {
            ed.select([o.id], expandGroups: false);
            ed.setTool(Tool.node);
          }
          return;
        }
        if (_shift) {
          ed.select([o.id], additive: true);
        } else if (!ed.selection.contains(o.id)) {
          ed.select([o.id]);
        }
        if (ed.selection.isNotEmpty) {
          ed.beginGesture();
          _captureStart();
          drag = _Drag.move;
        }
    }
  }

  void _onMove(PointerMoveEvent e) {
    pointers[e.pointer] = e.localPosition;
    if (drag == _Drag.pinch) {
      if (pointers.length < 2) return;
      final (c, d) = _pinchState();
      vp.zoomAt(_pinchCenter, d / _pinchDistance);
      vp.panBy(c - _pinchCenter);
      _pinchCenter = c;
      _pinchDistance = d;
      return;
    }
    final s = e.localPosition;
    final w = vp.toWorld(s);
    cursorWorld = w;
    widget.onCursor?.call(w);
    switch (drag) {
      case _Drag.none || _Drag.pinch:
        return;
      case _Drag.pan:
        vp.panBy(e.delta);
      case _Drag.move:
        _restoreStart();
        var d = w - startWorld;
        if (_shift) d = d.dx.abs() > d.dy.abs() ? Offset(d.dx, 0) : Offset(0, d.dy);
        if (ed.snapping && startBounds != null) d = _snap(d);
        ed.translateSelected(d);
        ed.updateGesture();
      case _Drag.scale:
        _scaleDrag(w);
      case _Drag.rotate:
        _restoreStart();
        final c = startBounds!.center;
        var a = math.atan2(w.dy - c.dy, w.dx - c.dx) - startAngle;
        if (_shift || ed.snapping) a = (a / (math.pi / 12)).round() * (math.pi / 12);
        ed.rotateSelection(a, c, record: false);
        ed.updateGesture();
      case _Drag.marquee || _Drag.crop:
        setState(() => marquee = Rect.fromPoints(startWorld, w));
      case _Drag.pen || _Drag.eraser:
        if ((vp.toScreen(stroke.last) - s).distance > 1.5) setState(() => stroke.add(w));
      case _Drag.node:
        final (ci, ni) = dragNode!;
        ed.moveNodeTo(ci, ni, w);
        ed.updateGesture();
      case _Drag.handleIn || _Drag.handleOut:
        final (ci, ni) = dragNode!;
        ed.moveHandleTo(ci, ni, drag == _Drag.handleOut, w, mirror: !HardwareKeyboard.instance.isAltPressed);
        ed.updateGesture();
    }
  }

  void _scaleDrag(Offset w) {
    final b = startBounds!;
    final h = handle!;
    final ax = switch (h) {
      _Handle.tl || _Handle.l || _Handle.bl => b.right,
      _Handle.tr || _Handle.r || _Handle.br => b.left,
      _ => b.center.dx,
    };
    final ay = switch (h) {
      _Handle.tl || _Handle.t || _Handle.tr => b.bottom,
      _Handle.bl || _Handle.b || _Handle.br => b.top,
      _ => b.center.dy,
    };
    final anchor = Offset(ax, ay);
    final corner = const {_Handle.tl, _Handle.tr, _Handle.bl, _Handle.br}.contains(h);
    final horizontalOnly = h == _Handle.l || h == _Handle.r;
    final verticalOnly = h == _Handle.t || h == _Handle.b;
    double ratio(double now, double start, double a) {
      final d = start - a;
      if (d.abs() < 1e-6) return 1;
      final r = (now - a) / d;
      return r.abs() < 0.01 ? 0.01 * (r.isNegative ? -1 : 1) : r;
    }

    var fx = verticalOnly ? 1.0 : ratio(w.dx, startWorld.dx, ax);
    var fy = horizontalOnly ? 1.0 : ratio(w.dy, startWorld.dy, ay);
    final lock = widget.lockRatio.value != _shift;
    if (corner && lock) {
      final f = math.max(fx.abs(), fy.abs());
      fx = f;
      fy = f;
    } else {
      // Don't flip through zero while dragging an edge.
      fx = fx.abs();
      fy = fy.abs();
    }
    _restoreStart();
    ed.scaleSelection(fx, fy, anchor, record: false);
    ed.updateGesture();
  }

  Offset _snap(Offset d) {
    final b = startBounds!.shift(d);
    final others = ed.project.objects
        .where((o) => o.visible && !ed.selection.contains(o.id))
        .map((o) => o.worldBounds());
    final mat = Rect.fromLTWH(0, 0, ed.project.mat.matSize.width, ed.project.mat.matSize.height);
    final xs = <double>[mat.left, mat.center.dx, mat.right], ys = <double>[mat.top, mat.center.dy, mat.bottom];
    for (final r in others) {
      xs.addAll([r.left, r.center.dx, r.right]);
      ys.addAll([r.top, r.center.dy, r.bottom]);
    }
    final threshold = 6 / vp.zoom;
    double? best(List<double> mine, List<double> targets, void Function(double) guide) {
      double? shift;
      double? at;
      for (final m in mine) {
        for (final t in targets) {
          final diff = t - m;
          if (diff.abs() <= threshold && (shift == null || diff.abs() < shift.abs())) {
            shift = diff;
            at = t;
          }
        }
      }
      if (at != null) guide(at);
      return shift;
    }

    guides = [];
    final dx = best([b.left, b.center.dx, b.right], xs, (x) => guides.add((Offset(x, -1e4), Offset(x, 1e4))));
    final dy = best([b.top, b.center.dy, b.bottom], ys, (y) => guides.add((Offset(-1e4, y), Offset(1e4, y))));
    return d + Offset(dx ?? 0, dy ?? 0);
  }

  void _onUp(PointerUpEvent e) {
    pointers.remove(e.pointer);
    if (drag == _Drag.pinch) {
      // Wait for every finger to lift before starting anything new.
      if (pointers.isEmpty) drag = _Drag.none;
      return;
    }
    final was = drag;
    drag = _Drag.none;
    handle = null;
    guides = [];
    switch (was) {
      case _Drag.move || _Drag.scale || _Drag.rotate || _Drag.node || _Drag.handleIn || _Drag.handleOut:
        ed.endGesture();
      case _Drag.marquee:
        final m = marquee;
        marquee = null;
        if (m != null && m.width * vp.zoom > 3) {
          ed.select([
            for (final o in ed.project.objects)
              if (o.visible && !o.locked && o.worldBounds().overlaps(m)) o.id,
          ], additive: _shift);
        } else {
          setState(() {});
        }
      case _Drag.crop:
        final m = marquee;
        marquee = null;
        if (m != null && m.width > 0.5 && m.height > 0.5) ed.cropTo(m);
        setState(() {});
      case _Drag.pen:
        final s = stroke;
        stroke = [];
        ed.addPenStroke(s, 8 / vp.zoom);
      case _Drag.eraser:
        final s = stroke;
        stroke = [];
        ed.erase(s);
      default:
        setState(() {});
    }
  }

  void _onSignal(PointerSignalEvent e) {
    if (e is PointerScrollEvent) {
      final k = HardwareKeyboard.instance;
      if (k.isControlPressed || k.isMetaPressed) {
        vp.zoomAt(e.localPosition, math.pow(1.0015, -e.scrollDelta.dy).toDouble());
      } else {
        vp.panBy(k.isShiftPressed ? Offset(-e.scrollDelta.dy, 0) : -e.scrollDelta);
      }
    } else if (e is PointerScaleEvent) {
      vp.zoomAt(e.localPosition, e.scale);
    }
  }

  double _lastScale = 1;

  MouseCursor get _cursor {
    if (drag == _Drag.pan || _space) return SystemMouseCursors.grabbing;
    return switch (ed.tool) {
      Tool.pen || Tool.crop => SystemMouseCursors.precise,
      Tool.eraser => SystemMouseCursors.none,
      _ => SystemMouseCursors.basic,
    };
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, c) {
        vp.size = c.biggest;
        return Focus(
          focusNode: focus,
          child: MouseRegion(
            cursor: _cursor,
            onHover: (e) {
              cursorWorld = vp.toWorld(e.localPosition);
              widget.onCursor?.call(cursorWorld!);
              if (ed.tool == Tool.eraser) setState(() {});
            },
            onExit: (_) => setState(() => cursorWorld = null),
            child: Listener(
              onPointerDown: _onDown,
              onPointerMove: _onMove,
              onPointerUp: _onUp,
              onPointerCancel: (e) {
                pointers.remove(e.pointer);
                if (drag == _Drag.move || drag == _Drag.scale || drag == _Drag.rotate) {
                  _restoreStart();
                  ed.endGesture();
                }
                setState(() => drag = _Drag.none);
              },
              onPointerSignal: _onSignal,
              onPointerPanZoomStart: (_) => _lastScale = 1,
              onPointerPanZoomUpdate: (e) {
                if ((e.scale - _lastScale).abs() > 1e-3) {
                  vp.zoomAt(e.localPosition, e.scale / _lastScale);
                  _lastScale = e.scale;
                } else {
                  vp.panBy(e.panDelta);
                }
              },
              child: ClipRect(
                child: CustomPaint(
                  size: c.biggest,
                  painter: _CanvasPainter(
                    ed: ed,
                    vp: vp,
                    images: widget.images,
                    scheme: scheme,
                    marquee: marquee,
                    cropping: drag == _Drag.crop,
                    stroke: stroke,
                    strokeMode: drag,
                    cursor: cursorWorld,
                    guides: guides,
                    labelStyle: Theme.of(context).textTheme.labelSmall ?? const TextStyle(),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CanvasPainter extends CustomPainter {
  _CanvasPainter({
    required this.ed,
    required this.vp,
    required this.images,
    required this.scheme,
    required this.marquee,
    required this.cropping,
    required this.stroke,
    required this.strokeMode,
    required this.cursor,
    required this.guides,
    required this.labelStyle,
  });

  final TextStyle labelStyle;
  final EditorController ed;
  final CanvasViewport vp;
  final AssetImages images;
  final ColorScheme scheme;
  final Rect? marquee;
  final bool cropping;
  final List<Offset> stroke;
  final _Drag strokeMode;
  final Offset? cursor;
  final List<(Offset, Offset)> guides;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = scheme.surfaceContainerLow);
    canvas.save();
    canvas.translate(vp.pan.dx, vp.pan.dy);
    canvas.scale(vp.zoom);
    _paintMat(canvas, size);
    for (final o in ed.project.objects) {
      if (o.visible) paintObject(canvas, o, images, vp.zoom);
    }
    canvas.restore();
    _paintOverlay(canvas, size);
  }

  void _paintMat(Canvas canvas, Size size) {
    final m = ed.project.mat.matSize;
    final mat = Rect.fromLTWH(0, 0, m.width, m.height);
    canvas.drawRect(
      mat.shift(Offset(0.8 / vp.zoom * 2, 1.2 / vp.zoom * 2)),
      Paint()..color = Colors.black.withValues(alpha: 0.08),
    );
    canvas.drawRect(mat, Paint()..color = scheme.surface);
    if (!ed.showGrid) return;
    final inch = ed.project.units == Units.inch;
    final major = inch ? 25.4 : 10.0;
    final minorDiv = inch ? 4 : 2;
    final minor = major / minorDiv;
    final showMinor = minor * vp.zoom > 6;
    final hair = 1 / vp.zoom;
    final minorPaint = Paint()
      ..color = scheme.outlineVariant.withValues(alpha: 0.35)
      ..strokeWidth = hair;
    final majorPaint = Paint()
      ..color = scheme.outlineVariant.withValues(alpha: 0.9)
      ..strokeWidth = hair;
    final step = showMinor ? minor : major;
    var i = 0;
    for (var x = 0.0; x <= m.width + 1e-6; x += step, i++) {
      final isMajor = !showMinor || i % minorDiv == 0;
      canvas.drawLine(Offset(x, 0), Offset(x, m.height), isMajor ? majorPaint : minorPaint);
    }
    i = 0;
    for (var y = 0.0; y <= m.height + 1e-6; y += step, i++) {
      final isMajor = !showMinor || i % minorDiv == 0;
      canvas.drawLine(Offset(0, y), Offset(m.width, y), isMajor ? majorPaint : minorPaint);
    }
    canvas.drawRect(
      mat,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = hair
        ..color = scheme.outline,
    );
  }

  void _paintOverlay(Canvas canvas, Size size) {
    final accent = scheme.primary;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = accent;

    for (final (a, b) in guides) {
      canvas.drawLine(
        vp.toScreen(a),
        vp.toScreen(b),
        Paint()
          ..color = const Color(0xFFD6409F)
          ..strokeWidth = 1,
      );
    }

    // Outline each selected object, then the selection box and handles.
    for (final o in ed.selected) {
      final p = contoursToPath(o.localContours, map: (q) => vp.toScreen(o.xform.apply(q)));
      canvas.drawPath(
        p,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = accent.withValues(alpha: 0.6),
      );
    }

    final b = ed.selectionBounds();
    if (b != null && ed.tool == Tool.select) {
      final r = Rect.fromPoints(vp.toScreen(b.topLeft), vp.toScreen(b.bottomRight));
      final locked = ed.selected.every((o) => o.locked);
      drawDashed(canvas, Path()..addRect(r), line, 5, 3);
      if (!locked) {
        final hs = {
          r.topLeft,
          r.topCenter,
          r.topRight,
          r.centerRight,
          r.bottomRight,
          r.bottomCenter,
          r.bottomLeft,
          r.centerLeft,
        };
        for (final h in hs) {
          canvas.drawRect(Rect.fromCenter(center: h, width: 9, height: 9), Paint()..color = scheme.surface);
          canvas.drawRect(Rect.fromCenter(center: h, width: 9, height: 9), line);
        }
        final rot = r.topCenter - const Offset(0, 28);
        canvas.drawLine(r.topCenter, rot, line);
        canvas.drawCircle(rot, 6, Paint()..color = scheme.surface);
        canvas.drawCircle(rot, 6, line);
      }
      _sizeLabel(canvas, r, b);
    }

    if (ed.tool == Tool.node) _paintNodes(canvas);

    if (marquee != null) {
      final r = Rect.fromPoints(vp.toScreen(marquee!.topLeft), vp.toScreen(marquee!.bottomRight));
      if (cropping) {
        final dim = Path()
          ..fillType = PathFillType.evenOdd
          ..addRect(Offset.zero & size)
          ..addRect(r);
        canvas.drawPath(dim, Paint()..color = Colors.black.withValues(alpha: 0.25));
        canvas.drawRect(r, line..strokeWidth = 1.5);
      } else {
        canvas.drawRect(r, Paint()..color = accent.withValues(alpha: 0.08));
        canvas.drawRect(r, line);
      }
    }

    if (stroke.length > 1) {
      final p = Path()..moveTo(vp.toScreen(stroke.first).dx, vp.toScreen(stroke.first).dy);
      for (final q in stroke.skip(1)) {
        final s = vp.toScreen(q);
        p.lineTo(s.dx, s.dy);
      }
      final eraser = strokeMode == _Drag.eraser;
      canvas.drawPath(
        p,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = eraser ? ed.eraserWidth * vp.zoom : 2
          ..color = eraser ? Colors.red.withValues(alpha: 0.25) : accent,
      );
    }
    if (ed.tool == Tool.eraser && cursor != null) {
      canvas.drawCircle(
        vp.toScreen(cursor!),
        ed.eraserWidth * vp.zoom / 2,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = scheme.onSurface,
      );
    }
  }

  void _sizeLabel(Canvas canvas, Rect screen, Rect world) {
    final u = ed.project.units;
    final text =
        '${u.fromMm(world.width).toStringAsFixed(2)} × ${u.fromMm(world.height).toStringAsFixed(2)} ${u.suffix}';
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: labelStyle.copyWith(fontSize: 11, color: scheme.onPrimary),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final at = screen.bottomCenter + Offset(-tp.width / 2 - 6, 10);
    canvas.drawRRect(
      RRect.fromRectAndRadius(at & Size(tp.width + 12, tp.height + 6), const Radius.circular(4)),
      Paint()..color = scheme.primary,
    );
    tp.paint(canvas, at + const Offset(6, 3));
  }

  void _paintNodes(Canvas canvas) {
    final o = ed.nodeTarget;
    if (o == null) return;
    final accent = scheme.primary;
    Offset s(Offset local) => vp.toScreen(o.xform.apply(local));
    final p = contoursToPath(o.contours, map: s);
    canvas.drawPath(
      p,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = accent,
    );
    for (var ci = 0; ci < o.contours.length; ci++) {
      final c = o.contours[ci];
      for (var ni = 0; ni < c.nodes.length; ni++) {
        final n = c.nodes[ni];
        final active = ed.activeNode == (ci, ni);
        if (active) {
          for (final h in [n.cIn, n.cOut]) {
            if (h == null) continue;
            canvas.drawLine(
              s(n.p),
              s(h),
              Paint()
                ..color = accent
                ..strokeWidth = 1,
            );
            canvas.drawCircle(s(h), 4.5, Paint()..color = accent);
          }
        }
        final r = Rect.fromCenter(center: s(n.p), width: 8, height: 8);
        final fill = Paint()..color = active ? accent : scheme.surface;
        if (n.isCorner) {
          canvas.drawRect(r, fill);
          canvas.drawRect(
            r,
            Paint()
              ..style = PaintingStyle.stroke
              ..color = accent,
          );
        } else {
          canvas.drawOval(r, fill);
          canvas.drawOval(
            r,
            Paint()
              ..style = PaintingStyle.stroke
              ..color = accent,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
