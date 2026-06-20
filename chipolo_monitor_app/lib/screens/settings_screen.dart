import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/ble_scanner_service.dart';
import '../services/notification_settings_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _rssiEnabled = false;
  int _rssiValue = -70;

  // Notification settings (loaded lazily from the service)
  bool _notifyEnabled = false;
  String _notifyEmail = NotificationSettingsService.defaultEmail;
  String _smtpHost = NotificationSettingsService.defaultSmtpHost;
  int _smtpPort = NotificationSettingsService.defaultSmtpPort;
  String _smtpUser = '';
  String _smtpPassword = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = context.read<BleScannerService>();
    _rssiEnabled = s.rssiThreshold != null;
    _rssiValue = s.rssiThreshold ?? -70;

    final ns = s.notifSettings;
    if (ns != null) {
      _notifyEnabled = ns.enabled;
      _notifyEmail = ns.notifyEmail;
      _smtpHost = ns.smtpHost;
      _smtpPort = ns.smtpPort;
      _smtpUser = ns.smtpUser;
      _smtpPassword = ns.smtpPassword;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scanner = context.watch<BleScannerService>();
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Scan Interval ──────────────────────────────────────────
          _SectionHeader('Scan'),
          _InfoCard(
            icon: Icons.refresh_rounded,
            title: 'Scan restart interval',
            subtitle:
                'BLE scan restarts every N seconds. '
                'Shorter = faster detection, more battery. '
                'Longer = lower battery use.',
            trailing: null,
          ),
          const SizedBox(height: 10),
          _IntervalPicker(
            selected: scanner.scanIntervalSec,
            onChanged: (v) => scanner.setScanInterval(v),
          ),

          const SizedBox(height: 24),
          // ── Detection ─────────────────────────────────────────────
          _SectionHeader('Detection'),
          _InfoCard(
            icon: Icons.timer_outlined,
            title: 'Gone timeout',
            subtitle:
                'Device marked as gone after ${scanner.timeoutSec.toInt()}s '
                'without a BLE packet.',
          ),
          const SizedBox(height: 12),
          _InfoCard(
            icon: Icons.signal_cellular_alt_rounded,
            title: 'RSSI Room Filter',
            subtitle:
                'Ignore packets weaker than threshold — simulates a smaller '
                'detection radius.',
            trailing: Switch(
              value: _rssiEnabled,
              onChanged: (v) {
                setState(() => _rssiEnabled = v);
                scanner.setRssiThreshold(v ? _rssiValue : null);
              },
            ),
          ),
          if (_rssiEnabled) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Threshold: $_rssiValue dBm',
                          style:
                              TextStyle(color: cs.onSurface.withAlpha(180))),
                      Text(_rssiLabel(_rssiValue),
                          style: TextStyle(
                              color: _rssiColor(_rssiValue),
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                  Slider(
                    value: _rssiValue.toDouble(),
                    min: -100,
                    max: -40,
                    divisions: 60,
                    label: '$_rssiValue dBm',
                    onChanged: (v) {
                      setState(() => _rssiValue = v.toInt());
                      scanner.setRssiThreshold(_rssiValue);
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('-100 dBm\n(far)',
                            style: TextStyle(
                                color: cs.onSurface.withAlpha(80),
                                fontSize: 11),
                            textAlign: TextAlign.center),
                        Text('-40 dBm\n(very close)',
                            style: TextStyle(
                                color: cs.onSurface.withAlpha(80),
                                fontSize: 11),
                            textAlign: TextAlign.center),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 24),
          _SectionHeader('Data'),
          _TileButton(
            icon: Icons.delete_sweep_outlined,
            label: 'Clear gone devices',
            color: const Color(0xFFFFB300),
            onTap: () {
              scanner.clearGoneDevices();
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Gone devices cleared')));
            },
          ),
          const SizedBox(height: 8),
          _TileButton(
            icon: Icons.clear_all_rounded,
            label: 'Clear all devices',
            color: const Color(0xFFEF5350),
            onTap: () => showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Clear all?'),
                content: const Text('This resets all device history.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel')),
                  TextButton(
                    onPressed: () {
                      scanner.clearAll();
                      Navigator.pop(ctx);
                    },
                    child: const Text('Clear',
                        style: TextStyle(color: Color(0xFFEF5350))),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),
          // ── Notifications ─────────────────────────────────────────
          _SectionHeader('Notifications'),
          _InfoCard(
            icon: Icons.mail_outline_rounded,
            title: 'Email alert on device gone',
            subtitle:
                'Send an email when a device has been out of range for '
                '1 minute. Requires SMTP credentials (e.g. Gmail App Password).',
            trailing: Switch(
              value: _notifyEnabled,
              onChanged: (v) {
                setState(() => _notifyEnabled = v);
                final sc = context.read<BleScannerService>();
                sc.notifSettings?.setEnabled(v);
                sc.addLog('[NOTIF] Email alerts ${v ? "enabled" : "disabled"}');
              },
            ),
          ),
          if (_notifyEnabled) ...[
            const SizedBox(height: 10),
            _TextSetting(
              label: 'Recipient email',
              value: _notifyEmail,
              hint: NotificationSettingsService.defaultEmail,
              icon: Icons.alternate_email_rounded,
              onSaved: (v) {
                if (v == _notifyEmail) return;
                setState(() => _notifyEmail = v);
                final sc = context.read<BleScannerService>();
                sc.notifSettings?.setNotifyEmail(v);
                sc.addLog('[NOTIF] Recipient email saved → $v');
              },
            ),
            const SizedBox(height: 8),
            _TextSetting(
              label: 'SMTP host',
              value: _smtpHost,
              hint: NotificationSettingsService.defaultSmtpHost,
              icon: Icons.dns_outlined,
              onSaved: (v) {
                if (v == _smtpHost) return;
                setState(() => _smtpHost = v);
                final sc = context.read<BleScannerService>();
                sc.notifSettings?.setSmtpHost(v);
                sc.addLog('[NOTIF] SMTP host saved → $v');
              },
            ),
            const SizedBox(height: 8),
            _TextSetting(
              label: 'SMTP port',
              value: _smtpPort.toString(),
              hint: '${NotificationSettingsService.defaultSmtpPort}',
              icon: Icons.settings_ethernet_rounded,
              keyboard: TextInputType.number,
              onSaved: (v) {
                final port = int.tryParse(v) ?? NotificationSettingsService.defaultSmtpPort;
                if (port == _smtpPort) return;
                setState(() => _smtpPort = port);
                final sc = context.read<BleScannerService>();
                sc.notifSettings?.setSmtpPort(port);
                sc.addLog('[NOTIF] SMTP port saved → $port');
              },
            ),
            const SizedBox(height: 8),
            _TextSetting(
              label: 'SMTP username (sender email)',
              value: _smtpUser,
              hint: 'sender@gmail.com',
              icon: Icons.person_outline_rounded,
              onSaved: (v) {
                if (v == _smtpUser) return;
                setState(() => _smtpUser = v);
                final sc = context.read<BleScannerService>();
                sc.notifSettings?.setSmtpUser(v);
                sc.addLog('[NOTIF] SMTP user saved → $v');
              },
            ),
            const SizedBox(height: 8),
            _TextSetting(
              label: 'SMTP password / App Password',
              value: _smtpPassword,
              hint: '••••••••••••',
              icon: Icons.lock_outline_rounded,
              obscure: true,
              onSaved: (v) {
                if (v == _smtpPassword) return;
                setState(() => _smtpPassword = v);
                final sc = context.read<BleScannerService>();
                sc.notifSettings?.setSmtpPassword(v);
                sc.addLog('[NOTIF] SMTP password saved (${v.length} chars)');
              },
            ),
          ],

          const SizedBox(height: 32),
          _SectionHeader('About'),
          _InfoCard(
            icon: Icons.info_outline_rounded,
            title: 'Chipolo POP color detection',
            subtitle:
                'Tag color cannot be read from BLE advertisement data.\n'
                'The FE65 payload encodes firmware version, flags, and a '
                'device ID — not color. Chipolo stores color server-side.\n'
                'Use the 🎨 button on each card to assign color manually.',
          ),
        ],
      ),
    );
  }

  String _rssiLabel(int rssi) {
    if (rssi >= -60) return '≈ 2–3 m';
    if (rssi >= -70) return '≈ 5–8 m';
    if (rssi >= -80) return '≈ 10–15 m';
    return '≈ >15 m';
  }

  Color _rssiColor(int rssi) {
    if (rssi >= -60) return const Color(0xFF4CAF50);
    if (rssi >= -75) return const Color(0xFFFFB300);
    return const Color(0xFFEF5350);
  }
}

