import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Service to handle driver hotspot visit outcomes and heat map generation
class DriverFeedbackService {
  static final _firestore = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;

  // Instance variables
  late final FirebaseFirestore _fs;

  DriverFeedbackService() {
    _fs = FirebaseFirestore.instance;
  }

  /// Record hotspot visit outcome (did driver get a hire?)
  Future<bool> recordHotspotOutcome({
    required String hotspotLabel,
    required LatLng location,
    required String driverId,
    required bool hireObtained,
    required double earnings,
    required String hotspotType,
  }) async {
    try {
      final visitRef = _fs.collection('hotspot_visits').add({
        'driver_id': driverId,
        'hotspot_label': hotspotLabel,
        'hotspot_type': hotspotType,
        'location': {
          'latitude': location.latitude,
          'longitude': location.longitude,
        },
        'visit_timestamp': FieldValue.serverTimestamp(),
        'hire_obtained': hireObtained,
        'earnings': earnings,
        'success': hireObtained ? 1 : 0, // For easy aggregation
      });

      // Also update hotspot stats
      await _updateHotspotStats(hotspotLabel, hireObtained, earnings);

      return true;
    } catch (e) {
      print('Error recording hotspot outcome: $e');
      return false;
    }
  }

  /// Update aggregate statistics for a hotspot
  Future<void> _updateHotspotStats(
    String hotspotLabel,
    bool hireObtained,
    double earnings,
  ) async {
    try {
      final hotspotQuery = await _fs
          .collection('hotspot_stats')
          .where('label', isEqualTo: hotspotLabel)
          .limit(1)
          .get();

      if (hotspotQuery.docs.isNotEmpty) {
        // Update existing stats
        final docRef = hotspotQuery.docs[0].reference;
        final data = hotspotQuery.docs[0].data();

        final totalVisits = (data['total_visits'] as int? ?? 0) + 1;
        final successCount =
            (data['successful_hires'] as int? ?? 0) + (hireObtained ? 1 : 0);
        final totalEarnings =
            (data['total_earnings'] as double? ?? 0.0) + earnings;

        await docRef.update({
          'total_visits': totalVisits,
          'successful_hires': successCount,
          'total_earnings': totalEarnings,
          'success_rate': (successCount / totalVisits * 100).toStringAsFixed(1),
          'avg_earnings': (totalEarnings / successCount).toStringAsFixed(2),
          'last_updated': FieldValue.serverTimestamp(),
        });
      } else {
        // Create new stats
        await _fs.collection('hotspot_stats').add({
          'label': hotspotLabel,
          'total_visits': 1,
          'successful_hires': hireObtained ? 1 : 0,
          'total_earnings': earnings,
          'success_rate': hireObtained ? '100.0' : '0.0',
          'avg_earnings': hireObtained ? earnings.toStringAsFixed(2) : '0.0',
          'created_at': FieldValue.serverTimestamp(),
          'last_updated': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      print('Error updating hotspot stats: $e');
    }
  }

  /// Get success rate for a specific hotspot
  Future<double> getHotspotSuccessRate(String hotspotLabel) async {
    try {
      final doc = await _fs
          .collection('hotspot_stats')
          .where('label', isEqualTo: hotspotLabel)
          .limit(1)
          .get();

      if (doc.docs.isEmpty) return 0.0;

      final successRate = doc.docs[0]['success_rate'] as String?;
      return double.tryParse(successRate ?? '0') ?? 0.0;
    } catch (e) {
      print('Error getting hotspot success rate: $e');
      return 0.0;
    }
  }

  /// Get average earnings for a hotspot
  Future<double> getHotspotAverageEarnings(String hotspotLabel) async {
    try {
      final doc = await _fs
          .collection('hotspot_stats')
          .where('label', isEqualTo: hotspotLabel)
          .limit(1)
          .get();

      if (doc.docs.isEmpty) return 0.0;

      final avgEarnings = doc.docs[0]['avg_earnings'] as String?;
      return double.tryParse(avgEarnings ?? '0') ?? 0.0;
    } catch (e) {
      print('Error getting hotspot average earnings: $e');
      return 0.0;
    }
  }

  /// Get all hotspots visited by a driver
  Future<List<HotspotVisit>> getDriverHotspotVisits(String driverId) async {
    try {
      final snapshot = await _fs
          .collection('hotspot_visits')
          .where('driver_id', isEqualTo: driverId)
          .orderBy('visit_timestamp', descending: true)
          .get();

      return snapshot.docs.map((doc) {
        final data = doc.data();
        return HotspotVisit(
          driverId: data['driver_id'] as String,
          hotspotLabel: data['hotspot_label'] as String,
          visitTimestamp: (data['visit_timestamp'] as Timestamp).toDate(),
          hireObtained: data['hire_obtained'] as bool,
          earnings: (data['earnings'] as num).toDouble(),
        );
      }).toList();
    } catch (e) {
      print('Error getting driver hotspot visits: $e');
      return [];
    }
  }

  /// Get heat map data for a geographic area
  Future<List<HeatMapPoint>> generateHeatMapData({
    double? northLat,
    double? southLat,
    double? eastLon,
    double? westLon,
  }) async {
    try {
      final hotspotStats = await _fs.collection('hotspot_stats').get();

      final heatMapPoints = <HeatMapPoint>[];

      for (final doc in hotspotStats.docs) {
        final data = doc.data();
        final successRate =
            double.tryParse(data['success_rate'] as String? ?? '0') ?? 0.0;
        final totalVisits = (data['total_visits'] as int?) ?? 0;

        heatMapPoints.add(
          HeatMapPoint(
            label: data['label'] as String,
            successRate: successRate,
            totalVisits: totalVisits,
            profitability:
                successRate *
                totalVisits /
                100, // Score based on success and popularity
            avgEarnings:
                double.tryParse(data['avg_earnings'] as String? ?? '0') ?? 0.0,
          ),
        );
      }

      // Sort by profitability (descending)
      heatMapPoints.sort((a, b) => b.profitability.compareTo(a.profitability));

      return heatMapPoints;
    } catch (e) {
      print('Error generating heat map data: $e');
      return [];
    }
  }

  /// Get trends over time (daily/weekly/monthly)
  Future<Map<String, dynamic>> getHotspotTrends(
    String hotspotLabel, {
    Duration period = const Duration(days: 7),
  }) async {
    try {
      final startDate = DateTime.now().subtract(period);

      final snapshot = await _fs
          .collection('hotspot_visits')
          .where('hotspot_label', isEqualTo: hotspotLabel)
          .where('visit_timestamp', isGreaterThan: startDate)
          .orderBy('visit_timestamp')
          .get();

      if (snapshot.docs.isEmpty) {
        return {'trend': [], 'total_visits': 0, 'recent_success_rate': 0.0};
      }

      // Group by date
      final byDate = <String, Map<String, int>>{};

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final timestamp = (data['visit_timestamp'] as Timestamp).toDate();
        final dateKey = '${timestamp.year}-${timestamp.month}-${timestamp.day}';

        byDate.putIfAbsent(dateKey, () => {'total': 0, 'success': 0});
        byDate[dateKey]!['total'] = byDate[dateKey]!['total']! + 1;
        if (data['hire_obtained'] as bool) {
          byDate[dateKey]!['success'] = byDate[dateKey]!['success']! + 1;
        }
      }

      // Calculate trend data
      final trend = byDate.entries
          .map(
            (entry) => {
              'date': entry.key,
              'visits': entry.value['total'],
              'success_rate':
                  (entry.value['success']! / entry.value['total']! * 100)
                      .toStringAsFixed(1),
            },
          )
          .toList();

      final recentSuccess = snapshot.docs
          .where((doc) => doc['hire_obtained'] as bool)
          .length;

      final recentSuccessRate = recentSuccess / snapshot.docs.length * 100;

      return {
        'trend': trend,
        'total_visits': snapshot.docs.length,
        'recent_success_rate': double.parse(
          recentSuccessRate.toStringAsFixed(1),
        ),
      };
    } catch (e) {
      print('Error getting hotspot trends: $e');
      return {};
    }
  }

  /// Get top profitable hotspots
  Future<List<ProfitableHotspot>> getTopProfitableHotspots({
    int limit = 10,
  }) async {
    try {
      final snapshot = await _fs
          .collection('hotspot_stats')
          .orderBy('total_earnings', descending: true)
          .limit(limit)
          .get();

      return snapshot.docs.map((doc) {
        final data = doc.data();
        return ProfitableHotspot(
          label: data['label'] as String,
          totalEarnings: (data['total_earnings'] as num).toDouble(),
          avgEarnings:
              double.tryParse(data['avg_earnings'] as String? ?? '0') ?? 0.0,
          successRate:
              double.tryParse(data['success_rate'] as String? ?? '0') ?? 0.0,
          totalVisits: (data['total_visits'] as int?) ?? 0,
        );
      }).toList();
    } catch (e) {
      print('Error getting top profitable hotspots: $e');
      return [];
    }
  }
}

/// Data class for hotspot visit records
class HotspotVisit {
  final String driverId;
  final String hotspotLabel;
  final DateTime visitTimestamp;
  final bool hireObtained;
  final double earnings;

  HotspotVisit({
    required this.driverId,
    required this.hotspotLabel,
    required this.visitTimestamp,
    required this.hireObtained,
    required this.earnings,
  });
}

/// Data class for heat map visualization
class HeatMapPoint {
  final String label;
  final double successRate;
  final int totalVisits;
  final double profitability;
  final double avgEarnings;

  HeatMapPoint({
    required this.label,
    required this.successRate,
    required this.totalVisits,
    required this.profitability,
    required this.avgEarnings,
  });

  /// Get color based on profitability (for heat map visualization)
  int getHeatMapColor() {
    if (profitability >= 70) {
      return 0xFF00DB24; // Green - Very profitable
    } else if (profitability >= 50) {
      return 0xFF7CFF00; // Light green - Profitable
    } else if (profitability >= 30) {
      return 0xFFFFED1C; // Yellow - Moderate
    } else if (profitability >= 10) {
      return 0xFFFFA500; // Orange - Low
    } else {
      return 0xFFFF0000; // Red - Very low/unprofitable
    }
  }
}

/// Data class for profitable hotspots
class ProfitableHotspot {
  final String label;
  final double totalEarnings;
  final double avgEarnings;
  final double successRate;
  final int totalVisits;

  ProfitableHotspot({
    required this.label,
    required this.totalEarnings,
    required this.avgEarnings,
    required this.successRate,
    required this.totalVisits,
  });
}
