import 'dart:convert';
import 'dart:ui';

import 'objects.dart';

const projectFormat = 'open-design-space';
const projectFormatVersion = 1;
const projectExtension = 'odsx';

enum Units { mm, inch }

extension UnitsX on Units {
  double fromMm(double mm) => this == Units.mm ? mm : mm / 25.4;
  double toMm(double v) => this == Units.mm ? v : v * 25.4;
  String get suffix => this == Units.mm ? 'mm' : 'in';
}

class MatSize {
  const MatSize(this.name, this.width, this.height);
  final String name;

  /// Millimetres.
  final double width, height;

  static const presets = [
    MatSize('12 × 12 in', 304.8, 304.8),
    MatSize('12 × 24 in', 304.8, 609.6),
    MatSize('4.5 × 6.5 in', 114.3, 165.1),
    MatSize('Letter (8.5 × 11 in)', 215.9, 279.4),
    MatSize('A4', 210, 297),
  ];

  Map<String, dynamic> toJson() => {'name': name, 'w': width, 'h': height};
  factory MatSize.fromJson(Map<String, dynamic> j) =>
      MatSize(j['name'], (j['w'] as num).toDouble(), (j['h'] as num).toDouble());
}

/// Where the user placed a mat item by hand.
class MatPlacement {
  MatPlacement(this.matKey, this.offset);
  String matKey;

  /// Top-left of the item on the mat, in millimetres.
  Offset offset;

  Map<String, dynamic> toJson() => {'mat': matKey, 'x': offset.dx, 'y': offset.dy};
  factory MatPlacement.fromJson(Map<String, dynamic> j) =>
      MatPlacement(j['mat'], Offset((j['x'] as num).toDouble(), (j['y'] as num).toDouble()));
}

class MatSettings {
  MatSize matSize = MatSize.presets.first;

  /// Pack items tightly instead of keeping the canvas arrangement.
  bool autoPack = true;

  /// Gap between packed items, mm.
  double spacing = 6;

  /// Margin kept clear around the mat edge, mm.
  double margin = 6;

  /// User-chosen cutting order of mats (mat keys). Unlisted mats follow.
  List<String> order = [];

  /// Manual placements by item key (object id or group id).
  Map<String, MatPlacement> placements = {};

  /// Mats to cut mirrored, e.g. for heat-transfer vinyl.
  Set<String> mirrored = {};

  /// Print then Cut sheet.
  MatSize printSheet = MatSize.presets[3];
  double printMargin = 6.35;

  Map<String, dynamic> toJson() => {
        'size': matSize.toJson(),
        'autoPack': autoPack,
        'spacing': spacing,
        'margin': margin,
        'order': order,
        'placements': placements.map((k, v) => MapEntry(k, v.toJson())),
        'mirrored': mirrored.toList(),
        'printSheet': printSheet.toJson(),
        'printMargin': printMargin,
      };

  static MatSettings fromJson(Map<String, dynamic>? j) {
    final m = MatSettings();
    if (j == null) return m;
    if (j['size'] != null) m.matSize = MatSize.fromJson(j['size']);
    m.autoPack = j['autoPack'] as bool? ?? true;
    m.spacing = (j['spacing'] as num? ?? 6).toDouble();
    m.margin = (j['margin'] as num? ?? 6).toDouble();
    m.order = [...(j['order'] as List? ?? []).cast<String>()];
    m.placements = (j['placements'] as Map<String, dynamic>? ?? {})
        .map((k, v) => MapEntry(k, MatPlacement.fromJson(v)));
    m.mirrored = {...(j['mirrored'] as List? ?? []).cast<String>()};
    if (j['printSheet'] != null) m.printSheet = MatSize.fromJson(j['printSheet']);
    m.printMargin = (j['printMargin'] as num? ?? 6.35).toDouble();
    return m;
  }
}

class Asset {
  Asset(this.mime, this.bytes);
  final String mime;
  final List<int> bytes;

  Map<String, dynamic> toJson() => {'mime': mime, 'data': base64Encode(bytes)};
  factory Asset.fromJson(Map<String, dynamic> j) => Asset(j['mime'], base64Decode(j['data']));
}

/// Summary shown in the library without loading the whole project.
class ProjectMeta {
  ProjectMeta({
    required this.id,
    required this.name,
    this.folder = '',
    this.favorite = false,
    required this.created,
    required this.updated,
    this.objectCount = 0,
  });

  final String id;
  String name;
  String folder;
  bool favorite;
  DateTime created;
  DateTime updated;
  int objectCount;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'folder': folder,
        'favorite': favorite,
        'created': created.toIso8601String(),
        'updated': updated.toIso8601String(),
        'objects': objectCount,
      };

  factory ProjectMeta.fromJson(Map<String, dynamic> j) => ProjectMeta(
        id: j['id'],
        name: j['name'] ?? 'Untitled',
        folder: j['folder'] ?? '',
        favorite: j['favorite'] ?? false,
        created: DateTime.tryParse(j['created'] ?? '') ?? DateTime.now(),
        updated: DateTime.tryParse(j['updated'] ?? '') ?? DateTime.now(),
        objectCount: j['objects'] ?? 0,
      );
}

class Project {
  Project({
    required this.meta,
    List<DesignObject>? objects,
    Map<String, Asset>? assets,
    MatSettings? mat,
    this.units = Units.inch,
  })  : objects = objects ?? [],
        assets = assets ?? {},
        mat = mat ?? MatSettings();

  final ProjectMeta meta;

  /// Bottom to top.
  List<DesignObject> objects;
  Map<String, Asset> assets;
  MatSettings mat;
  Units units;

  DesignObject? byId(String id) {
    for (final o in objects) {
      if (o.id == id) return o;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'format': projectFormat,
        'version': projectFormatVersion,
        'meta': (meta..objectCount = objects.length).toJson(),
        'units': units.name,
        'objects': [for (final o in objects) o.toJson()],
        'mat': mat.toJson(),
        'assets': assets.map((k, v) => MapEntry(k, v.toJson())),
      };

  String encode() => jsonEncode(toJson());

  factory Project.fromJson(Map<String, dynamic> j) {
    if (j['format'] != projectFormat) {
      throw const FormatException('Not an Open Design Space project');
    }
    return Project(
      meta: ProjectMeta.fromJson(j['meta']),
      units: Units.values.asNameMap()[j['units']] ?? Units.inch,
      objects: [for (final o in j['objects'] as List) DesignObject.fromJson(o)],
      mat: MatSettings.fromJson(j['mat']),
      assets: (j['assets'] as Map<String, dynamic>? ?? {})
          .map((k, v) => MapEntry(k, Asset.fromJson(v))),
    );
  }

  factory Project.decode(String s) => Project.fromJson(jsonDecode(s));
}
