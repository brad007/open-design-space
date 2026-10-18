import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A compact numeric field that commits on Enter or when focus leaves.
class NumberField extends StatefulWidget {
  const NumberField({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
    this.suffix,
    this.width = 78,
    this.decimals = 2,
    this.enabled = true,
  });

  final double? value;
  final ValueChanged<double> onChanged;
  final String? label, suffix;
  final double width;
  final int decimals;
  final bool enabled;

  @override
  State<NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<NumberField> {
  late final TextEditingController c = TextEditingController(text: _fmt(widget.value));
  final focus = FocusNode();

  String _fmt(double? v) => v == null ? '' : v.toStringAsFixed(widget.decimals).replaceFirst(RegExp(r'\.?0+$'), '');

  @override
  void initState() {
    super.initState();
    focus.addListener(() {
      if (!focus.hasFocus) _commit();
    });
  }

  @override
  void didUpdateWidget(NumberField old) {
    super.didUpdateWidget(old);
    if (!focus.hasFocus && _fmt(widget.value) != c.text) c.text = _fmt(widget.value);
  }

  void _commit() {
    final v = double.tryParse(c.text.replaceAll(',', '.'));
    if (v != null && v != widget.value) {
      widget.onChanged(v);
    } else {
      c.text = _fmt(widget.value);
    }
  }

  @override
  void dispose() {
    c.dispose();
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        width: widget.width,
        child: TextField(
          controller: c,
          focusNode: focus,
          enabled: widget.enabled,
          style: const TextStyle(fontSize: 13),
          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[-0-9.,]'))],
          decoration: InputDecoration(
            isDense: true,
            labelText: widget.label,
            suffixText: widget.suffix,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (_) => _commit(),
        ),
      );
}

class ToolButton extends StatelessWidget {
  const ToolButton({super.key, required this.icon, required this.tooltip, required this.onPressed, this.selected = false});
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        waitDuration: const Duration(milliseconds: 400),
        child: IconButton(
          isSelected: selected,
          style: IconButton.styleFrom(
            backgroundColor: selected ? Theme.of(context).colorScheme.primaryContainer : null,
            foregroundColor: selected ? Theme.of(context).colorScheme.onPrimaryContainer : null,
          ),
          icon: Icon(icon, size: 20),
          onPressed: onPressed,
        ),
      );
}

class BarDivider extends StatelessWidget {
  const BarDivider({super.key});
  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 26,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        color: Theme.of(context).dividerColor,
      );
}

class ColorDot extends StatelessWidget {
  const ColorDot(this.color, {super.key, this.size = 18});
  final int color;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Color(color),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.black26),
        ),
      );
}
