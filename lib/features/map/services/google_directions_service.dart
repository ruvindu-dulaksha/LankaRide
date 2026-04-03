import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../../core/constants/app_constants.dart';

/// Route with live traffic data from Google Directions API
class TrafficRoute {
  final List<LatLng> polylinePoints;
  final double distanceMeters;
  final int durationSeconds; // Current traffic
  final int durationInTraffic; // With live traffic
  final String summary;
  final int speedKmh; // Average speed
  bool isGoodTraffic; // true if duration matches baseline

  TrafficRoute({
    required this.polylinePoints,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.durationInTraffic,
    required this.summary,
    required this.speedKmh,
    required this.isGoodTraffic,
  });

  /// Get route status emoji
  String get statusEmoji {
    if (isGoodTraffic) {
      return '🟢'; // Good traffic
    } else if (durationInTraffic > durationSeconds * 1.5) {
      return '🔴'; // Heavy traffic
    } else {
      return '🟡'; // Moderate traffic
    }
  }

  /// Get readable traffic status
  String get trafficStatus {
    final delayMinutes = ((durationInTraffic - durationSeconds) / 60).toInt();
    if (delayMinutes <= 0) {
      return 'Good traffic';
    } else if (delayMinutes > 10) {
      return '$delayMinutes min delay - Heavy traffic!';
    } else {
      return '$delayMinutes min delay';
    }
  }
}

/// Google Directions service - fetches routes from Flask backend
/// The backend handles Google Directions API calls securely with API key
class GoogleDirectionsService {
  /// Get route from origin to destination with live traffic data
  /// This calls the Flask backend's /directions endpoint which internally
  /// calls Google Directions API with live traffic data
  static Future<TrafficRoute?> getTrafficAwareRoute(
    LatLng origin,
    LatLng destination,
  ) async {
    try {
      // Call Flask backend's directions endpoint
      // The backend calls Google Directions API securely
      final response = await http
          .post(
            Uri.parse('${AppConstants.baseUrl}/directions'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'origin_lat': origin.latitude,
              'origin_lng': origin.longitude,
              'dest_lat': destination.latitude,
              'dest_lng': destination.longitude,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);

        // Parse response from backend
        final polylinePoints = _decodePolyline(json['polyline'] ?? '');
        final distanceMeters = (json['distance_m'] as num).toInt();
        final durationSeconds = (json['duration_sec'] as num).toInt();
        final durationInTraffic = (json['duration_traffic_sec'] as num).toInt();

        final speedKmh = distanceMeters > 0
            ? (distanceMeters / durationInTraffic * 3.6).toInt()
            : 0;

        // Good traffic if actual matches baseline (within 10%)
        final isGoodTraffic =
            durationInTraffic <= (durationSeconds * 1.1).toInt();

        return TrafficRoute(
          polylinePoints: polylinePoints,
          distanceMeters: distanceMeters.toDouble(),
          durationSeconds: durationSeconds,
          durationInTraffic: durationInTraffic,
          summary:
              '${(distanceMeters / 1000).toStringAsFixed(1)}km • '
              '${(durationInTraffic / 60).toStringAsFixed(0)}m',
          speedKmh: speedKmh,
          isGoodTraffic: isGoodTraffic,
        );
      } else {
        print('❌ Directions endpoint error: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('❌ Directions service error: $e');
      return null;
    }
  }

  /// Decode Google polyline (algorithm from Maps API)
  static List<LatLng> _decodePolyline(String polyline) {
    List<LatLng> points = [];
    int index = 0, lat = 0, lng = 0;

    while (index < polyline.length) {
      int result = 0;
      int shift = 0;
      int byte;

      do {
        byte = polyline.codeUnitAt(index++) - 63;
        result |= (byte & 0x1f) << shift;
        shift += 5;
      } while (byte >= 0x20);

      int dlat = (result & 1) == 1 ? ~(result >> 1) : result >> 1;
      lat += dlat;

      result = 0;
      shift = 0;
      do {
        byte = polyline.codeUnitAt(index++) - 63;
        result |= (byte & 0x1f) << shift;
        shift += 5;
      } while (byte >= 0x20);

      int dlng = (result & 1) == 1 ? ~(result >> 1) : result >> 1;
      lng += dlng;

      points.add(LatLng(lat / 1e5, lng / 1e5));
    }

    return points;
  }
}
