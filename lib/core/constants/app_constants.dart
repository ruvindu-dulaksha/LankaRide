import 'dart:io';

class AppConstants {
  // API Configuration - Auto-detect environment
  static String get baseUrl {
    if (Platform.isAndroid) {
      return 'http://10.0.2.2:5001'; // Android Emulator
    } else if (Platform.isIOS) {
      return 'http://localhost:5001'; // iOS Simulator
    } else {
      return 'http://localhost:5001'; // macOS/Web
    }
  }

  static const String predictEndpoint = '/predict';

  // Map Configuration
  static const double defaultLat = 6.9271;
  static const double defaultLng = 79.8612;
  static const double defaultZoom = 15.0;
  static const double zoneRadius = 500.0; // meters

  // SharedPreferences Keys
  static const String userIdKey = 'user_id';
  static const String hasSeenOnboardingKey = 'has_seen_onboarding';

  // Default Values (from real sensors/weather, not demo)
  static const double defaultRainLevel = 0.0; // No rain by default
  static const double defaultUnionDensity = 0.0; // No vehicles by default

  // Risk Zones
  static const String redZone = 'red';
  static const String yellowZone = 'yellow';
  static const String greenZone = 'green';
}
