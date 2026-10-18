import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../model/project.dart';
import '../storage/project_store.dart';
import '../text/font_registry.dart';
import 'dialogs.dart';
import 'editor_screen.dart';
import 'files.dart';

enum _Filter { all, favorites, folder, trash }

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, required this.store, required this.fonts});
  final ProjectStore store;
  final FontRegistry fonts;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  List<ProjectMeta> projects = [];
  List<ProjectMeta> trash = [];
  final thumbs = <String, Uint8List?>{};
  _Filter filter = _Filter.all;
  String folder = '';
  String query = '';
  bool loading = true;

  ProjectStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final p = await store.list();
    final t = await store.list(trash: true);
    for (final m in p) {
      thumbs[m.id] ??= await store.thumbnail(m.id);
    }
    if (!mounted) return;
    setState(() {
      projects = p;
      trash = t;
      loading = false;
    });
  }

  List<String> get folders => {for (final p in projects) if (p.folder.isNotEmpty) p.folder}.toList()..sort();

  List<ProjectMeta> get visible {
    final src = filter == _Filter.trash ? trash : projects;
    return [
      for (final p in src)
        if ((filter != _Filter.favorites || p.favorite) &&
            (filter != _Filter.folder || p.folder == folder) &&
            (query.isEmpty || p.name.toLowerCase().contains(query.toLowerCase()) || p.folder.toLowerCase().contains(query.toLowerCase())))
          p,
    ];
  }

  void _open(Project p, {bool isNew = false}) => Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => EditorScreen(project: p, store: store, fonts: widget.fonts, isNew: isNew)),
      );

  Future<void> _openId(String id) async {
    final p = await store.load(id);
    if (p == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("This project file couldn't be read.")));
      return;
    }
    _open(p);
  }

  Future<void> _new() async {
    final p = store.create('Untitled project');
    if (filter == _Filter.folder) p.meta.folder = folder;
    _open(p, isNew: true);
  }

  Future<void> _importProject() async {
    for (final f in await pickFiles([projectExtension, 'json'], title: 'Import project')) {
      try {
        await store.importProject(utf8.decode(f.bytes));
      } on FormatException {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("${f.name} isn't an Open Design Space project.")));
      }
    }
    await _reload();
  }

  Future<void> _action(String a, ProjectMeta m) async {
    switch (a) {
      case 'rename':
        final n = await promptText(context, title: 'Rename', initial: m.name, action: 'Rename');
        if (n == null || n.trim().isEmpty) return;
        final p = await store.load(m.id);
        if (p == null) return;
        p.meta.name = n.trim();
        await store.save(p, touch: false);
      case 'folder':
        final n = await promptText(context, title: 'Move to folder', initial: m.folder, label: 'Folder name (empty for none)', action: 'Move');
        if (n == null) return;
        m.folder = n.trim();
        await store.saveMeta(m);
        final p = await store.load(m.id);
        if (p != null) {
          p.meta.folder = m.folder;
          await store.save(p, touch: false);
        }
      case 'favorite':
        m.favorite = !m.favorite;
        await store.saveMeta(m);
        final p = await store.load(m.id);
        if (p != null) {
          p.meta.favorite = m.favorite;
          await store.save(p, touch: false);
        }
      case 'duplicate':
        await store.duplicate(m.id);
      case 'export':
        final p = await store.load(m.id);
        if (p != null) await saveBytes('${safeFileName(m.name)}.$projectExtension', utf8.encode(p.encode()), 'application/json');
      case 'trash':
        await store.trash(m.id);
      case 'restore':
        await store.restore(m.id);
    }
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final wide = MediaQuery.sizeOf(context).width > 760;
    final sidebar = _sidebar(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Projects'),
        actions: [
          SizedBox(
            width: wide ? 280 : 160,
            child: TextField(
              decoration: const InputDecoration(isDense: true, prefixIcon: Icon(Icons.search), hintText: 'Search projects', border: OutlineInputBorder()),
              onChanged: (v) => setState(() => query = v),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(tooltip: 'Import project file', icon: const Icon(Icons.file_open_outlined), onPressed: _importProject),
          IconButton(tooltip: 'About', icon: const Icon(Icons.info_outline), onPressed: () => showAboutApp(context)),
          const SizedBox(width: 8),
          FilledButton.icon(onPressed: _new, icon: const Icon(Icons.add), label: const Text('New project')),
          const SizedBox(width: 12),
        ],
      ),
      drawer: wide ? null : Drawer(child: SafeArea(child: sidebar)),
      body: Row(children: [
        if (wide) ...[SizedBox(width: 220, child: sidebar), const VerticalDivider(width: 1)],
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (filter == _Filter.trash)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                      child: Row(children: [
                        Expanded(child: Text('Deleted projects stay here until you empty the trash.', style: TextStyle(color: scheme.onSurfaceVariant))),
                        TextButton(
                          onPressed: trash.isEmpty
                              ? null
                              : () async {
                                  final ok = await confirm(context,
                                      title: 'Empty trash?',
                                      message: 'This permanently erases ${trash.length} project${trash.length == 1 ? '' : 's'} and their restore points.',
                                      action: 'Empty trash',
                                      destructive: true);
                                  if (ok) {
                                    await store.emptyTrash();
                                    await _reload();
                                  }
                                },
                          child: const Text('Empty trash'),
                        ),
                      ]),
                    ),
                  Expanded(child: _grid(context)),
                ]),
        ),
      ]),
    );
  }

  Widget _sidebar(BuildContext context) {
    Widget item(String label, IconData icon, _Filter f, {String folder = '', int? count}) {
      final selected = filter == f && (f != _Filter.folder || this.folder == folder);
      return ListTile(
        dense: true,
        selected: selected,
        leading: Icon(icon, size: 20),
        title: Text(label, overflow: TextOverflow.ellipsis),
        trailing: count == null ? null : Text('$count'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        onTap: () => setState(() {
          filter = f;
          this.folder = folder;
        }),
      );
    }

    return ListView(padding: const EdgeInsets.all(8), children: [
      item('All projects', Icons.grid_view, _Filter.all, count: projects.length),
      item('Favorites', Icons.star_outline, _Filter.favorites, count: projects.where((p) => p.favorite).length),
      if (folders.isNotEmpty) const Padding(padding: EdgeInsets.fromLTRB(16, 16, 16, 4), child: Text('Folders')),
      for (final f in folders) item(f, Icons.folder_outlined, _Filter.folder, folder: f, count: projects.where((p) => p.folder == f).length),
      const Divider(),
      item('Trash', Icons.delete_outline, _Filter.trash, count: trash.length),
    ]);
  }

  Widget _grid(BuildContext context) {
    final items = visible;
    final scheme = Theme.of(context).colorScheme;
    if (items.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(filter == _Filter.trash ? Icons.delete_outline : Icons.draw_outlined, size: 48, color: scheme.outline),
          const SizedBox(height: 12),
          Text(
            query.isNotEmpty
                ? 'No projects match "$query".'
                : filter == _Filter.trash
                    ? 'Trash is empty.'
                    : 'No projects yet.',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (filter != _Filter.trash) ...[
            const SizedBox(height: 12),
            FilledButton.icon(onPressed: _new, icon: const Icon(Icons.add), label: const Text('New project')),
          ],
        ]),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(24),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 260, mainAxisSpacing: 16, crossAxisSpacing: 16, childAspectRatio: 0.92),
      itemCount: items.length,
      itemBuilder: (context, i) => _card(context, items[i]),
    );
  }

  Widget _card(BuildContext context, ProjectMeta m) {
    final scheme = Theme.of(context).colorScheme;
    final inTrash = filter == _Filter.trash;
    final thumb = thumbs[m.id];
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: scheme.outlineVariant)),
      child: InkWell(
        onTap: inTrash ? null : () => _openId(m.id),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            child: Container(
              color: scheme.surfaceContainerLow,
              padding: const EdgeInsets.all(8),
              child: thumb == null
                  ? Icon(Icons.draw_outlined, size: 40, color: scheme.outline)
                  : Image.memory(thumb, fit: BoxFit.contain, gaplessPlayback: true),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(m.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(
                    [
                      MaterialLocalizations.of(context).formatShortDate(m.updated),
                      if (m.folder.isNotEmpty) m.folder,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                ]),
              ),
              if (!inTrash)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: m.favorite ? 'Unfavorite' : 'Favorite',
                  icon: Icon(m.favorite ? Icons.star : Icons.star_outline, size: 20, color: m.favorite ? Colors.amber.shade700 : null),
                  onPressed: () => _action('favorite', m),
                ),
              PopupMenuButton<String>(
                onSelected: (a) => _action(a, m),
                itemBuilder: (_) => inTrash
                    ? const [PopupMenuItem(value: 'restore', child: Text('Restore'))]
                    : const [
                        PopupMenuItem(value: 'rename', child: Text('Rename')),
                        PopupMenuItem(value: 'folder', child: Text('Move to folder…')),
                        PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
                        PopupMenuItem(value: 'export', child: Text('Export project file')),
                        PopupMenuDivider(),
                        PopupMenuItem(value: 'trash', child: Text('Move to trash')),
                      ],
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
