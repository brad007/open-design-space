import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../geometry/boolean_ops.dart' as bool_ops;
import '../geometry/node_ops.dart';
import '../geometry/shapes.dart';
import '../geometry/svg_import.dart';
import '../geometry/trace.dart';
import '../model/geometry.dart';
import '../model/objects.dart';
import '../model/project.dart';
import '../storage/project_store.dart';
import '../text/font_registry.dart';
import '../text/text_layout.dart';

enum Tool { select, node, pen, eraser, crop }

enum AlignMode { left, centerH, right, top, centerV, bottom }

/// Everything the editor can do to a project. Every change goes through
/// [mutate] (or a gesture pair) so it can be undone and is autosaved.
class EditorController extends ChangeNotifier {
  EditorController({required this.project, required this.store, required this.fonts, this.onDisk = true})
      : text = TextEngine(fonts) {
    refreshAllText();
    fonts.addListener(_onFontsChanged);
  }

  final Project project;
  final ProjectStore store;
  final FontRegistry fonts;
  final TextEngine text;

  Tool tool = Tool.select;
  final Set<String> selection = {};
  bool snapping = false;
  bool showGrid = true;
  double eraserWidth = 4;
  String? status;

  /// Node editing target: contour and node index on the single selected path.
  (int, int)? activeNode;

  final _undo = <String>[];
  final _redo = <String>[];
  static const _historyLimit = 300;
  String? _gestureBefore;

  Timer? _autosave;
  DateTime _lastSnapshot = DateTime.now();
  bool dirty = false;
  bool saving = false;

  /// False for a fresh canvas that hasn't been saved yet. Empty canvases are
  /// never written, so opening the app doesn't litter the library.
  bool onDisk;
  DateTime? lastSaved;

  /// Renders a library thumbnail; set by the UI.
  Future<Uint8List?> Function()? thumbnailBuilder;

  List<Map<String, dynamic>> _clipboard = [];

  @override
  void dispose() {
    fonts.removeListener(_onFontsChanged);
    _autosave?.cancel();
    super.dispose();
  }

  void _onFontsChanged() {
    if (refreshAllText()) notifyListeners();
  }

  bool refreshAllText() {
    var changed = false;
    for (final o in project.objects) {
      if (o is TextObject) changed |= text.refresh(o);
    }
    return changed;
  }

  // ---------------------------------------------------------------- history

  String _encodeObjects() => jsonEncode([for (final o in project.objects) o.toJson()]);

  void _restoreObjects(String s) {
    project.objects = [for (final o in jsonDecode(s) as List) DesignObject.fromJson(o)];
    selection.removeWhere((id) => project.byId(id) == null);
    activeNode = null;
    refreshAllText();
  }

  void _pushUndo(String before) {
    _undo.add(before);
    if (_undo.length > _historyLimit) _undo.removeAt(0);
    _redo.clear();
  }

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  void undo() {
    if (_undo.isEmpty) return;
    _redo.add(_encodeObjects());
    _restoreObjects(_undo.removeLast());
    _changed();
  }

  void redo() {
    if (_redo.isEmpty) return;
    _undo.add(_encodeObjects());
    _restoreObjects(_redo.removeLast());
    _changed();
  }

  void mutate(void Function() fn, {String? message}) {
    final before = _encodeObjects();
    fn();
    refreshAllText();
    _pushUndo(before);
    status = message;
    _changed();
  }

  /// Starts a continuous edit such as a drag; [endGesture] records one undo step.
  void beginGesture() => _gestureBefore ??= _encodeObjects();

  void updateGesture() {
    refreshAllText();
    notifyListeners();
  }

  void endGesture() {
    final before = _gestureBefore;
    _gestureBefore = null;
    if (before == null) return;
    if (before != _encodeObjects()) {
      _pushUndo(before);
      _changed();
    }
  }

  void _changed() {
    dirty = true;
    notifyListeners();
    _autosave?.cancel();
    _autosave = Timer(const Duration(milliseconds: 1200), save);
  }

  /// Settings that aren't part of the object history (mat layout, units).
  void settingsChanged() => _changed();

