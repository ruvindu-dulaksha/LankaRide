import 'dart:math';
import 'package:flutter/material.dart';

/// Points of Interest (POI) Service
///
/// Displays interesting points, hotspots, and landmarks on the map
/// POI = Places with high passenger demand (restaurants, shops, hospitals, etc.)

class POIData {
  final String name;
  final double latitude;
  final double longitude;
  final String category;
  final String icon;
  final String description;
  final double demandScore; // 0-100, how likely to have passengers
  final int trafficLevel; // 1-5, how congested

  POIData({
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.category,
    required this.icon,
    required this.description,
    required this.demandScore,
    required this.trafficLevel,
  });
}

class POIService {
  /// All POI in Colombo 7
  static final List<POIData> poiList = [
    // Hospitals
    POIData(
      name: 'National Hospital',
      latitude: 6.9189,
      longitude: 79.8687,
      category: 'medical',
      icon: '🏥',
      description: 'Main tertiary care hospital',
      demandScore: 95,
      trafficLevel: 5,
    ),
    POIData(
      name: 'Eye Hospital',
      latitude: 6.917,
      longitude: 79.866,
      category: 'medical',
      icon: '👁️',
      description: 'Specialized eye care center',
      demandScore: 85,
      trafficLevel: 4,
    ),
    POIData(
      name: 'Colombo Private Hospital',
      latitude: 6.91,
      longitude: 79.87,
      category: 'medical',
      icon: '🏥',
      description: 'Private medical facility',
      demandScore: 80,
      trafficLevel: 4,
    ),

    // Shopping & Markets
    POIData(
      name: 'Odel Department Store',
      latitude: 6.91,
      longitude: 79.862,
      category: 'shopping',
      icon: '🛍️',
      description: 'Major retail hub',
      demandScore: 90,
      trafficLevel: 5,
    ),
    POIData(
      name: 'Cinnamon Gardens Shopping',
      latitude: 6.912,
      longitude: 79.866,
      category: 'shopping',
      icon: '🛍️',
      description: 'High-end fashion district',
      demandScore: 85,
      trafficLevel: 4,
    ),
    POIData(
      name: 'Gregory\'s Shopping Mall',
      latitude: 6.915,
      longitude: 79.865,
      category: 'shopping',
      icon: '🛍️',
      description: 'Premium shopping destination',
      demandScore: 75,
      trafficLevel: 4,
    ),

    // Restaurants & Food
    POIData(
      name: 'Cinnamon Gardens Restaurants',
      latitude: 6.913,
      longitude: 79.867,
      category: 'dining',
      icon: '🍽️',
      description: 'Restaurant district',
      demandScore: 80,
      trafficLevel: 4,
    ),
    POIData(
      name: 'Ward Place Food Hub',
      latitude: 6.915,
      longitude: 79.869,
      category: 'dining',
      icon: '🍽️',
      description: 'Local eateries cluster',
      demandScore: 70,
      trafficLevel: 3,
    ),

    // Educational Institutions
    POIData(
      name: 'University of Colombo',
      latitude: 6.912,
      longitude: 79.863,
      category: 'education',
      icon: '🎓',
      description: 'Main university campus',
      demandScore: 75,
      trafficLevel: 3,
    ),
    POIData(
      name: 'Science Faculty',
      latitude: 6.914,
      longitude: 79.864,
      category: 'education',
      icon: '🔬',
      description: 'Science building complex',
      demandScore: 70,
      trafficLevel: 3,
    ),

    // Government & Civic
    POIData(
      name: 'Town Hall',
      latitude: 6.9147,
      longitude: 79.8633,
      category: 'government',
      icon: '🏛️',
      description: 'City administration center',
      demandScore: 85,
      trafficLevel: 4,
    ),
    POIData(
      name: 'Presidential Secretariat',
      latitude: 6.903,
      longitude: 79.868,
      category: 'government',
      icon: '🏛️',
      description: 'Government official residence',
      demandScore: 80,
      trafficLevel: 4,
    ),

    // Cultural & Entertainment
    POIData(
      name: 'Nelum Pokuna Theater',
      latitude: 6.909,
      longitude: 79.861,
      category: 'cultural',
      icon: '🎭',
      description: 'Performing arts center',
      demandScore: 75,
      trafficLevel: 3,
    ),
    POIData(
      name: 'National Museum',
      latitude: 6.908,
      longitude: 79.863,
      category: 'cultural',
      icon: '🏛️',
      description: 'History & cultural museum',
      demandScore: 65,
      trafficLevel: 2,
    ),
    POIData(
      name: 'BMICH Convention Center',
      latitude: 6.901,
      longitude: 79.8735,
      category: 'events',
      icon: '🎪',
      description: 'Major event venue',
      demandScore: 70,
      trafficLevel: 4,
    ),

    // Parks & Recreation
    POIData(
      name: 'Viharamahadevi Park',
      latitude: 6.913,
      longitude: 79.864,
      category: 'recreation',
      icon: '🌳',
      description: 'Public park with walking paths',
      demandScore: 60,
      trafficLevel: 2,
    ),
    POIData(
      name: 'Racecourse Grounds',
      latitude: 6.906,
      longitude: 79.865,
      category: 'recreation',
      icon: '🏇',
      description: 'Historic racing venue',
      demandScore: 55,
      trafficLevel: 3,
    ),

    // Hotels & Lodging
    POIData(
      name: 'Mount Lavinia Hotel',
      latitude: 6.898,
      longitude: 79.87,
      category: 'lodging',
      icon: '🏨',
      description: 'Historic beach resort',
      demandScore: 75,
      trafficLevel: 3,
    ),

    // Transportation Hubs
    POIData(
      name: 'Main Bus Station',
      latitude: 6.915,
      longitude: 79.865,
      category: 'transport',
      icon: '🚌',
      description: 'Central bus terminal',
      demandScore: 95,
      trafficLevel: 5,
    ),
  ];

