import 'dart:math';

/// Route Matcher Service
///
/// Matches driver's GPS location to one of the 13 actual routes in Colombo 7
/// Each route has specific characteristics and risk profiles
///
/// Routes:
/// 1. Independence Square - High capacity (15), Busy area
/// 2. Cinnamon Gardens - Medium capacity (10), High POI
/// 3. Viharamahadevi Park - Low capacity (7), High POI
/// 4. Racecourse - Medium capacity (10), Commercial
/// 5. Ward Place - Low capacity (8), Residential
/// 6. Town Hall - Very High capacity (20), Government
/// 7. BMICH - Very Low capacity (2), Exhibition area
/// 8. Nelum Pokuna - Low capacity (6), Cultural
/// 9. Odel Roundabout - Medium capacity (12), Shopping
/// 10. General Hospital - Very High capacity (25), Medical
/// 11. National Museum - Medium capacity (10), Cultural
/// 12. Eye Hospital - High capacity (18), Medical
/// 13. Baudhaloka Mawatha - Medium capacity (12), Mixed

class RouteData {
  final String name;
  final double latitude;
  final double longitude;
  final int parkCapacity;
  final int poiDensity;
  final String
  type; // Type of area: government, commercial, medical, cultural, residential
  final String? unionRiskLevel; // RED, YELLOW, GREEN
  final String characteristics;

  RouteData({
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.parkCapacity,
    required this.poiDensity,
    required this.type,
    this.unionRiskLevel,
    required this.characteristics,
  });
}

class RouteMatcherService {
  // All 13 routes in Colombo 7
  static final List<RouteData> routes = [
    RouteData(
      name: 'Independence Square',
      latitude: 6.9034,
      longitude: 79.8677,
      parkCapacity: 15,
      poiDensity: 51,
      type: 'government',
      unionRiskLevel: 'RED',
      characteristics: 'Political & civic hub, very busy during day',
    ),
    RouteData(
      name: 'Cinnamon Gardens',
      latitude: 6.912,
      longitude: 79.866,
      parkCapacity: 10,
      poiDensity: 76,
      type: 'commercial',
      unionRiskLevel: 'YELLOW',
      characteristics: 'High-end shopping and residential',
    ),
    RouteData(
      name: 'Viharamahadevi Park',
      latitude: 6.913,
      longitude: 79.864,
      parkCapacity: 7,
      poiDensity: 76,
      type: 'recreational',
      unionRiskLevel: 'GREEN',
      characteristics: 'Public park, moderate traffic',
    ),
    RouteData(
      name: 'Racecourse',
      latitude: 6.906,
      longitude: 79.865,
      parkCapacity: 10,
      poiDensity: 76,
      type: 'recreational',
      unionRiskLevel: 'GREEN',
      characteristics: 'Historic grounds, event-based demand',
    ),
    RouteData(
      name: 'Ward Place',
      latitude: 6.915,
      longitude: 79.869,
      parkCapacity: 8,
      poiDensity: 76,
      type: 'residential',
      unionRiskLevel: 'GREEN',
      characteristics: 'Residential area, steady demand',
    ),
    RouteData(
      name: 'Town Hall',
      latitude: 6.9147,
      longitude: 79.8633,
      parkCapacity: 20,
      poiDensity: 76,
      type: 'government',
      unionRiskLevel: 'RED',
      characteristics: 'City administration center, peak during office hours',
    ),
    RouteData(
      name: 'BMICH',
      latitude: 6.901,
      longitude: 79.8735,
      parkCapacity: 2,
      poiDensity: 54,
      type: 'exhibition',
      unionRiskLevel: 'YELLOW',
      characteristics: 'Exhibition venue, event-dependent demand',
    ),
    RouteData(
      name: 'Nelum Pokuna',
      latitude: 6.909,
      longitude: 79.861,
      parkCapacity: 6,
      poiDensity: 69,
      type: 'cultural',
      unionRiskLevel: 'GREEN',
      characteristics: 'Performing arts center, evening events',
    ),
    RouteData(
      name: 'Odel Roundabout',
      latitude: 6.91,
      longitude: 79.862,
      parkCapacity: 12,
      poiDensity: 76,
      type: 'commercial',
      unionRiskLevel: 'YELLOW',
      characteristics: 'Major shopping area, constant traffic',
    ),
    RouteData(
      name: 'General Hospital',
      latitude: 6.9189,
      longitude: 79.8687,
      parkCapacity: 25,
      poiDensity: 91,
      type: 'medical',
      unionRiskLevel: 'YELLOW',
      characteristics: 'Main hospital, high ambulance & visitor traffic',
    ),
    RouteData(
      name: 'National Museum',
      latitude: 6.908,
      longitude: 79.863,
      parkCapacity: 10,
      poiDensity: 76,
      type: 'cultural',
      unionRiskLevel: 'GREEN',
      characteristics: 'Museum, tourist destination, steady demand',
    ),
    RouteData(
      name: 'Eye Hospital',
      latitude: 6.917,
      longitude: 79.866,
      parkCapacity: 18,
      poiDensity: 91,
      type: 'medical',
      unionRiskLevel: 'YELLOW',
      characteristics: 'Specialized hospital, medical traffic patterns',
    ),
    RouteData(
      name: 'Baudhaloka Mawatha',
      latitude: 6.899,
      longitude: 79.87,
      parkCapacity: 12,
      poiDensity: 54,
      type: 'mixed',
      unionRiskLevel: 'YELLOW',
      characteristics: 'Mixed-use area, morning & evening peaks',
    ),
  ];

