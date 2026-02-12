import 'package:cloud_firestore/cloud_firestore.dart';

class DriverModel {
  final String id;
  final String name;
  final String email;
  final String phone;
  final double? latitude;
  final double? longitude;
  final bool isLive;
  final String? vehicleColor;
  final String? licensePlate;
  final double rating;
  final int totalTrips;
  final DateTime lastUpdated;
  final String? photoPath;

  DriverModel({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.latitude,
    required this.longitude,
    required this.isLive,
    this.vehicleColor,
    this.licensePlate,
    required this.rating,
    required this.totalTrips,
    required this.lastUpdated,
    this.photoPath,
  });

  // Convert from Firestore user document
  factory DriverModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return DriverModel(
      id: doc.id,
      name: data['name'] ?? 'Unknown Driver',
      email: data['email'] ?? '',
      phone: data['phone'] ?? '',
      latitude: (data['latitude'] ?? 0.0).toDouble(),
      longitude: (data['longitude'] ?? 0.0).toDouble(),
      isLive: data['is_live'] ?? false,
      vehicleColor: data['vehicle_color'],
      licensePlate: data['license_plate'],
      rating: (data['rating'] ?? 0.0).toDouble(),
      totalTrips: data['total_trips'] ?? 0,
      lastUpdated: data['last_updated'] is Timestamp
          ? (data['last_updated'] as Timestamp).toDate()
          : DateTime.now(),
      photoPath: data['photo_path'],
    );
  }

  // Convert to map for Firestore
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'email': email,
      'phone': phone,
      'latitude': latitude,
      'longitude': longitude,
      'is_live': isLive,
      'vehicle_color': vehicleColor,
      'license_plate': licensePlate,
      'rating': rating,
      'total_trips': totalTrips,
      'last_updated': FieldValue.serverTimestamp(),
      'photo_path': photoPath,
    };
  }
}
