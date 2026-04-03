import 'package:flutter/material.dart';
import 'package:glassmorphism_ui/glassmorphism_ui.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'dart:math';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../services/poi_service.dart';

/// Hotspot Recommendations Widget
///
/// Shows:
/// - Nearby hotspots (high-demand POI)
/// - Distance to each hotspot
/// - Smart prediction for each (GREEN/YELLOW/RED)
/// - Demand score and estimated wait time
/// - Sorted by profit potential

class HotspotRecommendations extends StatelessWidget {
  final LatLng userLocation;
  final int currentHour;
  final double currentRain;
  final int currentUnionCount;

  const HotspotRecommendations({
    super.key,
    required this.userLocation,
    required this.currentHour,
    required this.currentRain,
    this.currentUnionCount = 10,
  });

  /// Calculate distance between two coordinates in meters
  double _calculateDistance(
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

  double _toRad(double deg) => deg * (pi / 180.0);

  /// Get Smart Hustle prediction for a hotspot
  Map<String, dynamic> _getPredictionForHotspot(POIData poi) {
    final trafficLevel = poi.trafficLevel.toDouble();
    final demand = poi.demandScore;
    final capacity = currentUnionCount;

    // Decision logic (simplified Smart Hustle)
    String zone;
    String recommendation;
    Color zoneColor;
    String emoji;

    // School closing peak logic (12-1:30 PM)
    bool isSchoolPeak = currentHour >= 12 && currentHour < 14;

    // High union capacity = RED zone risks
    if (capacity >= 20) {
      zone = 'RED';
      emoji = '🔴';
      zoneColor = Colors.red;
      recommendation = 'High Risk - Too crowded';
    } else if (capacity >= 15) {
      zone = 'YELLOW';
      emoji = '🟡';
      zoneColor = Colors.orange;
      recommendation = isSchoolPeak ? 'Caution - Peak Hour' : 'Moderate Risk';
    } else {
      // Check traffic for green zones
      if (trafficLevel < 1.5) {
        zone = 'GREEN_SAFE';
        emoji = '🟢';
        zoneColor = Colors.green;
        recommendation = 'Safe - Light Traffic';
      } else {
        zone = 'GREEN_PRIME';
        emoji = '🟢';
        zoneColor = Colors.green;
        recommendation = 'Prime Spot - Good Demand';
      }
    }

    // Calculate estimated wait time (minutes)
    int waitTime = (capacity * (trafficLevel / 2)).toInt();
    if (waitTime < 5) waitTime = 5;
    if (waitTime > 60) waitTime = 60;

    // Profit potential (1-10 scale)
    double profitScore = (demand / 10.0) * (1.0 / (trafficLevel * 0.5 + 0.5));
    if (profitScore > 10) profitScore = 10;

    return {
      'zone': zone,
      'emoji': emoji,
      'color': zoneColor,
      'recommendation': recommendation,
      'waitTime': waitTime,
      'profitScore': profitScore.toStringAsFixed(1),
      'profit': profitScore > 7
          ? '💰💰 High'
          : profitScore > 4
          ? '💰 Medium'
          : '⚠️ Low',
    };
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    // Get hotspots and calculate distances
    final hotspots = POIService.getHotspots(demandThreshold: 75.0);

    final hotspotsWithDistance = hotspots.map((poi) {
      final distance = _calculateDistance(
        userLocation.latitude,
        userLocation.longitude,
        poi.latitude,
        poi.longitude,
      );
      return {
        'poi': poi,
        'distance': distance,
        'prediction': _getPredictionForHotspot(poi),
      };
    }).toList();

    // Sort by profit potential
    hotspotsWithDistance.sort((a, b) {
      final predictionA = (a['prediction'] as Map<String, dynamic>?) ?? {};
      final predictionB = (b['prediction'] as Map<String, dynamic>?) ?? {};
      final scoreA =
          double.tryParse(predictionA['profitScore'].toString()) ?? 0;
      final scoreB =
          double.tryParse(predictionB['profitScore'].toString()) ?? 0;
      return scoreB.compareTo(scoreA); // Descending
    });

    return SingleChildScrollView(
      child: GlassContainer(
        blur: 15,
        opacity: 0.15,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: (isDarkMode ? Colors.white : Colors.black).withOpacity(0.2),
          width: 1.5,
        ),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: isDarkMode
                ? Colors.black.withOpacity(0.3)
                : Colors.white.withOpacity(0.3),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  const Text(
                    '🎯 Hotspot Recommendations',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${hotspotsWithDistance.length} Found',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Hotspot list
              if (hotspotsWithDistance.isEmpty)
                Text(
                  'No high-demand hotspots nearby',
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: Colors.grey),
                )
              else
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(hotspotsWithDistance.length, (index) {
                    final item = hotspotsWithDistance[index];
                    final poi = item['poi'] as POIData;
                    final distance = item['distance'] as double;
                    final prediction =
                        item['prediction'] as Map<String, dynamic>;

                    return _buildHotspotCard(
                      context,
                      poi,
                      distance,
                      prediction,
                      isDarkMode,
                      index,
                    );
                  }),
                ),
            ],
          ),
        ),
      ),
    ).animate().fadeIn(duration: 600.ms).slideY(begin: 0.2);
  }

  Widget _buildHotspotCard(
    BuildContext context,
    POIData poi,
    double distance,
    Map<String, dynamic> prediction,
    bool isDarkMode,
    int index,
  ) {
    final color = prediction['color'] as Color;
    final emoji = prediction['emoji'] as String;
    final recommendation = prediction['recommendation'] as String;
    final waitTime = prediction['waitTime'] as int;
    final profit = prediction['profit'] as String;

    // Distance formatting
    String distanceStr;
    if (distance < 1000) {
      distanceStr = '${distance.toStringAsFixed(0)}m';
    } else {
      distanceStr = '${(distance / 1000).toStringAsFixed(1)}km';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        border: Border.all(color: color.withOpacity(0.5), width: 1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Top row: Name and Distance
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${POIService.getIconByCategory(poi.category)} ${poi.name}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      poi.category.toUpperCase(),
                      style: const TextStyle(fontSize: 8, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    distanceStr,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                  const Text(
                    '📍 Away',
                    style: TextStyle(fontSize: 8, color: Colors.grey),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Prediction & metrics row
          Row(
            children: [
              // Zone prediction
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.2),
                  border: Border.all(color: color),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(emoji, style: const TextStyle(fontSize: 12)),
                    Text(
                      recommendation,
                      style: TextStyle(
                        fontSize: 7,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // Demand & profit
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Demand: ${poi.demandScore.toStringAsFixed(0)}/100',
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            profit,
                            style: const TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '⏱️ Est. Wait: $waitTime min | 👥 Union: ${poi.trafficLevel}/5',
                      style: const TextStyle(fontSize: 8, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    ).animate(delay: Duration(milliseconds: 50 * index)).fadeIn();
  }
}
