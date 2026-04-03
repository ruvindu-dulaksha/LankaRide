import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Heatmap visualization for LankaRide
///
/// Shows zone risk levels as colored overlays on the map
/// RED = High risk (union territory)
/// YELLOW = Medium risk (caution area)
/// GREEN = Low risk (safe area)
///
/// Uses polylines to draw colored route corridors

class HeatmapZone {
  final String name;
  final String zoneType; // RED, YELLOW, GREEN
  final List<LatLng> boundaryPoints;
  final String description;
  final int unionCapacity;
  final double demandScore;

  HeatmapZone({
    required this.name,
    required this.zoneType,
    required this.boundaryPoints,
    required this.description,
    required this.unionCapacity,
    required this.demandScore,
  });
}

class HeatmapVisualizationService {
  /// Define heatmap zones in Colombo 7
  /// Each zone has a risk level and characteristics
  static final List<HeatmapZone> heatmapZones = [
    // RED ZONES (High Union Risk - Capacity >= 15)
    HeatmapZone(
      name: 'Independence Square Core',
      zoneType: 'RED',
      boundaryPoints: [
        const LatLng(6.9034, 79.8677),
        const LatLng(6.9050, 79.8677),
        const LatLng(6.9050, 79.8690),
        const LatLng(6.9034, 79.8690),
      ],
      description: 'Political hub with strong union presence',
      unionCapacity: 15,
      demandScore: 80,
    ),
    HeatmapZone(
      name: 'Town Hall District',
      zoneType: 'RED',
      boundaryPoints: [
        const LatLng(6.9147, 79.8633),
        const LatLng(6.9160, 79.8633),
        const LatLng(6.9160, 79.8650),
        const LatLng(6.9147, 79.8650),
      ],
      description: 'Government center with union control',
      unionCapacity: 20,
      demandScore: 85,
    ),
    HeatmapZone(
      name: 'General Hospital Complex',
      zoneType: 'RED',
      boundaryPoints: [
        const LatLng(6.9189, 79.8687),
        const LatLng(6.9200, 79.8687),
        const LatLng(6.9200, 79.8700),
        const LatLng(6.9189, 79.8700),
      ],
      description: 'Large hospital with organized unions',
      unionCapacity: 25,
      demandScore: 90,
    ),

    // YELLOW ZONES (Medium Risk - Capacity 12-14 or high traffic)
    HeatmapZone(
      name: 'Cinnamon Gardens Market',
      zoneType: 'YELLOW',
      boundaryPoints: [
        const LatLng(6.912, 79.866),
        const LatLng(6.918, 79.866),
        const LatLng(6.918, 79.872),
        const LatLng(6.912, 79.872),
      ],
      description: 'Shopping area with moderate union presence',
      unionCapacity: 12,
      demandScore: 85,
    ),
    HeatmapZone(
      name: 'Odel Roundabout Shopping',
      zoneType: 'YELLOW',
      boundaryPoints: [
        const LatLng(6.91, 79.862),
        const LatLng(6.915, 79.862),
        const LatLng(6.915, 79.867),
        const LatLng(6.91, 79.867),
      ],
      description: 'Major shopping zone with gridlock risk',
      unionCapacity: 12,
      demandScore: 90,
    ),
    HeatmapZone(
      name: 'Eye Hospital Zone',
      zoneType: 'YELLOW',
      boundaryPoints: [
        const LatLng(6.917, 79.866),
        const LatLng(6.922, 79.866),
        const LatLng(6.922, 79.871),
        const LatLng(6.917, 79.871),
      ],
      description: 'Medical facility with organized traffic',
      unionCapacity: 18,
      demandScore: 85,
    ),
    HeatmapZone(
      name: 'Baudhaloka Mixed Use',
      zoneType: 'YELLOW',
      boundaryPoints: [
        const LatLng(6.899, 79.87),
        const LatLng(6.904, 79.87),
        const LatLng(6.904, 79.875),
        const LatLng(6.899, 79.875),
      ],
      description: 'Mixed-use area with caution zone',
      unionCapacity: 12,
      demandScore: 75,
    ),
    HeatmapZone(
      name: 'BMICH Exhibition Center',
      zoneType: 'YELLOW',
      boundaryPoints: [
        const LatLng(6.901, 79.8735),
        const LatLng(6.905, 79.8735),
        const LatLng(6.905, 79.8780),
        const LatLng(6.901, 79.8780),
      ],
      description: 'Event venue with variable demand',
      unionCapacity: 8,
      demandScore: 70,
    ),

    // GREEN ZONES (Low Risk - Capacity < 12)
    HeatmapZone(
      name: 'Viharamahadevi Park',
      zoneType: 'GREEN',
      boundaryPoints: [
        const LatLng(6.913, 79.864),
        const LatLng(6.918, 79.864),
        const LatLng(6.918, 79.869),
        const LatLng(6.913, 79.869),
      ],
      description: 'Safe recreational area',
      unionCapacity: 7,
      demandScore: 60,
    ),
    HeatmapZone(
      name: 'Racecourse Grounds',
      zoneType: 'GREEN',
      boundaryPoints: [
        const LatLng(6.906, 79.865),
        const LatLng(6.911, 79.865),
        const LatLng(6.911, 79.870),
        const LatLng(6.906, 79.870),
      ],
      description: 'Safe with low union interference',
      unionCapacity: 10,
      demandScore: 55,
    ),
    HeatmapZone(
      name: 'Ward Place Residential',
      zoneType: 'GREEN',
      boundaryPoints: [
        const LatLng(6.915, 79.869),
        const LatLng(6.920, 79.869),
        const LatLng(6.920, 79.874),
        const LatLng(6.915, 79.874),
      ],
      description: 'Safe residential area',
      unionCapacity: 8,
      demandScore: 70,
    ),
    HeatmapZone(
      name: 'National Museum District',
      zoneType: 'GREEN',
      boundaryPoints: [
        const LatLng(6.908, 79.863),
        const LatLng(6.912, 79.863),
        const LatLng(6.912, 79.868),
        const LatLng(6.908, 79.868),
      ],
      description: 'Cultural zone with steady demand',
      unionCapacity: 10,
      demandScore: 65,
    ),
    HeatmapZone(
      name: 'Nelum Pokuna Theater',
      zoneType: 'GREEN',
      boundaryPoints: [
        const LatLng(6.909, 79.861),
        const LatLng(6.913, 79.861),
        const LatLng(6.913, 79.866),
        const LatLng(6.909, 79.866),
      ],
      description: 'Safe cultural entertainment zone',
      unionCapacity: 6,
      demandScore: 75,
    ),
  ];

