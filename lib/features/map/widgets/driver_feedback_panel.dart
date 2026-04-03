import 'package:flutter/material.dart';
import 'package:glassmorphism_ui/glassmorphism_ui.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// Feedback rating model
class FeatureRating {
  final String featureName;
  final int rating; // 1-5 stars
  final String category; // 'corridor', 'hotspot', 'ui', 'performance'
  final DateTime timestamp;

  FeatureRating({
    required this.featureName,
    required this.rating,
    required this.category,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() => {
    'feature': featureName,
    'rating': rating,
    'category': category,
    'timestamp': timestamp.toIso8601String(),
  };
}

/// Quick feedback panel for drivers
class DriverFeedbackPanel extends StatefulWidget {
  final Function(FeatureRating) onRatingSubmitted;
  final VoidCallback? onClose;

  const DriverFeedbackPanel({
    super.key,
    required this.onRatingSubmitted,
    this.onClose,
  });

  @override
  State<DriverFeedbackPanel> createState() => _DriverFeedbackPanelState();
}

class _DriverFeedbackPanelState extends State<DriverFeedbackPanel> {
  String _selectedFeature = 'Interactive Corridors';
  int _selectedRating = 3;
  final TextEditingController _commentController = TextEditingController();
  bool _isSubmitting = false;

  final List<String> _features = [
    'Interactive Corridors',
    'Hotspot Detection',
    'Route Analysis',
    'Overall UI',
    'Response Time',
  ];

  final List<String> _feedbackPrompts = [
    'How useful is this feature for your daily work?',
    'How helpful are the hotspot alerts for route planning?',
    'Does route analysis help you make better decisions?',
    'Is the interface easy to use?',
    'How quickly does the app respond to your actions?',
  ];

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  void _submitFeedback() async {
    if (_selectedRating == 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('✨ Please select a rating')));
      return;
    }

    setState(() => _isSubmitting = true);

    // Simulate submission delay
    await Future.delayed(const Duration(milliseconds: 800));

    final rating = FeatureRating(
      featureName: _selectedFeature,
      rating: _selectedRating,
      category: _selectedFeature.toLowerCase().replaceAll(' ', '_'),
      timestamp: DateTime.now(),
    );

    widget.onRatingSubmitted(rating);

    setState(() => _isSubmitting = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Thank you for your feedback!'),
          duration: Duration(seconds: 2),
        ),
      );

      // Reset form
      _commentController.clear();
      _selectedRating = 3;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final currentPrompt =
        _feedbackPrompts[_features
            .indexOf(_selectedFeature)
            .clamp(0, _feedbackPrompts.length - 1)];

    return GlassContainer(
      blur: 20,
      opacity: 0.15,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.blue.withOpacity(0.3), width: 1.5),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: isDarkMode
              ? Colors.blue.withOpacity(0.05)
              : Colors.blue.withOpacity(0.02),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '💬 Quick Feedback',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                if (widget.onClose != null)
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: widget.onClose,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
              ],
            ),
            const Divider(height: 12),
            const SizedBox(height: 8),

            // Feature selector
            Text(
              'Select Feature',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Colors.grey[600],
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _features.map((feature) {
                  final isSelected = _selectedFeature == feature;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: FilterChip(
                      label: Text(
                        feature,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: isSelected ? Colors.white : null,
                        ),
                      ),
                      selected: isSelected,
                      onSelected: (_) {
                        setState(() => _selectedFeature = feature);
                      },
                      backgroundColor: Colors.grey.withOpacity(0.2),
                      selectedColor: Colors.blue,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 14),

            // Prompt
            Text(
              currentPrompt,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontStyle: FontStyle.italic,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 12),

            // Star Rating
            Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (index) {
                  final starIndex = index + 1;
                  final isFilled = starIndex <= _selectedRating;

                  return GestureDetector(
                    onTap: () {
                      setState(() => _selectedRating = starIndex);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(
                        isFilled ? Icons.star : Icons.star_outline,
                        size: 28,
                        color: isFilled ? Colors.amber : Colors.grey,
                      ),
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(
                [
                  'Not Helpful',
                  'Poor',
                  'Average',
                  'Good',
                  'Excellent',
                ][_selectedRating - 1],
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Optional comment
            TextField(
              controller: _commentController,
              maxLines: 2,
              maxLength: 150,
              decoration: InputDecoration(
                hintText:
                    'Optional: Share more details (e.g., "Hotspots helped me avoid traffic")...',
                hintStyle: TextStyle(fontSize: 11, color: Colors.grey[500]),
                contentPadding: const EdgeInsets.all(8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey.withOpacity(0.3)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey.withOpacity(0.3)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.blue.withOpacity(0.5)),
                ),
                counterText: '',
                filled: true,
                fillColor: Colors.grey.withOpacity(0.05),
              ),
              style: const TextStyle(fontSize: 11),
            ),
            const SizedBox(height: 12),

            // Submit button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isSubmitting ? null : _submitFeedback,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  disabledBackgroundColor: Colors.grey,
                ),
                icon: _isSubmitting
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white.withOpacity(0.8),
                          ),
                        ),
                      )
                    : const Icon(Icons.check_circle, size: 18),
                label: Text(
                  _isSubmitting ? 'Submitting...' : 'Submit Feedback',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),

            // Tip
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  const Text('💡', style: TextStyle(fontSize: 12)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Your feedback helps us improve LankaRide!',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontSize: 9,
                        color: Colors.blue[700],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.1, end: 0);
  }
}

/// Summary card showing feedback statistics
class FeedbackSummaryCard extends StatelessWidget {
  final List<FeatureRating> ratings;
  final int totalResponses;

  const FeedbackSummaryCard({
    super.key,
    required this.ratings,
    required this.totalResponses,
  });

  @override
  Widget build(BuildContext context) {
    if (ratings.isEmpty) {
      return const SizedBox();
    }

    final avgRating =
        ratings.fold<double>(0, (sum, r) => sum + r.rating) / ratings.length;
    final positiveCount = ratings.where((r) => r.rating >= 4).length;
    final positivePercentage = ratings.isEmpty
        ? 0
        : (positiveCount / ratings.length * 100).toInt();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.withOpacity(0.3), width: 1),
      ),
      child: Row(
        children: [
          const Text('✅', style: TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Feedback Summary',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.green[800],
                  ),
                ),
                Text(
                  '${avgRating.toStringAsFixed(1)}★ avg • $positivePercentage% positive • $totalResponses responses',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontSize: 9,
                    color: Colors.grey[700],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