  Future<void> save() async {
    if (saving) return;
    if (!onDisk && project.objects.isEmpty) return;
    saving = true;
    try {
      final thumb = await thumbnailBuilder?.call();
      await store.save(project, thumbnail: thumb);
      onDisk = true;
      if (DateTime.now().difference(_lastSnapshot) > const Duration(minutes: 5)) {
        await store.snapshot(project);
        _lastSnapshot = DateTime.now();
      }
      dirty = false;
      lastSaved = DateTime.now();
    } finally {
      saving = false;
      notifyListeners();
    }
  }

  Future<void> saveRestorePoint() async {
    await save();
    await store.snapshot(project);
    _lastSnapshot = DateTime.now();
    status = 'Restore point saved';
    notifyListeners();
  }

  void replaceWithSnapshot(Project snap) {
    mutate(() {
      project.objects = snap.objects;
      project.assets.addAll(snap.assets);
      project.mat = snap.mat;
    }, message: 'Restored an earlier version (undo to go back)');
  }

  // -------------------------------------------------------------- selection

  List<DesignObject> get selected => [for (final o in project.objects) if (selection.contains(o.id)) o];

  DesignObject? get single => selection.length == 1 ? project.byId(selection.first) : null;

  /// Selecting a grouped object selects the whole group.
  Set<String> _expand(Iterable<String> ids) {
    final out = <String>{...ids};
    final groups = {for (final id in ids) project.byId(id)?.groupId}..remove(null);
    if (groups.isNotEmpty) {
      for (final o in project.objects) {
        if (groups.contains(o.groupId)) out.add(o.id);
      }
    }
    return out;
  }

  void select(Iterable<String> ids, {bool additive = false, bool expandGroups = true}) {
    final ex = expandGroups ? _expand(ids) : ids.toSet();
    if (!additive) selection.clear();
    if (additive && ex.every(selection.contains)) {
      selection.removeAll(ex);
    } else {
      selection.addAll(ex);
    }
    activeNode = null;
    notifyListeners();
  }

  void clearSelection() {
    if (selection.isEmpty) return;
    selection.clear();
    activeNode = null;
    notifyListeners();
  }

  void selectAll() => select([for (final o in project.objects) if (o.visible && !o.locked) o.id]);

  void setTool(Tool t) {
    tool = t;
    activeNode = null;
    if (t == Tool.node && single is TextObject) {
      status = 'Convert text to outlines to edit its nodes.';
    } else {
      status = null;
    }
    notifyListeners();
  }

  /// Topmost visible object under [world], within [tolerance] mm.
  DesignObject? hitTest(Offset world, double tolerance) {
    for (final o in project.objects.reversed) {
      if (!o.visible || o.locked) continue;
      if (!o.worldBounds().inflate(tolerance).contains(world)) continue;
      if (o is ImageObject) return o;
      final polys = o.worldPolylines(0.2);
      final closed = o.localContours.every((c) => c.closed);
      if (closed && _insideEvenOdd(polys, world)) return o;
      for (final p in polys) {
        for (var i = 0; i < p.length - (closed ? 0 : 1); i++) {
          if (distanceToSegment(world, p[i], p[(i + 1) % p.length]) <= tolerance) return o;
        }
      }
    }
    return null;
  }

  static bool _insideEvenOdd(List<List<Offset>> polys, Offset q) {
    var inside = false;
    for (final p in polys) {
      for (var i = 0, j = p.length - 1; i < p.length; j = i++) {
        final a = p[i], b = p[j];
        if ((a.dy > q.dy) != (b.dy > q.dy) && q.dx < (b.dx - a.dx) * (q.dy - a.dy) / (b.dy - a.dy) + a.dx) {
          inside = !inside;
        }
      }
    }
    return inside;
  }

  Rect? selectionBounds([Iterable<DesignObject>? objs]) {
    final list = (objs ?? selected).toList();
    if (list.isEmpty) return null;
    return list.map((o) => o.worldBounds()).reduce((a, b) => a.expandToInclude(b));
  }

  Rect contentBounds() =>
      selectionBounds(project.objects.where((o) => o.visible)) ?? Rect.fromLTWH(0, 0, project.mat.matSize.width, project.mat.matSize.height);

  // ----------------------------------------------------------------- create

  int _counter = 0;
  String _name(String base) {
    final used = {for (final o in project.objects) o.name};
    var n = ++_counter;
    while (used.contains('$base $n')) {
      n++;
    }
    return '$base $n';
  }

