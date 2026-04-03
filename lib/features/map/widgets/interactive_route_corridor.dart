import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:glassmorphism_ui/glassmorphism_ui.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// Interactive Route Corridor Map
///
/// Visualizes the entire route corridor on the map with:
/// - Colored polylines for each segment (RED/YELLOW/GREEN)
/// - Waypoint markers (1-7) showing segment progression
/// - Hotspots along the route with their demand colors
/// - Clickable segments to see detailed metrics
/// - Real-time corridor analysis overlay

class InteractiveRouteCorridor extends StatefulWidget {
  final GoogleMapController? mapController;
  final List<Map<String, dynamic>> segments; // From /predict-route API
  final LatLng startLocation;
  final LatLng endLocation;
  final String overallZone;
  final VoidCallback? onSegmentTap;

  const InteractiveRouteCorridor({
    super.key,
    required this.mapController,
    required this.segments,
    required this.startLocation,
    required this.endLocation,
    required this.overallZone,
    this.onSegmentTap,
  });

  @override
  State<InteractiveRouteCorridor> createState() =>
      _InteractiveRouteCorridorState();
}

class _InteractiveRouteCorridorState extends State<InteractiveRouteCorridor> {
  late Set<Polyline> _corridorPolylines;
  late Set<Marker> _segmentMarkers;
  late Set<Marker> _hotspotsOnRoute;
  int? _selectedSegment;

  @override
  void initState() {
    super.initState();
    _corridorPolylines = {};
    _segmentMarkers = {};
    _hotspotsOnRoute = {};
    _buildCorridor();
  }

  /// Build corridor visualization from segments
  void _buildCorridor() {
    _corridorPolylines.clear();
    _segmentMarkers.clear();
    _hotspotsOnRoute.clear();

    // Draw polylines for each segment
    for (int i = 0; i < widget.segments.length - 1; i++) {
      final currentSegment = widget.segments[i];
      final nextSegment = widget.segments[i + 1];

      final currentLat = currentSegment['metrics']?['latitude'] ?? 6.9271;
      final currentLon = currentSegment['metrics']?['longitude'] ?? 80.7789;
      final nextLat = nextSegment['metrics']?['latitude'] ?? 6.9271;
      final nextLon = nextSegment['metrics']?['longitude'] ?? 80.7789;

      final zone = currentSegment['zone'] ?? 'GREEN';

      // Create polyline for this segment
      _corridorPolylines.add(
        Polyline(
          polylineId: PolylineId('segment_$i'),
          points: [LatLng(currentLat, currentLon), LatLng(nextLat, nextLon)],
          color: _getZoneColor(zone),
          width: 8,
          geodesic: true,
          patterns: [PatternItem.dash(15), PatternItem.gap(10)],
          onTap: () => _onSegmentTap(i),
        ),
      );

      // Create waypoint marker for this segment
      _segmentMarkers.add(
        Marker(
          markerId: MarkerId('waypoint_$i'),
          position: LatLng(currentLat, currentLon),
          infoWindow: InfoWindow(title: 'Segment ${i + 1}/7', snippet: zone),
          icon: _getWaypointIcon(i, zone),
          onTap: () => _onSegmentTap(i),
        ),
      );
    }

    // Add final waypoint
    final lastSegment = widget.segments.last;
    final lastLat = lastSegment['metrics']?['latitude'] ?? 6.9271;
    final lastLon = lastSegment['metrics']?['longitude'] ?? 80.7789;
    _segmentMarkers.add(
      Marker(
        markerId: const MarkerId('waypoint_end'),
        position: LatLng(lastLat, lastLon),
        infoWindow: const InfoWindow(
          title: 'Destination',
          snippet: 'End of route',
        ),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      ),
    );

    // Add start marker
    _segmentMarkers.add(
      Marker(
        markerId: const MarkerId('start'),
        position: widget.startLocation,
        infoWindow: const InfoWindow(
          title: 'Start',
          snippet: 'Your current location',
        ),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      ),
    );

    setState(() {});
  }

  /// Get color based on zone
  Color _getZoneColor(String zone) {
    switch (zone.toUpperCase()) {
      case 'RED':
        return const Color(0xFFEF5350);
      case 'YELLOW':
        return const Color(0xFFFFA726);
      case 'GREEN':
        return const Color(0xFF66BB6A);
      default:
        return Colors.grey;
    }
  }

  /// Get waypoint icon
  BitmapDescriptor _getWaypointIcon(int index, String zone) {
    switch (zone.toUpperCase()) {
      case 'RED':
        return BitmapDescriptor.defaultMarkerWithHue(0); // Red
      case 'YELLOW':
        return BitmapDescriptor.defaultMarkerWithHue(45); // Orange
      case 'GREEN':
        return BitmapDescriptor.defaultMarkerWithHue(120); // Green
      default:
        return BitmapDescriptor.defaultMarkerWithHue(0);
    }
  }

