import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/api/api_service.dart';
import '../../../core/theme/app_theme.dart';

class RiskDialog extends StatelessWidget {
  final PredictionResponse response;

  const RiskDialog({super.key, required this.response});

  @override
  Widget build(BuildContext context) {
    Color zoneColor;
    IconData zoneIcon;
    String title;
    String subtitle;
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDarkMode ? Colors.white : Colors.black87;

    if (response.isRedZone) {
      zoneColor = AppTheme.error;
      zoneIcon = Icons.dangerous;
      title = 'DANGER!';
      subtitle = 'Union Territory Detected';
    } else if (response.isYellowZone) {
      zoneColor = AppTheme.warning;
      zoneIcon = Icons.warning_amber;
      title = 'OPPORTUNITY!';
      subtitle = 'High Demand Area';
    } else {
      zoneColor = AppTheme.accent;
      zoneIcon = Icons.check_circle;
      title = 'SAFE ZONE';
      subtitle = 'High Opportunity & Low Risk';
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: zoneColor.withOpacity(0.5), width: 2),
          boxShadow: [
            BoxShadow(
              color: zoneColor.withOpacity(0.3),
              blurRadius: 30,
              spreadRadius: 10,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon
            Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: zoneColor.withOpacity(0.2),
                    boxShadow: [
                      BoxShadow(
                        color: zoneColor.withOpacity(0.4),
                        blurRadius: 20,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: Icon(zoneIcon, size: 60, color: zoneColor),
                )
                .animate(
                  onPlay: (controller) => controller.repeat(reverse: true),
                )
                .scale(
                  duration: 1000.ms,
                  begin: const Offset(1.0, 1.0),
                  end: const Offset(1.1, 1.1),
                )
                .shimmer(duration: 1500.ms, color: zoneColor.withOpacity(0.3)),

            const SizedBox(height: 24),

            // Title
            Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.displayMedium?.copyWith(color: zoneColor),
                  textAlign: TextAlign.center,
                )
                .animate()
                .fadeIn(delay: 100.ms, duration: 400.ms)
                .slideY(begin: 0.3, end: 0),

            const SizedBox(height: 8),

            // Subtitle
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: textColor,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ).animate().fadeIn(delay: 200.ms, duration: 400.ms),

            const SizedBox(height: 16),

            // Message
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: zoneColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: zoneColor.withOpacity(0.3), width: 1),
              ),
              child: Text(
                response.message,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: textColor),
                textAlign: TextAlign.center,
              ),
            ).animate().fadeIn(delay: 300.ms, duration: 400.ms),

            const SizedBox(height: 16),

            // Risk Score
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Risk Score: ',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: textColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  '${(response.riskScore * 100).toStringAsFixed(0)}%',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: zoneColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ).animate().fadeIn(delay: 400.ms, duration: 400.ms),

            const SizedBox(height: 24),

            // Additional info for Yellow zone
            if (response.isYellowZone)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.warning.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppTheme.warning.withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.lightbulb_outline,
                      color: AppTheme.warning,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Maintain 500m buffer from nearest stand',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: textColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ).animate().fadeIn(delay: 500.ms, duration: 400.ms),

            if (response.isYellowZone) const SizedBox(height: 16),

            // Close button
            SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: zoneColor,
                      foregroundColor: response.isYellowZone
                          ? Colors.black
                          : Colors.white,
                    ),
                    child: const Text('GOT IT'),
                  ),
                )
                .animate()
                .fadeIn(delay: 600.ms, duration: 400.ms)
                .slideY(begin: 0.2, end: 0),
          ],
        ),
      ),
    );
  }
}