// ── Scan interval picker ─────────────────────────────────────────────────────

class _IntervalPicker extends StatelessWidget {
  final int selected;
  final void Function(int) onChanged;
  const _IntervalPicker({required this.selected, required this.onChanged});

  static const _labels = {
    1: '1s\nRealtime',
    5: '5s\nFast',
    10: '10s\nDefault',
    20: '20s\nBalanced',
    60: '1m\nLow pwr',
    256: '256s\nMinimal',
  };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: scanIntervalOptions.map((v) {
        final active = v == selected;
        return GestureDetector(
          onTap: () => onChanged(v),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: active
                  ? const Color(0xFF00BCD4).withAlpha(40)
                  : cs.surfaceContainer,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: active
                    ? const Color(0xFF00BCD4)
                    : const Color(0xFF30363D),
                width: active ? 1.5 : 1,
              ),
            ),
            child: Text(
              _labels[v] ?? '${v}s',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: active ? const Color(0xFF00BCD4) : cs.onSurface.withAlpha(160),
                fontSize: 12,
                fontWeight: active ? FontWeight.w700 : FontWeight.normal,
                height: 1.4,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ── Shared helper widgets ────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 4),
        child: Text(title.toUpperCase(),
            style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2)),
      );
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  const _InfoCard(
      {required this.icon,
      required this.title,
      required this.subtitle,
      this.trailing});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: cs.primary, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14)),
                const SizedBox(height: 4),
                Text(subtitle,
                    style: TextStyle(
                        color: cs.onSurface.withAlpha(140), fontSize: 12)),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    );
  }
}