  /// Handle segment tap
  void _onSegmentTap(int segmentIndex) {
    setState(() {
      _selectedSegment = _selectedSegment == segmentIndex ? null : segmentIndex;
    });
    widget.onSegmentTap?.call();

    // Animate camera to segment
    if (widget.mapController != null) {
      final segment = widget.segments[segmentIndex];
      final lat = segment['metrics']?['latitude'] ?? 6.9271;
      final lon = segment['metrics']?['longitude'] ?? 80.7789;

      widget.mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: LatLng(lat, lon), zoom: 16),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Stack(
      children: [
        // Legend
        Positioned(
          top: 12,
          left: 12,
          right: 12,
          child: _buildCorridorLegend(context, isDarkMode),
        ),

        // Segment detail card (when selected)
        if (_selectedSegment != null)
          Positioned(
            bottom: 20,
            left: 16,
            right: 16,
            child: _buildSegmentDetailCard(context, isDarkMode),
          ),
      ],
    );
  }

  Widget _buildCorridorLegend(BuildContext context, bool isDarkMode) {
    final redCount = widget.segments
        .where((s) => s['zone']?.toUpperCase() == 'RED')
        .length;
    final yellowCount = widget.segments
        .where((s) => s['zone']?.toUpperCase() == 'YELLOW')
        .length;
    final greenCount = widget.segments
        .where((s) => s['zone']?.toUpperCase() == 'GREEN')
        .length;

    return GlassContainer(
      blur: 15,
      opacity: 0.15,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: (isDarkMode ? Colors.white : Colors.black).withOpacity(0.2),
        width: 1,
      ),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: isDarkMode
              ? Colors.black.withOpacity(0.2)
              : Colors.white.withOpacity(0.2),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '🛣️ Route Corridor Analysis',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: _getZoneColor(widget.overallZone),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    widget.overallZone,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 6,
              children: [
                _buildZoneIndicator('🔴 Red', redCount, Colors.red),
                _buildZoneIndicator('🟡 Yellow', yellowCount, Colors.orange),
                _buildZoneIndicator('🟢 Green', greenCount, Colors.green),
                _buildZoneIndicator(
                  '📍 Segments',
                  widget.segments.length,
                  Colors.blue,
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Tap on route segments to see details',
              style: TextStyle(
                fontSize: 9,
                color: Colors.grey,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 400.ms);
  }

  Widget _buildZoneIndicator(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.25),
        border: Border.all(color: color.withOpacity(0.6), width: 1),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        '$label: $count',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color.withOpacity(0.9),
        ),
      ),
    );
  }

  Widget _buildSegmentDetailCard(BuildContext context, bool isDarkMode) {
    final segment = widget.segments[_selectedSegment!];
    final zone = segment['zone'] ?? 'GREEN';
    final zoneColor = _getZoneColor(zone);
    final metrics = segment['metrics'] ?? {};

    return GlassContainer(
      blur: 20,
      opacity: 0.2,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: zoneColor.withOpacity(0.5), width: 1.5),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: zoneColor.withOpacity(0.1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Segment ${_selectedSegment! + 1}/7',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: zoneColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    zone,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Metrics grid
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.0,
              children: [
                _buildMetricItem(
                  '👥',
                  'Union',
                  '${metrics['union_capacity'] ?? 0}',
                ),
                _buildMetricItem('🏢', 'POI', '${metrics['poi_density'] ?? 0}'),
                _buildMetricItem(
                  '⏱️',
                  'Time',
                  '${metrics['traffic_duration_sec'] ?? 0}s',
                ),
                _buildMetricItem(
                  '📊',
                  'Demand',
                  '${(metrics['demand_score'] ?? 0).toStringAsFixed(0)}/100',
                ),
                _buildMetricItem(
                  '💧',
                  'Rain',
                  '${metrics['rainfall_mm'] ?? 0}mm',
                ),
                _buildMetricItem(
                  '📍',
                  'Type',
                  '${metrics['demand_type'] ?? 'Normal'}'.split('_').first,
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Message
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: zoneColor.withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                segment['message'] ?? 'Normal traffic conditions',
                style: TextStyle(
                  fontSize: 9,
                  color: zoneColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn();
  }

  Widget _buildMetricItem(String icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey.withOpacity(0.3), width: 1),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            icon,
            style: const TextStyle(fontSize: 16),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: const TextStyle(
              fontSize: 8,
              color: Colors.grey,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  /// Get polylines for GoogleMap
  Set<Polyline> getPolylines() => _corridorPolylines;

  /// Get markers for GoogleMap
  Set<Marker> getMarkers() => _segmentMarkers;
}
