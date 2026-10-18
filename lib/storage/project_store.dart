import 'dart:convert';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../model/project.dart';
import '../platform/platform.dart';

const _uuid = Uuid();

String newId() => _uuid.v4();

/// Projects live as plain files in the app's data folder:
///
/// ```text
/// projects/{id}.odsx        the project (JSON)
/// projects/{id}.meta.json   name/folder/favorite for the library
/// thumbs/{id}.png           library thumbnail
/// snapshots/{id}/{ms}.odsx  restore points
/// trash/                    deleted projects, restorable
/// ```
class ProjectStore {
  ProjectStore(this.files);

  static Future<ProjectStore> open() async => ProjectStore(FileStore(await appDataDir()));

  final FileStore files;
  static const maxSnapshots = 30;

  Future<List<ProjectMeta>> list({bool trash = false}) async {
    final dir = trash ? 'trash' : 'projects';
    final metas = <ProjectMeta>[];
    for (final f in await files.list(dir)) {
      if (!f.endsWith('.meta.json')) continue;
      final s = await files.readString('$dir/$f');
      if (s == null) continue;
      try {
        metas.add(ProjectMeta.fromJson(jsonDecode(s)));
      } on FormatException {
        // A damaged index entry; the project file itself is still there.
      }
    }
    metas.sort((a, b) => b.updated.compareTo(a.updated));
    return metas;
  }

  Project create(String name) {
    final now = DateTime.now();
    return Project(meta: ProjectMeta(id: newId(), name: name, created: now, updated: now));
  }

  Future<Project?> load(String id) async {
    final s = await files.readString('projects/$id.$projectExtension');
    return s == null ? null : Project.decode(s);
  }

  Future<void> save(Project p, {Uint8List? thumbnail, bool touch = true}) async {
    if (touch) p.meta.updated = DateTime.now();
    await files.writeAtomic('projects/${p.meta.id}.$projectExtension', utf8.encode(p.encode()));
    await saveMeta(p.meta..objectCount = p.objects.length);
    if (thumbnail != null) await files.writeAtomic('thumbs/${p.meta.id}.png', thumbnail);
  }

  Future<void> saveMeta(ProjectMeta m, {bool trash = false}) =>
      files.writeAtomic('${trash ? 'trash' : 'projects'}/${m.id}.meta.json', utf8.encode(jsonEncode(m.toJson())));

  Future<Uint8List?> thumbnail(String id) => files.readBytes('thumbs/$id.png');

  Future<void> snapshot(Project p) async {
    final dir = 'snapshots/${p.meta.id}';
    await files.writeAtomic('$dir/${DateTime.now().millisecondsSinceEpoch}.$projectExtension', utf8.encode(p.encode()));
    final all = await snapshots(p.meta.id);
    for (final old in all.skip(maxSnapshots)) {
      await files.delete('$dir/${old.millisecondsSinceEpoch}.$projectExtension');
    }
  }

  /// Newest first.
  Future<List<DateTime>> snapshots(String id) async {
    final names = await files.list('snapshots/$id');
    final times = [
      for (final n in names)
        if (n.endsWith('.$projectExtension'))
          if (int.tryParse(n.split('.').first) case final ms?) DateTime.fromMillisecondsSinceEpoch(ms),
    ]..sort((a, b) => b.compareTo(a));
    return times;
  }

  Future<Project?> loadSnapshot(String id, DateTime at) async {
    final s = await files.readString('snapshots/$id/${at.millisecondsSinceEpoch}.$projectExtension');
    return s == null ? null : Project.decode(s);
  }

  Future<Project> duplicate(String id) async {
    final p = (await load(id))!;
    final now = DateTime.now();
    final copy = Project.decode(p.encode());
    final meta = ProjectMeta(
      id: newId(),
      name: '${p.meta.name} copy',
      folder: p.meta.folder,
      created: now,
      updated: now,
    );
    final out = Project(meta: meta, objects: copy.objects, assets: copy.assets, mat: copy.mat, units: copy.units);
    await save(out);
    final thumb = await thumbnail(id);
    if (thumb != null) await files.writeAtomic('thumbs/${meta.id}.png', thumb);
    return out;
  }

  /// Moves a project to the trash. Nothing is erased until the trash is emptied.
  Future<void> trash(String id) async {
    final s = await files.readString('projects/$id.$projectExtension');
    final m = await files.readString('projects/$id.meta.json');
    if (s != null) await files.writeAtomic('trash/$id.$projectExtension', utf8.encode(s));
    if (m != null) await files.writeAtomic('trash/$id.meta.json', utf8.encode(m));
    await files.delete('projects/$id.$projectExtension');
    await files.delete('projects/$id.meta.json');
  }

  Future<void> restore(String id) async {
    final s = await files.readString('trash/$id.$projectExtension');
    final m = await files.readString('trash/$id.meta.json');
    if (s != null) await files.writeAtomic('projects/$id.$projectExtension', utf8.encode(s));
    if (m != null) await files.writeAtomic('projects/$id.meta.json', utf8.encode(m));
    await files.delete('trash/$id.$projectExtension');
    await files.delete('trash/$id.meta.json');
  }

  Future<void> emptyTrash() async {
    for (final m in await list(trash: true)) {
      await files.deleteDir('snapshots/${m.id}');
      await files.delete('thumbs/${m.id}.png');
    }
    await files.deleteDir('trash');
  }

  /// Adds a project from an exported .odsx file as a new project.
  Future<Project> importProject(String source) async {
    final p = Project.decode(source);
    final now = DateTime.now();
    final meta = ProjectMeta(id: newId(), name: p.meta.name, folder: p.meta.folder, created: now, updated: now);
    final out = Project(meta: meta, objects: p.objects, assets: p.assets, mat: p.mat, units: p.units);
    await save(out);
    return out;
  }
}
