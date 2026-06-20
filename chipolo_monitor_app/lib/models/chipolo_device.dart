import 'package:flutter/material.dart';

enum PresenceStatus { present, gone }

// ── Chipolo POP available colors (physical product colors) ──────────────────
// Color cannot be read from BLE advertisement packets — the firmware does not
// encode it. Chipolo's own app stores color preference server-side / locally
// indexed by device address. We provide manual assignment instead.
const chipoloTagColors = [
  (label: 'Red',    color: Color(0xFFE53935)),
  (label: 'Black',  color: Color(0xFF424242)),
  (label: 'White',  color: Color(0xFFEEEEEE)),
  (label: 'Yellow', color: Color(0xFFFFD600)),
  (label: 'Green',  color: Color(0xFF43A047)),
  (label: 'Blue',   color: Color(0xFF1E88E5)),
  (label: 'Orange', color: Color(0xFFFF6D00)),
  (label: 'Pink',   color: Color(0xFFEC407A)),
];

class ChipoloDevice {
  final String address;

  /// Detected name from BLE advertisement
  String name;

  /// User-assigned custom name (overrides [name] in UI)
  String? customName;

  /// Index into [chipoloTagColors]; null = unassigned
  int? colorIndex;

  final DateTime firstSeen;
  DateTime lastSeen;
  int lastRssi;
  int packetCount;
  PresenceStatus status;
  DateTime? goneAt;
  List<int> rssiHistory;
  Map<String, String> _fe65Info = {};

  ChipoloDevice({
    required this.address,
    required this.name,
    required this.firstSeen,
    required this.lastRssi,
  })  : lastSeen = firstSeen,
        packetCount = 1,
        status = PresenceStatus.present,
        rssiHistory = [lastRssi];

  // ── Display helpers ───────────────────────────────────────────────────────

  /// Returns the user-assigned name if set, otherwise the BLE-detected name.
  String get displayName => customName?.isNotEmpty == true ? customName! : name;

  Color? get tagColor =>
      colorIndex != null ? chipoloTagColors[colorIndex!].color : null;

  String? get tagColorLabel =>
      colorIndex != null ? chipoloTagColors[colorIndex!].label : null;

  // ── BLE update ────────────────────────────────────────────────────────────

  void update(int rssi, String newName) {
    lastSeen = DateTime.now();
    lastRssi = rssi;
    packetCount++;
    status = PresenceStatus.present;
    goneAt = null;
    // Only update the detected name if it looks valid and user hasn't renamed
    if (newName.isNotEmpty && !newName.startsWith(address.substring(0, 4))) {
      name = newName;
    }
    rssiHistory.add(rssi);
    if (rssiHistory.length > 40) rssiHistory.removeAt(0);
  }

  void markGone() {
    goneAt ??= DateTime.now();
    status = PresenceStatus.gone;
  }

  bool get isPresent => status == PresenceStatus.present;

  Duration get goneDuration =>
      goneAt != null ? DateTime.now().difference(goneAt!) : Duration.zero;

  Duration get trackedDuration => DateTime.now().difference(firstSeen);

  int get signalBars {
    if (lastRssi >= -50) return 5;
    if (lastRssi >= -60) return 4;
    if (lastRssi >= -70) return 3;
    if (lastRssi >= -80) return 2;
    if (lastRssi >= -90) return 1;
    return 0;
  }

  double get signalStrength =>
      ((lastRssi.clamp(-100, -40) + 100) / 60).clamp(0.0, 1.0);

  Map<String, String> get fe65Info => Map.unmodifiable(_fe65Info);
  void setFe65Info(Map<String, String> info) => _fe65Info = info;

  String get shortAddress {
    if (address.length > 17) return address.split('-').last.toUpperCase();
    return address.toUpperCase();
  }

  // ── Persistence ───────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
        'address': address,
        'name': name,
        'customName': customName,
        'colorIndex': colorIndex,
        'firstSeen': firstSeen.toIso8601String(),
        'lastSeen': lastSeen.toIso8601String(),
        'lastRssi': lastRssi,
        'packetCount': packetCount,
      };

  factory ChipoloDevice.fromJson(Map<String, dynamic> j) {
    final d = ChipoloDevice(
      address: j['address'] as String,
      name: j['name'] as String,
      firstSeen: DateTime.parse(j['firstSeen'] as String),
      lastRssi: (j['lastRssi'] as num).toInt(),
    );
    d.customName = j['customName'] as String?;
    d.colorIndex = j['colorIndex'] as int?;
    d.lastSeen = DateTime.parse(j['lastSeen'] as String);
    d.packetCount = (j['packetCount'] as num?)?.toInt() ?? 1;
    d.markGone(); // restored devices start as gone until seen again
    return d;
  }
}
