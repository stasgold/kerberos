import 'package:flutter/material.dart';
import '../services/ble_scanner_service.dart';

class StatsBar extends StatelessWidget {
  final BleScannerService scanner;
  const StatsBar({super.key, required this.scanner});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final present = scanner.presentDevices.length;
    final gone = scanner.goneDevices.length;
    final total = scanner.allDevices.length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _Stat(
            value: '$present',
            label: 'In Range',
            color: const Color(0xFF4CAF50),
          ),
          _Divider(),
          _Stat(
            value: '$gone',
            label: 'Gone',
            color: const Color(0xFFEF5350),
          ),
          _Divider(),
          _Stat(
            value: '$total',
            label: 'Total',
            color: const Color(0xFF00BCD4),
          ),
          _Divider(),
          _Stat(
            value: '${scanner.totalPackets}',
            label: 'Packets',
            color: cs.onSurface.withAlpha(180),
          ),
          if (scanner.rssiThreshold != null) ...[
            _Divider(),
            _Stat(
              value: '${scanner.rssiThreshold}',
              label: 'dBm min',
              color: const Color(0xFFFFB300),
            ),
          ],
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  const _Stat({required this.value, required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value,
              style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  fontFamily: 'monospace')),
          Text(label,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface.withAlpha(120),
                  fontSize: 10,
                  letterSpacing: 0.5)),
        ],
      );
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 28,
        color: const Color(0xFF30363D),
      );
}
