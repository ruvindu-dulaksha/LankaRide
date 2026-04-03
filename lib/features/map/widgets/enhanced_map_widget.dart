import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:glassmorphism_ui/glassmorphism_ui.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/route_matcher_service.dart';
import '../services/poi_service.dart';
import '../services/heatmap_service.dart';

/// Enhanced Map Display Widget
///
/// Shows:
/// - Heatmap zones (RED/YELLOW/GREEN) as colored overlays
/// - POI markers (hospitals, shops, restaurants, etc.)
/// - Route information (current route + nearby routes)
/// - Real-time location matching
/// - Live demand indicators

class EnhancedMapWidget extends StatefulWidget {
  final GoogleMapController? mapController;
  final LatLng userLocation;
  final bool showHeatmap;
  final bool showPOI;

  const EnhancedMapWidget({
    super.key,
    required this.mapController,
    required this.userLocation,
    this.showHeatmap = true,
    this.showPOI = true,
  });

  @override
  State<EnhancedMapWidget> createState() => _EnhancedMapWidgetState();
}

class _EnhancedMapWidgetState extends State<EnhancedMapWidget> {
  late Set<Polygon> _heatmapPolygons;
  late Set<Marker> _poiMarkers;
  late RouteData _currentRoute;
  late List<({RouteData route, double distanceMeters})> _nearbyRoutes;
  late List<POIData> _nearbyPOI;
  late List<HeatmapZone> _currentZones;

  @override
  void initState() {
    super.initState();
    _initializeMapData();
  }

  void _initializeMapData() {
    // Match GPS to route
    final matchResult = RouteMatcherService.findNearestRoute(
      widget.userLocation.latitude,
      widget.userLocation.longitude,
    );
    _currentRoute = matchResult.route;

    // Find nearby routes (within 1km)
    _nearbyRoutes = RouteMatcherService.findRoutesWithinRadius(
      widget.userLocation.latitude,
      widget.userLocation.longitude,
      1000, // 1km radius
    );

    // Find nearby POI (within 2km)
    _nearbyPOI = POIService.getPOIWithinRadius(
      widget.userLocation.latitude,
      widget.userLocation.longitude,
      2000,
    );

    // Get zones at current location
    _currentZones = HeatmapVisualizationService.getZonesAtLocation(
      widget.userLocation,
    );

    // Build markers and polygons
    _buildHeatmapPolygons();
    _buildPOIMarkers();
  }

  void _buildHeatmapPolygons() {
    _heatmapPolygons = {};
    int index = 0;

    for (final zone in HeatmapVisualizationService.heatmapZones) {
      _heatmapPolygons.add(
        HeatmapVisualizationService.createZonePolygon(zone, index),
      );
      index++;
    }
  }

  void _buildPOIMarkers() {
    _poiMarkers = {};

    for (final poi in _nearbyPOI) {
      final markerColor = POIService.getColorByDemand(poi.demandScore);

      _poiMarkers.add(
        Marker(
          markerId: MarkerId('poi_${poi.name}'),
          position: LatLng(poi.latitude, poi.longitude),
          infoWindow: InfoWindow(
            title: poi.name,
            snippet:
                '${poi.category} • Demand: ${poi.demandScore.toStringAsFixed(0)}/100',
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            _getHueFromColor(markerColor),
          ),
        ),
      );
    }
  }

  double _getHueFromColor(Color color) {
    // Convert Flutter color to Google Maps hue
    if (color == const Color(0xFF1976D2)) return 240; // Blue
    if (color == const Color(0xFF42A5F5)) return 200; // Light blue
    if (color == const Color(0xFF66BB6A)) return 120; // Green
    return 0; // Default
  }

