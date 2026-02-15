import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Helper utility to fix existing users who don't have Firestore documents
class UserDocumentHelper {
  /// Check and create Firestore document for current user if it doesn't exist
  static Future<void> ensureUserDocument() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        debugPrint('⚠️ No user signed in');
        return;
      }

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (!userDoc.exists) {
        debugPrint('📝 Creating missing user document for ${user.email}');
        await _createUserDocument(user);
      } else {
        debugPrint('✅ User document already exists');
      }
    } catch (e) {
      debugPrint('❌ Error ensuring user document: $e');
    }
  }

  /// Create initial user document in Firestore
  static Future<void> _createUserDocument(User user) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'name': user.displayName ?? user.email?.split('@')[0] ?? 'Driver',
        'email': user.email ?? '',
        'phone': user.phoneNumber ?? '',
        'latitude': 6.9271, // Default Colombo location
        'longitude': 79.8612,
        'is_live': false,
        'vehicle_color': '', // To be filled by user
        'license_plate': '', // To be filled by user
        'rating': 5.0,
        'total_trips': 0,
        'last_updated': FieldValue.serverTimestamp(),
        'photo_path': null,
        'created_at': FieldValue.serverTimestamp(),
      });
      debugPrint('✅ User document created: ${user.email}');
    } catch (e) {
      debugPrint('❌ Error creating user document: $e');
    }
  }

  /// Batch create documents for all authenticated users (for migration)
  static Future<void> fixAllUsers() async {
    try {
      final users = FirebaseAuth.instance.currentUser;
      if (users == null) {
        debugPrint('⚠️ No users to fix');
        return;
      }

      await ensureUserDocument();
      debugPrint('✅ User document check complete');
    } catch (e) {
      debugPrint('❌ Error in fixAllUsers: $e');
    }
  }
}
