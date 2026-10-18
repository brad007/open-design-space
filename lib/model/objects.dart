import 'dart:ui';

import 'geometry.dart';

/// What the machine does with an object's outline.
enum Operation {
  cut('Cut'),
  kissCut('Kiss cut'),
  score('Score'),
  draw('Draw'),
  print('Print then cut'),
  guide('Guide (ignored)');

  const Operation(this.label);
  final String label;

  /// Whether this object reaches the machine at all.
  bool get isMachined => this != guide;
}

enum TextAlign2 { left, center, right }

sealed class DesignObject {
  DesignObject({
    required this.id,
    required this.name,
    this.color = 0xFF2F6FED,
    this.operation = Operation.cut,
    this.xform = const Xform(),
    this.visible = true,
    this.locked = false,
    this.groupId,
  });

  final String id;
  String name;
  int color;
  Operation operation;
  Xform xform;
  bool visible;
  bool locked;

  /// Objects sharing a group id select, move and lay out on the mat together.
  String? groupId;

  String get kind;

  /// Geometry in local coordinates, roughly centered on the origin.
  List<Contour> get localContours;

  List<Contour> worldContours() =>
      [for (final c in localContours) c.transformed(xform.apply)];

  List<List<Offset>> worldPolylines([double tolerance = 0.05]) {
    final scale = (xform.sx.abs() + xform.sy.abs()) / 2;
    final t = tolerance / (scale == 0 ? 1 : scale);
    return [
      for (final c in localContours)
        if (c.nodes.length > 1) [for (final p in c.flatten(t)) xform.apply(p)],
    ];
  }

  Rect worldBounds() => boundsOfPoints(worldPolylines(0.2).expand((e) => e));

  Map<String, dynamic> baseJson() => {
        'kind': kind,
        'id': id,
        'name': name,
        'color': color,
        'op': operation.name,
        'xf': xform.toJson(),
        if (!visible) 'hidden': true,
        if (locked) 'locked': true,
        if (groupId != null) 'group': groupId,
      };

  Map<String, dynamic> toJson();

  DesignObject clone({required String id});

  static DesignObject fromJson(Map<String, dynamic> j) {
    final DesignObject o = switch (j['kind']) {
      'path' => PathObject(
          id: j['id'],
          name: j['name'],
          contours: [for (final c in j['contours'] as List) Contour.fromJson(c)],
        ),
      'text' => TextObject.fromJsonBody(j),
      'image' => ImageObject(
          id: j['id'],
          name: j['name'],
          assetId: j['asset'],
          width: (j['w'] as num).toDouble(),
          height: (j['h'] as num).toDouble(),
          crop: j['crop'] == null
              ? null
              : Rect.fromLTRB(
                  (j['crop'][0] as num).toDouble(),
                  (j['crop'][1] as num).toDouble(),
                  (j['crop'][2] as num).toDouble(),
                  (j['crop'][3] as num).toDouble(),
                ),
        )..cutOutline = (j['cutOutline'] as List?)?.map((c) => Contour.fromJson(c)).toList(),
      final k => throw FormatException('Unknown object kind $k'),
    };
    o
      ..color = j['color'] as int? ?? o.color
      ..operation = Operation.values.asNameMap()[j['op']] ?? Operation.cut
      ..xform = Xform.fromJson(j['xf'])
      ..visible = !(j['hidden'] as bool? ?? false)
      ..locked = j['locked'] as bool? ?? false
      ..groupId = j['group'] as String?;
    return o;
  }

  void copyBaseTo(DesignObject o) {
    o
      ..color = color
      ..operation = operation
      ..xform = xform
      ..visible = visible
      ..locked = locked
      ..groupId = groupId;
  }
}

class PathObject extends DesignObject {
  PathObject({
    required super.id,
    required super.name,
    required this.contours,
    super.color,
    super.operation,
    super.xform,
  });

  List<Contour> contours;

  @override
  String get kind => 'path';

  @override
  List<Contour> get localContours => contours;

  @override
  Map<String, dynamic> toJson() => {
        ...baseJson(),
        'contours': [for (final c in contours) c.toJson()],
      };

  @override
  PathObject clone({required String id}) {
    final o = PathObject(
      id: id,
      name: name,
      contours: [for (final c in contours) c.copy()],
    );
    copyBaseTo(o);
    return o;
  }
}

/// Text stays editable. Its outline is regenerated from the font and cached in
/// the file, so a project still opens and cuts on a machine without the font.
class TextObject extends DesignObject {
  TextObject({
    required super.id,
    required super.name,
    required this.text,
    required this.fontFamily,
    this.fontStyle = 'Regular',
    this.size = 20,
    this.letterSpacing = 0,
    this.lineSpacing = 1.2,
    this.curve = 0,
    this.align = TextAlign2.left,
    this.useKerning = true,
    super.color,
    super.operation,
    super.xform,
  });

