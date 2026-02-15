import 'dart:async';
import 'dart:ui' as ui;
import 'dart:math' as math;
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
  Timer? _driverRefreshTimer;
  StreamSubscription<Position>? _positionStream;
  StreamSubscription<dynamic>? _driversSubscription;
  String? _currentUserId;
  LatLng? _centerLocation; // Store center location for driver loading
  BitmapDescriptor? _tukTukIcon; // Custom icon for driver markers
  Timer? _debounceTimer; // Debounce timer for location updates
  DateTime? _lastDriverReload; // Track last driver reload time

  @override
  void initState() {
    super.initState();
    _loadMapStyles();
    _loadTukTukIcon();
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
    // Cancel all timers and streams
    _locationUpdateTimer?.cancel();
    _driverRefreshTimer?.cancel();
    _positionStream?.cancel();
    _driversSubscription?.cancel();
    _debounceTimer?.cancel();
    super.dispose();
  }

  Future<void> _setUserOffline() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        // Use set with merge to avoid errors if document doesn't exist
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'is_live': false,
          'last_updated': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
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
        // Use set with merge to create document if it doesn't exist
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'latitude': position.latitude,
          'longitude': position.longitude,
          'is_live': true,
          'last_updated': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        debugPrint(
          '📍 Updated user location: ${position.latitude}, ${position.longitude}',
        );
      }
    } catch (e) {
      debugPrint('Error updating location: $e');
    }
  }

  void _startLocationTracking() {
    debugPrint('🔄 Starting location tracking...');

    // Listen to real-time location changes with optimized settings
    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter:
          50, // Update every 50 meters (reduced from 10 for performance)
    );

    _positionStream =
        Geolocator.getPositionStream(
          locationSettings: locationSettings,
        ).listen((Position position) {
          debugPrint(
            '📍 Location changed: ${position.latitude}, ${position.longitude}',
          );

          // Batch all state updates together
          _currentPosition = position;
          final newLatLng = LatLng(position.latitude, position.longitude);

          // Update UI and provider in single batch
          setState(() {
            // Update marker position
            _markers.removeWhere((m) => m.markerId.value == 'user');
            _markers.add(
              Marker(
                markerId: const MarkerId('user'),
                position: newLatLng,
                icon: BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueAzure,
                ),
                infoWindow: const InfoWindow(title: 'You'),
              ),
            );
          });

          if (mounted) {
            ref.read(currentLocationProvider.notifier).state = newLatLng;
          }

          // Smooth camera movement without animation (faster)
          _mapController?.moveCamera(CameraUpdate.newLatLng(newLatLng));

          // Debounced Firestore update
          _debounceTimer?.cancel();
          _debounceTimer = Timer(const Duration(seconds: 3), () {
            if (mounted) _updateUserLocation(position);
          });

          // Reload drivers only if significant distance change (every 200m)
          final now = DateTime.now();
          if (_lastDriverReload == null ||
              now.difference(_lastDriverReload!) >
                  const Duration(seconds: 10)) {
            _lastDriverReload = now;
            _loadActiveDrivers(newLatLng);
          }
        });

    // Reduced backup interval for better performance
    _locationUpdateTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (_currentPosition != null) {
        _updateUserLocation(_currentPosition!);
      }
    });

    debugPrint('✅ Location tracking started with optimized settings');
  }

  void _startDriverRefreshTimer(LatLng center) {
    // Cancel any existing timer
    _driverRefreshTimer?.cancel();

    // Refresh drivers every 5 seconds to catch Firebase updates
    _driverRefreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted && _centerLocation != null) {
        debugPrint('🔄 Periodic driver refresh...');
        _loadActiveDrivers(_centerLocation!);
      }
    });

    debugPrint('✅ Driver refresh timer started (every 5 seconds)');
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

  Future<void> _loadTukTukIcon() async {
    try {
      // Create a custom marker icon using a green circle with tuk-tuk emoji
      final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
      final Canvas canvas = Canvas(pictureRecorder);
      const double size = 120.0;

      // Draw green circular background
      final Paint circlePaint = Paint()
        ..color =
            const Color(0xFF10B981) // Green color
        ..style = PaintingStyle.fill;

      canvas.drawCircle(
        const Offset(size / 2, size / 2),
        size / 2,
        circlePaint,
      );

      // Draw white border
      final Paint borderPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.0;

      canvas.drawCircle(
        const Offset(size / 2, size / 2),
        size / 2 - 2,
        borderPaint,
      );

      // Draw tuk-tuk emoji/text
      final textPainter = TextPainter(
        text: const TextSpan(text: '🛺', style: TextStyle(fontSize: 60.0)),
        textDirection: TextDirection.ltr,
      );

      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset((size - textPainter.width) / 2, (size - textPainter.height) / 2),
      );

      // Convert to image
      final ui.Image image = await pictureRecorder.endRecording().toImage(
        size.toInt(),
        size.toInt(),
      );

      final ByteData? byteData = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );

      if (byteData != null) {
        final Uint8List bytes = byteData.buffer.asUint8List();
        _tukTukIcon = BitmapDescriptor.fromBytes(bytes);
        debugPrint('🛺 TukTuk marker icon loaded successfully');
      }
    } catch (e) {
      debugPrint('Error loading tuk-tuk icon: $e');
      // Will fall back to default orange marker
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

  // Ensure user document exists in Firestore (for existing users without documents)
  Future<void> _ensureUserDocumentExists() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (!userDoc.exists) {
        debugPrint('📝 Creating missing user document for ${user.email}');
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
        debugPrint('✅ User document created successfully');
      } else {
        debugPrint('✅ User document already exists');
      }
    } catch (e) {
      debugPrint('❌ Error ensuring user document: $e');
    }
  }

  Future<void> _initializeLocation() async {
    debugPrint('Initializing location...');

    // Ensure user document exists in Firestore (for existing users)
    await _ensureUserDocumentExists();

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
      if (!mounted) return;
      ref.read(currentLocationProvider.notifier).state = currentLatLng;

      // Update user location in Firestore and set as live
      await _updateUserLocation(position);

      // Start continuous location tracking
      _startLocationTracking();

      // Add user marker
      _addUserMarker(currentLatLng);

      // Load real active drivers from Firebase
      _loadActiveDrivers(currentLatLng);

      // Start periodic driver refresh
      _startDriverRefreshTimer(currentLatLng);

      // Move camera to current location
      _mapController?.animateCamera(CameraUpdate.newLatLng(currentLatLng));
    } catch (e) {
      debugPrint('Error getting location: $e');
      // Use default location (Colombo, Sri Lanka)
      debugPrint(
        'Using default location: ${AppConstants.defaultLat}, ${AppConstants.defaultLng}',
      );
      const defaultLocation = LatLng(
        AppConstants.defaultLat,
        AppConstants.defaultLng,
      );
      if (!mounted) return;
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
        // Use set with merge to create document if needed
        await FirebaseFirestore.instance
            .collection('users')
            .doc(_currentUserId)
            .set({
              'latitude': AppConstants.defaultLat,
              'longitude': AppConstants.defaultLng,
              'is_live': true,
              'last_updated': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
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
    // Store center location
    setState(() {
      _centerLocation = center;
    });

    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    debugPrint('🔍 Current user ID: $currentUserId');

    // Cancel previous subscription
    _driversSubscription?.cancel();

    // Subscribe directly to Firestore for real-time updates
    _driversSubscription = FirebaseFirestore.instance
        .collection('users')
        .where('is_live', isEqualTo: true)
        .snapshots()
        .listen(
          (snapshot) {
            if (!mounted) return;

            debugPrint(
              '🚗 Firestore update: ${snapshot.docs.length} live users total',
            );

            // Log all live users for debugging
            for (final doc in snapshot.docs) {
              final data = doc.data();
              debugPrint(
                '  📋 User: ${doc.id}, Name: ${data['name']}, Lat: ${data['latitude']}, Lng: ${data['longitude']}',
              );
            }

            final drivers = <DriverModel>[];

            for (final doc in snapshot.docs) {
              // Exclude current user
              if (doc.id == currentUserId) {
                debugPrint('⏭️ Excluding current user: ${doc.id}');
                continue;
              }

              try {
                final driver = DriverModel.fromFirestore(doc);

                // Check for valid coordinates
                if ((driver.latitude ?? 0.0) == 0.0 ||
                    (driver.longitude ?? 0.0) == 0.0) {
                  debugPrint(
                    '⚠️ Skipping driver ${driver.name}: invalid coordinates',
                  );
                  continue;
                }

                // Calculate distance
                final lat1 = center.latitude;
                final lat2 = driver.latitude ?? 0.0;
                final lng1 = center.longitude;
                final lng2 = driver.longitude ?? 0.0;

                final distance = math.sqrt(
                  (lat1 - lat2) * (lat1 - lat2) + (lng1 - lng2) * (lng1 - lng2),
                );

                final distanceKm = distance * 111;

                if (distanceKm <= 5.0) {
                  drivers.add(driver);
                  debugPrint(
                    '✅ Added driver: ${driver.name} at ${distanceKm.toStringAsFixed(2)}km',
                  );
                } else {
                  debugPrint(
                    '⚠️ Driver ${driver.name} too far: ${distanceKm.toStringAsFixed(2)}km',
                  );
                }
              } catch (e) {
                debugPrint('Error processing driver ${doc.id}: $e');
              }
            }

            debugPrint('🎯 Final: ${drivers.length} drivers within 5km radius');

            if (mounted) {
              _createDriverMarkers(drivers);
              ref.read(activeDriversNearbyProvider.notifier).state = drivers;
            }
          },
          onError: (error) {
            debugPrint('❌ Error loading drivers: $error');
          },
        );

    debugPrint('🔄 Started Firestore listener for live drivers');
  }

  void _createDriverMarkers(List<DriverModel> drivers) {
    // Get existing driver IDs
    final existingDriverIds = _markers
        .where((m) => m.markerId.value.startsWith('driver_'))
        .map((m) => m.markerId.value)
        .toSet();

    final newDriverIds = drivers.map((d) => 'driver_${d.id}').toSet();

    // Only update if there are actual changes
    if (existingDriverIds.length == newDriverIds.length &&
        existingDriverIds.containsAll(newDriverIds)) {
      return; // No changes, skip update
    }

    final driverMarkers = <Marker>{};
    final icon =
        _tukTukIcon ??
        BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange);

    for (final driver in drivers) {
      driverMarkers.add(
        Marker(
          markerId: MarkerId('driver_${driver.id}'),
          position: LatLng(
            driver.latitude ?? 6.9271,
            driver.longitude ?? 79.8612,
          ),
          icon: icon, // Reuse same icon instance
          infoWindow: const InfoWindow(title: '🛺 TukTuk'),
          onTap: () {
            debugPrint('Tapped driver: ${driver.name}');
          },
        ),
      );
    }

    setState(() {
      _markers.removeWhere((m) => m.markerId.value.startsWith('driver_'));
      _markers.addAll(driverMarkers);
    });

    if (mounted) {
      ref.read(driverMarkersProvider.notifier).state = driverMarkers;
    }
    debugPrint('🚕 Updated ${driverMarkers.length} driver markers');
  }

  Future<void> _analyzeRisk() async {
    final currentLocation = ref.read(currentLocationProvider);

    if (currentLocation == null) {
      _showErrorDialog('Location not available. Please enable GPS.');
      return;
    }

    if (!mounted) return;
    ref.read(isAnalyzingProvider.notifier).state = true;

    try {
      final apiService = ref.read(apiServiceProvider);

      // Send location + real-time context from Firebase
      final nearbyDrivers = ref.read(activeDriversNearbyProvider);
      final response = await apiService.predictRisk(
        latitude: currentLocation.latitude,
        longitude: currentLocation.longitude,
        rainLevel: 0.0, // Client weather hint (server fetches its own)
        unionDensity: nearbyDrivers.length
            .toDouble(), // Live driver count from Firebase
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
      if (mounted) {
        ref.read(isAnalyzingProvider.notifier).state = false;
      }
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

    if (mounted) {
      ref.read(zoneCircleProvider.notifier).state = circle;
    }
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

    // Watch active drivers stream for real-time updates
    if (_centerLocation != null) {
      final params = {
        'latitude': _centerLocation!.latitude,
        'longitude': _centerLocation!.longitude,
        'radiusKm': 5.0,
      };

      final driversAsync = ref.watch(activeDriversProvider(params));
      driversAsync.whenData((drivers) {
        // Avoid calling setState during build
        Future.microtask(() {
          if (!mounted) return;
          _createDriverMarkers(drivers);
          ref.read(activeDriversNearbyProvider.notifier).state = drivers;
        });
      });
    }

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
                    : const LinearGradient(
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
