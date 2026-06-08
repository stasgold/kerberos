import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/chipolo_device.dart';

class DeviceStorageService {
  static const _fileName = 'kerberos_devices.json';

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  static Future<Map<String, ChipoloDevice>> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return {};
      final raw = await f.readAsString();
      final list = jsonDecode(raw) as List<dynamic>;
      return {
        for (final j in list)
          (j['address'] as String): ChipoloDevice.fromJson(
              j as Map<String, dynamic>)
      };
    } catch (_) {
      return {};
    }
  }

  static Future<void> save(Map<String, ChipoloDevice> devices) async {
    try {
      final f = await _file();
      final list = devices.values.map((d) => d.toJson()).toList();
      await f.writeAsString(jsonEncode(list));
    } catch (_) {}
  }

  static Future<void> remove(String address) async {
    try {
      final f = await _file();
      if (!await f.exists()) return;
      final raw = await f.readAsString();
      final list = (jsonDecode(raw) as List<dynamic>)
          .where((j) => (j as Map)['address'] != address)
          .toList();
      await f.writeAsString(jsonEncode(list));
    } catch (_) {}
  }
}