class _TileButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _TileButton(
      {required this.icon,
      required this.label,
      required this.color,
      required this.onTap});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: cs.surfaceContainer,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF30363D)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 12),
            Text(label,
                style:
                    TextStyle(color: color, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _TextSetting extends StatefulWidget {
  final String label;
  final String value;
  final String hint;
  final IconData icon;
  final bool obscure;
  final TextInputType keyboard;
  final void Function(String) onSaved;

  const _TextSetting({
    required this.label,
    required this.value,
    required this.hint,
    required this.icon,
    required this.onSaved,
    this.obscure = false,
    this.keyboard = TextInputType.text,
  });

  @override
  State<_TextSetting> createState() => _TextSettingState();
}

class _TextSettingState extends State<_TextSetting> {
  late TextEditingController _ctrl;
  late FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value);
    _focus = FocusNode()
      ..addListener(() {
        if (!_focus.hasFocus) {
          widget.onSaved(_ctrl.text);
        }
      });
  }

  @override
  void didUpdateWidget(_TextSetting old) {
    super.didUpdateWidget(old);
    // Only sync from outside if the field is not focused
    if (!_focus.hasFocus && old.value != widget.value) {
      _ctrl.text = widget.value;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Row(
        children: [
          Icon(widget.icon, color: cs.primary, size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _ctrl,
              focusNode: _focus,
              obscureText: widget.obscure,
              keyboardType: widget.keyboard,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                labelText: widget.label,
                hintText: widget.hint,
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              onSubmitted: widget.onSaved,
            ),
          ),
        ],
      ),
    );
  }
}