  @override
  void didUpdateWidget(EnhancedMapWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userLocation != widget.userLocation) {
      _initializeMapData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Map with heatmap and POI
        _buildMapLayer(),

        // Bottom info panel
        Positioned(
          bottom: 20,
          left: 16,
          right: 16,
          child: _buildEnhancedInfoPanel(context),
        ),

        // Top status bar
        Positioned(
          top: 12,
          left: 16,
          right: 16,
          child: _buildStatusBar(context),
        ),
      ],
    );
  }

  Widget _buildMapLayer() {
    // This would normally be in a GoogleMap widget
    // But here we're showing the overlay components
    return Container(
      color: Colors.grey[900],
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Map would render here with:',
              style: TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(
              'Polygons: ${_heatmapPolygons.length} zones',
              style: const TextStyle(color: Colors.grey),
            ),
            Text(
              'POI Markers: ${_poiMarkers.length} points',
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: [
                _buildZoneBadge('RED', Colors.red),
                _buildZoneBadge('YELLOW', Colors.orange),
                _buildZoneBadge('GREEN', Colors.green),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildZoneBadge(String zone, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.3),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        zone,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 11,
        ),
      ),
    );
  }

  Widget _buildStatusBar(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return GlassContainer(
      blur: 15,
      opacity: 0.15,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: (isDarkMode ? Colors.white : Colors.black).withOpacity(0.2),
        width: 1,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: isDarkMode
              ? Colors.black.withOpacity(0.2)
              : Colors.white.withOpacity(0.2),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '📍 ${_currentRoute.name}',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'Type: ${_currentRoute.type} • Capacity: ${_currentRoute.parkCapacity}',
                    style: Theme.of(
                      context,
                    ).textTheme.labelSmall?.copyWith(fontSize: 9),
                  ),
                ],
              ),
            ),
            Text(
              _currentZones.isNotEmpty
                  ? _currentZones[0].zoneType == 'RED'
                        ? '🔴'
                        : _currentZones[0].zoneType == 'YELLOW'
                        ? '🟡'
                        : '🟢'
                  : '⚪',
              style: const TextStyle(fontSize: 20),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 500.ms);
  }

  Widget _buildEnhancedInfoPanel(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return GlassContainer(
      blur: 20,
      opacity: 0.2,
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
            // Current location info
            _buildInfoSection(
              context,
              '🧭 Current Location',
              _buildLocationDetails(),
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),

            // Nearby routes
            _buildInfoSection(
              context,
              '🛣️ Nearby Routes (${_nearbyRoutes.length})',
              _buildNearbyRoutesList(),
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),

            // Nearby POI hotspots
            _buildInfoSection(
              context,
              '📌 Hotspots (${_nearbyPOI.length})',
              _buildHotspotsList(),
            ),
          ],
        ),
      ),
    ).animate().slideY(begin: 0.3, duration: 600.ms).fadeIn();
  }

  Widget _buildInfoSection(BuildContext context, String title, Widget content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        content,
      ],
    );
  }

  Widget _buildLocationDetails() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildDetailRow('Route', _currentRoute.name),
        _buildDetailRow('Type', _currentRoute.type.toUpperCase()),
        _buildDetailRow('Capacity', '${_currentRoute.parkCapacity}'),
        _buildDetailRow('POI Density', '${_currentRoute.poiDensity}'),
        _buildDetailRow(
          'Union Risk',
          _currentRoute.unionRiskLevel ?? 'INFO_PENDING',
        ),
      ],
    );
  }

  Widget _buildNearbyRoutesList() {
    if (_nearbyRoutes.isEmpty) {
      return Text(
        'No nearby routes',
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: Colors.grey),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _nearbyRoutes.take(3).map((item) {
        final route = item.route;
        final distance = item.distanceMeters;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.15),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.blue.withOpacity(0.5)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                route.name,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 10,
                ),
              ),
              Text(
                '${distance.toStringAsFixed(0)}m away',
                style: const TextStyle(fontSize: 9, color: Colors.grey),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildHotspotsList() {
    final hotspots = _nearbyPOI.where((p) => p.demandScore >= 75).toList();

    if (hotspots.isEmpty) {
      return Text(
        'No high-demand hotspots nearby',
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: Colors.grey),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: hotspots.take(4).map((poi) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.orange.withOpacity(0.15),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.orange.withOpacity(0.5)),
          ),
          child: Text(
            '${POIService.getIconByCategory(poi.category)} ${poi.name}',
            style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w500),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
          Text(
            value,
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
