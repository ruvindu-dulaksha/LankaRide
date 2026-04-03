import 'package:flutter/material.dart';
import 'package:glassmorphism_ui/glassmorphism_ui.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/route_analysis_service.dart';

/// Route Corridor Analysis Screen
///
/// Shows the driver:
/// - Overall route safety (RED/YELLOW/GREEN)
/// - Risk level at EACH SEGMENT
/// - Location-specific metrics
/// - NOT just the starting point!
///
/// Example: Borella → B'mich (7 waypoints analyzed)

class RouteCorridorAnalysisScreen extends StatefulWidget {
  final double startLat;
  final double startLon;
  final double endLat;
  final double endLon;
  final String startLocationName;
  final String endLocationName;

  const RouteCorridorAnalysisScreen({
    super.key,
    required this.startLat,
    required this.startLon,
    required this.endLat,
    required this.endLon,
    required this.startLocationName,
    required this.endLocationName,
  });

  @override
  State<RouteCorridorAnalysisScreen> createState() =>
      _RouteCorridorAnalysisScreenState();
}

class _RouteCorridorAnalysisScreenState
    extends State<RouteCorridorAnalysisScreen> {
  late Future<RouteAnalysis> _analysisFuture;

  @override
  void initState() {
    super.initState();
    _analysisFuture = _analyzeRoute();
  }

  Future<RouteAnalysis> _analyzeRoute() async {
    try {
      final response = await RouteAnalysisService.analyzeRouteCorridor(
        startLat: widget.startLat,
        startLon: widget.startLon,
        endLat: widget.endLat,
        endLon: widget.endLon,
      );

      return RouteAnalysisService.parseResponse(response);
    } catch (e) {
      rethrow;
    }
  }

  Color _getZoneColor(String zone) {
    switch (zone) {
      case 'RED':
        return Colors.red;
      case 'YELLOW':
        return Colors.orange;
      case 'GREEN':
        return Colors.greenAccent;
      default:
        return Colors.grey;
    }
  }

  String _getZoneEmoji(String zone) {
    switch (zone) {
      case 'RED':
        return '🔴';
      case 'YELLOW':
        return '🟡';
      case 'GREEN':
        return '🟢';
      default:
        return '⚪';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDarkMode ? Colors.black : Colors.grey[50],
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Route Corridor Analysis'),
            Text(
              '${widget.startLocationName} → ${widget.endLocationName}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: FutureBuilder<RouteAnalysis>(
        future: _analysisFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return _buildLoadingState();
          }

          if (snapshot.hasError) {
            return _buildErrorState(snapshot.error.toString());
          }

          if (!snapshot.hasData) {
            return _buildErrorState('No data received');
          }

          final analysis = snapshot.data!;
          return _buildAnalysisView(context, analysis, isDarkMode);
        },
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            '🧭 Analyzing route corridor...',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'Checking ${widget.startLocationName} to ${widget.endLocationName}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('❌ Analysis Error', style: TextStyle(fontSize: 20)),
            const SizedBox(height: 16),
            Text(error, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => setState(() {
                _analysisFuture = _analyzeRoute();
              }),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnalysisView(
    BuildContext context,
    RouteAnalysis analysis,
    bool isDarkMode,
  ) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Overall route safety card
            _buildOverallCard(context, analysis, isDarkMode),
            const SizedBox(height: 24),

            // Route context
            _buildContextCard(context, analysis, isDarkMode),
            const SizedBox(height: 24),

            // Segment-by-segment analysis
            _buildSegmentsHeader(context),
            const SizedBox(height: 12),
            ..._buildSegmentCards(context, analysis, isDarkMode),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildOverallCard(
    BuildContext context,
    RouteAnalysis analysis,
    bool isDarkMode,
  ) {
    final zoneColor = _getZoneColor(analysis.overallZone);
    final zoneEmoji = _getZoneEmoji(analysis.overallZone);

    return GlassContainer(
      blur: 20,
      opacity: 0.2,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: (isDarkMode ? Colors.white : Colors.black).withOpacity(0.2),
        width: 1.5,
      ),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: zoneColor.withOpacity(0.1),
          border: Border(left: BorderSide(color: zoneColor, width: 4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Overall Route Safety',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(zoneEmoji, style: const TextStyle(fontSize: 32)),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              analysis.overallZone,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: zoneColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              analysis.overallMessage,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildMetricBadge(context, '⚠️ Risk Level', analysis.riskLevel),
                _buildMetricBadge(
                  context,
                  '🧭 Segments',
                  analysis.corridorSegments.toString(),
                ),
                _buildMetricBadge(
                  context,
                  '🚗 Avg Capacity',
                  analysis.corridorCapacityAvg,
                ),
              ],
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 600.ms).slideY(begin: 0.2);
  }

  Widget _buildContextCard(
    BuildContext context,
    RouteAnalysis analysis,
    bool isDarkMode,
  ) {
    final summary = analysis.routeSummary;
    final hour = summary.hour;
    final timeStr = '${hour.toString().padLeft(2, '0')}:00';

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
              ? Colors.blue.withOpacity(0.1)
              : Colors.blue.withOpacity(0.05),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '🕐 Route Context',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildContextItem('Time', timeStr),
                _buildContextItem(
                  'Day',
                  summary.isWeekend ? 'Weekend' : 'Weekday',
                ),
                _buildContextItem(
                  'School',
                  summary.schoolClosed ? 'Closed' : 'Open',
                ),
                _buildContextItem(
                  'Rain',
                  '${summary.rainfallMm.toStringAsFixed(1)}mm',
                ),
              ],
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 600.ms);
  }

  Widget _buildContextItem(String label, String value) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
      ],
    );
  }

  Widget _buildSegmentsHeader(BuildContext context) {
    return const Row(
      children: [
        Text('📍 Segment Analysis', style: TextStyle(fontSize: 16)),
        Text(
          ' (7 waypoints)',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ],
    );
  }

  List<Widget> _buildSegmentCards(
    BuildContext context,
    RouteAnalysis analysis,
    bool isDarkMode,
  ) {
    return List.generate(analysis.segmentDetails.length, (index) {
      final segment = analysis.segmentDetails[index];
      final zoneColor = _getZoneColor(segment.zone);
      final zoneEmoji = _getZoneEmoji(segment.zone);

      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child:
            GlassContainer(
                  blur: 15,
                  opacity: 0.15,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: (isDarkMode ? Colors.white : Colors.black)
                        .withOpacity(0.2),
                    width: 1,
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: zoneColor.withOpacity(0.05),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header with segment number and zone
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      segment.segment,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(width: 8),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      segment.location,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                    Text(
                                      '(${segment.lat.toStringAsFixed(4)}, ${segment.lon.toStringAsFixed(4)})',
                                      style: const TextStyle(
                                        fontSize: 9,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            Text(
                              zoneEmoji,
                              style: const TextStyle(fontSize: 20),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        // Zone and message
                        Text(
                          segment.zone,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: zoneColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          segment.message,
                          style: Theme.of(context).textTheme.labelSmall,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 10),

                        // Metrics grid
                        _buildSegmentMetricsGrid(context, segment),
                      ],
                    ),
                  ),
                )
                .animate(delay: Duration(milliseconds: 50 * index))
                .fadeIn()
                .slideX(begin: -0.2, end: 0),
      );
    });
  }

  Widget _buildSegmentMetricsGrid(BuildContext context, SegmentDetail segment) {
    final metrics = segment.metrics;

    return Wrap(
      spacing: 10,
      runSpacing: 8,
      children: [
        _buildMetricChip('Union Cap', metrics.unionCapacity.toString()),
        _buildMetricChip('POI', metrics.poiDensity.toString()),
        _buildMetricChip('Traffic', '${metrics.trafficDurationSec}s'),
        _buildMetricChip('Demand', metrics.demandScore.toStringAsFixed(0)),
        _buildMetricChip('Rain', '${metrics.rainfallMm.toStringAsFixed(1)}mm'),
      ],
    );
  }

  Widget _buildMetricChip(String label, String value) {
    return Chip(
      label: Text('$label: $value', style: const TextStyle(fontSize: 10)),
      backgroundColor: Colors.grey.withOpacity(0.2),
    );
  }

  Widget _buildMetricBadge(BuildContext context, String label, String value) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
        ),
      ],
    );
  }
}
