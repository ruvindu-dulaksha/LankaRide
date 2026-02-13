import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:math' as math;
import '../models/driver_model.dart';

// Firebase instance
final firebaseProvider = Provider<FirebaseFirestore>((ref) {
  return FirebaseFirestore.instance;
});

// Provider to fetch active drivers nearby (from users collection)
final activeDriversProvider =
    StreamProvider.family<List<DriverModel>, Map<String, dynamic>>((
      ref,
      params,
    ) {
      final db = ref.watch(firebaseProvider);
      final userLat = params['latitude'] as double;
      final userLng = params['longitude'] as double;
      final radiusKm =
          params['radiusKm'] as double? ?? 5.0; // Default 5km radius

      // Optimized query with proper indexing and limits
      return db
          .collection('users')
          .where('is_live', isEqualTo: true)
          .orderBy(
            'last_updated',
            descending: true,
          ) // Show recently active first
          .limit(50) // Limit to 50 drivers max for performance
          .snapshots()
          .map((snapshot) {
            final drivers = snapshot.docs
                .map((doc) => DriverModel.fromFirestore(doc))
                .where((driver) {
                  // Only drivers with valid coordinates
                  if ((driver.latitude ?? 0.0) == 0.0 ||
                      (driver.longitude ?? 0.0) == 0.0) {
                    return false;
                  }

                  // Fast distance calculation
                  final lat1 = userLat;
                  final lat2 = driver.latitude ?? 0.0;
                  final lng1 = userLng;
                  final lng2 = driver.longitude ?? 0.0;

                  final distance = math.sqrt(
                    (lat1 - lat2) * (lat1 - lat2) +
                        (lng1 - lng2) * (lng1 - lng2),
                  );

                  // Rough approximation: 1 degree ≈ 111 km
                  final distanceKm = distance * 111;
                  return distanceKm <= radiusKm;
                })
                .toList();

            return drivers;
          });
    });

// Provider to get all online drivers count
final onlineDriversCountProvider = StreamProvider<int>((ref) {
  final db = ref.watch(firebaseProvider);

  return db
      .collection('users')
      .where('is_live', isEqualTo: true)
      .snapshots()
      .map((snapshot) => snapshot.docs.length);
});

// Function to update driver location
Future<void> updateDriverLocation({
  required String driverId,
  required double latitude,
  required double longitude,
}) async {
  await FirebaseFirestore.instance.collection('users').doc(driverId).set({
    'latitude': latitude,
    'longitude': longitude,
    'last_updated': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
}

// Function to set driver as live
Future<void> setDriverLive({
  required String driverId,
  required bool isLive,
}) async {
  await FirebaseFirestore.instance.collection('users').doc(driverId).set({
    'is_live': isLive,
    'last_updated': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
}
