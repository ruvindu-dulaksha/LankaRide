import 'package:flutter/material.dart';
import 'package:glassmorphism_ui/glassmorphism_ui.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/poi_service.dart';

/// Enhanced Map Legend Widget
///
/// Shows:
/// - Heatmap zone color meanings (RED/YELLOW/GREEN)
/// - POI demand colors and indicators
/// - Route information and statistics
/// - Real-time zone status
/// - Interactive legend with filtering options

class EnhancedMapLegend extends StatefulWidget {
  final int nearbyDriversCount;
  final double rainLevel;
  final String? currentZone;
  final VoidCallback? onToggleHeatmap;
  final VoidCallback? onTogglePOI;

  const EnhancedMapLegend({
    super.key,
    required this.nearbyDriversCount,
    required this.rainLevel,
    this.currentZone,
    this.onToggleHeatmap,
    this.onTogglePOI,
  });

  @override
  State<EnhancedMapLegend> createState() => _EnhancedMapLegendState();
}

class _EnhancedMapLegendState extends State<EnhancedMapLegend> {
  late bool _showHeatmap;
  late bool _showPOI;

  @override
  void initState() {
    super.initState();
    _showHeatmap = true;
    _showPOI = true;
  }

  void _toggleHeatmap() {
    setState(() => _showHeatmap = !_showHeatmap);
    widget.onToggleHeatmap?.call();
  }

  void _togglePOI() {
    setState(() => _showPOI = !_showPOI);
    widget.onTogglePOI?.call();
  }

  @override
  Widget build(BuildContext context) {
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
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Text(
                '🗺️ Map Legend',
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),

              // Heatmap zones
              _buildHeatmapLegend(context),
              const SizedBox(height: 16),

              // POI demand colors
              _buildPOIDemandLegend(context),
              const SizedBox(height: 16),

              // Toggle buttons
              _buildToggleButtons(context),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),

              // Stats
              _buildStatRow(
                context,
                icon: Icons.directions_car,
                label: 'Drivers Nearby',
                value: widget.nearbyDriversCount.toString(),
                color: Colors.blue,
              ),
              const SizedBox(height: 8),
              _buildStatRow(
                context,
                icon: Icons.water_drop,
                label: 'Rain Level',
                value: '${widget.rainLevel.toStringAsFixed(1)}mm',
                color: Colors.cyan,
              ),
              const SizedBox(height: 8),
              _buildStatRow(
                context,
                icon: Icons.location_on,
                label: 'Current Zone',
                value: widget.currentZone ?? 'Unknown',
                color: Colors.green,
              ),
              const SizedBox(height: 8),
              _buildStatRow(
                context,
                icon: Icons.pin_drop,
                label: 'Total POI',
                value: POIService.poiList.length.toString(),
                color: Colors.orange,
              ),
            ],
          ),
        ),
      ),
    ).animate().fadeIn(duration: 600.ms).slideX(begin: -0.1);
  }

  Widget _buildHeatmapLegend(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '🔥 Heatmap Zones',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.bold,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 8),
        _buildHeatmapZoneItem(
          '🔴 RED',
          'High Risk',
          'Very high demand, heavy traffic',
          Colors.red,
        ),
        const SizedBox(height: 6),
        _buildHeatmapZoneItem(
          '🟡 YELLOW',
          'Caution Zone',
          'Moderate demand, medium traffic',
          Colors.orange,
        ),
        const SizedBox(height: 6),
        _buildHeatmapZoneItem(
          '🟢 GREEN',
          'Safe Zone',
          'Low demand, light traffic',
          Colors.green,
        ),
      ],
    );
  }

  Widget _buildHeatmapZoneItem(
    String label,
    String title,
    String description,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        border: Border.all(color: color.withOpacity(0.5), width: 0.5),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  description,
                  style: const TextStyle(fontSize: 8, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPOIDemandLegend(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '📌 POI Demand Level',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.bold,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 8),
        _buildDemandIndicator('Very High', '85+', const Color(0xFF1976D2)),
        const SizedBox(height: 4),
        _buildDemandIndicator('High', '75-84', const Color(0xFF42A5F5)),
        const SizedBox(height: 4),
        _buildDemandIndicator('Medium', '60-74', const Color(0xFF66BB6A)),
        const SizedBox(height: 4),
        _buildDemandIndicator('Low', '<60', const Color(0xFF78909C)),
      ],
    );
  }

  Widget _buildDemandIndicator(String label, String range, Color color) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600),
        ),
        const SizedBox(width: 4),
        Text(range, style: const TextStyle(fontSize: 8, color: Colors.grey)),
      ],
    );
  }

  Widget _buildToggleButtons(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _buildToggleButton('🔥 Heatmap', _showHeatmap, _toggleHeatmap),
        ),
        const SizedBox(width: 8),
        Expanded(child: _buildToggleButton('📌 POI', _showPOI, _togglePOI)),
      ],
    );
  }

  Widget _buildToggleButton(
    String label,
    bool isEnabled,
    VoidCallback onToggle,
  ) {
    return GestureDetector(
      onTap: onToggle,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: isEnabled
              ? Colors.blue.withOpacity(0.2)
              : Colors.grey.withOpacity(0.1),
          border: Border.all(
            color: isEnabled
                ? Colors.blue.withOpacity(0.5)
                : Colors.grey.withOpacity(0.3),
            width: 0.5,
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 9,
              color: isEnabled ? Colors.blue : Colors.grey,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(fontSize: 9, color: Colors.grey),
            ),
          ],
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            value,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}
