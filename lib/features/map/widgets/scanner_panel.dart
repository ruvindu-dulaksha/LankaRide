import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:glassmorphism_ui/glassmorphism_ui.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/theme/app_theme.dart';
import '../../drivers/providers/driver_provider.dart';
import '../screens/map_screen.dart';

class ScannerPanel extends ConsumerWidget {
  final VoidCallback onAnalyze;

  const ScannerPanel({super.key, required this.onAnalyze});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAnalyzing = ref.watch(isAnalyzingProvider);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDarkMode ? Colors.white : Colors.black87;
    final panelColor = isDarkMode
        ? Colors.black.withOpacity(0.3)
        : Colors.white.withOpacity(0.3);

    return GlassContainer(
      blur: 25,
      opacity: 0.25,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(
        color: (isDarkMode ? Colors.white : Colors.black).withOpacity(0.2),
        width: 1.5,
      ),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          color: panelColor,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Title
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.radar, color: AppTheme.primary, size: 24)
                    .animate(onPlay: (controller) => controller.repeat())
                    .rotate(duration: 3000.ms),
                const SizedBox(width: 12),
                Text(
                  'Zone Scanner',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: textColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Description
            Text(
              'Analyze your current location for risk assessment',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: textColor),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 20),

            // Analyze Button
            SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: isAnalyzing ? null : onAnalyze,
                    icon: isAnalyzing
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                isDarkMode ? Colors.white : Colors.black87,
                              ),
                            ),
                          )
                        : const Icon(Icons.search),
                    label: Text(isAnalyzing ? 'ANALYZING...' : 'ANALYZE RISK'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 16,
                      ),
                    ),
                  ),
                )
                .animate(
                  onPlay: (controller) => controller.repeat(reverse: true),
                )
                .shimmer(
                  duration: 2000.ms,
                  color: AppTheme.primary.withOpacity(0.3),
                ),

            const SizedBox(height: 12),

            // Status indicators
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildStatusIndicator(
                  context,
                  icon: Icons.gps_fixed,
                  label: 'GPS Active',
                  color: AppTheme.accent,
                ),
                _buildStatusIndicator(
                  context,
                  icon: Icons.cloud,
                  label: 'AI Ready',
                  color: AppTheme.primary,
                ),
                Consumer(
                  builder: (context, ref, child) {
                    final onlineCount = ref.watch(onlineDriversCountProvider);
                    final driverCount = onlineCount.when(
                      data: (count) => count,
                      loading: () => 0,
                      error: (_, __) => 0,
                    );
                    return _buildStatusIndicator(
                      context,
                      icon: Icons.local_taxi,
                      label: '$driverCount Online',
                      color: AppTheme.warning,
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 600.ms).slideY(begin: 0.3, end: 0);
  }

  Widget _buildStatusIndicator(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
  }) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDarkMode ? Colors.white : Colors.black87;

    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: textColor,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
