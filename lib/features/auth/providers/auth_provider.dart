import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lanka_ride/core/constants/app_constants.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Auth State Provider (Firebase)
final authStateProvider = StreamProvider<User?>((ref) {
  try {
    // Check if Firebase is initialized
    if (Firebase.apps.isEmpty) {
      return Stream.value(null);
    }
    return FirebaseAuth.instance.authStateChanges();
  } catch (e) {
    debugPrint('Firebase not initialized, using guest mode: $e');
    return Stream.value(null);
  }
});

// Auth State Provider (checks both Firebase and valid guest login)
final isAuthenticatedProvider = FutureProvider<bool>((ref) async {
  // Check Firebase auth first
  final authState = await ref.watch(authStateProvider.future);
  if (authState != null) {
    return true;
  }

  // Check for valid user session (not just onboarding completion)
  final prefs = await SharedPreferences.getInstance();
  final userId = prefs.getString(AppConstants.userIdKey);
  final hasValidSession = prefs.getBool('has_valid_session') ?? false;
  return userId != null && userId.isNotEmpty && hasValidSession;
});

// Auth Service Provider
final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(ref);
});

class AuthService {
  final Ref _ref;

  AuthService(this._ref);

  FirebaseAuth? get _auth {
    try {
      if (Firebase.apps.isNotEmpty) {
        final auth = FirebaseAuth.instance;
        debugPrint('🔥 Firebase Auth initialized');
        return auth;
      } else {
        debugPrint('⚠️ Firebase apps list is empty');
      }
    } catch (e) {
      debugPrint('❌ Firebase not available: $e');
    }
    return null;
  }

  // Get current user
  User? get currentUser => _auth?.currentUser;

