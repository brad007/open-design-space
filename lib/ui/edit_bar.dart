import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../model/objects.dart';
import '../model/project.dart';
import '../state/editor.dart';
import 'dialogs.dart';
import 'widgets.dart';

final _recentFonts = <String>[];

/// Always-visible editing controls for the current selection. They sit above
/// the canvas instead of in a panel, so the canvas never shrinks or jumps.
class EditBar extends StatelessWidget {
  const EditBar({super.key, required this.ed, required this.lockRatio, required this.textFocus, required this.textController});

  final EditorController ed;
  final ValueNotifier<bool> lockRatio;
  final FocusNode textFocus;
  final TextEditingController textController;

  @override
  Widget build(BuildContext context) {
    final sel = ed.selected;
    final scheme = Theme.of(context).colorScheme;
    final rows = <Widget>[];
    if (sel.isEmpty) {
      rows.add(Row(children: [
        Icon(Icons.touch_app_outlined, size: 18, color: scheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Text(
          ed.tool == Tool.pen
              ? 'Draw freehand. End near the start to make a closed, cuttable shape.'
              : ed.tool == Tool.eraser
                  ? 'Drag over shapes to erase. Select shapes first to erase only those.'
                  : ed.tool == Tool.crop
                      ? 'Select what to crop, then drag a rectangle.'
                      : 'Select something, or add a shape, text or image from the left.',
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
        if (ed.tool == Tool.eraser) ...[
          const SizedBox(width: 16),
          const Text('Brush'),
          SizedBox(
            width: 160,
            child: Slider(
              value: ed.eraserWidth,
              min: 0.5,
              max: 25,
              onChanged: (v) {
                ed.eraserWidth = v;
                ed.updateGesture();
              },
            ),
          ),
          Text(ed.project.units.fromMm(ed.eraserWidth).toStringAsFixed(2) + ed.project.units.suffix),
        ],
      ]));
    } else {
      rows.add(_general(context, sel));
      final t = ed.single;
      if (t is TextObject) rows.add(_text(context, t));
      if (t is ImageObject) rows.add(_image(context, t));
      if (ed.tool == Tool.node && ed.nodeTarget != null) rows.add(_node(context));
    }
    return Material(
      color: scheme.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final r in rows)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: SizedBox(height: 40, child: r)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _general(BuildContext context, List<DesignObject> sel) {
    final u = ed.project.units;
    final b = ed.selectionBounds()!;
    final first = sel.first;
    final sameOp = sel.every((o) => o.operation == first.operation);
    final sameColor = sel.every((o) => o.color == first.color);
    final grouped = sel.any((o) => o.groupId != null);
    final rotation = sel.length == 1 ? first.xform.rotation * 180 / math.pi : 0.0;
    return Row(children: [
      DropdownButton<Operation>(
        value: sameOp ? first.operation : null,
        hint: const Text('Mixed'),
        underline: const SizedBox(),
        borderRadius: BorderRadius.circular(8),
        items: [
          for (final op in Operation.values) DropdownMenuItem(value: op, child: Text(op.label)),
        ],
        onChanged: (op) => op == null ? null : ed.setProperty((o) => o.operation = op),
      ),
      const SizedBox(width: 6),
      Tooltip(
        message: 'Color (each color cuts on its own mat)',
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () async {
            final c = await pickColor(context, first.color);
            if (c != null) ed.setProperty((o) => o.color = c);
          },
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: sameColor ? ColorDot(first.color, size: 22) : const Icon(Icons.palette_outlined),
          ),
        ),
      ),
      const BarDivider(),
      NumberField(
        label: 'W',
        suffix: u.suffix,
        value: u.fromMm(b.width),
        onChanged: (v) => ed.resizeSelectionTo(width: u.toMm(v), keepRatio: lockRatio.value),
      ),
      ValueListenableBuilder(
        valueListenable: lockRatio,
        builder: (context, locked, _) => ToolButton(
          icon: locked ? Icons.link : Icons.link_off,
          tooltip: locked ? 'Proportions locked (click to unlock)' : 'Proportions unlocked (click to lock)',
          selected: locked,
          onPressed: () => lockRatio.value = !locked,
        ),
      ),
      NumberField(
        label: 'H',
        suffix: u.suffix,
        value: u.fromMm(b.height),
        onChanged: (v) => ed.resizeSelectionTo(height: u.toMm(v), keepRatio: lockRatio.value),
      ),
      const SizedBox(width: 8),
      NumberField(
        label: 'X',
        suffix: u.suffix,
        value: u.fromMm(b.left),
        onChanged: (v) => ed.nudge(Offset(u.toMm(v) - b.left, 0)),
      ),
      const SizedBox(width: 4),
      NumberField(
        label: 'Y',
        suffix: u.suffix,
        value: u.fromMm(b.top),
        onChanged: (v) => ed.nudge(Offset(0, u.toMm(v) - b.top)),
      ),
      const SizedBox(width: 4),
      NumberField(
        label: 'Rotate',
        suffix: '°',
        width: 74,
        decimals: 1,
        value: rotation,
        onChanged: (v) => ed.rotateSelection((v - rotation) * math.pi / 180, b.center),
      ),
      const BarDivider(),
      PopupMenuButton<AlignMode>(
        tooltip: sel.length == 1 ? 'Align to mat' : 'Align',
        icon: const Icon(Icons.align_horizontal_left, size: 20),
        onSelected: ed.align,
        itemBuilder: (_) => const [
          PopupMenuItem(value: AlignMode.left, child: ListTile(leading: Icon(Icons.align_horizontal_left), title: Text('Left'))),
          PopupMenuItem(value: AlignMode.centerH, child: ListTile(leading: Icon(Icons.align_horizontal_center), title: Text('Center horizontally'))),
          PopupMenuItem(value: AlignMode.right, child: ListTile(leading: Icon(Icons.align_horizontal_right), title: Text('Right'))),
          PopupMenuItem(value: AlignMode.top, child: ListTile(leading: Icon(Icons.align_vertical_top), title: Text('Top'))),
          PopupMenuItem(value: AlignMode.centerV, child: ListTile(leading: Icon(Icons.align_vertical_center), title: Text('Center vertically'))),
          PopupMenuItem(value: AlignMode.bottom, child: ListTile(leading: Icon(Icons.align_vertical_bottom), title: Text('Bottom'))),
        ],
      ),
      PopupMenuButton<String>(
        tooltip: 'Arrange',
        icon: const Icon(Icons.layers_outlined, size: 20),
        onSelected: (v) => switch (v) {
          'front' => ed.toFront(),
          'forward' => ed.reorder(1),
          'backward' => ed.reorder(-1),
          'back' => ed.toBack(),
          'distH' => ed.distribute(horizontal: true),
          'distV' => ed.distribute(horizontal: false),
          _ => null,
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'front', child: Text('Bring to front')),
          const PopupMenuItem(value: 'forward', child: Text('Bring forward  ⌘]')),
          const PopupMenuItem(value: 'backward', child: Text('Send backward  ⌘[')),
          const PopupMenuItem(value: 'back', child: Text('Send to back')),
          const PopupMenuDivider(),
          PopupMenuItem(value: 'distH', enabled: sel.length > 2, child: const Text('Distribute horizontally')),
          PopupMenuItem(value: 'distV', enabled: sel.length > 2, child: const Text('Distribute vertically')),
        ],
      ),
      ToolButton(icon: Icons.flip, tooltip: 'Flip horizontally (mirror)', onPressed: () => ed.flip(horizontal: true)),
      RotatedBox(
        quarterTurns: 1,
        child: ToolButton(icon: Icons.flip, tooltip: 'Flip vertically', onPressed: () => ed.flip(horizontal: false)),
      ),
      grouped
          ? ToolButton(icon: Icons.layers_clear_outlined, tooltip: 'Ungroup  ⌘⇧G', onPressed: ed.ungroup)
          : ToolButton(icon: Icons.workspaces_outlined, tooltip: 'Group (keeps arrangement on the mat)  ⌘G', onPressed: sel.length > 1 ? ed.group : null),
      const BarDivider(),
      TextButton.icon(onPressed: sel.length > 1 ? ed.weld : null, icon: const Icon(Icons.join_full, size: 18), label: const Text('Weld')),
      TextButton.icon(onPressed: sel.length == 2 ? ed.slice : null, icon: const Icon(Icons.content_cut, size: 18), label: const Text('Slice')),
      TextButton.icon(onPressed: sel.length > 1 ? ed.intersectSelected : null, icon: const Icon(Icons.join_inner, size: 18), label: const Text('Intersect')),
      TextButton.icon(onPressed: sel.length > 1 ? ed.subtract : null, icon: const Icon(Icons.join_left, size: 18), label: const Text('Subtract')),
      TextButton.icon(onPressed: () => showOffsetDialog(context, ed), icon: const Icon(Icons.border_outer, size: 18), label: const Text('Offset')),
      const BarDivider(),
      ToolButton(icon: Icons.copy_all_outlined, tooltip: 'Duplicate  ⌘D', onPressed: ed.duplicate),
      ToolButton(icon: Icons.delete_outline, tooltip: 'Delete', onPressed: ed.deleteSelected),
    ]);
  }

