import 'package:flutter/material.dart';
import 'package:glassmorphism_ui/glassmorphism_ui.dart';
import 'package:flutter_animate/flutter_animate.dart';

class WeatherIndicator extends StatelessWidget {
  final double rainMm;
  final double temperature;
  final String weatherCondition;
  final double windSpeed;

  const WeatherIndicator({
    super.key,
    required this.rainMm,
    this.temperature = 0.0,
    this.weatherCondition = 'Clear',
    this.windSpeed = 0.0,
  });

  String _getWeatherEmoji() {
    if (rainMm > 5.0) return '⛈️';
    if (rainMm > 2.0) return '🌧️';
    if (rainMm > 0.1) return '🌦️';
    return '☀️';
  }

  Color _getRainColor() {
    if (rainMm > 5.0) return Colors.red;
    if (rainMm > 2.0) return Colors.orange;
    if (rainMm > 0.1) return Colors.amber;
    return Colors.blue;
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final rainColor = _getRainColor();

    return GlassContainer(
      blur: 20,
      opacity: 0.2,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: (isDarkMode ? Colors.white : Colors.black).withOpacity(0.2),
        width: 1.5,
      ),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: isDarkMode
              ? Colors.black.withOpacity(0.2)
              : Colors.white.withOpacity(0.2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Weather emoji
            Text(_getWeatherEmoji(), style: const TextStyle(fontSize: 32)),
            const SizedBox(width: 12),

            // Weather info
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Temperature
                if (temperature > 0)
                  Text(
                    '${temperature.toStringAsFixed(0)}°C',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                // Condition
                Text(
                  weatherCondition,
                  style: Theme.of(context).textTheme.labelSmall,
                ),

                // Rain level
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: rainColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: rainColor.withOpacity(0.5)),
                  ),
                  child: Text(
                    '💧 ${rainMm.toStringAsFixed(1)}mm',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: rainColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 600.ms);
  }
}
