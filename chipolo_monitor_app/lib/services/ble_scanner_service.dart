import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import '../models/chipolo_device.dart';
import 'device_storage_service.dart';
import 'notification_settings_service.dart';

const _chipoloUuids = {
  '0000fe65-0000-1000-8000-00805f9b34fb',
  '0000fe2c-0000-1000-8000-00805f9b34fb',
  '0000fee0-0000-1000-8000-00805f9b34fb',
  '0000fee1-0000-1000-8000-00805f9b34fb',
};

/// Valid scan-restart intervals (seconds).
const scanIntervalOptions = [1, 5, 10, 20, 60, 256];

class BleScannerService extends ChangeNotifier {
  final Map<String, ChipoloDevice> _devices = {};
  final double timeoutSec;
  bool _loaded = false;

  // BT adapter state
  BluetoothAdapterState _btState = BluetoothAdapterState.unknown;
  StreamSubscription<BluetoothAdapterState>? _btStateSub;

  // Email: track which devices have had notification sent (address → sentAt)
  final Map<String, DateTime> _emailSentAt = {};
  NotificationSettingsService? _notifSettings;

  BleScannerService({this.timeoutSec = 8.0}) {
    _init();
  }

  Future<void> _init() async {
    _notifSettings = await NotificationSettingsService.load();

    // Monitor BT adapter state
    _btStateSub = FlutterBluePlus.adapterState.listen((state) {
      _btState = state;
      _log('[BT] adapter state → $state');
      notifyListeners();
    });

    await _loadSaved();
  }

  Future<void> _loadSaved() async {
    final saved = await DeviceStorageService.load();
    if (saved.isNotEmpty) {
      _devices.addAll(saved);
      _log('📂 Loaded ${saved.length} remembered device(s)');
    }
    _loaded = true;
    notifyListeners();
  }

  bool _scanning = false;
  int? _rssiThreshold;
  int _scanIntervalSec = 10; // BLE scan restarts every N seconds

  StreamSubscription<List<ScanResult>>? _scanSub;
  Timer? _timeoutTimer;
  Timer? _scanRestartTimer;
  int _totalPackets = 0;
  final List<String> _eventLog = [];
  static const _maxLogLines = 200;

  // ── Getters ───────────────────────────────────────────────────────────────

  bool get isLoaded => _loaded;
  bool get isScanning => _scanning;
  int get totalPackets => _totalPackets;
  int? get rssiThreshold => _rssiThreshold;
  int get scanIntervalSec => _scanIntervalSec;
  List<String> get eventLog => List.unmodifiable(_eventLog);
  BluetoothAdapterState get btAdapterState => _btState;
  bool get isBluetoothOn => _btState == BluetoothAdapterState.on;
  NotificationSettingsService? get notifSettings => _notifSettings;

  List<ChipoloDevice> get allDevices {
    final list = _devices.values.toList();
    list.sort((a, b) {
      if (a.isPresent != b.isPresent) return a.isPresent ? -1 : 1;
      return b.lastRssi.compareTo(a.lastRssi);
    });
    return list;
  }

  List<ChipoloDevice> get presentDevices =>
      allDevices.where((d) => d.isPresent).toList();
  List<ChipoloDevice> get goneDevices =>
      allDevices.where((d) => !d.isPresent).toList();

  // ── Scan control ──────────────────────────────────────────────────────────

  Future<void> startScan({int? rssiThreshold}) async {
    if (_scanning) return;
    _rssiThreshold = rssiThreshold;

    await _startBleScan();

    // Subscribe once — survives stop/restart cycles
    _scanSub = FlutterBluePlus.onScanResults.listen(_onScanResult);

    // Presence timeout checker (runs every 500 ms)
    _timeoutTimer = Timer.periodic(
        const Duration(milliseconds: 500), _checkTimeouts);

    // Scan restart timer — refreshes BLE scan every [scanIntervalSec]
    _scanRestartTimer = Timer.periodic(
      Duration(seconds: _scanIntervalSec),
      (_) async {
        if (!_scanning) return;
        await FlutterBluePlus.stopScan();
        await Future.delayed(const Duration(milliseconds: 100));
        await _startBleScan();
      },
    );

    _scanning = true;
    _log('▶ Scan started  timeout=${timeoutSec}s  interval=${_scanIntervalSec}s'
        '${rssiThreshold != null ? "  RSSI≥${rssiThreshold}dBm" : ""}');
    notifyListeners();
  }

