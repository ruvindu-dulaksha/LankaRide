import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math';

/// Route Corridor Analysis Service
///
/// Analyzes the entire path from start to destination
/// NOT just the starting point!
///
/// Example: Borella → B'mich
/// - Samples 7 points along the route
/// - Analyzes union capacity at each point
/// - Checks traffic, weather, schools
/// - Returns corridor risk assessment

class RouteAnalysisService {
  static const String baseUrl = 'http://localhost:5001';

  /// Analyze entire route corridor from start to destination
  ///
  /// This gives you:
  /// - Overall corridor safety (RED/YELLOW/GREEN)
  /// - Risk level for each segment
  /// - Detailed metrics for entire path
  /// - NOT just the starting location!
  static Future<Map<String, dynamic>> analyzeRouteCorridor({
    required double startLat,
    required double startLon,
    required double endLat,
    required double endLon,
    double rainLevel = 0.0,
    bool isPublicHoliday = false,
  }) async {
    try {
      print('🧭 Analyzing route corridor...');
      print('   Start: ($startLat, $startLon)');
      print('   End:   ($endLat, $endLon)');

      final response = await http
          .post(
            Uri.parse('$baseUrl/predict-route'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'start_lat': startLat,
              'start_lon': startLon,
              'end_lat': endLat,
              'end_lon': endLon,
              'rain_level': rainLevel,
              'is_public_holiday': isPublicHoliday ? 1 : 0,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('✅ Route analysis complete');
        return data;
      } else {
        throw Exception('Route analysis failed: ${response.body}');
      }
    } catch (e) {
      print('❌ Route analysis error: $e');
      rethrow;
    }
  }

  /// Calculate distance between two points (Haversine)
  static double calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const R = 6371000; // Earth radius in meters
    final dLat = _toRad(lat2 - lat1);
    final dLon = _toRad(lon2 - lon1);
    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRad(lat1)) * cos(_toRad(lat2)) * sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  static double _toRad(double deg) => deg * (pi / 180.0);

  /// Parse route analysis response
  static RouteAnalysis parseResponse(Map<String, dynamic> data) {
    return RouteAnalysis.fromJson(data);
  }
}

/// Route Analysis Data Model
class RouteAnalysis {
  final String overallZone;
  final String overallMessage;
  final String riskLevel;
  final String corridorCapacityAvg;
  final int corridorSegments;
  final List<SegmentDetail> segmentDetails;
  final RouteSummary routeSummary;

  RouteAnalysis({
    required this.overallZone,
    required this.overallMessage,
    required this.riskLevel,
    required this.corridorCapacityAvg,
    required this.corridorSegments,
    required this.segmentDetails,
    required this.routeSummary,
  });

  factory RouteAnalysis.fromJson(Map<String, dynamic> json) {
    final routeAnalysis = json['route_analysis'] ?? {};
    final segmentDetailsJson = json['segment_details'] ?? [];
    final routeSummary = json['route_summary'] ?? {};

    return RouteAnalysis(
      overallZone: routeAnalysis['overall_zone'] ?? 'UNKNOWN',
      overallMessage: routeAnalysis['overall_message'] ?? '',
      riskLevel: routeAnalysis['risk_level'] ?? '0/3.0',
      corridorCapacityAvg: routeAnalysis['corridor_capacity_avg'] ?? '0',
      corridorSegments: routeAnalysis['corridor_segments'] ?? 0,
      segmentDetails: (segmentDetailsJson as List)
          .map((s) => SegmentDetail.fromJson(s as Map<String, dynamic>))
          .toList(),
      routeSummary: RouteSummary.fromJson(routeSummary as Map<String, dynamic>),
    );
  }
}

/// Individual route segment analysis
class SegmentDetail {
  final String segment;
  final String location;
  final double lat;
  final double lon;
  final String zone;
  final String message;
  final SegmentMetrics metrics;

  SegmentDetail({
    required this.segment,
    required this.location,
    required this.lat,
    required this.lon,
    required this.zone,
    required this.message,
    required this.metrics,
  });

  factory SegmentDetail.fromJson(Map<String, dynamic> json) {
    final coords = json['coordinates'] ?? {};
    final metricsJson = json['metrics'] ?? {};

    return SegmentDetail(
      segment: json['segment'] ?? '',
      location: json['location'] ?? '',
      lat: (coords['lat'] ?? 0.0).toDouble(),
      lon: (coords['lon'] ?? 0.0).toDouble(),
      zone: json['zone'] ?? 'UNKNOWN',
      message: json['message'] ?? '',
      metrics: SegmentMetrics.fromJson(metricsJson as Map<String, dynamic>),
    );
  }
}

/// Metrics for each route segment
class SegmentMetrics {
  final int unionCapacity;
  final int poiDensity;
  final int trafficDurationSec;
  final double demandScore;
  final String demandType;
  final double rainfallMm;

  SegmentMetrics({
    required this.unionCapacity,
    required this.poiDensity,
    required this.trafficDurationSec,
    required this.demandScore,
    required this.demandType,
    required this.rainfallMm,
  });

  factory SegmentMetrics.fromJson(Map<String, dynamic> json) {
    return SegmentMetrics(
      unionCapacity: json['union_capacity'] ?? 0,
      poiDensity: json['poi_density'] ?? 0,
      trafficDurationSec: json['traffic_duration_sec'] ?? 0,
      demandScore: (json['demand_score'] ?? 0.0).toDouble(),
      demandType: json['demand_type'] ?? '',
      rainfallMm: (json['rainfall_mm'] ?? 0.0).toDouble(),
    );
  }
}

/// Route summary with context
class RouteSummary {
  final double startLat;
  final double startLon;
  final double endLat;
  final double endLon;
  final List<String> zonesEncountered;
  final String highestRisk;
  final int hour;
  final bool isWeekend;
  final bool schoolClosed;
  final double rainfallMm;

  RouteSummary({
    required this.startLat,
    required this.startLon,
    required this.endLat,
    required this.endLon,
    required this.zonesEncountered,
    required this.highestRisk,
    required this.hour,
    required this.isWeekend,
    required this.schoolClosed,
    required this.rainfallMm,
  });

  factory RouteSummary.fromJson(Map<String, dynamic> json) {
    final start = json['start'] ?? {};
    final end = json['end'] ?? {};
    final context = json['context'] ?? {};

    return RouteSummary(
      startLat: (start['lat'] ?? 0.0).toDouble(),
      startLon: (start['lon'] ?? 0.0).toDouble(),
      endLat: (end['lat'] ?? 0.0).toDouble(),
      endLon: (end['lon'] ?? 0.0).toDouble(),
      zonesEncountered: List<String>.from(json['zones_encountered'] ?? []),
      highestRisk: json['highest_risk'] ?? 'UNKNOWN',
      hour: context['time'] ?? 0,
      isWeekend: context['is_weekend'] ?? false,
      schoolClosed: context['school_closed'] ?? false,
      rainfallMm: (context['rainfall_mm'] ?? 0.0).toDouble(),
    );
  }
}