  /// Get POI by category
  static List<POIData> getPOIByCategory(String category) {
    return poiList.where((poi) => poi.category == category).toList();
  }

  /// Get all POI within a radius
  static List<POIData> getPOIWithinRadius(
    double latitude,
    double longitude,
    double radiusMeters,
  ) {
    return poiList.where((poi) {
      final distance = _calculateDistance(
        latitude,
        longitude,
        poi.latitude,
        poi.longitude,
      );
      return distance <= radiusMeters;
    }).toList();
  }

  /// Get high-demand POI (potential hotspots)
  static List<POIData> getHotspots({double demandThreshold = 75.0}) {
    return poiList.where((poi) => poi.demandScore >= demandThreshold).toList()
      ..sort((a, b) => b.demandScore.compareTo(a.demandScore));
  }

  /// Get color based on demand score
  static Color getColorByDemand(double demandScore) {
    if (demandScore >= 85) {
      return const Color(0xFF1976D2); // Deep blue - VERY HIGH demand
    } else if (demandScore >= 75) {
      return const Color(0xFF42A5F5); // Blue - HIGH demand
    } else if (demandScore >= 60) {
      return const Color(0xFF66BB6A); // Green - GOOD demand
    } else {
      return const Color(0xFF78909C); // Grey - MODERATE demand
    }
  }

  /// Get icon emoji based on category
  static String getIconByCategory(String category) {
    switch (category) {
      case 'medical':
        return '🏥';
      case 'shopping':
        return '🛍️';
      case 'dining':
        return '🍽️';
      case 'education':
        return '🎓';
      case 'government':
        return '🏛️';
      case 'cultural':
        return '🎭';
      case 'events':
        return '🎪';
      case 'recreation':
        return '🌳';
      case 'lodging':
        return '🏨';
      case 'transport':
        return '🚌';
      default:
        return '📍';
    }
  }

  static double _calculateDistance(
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
}
