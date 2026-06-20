import 'package:shared_preferences/shared_preferences.dart';

class NotificationSettingsService {
  static const _keyEmail = 'notify_email';
  static const _keySmtpHost = 'smtp_host';
  static const _keySmtpPort = 'smtp_port';
  static const _keySmtpUser = 'smtp_user';
  static const _keySmtpPassword = 'smtp_password';
  static const _keyEnabled = 'notify_enabled';

  static const defaultEmail = 'stasgold@gmail.com';
  static const defaultSmtpHost = 'smtp.gmail.com';
  static const defaultSmtpPort = 587;

  final SharedPreferences _prefs;

  NotificationSettingsService._(this._prefs);

  static Future<NotificationSettingsService> load() async {
    final prefs = await SharedPreferences.getInstance();
    return NotificationSettingsService._(prefs);
  }

  bool get enabled => _prefs.getBool(_keyEnabled) ?? false;
  String get notifyEmail => _prefs.getString(_keyEmail) ?? defaultEmail;
  String get smtpHost => _prefs.getString(_keySmtpHost) ?? defaultSmtpHost;
  int get smtpPort => _prefs.getInt(_keySmtpPort) ?? defaultSmtpPort;
  String get smtpUser => _prefs.getString(_keySmtpUser) ?? '';
  String get smtpPassword => _prefs.getString(_keySmtpPassword) ?? '';

  Future<void> setEnabled(bool v) => _prefs.setBool(_keyEnabled, v);
  Future<void> setNotifyEmail(String v) => _prefs.setString(_keyEmail, v);
  Future<void> setSmtpHost(String v) => _prefs.setString(_keySmtpHost, v);
  Future<void> setSmtpPort(int v) => _prefs.setInt(_keySmtpPort, v);
  Future<void> setSmtpUser(String v) => _prefs.setString(_keySmtpUser, v);
  Future<void> setSmtpPassword(String v) =>
      _prefs.setString(_keySmtpPassword, v);
}
