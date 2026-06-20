import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../services/ble_scanner_service.dart';
import '../widgets/device_card.dart';
import '../widgets/stats_bar.dart';
import '../widgets/event_log_sheet.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;
  bool _permissionsGranted = false;
  bool _permPermanentlyDenied = false;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnim = Tween(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    if (!Platform.isAndroid) {
      if (mounted) setState(() => _permissionsGranted = true);
      return;
    }

    // Android 12+ uses BLUETOOTH_SCAN + BLUETOOTH_CONNECT.
    // permission_handler maps these correctly across SDK versions.
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();

    final granted = statuses.values.every((s) => s.isGranted);
    final permanent = statuses.values.any((s) => s.isPermanentlyDenied);

    if (mounted) {
      setState(() {
        _permissionsGranted = granted;
        _permPermanentlyDenied = permanent;
      });

      // ── Debug: log every permission status into the event log ──────────
      final scanner = context.read<BleScannerService>();
      statuses.forEach((perm, status) {
        scanner.addLog('[PERM] ${perm.toString().split('.').last}: $status');
      });
      scanner.addLog(
          '[PERM] result → granted=$granted permanentlyDenied=$permanent'
          ' → button ${granted ? "ENABLED" : "DISABLED"}');
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scanner = context.watch<BleScannerService>();
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      body: CustomScrollView(
        slivers: [
          // ── App Bar ────────────────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 120,
            pinned: true,
            backgroundColor: cs.surface,
            surfaceTintColor: Colors.transparent,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              title: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Animated radar icon
                  AnimatedBuilder(
                    animation: _pulseAnim,
                    builder: (_, __) => Transform.scale(
                      scale: scanner.isScanning ? _pulseAnim.value : 1.0,
                      child: Icon(
                        Icons.radar,
                        color: scanner.isScanning
                            ? const Color(0xFF00BCD4)
                            : cs.onSurface.withAlpha(100),
                        size: 28,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Kerberos',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              background: _AppBarBackground(isScanning: scanner.isScanning),
            ),
            actions: [
              // Log button
              IconButton(
                icon: const Icon(Icons.terminal_rounded),
                tooltip: 'Event log',
                onPressed: () => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => const EventLogSheet(),
                ),
              ),
              // Settings
              IconButton(
                icon: const Icon(Icons.tune_rounded),
                tooltip: 'Settings',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                ),
              ),
            ],
          ),

          // ── Bluetooth disabled banner ─────────────────────────────────────
          if (!scanner.isBluetoothOn)
            SliverToBoxAdapter(
              child: _BluetoothOffBanner(
                state: scanner.btAdapterState,
              ),
            ),

          // ── Permission banner ───────────────────────────────────────
          if (!_permissionsGranted)
            SliverToBoxAdapter(
              child: _PermissionBanner(
                permanentlyDenied: _permPermanentlyDenied,
                onRequestAgain: _requestPermissions,
              ),
            ),

          // ── Stats bar ──────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: StatsBar(scanner: scanner),
            ),
          ),

          // ── Device list ────────────────────────────────────────────────
          if (scanner.allDevices.isEmpty)
            SliverFillRemaining(
              child: _EmptyState(
                isScanning: scanner.isScanning,
                permissionsGranted: _permissionsGranted,
              ),
            )

          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
              sliver: SliverList.builder(
                itemCount: scanner.allDevices.length,
                itemBuilder: (ctx, i) {
                  final device = scanner.allDevices[i];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: DeviceCard(device: device),
                  );
                },
              ),
            ),
        ],
      ),

      // ── FAB ─────────────────────────────────────────────────────────────
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: _ScanFab(
        isScanning: scanner.isScanning,
        enabled: _permissionsGranted,
        onTap: () async {
          if (scanner.isScanning) {
            await scanner.stopScan();
          } else {
            await scanner.startScan(rssiThreshold: scanner.rssiThreshold);
          }
        },
      ),
    );
  }
}

// ── App bar animated background ─────────────────────────────────────────────