  Future<void> stopScan() async {
    _scanSub?.cancel();
    _timeoutTimer?.cancel();
    _scanRestartTimer?.cancel();
    _scanSub = null;
    _timeoutTimer = null;
    _scanRestartTimer = null;
    await FlutterBluePlus.stopScan();
    _scanning = false;
    _log('■ Scan stopped  packets=$_totalPackets');
    notifyListeners();
  }

  Future<void> _startBleScan() async {
    await FlutterBluePlus.startScan(
      continuousUpdates: true,
      removeIfGone: Duration(seconds: timeoutSec.round() * 3),
    );
  }

  // ── Settings setters ─────────────────────────────────────────────────────

  void setRssiThreshold(int? value) {
    _rssiThreshold = value;
    notifyListeners();
  }

  /// Change scan restart interval. Takes effect on the next restart cycle.
  /// If scanning, restarts immediately with new interval.
  Future<void> setScanInterval(int seconds) async {
    if (!scanIntervalOptions.contains(seconds)) return;
    _scanIntervalSec = seconds;
    if (_scanning) {
      _scanRestartTimer?.cancel();
      _scanRestartTimer = Timer.periodic(
        Duration(seconds: _scanIntervalSec),
        (_) async {
          if (!_scanning) return;
          await FlutterBluePlus.stopScan();
          await Future.delayed(const Duration(milliseconds: 100));
          await _startBleScan();
        },
      );
      _log('⚙ Scan interval changed to ${seconds}s');
    }
    notifyListeners();
  }

  // ── Device metadata ───────────────────────────────────────────────────────

  void setDeviceName(String address, String? customName) {
    if (!_devices.containsKey(address)) return;
    _devices[address]!.customName =
        (customName?.trim().isEmpty ?? true) ? null : customName!.trim();
    _log('✏ Renamed "${_devices[address]!.name}" → '
        '"${_devices[address]!.displayName}"');
    DeviceStorageService.save(_devices);
    notifyListeners();
  }

  void setDeviceColor(String address, int? colorIndex) {
    if (!_devices.containsKey(address)) return;
    _devices[address]!.colorIndex = colorIndex;
    final label = colorIndex != null
        ? chipoloTagColors[colorIndex].label
        : 'unset';
    _log('🎨 Color "${_devices[address]!.displayName}" → $label');
    DeviceStorageService.save(_devices);
    notifyListeners();
  }

  // ── Device list management ────────────────────────────────────────────────

  void clearGoneDevices() {
    _devices.removeWhere((_, d) => d.status == PresenceStatus.gone);
    _log('🗑 Cleared gone devices');
    DeviceStorageService.save(_devices);
    notifyListeners();
  }

  void clearAll() {
    _devices.clear();
    _totalPackets = 0;
    DeviceStorageService.save(_devices);
    notifyListeners();
  }

  void removeDevice(String address) {
    _devices.remove(address);
    _emailSentAt.remove(address);
    DeviceStorageService.remove(address);
    _log('🗑 Removed device $address');
    notifyListeners();
  }

  // ── Internal ─────────────────────────────────────────────────────────────

  void _onScanResult(List<ScanResult> results) {
    bool changed = false;
    for (final r in results) {
      if (!_isChipolo(r)) continue;
      final rssi = r.rssi;
      if (_rssiThreshold != null && rssi < _rssiThreshold!) continue;
      _totalPackets++;
      final addr = r.device.remoteId.str;
      final advName = r.advertisementData.advName;
      final platName = r.device.platformName;
      final name = advName.isNotEmpty
          ? advName
          : platName.isNotEmpty
              ? platName
              : addr.substring(0, 8);

      if (!_devices.containsKey(addr)) {
        _devices[addr] = ChipoloDevice(
            address: addr, name: name, firstSeen: DateTime.now(), lastRssi: rssi);
        _log('+ NEW  "$name"  RSSI=${rssi}dBm');
        DeviceStorageService.save(_devices);
      } else {
        final wasGone = !_devices[addr]!.isPresent;
        _devices[addr]!.update(rssi, name);
        if (wasGone) {
          _emailSentAt.remove(addr); // reset so we can notify again if it goes missing
          _log('✓ BACK "${_devices[addr]!.displayName}"  RSSI=${rssi}dBm');
          DeviceStorageService.save(_devices);
        }
      }

      for (final entry in r.advertisementData.serviceData.entries) {
        if (entry.key.toString().toLowerCase().contains('fe65')) {
          _devices[addr]!.setFe65Info(_parseFe65(entry.value));
        }
      }
      changed = true;
    }
    if (changed) notifyListeners();
  }

