import 'dart:math' as math;
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Represents a hotspot location with demand intensity
class Hotspot {
  final LatLng location;
  final String type; // 'high_demand', 'traffic', 'accident', 'weather'
  final double intensity; // 0.0 - 1.0
  final String label;
  final int driverCount; // Number of drivers in this hotspot

  Hotspot({
    required this.location,
    required this.type,
    required this.intensity,
    required this.label,
    required this.driverCount,
  });

  /// Get color based on hotspot type and intensity
  int getColor() {
    switch (type) {
      case 'high_demand':
        return _getIntensityColor(intensity, const [
          0xFF4CAF50, // Green (low)
          0xFFFFC107, // Yellow (medium)
          0xFFFF5722, // Orange (high)
        ]);
      case 'traffic':
        return _getIntensityColor(intensity, const [
          0xFF81C784, // Light green
          0xFFFFB74D, // Light orange
          0xFFE57373, // Light red
        ]);
      case 'accident':
        return 0xFFD32F2F; // Red
      case 'weather':
        return _getIntensityColor(intensity, const [
          0xFF4FC3F7, // Light blue
          0xFF29B6F6, // Blue
          0xFF0277BD, // Dark blue
        ]);
      default:
        return 0xFF2196F3; // Blue
    }
  }

  /// Get color based on intensity from a gradient
  static int _getIntensityColor(double intensity, List<int> colors) {
    if (intensity <= 0.5) {
      // Blend between first and second color
      return colors[0];
    } else if (intensity <= 0.75) {
      // Blend between second and third color
      return colors[1];
    } else {
      return colors[2];
    }
  }

  /// Get marker icon opacity based on intensity
  double get opacity => 0.5 + (intensity * 0.5); // 0.5 - 1.0

  /// Get marker size based on intensity and driver count
  double get size => 20 + (intensity * 30) + (math.min(driverCount, 5) * 5);
}

/// Service for analyzing and generating hotspots
class HotspotService {
  /// Analyze hotspots from route segments
  static List<Hotspot> analyzeRouteHotspots(
    List<Map<String, dynamic>> segments,
  ) {
    final hotspots = <Hotspot>[];

    for (int i = 0; i < segments.length; i++) {
      final segment = segments[i];
      final demandScore =
          (segment['metrics']?['demand_score'] ?? 0.0) as double;
      final trafficDuration =
          (segment['metrics']?['traffic_duration_sec'] ?? 0) as int;
      final rainfall = (segment['metrics']?['rainfall_mm'] ?? 0.0) as double;
      final zone = segment['zone'] ?? 'GREEN';
      final coordinates = segment['coordinates'] as Map<String, dynamic>?;

      if (coordinates != null) {
        final lat = coordinates['lat'] as double?;
        final lng = coordinates['lng'] as double?;

        if (lat != null && lng != null) {
          // High demand hotspot
          if (demandScore > 70) {
            hotspots.add(
              Hotspot(
                location: LatLng(lat, lng),
                type: 'high_demand',
                intensity: math.min(demandScore / 100.0, 1.0),
                label: 'High Demand - Seg ${i + 1}',
                driverCount: (demandScore / 20).toInt(),
              ),
            );
          }

          // Traffic hotspot
          if (trafficDuration > 120) {
            hotspots.add(
              Hotspot(
                location: LatLng(lat + 0.001, lng + 0.001),
                type: 'traffic',
                intensity: math.min(trafficDuration / 300.0, 1.0),
                label: 'Heavy Traffic - Seg ${i + 1}',
                driverCount: 0,
              ),
            );
          }

          // Weather hotspot
          if (rainfall > 20) {
            hotspots.add(
              Hotspot(
                location: LatLng(lat - 0.001, lng - 0.001),
                type: 'weather',
                intensity: math.min(rainfall / 100.0, 1.0),
                label: 'Heavy Rain - Seg ${i + 1}',
                driverCount: 0,
              ),
            );
          }
        }
      }
    }

    return hotspots;
  }

  /// Analyze hotspots from driver locations
  static List<Hotspot> analyzeDriverHotspots(
    List<Map<String, dynamic>> drivers,
    LatLng userLocation,
  ) {
    final hotspots = <Hotspot>[];

    // Group nearby drivers
    final driverGroups = <String, List<Map<String, dynamic>>>{};

    for (final driver in drivers) {
      final lat = driver['latitude'] as double?;
      final lng = driver['longitude'] as double?;
      final driverId = driver['id'] as String?;

      if (lat != null && lng != null && driverId != null) {
        final cellKey = '${(lat * 1000).toInt()}_${(lng * 1000).toInt()}';
        driverGroups.putIfAbsent(cellKey, () => []).add(driver);
      }
    }

    // Create hotspots for driver groups
    driverGroups.forEach((cellKey, groupDrivers) {
      if (groupDrivers.isNotEmpty) {
        final firstDriver = groupDrivers.first;
        final lat = firstDriver['latitude'] as double;
        final lng = firstDriver['longitude'] as double;
        final count = groupDrivers.length;

        // Intensity based on driver concentration
        final intensity = math.min((count / 10.0), 1.0);

        hotspots.add(
          Hotspot(
            location: LatLng(lat, lng),
            type: 'high_demand',
            intensity: intensity,
            label: '$count drivers online',
            driverCount: count,
          ),
        );
      }
    });

    return hotspots;
  }

  /// Get route hotspots for nearby roads
  static List<Hotspot> getRouteHotspots(
    List<Map<String, dynamic>> nearbyRoutes,
    LatLng centerLocation,
  ) {
    final hotspots = <Hotspot>[];

    for (final route in nearbyRoutes) {
      final segments = route['segments'] as List<dynamic>?;
      if (segments != null) {
        final segmentList = segments.cast<Map<String, dynamic>>();
        final routeHotspots = analyzeRouteHotspots(segmentList);
        hotspots.addAll(routeHotspots);
      }
    }

    return hotspots;
  }

  /// Calculate distance between two locations in meters
  static double calculateDistance(LatLng from, LatLng to) {
    const earthRadius = 6371000; // Earth radius in meters
    final dLat = _toRadian(to.latitude - from.latitude);
    final dLng = _toRadian(to.longitude - from.longitude);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadian(from.latitude)) *
            math.cos(_toRadian(to.latitude)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  static double _toRadian(double degree) {
    return degree * math.pi / 180;
  }
}
