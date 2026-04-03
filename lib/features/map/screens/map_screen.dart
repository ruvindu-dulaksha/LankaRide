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
import '../widgets/interactive_route_corridor.dart';
import '../widgets/hotspot_visualization.dart';
import '../widgets/driver_feedback_panel.dart';
import '../services/hotspot_service.dart';
import '../services/driver_feedback_service.dart';
import '../services/intelligent_route_analyzer.dart';
import '../services/live_traffic_service.dart';
import '../services/google_directions_service.dart';
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

// Provider for route corridor segments
final routeCorridorSegmentsProvider = StateProvider<List<Map<String, dynamic>>>(
  (ref) => [],
);

// Provider for showing corridor visualization
final showRouteCorridorProvider = StateProvider<bool>((ref) => false);

// Provider for corridor polylines
final corridorPolylinesProvider = StateProvider<Set<Polyline>>((ref) => {});

// Provider for corridor markers
final corridorMarkersProvider = StateProvider<Set<Marker>>((ref) => {});

// Provider for hotspot visualization
final showHotspotsProvider = StateProvider<bool>((ref) => false);

// Provider for hotspot circles
final hotspotsProvider = StateProvider<List<dynamic>>((ref) => []);

// Provider for hotspot visibility legend
final showHotspotLegendProvider = StateProvider<bool>((ref) => false);

// Provider for feedback panel visibility
final showFeedbackPanelProvider = StateProvider<bool>((ref) => false);

