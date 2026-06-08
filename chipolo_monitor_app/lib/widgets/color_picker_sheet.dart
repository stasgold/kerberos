import 'package:flutter/material.dart';
import '../models/chipolo_device.dart';

class ColorPickerSheet extends StatelessWidget {
  final ChipoloDevice device;
  final void Function(int? colorIndex) onSelected;

  const ColorPickerSheet({
    super.key,
    required this.device,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0D1117),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF30363D),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Row(
            children: [
              const Icon(Icons.palette_outlined,
                  color: Color(0xFF00BCD4), size: 18),
              const SizedBox(width: 8),
              Text(
                'Tag Color — ${device.displayName}',
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 15),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Color cannot be read from BLE data.\nAssign manually to match your physical tag.',
            style: TextStyle(
                color: cs.onSurface.withAlpha(100), fontSize: 12),
          ),
          const SizedBox(height: 20),
          // Color swatches grid
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              // "Unset" option
              _ColorSwatch(
                color: cs.surfaceContainer,
                label: 'None',
                selected: device.colorIndex == null,
                isNone: true,
                onTap: () {
                  onSelected(null);
                  Navigator.pop(context);
                },
              ),
              ...List.generate(chipoloTagColors.length, (i) {
                final c = chipoloTagColors[i];
                return _ColorSwatch(
                  color: c.color,
                  label: c.label,
                  selected: device.colorIndex == i,
                  onTap: () {
                    onSelected(i);
                    Navigator.pop(context);
                  },
                );
              }),
            ],
          ),
        ],
      ),
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  final Color color;
  final String label;
  final bool selected;
  final bool isNone;
  final VoidCallback onTap;

  const _ColorSwatch({
    required this.color,
    required this.label,
    required this.selected,
    required this.onTap,
    this.isNone = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected
                    ? const Color(0xFF00BCD4)
                    : Colors.white.withAlpha(30),
                width: selected ? 3 : 1,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: const Color(0xFF00BCD4).withAlpha(100),
                        blurRadius: 8,
                        spreadRadius: 1,
                      )
                    ]
                  : [],
            ),
            child: isNone
                ? Icon(Icons.block_outlined,
                    color: Colors.white.withAlpha(80), size: 24)
                : selected
                    ? const Icon(Icons.check, color: Colors.white, size: 22)
                    : null,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: selected
                  ? const Color(0xFF00BCD4)
                  : Colors.white.withAlpha(140),
              fontWeight:
                  selected ? FontWeight.w700 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}