  /// Where new objects appear: the visible center if known, else the mat center.
  Offset insertionPoint = const Offset(152.4, 152.4);

  int nextColor() {
    const palette = [0xFF2F6FED, 0xFFE5484D, 0xFF30A46C, 0xFFF5A524, 0xFF8E4EC6, 0xFF12A594, 0xFFD6409F, 0xFF1F2937];
    return palette[project.objects.length % palette.length];
  }

  void _add(DesignObject o, {String? message}) {
    mutate(() {
      project.objects.add(o);
      selection
        ..clear()
        ..add(o.id);
    }, message: message);
  }

  void addShape(ShapeKind kind) {
    final o = PathObject(
      id: newId(),
      name: _name(kind.label),
      contours: buildShape(kind, size: 50.8),
      color: kind == ShapeKind.line ? 0xFF6B7280 : nextColor(),
      operation: kind == ShapeKind.line ? Operation.score : Operation.cut,
      xform: Xform(tx: insertionPoint.dx, ty: insertionPoint.dy),
    );
    _add(o);
  }

  void addText([String content = 'Text']) {
    final family = fonts.defaultFamily;
    if (family == null) {
      status = 'No fonts found. Use Import font to add a .ttf file.';
      notifyListeners();
      return;
    }
    final t = TextObject(
      id: newId(),
      name: _name('Text'),
      text: content,
      fontFamily: family,
      fontStyle: fonts.stylesOf(family).first,
      size: 25.4,
      color: nextColor(),
      xform: Xform(tx: insertionPoint.dx, ty: insertionPoint.dy),
    );
    text.refresh(t);
    _add(t);
  }

