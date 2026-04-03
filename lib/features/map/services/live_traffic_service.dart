import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

/// Live traffic data from the trained model
class TrafficPrediction {
  final String zone; // GREEN, YELLOW, RED
  final String message;
  final double riskScore; // 0-1
  final String location;
  final int unionCapacity;
  final double rainMm;
  final int poiDensity;
  final double predictedTrafficSec;
  final double trafficIntensity; // 0-1
  final String demandLevel; // Low, Medium, High, Peak
  final bool schoolClosed;
  final bool schoolClosingPeak;
  final bool hasSchoolsNearby;
  final List<Map<String, dynamic>> nearbySchools;
  final int nearestSchoolDistanceM;
  final bool isWeekend;
  final String timeOfDay;
  final bool modelUsed;
  final LatLng coordinates;

  TrafficPrediction({
    required this.zone,
    required this.message,
    required this.riskScore,
    required this.location,
    required this.unionCapacity,
    required this.rainMm,
    required this.poiDensity,
    required this.predictedTrafficSec,
    required this.trafficIntensity,
    required this.demandLevel,
    required this.schoolClosed,
    required this.schoolClosingPeak,
    required this.hasSchoolsNearby,
    required this.nearbySchools,
    required this.nearestSchoolDistanceM,
    required this.isWeekend,
    required this.timeOfDay,
    required this.modelUsed,
    required this.coordinates,
  });

  /// Get zone emoji
  String get zoneEmoji {
    switch (zone) {
      case 'GREEN':
        return '🟢';
      case 'RED':
        return '🔴';
      case 'YELLOW':
        return '🟡';
      default:
        return '⚪';
    }
  }

  /// Color for UI elements
  int get zoneColor {
    switch (zone) {
      case 'GREEN':
        return 0xFF00DB24;
      case 'RED':
        return 0xFFFF0000;
      case 'YELLOW':
        return 0xFFFFED1C;
      default:
        return 0xFF808080;
    }
  }

  /// Parse from JSON response
  factory TrafficPrediction.fromJson(Map<String, dynamic> json) {
    final metadata = json['metadata'] ?? {};
    final nearbySchools = List<Map<String, dynamic>>.from(
      metadata['nearby_schools'] ?? [],
    );

    return TrafficPrediction(
      zone: json['zone'] ?? 'YELLOW',
      message: json['message'] ?? 'No data',
      riskScore: (json['risk_score'] ?? 0.0).toDouble(),
      location: metadata['location'] ?? 'Unknown',
      unionCapacity: metadata['union_capacity'] ?? 0,
      rainMm: (metadata['rain_mm'] ?? 0.0).toDouble(),
      poiDensity: metadata['poi_density'] ?? 40,
      predictedTrafficSec: (metadata['predicted_traffic_sec'] ?? 0.0)
          .toDouble(),
      trafficIntensity: (metadata['traffic_intensity'] ?? 0.0).toDouble(),
      demandLevel: metadata['demand_level'] ?? 'Unknown',
      schoolClosed: metadata['school_closed'] ?? false,
      schoolClosingPeak: metadata['school_closing_peak'] ?? false,
      hasSchoolsNearby: metadata['has_schools_nearby'] ?? false,
      nearbySchools: nearbySchools,
      nearestSchoolDistanceM:
          metadata['nearest_school_distance_m']?.toInt() ?? 0,
      isWeekend: metadata['is_weekend'] ?? false,
      timeOfDay: metadata['time_of_day'] ?? '00:00',
      modelUsed: metadata['model_used'] ?? false,
      coordinates: LatLng(
        metadata['coordinates']?['lat'] ?? 6.9271,
        metadata['coordinates']?['lon'] ?? 79.8677,
      ),
    );
  }
}

/// Live traffic service - integrates with backend XGBoost model
class LiveTrafficService {
  static const String _baseUrl = 'http://localhost:5000'; // Flask backend
  static const int _timeoutSeconds = 10;

