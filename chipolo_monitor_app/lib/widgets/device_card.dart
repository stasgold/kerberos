import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/chipolo_device.dart';
import '../services/ble_scanner_service.dart';
import 'color_picker_sheet.dart';

class DeviceCard extends StatelessWidget {
  final ChipoloDevice device;
  const DeviceCard({super.key, required this.device});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isPresent = device.isPresent;
    final accent = isPresent ? const Color(0xFF00BCD4) : const Color(0xFF6E7681);
    final statusColor =
        isPresent ? const Color(0xFF4CAF50) : const Color(0xFFEF5350);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isPresent
              ? const Color(0xFF00BCD4).withAlpha(60)
              : const Color(0xFF30363D),
          width: isPresent ? 1.5 : 1,
        ),
        boxShadow: isPresent
            ? [BoxShadow(color: const Color(0xFF00BCD4).withAlpha(20), blurRadius: 12)]
            : [],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 0),
            child: Row(
              children: [
                _StatusDot(isPresent: isPresent, color: statusColor),
                const SizedBox(width: 8),
                // Color dot (manual assignment)
                if (device.tagColor != null) ...[
                  GestureDetector(
                    onTap: () => _showColorPicker(context),
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: device.tagColor,
                        border: Border.all(color: Colors.white24, width: 1),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                // Name + edit button
                Expanded(
                  child: GestureDetector(
                    onTap: () => _showNameEditor(context),
                    child: Row(
                      children: [
                        Flexible(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                device.displayName,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700, fontSize: 16),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                device.shortAddress,
                                style: TextStyle(
                                    color: cs.onSurface.withAlpha(100),
                                    fontSize: 11,
                                    fontFamily: 'monospace'),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.edit_outlined,
                            size: 14,
                            color: cs.onSurface.withAlpha(80)),
                      ],
                    ),
                  ),
                ),
                // Color assign button
                IconButton(
                  icon: Icon(Icons.palette_outlined,
                      size: 18,
                      color: device.tagColor ??
                          cs.onSurface.withAlpha(80)),
                  tooltip: 'Assign color',
                  onPressed: () => _showColorPicker(context),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
                // Delete button
                IconButton(
                  icon: Icon(Icons.delete_outline_rounded,
                      size: 18,
                      color: cs.onSurface.withAlpha(80)),
                  tooltip: 'Forget device',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: () => _confirmDelete(context),
                ),
                // Signal bars
                _SignalBars(bars: device.signalBars, color: accent),
                const SizedBox(width: 4),
              ],
            ),
          ),

          // ── RSSI sparkline ───────────────────────────────────────────
          if (device.rssiHistory.length > 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: SizedBox(
                height: 36,
                child: _RssiSparkline(
                    values: device.rssiHistory,
                    color: isPresent ? accent : Colors.grey),
              ),
            ),

          // ── Stats row ────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            child: Row(
              children: [
                _Chip(
                    icon: Icons.wifi_outlined,
                    label: '${device.lastRssi} dBm',
                    color: _rssiColor(device.lastRssi)),
                const SizedBox(width: 8),
                _Chip(
                    icon: Icons.receipt_long_outlined,
                    label: '${device.packetCount} pkts',
                    color: accent),
                const SizedBox(width: 8),
                if (isPresent)
                  _Chip(
                      icon: Icons.check_circle_outline,
                      label: 'IN RANGE',
                      color: const Color(0xFF4CAF50))
                else
                  _Chip(
                      icon: Icons.arrow_outward_rounded,
                      label: 'GONE  ${_formatDuration(device.goneDuration)}',
                      color: const Color(0xFFEF5350)),
              ],
            ),
          ),

          // ── FE65 payload ─────────────────────────────────────────────
          if (device.fe65Info.isNotEmpty)
            _Fe65Details(info: device.fe65Info, accent: accent),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    final scanner = context.read<BleScannerService>();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Forget device?'),
        content: Text(
            '"${device.displayName}" will be removed from the list. '
            'It will reappear if seen again via BLE.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              scanner.removeDevice(device.address);
              Navigator.pop(ctx);
            },
            child: const Text('Forget',
                style: TextStyle(color: Color(0xFFEF5350))),
          ),
        ],
      ),
    );
  }

  void _showNameEditor(BuildContext context) {
    final scanner = context.read<BleScannerService>();
    final ctrl = TextEditingController(
        text: device.customName ?? device.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename device'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(
            hintText: device.name,
            labelText: 'Display name',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () => ctrl.clear(),
            ),
          ),
          onSubmitted: (v) {
            scanner.setDeviceName(device.address, v.isEmpty ? null : v);
            Navigator.pop(ctx);
          },
        ),
        actions: [
          TextButton(
            onPressed: () {
              scanner.setDeviceName(device.address, null); // reset to BLE name
              Navigator.pop(ctx);
            },
            child: Text('Reset',
                style: TextStyle(
                    color: Theme.of(ctx).colorScheme.onSurface.withAlpha(140))),
          ),
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              scanner.setDeviceName(
                  device.address, ctrl.text.isEmpty ? null : ctrl.text);
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showColorPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => ColorPickerSheet(
        device: device,
        onSelected: (idx) =>
            context.read<BleScannerService>().setDeviceColor(device.address, idx),
      ),
    );
  }

  Color _rssiColor(int rssi) {
    if (rssi >= -60) return const Color(0xFF4CAF50);
    if (rssi >= -75) return const Color(0xFFFFB300);
    return const Color(0xFFEF5350);
  }

  String _formatDuration(Duration d) {
    if (d.inHours > 0) return '${d.inHours}h';
    if (d.inMinutes > 0) return '${d.inMinutes}m';
    return '${d.inSeconds}s';
  }
}