  Future<void> addImage(Uint8List bytes, String mime, String fileName) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final img = frame.image;
    // Fit within 100 mm on the longest side.
    final aspect = img.width / img.height;
    final w = aspect >= 1 ? 101.6 : 101.6 * aspect;
    final h = aspect >= 1 ? 101.6 / aspect : 101.6;
    img.dispose();
    final assetId = newId();
    project.assets[assetId] = Asset(mime, bytes);
    _add(ImageObject(
      id: newId(),
      name: fileName,
      assetId: assetId,
      width: w,
      height: h,
      xform: Xform(tx: insertionPoint.dx, ty: insertionPoint.dy),
    ));
  }

  void addSvg(String source, String fileName) {
    final shapes = importSvg(source);
    if (shapes.isEmpty) {
      status = 'No shapes found in $fileName';
      notifyListeners();
      return;
    }
    final all = boundsOfPoints(shapes.expand((s) => s.contours.expand((c) => c.flatten(0.5))));
    final shift = insertionPoint - all.center;
    final group = shapes.length > 1 ? newId() : null;
    mutate(() {
      selection.clear();
      for (final s in shapes) {
        final o = _pathFromWorld([for (final c in s.contours) c.transformed((p) => p + shift)], s.name, s.color)
          ..groupId = group;
        project.objects.add(o);
        selection.add(o.id);
      }
    }, message: 'Imported ${shapes.length} shape${shapes.length == 1 ? '' : 's'} from $fileName');
  }

  PathObject _pathFromWorld(List<Contour> world, String name, int color, {Operation op = Operation.cut}) {
    final c = boundsOfContours(world).center;
    return PathObject(
      id: newId(),
      name: name,
      contours: [for (final k in world) k.transformed((p) => p - c)],
      color: color,
      operation: op,
      xform: Xform(tx: c.dx, ty: c.dy),
    );
  }

  PathObject _pathFromPolys(bool_ops.Polys polys, String name, int color, {Operation op = Operation.cut}) =>
      _pathFromWorld(bool_ops.polysToContours(polys), name, color, op: op);

  // ------------------------------------------------------------- arrangement

  void deleteSelected() {
    if (selection.isEmpty) return;
    mutate(() {
      project.objects.removeWhere((o) => selection.contains(o.id));
      selection.clear();
    });
  }

  List<DesignObject> _cloneAll(Iterable<DesignObject> objs, Offset shift) {
    final groupMap = <String, String>{};
    return [
      for (final o in objs)
        o.clone(id: newId())
          ..xform = o.xform.translated(shift)
          ..groupId = o.groupId == null ? null : (groupMap[o.groupId!] ??= newId()),
    ];
  }

  void duplicate() {
    final src = selected;
    if (src.isEmpty) return;
    mutate(() {
      final copies = _cloneAll(src, const Offset(6, 6));
      project.objects.addAll(copies);
      selection
        ..clear()
        ..addAll(copies.map((c) => c.id));
    });
  }

  void copy() {
    _clipboard = [for (final o in selected) o.toJson()];
    status = 'Copied ${_clipboard.length}';
    notifyListeners();
  }

  void cut() {
    copy();
    deleteSelected();
  }

  void paste() {
    if (_clipboard.isEmpty) return;
    final objs = [for (final j in _clipboard) DesignObject.fromJson(j)];
    mutate(() {
      final copies = _cloneAll(objs, const Offset(10, 10));
      project.objects.addAll(copies);
      selection
        ..clear()
        ..addAll(copies.map((c) => c.id));
      _clipboard = [for (final c in copies) c.toJson()];
    });
  }

  void group() {
    if (selection.length < 2) return;
    final g = newId();
    mutate(() {
      for (final o in selected) {
        o.groupId = g;
      }
    }, message: 'Grouped: these stay together on the mat');
  }

  void ungroup() {
    mutate(() {
      for (final o in selected) {
        o.groupId = null;
      }
    });
  }

  void reorder(int delta) {
    if (selection.isEmpty) return;
    mutate(() {
      final objs = project.objects;
      if (delta > 0) {
        for (var i = objs.length - 2; i >= 0; i--) {
          if (selection.contains(objs[i].id) && !selection.contains(objs[i + 1].id)) {
            objs.insert(i + 1, objs.removeAt(i));
          }
        }
      } else {
        for (var i = 1; i < objs.length; i++) {
          if (selection.contains(objs[i].id) && !selection.contains(objs[i - 1].id)) {
            objs.insert(i - 1, objs.removeAt(i));
          }
        }
      }
    });
  }

  void toFront() => mutate(() {
        final sel = selected;
        project.objects
          ..removeWhere((o) => selection.contains(o.id))
          ..addAll(sel);
      });

  void toBack() => mutate(() {
        final sel = selected;
        project.objects
          ..removeWhere((o) => selection.contains(o.id))
          ..insertAll(0, sel);
      });

  /// Moves one layer to [newIndex] in the bottom-to-top list.
  void moveLayer(int oldIndex, int newIndex) => mutate(() {
        final o = project.objects.removeAt(oldIndex);
        project.objects.insert(newIndex.clamp(0, project.objects.length), o);
      });

  void translateSelected(Offset d) {
    for (final o in selected) {
      if (!o.locked) o.xform = o.xform.translated(d);
    }
  }

  void nudge(Offset d) => mutate(() => translateSelected(d));

  void align(AlignMode mode) {
    final objs = selected;
    if (objs.isEmpty) return;
    // A single object aligns to the mat.
    final ref = objs.length == 1
        ? Rect.fromLTWH(0, 0, project.mat.matSize.width, project.mat.matSize.height)
        : selectionBounds(objs)!;
    final groups = <String, List<DesignObject>>{};
    for (final o in objs) {
      (groups[o.groupId ?? o.id] ??= []).add(o);
    }
    mutate(() {
      for (final members in groups.values) {
        final b = selectionBounds(members)!;
        final d = switch (mode) {
          AlignMode.left => Offset(ref.left - b.left, 0),
          AlignMode.centerH => Offset(ref.center.dx - b.center.dx, 0),
          AlignMode.right => Offset(ref.right - b.right, 0),
          AlignMode.top => Offset(0, ref.top - b.top),
          AlignMode.centerV => Offset(0, ref.center.dy - b.center.dy),
          AlignMode.bottom => Offset(0, ref.bottom - b.bottom),
        };
        for (final o in members) {
          o.xform = o.xform.translated(d);
        }
      }
    });
  }

  void distribute({required bool horizontal}) {
    final objs = selected;
    if (objs.length < 3) return;
    objs.sort((a, b) => horizontal
        ? a.worldBounds().center.dx.compareTo(b.worldBounds().center.dx)
        : a.worldBounds().center.dy.compareTo(b.worldBounds().center.dy));
    final first = objs.first.worldBounds().center, last = objs.last.worldBounds().center;
    mutate(() {
      for (var i = 1; i < objs.length - 1; i++) {
        final target = Offset.lerp(first, last, i / (objs.length - 1))!;
        final c = objs[i].worldBounds().center;
        objs[i].xform = objs[i].xform.translated(horizontal ? Offset(target.dx - c.dx, 0) : Offset(0, target.dy - c.dy));
      }
    });
  }

  void flip({required bool horizontal}) {
    final b = selectionBounds();
    if (b == null) return;
    mutate(() {
      for (final o in selected) {
        final x = o.xform;
        o.xform = horizontal
            ? Xform(tx: 2 * b.center.dx - x.tx, ty: x.ty, rotation: -x.rotation, sx: -x.sx, sy: x.sy)
            : Xform(tx: x.tx, ty: 2 * b.center.dy - x.ty, rotation: -x.rotation, sx: x.sx, sy: -x.sy);
      }
    });
  }

  /// Sets the selection's overall size in mm, keeping its center.
  void resizeSelectionTo({double? width, double? height, bool keepRatio = true}) {
    final b = selectionBounds();
    if (b == null || b.width == 0 || b.height == 0) return;
    var fx = width == null ? null : width / b.width;
    var fy = height == null ? null : height / b.height;
    if (keepRatio) {
      fx ??= fy;
      fy ??= fx;
    }
    fx ??= 1;
    fy ??= 1;
    scaleSelection(fx, fy, b.center);
  }

  /// Scales selected objects around [anchor] in world axes.
  void scaleSelection(double fx, double fy, Offset anchor, {bool record = true}) {
    void apply() {
      for (final o in selected) {
        if (o.locked) continue;
        final x = o.xform;
        final c = (x.translation - anchor);
        // Axis-aligned world scaling of a rotated object only stays affine
        // when uniform, or when the object isn't rotated.
        final quarter = x.rotation / (math.pi / 2);
        final rotated = (quarter - quarter.round()).abs() > 1e-6;
        final ux = rotated ? math.sqrt(fx.abs() * fy.abs()) * fx.sign : fx;
        final uy = rotated ? math.sqrt(fx.abs() * fy.abs()) * fy.sign : fy;
        final swap = !rotated && quarter.round().abs() % 2 == 1;
        o.xform = x.copyWith(
          tx: anchor.dx + c.dx * fx,
          ty: anchor.dy + c.dy * fy,
          sx: x.sx * (swap ? uy : ux),
          sy: x.sy * (swap ? ux : uy),
        );
      }
    }

    if (record) {
      mutate(apply);
    } else {
      apply();
    }
  }

  void rotateSelection(double radians, Offset pivot, {bool record = true}) {
    void apply() {
      final c = math.cos(radians), s = math.sin(radians);
      for (final o in selected) {
        if (o.locked) continue;
        final d = o.xform.translation - pivot;
        o.xform = o.xform.copyWith(
          tx: pivot.dx + d.dx * c - d.dy * s,
          ty: pivot.dy + d.dx * s + d.dy * c,
          rotation: o.xform.rotation + radians,
        );
      }
    }

    if (record) {
      mutate(apply);
    } else {
      apply();
    }
  }

  void setProperty(void Function(DesignObject o) f) => mutate(() {
        for (final o in selected) {
          f(o);
        }
      });

  void editText(TextObject t, void Function(TextObject t) f) => mutate(() => f(t));

  void toggleVisible(DesignObject o) => mutate(() => o.visible = !o.visible);

  void toggleLocked(DesignObject o) => mutate(() {
        o.locked = !o.locked;
        if (o.locked) selection.remove(o.id);
      });

  void rename(DesignObject o, String name) => mutate(() => o.name = name);

  // --------------------------------------------------------------- path ops

  List<DesignObject> get _shapeable => [for (final o in selected) if (o is! ImageObject || o.cutOutline != null) o];

  void weld() {
    final objs = _shapeable;
    if (objs.length < 2) return _say('Select two or more shapes to weld.');
    final result = bool_ops.union([for (final o in objs) o.worldPolylines()]);
    _replace(objs, [_pathFromPolys(result, _name('Weld'), objs.last.color, op: objs.last.operation)], 'Welded ${objs.length} shapes (undo to separate)');
  }

  void intersectSelected() {
    final objs = _shapeable;
    if (objs.length < 2) return _say('Select two or more shapes to intersect.');
    var acc = objs.first.worldPolylines();
    for (final o in objs.skip(1)) {
      acc = bool_ops.intersect(acc, o.worldPolylines());
    }
    _replace(objs, [_pathFromPolys(acc, _name('Intersect'), objs.first.color, op: objs.first.operation)], 'Kept the overlap');
  }

  /// The top shapes cut their outline out of the bottom one.
  void subtract() {
    final objs = _shapeable;
    if (objs.length < 2) return _say('Select a shape and the shapes to cut out of it.');
    final base = objs.first;
    final cutters = bool_ops.union([for (final o in objs.skip(1)) o.worldPolylines()]);
    final result = bool_ops.difference(base.worldPolylines(), cutters);
    _replace(objs, [_pathFromPolys(result, base.name, base.color, op: base.operation)], 'Subtracted');
  }

  /// Splits two overlapping shapes into all their pieces.
  void slice() {
    final objs = _shapeable;
    if (objs.length != 2) return _say('Select exactly two shapes to slice.');
    final a = objs[0].worldPolylines(), b = objs[1].worldPolylines();
    final pieces = [
      (bool_ops.difference(a, b), objs[0].color, '${objs[0].name} piece'),
      (bool_ops.difference(b, a), objs[1].color, '${objs[1].name} piece'),
      (bool_ops.intersect(a, b), objs[1].color, 'Slice overlap'),
    ];
    final out = [
      for (final (polys, color, name) in pieces)
        if (polys.isNotEmpty) _pathFromPolys(polys, name, color),
    ];
    _replace(objs, out, 'Sliced into ${out.length} pieces');
  }

  /// Adds an outline [distance] mm outside (or inside, if negative) the selection.
  void offsetSelected(double distance, {bool rounded = true, bool weldResult = true}) {
    final objs = _shapeable.isEmpty ? selected : _shapeable;
    if (objs.isEmpty) return;
    final polys = [for (final o in objs) o.worldPolylines()];
    final src = weldResult ? [bool_ops.union(polys)] : polys;
    mutate(() {
      final firstIndex = project.objects.indexWhere((o) => selection.contains(o.id));
      final made = [
        for (final p in src) _pathFromPolys(bool_ops.offsetPolys(p, distance, rounded: rounded), _name('Offset'), 0xFF9CA3AF),
      ];
      project.objects.insertAll(math.max(0, firstIndex), made);
      selection
        ..clear()
        ..addAll(made.map((m) => m.id));
    }, message: 'Offset created behind the original');
  }

  void _replace(List<DesignObject> old, List<DesignObject> made, String message) {
    mutate(() {
      final ids = old.map((o) => o.id).toSet();
      final at = project.objects.indexWhere((o) => ids.contains(o.id));
      project.objects.removeWhere((o) => ids.contains(o.id));
      project.objects.insertAll(at.clamp(0, project.objects.length), made);
      selection
        ..clear()
        ..addAll(made.map((m) => m.id));
    }, message: message);
  }

  void _say(String s) {
    status = s;
    notifyListeners();
  }

  /// Text becomes an editable shape; the original text is kept, hidden.
  void textToOutlines() {
    final texts = selected.whereType<TextObject>().toList();
    if (texts.isEmpty) return _say('Select text to convert.');
    mutate(() {
      selection.clear();
      for (final t in texts) {
        final p = PathObject(
          id: newId(),
          name: '${t.name} (outlines)',
          contours: [for (final c in t.outline) c.copy()],
          color: t.color,
          operation: t.operation,
          xform: t.xform,
        )..groupId = t.groupId;
        final i = project.objects.indexOf(t);
        project.objects.insert(i + 1, p);
        t
          ..visible = false
          ..name = '${t.name} (original)';
        selection.add(p.id);
      }
    }, message: 'Converted to outlines. The original text is kept hidden in Layers.');
  }

  /// Applies the eraser brush along [stroke] (world mm).
  void erase(List<Offset> stroke) {
    final brush = bool_ops.strokeOutline(stroke, eraserWidth);
    final r = boundsOfPoints(brush.expand((e) => e));
    final targets = (selection.isEmpty ? project.objects : selected)
        .where((o) => o is PathObject && o.visible && !o.locked && o.worldBounds().overlaps(r))
        .toList();
    if (targets.isEmpty) {
      return _say(selected.any((o) => o is TextObject) ? 'Convert text to outlines before erasing.' : 'Nothing to erase here.');
    }
    mutate(() {
      for (final o in targets.cast<PathObject>()) {
        final result = bool_ops.difference(o.worldPolylines(), brush);
        final i = project.objects.indexOf(o);
        project.objects.removeAt(i);
        if (result.isEmpty) {
          selection.remove(o.id);
          continue;
        }
        final p = _pathFromPolys(result, o.name, o.color, op: o.operation)..groupId = o.groupId;
        project.objects.insert(i, p);
        if (selection.remove(o.id)) selection.add(p.id);
      }
    });
  }

  /// Crops selected objects to the world rectangle [r].
  void cropTo(Rect r) {
    final objs = selected;
    if (objs.isEmpty) return _say('Select what to crop first.');
    final clip = [
      [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft],
    ];
    mutate(() {
      for (final o in objs) {
        final i = project.objects.indexOf(o);
        if (o is ImageObject) {
          final corners = [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft].map(o.xform.invert);
          final local = boundsOfPoints(corners).intersect(o.visibleRect);
          if (local.width > 0 && local.height > 0) o.crop = local;
          continue;
        }
        final result = bool_ops.intersect(o.worldPolylines(), clip);
        project.objects.removeAt(i);
        selection.remove(o.id);
        if (result.isEmpty) continue;
        final p = _pathFromPolys(result, o.name, o.color, op: o.operation)..groupId = o.groupId;
        project.objects.insert(i, p);
        selection.add(p.id);
      }
    }, message: 'Cropped');
  }

  /// Traces an image. With [asCutLine], the outline (grown by [offset] mm)
  /// becomes the image's own cut line for Print then Cut stickers; otherwise
  /// it becomes a new cut shape.
  Future<void> traceSelectedImage({
    required TraceMode mode,
    required double threshold,
    double offset = 0,
    bool asCutLine = true,
    bool outerOnly = true,
  }) async {
    final img = single;
    if (img is! ImageObject) return _say('Select one image to trace.');
    final asset = project.assets[img.assetId];
    if (asset == null) return;
    final codec = await ui.instantiateImageCodec(Uint8List.fromList(asset.bytes), targetWidth: 900);
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final w = frame.image.width, h = frame.image.height;
    frame.image.dispose();
    if (data == null) return;
    final loops = traceImage(data.buffer.asUint8List(), w, h, mode: mode, threshold: threshold, simplify: 0.9);
    final sx = img.width / w, sy = img.height / h;
    var local = [
      for (final l in loops) [for (final p in l) Offset(p.dx * sx - img.width / 2, p.dy * sy - img.height / 2)],
    ];
    if (img.crop != null) {
      local = bool_ops.intersect(local, [
        [img.crop!.topLeft, img.crop!.topRight, img.crop!.bottomRight, img.crop!.bottomLeft],
      ]);
    }
    if (offset != 0) local = bool_ops.offsetPolys(local, offset / ((img.xform.sx.abs() + img.xform.sy.abs()) / 2));
    if (outerOnly) {
      // Drop holes: keep loops with the dominant orientation.
      final merged = bool_ops.union([local]);
      final sign = merged.fold(0.0, (a, p) => a + polygonArea(p)).sign;
      local = [for (final p in merged) if (polygonArea(p).sign == sign) p];
    }
    final contours = bool_ops.polysToContours(local, simplify: 0.05, minArea: 0.5);
    if (contours.isEmpty) return _say('Nothing to trace at this threshold.');
    mutate(() {
      if (asCutLine) {
        img
          ..cutOutline = contours
          ..operation = Operation.print;
      } else {
        final p = PathObject(id: newId(), name: '${img.name} trace', contours: contours, color: nextColor(), xform: img.xform);
        project.objects.insert(project.objects.indexOf(img) + 1, p);
        selection
          ..clear()
          ..add(p.id);
      }
    }, message: asCutLine ? 'Cut line set: the image will print and cut along its outline' : 'Traced into a new shape');
  }

  void clearCutOutline() {
    final img = single;
    if (img is ImageObject) mutate(() => img.cutOutline = null);
  }

  // ---------------------------------------------------------------- drawing

  /// Turns a freehand stroke into a smooth path. Strokes that end near their
  /// start close into a cuttable shape; others become a draw line.
  void addPenStroke(List<Offset> stroke, double closeDistance) {
    if (stroke.length < 2) return;
    final closed = stroke.length > 4 && (stroke.first - stroke.last).distance < closeDistance;
    final pts = simplifyPolyline(stroke, 0.35);
    if (closed && pts.length > 2 && (pts.first - pts.last).distance < closeDistance) pts.removeLast();
    final c = smoothContour(pts, closed: closed);
    final o = _pathFromWorld([c], _name(closed ? 'Drawing' : 'Line'), closed ? nextColor() : 0xFF111827,
        op: closed ? Operation.cut : Operation.draw);
    _add(o);
  }

  // ---------------------------------------------------------- node editing

  PathObject? get nodeTarget => single is PathObject ? single as PathObject : null;

  void moveNodeTo(int contour, int node, Offset world) {
    final o = nodeTarget;
    if (o == null) return;
    moveNode(o.contours[contour].nodes[node], o.xform.invert(world));
  }

  void moveHandleTo(int contour, int node, bool outHandle, Offset world, {bool mirror = true}) {
    final o = nodeTarget;
    if (o == null) return;
    final n = o.contours[contour].nodes[node];
    final local = o.xform.invert(world);
    if (outHandle) {
      n.cOut = local;
      if (mirror && n.cIn != null) n.cIn = n.p * 2 - local;
    } else {
      n.cIn = local;
      if (mirror && n.cOut != null) n.cOut = n.p * 2 - local;
    }
  }

  void insertNodeAt(Offset world) {
    final o = nodeTarget;
    if (o == null) return;
    final hit = nearestOnContours(o.contours, o.xform.invert(world));
    if (hit == null) return;
    mutate(() {
      insertNode(o.contours[hit.contour], hit.segment, hit.t);
      activeNode = (hit.contour, hit.segment + 1);
    });
  }

  void deleteActiveNode() {
    final o = nodeTarget, a = activeNode;
    if (o == null || a == null) return;
    mutate(() {
      if (!deleteNode(o.contours[a.$1], a.$2)) {
        status = 'A shape needs at least three points.';
      }
      activeNode = null;
    });
  }

  void toggleActiveNodeSmooth() {
    final o = nodeTarget, a = activeNode;
    if (o == null || a == null) return;
    mutate(() => toggleSmooth(o.contours[a.$1], a.$2));
  }

  /// Splits an open/closed contour at the active node (closed contours open up).
  void breakAtActiveNode() {
    final o = nodeTarget, a = activeNode;
    if (o == null || a == null) return;
    mutate(() {
      final c = o.contours[a.$1];
      if (c.closed) {
        final rotated = [...c.nodes.sublist(a.$2), ...c.nodes.sublist(0, a.$2), c.nodes[a.$2].copy()];
        rotated.first.cIn = null;
        rotated.last.cOut = null;
        o.contours[a.$1] = Contour(rotated, closed: false);
      }
      activeNode = null;
    }, message: 'Path opened at this point');
  }
}

/// Catmull–Rom smoothing into cubic nodes.
Contour smoothContour(List<Offset> pts, {required bool closed}) {
  final n = pts.length;
  Offset at(int i) => closed ? pts[(i + n) % n] : pts[i.clamp(0, n - 1)];
  final nodes = <PathNode>[];
  for (var i = 0; i < n; i++) {
    final tangent = (at(i + 1) - at(i - 1)) / 6;
    final isEnd = !closed && (i == 0 || i == n - 1);
    nodes.add(PathNode(
      pts[i],
      cIn: isEnd && i == 0 ? null : pts[i] - tangent,
      cOut: isEnd && i == n - 1 ? null : pts[i] + tangent,
    ));
  }
  return Contour(nodes, closed: closed);
}