  /// Get live traffic prediction for current location
  static Future<TrafficPrediction?> getTrafficPrediction(
    double latitude,
    double longitude, {
    double? rainLevel,
    double? unionDensity,
    bool? isPublicHoliday,
  }) async {
    try {
      final url = Uri.parse('$_baseUrl/predict');

      final payload = {
        'latitude': latitude,
        'longitude': longitude,
        'rain_level': rainLevel ?? 0.0,
        'union_density': unionDensity ?? 0.0,
        'is_public_holiday': (isPublicHoliday ?? false) ? 1 : 0,
      };

      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: _timeoutSeconds));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return TrafficPrediction.fromJson(json);
      } else if (response.statusCode == 403) {
        // Out of service area
        print('🚫 Location out of service area');
        return null;
      } else {
        print('❌ Traffic prediction failed: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('❌ Traffic service error: $e');
      return null;
    }
  }

  /// Apply traffic rules to determine which hotspots are best RIGHT NOW
  static List<Map<String, dynamic>> applySmartHustleRules(
    List<Map<String, dynamic>> hotspots,
    TrafficPrediction traffic,
  ) {
    final scoredHotspots = <Map<String, dynamic>>[];

    for (final hotspot in hotspots) {
      final poiDensity = (hotspot['poi_density'] as int).toDouble();
      final profitScore = (poiDensity / 91) * 100;

      // SMART HUSTLING RULES
      // Rule 1: Traffic condition multiplier
      double trafficMultiplier = 1.0;
      if (traffic.zone == 'GREEN') {
        trafficMultiplier = 1.3; // 30% boost - low traffic, more pickups
      } else if (traffic.zone == 'YELLOW') {
        trafficMultiplier = 1.0; // Normal traffic
      } else if (traffic.zone == 'RED') {
        trafficMultiplier = 0.7; // 30% penalty - high traffic, slow pickups
      }

      // Rule 2: School nearby detection
      double schoolBoost = 1.0;
      if (traffic.hasSchoolsNearby &&
          traffic.schoolClosed &&
          traffic.schoolClosingPeak) {
        // School just closed = PEAK TIME for students going home
        schoolBoost = 1.5; // 50% boost
      }

      // Rule 3: Demand level multiplier
      double demandMultiplier = 1.0;
      switch (traffic.demandLevel) {
        case 'Peak':
          demandMultiplier = 1.4;
          break;
        case 'High':
          demandMultiplier = 1.2;
          break;
        case 'Medium':
          demandMultiplier = 1.0;
          break;
        case 'Low':
          demandMultiplier = 0.8;
          break;
      }

      // Rule 4: Weather penalty (rain reduces pickups)
      double weatherPenalty = 1.0;
      if (traffic.rainMm > 2.0) {
        weatherPenalty = 0.9; // 10% penalty for significant rain
      }

      // FINAL SMART SCORE
      double smartScore =
          profitScore *
          trafficMultiplier *
          schoolBoost *
          demandMultiplier *
          weatherPenalty;

      scoredHotspots.add({
        ...hotspot,
        'smart_score': smartScore,
        'original_score': profitScore,
        'traffic_multiplier': trafficMultiplier,
        'demand_multiplier': demandMultiplier,
        'school_boost': schoolBoost,
        'weather_penalty': weatherPenalty,
        'reasoning': _generateReasoning(
          hotspot['name'],
          traffic,
          trafficMultiplier,
          schoolBoost,
          demandMultiplier,
        ),
      });
    }

    // Sort by smart score (highest first)
    scoredHotspots.sort(
      (a, b) =>
          (b['smart_score'] as double).compareTo(a['smart_score'] as double),
    );

    return scoredHotspots;
  }

  /// Generate human-readable reasoning for each hotspot ranking
  static String _generateReasoning(
    String hotspotName,
    TrafficPrediction traffic,
    double trafficMult,
    double schoolBoost,
    double demandMult,
  ) {
    final reasons = <String>[];

    // Traffic reason
    if (trafficMult > 1.1) {
      reasons.add('${traffic.zone} - light traffic');
    } else if (trafficMult < 0.9) {
      reasons.add('${traffic.zone} - heavy traffic');
    }

    // School boost
    if (schoolBoost > 1.1) {
      reasons.add(
        'school closing peak (${traffic.nearbySchools.length} schools nearby)',
      );
    }

    // Demand
    if (demandMult > 1.1) {
      reasons.add('${traffic.demandLevel} demand');
    }

    // Time specific
    reasons.add('Time: ${traffic.timeOfDay}');

    return reasons.join(' • ');
  }

  /// Get real-time ranking of hotspots based on traffic
  static Future<List<Map<String, dynamic>>> getRealTimeHotspotRanking(
    double latitude,
    double longitude,
    List<Map<String, dynamic>> allHotspots,
  ) async {
    // Get live traffic
    final traffic = await getTrafficPrediction(latitude, longitude);

    if (traffic == null) {
      // If traffic data not available, return hotspots sorted by POI only
      final sorted = [...allHotspots];
      sorted.sort(
        (a, b) => (b['poi_density'] as int).compareTo(a['poi_density'] as int),
      );
      return sorted;
    }

    // Apply smart hustling rules
    return applySmartHustleRules(allHotspots, traffic);
  }
}