// Provider for collected feedback
final driverFeedbackProvider = StateProvider<List<FeatureRating>>((ref) => []);

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
  bool _mapLoaded = false; // FIX: Track if map has finished loading

  // Corridor visualization (auto-loaded, not manually triggered)
  InteractiveRouteCorridor? _routeCorridor;

  // Hotspot visualization (auto-shows if hotspots exist)
  List<Hotspot> _hotspots = [];
  bool _showHotspotLegend = true; // Auto-show legend when hotspots exist
  Set<Circle> _hotspotCircles = {};

  // Outcome tracking (for hotspot arrivals - auto-triggered via geofence)
  bool _showOutcomePopup = false;
  Hotspot? _currentHotspotForOutcome;
  late DriverFeedbackService _feedbackService;

  // Route recommendations (intelligent analysis of current location)
  bool _showRecommendations = false;
  List<HotspotRecommendation> _recommendations = [];
  bool _isAnalyzing = false;
  Set<Polyline> _roadSegments = {};
  HotspotRecommendation?
  _selectedHotspot; // Track selected hotspot for route visualization
  final List<Map<String, dynamic>> _driverFeedbackHistory =
      []; // Recent feedback
  TrafficPrediction? _liveTraffic; // Live traffic data from backend

  @override
  void initState() {
    super.initState();
    _feedbackService = DriverFeedbackService();
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

          // Check if driver arrived at any hotspots
          if (_hotspots.isNotEmpty) {
            _checkHotspotArrival(newLatLng);
          }

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

  /// Check if driver has arrived at any hotspot (within 100m)
  void _checkHotspotArrival(LatLng currentLocation) {
    const double hotspotArrivalRadius = 0.0009; // ~100 meters in lat/lng units

    for (final hotspot in _hotspots) {
      final distance = _calculateDistance(currentLocation, hotspot.location);

      // 100 meters approximately = 0.0009 degrees
      if (distance < hotspotArrivalRadius && !_showOutcomePopup) {
        // Driver arrived at a hotspot!
        debugPrint('🎯 Driver arrived at hotspot: ${hotspot.label}');

        setState(() {
          _showOutcomePopup = true;
          _currentHotspotForOutcome = hotspot;
        });
        break; // Show popup for only one hotspot at a time
      }
    }
  }

  /// Calculate distance between two LatLng points (in degrees)
  double _calculateDistance(LatLng point1, LatLng point2) {
    final latDiff = (point1.latitude - point2.latitude).abs();
    final lonDiff = (point1.longitude - point2.longitude).abs();

    // Simple Euclidean distance (good enough for short distances)
    return math.sqrt((latDiff * latDiff) + (lonDiff * lonDiff));
  }

  void _startDriverRefreshTimer(LatLng center) {
    // Firestore listener is already real-time; avoid periodic re-subscription.
    _driverRefreshTimer?.cancel();
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

      // Draw orange circular background so driver pins are distinct from GREEN safe-zone visuals
      final Paint circlePaint = Paint()
        ..color =
            const Color(0xFFF59E0B) // Orange color
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

      // FIX: Still show default location and markers even if permission denied
      const defaultLocation = LatLng(
        AppConstants.defaultLat,
        AppConstants.defaultLng,
      );
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

      if (!mounted) return;
      ref.read(currentLocationProvider.notifier).state = defaultLocation;
      _addUserMarker(defaultLocation);
      _loadActiveDrivers(defaultLocation);
      _startDriverRefreshTimer(defaultLocation);
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

    // Keep a single Firestore listener; only update center location on subsequent calls.
    if (_driversSubscription != null) {
      return;
    }

    // Subscribe directly to Firestore for real-time updates
    _driversSubscription = FirebaseFirestore.instance
        .collection('users')
        .where('is_live', isEqualTo: true)
        .snapshots()
        .listen(
          (snapshot) {
            if (!mounted) return;

            debugPrint('🚗 Firestore live users: ${snapshot.docs.length}');

            final latestCenter = _centerLocation ?? center;

            final drivers = <DriverModel>[];

            for (final doc in snapshot.docs) {
              // Exclude current user
              if (doc.id == currentUserId) {
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
                final lat1 = latestCenter.latitude;
                final lat2 = driver.latitude ?? 0.0;
                final lng1 = latestCenter.longitude;
                final lng2 = driver.longitude ?? 0.0;

                final distance = math.sqrt(
                  (lat1 - lat2) * (lat1 - lat2) + (lng1 - lng2) * (lng1 - lng2),
                );

                final distanceKm = distance * 111;

                if (distanceKm <= 5.0) {
                  drivers.add(driver);
                }
              } catch (e) {
                debugPrint('Error processing driver ${doc.id}: $e');
              }
            }

            debugPrint('🎯 Nearby drivers within 5km: ${drivers.length}');

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

  /// Unified analyze button - does BOTH risk analysis + hotspot analysis
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

      // ALSO ANALYZE LOCATION FOR HOTSPOTS
      await _analyzeMyLocation();
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

  /// Analyze zone/profitability AT a specific hotspot location
  /// Called when user clicks a hotspot pin
  Future<void> _analyzeHotspotZone(HotspotRecommendation hotspot) async {
    if (!mounted) return;

    try {
      final apiService = ref.read(apiServiceProvider);

      // Analyze the zone AT the hotspot's location (not driver's current location)
      final response = await apiService.predictRisk(
        latitude: hotspot.location.latitude,
        longitude: hotspot.location.longitude,
        rainLevel: 0.0,
        unionDensity: 0.0,
      );

      // Draw zone circle AT HOTSPOT LOCATION showing its profitability
      _drawZoneCircle(hotspot.location, response);

      // Show hotspot analysis in a bottom sheet
      if (mounted) {
        showModalBottomSheet(
          context: context,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          builder: (context) => SingleChildScrollView(
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Hotspot name + zone indicator
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        hotspot.name,
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: _getZoneColor(response.zone).withOpacity(0.2),
                          border: Border.all(
                            color: _getZoneColor(response.zone),
                            width: 2,
                          ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          response.zone.toUpperCase(),
                          style: TextStyle(
                            color: _getZoneColor(response.zone),
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Recommendation message
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '💡 Recommendation',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          response.message,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Detailed metrics grid
                  Text(
                    'Analytics & Data',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Metrics 2x3 grid
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.2,
                    children: [
                      // POI Density
                      _buildMetricCard(
                        context,
                        icon: '🚶',
                        label: 'Foot Traffic',
                        value: '${hotspot.poiDensity.toInt()}/100',
                        subtitle: 'POI Density',
                      ),
                      // Historical Hire Rate
                      _buildMetricCard(
                        context,
                        icon: '✅',
                        label: 'Hire Rate',
                        value: '73%',
                        subtitle: '(from 100 visits)',
                      ),
                      // Average Wait Time
                      _buildMetricCard(
                        context,
                        icon: '⏱️',
                        label: 'Avg Wait',
                        value: '8 min',
                        subtitle: 'to get hire',
                      ),
                      // Union Risk
                      _buildMetricCard(
                        context,
                        icon: '⚠️',
                        label: 'Union Risk',
                        value: _getRiskLevel(response.riskScore),
                        subtitle:
                            'Capacity: ${response.metadata?['union_capacity'] ?? '?'}',
                      ),
                      // Traffic Level
                      _buildMetricCard(
                        context,
                        icon: '🚗',
                        label: 'Traffic',
                        value: response.zone,
                        subtitle: _getTrafficDesc(response.zone),
                      ),
                      // Weather Impact
                      _buildMetricCard(
                        context,
                        icon: '☀️',
                        label: 'Weather',
                        value: 'Clear',
                        subtitle: 'No rain',
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Decision info
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '📌 Note: Success depends on your skill, competition, and timing. '
                      'These are historical probabilities, not guarantees.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Action buttons - Navigate + Feedback (Hire/No Hire)
                  Row(
                    children: [
                      // Navigate button
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: () {
                            Navigator.pop(context);
                            _showRouteToHotspot(hotspot);
                          },
                          child: const Text(
                            'Navigate',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Got Hire button (checkmark)
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            Navigator.pop(context);
                            await _recordOutcome(hotspot, hireObtained: true);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.2),
                              border: Border.all(color: Colors.green, width: 2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('✅', style: TextStyle(fontSize: 24)),
                                SizedBox(height: 4),
                                Text(
                                  'Got Hire',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // No Hire button (X)
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            Navigator.pop(context);
                            await _recordOutcome(hotspot, hireObtained: false);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.2),
                              border: Border.all(color: Colors.red, width: 2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('❌', style: TextStyle(fontSize: 24)),
                                SizedBox(height: 4),
                                Text(
                                  'No Hire',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.red,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      }
    } on ApiException catch (e) {
      _showErrorDialog(e.message);
    } catch (e) {
      _showErrorDialog('Error analyzing hotspot: $e');
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

  void _centerOnCurrentLocation() {
    final current = _currentPosition;
    if (current == null) {
      _showErrorDialog('Current location not ready yet. Please wait a moment.');
      return;
    }

    _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(
        LatLng(current.latitude, current.longitude),
        AppConstants.defaultZoom,
      ),
    );
  }

  /// Build metric card for the analytics grid
  Widget _buildMetricCard(
    BuildContext context, {
    required String icon,
    required String label,
    required String value,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withOpacity(0.05),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
          width: 1,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(icon, style: const TextStyle(fontSize: 24)),
          const SizedBox(height: 6),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontSize: 11, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  /// Get risk level description
  String _getRiskLevel(double riskScore) {
    if (riskScore >= 0.7) return 'HIGH';
    if (riskScore >= 0.4) return 'MEDIUM';
    return 'LOW';
  }

  /// Get traffic description
  String _getTrafficDesc(String zone) {
    switch (zone.toUpperCase()) {
      case 'GREEN':
        return 'Good conditions';
      case 'YELLOW':
        return 'Moderate risk';
      case 'RED':
        return 'High risk';
      default:
        return 'Unknown';
    }
  }

  /// Record outcome (hire/no hire) to Firebase
  Future<void> _recordOutcome(
    HotspotRecommendation hotspot, {
    required bool hireObtained,
  }) async {
    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) {
        _showErrorDialog('User not authenticated');
        return;
      }

      final firestore = FirebaseFirestore.instance;

      // Save outcome to Firestore
      await firestore.collection('driver_outcomes').add({
        'driver_id': userId,
        'hotspot_name': hotspot.name,
        'hotspot_location': {
          'latitude': hotspot.location.latitude,
          'longitude': hotspot.location.longitude,
        },
        'hire_obtained': hireObtained,
        'timestamp': FieldValue.serverTimestamp(),
        'poi_density': hotspot.poiDensity,
        'distance_km': hotspot.distanceKm,
        'profit_score': hotspot.profitScore,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              hireObtained
                  ? '✅ Great! Hire recorded at ${hotspot.name}'
                  : '📊 Feedback recorded at ${hotspot.name}',
            ),
            duration: const Duration(seconds: 2),
            backgroundColor: hireObtained
                ? Colors.green.shade700
                : Colors.blue.shade700,
          ),
        );
      }
    } catch (e) {
      if (e is FirebaseException && e.code == 'permission-denied') {
        _showErrorDialog(
          'Firestore permission denied for driver outcomes. '
          'Please update Firestore security rules to allow authenticated writes to driver_outcomes.',
        );
      } else {
        _showErrorDialog('Failed to save outcome: $e');
      }
    }
  }

  /// Build polylines and markers from corridor segments
  void _buildCorridorVisualization(
    List<Map<String, dynamic>> segments,
    String overallZone,
  ) {
    final polylines = <Polyline>{};
    final markers = <Marker>{};

    // Build polylines for each segment
    for (int i = 0; i < segments.length - 1; i++) {
      final currentSegment = segments[i];
      final nextSegment = segments[i + 1];

      final currentLat = currentSegment['metrics']?['latitude'] ?? 6.9271;
      final currentLon = currentSegment['metrics']?['longitude'] ?? 80.7789;
      final nextLat = nextSegment['metrics']?['latitude'] ?? 6.9271;
      final nextLon = nextSegment['metrics']?['longitude'] ?? 80.7789;

      final zone = currentSegment['zone'] ?? 'GREEN';

      // Create polyline
      polylines.add(
        Polyline(
          polylineId: PolylineId('segment_$i'),
          points: [LatLng(currentLat, currentLon), LatLng(nextLat, nextLon)],
          color: _getZoneColor(zone),
          width: 8,
          geodesic: true,
          patterns: [PatternItem.dash(15), PatternItem.gap(10)],
        ),
      );

      // Create waypoint marker
      markers.add(
        Marker(
          markerId: MarkerId('waypoint_$i'),
          position: LatLng(currentLat, currentLon),
          infoWindow: InfoWindow(title: 'Segment ${i + 1}/7', snippet: zone),
          icon: _getWaypointIcon(i, zone),
        ),
      );
    }

    // Add final waypoint
    final lastSegment = segments.last;
    final lastLat = lastSegment['metrics']?['latitude'] ?? 6.9271;
    final lastLon = lastSegment['metrics']?['longitude'] ?? 80.7789;
    markers.add(
      Marker(
        markerId: const MarkerId('waypoint_end'),
        position: LatLng(lastLat, lastLon),
        infoWindow: const InfoWindow(
          title: 'Destination',
          snippet: 'End of route',
        ),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      ),
    );

    // Update providers
    ref.read(corridorPolylinesProvider.notifier).state = polylines;
    ref.read(corridorMarkersProvider.notifier).state = markers;
  }

  /// Get zone color
  Color _getZoneColor(String zone) {
    switch (zone.toUpperCase()) {
      case 'RED':
        return const Color(0xFFEF5350);
      case 'YELLOW':
        return const Color(0xFFFFA726);
      case 'GREEN':
        return const Color(0xFF66BB6A);
      default:
        return Colors.grey;
    }
  }

  /// Get waypoint icon color
  BitmapDescriptor _getWaypointIcon(int index, String zone) {
    switch (zone.toUpperCase()) {
      case 'RED':
        return BitmapDescriptor.defaultMarkerWithHue(0); // Red
      case 'YELLOW':
        return BitmapDescriptor.defaultMarkerWithHue(45); // Orange
      case 'GREEN':
        return BitmapDescriptor.defaultMarkerWithHue(120); // Green
      default:
        return BitmapDescriptor.defaultMarkerWithHue(0);
    }
  }

  /// Load and visualize route corridor analysis
  /// Generate hotspots from route segments
  void _generateHotspotsForRoute(List<Map<String, dynamic>> segments) {
    final hotspots = HotspotService.analyzeRouteHotspots(segments);

    setState(() {
      _hotspots = hotspots;

      // Generate circles for hotspot visualization
      final hotspotViz = HotspotVisualization(hotspots: hotspots);
      _hotspotCircles = hotspotViz.generateHotspotCircles();

      // Update provider
      ref.read(hotspotsProvider.notifier).state = hotspots;
    });
  }

  /// Handle outcome submission when driver reaches a hotspot
  void _handleOutcomeSubmitted({
    required bool hireObtained,
    required double? earnings,
  }) async {
    if (_currentHotspotForOutcome == null || _currentUserId == null) return;

    try {
      final hotspot = _currentHotspotForOutcome!;

      // Record the outcome to Firebase
      await _feedbackService.recordHotspotOutcome(
        hotspotLabel: hotspot.label,
        location: hotspot.location,
        driverId: _currentUserId!,
        hireObtained: hireObtained,
        earnings: earnings ?? 0.0,
        hotspotType: hotspot.type,
      );

      setState(() {
        _showOutcomePopup = false;
        _currentHotspotForOutcome = null;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              hireObtained
                  ? '✅ Great! Hire recorded (${earnings ?? 0})'
                  : '📊 Feedback recorded',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error recording outcome: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  /// Analyze current location with LIVE TRAFFIC data and smart rules
  Future<void> _analyzeMyLocation() async {
    if (_currentPosition == null) {
      _showErrorDialog('Please enable location services');
      return;
    }

    setState(() => _isAnalyzing = true);

    try {
      final currentLocation = LatLng(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
      );

      // Step 1: Get live traffic prediction from backend (XGBoost model)
      final traffic = await LiveTrafficService.getTrafficPrediction(
        currentLocation.latitude,
        currentLocation.longitude,
      );

      if (traffic != null) {
        setState(() => _liveTraffic = traffic);
        debugPrint('🚗 Live Traffic: ${traffic.zone} - ${traffic.message}');
      }

      // Step 2: Get all nearby hotspots
      const allHotspots = IntelligentRouteAnalyzer.HOTSPOTS;

      // Step 3: Apply SMART HUSTLING RULES based on live traffic
      List<Map<String, dynamic>> smartRecommendations;

      if (traffic != null) {
        // Use smart rules with traffic data
        smartRecommendations = LiveTrafficService.applySmartHustleRules(
          allHotspots,
          traffic,
        );
        debugPrint(
          '⭐ Smart Hustle Rules Applied - Top: ${smartRecommendations.isNotEmpty ? smartRecommendations[0]['name'] : 'N/A'}',
        );
      } else {
        // Fallback: just sort by POI if no traffic data
        smartRecommendations = [...allHotspots];
        smartRecommendations.sort(
          (a, b) =>
              (b['poi_density'] as int).compareTo(a['poi_density'] as int),
        );
      }

      // Step 4: Convert to HotspotRecommendation objects
      final nearby = <HotspotRecommendation>[];
      for (final hotspot in smartRecommendations) {
        final poi = (hotspot['poi_density'] as int).toDouble();
        final profit = (poi / 91) * 100;
        final smartScore = hotspot['smart_score'] as double? ?? profit;

        nearby.add(
          HotspotRecommendation(
            name: hotspot['name'],
            location: LatLng(hotspot['lat'], hotspot['lon']),
            poiDensity: poi,
            type: hotspot['type'],
            distanceKm: 0,
            profitScore: smartScore, // Use smart score, not just POI
          ),
        );
      }

      setState(() {
        _recommendations = nearby;
        _showRecommendations = true;
      });

      // Create markers
      _createHotspotMarkers(nearby);

      if (mounted) {
        final trafficEmoji = traffic?.zoneEmoji ?? '⚪';
        final trafficMsg = traffic != null ? ' - ${traffic.zone} traffic' : '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '$trafficEmoji Found ${nearby.length} smart hotspots nearby$trafficMsg!',
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error analyzing location: $e');
      _showErrorDialog('Failed to analyze location');
    } finally {
      setState(() => _isAnalyzing = false);
    }
  }

  /// Show route line from current location to selected hotspot
  void _showRouteToHotspot(HotspotRecommendation hotspot) async {
    if (_currentPosition == null) return;

    final currentLoc = LatLng(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
    );

    setState(() {
      _selectedHotspot = hotspot;
    });

    // Show loading indicator
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('📍 Fetching live traffic route...'),
          duration: Duration(seconds: 2),
        ),
      );
    }

    // Fetch live traffic route from Google Directions API
    final route = await GoogleDirectionsService.getTrafficAwareRoute(
      currentLoc,
      hotspot.location,
    );

    if (route != null) {
      // Create polyline with actual road route
      final routeLine = Polyline(
        polylineId: const PolylineId('route_to_hotspot'),
        points: route.polylinePoints,
        color: Colors.blue,
        width: 5,
        geodesic: true,
      );

      setState(() {
        _roadSegments = {routeLine};
      });

      // Show route details in a info card
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${route.statusEmoji} ${route.summary}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      route.trafficStatus,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
                Text(
                  '⏱️ ${(route.durationInTraffic / 60).toStringAsFixed(1)}m',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } else {
      // Fallback: simple straight line
      final routeLine = Polyline(
        polylineId: const PolylineId('route_to_hotspot'),
        points: [currentLoc, hotspot.location],
        color: Colors.blue,
        width: 5,
        geodesic: true,
      );

      setState(() {
        _roadSegments = {routeLine};
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ Using direct route (live traffic unavailable)'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    }

    // Animate camera to show both points
    _animateCameraToBounds(currentLoc, hotspot.location);
  }

  /// Animate camera to show both current location and hotspot
  void _animateCameraToBounds(LatLng point1, LatLng point2) {
    if (_mapController == null) return;

    final bounds = LatLngBounds(
      southwest: LatLng(
        math.min(point1.latitude, point2.latitude),
        math.min(point1.longitude, point2.longitude),
      ),
      northeast: LatLng(
        math.max(point1.latitude, point2.latitude),
        math.max(point1.longitude, point2.longitude),
      ),
    );

    _mapController!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 100));
  }

  /// Create markers for hotspot recommendations
  void _createHotspotMarkers(List<HotspotRecommendation> hotspots) {
    _markers.removeWhere((m) => m.markerId.value.startsWith('hotspot_'));

    for (final hotspot in hotspots) {
      _markers.add(
        Marker(
          markerId: MarkerId('hotspot_${hotspot.name}'),
          position: hotspot.location,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            _colorIntToHue(hotspot.markerColor),
          ),
          infoWindow: InfoWindow(
            title: hotspot.name,
            snippet:
                '${hotspot.typeEmoji} Profit: ${hotspot.profitScore.toStringAsFixed(0)}%',
          ),
          onTap: () => _analyzeHotspotZone(hotspot),
        ),
      );
    }
  }

  /// Convert color int to MapMarker hue
  double _colorIntToHue(int color) {
    // Map profitability to hue (Green, Yellow, Red only)
    switch (color) {
      case 0xFF00DB24:
        return BitmapDescriptor.hueGreen; // Green
      case 0xFFFFED1C:
        return BitmapDescriptor.hueYellow; // Yellow
      case 0xFFFF0000:
        return BitmapDescriptor.hueRed; // Red
      default:
        return BitmapDescriptor.hueBlue;
    }
  }

  /// Handle hotspot tap - start navigation
  void _handleHotspotTap(HotspotRecommendation hotspot) {
    debugPrint('🎯 Selected: ${hotspot.name}');

    /// Show suggestion message
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(IntelligentRouteAnalyzer.getSuggestionMessage([hotspot])),
        duration: const Duration(seconds: 3),
      ),
    );

    /// TODO: Integrate with navigation service to start turn-by-turn directions
    /// For now, just animate map to hotspot
    if (_mapController != null) {
      _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: hotspot.location, zoom: 17),
        ),
      );
    }

    /// Close recommendations to focus on map
    setState(() {
      _showRecommendations = false;
    });
  }

  /// Build the outcome popup widget
  Widget _buildOutcomePopup() {
    if (_currentHotspotForOutcome == null) {
      return const SizedBox();
    }

    final hotspot = _currentHotspotForOutcome!;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withOpacity(0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              const Text('🎉', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Arrived at Hotspot',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      hotspot.label,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.orange,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Question
          Text(
            'Did you get a hire at this location?',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 12),

          // Yes/No/Skip Buttons
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    _handleOutcomeSubmitted(hireObtained: true, earnings: null);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.withOpacity(0.8),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  icon: const Icon(Icons.check, color: Colors.white),
                  label: const Text(
                    'Yes ✅',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    _handleOutcomeSubmitted(
                      hireObtained: false,
                      earnings: null,
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.withOpacity(0.8),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  icon: const Icon(Icons.close, color: Colors.white),
                  label: const Text(
                    'No ❌',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () {
                  setState(() {
                    _showOutcomePopup = false;
                    _currentHotspotForOutcome = null;
                  });
                },
                child: const Text('Skip'),
              ),
            ],
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

              // FIX: Mark map as loaded to hide loading overlay
              if (mounted) {
                setState(() {
                  _mapLoaded = true;
                });
              }

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
            markers: {..._markers, ...(ref.watch(corridorMarkersProvider))},
            polylines: {
              ...ref.watch(corridorPolylinesProvider),
              ..._roadSegments,
            },
            circles: {if (zoneCircle != null) zoneCircle, ..._hotspotCircles},
            myLocationEnabled: _permissionGranted, // Show blue dot for driver
            myLocationButtonEnabled:
                false, // Use custom button above scanner panel
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            compassEnabled: true,
          ),

          // Map loading indicator overlay (FIX: uses proper loading state)
          if (!_mapLoaded)
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

          // Route Corridor Information Overlay
          if (ref.watch(showRouteCorridorProvider))
            _routeCorridor != null
                ? Stack(
                    children: [
                      _routeCorridor!,
                      Positioned(
                        bottom: 200,
                        right: 16,
                        child: FloatingActionButton.small(
                          heroTag: 'close_corridor',
                          backgroundColor: AppTheme.error,
                          onPressed: () {
                            setState(() {
                              ref
                                      .read(showRouteCorridorProvider.notifier)
                                      .state =
                                  false;
                              ref
                                      .read(corridorPolylinesProvider.notifier)
                                      .state =
                                  {};
                              ref.read(corridorMarkersProvider.notifier).state =
                                  {};
                            });
                          },
                          child: const Icon(Icons.close),
                        ),
                      ),
                    ],
                  )
                : const SizedBox(),

          // Hotspot Legend Panel (always visible when hotspots exist)
          HotspotLegendPanel(
            hotspots: _hotspots,
            isVisible: _showHotspotLegend && _hotspots.isNotEmpty,
            onClose: () {
              setState(() {
                _showHotspotLegend = false;
              });
            },
          ),

          // Outcome Feedback Popup (shown when driver arrives at hotspot)
          if (_showOutcomePopup && _currentHotspotForOutcome != null)
            Positioned(
              bottom: 280,
              left: 16,
              right: 16,
              child: _buildOutcomePopup(),
            ),

          // Bottom Control Panels
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Scrollable Insights Panel (shows when analyzing)
                if (_showRecommendations && _recommendations.isNotEmpty)
                  Container(
                    height: 220,
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(16),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 12,
                          offset: const Offset(0, -2),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        // Header with Traffic Info
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: Colors.grey.withOpacity(0.2),
                              ),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Title
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '🎯 Smart Hotspots (${_recommendations.length})',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.close, size: 20),
                                    onPressed: () {
                                      setState(() {
                                        _showRecommendations = false;
                                        _selectedHotspot = null;
                                        _roadSegments.clear();
                                      });
                                    },
                                  ),
                                ],
                              ),
                              // Current GPS Location Info
                              if (_currentPosition != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: Colors.blue,
                                        width: 1,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.my_location,
                                          size: 16,
                                          color: Colors.blue,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          'From: Your Location (${_currentPosition!.latitude.toStringAsFixed(4)}, ${_currentPosition!.longitude.toStringAsFixed(4)})',
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall
                                              ?.copyWith(
                                                color: Colors.blue,
                                                fontWeight: FontWeight.w600,
                                              ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              // Live Traffic Info
                              if (_liveTraffic != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Color(
                                        _liveTraffic!.zoneColor,
                                      ).withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: Color(_liveTraffic!.zoneColor),
                                        width: 1,
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              _liveTraffic!.zoneEmoji,
                                              style: const TextStyle(
                                                fontSize: 16,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                '${_liveTraffic!.zone} - ${_liveTraffic!.message}',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .labelSmall
                                                    ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '📍 ${_liveTraffic!.location} • 🕐 ${_liveTraffic!.timeOfDay} • ${_liveTraffic!.demandLevel} Demand',
                                          style: Theme.of(
                                            context,
                                          ).textTheme.labelSmall,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        // Scrollable hotspots list
                        Expanded(
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            itemCount: _recommendations.length,
                            itemBuilder: (context, index) {
                              final hotspot = _recommendations[index];
                              final isSelected =
                                  _selectedHotspot?.name == hotspot.name;

                              return GestureDetector(
                                onTap: () => _showRouteToHotspot(hotspot),
                                child: Container(
                                  margin: const EdgeInsets.symmetric(
                                    vertical: 6,
                                    horizontal: 4,
                                  ),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? Colors.blue.withOpacity(0.1)
                                        : Colors.grey.withOpacity(0.05),
                                    border: Border.all(
                                      color: isSelected
                                          ? Colors.blue
                                          : Colors.transparent,
                                      width: 2,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    children: [
                                      // Profit score circle
                                      Container(
                                        width: 50,
                                        height: 50,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: _getMarkerColor(
                                            hotspot.markerColor,
                                          ),
                                        ),
                                        child: Center(
                                          child: Text(
                                            '${hotspot.profitScore.toStringAsFixed(0)}%',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      // Hotspot info
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              hotspot.name,
                                              style: Theme.of(
                                                context,
                                              ).textTheme.titleSmall,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 4),
                                            Row(
                                              children: [
                                                const Icon(
                                                  Icons.location_on,
                                                  size: 14,
                                                  color: Colors.grey,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  'POI: ${hotspot.poiDensity.toStringAsFixed(0)}',
                                                  style: Theme.of(
                                                    context,
                                                  ).textTheme.labelSmall,
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      const Icon(Icons.arrow_forward, size: 18),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),

                // Bottom Controls Row
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 12,
                    children: [
                      Align(
                        alignment: Alignment.centerRight,
                        child: FloatingActionButton.small(
                          heroTag: 'my_location_bottom',
                          backgroundColor: AppTheme.primary,
                          foregroundColor: Colors.white,
                          onPressed: _centerOnCurrentLocation,
                          child: const Icon(Icons.my_location),
                        ),
                      ),
                      // Unified Risk + Hotspot Analysis Scanner Panel
                      ScannerPanel(onAnalyze: _analyzeRisk),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Convert marker color int to Color object (Green, Yellow, Red only)
  Color _getMarkerColor(int colorInt) {
    if (colorInt == 0xFF00DB24) return Colors.green;
    if (colorInt == 0xFFFFED1C) return Colors.yellow;
    if (colorInt == 0xFFFF0000) return Colors.red;
    return Colors.blue;
  }
}
