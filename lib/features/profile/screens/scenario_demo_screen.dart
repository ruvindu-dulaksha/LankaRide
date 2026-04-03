import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../map/widgets/risk_dialog.dart';

class ScenarioDemoScreen extends StatelessWidget {
  const ScenarioDemoScreen({super.key});

  void _runScenario(BuildContext context, _Scenario scenario) {
    showDialog(
      context: context,
      builder: (context) => RiskDialog(response: scenario.response),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scenario Demo Tests'),
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back_ios),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          _ObjectiveCard(isDarkMode: isDarkMode),
          const SizedBox(height: 12),
          ..._scenarios.map((scenario) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _ScenarioCard(
                scenario: scenario,
                isDarkMode: isDarkMode,
                onRun: () => _runScenario(context, scenario),
              ),
            );
          }),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDarkMode
                  ? Colors.white.withOpacity(0.05)
                  : Colors.black.withOpacity(0.03),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDarkMode
                    ? Colors.white.withOpacity(0.1)
                    : Colors.black.withOpacity(0.12),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.emergency_outlined, color: AppTheme.warning),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Emergency quick test: tap any scenario below to open the same real alert popup style used in map scan.',
                    style: Theme.of(context).textTheme.bodyMedium,
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

class _ObjectiveCard extends StatelessWidget {
  const _ObjectiveCard({required this.isDarkMode});

  final bool isDarkMode;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDarkMode
              ? [const Color(0xFF1E293B), const Color(0xFF0F172A)]
              : [const Color(0xFFEFF6FF), const Color(0xFFF8FAFC)],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primary.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '5.3 Software Execution (Scenario Analysis and Validation)',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            'These four live test scenarios validate Smart Hustle and Ghost Town logic against research objectives.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _ScenarioCard extends StatelessWidget {
  const _ScenarioCard({
    required this.scenario,
    required this.isDarkMode,
    required this.onRun,
  });

  final _Scenario scenario;
  final bool isDarkMode;
  final VoidCallback onRun;

  @override
  Widget build(BuildContext context) {
    final Color chipColor = switch (scenario.zone) {
      'RED' => AppTheme.error,
      'YELLOW' => AppTheme.warning,
      _ => AppTheme.accent,
    };

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDarkMode
            ? Colors.white.withOpacity(0.06)
            : Colors.black.withOpacity(0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: chipColor.withOpacity(0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${scenario.title} (${scenario.zone})',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: chipColor.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: chipColor.withOpacity(0.5)),
                ),
                child: Text(
                  scenario.zone,
                  style: TextStyle(
                    color: chipColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _label(context, 'Context'),
          Text(scenario.context, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 8),
          _label(context, 'System Rationale'),
          Text(
            scenario.rationale,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          _label(context, 'Expected Output'),
          Text(scenario.output, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onRun,
              icon: const Icon(Icons.play_arrow),
              label: Text('Run ${scenario.shortCode} Demo'),
              style: ElevatedButton.styleFrom(
                backgroundColor: chipColor,
                foregroundColor: scenario.zone == 'YELLOW'
                    ? Colors.black
                    : Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: AppTheme.primary,
        ),
      ),
    );
  }
}

class _Scenario {
  const _Scenario({
    required this.shortCode,
    required this.title,
    required this.zone,
    required this.context,
    required this.rationale,
    required this.output,
    required this.response,
  });

  final String shortCode;
  final String title;
  final String zone;
  final String context;
  final String rationale;
  final String output;
  final PredictionResponse response;
}

final List<_Scenario> _scenarios = [
  _Scenario(
    shortCode: 'A',
    title: 'Scenario A: The Union Stronghold',
    zone: 'RED',
    context:
        'Near Town Hall three-wheeler parking during business hours with good weather.',
    rationale:
        'Union capacity is 20 (high risk), rain is 0mm, and safety lock remains active.',
    output:
        'Show RED gauge/dialog with message: "High Union Risk. Stay Clear."',
    response: PredictionResponse(
      zone: 'RED',
      message: 'High Union Risk. Stay Clear.',
      riskScore: 0.80,
      metadata: {
        'location': 'Town Hall',
        'traffic_intensity': 1.3,
        'rain_mm': 0.0,
        'union_capacity': 20,
        'demand_level': 'Moderate (Standard)',
      },
    ),
  ),
  _Scenario(
    shortCode: 'B',
    title: 'Scenario B: Smart Hustle Opportunity',
    zone: 'YELLOW',
    context:
        'Near Town Hall while Weather API reports heavy rain around 5.2mm.',
    rationale:
        'High union capacity is present, but rainfall drives demand overflow and novelty override.',
    output:
        'Show YELLOW gauge/dialog with message: "High Demand (Rain). Safe to Operate."',
    response: PredictionResponse(
      zone: 'YELLOW',
      message: 'High Demand (Rain). Safe to Operate.',
      riskScore: 0.74,
      metadata: {
        'location': 'Town Hall',
        'traffic_intensity': 1.7,
        'rain_mm': 5.2,
        'union_capacity': 20,
        'demand_level': 'High Demand (Rain)',
      },
    ),
  ),
  _Scenario(
    shortCode: 'C',
    title: 'Scenario C: Prime Spot (Active Green)',
    zone: 'GREEN',
    context: 'Near Independence Square at night during an event.',
    rationale:
        'Low union capacity (<10), high traffic proxy (TIS > 2.0), and boosted demand score.',
    output:
        'Show GREEN gauge/dialog with message: "Prime Spot. High Activity."',
    response: PredictionResponse(
      zone: 'GREEN',
      message: 'Prime Spot. High Activity.',
      riskScore: 0.36,
      metadata: {
        'location': 'Independence Square',
        'traffic_intensity': 2.2,
        'rain_mm': 0.0,
        'union_capacity': 8,
        'demand_level': 'Prime Spot (Event Surge)',
      },
    ),
  ),
  _Scenario(
    shortCode: 'D',
    title: 'Scenario D: Ghost Town (Low Activity Green)',
    zone: 'GREEN',
    context: 'Large residential street at 2:00 AM.',
    rationale:
        'Low union capacity and free-flow traffic proxy indicate minimal activity.',
    output: 'Show GREEN gauge/dialog with caution: "Safe but Low Activity."',
    response: PredictionResponse(
      zone: 'GREEN',
      message: 'Safe but Low Activity.',
      riskScore: 0.18,
      metadata: {
        'location': 'Residential Street',
        'traffic_intensity': 1.0,
        'rain_mm': 0.0,
        'union_capacity': 2,
        'demand_level': 'Low Activity (Ghost Town)',
      },
    ),
  ),
];
