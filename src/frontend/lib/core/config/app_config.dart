/// Environment / base URL configuration for API calls.
///
/// Switch [apiBaseUrl] to match how you run the app:
/// - [androidEmulatorBaseUrl] — Android emulator → host machine
/// - [localhostBaseUrl] — Windows / macOS / Linux desktop, Chrome
/// - [lanBaseUrl] — Physical phone on same Wi‑Fi (use your PC’s IP)
class AppConfig {
  AppConfig._();

  static const String androidEmulatorBaseUrl = 'http://10.0.2.2:8000';
  static const String localhostBaseUrl = 'http://127.0.0.1:8000';

  /// Example LAN host; replace with your machine’s IP if needed.
  static const String lanBaseUrl = 'http://192.168.1.4:8000';
  //'http://10.229.17.34:8000'; //'http://192.168.1.3:8000';

  /// Active base URL (no trailing slash).
  static const String apiBaseUrl = lanBaseUrl;
}