  String text;
  String fontFamily;
  String fontStyle;

  /// Em size in millimetres.
  double size;

  /// Extra spacing between letters, as a fraction of the em size.
  double letterSpacing;

  /// Line advance as a multiple of the font's natural line height.
  double lineSpacing;

  /// Bend in degrees; positive arcs upward, negative downward. 360 is a circle.
  double curve;
  TextAlign2 align;
  bool useKerning;

  List<Contour> outline = [];

  /// The parameters [outline] was generated from.
  String outlineKey = '';

  /// True when the font could not be found and [outline] came from the file.
  bool fontMissing = false;

  String get layoutKey =>
      '$text|$fontFamily|$fontStyle|$size|$letterSpacing|$lineSpacing|$curve|${align.name}|$useKerning';

  @override
  String get kind => 'text';

  @override
  List<Contour> get localContours => outline;

  @override
  Map<String, dynamic> toJson() => {
        ...baseJson(),
        'text': text,
        'font': fontFamily,
        'style': fontStyle,
        'size': size,
        'ls': letterSpacing,
        'lh': lineSpacing,
        'curve': curve,
        'align': align.name,
        'kern': useKerning,
        'outline': [for (final c in outline) c.toJson()],
        'outlineKey': outlineKey,
      };

  static TextObject fromJsonBody(Map<String, dynamic> j) {
    final t = TextObject(
      id: j['id'],
      name: j['name'],
      text: j['text'],
      fontFamily: j['font'],
      fontStyle: j['style'] ?? 'Regular',
      size: (j['size'] as num).toDouble(),
      letterSpacing: (j['ls'] as num? ?? 0).toDouble(),
      lineSpacing: (j['lh'] as num? ?? 1.2).toDouble(),
      curve: (j['curve'] as num? ?? 0).toDouble(),
      align: TextAlign2.values.asNameMap()[j['align']] ?? TextAlign2.left,
      useKerning: j['kern'] as bool? ?? true,
    );
    t.outline = [for (final c in (j['outline'] as List? ?? [])) Contour.fromJson(c)];
    t.outlineKey = j['outlineKey'] as String? ?? '';
    return t;
  }

  @override
  TextObject clone({required String id}) {
    final o = TextObject(
      id: id,
      name: name,
      text: text,
      fontFamily: fontFamily,
      fontStyle: fontStyle,
      size: size,
      letterSpacing: letterSpacing,
      lineSpacing: lineSpacing,
      curve: curve,
      align: align,
      useKerning: useKerning,
    )
      ..outline = [for (final c in outline) c.copy()]
      ..outlineKey = outlineKey
      ..fontMissing = fontMissing;
    copyBaseTo(o);
    return o;
  }
}

/// A raster image. Image bytes live in the project's asset table so undo
/// history and duplicates don't copy them.
class ImageObject extends DesignObject {
  ImageObject({
    required super.id,
    required super.name,
    required this.assetId,
    required this.width,
    required this.height,
    this.crop,
    super.xform,
  }) : super(operation: Operation.print, color: 0xFF000000);

  final String assetId;

  /// Size in millimetres at scale 1.
  double width, height;

  /// Visible part of the image, in local coordinates. Null shows all of it.
  Rect? crop;

  /// Traced cut line around the artwork. Null cuts the image's rectangle.
  List<Contour>? cutOutline;

  Rect get fullRect => Rect.fromCenter(center: Offset.zero, width: width, height: height);
  Rect get visibleRect => crop ?? fullRect;

  @override
  String get kind => 'image';

  @override
  List<Contour> get localContours {
    if (cutOutline != null && cutOutline!.isNotEmpty) return cutOutline!;
    return [_rectContour(visibleRect)];
  }

  static Contour _rectContour(Rect r) =>
      Contour.polyline([r.topLeft, r.topRight, r.bottomRight, r.bottomLeft]);

  /// Covers both the picture and its cut line.
  @override
  Rect worldBounds() {
    final pic = boundsOfPoints(_rectContour(visibleRect).nodes.map((n) => xform.apply(n.p)));
    return cutOutline == null ? pic : pic.expandToInclude(super.worldBounds());
  }

  @override
  Map<String, dynamic> toJson() => {
        ...baseJson(),
        'asset': assetId,
        'w': width,
        'h': height,
        if (crop != null) 'crop': [crop!.left, crop!.top, crop!.right, crop!.bottom],
        if (cutOutline != null) 'cutOutline': [for (final c in cutOutline!) c.toJson()],
      };

  @override
  ImageObject clone({required String id}) {
    final o = ImageObject(
      id: id,
      name: name,
      assetId: assetId,
      width: width,
      height: height,
      crop: crop,
    )..cutOutline = cutOutline?.map((c) => c.copy()).toList();
    copyBaseTo(o);
    return o;
  }
}
