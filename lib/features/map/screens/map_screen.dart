import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/api/api_service.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../widgets/scanner_panel.dart';
import '../widgets/risk_dialog.dart';
import '../../drivers/providers/driver_provider.dart';
import '../../drivers/models/driver_model.dart';

// Provider for map controller
final mapControllerProvider = StateProvider<GoogleMapController?>(
  (ref) => null,
);

// Provider for current location
final currentLocationProvider = StateProvider<LatLng?>((ref) => null);

// Provider for driver markers (real from Firebase)
final driverMarkersProvider = StateProvider<Set<Marker>>((ref) => {});

// Provider for active drivers list
final activeDriversNearbyProvider = StateProvider<List<DriverModel>>(
  (ref) => [],
);

// Provider for zone circle
final zoneCircleProvider = StateProvider<Circle?>((ref) => null);

// Provider for loading state
final isAnalyzingProvider = StateProvider<bool>((ref) => false);

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  GoogleMapController? _mapController;
  String? _mapStyleLight;
  String? _mapStyleDark;
  final Set<Marker> _markers = {};
  Position? _currentPosition;
  bool _permissionGranted = false;
  Timer? _locationUpdateTimer;
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _loadMapStyles();
    _initializeLocation();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reapply map style when theme changes
    if (_mapController != null) {
      _applyMapStyle(_mapController!);
    }
  }

  @override
  void dispose() {
    _mapController?.dispose();
    // Set user as offline when leaving map
    _setUserOffline();
    // Cancel location update timer
    _locationUpdateTimer?.cancel();
    super.dispose();
  }

  Future<void> _setUserOffline() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .update({
              'is_live': false,
              'last_updated': FieldValue.serverTimestamp(),
            });
        debugPrint('✅ User set offline');
      }
    } catch (e) {
      debugPrint('Error setting user offline: $e');
    }
  }

  Future<void> _updateUserLocation(Position position) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .update({
              'latitude': position.latitude,
              'longitude': position.longitude,
              'is_live': true,
              'last_updated': FieldValue.serverTimestamp(),
            });
        debugPrint(
          '📍 Updated user location: ${position.latitude}, ${position.longitude}',
        );
      }
    } catch (e) {
      debugPrint('Error updating location: $e');
    }
  }

  void _startLocationTracking() {
    // Update location every 15 seconds
    _locationUpdateTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_currentPosition != null) {
        _updateUserLocation(_currentPosition!);
      }
    });
    debugPrint('🔄 Location tracking started');
  }

  Future<void> _loadMapStyles() async {
    try {
      _mapStyleLight = await rootBundle.loadString(
        'assets/map_style_light.json',
      );
      _mapStyleDark = await rootBundle.loadString('assets/map_style.json');
      debugPrint('Map styles loaded successfully');
    } catch (e) {
      debugPrint('Error loading map style: $e');
    }
  }

  Future<void> _applyMapStyle(GoogleMapController controller) async {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final mapStyle = isDarkMode ? _mapStyleDark : _mapStyleLight;

    if (mapStyle != null) {
      try {
        await controller.setMapStyle(mapStyle);
        debugPrint('Map style applied: ${isDarkMode ? 'DARK' : 'LIGHT'} mode');
      } catch (e) {
        debugPrint('Error applying map style: $e');
      }
    }
  }

  Future<void> _initializeLocation() async {
    debugPrint('Initializing location...');

    // Check and request location permissions
    LocationPermission permission = await Geolocator.checkPermission();
    debugPrint('Current location permission: $permission');

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      debugPrint('Requested location permission: $permission');
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      debugPrint('Location permission denied, using default location');
      setState(() {
        _permissionGranted = false;
      });
      return;
    }

    setState(() {
      _permissionGranted = true;
    });

    // Get current user ID from Firebase Auth
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _currentUserId = user.uid;
      debugPrint('👤 Current user: ${user.email}');
    }

    // Get current location
    try {
      debugPrint('Getting current position...');
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      debugPrint(
        'Current position: ${position.latitude}, ${position.longitude}',
      );

      setState(() {
        _currentPosition = position;
      });

      final currentLatLng = LatLng(position.latitude, position.longitude);
      ref.read(currentLocationProvider.notifier).state = currentLatLng;

      // Update user location in Firestore and set as live
      await _updateUserLocation(position);

      // Start continuous location tracking
      _startLocationTracking();

      // Add user marker
      _addUserMarker(currentLatLng);

      // Load real active drivers from Firebase
      _loadActiveDrivers(currentLatLng);

      // Move camera to current location
      _mapController?.animateCamera(CameraUpdate.newLatLng(currentLatLng));
    } catch (e) {
      debugPrint('Error getting location: $e');
      // Use default location (Colombo, Sri Lanka)
      debugPrint(
        'Using default location: ${AppConstants.defaultLat}, ${AppConstants.defaultLng}',
      );
      final defaultLocation = LatLng(
        AppConstants.defaultLat,
        AppConstants.defaultLng,
      );
      ref.read(currentLocationProvider.notifier).state = defaultLocation;

      // Create a fake position for default location
      setState(() {
        _currentPosition = Position(
          longitude: AppConstants.defaultLng,
          latitude: AppConstants.defaultLat,
          timestamp: DateTime.now(),
          accuracy: 0,
          altitude: 0,
          heading: 0,
          speed: 0,
          speedAccuracy: 0,
          altitudeAccuracy: 0,
          headingAccuracy: 0,
        );
      });

      // Update Firestore with default location and set as live
      if (_currentUserId != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(_currentUserId)
            .update({
              'latitude': AppConstants.defaultLat,
              'longitude': AppConstants.defaultLng,
              'is_live': true,
              'last_updated': FieldValue.serverTimestamp(),
            });
        debugPrint('📍 Set user to default location');
      }

      // Start location tracking
      _startLocationTracking();

      // Add user marker
      _addUserMarker(defaultLocation);

      // Load active drivers from Firebase
      _loadActiveDrivers(defaultLocation);
    }
  }

  void _addUserMarker(LatLng position) {
    final marker = Marker(
      markerId: const MarkerId('user'),
      position: position,
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
      infoWindow: const InfoWindow(title: 'You'),
    );

    setState(() {
      _markers.add(marker);
    });
  }

  void _loadActiveDrivers(LatLng center) {
    // Fetch active drivers from Firebase within 5km radius
    final params = {
      'latitude': center.latitude,
      'longitude': center.longitude,
      'radiusKm': 5.0,
    };

    ref.listen(activeDriversProvider(params), (prev, next) {
      next.whenData((drivers) {
        _createDriverMarkers(drivers);
        ref.read(activeDriversNearbyProvider.notifier).state = drivers;
      });
    });
  }

  void _createDriverMarkers(List<DriverModel> drivers) {
    final driverMarkers = <Marker>{};

    for (final driver in drivers) {
      final marker = Marker(
        markerId: MarkerId('driver_${driver.id}'),
        position: LatLng(
          driver.latitude ?? 6.9271, // Default to Colombo if no location
          driver.longitude ?? 79.8612,
        ),
        icon: BitmapDescriptor.defaultMarkerWithHue(
          BitmapDescriptor.hueOrange, // TukTuk color
        ),
        infoWindow: InfoWindow(
          title: driver.licensePlate ?? 'Anonymous Driver',
          snippet:
              '⭐ ${driver.rating.toStringAsFixed(1)} • ${driver.totalTrips} trips • ${driver.vehicleColor ?? 'Unknown'}',
        ),
        onTap: () {
          // Handle driver tap
          debugPrint('Tapped driver: ${driver.name}');
        },
      );

      driverMarkers.add(marker);
    }

    setState(() {
      // Remove old driver markers
      _markers.removeWhere((m) => m.markerId.value.startsWith('driver_'));
      // Add new driver markers
      _markers.addAll(driverMarkers);
    });

    ref.read(driverMarkersProvider.notifier).state = driverMarkers;
  }

  Future<void> _analyzeRisk() async {
    final currentLocation = ref.read(currentLocationProvider);

    if (currentLocation == null) {
      _showErrorDialog('Location not available. Please enable GPS.');
      return;
    }

    ref.read(isAnalyzingProvider.notifier).state = true;

    try {
      final apiService = ref.read(apiServiceProvider);

      // Production: Send real location with default values
      // In future, integrate real-time weather API and driver GPS clustering
      final response = await apiService.predictRisk(
        latitude: currentLocation.latitude,
        longitude: currentLocation.longitude,
        rainLevel: 0.0, // Get from weather API in production
        unionDensity: 0.0, // Get from real driver clustering in production
      );

      // Draw zone circle
      _drawZoneCircle(currentLocation, response);

      // Show risk dialog
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => RiskDialog(response: response),
        );
      }
    } on ApiException catch (e) {
      _showErrorDialog(e.message);
    } catch (e) {
      _showErrorDialog('Unexpected error occurred: $e');
    } finally {
      ref.read(isAnalyzingProvider.notifier).state = false;
    }
  }

  void _drawZoneCircle(LatLng center, PredictionResponse response) {
    Color circleColor;

    if (response.isRedZone) {
      circleColor = AppTheme.error;
    } else if (response.isYellowZone) {
      circleColor = AppTheme.warning;
    } else {
      circleColor = AppTheme.accent;
    }

    final circle = Circle(
      circleId: const CircleId('risk_zone'),
      center: center,
      radius: AppConstants.zoneRadius,
      fillColor: circleColor.withOpacity(0.2),
      strokeColor: circleColor,
      strokeWidth: 2,
    );

    ref.read(zoneCircleProvider.notifier).state = circle;
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Text(
          'Error',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            color: AppTheme.error,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          message,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).textTheme.bodyMedium?.color,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final zoneCircle = ref.watch(zoneCircleProvider);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDarkMode ? Colors.white : Colors.black87;

    return Scaffold(
      body: Stack(
        children: [
          // Map
          GoogleMap(
            onMapCreated: (controller) async {
              debugPrint('Google Map created successfully');
              _mapController = controller;
              ref.read(mapControllerProvider.notifier).state = controller;

              await _applyMapStyle(controller);

              // Move camera to current location if available
              if (_currentPosition != null) {
                final currentLatLng = LatLng(
                  _currentPosition!.latitude,
                  _currentPosition!.longitude,
                );
                controller.animateCamera(CameraUpdate.newLatLng(currentLatLng));
              }
            },
            initialCameraPosition: CameraPosition(
              target: _currentPosition != null
                  ? LatLng(
                      _currentPosition!.latitude,
                      _currentPosition!.longitude,
                    )
                  : const LatLng(
                      AppConstants.defaultLat,
                      AppConstants.defaultLng,
                    ),
              zoom: AppConstants.defaultZoom,
            ),
            markers: _markers,
            circles: zoneCircle != null ? {zoneCircle} : {},
            myLocationEnabled: _permissionGranted,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            compassEnabled: true,
          ),

          // Map loading indicator overlay
          if (_markers.isEmpty)
            Container(
              color: isDarkMode
                  ? Colors.black.withOpacity(0.7)
                  : Colors.white.withOpacity(0.8),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(color: AppTheme.primary),
                    const SizedBox(height: 16),
                    Text(
                      'Loading Map...',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            color: isDarkMode ? Colors.white : Colors.black87,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Make sure you have internet connection',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: isDarkMode ? Colors.white70 : Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Top App Bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 8,
                bottom: 8,
                left: 16,
                right: 16,
              ),
              decoration: BoxDecoration(
                gradient: isDarkMode
                    ? LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withOpacity(0.7),
                          Colors.transparent,
                        ],
                      )
                    : LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.transparent],
                      ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Lanka Ride',
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      color: textColor,
                      fontWeight: FontWeight.w700,
                      shadows: isDarkMode
                          ? [
                              Shadow(
                                color: Colors.black.withOpacity(0.5),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : [
                              Shadow(
                                color: Colors.white.withOpacity(0.8),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      // Navigate to profile screen
                      context.go('/profile');
                    },
                    icon: Icon(Icons.person_outline, color: textColor),
                  ),
                ],
              ),
            ),
          ),

          // Scanner Panel
          Positioned(
            bottom: 32,
            left: 16,
            right: 16,
            child: ScannerPanel(onAnalyze: _analyzeRisk),
          ),
        ],
      ),
    );
  }
}