  /// Get color for zone type
  static Color getZoneColor(String zoneType) {
    switch (zoneType) {
      case 'RED':
        return const Color(0xFFEF5350); // Red - High Risk
      case 'YELLOW':
        return const Color(0xFFFFA726); // Orange - Medium Risk
      case 'GREEN':
        return const Color(0xFF66BB6A); // Green - Low Risk
      default:
        return const Color(0xFF9E9E9E); // Grey
    }
  }

  /// Get zone description with emoji
  static ({String emoji, String label, String color}) getZoneLabel(
    String zoneType,
  ) {
    switch (zoneType) {
      case 'RED':
        return (emoji: '🔴', label: 'HIGH RISK', color: '#EF5350');
      case 'YELLOW':
        return (emoji: '🟡', label: 'CAUTION', color: '#FFA726');
      case 'GREEN':
        return (emoji: '🟢', label: 'SAFE', color: '#66BB6A');
      default:
        return (emoji: '⚪', label: 'UNKNOWN', color: '#9E9E9E');
    }
  }

  /// Create polygon for a zone
  static Polygon createZonePolygon(HeatmapZone zone, int polygonIndex) {
    return Polygon(
      polygonId: PolygonId('zone_${zone.name}_$polygonIndex'),
      points: zone.boundaryPoints,
      fillColor: getZoneColor(zone.zoneType).withOpacity(0.25),
      strokeColor: getZoneColor(zone.zoneType),
      strokeWidth: 2,
      geodesic: false,
    );
  }

  /// Create polyline for route corridor coloring
  static Polyline createRoutePolyline(
    String routeName,
    List<LatLng> routePoints,
    String zoneType,
  ) {
    return Polyline(
      polylineId: PolylineId('route_$routeName'),
      points: routePoints,
      color: getZoneColor(zoneType),
      width: 6,
      geodesic: true,
      patterns: [PatternItem.dash(30), PatternItem.gap(20)],
    );
  }

  /// Get zones that contain a specific coordinate
  static List<HeatmapZone> getZonesAtLocation(LatLng location) {
    return heatmapZones
        .where((zone) => _isPointInPolygon(location, zone.boundaryPoints))
        .toList();
  }

  /// Check if a point is inside a polygon (ray casting algorithm)
  static bool _isPointInPolygon(LatLng point, List<LatLng> polygon) {
    int crossings = 0;
    for (int i = 0; i < polygon.length; i++) {
      final p1 = polygon[i];
      final p2 = polygon[(i + 1) % polygon.length];

      if ((p1.latitude <= point.latitude && point.latitude < p2.latitude) ||
          (p2.latitude <= point.latitude && point.latitude < p1.latitude)) {
        final xinters =
            (point.latitude - p1.latitude) *
                (p2.longitude - p1.longitude) /
                (p2.latitude - p1.latitude) +
            p1.longitude;
        if (point.longitude < xinters) {
          crossings++;
        }
      }
    }
    return crossings % 2 != 0;
  }

  /// Get all zones and their statistics
  static Map<String, int> getZoneStatistics() {
    return {
      'RED': heatmapZones.where((z) => z.zoneType == 'RED').length,
      'YELLOW': heatmapZones.where((z) => z.zoneType == 'YELLOW').length,
      'GREEN': heatmapZones.where((z) => z.zoneType == 'GREEN').length,
      'TOTAL': heatmapZones.length,
    };
  }
}
