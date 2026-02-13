import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class DriverMarkerWidget extends StatelessWidget {
  final String driverName;
  final double rating;
  final bool isSelected;

  const DriverMarkerWidget({
    super.key,
    required this.driverName,
    required this.rating,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isSelected ? Colors.orange : Colors.orange.withOpacity(0.8),
        shape: BoxShape.circle,
        border: Border.all(
          color: isSelected ? Colors.yellow : Colors.white,
          width: isSelected ? 3 : 2,
        ),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.local_taxi, color: Colors.white, size: 20),
          if (rating > 0)
            Text(
              '★${rating.toStringAsFixed(1)}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 8,
                fontWeight: FontWeight.bold,
              ),
            ),
        ],
      ),
    );
  }
}

// Helper function to create BitmapDescriptor from the widget
Future<BitmapDescriptor> createDriverMarker({
  required String driverName,
  required double rating,
  bool isSelected = false,
}) async {
  // For simplicity, using default marker with specific color
  // In production, you might want to use custom SVG icons
  return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange);
}