  Widget _text(BuildContext context, TextObject t) {
    if (textController.text != t.text && !textFocus.hasFocus) textController.text = t.text;
    final u = ed.project.units;
    final styles = ed.fonts.stylesOf(t.fontFamily);
    return Row(children: [
      SizedBox(
        width: 220,
        child: TextField(
          controller: textController,
          focusNode: textFocus,
          minLines: 1,
          maxLines: 3,
          style: const TextStyle(fontSize: 13),
          decoration: const InputDecoration(isDense: true, labelText: 'Text', border: OutlineInputBorder()),
          onChanged: (v) => ed.editText(t, (t) => t.text = v),
        ),
      ),
      const SizedBox(width: 8),
      OutlinedButton.icon(
        icon: t.fontMissing ? const Icon(Icons.warning_amber, color: Colors.orange, size: 18) : const Icon(Icons.font_download_outlined, size: 18),
        label: Text(t.fontFamily, overflow: TextOverflow.ellipsis),
        onPressed: () async {
          final f = await pickFont(context, ed.fonts, current: t.fontFamily, recent: _recentFonts);
          if (f == null) return;
          _recentFonts
            ..remove(f)
            ..insert(0, f);
          if (_recentFonts.length > 8) _recentFonts.removeLast();
          ed.editText(t, (t) {
            t.fontFamily = f;
            final s = ed.fonts.stylesOf(f);
            if (!s.contains(t.fontStyle)) t.fontStyle = s.first;
          });
        },
      ),
      const SizedBox(width: 4),
      if (styles.length > 1)
        DropdownButton<String>(
          value: styles.contains(t.fontStyle) ? t.fontStyle : styles.first,
          underline: const SizedBox(),
          items: [for (final s in styles) DropdownMenuItem(value: s, child: Text(s))],
          onChanged: (s) => s == null ? null : ed.editText(t, (t) => t.fontStyle = s),
        ),
      const SizedBox(width: 6),
      NumberField(label: 'Size', suffix: u.suffix, value: u.fromMm(t.size * t.xform.sy.abs()), onChanged: (v) {
        ed.editText(t, (t) {
          t.size = u.toMm(v) / t.xform.sy.abs();
        });
      }),
      const SizedBox(width: 4),
      NumberField(label: 'Spacing', value: t.letterSpacing * 100, decimals: 0, width: 84, suffix: '%', onChanged: (v) => ed.editText(t, (t) => t.letterSpacing = v / 100)),
      const SizedBox(width: 4),
      NumberField(label: 'Line', value: t.lineSpacing, decimals: 2, width: 66, onChanged: (v) => ed.editText(t, (t) => t.lineSpacing = v.clamp(0.3, 5))),
      const SizedBox(width: 8),
      const Text('Curve'),
      SizedBox(
        width: 140,
        child: Slider(
          value: t.curve.clamp(-360, 360),
          min: -360,
          max: 360,
          onChangeStart: (_) => ed.beginGesture(),
          onChanged: (v) {
            t.curve = (v.abs() < 4 ? 0 : v).roundToDouble();
            ed.updateGesture();
          },
          onChangeEnd: (_) => ed.endGesture(),
        ),
      ),
      NumberField(value: t.curve, decimals: 0, width: 72, suffix: '°', onChanged: (v) => ed.editText(t, (t) => t.curve = v.clamp(-360, 360))),
      const SizedBox(width: 8),
      SegmentedButton<TextAlign2>(
        showSelectedIcon: false,
        style: const ButtonStyle(visualDensity: VisualDensity.compact),
        segments: const [
          ButtonSegment(value: TextAlign2.left, icon: Icon(Icons.format_align_left, size: 18)),
          ButtonSegment(value: TextAlign2.center, icon: Icon(Icons.format_align_center, size: 18)),
          ButtonSegment(value: TextAlign2.right, icon: Icon(Icons.format_align_right, size: 18)),
        ],
        selected: {t.align},
        onSelectionChanged: (s) => ed.editText(t, (t) => t.align = s.first),
      ),
      const SizedBox(width: 4),
      FilterChip(
        label: const Text('Kerning'),
        selected: t.useKerning,
        onSelected: (v) => ed.editText(t, (t) => t.useKerning = v),
      ),
      const SizedBox(width: 8),
      TextButton.icon(
        onPressed: ed.textToOutlines,
        icon: const Icon(Icons.gesture, size: 18),
        label: const Text('To outlines'),
      ),
      if (t.fontMissing)
        const Padding(
          padding: EdgeInsets.only(left: 8),
          child: Text('Font not installed. Showing the saved outline.', style: TextStyle(color: Colors.orange)),
        ),
    ]);
  }

