import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../widgets/driver_feedback_panel.dart';

/// Service to handle driver feedback storage and analytics
class DriverFeedbackService {
  static final _firestore = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;

  /// Submit driver feedback to Firestore
  static Future<bool> submitFeedback({
    required FeatureRating rating,
    String? comment,
    required String driverId,
  }) async {
    try {
      final feedbackRef = _firestore
          .collection('drivers')
          .doc(driverId)
          .collection('feedback');

      await feedbackRef.add({
        'feature': rating.featureName,
        'rating': rating.rating,
        'category': rating.category,
        'comment': comment ?? '',
        'timestamp': FieldValue.serverTimestamp(),
        'driver_id': driverId,
      });

      // Also store in global feedback collection for analytics
      await _firestore.collection('feedback_analytics').add({
        'feature': rating.featureName,
        'rating': rating.rating,
        'category': rating.category,
        'comment': comment ?? '',
        'timestamp': FieldValue.serverTimestamp(),
        'driver_id': driverId,
      });

      return true;
    } catch (e) {
      print('Error submitting feedback: $e');
      return false;
    }
  }

  /// Get all feedback for a specific feature
  static Future<List<FeatureRating>> getFeatureRatings(
    String featureName,
  ) async {
    try {
      final snapshot = await _firestore
          .collection('feedback_analytics')
          .where('feature', isEqualTo: featureName)
          .orderBy('timestamp', descending: true)
          .limit(100)
          .get();

      return snapshot.docs
          .map(
            (doc) => FeatureRating(
              featureName: doc['feature'] as String,
              rating: doc['rating'] as int,
              category: doc['category'] as String,
              timestamp: (doc['timestamp'] as Timestamp).toDate(),
            ),
          )
          .toList();
    } catch (e) {
      print('Error fetching feature ratings: $e');
      return [];
    }
  }

  /// Get aggregate feedback statistics
  static Future<Map<String, dynamic>> getFeedbackStatistics() async {
    try {
      final snapshot = await _firestore.collection('feedback_analytics').get();

      if (snapshot.docs.isEmpty) {
        return {
          'total': 0,
          'average_rating': 0.0,
          'positive_percentage': 0,
          'by_feature': {},
        };
      }

      final allRatings = snapshot.docs
          .map((doc) => doc['rating'] as int)
          .toList();
      final avgRating =
          allRatings.fold<double>(0, (sum, r) => sum + r) / allRatings.length;
      final positiveCount = allRatings.where((r) => r >= 4).length;
      final positivePercentage = (positiveCount / allRatings.length * 100)
          .toInt();

      // Group by feature
      final byFeature = <String, Map<String, dynamic>>{};
      for (final doc in snapshot.docs) {
        final feature = doc['feature'] as String;
        final rating = doc['rating'] as int;

        byFeature.putIfAbsent(
          feature,
          () => {'total': 0, 'sum': 0, 'ratings': <int>[]},
        );

        byFeature[feature]!['total']++;
        byFeature[feature]!['sum'] += rating;
        (byFeature[feature]!['ratings'] as List<int>).add(rating);
      }

      // Calculate per-feature averages
      final featureStats = <String, dynamic>{};
      byFeature.forEach((feature, data) {
        final avg = data['sum'] / data['total'];
        featureStats[feature] = {
          'average': double.parse(avg.toStringAsFixed(2)),
          'count': data['total'],
          'positive':
              data['ratings'].where((r) => r >= 4).length / data['total'] * 100,
        };
      });

      return {
        'total': allRatings.length,
        'average_rating': double.parse(avgRating.toStringAsFixed(2)),
        'positive_percentage': positivePercentage,
        'by_feature': featureStats,
      };
    } catch (e) {
      print('Error fetching statistics: $e');
      return {};
    }
  }

  /// Get driver's feedback history
  static Future<List<FeatureRating>> getDriverFeedbackHistory(
    String driverId,
  ) async {
    try {
      final snapshot = await _firestore
          .collection('drivers')
          .doc(driverId)
          .collection('feedback')
          .orderBy('timestamp', descending: true)
          .get();

      return snapshot.docs
          .map(
            (doc) => FeatureRating(
              featureName: doc['feature'] as String,
              rating: doc['rating'] as int,
              category: doc['category'] as String,
              timestamp: (doc['timestamp'] as Timestamp).toDate(),
            ),
          )
          .toList();
    } catch (e) {
      print('Error fetching driver feedback: $e');
      return [];
    }
  }

  /// Check if driver has already rated a feature recently
  static Future<bool> hasRecentFeedback(
    String driverId,
    String featureName, {
    Duration duration = const Duration(hours: 1),
  }) async {
    try {
      final cutoffTime = DateTime.now().subtract(duration);

      final snapshot = await _firestore
          .collection('drivers')
          .doc(driverId)
          .collection('feedback')
          .where('feature', isEqualTo: featureName)
          .where('timestamp', isGreaterThan: cutoffTime)
          .limit(1)
          .get();

      return snapshot.docs.isNotEmpty;
    } catch (e) {
      print('Error checking recent feedback: $e');
      return false;
    }
  }

  /// Get top-rated and lowest-rated features
  static Future<Map<String, List<String>>> getFeatureRankings() async {
    try {
      final stats = await getFeedbackStatistics();
      final byFeature = stats['by_feature'] as Map<String, dynamic>;

      if (byFeature.isEmpty) {
        return {'top': [], 'bottom': []};
      }

      final sorted =
          (byFeature.entries.toList()..sort(
                (a, b) => (b.value['average'] as double).compareTo(
                  a.value['average'] as double,
                ),
              ))
              .map((e) => e.key)
              .toList();

      return {
        'top': sorted.take(3).toList(),
        'bottom': sorted.reversed.take(3).toList(),
      };
    } catch (e) {
      print('Error getting feature rankings: $e');
      return {'top': [], 'bottom': []};
    }
  }
}
