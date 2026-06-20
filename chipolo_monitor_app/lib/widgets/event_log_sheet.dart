import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/ble_scanner_service.dart';

class EventLogSheet extends StatelessWidget {
  const EventLogSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final scanner = context.watch<BleScannerService>();
    final cs = Theme.of(context).colorScheme;
    final log = scanner.eventLog;

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.35,
      maxChildSize: 0.92,
      builder: (_, controller) => Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0D1117),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border.all(color: const Color(0xFF30363D)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 8),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF30363D),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Row(
                children: [
                  Icon(Icons.terminal_rounded,
                      color: cs.primary, size: 18),
                  const SizedBox(width: 8),
                  Text('Event Log',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: cs.onSurface)),
                  const Spacer(),
                  Text('${log.length} events',
                      style: TextStyle(
                          color: cs.onSurface.withAlpha(100), fontSize: 12)),
                ],
              ),
            ),
            const Divider(color: Color(0xFF30363D), height: 1),
            // Log lines
            Expanded(
              child: log.isEmpty
                  ? Center(
                      child: Text(
                        'No events yet.\nStart scanning to see activity.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: cs.onSurface.withAlpha(80), fontSize: 13),
                      ),
                    )
                  : ListView.builder(
                      controller: controller,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      itemCount: log.length,
                      itemBuilder: (_, i) => _LogLine(line: log[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LogLine extends StatelessWidget {
  final String line;
  const _LogLine({required this.line});

  Color _lineColor(String line) {
    if (line.contains('GONE') || line.contains('✗')) {
      return const Color(0xFFEF5350);
    }
    if (line.contains('BACK') || line.contains('✓')) {
      return const Color(0xFF4CAF50);
    }
    if (line.contains('NEW') || line.contains('+')) {
      return const Color(0xFF00BCD4);
    }
    if (line.contains('■') || line.contains('▶')) {
      return const Color(0xFFFFB300);
    }
    return const Color(0xFF8B949E);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text(
        line,
        style: TextStyle(
          color: _lineColor(line),
          fontSize: 11.5,
          fontFamily: 'monospace',
          height: 1.5,
        ),
      ),
    );
  }
}
