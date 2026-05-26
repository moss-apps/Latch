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

    return Scaffold(
      backgroundColor: context.backgroundColor,
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: context.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Performance Settings',
          style: TextStyle(
            fontFamily: 'ProductSans',
            color: context.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          _buildSectionTitle(context, 'Performance Mode'),
          const SizedBox(height: 8),
          ...PerformanceMode.values.map(
            (mode) => _buildModeCard(context, ref, performanceMode, mode),
          ),
          const SizedBox(height: 24),
          _buildSectionTitle(context, 'Performance Metrics'),
          const SizedBox(height: 8),
          _buildMetricsCard(context),
          const SizedBox(height: 24),
          _buildSectionTitle(context, 'Tips'),
          const SizedBox(height: 8),
          _buildTipsCard(context),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        title,
        style: TextStyle(
          fontFamily: 'ProductSans',
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: context.textPrimary,
        ),
      ),
    );
  }

  Widget _buildModeCard(
    BuildContext context,
    WidgetRef ref,
    PerformanceMode currentMode,
    PerformanceMode mode,
  ) {
    final isSelected = currentMode == mode;
    final notifier = ref.read(performanceModeProvider.notifier);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: isSelected
          ? context.accentColor.withValues(alpha: 0.15)
          : context.surfaceColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isSelected
            ? BorderSide(color: context.accentColor, width: 2)
            : BorderSide(color: context.dividerColor),
      ),
      child: ListTile(
        leading: Icon(
          _getModeIcon(mode),
          color: isSelected ? context.accentColor : context.textSecondary,
        ),
        title: Text(
          notifier.getModeName(mode),
          style: TextStyle(
            fontFamily: 'ProductSans',
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            color: isSelected ? context.accentColor : context.textPrimary,
          ),
        ),
        subtitle: Text(
          notifier.getModeDescription(mode),
          style: TextStyle(
            fontFamily: 'ProductSans',
            fontSize: 12,
            color: context.textTertiary,
          ),
        ),
        trailing: isSelected
            ? Icon(Icons.check_circle, color: context.accentColor)
            : null,
        onTap: () => notifier.setMode(mode),
      ),
    );
  }

  IconData _getModeIcon(PerformanceMode mode) {
    switch (mode) {
      case PerformanceMode.highPerformance:
        return Icons.speed;
      case PerformanceMode.balanced:
        return Icons.balance;
      case PerformanceMode.quality:
        return Icons.high_quality;
    }
  }

  Widget _buildMetricsCard(BuildContext context) {
    final optimizer = FrameRateOptimizer();
    final metrics = optimizer.getMetrics();

    return Card(
      elevation: 0,
      color: context.surfaceColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: context.dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoRow(
              context,
              'Average FPS',
              metrics.averageFps.toStringAsFixed(1),
            ),
            const SizedBox(height: 8),
            _buildInfoRow(
              context,
              'Jank Percentage',
              '${metrics.jankPercentage.toStringAsFixed(2)}%',
            ),
            const SizedBox(height: 8),
            _buildInfoRow(
              context,
              'Dropped Frames',
              '${metrics.droppedFrames}',
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () {
                optimizer.resetMetrics();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Metrics reset',
                      style: TextStyle(fontFamily: 'ProductSans'),
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.refresh),
              label: const Text(
                'Reset Metrics',
                style: TextStyle(fontFamily: 'ProductSans'),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: context.accentColor,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(BuildContext context, String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: 'ProductSans',
            color: context.textSecondary,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontFamily: 'ProductSans',
            fontWeight: FontWeight.w600,
            color: context.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildTipsCard(BuildContext context) {
    final tips = [
      'Close unused apps to free up memory',
      'Reduce animation scale in device settings',
      'Clear app cache periodically',
      'Use High Performance mode for smoother scrolling',
    ];

    return Card(
      elevation: 0,
      color: context.surfaceColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: context.dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: tips.asMap().entries.map((entry) {
            final isLast = entry.key == tips.length - 1;
            return Column(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.lightbulb_outline,
                    color: context.accentColor,
                    size: 20,
                  ),
                  title: Text(
                    entry.value,
                    style: TextStyle(
                      fontFamily: 'ProductSans',
                      fontSize: 13,
                      color: context.textPrimary,
                    ),
                  ),
                  minLeadingWidth: 24,
                ),
                if (!isLast)
                  Divider(height: 1, color: context.dividerColor),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }
}
