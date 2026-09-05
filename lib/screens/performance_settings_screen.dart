import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/performance_provider.dart';
import '../themes/app_colors.dart';
import '../utils/frame_rate_optimizer.dart';

/// Screen for configuring performance settings
class PerformanceSettingsScreen extends ConsumerWidget {
  const PerformanceSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final performanceMode = ref.watch(performanceModeProvider);
    final optimizer = FrameRateOptimizer();
    final metrics = optimizer.getMetrics();

    const tips = [
      'Close unused apps to free up memory',
      'Reduce animation scale in device settings',
      'Clear app cache periodically',
      'Use High Performance mode for smoother scrolling',
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Performance Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          _sectionTitle(context, 'Performance Mode'),
          ...PerformanceMode.values.map(
            (mode) => _modeTile(context, ref, performanceMode, mode),
          ),
          const SizedBox(height: 24),
          _sectionTitle(context, 'Performance Metrics'),
          _infoTile(context, 'Average FPS', metrics.averageFps.toStringAsFixed(1)),
          _infoTile(
            context,
            'Jank Percentage',
            '${metrics.jankPercentage.toStringAsFixed(2)}%',
          ),
          _infoTile(context, 'Dropped Frames', '${metrics.droppedFrames}'),
          _tile(
            context,
            icon: Icons.refresh,
            title: 'Reset Metrics',
            subtitle: 'Clear the recorded frame statistics',
            onTap: () => _resetMetrics(context, optimizer),
          ),
          const SizedBox(height: 24),
          _sectionTitle(context, 'Tips'),
          ...tips.map((tip) => ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: Icon(
                  Icons.lightbulb_outline,
                  color: context.accentColor,
                  size: 20,
                ),
                title: Text(
                  tip,
                  style: TextStyle(
                    fontSize: 13,
                    color: context.textPrimary,
                  ),
                ),
              )),
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
          color: context.accentColor,
        ),
      ),
    );
  }

  Widget _modeTile(
    BuildContext context,
    WidgetRef ref,
    PerformanceMode currentMode,
    PerformanceMode mode,
  ) {
    final isSelected = currentMode == mode;
    final notifier = ref.read(performanceModeProvider.notifier);

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        switch (mode) {
          PerformanceMode.highPerformance => Icons.speed,
          PerformanceMode.balanced => Icons.balance,
          PerformanceMode.quality => Icons.high_quality,
        },
        color: isSelected ? context.accentColor : context.textSecondary,
      ),
      title: Text(
        notifier.getModeName(mode),
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          color: isSelected ? context.accentColor : context.textPrimary,
        ),
      ),
      subtitle: Text(
        notifier.getModeDescription(mode),
        style: TextStyle(fontSize: 12, color: context.textTertiary),
      ),
      trailing: isSelected
          ? Icon(Icons.check_circle, color: context.accentColor)
          : null,
      onTap: () => notifier.setMode(mode),
    );
  }

  void _resetMetrics(BuildContext context, FrameRateOptimizer optimizer) {
    optimizer.resetMetrics();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Metrics reset')),
    );
  }

  Widget _tile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: context.accentColor),
      title: Text(title),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 12, color: context.textTertiary),
      ),
      trailing: Icon(Icons.chevron_right, color: context.textTertiary),
      onTap: onTap,
    );
  }

  Widget _infoTile(BuildContext context, String label, String value) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(label),
      trailing: Text(
        value,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: context.textSecondary,
        ),
      ),
    );
  }
}
