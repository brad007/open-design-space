import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../model/objects.dart';
import '../state/editor.dart';
import 'dialogs.dart';
import 'widgets.dart';

class LayersPanel extends StatelessWidget {
  const LayersPanel({super.key, required this.ed});
  final EditorController ed;

  IconData _icon(DesignObject o) => switch (o) {
        TextObject() => Icons.text_fields,
        ImageObject() => Icons.image_outlined,
        PathObject() => Icons.category_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final objs = ed.project.objects;
    // Top of the stack is shown first.
    final shown = objs.reversed.toList();
    return Material(
      color: scheme.surface,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: Row(children: [
            Text('Layers', style: Theme.of(context).textTheme.titleSmall),
            const Spacer(),
            Text('${objs.length}', style: TextStyle(color: scheme.onSurfaceVariant)),
          ]),
        ),
        Expanded(
          child: objs.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('Nothing here yet.', style: TextStyle(color: scheme.onSurfaceVariant)),
                )
              : ReorderableListView.builder(
                  buildDefaultDragHandles: false,
                  itemCount: shown.length,
                  onReorderItem: (from, to) {
                    // Convert top-first indices into the bottom-first list.
                    ed.moveLayer(objs.length - 1 - from, objs.length - 1 - to);
                  },
                  itemBuilder: (context, i) {
                    final o = shown[i];
                    final sel = ed.selection.contains(o.id);
                    return Material(
                      key: ValueKey(o.id),
                      color: sel ? scheme.primaryContainer.withValues(alpha: 0.6) : Colors.transparent,
                      child: InkWell(
                        onTap: () => ed.select([o.id], additive: HardwareKeyboard.instance.isShiftPressed || HardwareKeyboard.instance.isMetaPressed, expandGroups: false),
                        onDoubleTap: () async {
                          final n = await promptText(context, title: 'Rename layer', initial: o.name, action: 'Rename');
                          if (n != null && n.trim().isNotEmpty) ed.rename(o, n.trim());
                        },
                        child: Padding(
                          padding: EdgeInsets.only(left: o.groupId != null ? 22 : 8, right: 4),
                          child: Row(children: [
                            ReorderableDragStartListener(
                              index: i,
                              child: const Padding(padding: EdgeInsets.all(6), child: Icon(Icons.drag_indicator, size: 16)),
                            ),
                            ColorDot(o.color, size: 14),
                            const SizedBox(width: 8),
                            Icon(_icon(o), size: 16, color: scheme.onSurfaceVariant),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(
                                  o.name,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: o.visible ? null : scheme.onSurfaceVariant, fontSize: 13),
                                ),
                                Text(o.operation.label, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                              ]),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              tooltip: o.visible ? 'Hide (hidden layers are not cut)' : 'Show',
                              icon: Icon(o.visible ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 18),
                              onPressed: () => ed.toggleVisible(o),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              tooltip: o.locked ? 'Unlock' : 'Lock',
                              icon: Icon(o.locked ? Icons.lock : Icons.lock_open_outlined, size: 18),
                              onPressed: () => ed.toggleLocked(o),
                            ),
                          ]),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}
