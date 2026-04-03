import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/theme/app_theme.dart';

class AnimatedZoneIndicator extends StatefulWidget {
  final String zone; // RED, YELLOW, GREEN
  final String message;
  final double riskScore;
  final double? trafficIntensity;
  final double? rainMm;

  const AnimatedZoneIndicator({
    super.key,
    required this.zone,
    required this.message,
    required this.riskScore,
    this.trafficIntensity,
    this.rainMm,
  });

  @override
  State<AnimatedZoneIndicator> createState() => _AnimatedZoneIndicatorState();
}

class _AnimatedZoneIndicatorState extends State<AnimatedZoneIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Color _getZoneColor() {
    switch (widget.zone) {
      case 'RED':
        return AppTheme.error;
      case 'YELLOW':
        return AppTheme.warning;
      case 'GREEN':
        return AppTheme.accent;
      default:
        return AppTheme.primary;
    }
  }

  String _getZoneEmoji() {
    switch (widget.zone) {
      case 'RED':
        return '🔴';
      case 'YELLOW':
        return '🟡';
      case 'GREEN':
        return '🟢';
      default:
        return '⚪';
    }
  }

  @override
  Widget build(BuildContext context) {
    final zoneColor = _getZoneColor();
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: zoneColor.withOpacity(0.5),
          width: 2,
        ),
        color: isDarkMode
            ? Colors.black.withOpacity(0.4)
            : Colors.white.withOpacity(0.4),
        boxShadow: [
          BoxShadow(
            color: zoneColor.withOpacity(0.3),
            blurRadius: 12,
            spreadRadius: 2,
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Pulsing zone indicator
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              final pulse = Tween<double>(begin: 0.8, end: 1.2)
                  .evaluate(CurvedAnimation(
                    parent: _pulseController,
                    curve: Curves.easeInOut,
                  ));
              return Transform.scale(
                scale: pulse,
                child: Text(
                  _getZoneEmoji(),
                  style: const TextStyle(fontSize: 48),
                ),
              );
            },
          ),
          const SizedBox(height: 12),

          // Zone label
          Text(
            widget.zone,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: zoneColor,
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),

          // Message
          Text(
            widget.message,
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),

          // Risk Score Progress
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Risk Score',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  Text(
                    '${(widget.riskScore * 100).toStringAsFixed(0)}%',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: zoneColor,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: widget.riskScore,
                  minHeight: 6,
                  backgroundColor: Colors.grey.withOpacity(0.3),
                  valueColor: AlwaysStoppedAnimation<Color>(zoneColor),
                ),
              ),
            ],
          ),

          // Additional metrics if available
          if (widget.trafficIntensity != null || widget.rainMm != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: isDarkMode
                    ? Colors.white.withOpacity(0.05)
                    : Colors.black.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  if (widget.trafficIntensity != null)
                    _buildMetricBadge(
                      context,
                      icon: '🚦',
                      label: 'Traffic',
                      value:
                          'I=${widget.trafficIntensity!.toStringAsFixed(1)}',
                    ),
                  if (widget.rainMm != null)
                    _buildMetricBadge(
                      context,
                      icon: '💧',
                      label: 'Rain',
                      value:
                          '${widget.rainMm!.toStringAsFixed(1)}mm',
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    )
        .animate()
        .fadeIn(duration: 500.ms)
        .slideY(begin: 0.2, end: 0, duration: 500.ms);
  }

  Widget _buildMetricBadge(
    BuildContext context, {
    required String icon,
    required String label,
    required String value,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(icon, style: const TextStyle(fontSize: 14)),
        const SizedBox(height: 2),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontSize: 10,
              ),
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontSize: 9,
                fontWeight: FontWeight.bold,
              ),
        ),
      ],
    );
  }
}