  // Guest login (no Firebase required)
  Future<bool> signInAsGuest() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        AppConstants.userIdKey,
        'guest_${DateTime.now().millisecondsSinceEpoch}',
      );
      await prefs.setBool(AppConstants.hasSeenOnboardingKey, true);
      await prefs.setBool('has_valid_session', true);
      debugPrint('✅ Guest login successful');

      // Invalidate auth state to trigger router update
      _ref.invalidate(isAuthenticatedProvider);

      return true;
    } catch (e) {
      debugPrint('Error in guest login: $e');
      return false;
    }
  }

  // Sign in anonymously (for demo purposes)
  Future<User?> signInAnonymously() async {
    try {
      if (_auth == null) {
        throw Exception(
          'Authentication service not available. Please try again later.',
        );
      }

      final userCredential = await _auth!.signInAnonymously();
      final user = userCredential.user;

      if (user != null) {
        // Save user ID to SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(AppConstants.userIdKey, user.uid);
        await prefs.setBool(AppConstants.hasSeenOnboardingKey, true);
        await prefs.setBool('has_valid_session', true);
      }

      return user;
    } catch (e) {
      debugPrint('Error signing in anonymously: $e');
      throw Exception(_getAuthErrorMessage(e));
    }
  }

  // Sign in with email/password (mock)
  Future<User?> signInWithEmail(String email, String password) async {
    try {
      if (_auth == null) {
        throw Exception(
          'Authentication service not available. Please try again later.',
        );
      }

      final userCredential = await _auth!.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = userCredential.user;

      if (user != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(AppConstants.userIdKey, user.uid);
        await prefs.setBool(AppConstants.hasSeenOnboardingKey, true);
        await prefs.setBool('has_valid_session', true);

        // Ensure user document exists in Firestore
        await _ensureUserDocument(user);
      }

      return user;
    } catch (e) {
      debugPrint('Error signing in with email: $e');
      throw Exception(_getAuthErrorMessage(e));
    }
  }

  // Sign up with email/password (mock)
  Future<User?> signUpWithEmail(String email, String password) async {
    try {
      if (_auth == null) {
        throw Exception(
          'Authentication service not available. Please try again later.',
        );
      }

      final userCredential = await _auth!.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = userCredential.user;

      if (user != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(AppConstants.userIdKey, user.uid);
        await prefs.setBool(AppConstants.hasSeenOnboardingKey, true);
        await prefs.setBool('has_valid_session', true);

        // Create user document in Firestore
        await _createUserDocument(user, user.email?.split('@')[0] ?? 'Driver');
      }

      return user;
    } catch (e) {
      debugPrint('Error signing up with email: $e');
      throw Exception(_getAuthErrorMessage(e));
    }
  }

  // Create user with email, password and display name
  Future<User?> createUserWithEmailAndPassword({
    required String email,
    required String password,
    required String displayName,
  }) async {
    try {
      if (_auth == null) {
        throw Exception(
          'Authentication service not available. Please try again later.',
        );
      }

      final userCredential = await _auth!.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = userCredential.user;

      if (user != null) {
        // Update user profile with display name
        await user.updateDisplayName(displayName);
        await user.reload();

        // Create user document in Firestore with all required fields
        await _createUserDocument(user, displayName);
      }

      return _auth!.currentUser; // Get updated user
    } catch (e) {
      debugPrint('Error creating user: $e');
      throw Exception(_getAuthErrorMessage(e));
    }
  }

  // Create initial user document in Firestore
  Future<void> _createUserDocument(User user, String displayName) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'name': displayName,
        'email': user.email ?? '',
        'phone': user.phoneNumber ?? '',
        'latitude': 6.9271, // Default Colombo location
        'longitude': 79.8612,
        'is_live': false,
        'vehicle_color': 'Yellow', // Default tuk-tuk color
        'license_plate': 'TBD',
        'rating': 5.0,
        'total_trips': 0,
        'last_updated': FieldValue.serverTimestamp(),
        'photo_path': null,
        'created_at': FieldValue.serverTimestamp(),
      });
      debugPrint('✅ User document created in Firestore');
    } catch (e) {
      debugPrint('❌ Error creating user document: $e');
    }
  }

  // Ensure user document exists (for existing users)
  Future<void> _ensureUserDocument(User user) async {
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (!userDoc.exists) {
        // Create document if it doesn't exist
        await _createUserDocument(user, user.displayName ?? 'Driver');
      }
    } catch (e) {
      debugPrint('❌ Error checking user document: $e');
    }
  }

  // Reset password
  Future<void> resetPassword(String email) async {
    try {
      if (_auth == null) {
        throw Exception(
          'Authentication service not available. Please try again later.',
        );
      }

      await _auth!.sendPasswordResetEmail(email: email);
    } catch (e) {
      debugPrint('Error resetting password: $e');
      throw Exception(_getAuthErrorMessage(e));
    }
  }

  // Update user profile
  Future<void> updateUserProfile({
    String? displayName,
    String? phoneNumber,
    File? photoFile,
  }) async {
    try {
      if (_auth == null || currentUser == null) {
        throw Exception(
          'Authentication service not available or user not signed in.',
        );
      }

      if (displayName != null && displayName.trim().isNotEmpty) {
        await currentUser!.updateDisplayName(displayName.trim());
      }

      // Handle photo - save locally
      if (photoFile != null) {
        await _savePhotoLocally(photoFile);
      }

      // Note: Firebase Auth doesn't have built-in phone number update for email users
      // In a real app, you'd store this in Firestore or another database
      if (phoneNumber != null && phoneNumber.trim().isNotEmpty) {
        // This is a placeholder - in production, store in Firestore
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          'user_phone_${currentUser!.uid}',
          phoneNumber.trim(),
        );
      }

      await currentUser!.reload();
    } catch (e) {
      debugPrint('Error updating profile: $e');
      throw Exception(_getAuthErrorMessage(e));
    }
  }

  // Save photo locally to app directory
  Future<void> _savePhotoLocally(File photoFile) async {
    try {
      debugPrint('🖼️ Starting to save photo locally...');

      if (currentUser == null) {
        throw Exception('User not authenticated');
      }

      debugPrint('📁 Getting app document directory...');
      final appDir = await getApplicationDocumentsDirectory();
      final photoDir = Directory('${appDir.path}/profile_pictures');

      debugPrint('🔐 Creating profile_pictures directory...');
      if (!photoDir.existsSync()) {
        photoDir.createSync(recursive: true);
      }

      final fileName = '${currentUser!.uid}.jpg';
      final photoPath = '${photoDir.path}/$fileName';

      debugPrint('💾 Copying file to: $photoPath');
      final savedFile = await photoFile.copy(photoPath);

      debugPrint('💿 Storing path in SharedPreferences...');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'user_photo_path_${currentUser!.uid}',
        savedFile.path,
      );

      debugPrint('✅ Photo saved successfully: $photoPath');
    } catch (e) {
      debugPrint('❌ Error saving photo locally: $e');
      throw Exception('Failed to save photo: $e');
    }
  }

  // Get user's saved photo path
  Future<String?> getUserPhotoPath() async {
    if (currentUser == null) return null;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_photo_path_${currentUser!.uid}');
  }

  // Get user-friendly error messages
  String _getAuthErrorMessage(dynamic error) {
    final String errorMessage = error.toString().toLowerCase();

    if (errorMessage.contains('user-not-found')) {
      return 'No account found with this email address.';
    } else if (errorMessage.contains('wrong-password')) {
      return 'Incorrect password. Please try again.';
    } else if (errorMessage.contains('email-already-in-use')) {
      return 'An account already exists with this email address.';
    } else if (errorMessage.contains('weak-password')) {
      return 'Password is too weak. Please use at least 6 characters.';
    } else if (errorMessage.contains('invalid-email')) {
      return 'Please enter a valid email address.';
    } else if (errorMessage.contains('user-disabled')) {
      return 'This account has been disabled. Please contact support.';
    } else if (errorMessage.contains('too-many-requests')) {
      return 'Too many failed attempts. Please try again later.';
    } else if (errorMessage.contains('network-request-failed')) {
      return 'Network error. Please check your connection.';
    } else {
      return 'An error occurred. Please try again.';
    }
  }

  // Sign out
  Future<void> signOut() async {
    if (_auth != null) {
      await _auth!.signOut();
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AppConstants.userIdKey);
    await prefs.remove('has_valid_session');

    // Invalidate auth state to trigger router update
    _ref.invalidate(isAuthenticatedProvider);
  }

  // Check if user has seen onboarding
  Future<bool> hasSeenOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(AppConstants.hasSeenOnboardingKey) ?? false;
  }
}