  void _checkTimeouts(Timer _) {
    final now = DateTime.now();
    bool changed = false;
    for (final d in _devices.values) {
      if (d.isPresent &&
          now.difference(d.lastSeen).inMilliseconds > timeoutSec * 1000) {
        d.markGone();
        _log('✗ GONE "${d.displayName}"  last RSSI=${d.lastRssi}dBm');
        changed = true;
      }
      // Email alert after 1 minute of being gone
      if (!d.isPresent &&
          d.goneAt != null &&
          now.difference(d.goneAt!).inSeconds >= 60 &&
          !_emailSentAt.containsKey(d.address)) {
        _emailSentAt[d.address] = now;
        _sendGoneEmail(d);
      }
    }
    if (changed) notifyListeners();
  }

  Future<void> _sendGoneEmail(ChipoloDevice device) async {
    final settings = _notifSettings;
    if (settings == null || !settings.enabled) {
      _log('✉ [DEBUG] Email skipped — enabled=${settings?.enabled}');
      return;
    }
    _log('✉ [DEBUG] Attempting email for "${device.displayName}"'
        '  to=${settings.notifyEmail}'
        '  smtp=${settings.smtpHost}:${settings.smtpPort}'
        '  user=${settings.smtpUser.isEmpty ? "<empty>" : settings.smtpUser}'
        '  pass=${settings.smtpPassword.isEmpty ? "<empty>" : "***"}');
    if (settings.smtpUser.isEmpty || settings.smtpPassword.isEmpty) {
      _log('✉ Email skipped — SMTP credentials not configured');
      return;
    }
    try {
      final smtpServer = SmtpServer(
        settings.smtpHost,
        port: settings.smtpPort,
        username: settings.smtpUser,
        password: settings.smtpPassword,
        ssl: false,
        allowInsecure: settings.smtpPort == 465 ? false : true,
      );
      final message = Message()
        ..from = Address(settings.smtpUser, 'Kerberos Monitor')
        ..recipients.add(settings.notifyEmail)
        ..subject = '⚠ Device gone: ${device.displayName}'
        ..text = 'Kerberos Monitor Alert\n\n'
            'Device "${device.displayName}" (${device.shortAddress}) has been '
            'out of range for 1 minute.\n\n'
            'Last seen: ${device.lastSeen}\n'
            'Last RSSI: ${device.lastRssi} dBm\n';
      await send(message, smtpServer);
      _log('✉ Alert sent for "${device.displayName}" → ${settings.notifyEmail}');
    } catch (e) {
      _log('✉ Email failed: $e');
    }
  }

  /// Expose logging so UI layers can write debug entries.
  void addLog(String msg) => _log(msg);

  void _log(String msg) {
    final now = DateTime.now();
    final ts =
        '${now.hour.toString().padLeft(2, "0")}:${now.minute.toString().padLeft(2, "0")}:${now.second.toString().padLeft(2, "0")}';
    _eventLog.insert(0, '[$ts] $msg');
    if (_eventLog.length > _maxLogLines) _eventLog.removeLast();
  }

  static bool _isChipolo(ScanResult r) {
    final name =
        '${r.advertisementData.advName}${r.device.platformName}'.toLowerCase();
    if (name.contains('chipolo')) return true;
    final uuids = r.advertisementData.serviceUuids
        .map((g) => g.toString().toLowerCase())
        .toSet();
    if (uuids.intersection(_chipoloUuids).isNotEmpty) return true;
    final svcKeys = r.advertisementData.serviceData.keys
        .map((g) => g.toString().toLowerCase())
        .toSet();
    return svcKeys.intersection(_chipoloUuids).isNotEmpty;
  }

  static Map<String, String> _parseFe65(List<int> data) {
    if (data.length < 4) return {};
    final flags = data[3];
    final result = <String, String>{
      'firmware': '${data[1]}.${data[2]}',
      'button': (flags & 0x01) != 0 ? 'PRESSED' : 'no',
      'lost_mode': (flags & 0x02) != 0 ? 'ON' : 'off',
    };
    if (data.length >= 10) {
      result['device_id'] = data
          .sublist(4, 10)
          .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
          .join(':');
    }
    return result;
  }

  @override
  void dispose() {
    _btStateSub?.cancel();
    stopScan();
    super.dispose();
  }
}