  Widget _image(BuildContext context, ImageObject img) => Row(children: [
        FilledButton.tonalIcon(
          onPressed: () => showTraceDialog(context, ed),
          icon: const Icon(Icons.auto_fix_high, size: 18),
          label: Text(img.cutOutline == null ? 'Trace outline' : 'Re-trace'),
        ),
        const SizedBox(width: 8),
        if (img.cutOutline != null)
          TextButton(onPressed: ed.clearCutOutline, child: const Text('Cut the rectangle instead')),
        TextButton.icon(
          onPressed: () => ed.setTool(Tool.crop),
          icon: const Icon(Icons.crop, size: 18),
          label: const Text('Crop'),
        ),
        if (img.crop != null)
          TextButton(onPressed: () => ed.setProperty((o) => (o as ImageObject).crop = null), child: const Text('Uncrop')),
        const SizedBox(width: 8),
        Text(
          img.operation == Operation.print ? 'Prints, then cuts along the red line.' : 'Set the operation to "Print then cut" to print this image.',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ]);

  Widget _node(BuildContext context) {
    final hasNode = ed.activeNode != null;
    return Row(children: [
      Text('Drag points and handles. Double-click an outline to add a point.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      const SizedBox(width: 12),
      TextButton.icon(onPressed: hasNode ? ed.toggleActiveNodeSmooth : null, icon: const Icon(Icons.timeline, size: 18), label: const Text('Smooth / corner')),
      TextButton.icon(onPressed: hasNode ? ed.deleteActiveNode : null, icon: const Icon(Icons.remove_circle_outline, size: 18), label: const Text('Delete point')),
      TextButton.icon(onPressed: hasNode ? ed.breakAtActiveNode : null, icon: const Icon(Icons.call_split, size: 18), label: const Text('Break path')),
      TextButton(onPressed: () => ed.setTool(Tool.select), child: const Text('Done')),
    ]);
  }
}