// ── Status dot ───────────────────────────────────────────────────────────────

class _StatusDot extends StatefulWidget {
  final bool isPresent;
  final Color color;
  const _StatusDot({required this.isPresent, required this.color});
  @override
  State<_StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<_StatusDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat();
    _anim = Tween(begin: 0.0, end: 1.0).animate(_ctrl);
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 20, height: 20,
    child: Stack(alignment: Alignment.center, children: [
      if (widget.isPresent)
        AnimatedBuilder(
          animation: _anim,
          builder: (_, __) => Container(
            width: 20 * _anim.value, height: 20 * _anim.value,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.color.withAlpha((80 * (1 - _anim.value)).toInt()),
            ),
          ),
        ),
      Container(
        width: 10, height: 10,
        decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color),
      ),
    ]),
  );
}

// ── Signal bars ──────────────────────────────────────────────────────────────

class _SignalBars extends StatelessWidget {
  final int bars;
  final Color color;
  const _SignalBars({required this.bars, required this.color});
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.end,
    children: List.generate(5, (i) {
      final active = i < bars;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 1.5),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 4,
          height: 6.0 + i * 3.0,
          decoration: BoxDecoration(
            color: active ? color : color.withAlpha(40),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );
    }),
  );
}

// ── RSSI sparkline ───────────────────────────────────────────────────────────

class _RssiSparkline extends StatelessWidget {
  final List<int> values;
  final Color color;
  const _RssiSparkline({required this.values, required this.color});
  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _SparklinePainter(values: values, color: color));
}

class _SparklinePainter extends CustomPainter {
  final List<int> values;
  final Color color;
  _SparklinePainter({required this.values, required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    const minVal = -100.0;
    const maxVal = -30.0;
    const range = maxVal - minVal;
    double norm(int v) =>
        1.0 - ((v.clamp(-100, -30).toDouble() - minVal) / range);
    final linePaint = Paint()
      ..color = color.withAlpha(200)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.withAlpha(60), color.withAlpha(0)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;
    final path = Path();
    final fill = Path();
    for (int i = 0; i < values.length; i++) {
      final x = (i / (values.length - 1)) * size.width;
      final y = norm(values[i]) * size.height;
      if (i == 0) {
        path.moveTo(x, y);
        fill.moveTo(x, size.height);
        fill.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fill.lineTo(x, y);
      }
    }
    fill.lineTo(size.width, size.height);
    fill.close();
    canvas.drawPath(fill, fillPaint);
    canvas.drawPath(path, linePaint);
  }
  @override
  bool shouldRepaint(_SparklinePainter old) => old.values != values;
}

// ── Chip label ───────────────────────────────────────────────────────────────

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _Chip({required this.icon, required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withAlpha(28),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                color: color, fontSize: 11, fontWeight: FontWeight.w600)),
      ],
    ),
  );
}

// ── FE65 details ─────────────────────────────────────────────────────────────

class _Fe65Details extends StatelessWidget {
  final Map<String, String> info;
  final Color accent;
  const _Fe65Details({required this.info, required this.accent});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 4,
        children: [
          Text('FE65',
              style: TextStyle(
                  color: accent,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1)),
          ...info.entries.map((e) => Text('${e.key}: ${e.value}',
              style: TextStyle(
                  color: cs.onSurface.withAlpha(160),
                  fontSize: 11,
                  fontFamily: 'monospace'))),
        ],
      ),
    );
  }
}
