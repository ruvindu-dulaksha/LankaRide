import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../services/hotspot_service.dart';

/// Widget to display hotspot visualization on map
class HotspotVisualization extends StatelessWidget {
  final List<Hotspot> hotspots;
  final Function(Hotspot)? onHotspotTapped;

  const HotspotVisualization({
    super.key,
    required this.hotspots,
    this.onHotspotTapped,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Hotspot circles on map (drawn as custom circles)
        for (final hotspot in hotspots)
          Positioned(child: _buildHotspotMarker(context, hotspot)),
      ],
    );
  }

  Widget _buildHotspotMarker(BuildContext context, Hotspot hotspot) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: () => onHotspotTapped?.call(hotspot),
      child: Tooltip(
        message:
            '${hotspot.label}\nIntensity: ${(hotspot.intensity * 100).toStringAsFixed(0)}%\nDrivers: ${hotspot.driverCount}',
        child: Container(
          width: hotspot.size,
          height: hotspot.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Color(hotspot.getColor()).withOpacity(hotspot.opacity * 0.6),
            border: Border.all(
              color: Color(hotspot.getColor()).withOpacity(hotspot.opacity),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Color(
                  hotspot.getColor(),
                ).withOpacity(hotspot.opacity * 0.3),
                blurRadius: 8 + (hotspot.intensity * 8),
                spreadRadius: 2 + (hotspot.intensity * 4),
              ),
            ],
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildHotspotIcon(hotspot.type),
                if (hotspot.driverCount > 0)
                  Text(
                    '${hotspot.driverCount}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHotspotIcon(String type) {
    switch (type) {
      case 'high_demand':
        return const Text('📍', style: TextStyle(fontSize: 14));
      case 'traffic':
        return const Text('🚗', style: TextStyle(fontSize: 14));
      case 'accident':
        return const Text('⚠️', style: TextStyle(fontSize: 14));
      case 'weather':
        return const Text('🌧️', style: TextStyle(fontSize: 14));
      default:
        return const Text(
          '•',
          style: TextStyle(fontSize: 16, color: Colors.white),
        );
    }
  }

  /// Generate circles for map display
  Set<Circle> generateHotspotCircles() {
    return {
      for (final hotspot in hotspots)
        Circle(
          circleId: CircleId(
            'hotspot_${hotspot.location.latitude}_${hotspot.location.longitude}',
          ),
          center: hotspot.location,
          radius: 100 + (hotspot.intensity * 200),
          fillColor: Color(hotspot.getColor()).withOpacity(0.2),
          strokeColor: Color(hotspot.getColor()).withOpacity(0.8),
          strokeWidth: 2,
        ),
    };
  }

  /// Generate markers for map display
  Set<Marker> generateHotspotMarkers() {
    return {
      for (final hotspot in hotspots)
        Marker(
          markerId: MarkerId('hotspot_${hotspot.label}'),
          position: hotspot.location,
          infoWindow: InfoWindow(
            title: hotspot.label,
            snippet:
                'Intensity: ${(hotspot.intensity * 100).toStringAsFixed(0)}%',
          ),
        ),
    };
  }
}

/// Panel to show hotspot summary and legend
class HotspotLegendPanel extends StatelessWidget {
  final List<Hotspot> hotspots;
  final bool isVisible;
  final VoidCallback onClose;

  const HotspotLegendPanel({
    super.key,
    required this.hotspots,
    required this.isVisible,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    if (!isVisible) return const SizedBox();

    final groupedHotspots = <String, List<Hotspot>>{};
    for (final hotspot in hotspots) {
      groupedHotspots.putIfAbsent(hotspot.type, () => []).add(hotspot);
    }

    return Positioned(
      top: 80,
      right: 16,
      width: 280,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.withOpacity(0.3), width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '🔥 Active Hotspots',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: onClose,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const Divider(height: 8),
            ...groupedHotspots.entries.map((entry) {
              final type = entry.key;
              final spots = entry.value;
              final icon = _getTypeIcon(type);
              final count = spots.length;
              final avgIntensity =
                  spots.fold(0.0, (sum, h) => sum + h.intensity) / spots.length;

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Text(icon, style: const TextStyle(fontSize: 14)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            type.replaceAll('_', ' ').toUpperCase(),
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '$count hotspots • ${(avgIntensity * 100).toStringAsFixed(0)}% avg intensity',
                            style: TextStyle(
                              fontSize: 9,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 8),
            Text(
              'Total: ${hotspots.length} hotspots detected',
              style: TextStyle(
                fontSize: 9,
                color: Colors.grey[600],
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getTypeIcon(String type) {
    switch (type) {
      case 'high_demand':
        return '📍';
      case 'traffic':
        return '🚗';
      case 'accident':
        return '⚠️';
      case 'weather':
        return '🌧️';
      default:
        return '•';
    }
  }
}