class _AppBarBackground extends StatelessWidget {
  final bool isScanning;
  const _AppBarBackground({required this.isScanning});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _RadarPainter(isScanning: isScanning),
    );
  }
}

class _RadarPainter extends CustomPainter {
  final bool isScanning;
  _RadarPainter({required this.isScanning});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.85, size.height * 0.5);
    final paint = Paint()
      ..color = isScanning
          ? const Color(0xFF00BCD4).withAlpha(18)
          : Colors.white.withAlpha(8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (int i = 1; i <= 4; i++) {
      canvas.drawCircle(center, i * 28.0, paint);
    }
  }

  @override
  bool shouldRepaint(_RadarPainter old) => old.isScanning != isScanning;
}

// ── Scan FAB ────────────────────────────────────────────────────────────────

class _ScanFab extends StatelessWidget {
  final bool isScanning;
  final bool enabled;
  final VoidCallback onTap;
  const _ScanFab(
      {required this.isScanning, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final Color bg = isScanning
        ? const Color(0xFFEF5350)
        : const Color(0xFF00BCD4);

    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        height: 56,
        constraints: const BoxConstraints(minWidth: 160, maxWidth: 220),
        decoration: BoxDecoration(
          color: enabled ? bg : Colors.grey.shade800,
          borderRadius: BorderRadius.circular(28),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: bg.withAlpha(100),
                    blurRadius: 16,
                    spreadRadius: 2,
                  )
                ]
              : [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isScanning ? Icons.stop_rounded : Icons.bluetooth_searching,
              color: Colors.white,
              size: 22,
            ),
            const SizedBox(width: 8),
            Text(
              isScanning ? 'Stop Scan' : 'Start Scan',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 15,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Bluetooth off banner ───────────────────────────────────────────────────

class _BluetoothOffBanner extends StatelessWidget {
  final BluetoothAdapterState state;
  const _BluetoothOffBanner({required this.state});

  @override
  Widget build(BuildContext context) {
    final msg = state == BluetoothAdapterState.off
        ? 'Bluetooth is turned off. Enable it in device settings to scan.'
        : 'Bluetooth is not available (state: $state).';
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF001F3D),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF00BCD4).withAlpha(180)),
      ),
      child: Row(
        children: [
          const Icon(Icons.bluetooth_disabled,
              color: Color(0xFF00BCD4), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              msg,
              style: const TextStyle(
                  color: Color(0xFFB2EBF2), fontSize: 13, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Permission banner ──────────────────────────────────────────────────────

class _PermissionBanner extends StatelessWidget {
  final bool permanentlyDenied;
  final VoidCallback onRequestAgain;
  const _PermissionBanner(
      {required this.permanentlyDenied, required this.onRequestAgain});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF3D1A00),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFF6D00).withAlpha(180)),
      ),
      child: Row(
        children: [
          const Icon(Icons.bluetooth_disabled,
              color: Color(0xFFFF6D00), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              permanentlyDenied
                  ? 'Bluetooth permission permanently denied. Open app settings to grant it.'
                  : 'Bluetooth permission is required to scan for nearby devices.',
              style: const TextStyle(
                  color: Color(0xFFFFCC80), fontSize: 13, height: 1.4),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: permanentlyDenied ? openAppSettings : onRequestAgain,
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFFF6D00),
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              permanentlyDenied ? 'Settings' : 'Grant',
              style: const TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Empty state ─────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final bool isScanning;
  final bool permissionsGranted;
  const _EmptyState(
      {required this.isScanning, required this.permissionsGranted});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            permissionsGranted
                ? Icons.bluetooth_searching
                : Icons.bluetooth_disabled,
            size: 64,
            color: cs.onSurface.withAlpha(60),
          ),
          const SizedBox(height: 16),
          Text(
            isScanning ? 'Scanning for Chipolo tags…' : 'No devices found',
            style: TextStyle(
              color: cs.onSurface.withAlpha(140),
              fontSize: 16,
            ),
          ),
          if (!isScanning) ...[
            const SizedBox(height: 8),
            Text(
              'Press Start Scan to begin',
              style: TextStyle(
                color: cs.onSurface.withAlpha(80),
                fontSize: 13,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
