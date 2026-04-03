import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'dart:math' as math;

/// Service to analyze driver's current location and suggest profitable routes
/// This integrates with your dataset (routes_db.csv, collector data, trained model)
class IntelligentRouteAnalyzer {
  /// All hotspots from your database
  static const List<Map<String, dynamic>> HOTSPOTS = [
    {
      "name": "Independence Square",
      "lat": 6.9034,
      "lon": 79.8677,
      "poi_density": 51,
      "type": "demand",
    },
    {
      "name": "Cinnamon Gardens",
      "lat": 6.912,
      "lon": 79.866,
      "poi_density": 76,
      "type": "demand",
    },
    {
      "name": "Viharamahadevi Park",
      "lat": 6.913,
      "lon": 79.864,
      "poi_density": 76,
      "type": "demand",
    },
    {
      "name": "Racecourse",
      "lat": 6.906,
      "lon": 79.865,
      "poi_density": 76,
      "type": "demand",
    },
    {
      "name": "Ward Place",
      "lat": 6.915,
      "lon": 79.869,
      "poi_density": 76,
      "type": "demand",
    },
    {
      "name": "Town Hall",
      "lat": 6.9147,
      "lon": 79.8633,
      "poi_density": 76,
      "type": "demand",
    },
    {
      "name": "BMICH",
      "lat": 6.901,
      "lon": 79.8735,
      "poi_density": 54,
      "type": "traffic",
    },
    {
      "name": "Nelum Pokuna",
      "lat": 6.909,
      "lon": 79.861,
      "poi_density": 69,
      "type": "demand",
    },
    {
      "name": "Odel Roundabout",
      "lat": 6.91,
      "lon": 79.862,
      "poi_density": 76,
      "type": "demand",
    },
    {
      "name": "General Hospital",
      "lat": 6.9189,
      "lon": 79.8687,
      "poi_density": 91,
      "type": "demand",
    },
    {
      "name": "National Museum",
      "lat": 6.908,
      "lon": 79.863,
      "poi_density": 76,
      "type": "demand",
    },
    {
      "name": "Eye Hospital",
      "lat": 6.917,
      "lon": 79.866,
      "poi_density": 91,
      "type": "demand",
    },
    {
      "name": "Baudhaloka Mawatha",
      "lat": 6.899,
      "lon": 79.87,
      "poi_density": 54,
      "type": "traffic",
    },
  ];

  /// Find all hotspots near driver's current location
  static List<HotspotRecommendation> findNearbyHotspots(
    LatLng driverLocation, {
    double radiusKm = 2.0,
  }) {
    final recommendations = <HotspotRecommendation>[];

    for (final hotspot in HOTSPOTS) {
      final distance = _calculateDistance(
        driverLocation.latitude,
        driverLocation.longitude,
        hotspot['lat'] as double,
        hotspot['lon'] as double,
      );

      if (distance <= radiusKm) {
        recommendations.add(
          HotspotRecommendation(
            name: hotspot['name'] as String,
            location: LatLng(
              hotspot['lat'] as double,
              hotspot['lon'] as double,
            ),
            poiDensity: (hotspot['poi_density'] as int).toDouble(),
            type: hotspot['type'] as String,
            distanceKm: distance,
            profitScore: _calculateProfitScore(hotspot),
          ),
        );
      }
    }

    // Sort by profitability (highest first)
    recommendations.sort((a, b) => b.profitScore.compareTo(a.profitScore));
    return recommendations;
  }

  /// Calculate profit score based on POI density and type
  static double _calculateProfitScore(Map<String, dynamic> hotspot) {
    final poiDensity = hotspot['poi_density'] as int;
    final type = hotspot['type'] as String;

    // Demand areas are more profitable than traffic areas
    final typeMultiplier = type == 'demand' ? 1.5 : 1.0;

    // Convert POI density to profit score (0-100)
    // Higher POI = potentially more hires
    return (poiDensity / 91) * 100 * typeMultiplier; // 91 is max from dataset
  }

  /// Calculate distance in km using Haversine formula
  static double _calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const double earthRadiusKm = 6371;

    final dLat = _toRad(lat2 - lat1);
    final dLon = _toRad(lon2 - lon1);

    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRad(lat1)) *
            math.cos(_toRad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);

    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    return earthRadiusKm * c;
  }

  static double _toRad(double degrees) {
    return degrees * (math.pi / 180);
  }

  /// Generate color for road segment based on hotspot intensity
  static int getSegmentColor(double avgPoiDensity) {
    // Profitability scale (0-100)
    final score = (avgPoiDensity / 91) * 100;

    if (score >= 80) {
      return 0xFF00DB24; // 🟢 Very High - Green
    } else if (score >= 60) {
      return 0xFF7CFF00; // 🟡 High - Light Green
    } else if (score >= 40) {
      return 0xFFFFED1C; // 🟡 Medium - Yellow
    } else if (score >= 20) {
      return 0xFFFFA500; // 🟠 Low - Orange
    } else {
      return 0xFFFF0000; // 🔴 Very Low - Red
    }
  }

  /// Get intelligent suggestion message for driver
  static String getSuggestionMessage(List<HotspotRecommendation> hotspots) {
    if (hotspots.isEmpty) {
      return "📍 No hotspots nearby. Head towards downtown!";
    }

    final best = hotspots.first;
    final distance = best.distanceKm;

    if (distance < 0.5) {
      return "🎯 ${best.name} is very close! High success rate here.";
    } else if (distance < 1.0) {
      return "📍 ${best.name} is nearby. Good earnings potential!";
    } else {
      return "🛣️ Head to ${best.name} (${distance.toStringAsFixed(1)}km away)";
    }
  }
}

/// Recommendation data class
class HotspotRecommendation {
  final String name;
  final LatLng location;
  final double poiDensity; // 0-91
  final String type; // 'demand' or 'traffic'
  final double distanceKm;
  final double profitScore; // 0-150

  HotspotRecommendation({
    required this.name,
    required this.location,
    required this.poiDensity,
    required this.type,
    required this.distanceKm,
    required this.profitScore,
  });

  /// Get color for this hotspot marker (Green, Yellow, Red only)
  int get markerColor {
    if (profitScore >= 80) return 0xFF00DB24; // Green (80%+)
    if (profitScore >= 40) return 0xFFFFED1C; // Yellow (40-80%)
    return 0xFFFF0000; // Red (<40%)
  }

  /// Get emoji for this hotspot type
  String get typeEmoji {
    switch (type) {
      case 'demand':
        return '🎯';
      case 'traffic':
        return '⚠️';
      default:
        return '📍';
    }
  }
}