  /// Find the nearest route to a given GPS coordinate
  /// Returns the closest route and distance in meters
  static ({RouteData route, double distanceMeters}) findNearestRoute(
    double latitude,
    double longitude,
  ) {
    double minDistance = double.infinity;
    late RouteData nearestRoute;

    for (final route in routes) {
      final distance = _calculateDistance(
        latitude,
        longitude,
        route.latitude,
        route.longitude,
      );

      if (distance < minDistance) {
        minDistance = distance;
        nearestRoute = route;
      }
    }

    return (route: nearestRoute, distanceMeters: minDistance);
  }

  /// Find all routes within a radius
  /// Useful for showing nearby areas
  static List<({RouteData route, double distanceMeters})>
  findRoutesWithinRadius(
    double latitude,
    double longitude,
    double radiusMeters,
  ) {
    final nearby = <({RouteData route, double distanceMeters})>[];

    for (final route in routes) {
      final distance = _calculateDistance(
        latitude,
        longitude,
        route.latitude,
        route.longitude,
      );

      if (distance <= radiusMeters) {
        nearby.add((route: route, distanceMeters: distance));
      }
    }

    // Sort by distance
    nearby.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
    return nearby;
  }

  /// Determine risk profile of a route based on capacity and POI density
  static String determineRiskProfile(RouteData route, double trafficIntensity) {
    // If already has union risk level, use it
    if (route.unionRiskLevel != null) {
      return route.unionRiskLevel!;
    }

    // Otherwise determine from capacity and traffic
    if (route.parkCapacity >= 18) {
      return trafficIntensity > 2.0 ? 'RED' : 'YELLOW';
    } else if (route.parkCapacity >= 12) {
      return trafficIntensity > 3.0 ? 'YELLOW' : 'GREEN';
    } else {
      return 'GREEN';
    }
  }

  /// Get demand multiplier for a specific route type
  static double getDemandMultiplier(String routeType, int hour) {
    switch (routeType) {
      case 'government':
        // Government areas: peak 9-11 AM and 2-4 PM
        if ((hour >= 9 && hour < 11) || (hour >= 14 && hour < 16)) {
          return 1.5;
        }
        return 1.0;

      case 'commercial':
        // Shopping areas: peak 10 AM - 6 PM
        if (hour >= 10 && hour < 18) {
          return 1.3;
        }
        return 0.8;

      case 'medical':
        // Hospitals: consistent throughout day, slight peak 9-11 AM
        if (hour >= 9 && hour < 11) {
          return 1.2;
        }
        return 1.1;

      case 'cultural':
        // Cultural venues: evening peaks (5-8 PM)
        if (hour >= 17 && hour < 20) {
          return 1.4;
        }
        return 0.7;

      case 'recreational':
        // Parks: peak afternoon/evening
        if (hour >= 15 && hour < 19) {
          return 1.2;
        }
        return 0.8;

      case 'residential':
        // Residential: morning (6-8 AM) and evening (5-7 PM)
        if ((hour >= 6 && hour < 8) || (hour >= 17 && hour < 19)) {
          return 1.3;
        }
        return 0.9;

      case 'exhibition':
        // Events-based: depends on event schedule
        return 1.0; // Would need external event data

      case 'mixed':
        // Mixed-use: multiple peaks
        if ((hour >= 6 && hour < 9) ||
            (hour >= 12 && hour < 14) ||
            (hour >= 17 && hour < 19)) {
          return 1.2;
        }
        return 0.9;

      default:
        return 1.0;
    }
  }

  /// Calculate Haversine distance between two coordinates
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

  /// Get all nearby routes with risk level and demand info
  static List<Map<String, dynamic>> getNearbyRoutesWithContext(
    double latitude,
    double longitude,
    double radiusMeters,
    int currentHour,
    double trafficIntensity,
  ) {
    final nearby = findRoutesWithinRadius(latitude, longitude, radiusMeters);

    return nearby.map((item) {
      final route = item.route;
      final distance = item.distanceMeters;
      final riskProfile = determineRiskProfile(route, trafficIntensity);
      final demandMultiplier = getDemandMultiplier(route.type, currentHour);

      return {
        'name': route.name,
        'type': route.type,
        'distance_m': distance,
        'park_capacity': route.parkCapacity,
        'poi_density': route.poiDensity,
        'risk_level': riskProfile,
        'demand_multiplier': demandMultiplier,
        'characteristics': route.characteristics,
        'lat': route.latitude,
        'lon': route.longitude,
      };
    }).toList();
  }
}
