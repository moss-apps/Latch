import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/accent_color.dart';
import '../providers/theme_provider.dart';
import '../themes/app_colors.dart';

class AccentColorPickerScreen extends ConsumerWidget {
  const AccentColorPickerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentAccentColor = ref.watch(accentColorProvider);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: context.backgroundColor,
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: context.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Accent Color',
          style: TextStyle(
            fontFamily: 'ProductSans',
            color: context.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Stack(
        children: [
          _buildBackground(context),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Choose your accent color',
                    style: TextStyle(
                      fontSize: 18,
                      color: context.textSecondary,
                      fontFamily: 'ProductSans',
                    ),
                  ),
                  const SizedBox(height: 24),
                  Expanded(
                    child: GridView.builder(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                        childAspectRatio: 1.5,
                      ),
                      itemCount: AccentColors.all.length,
                      itemBuilder: (context, index) {
                        final color = AccentColors.all[index];
                        final isSelected = color.id == currentAccentColor.id;
                        return _buildColorOption(
                          context,
                          ref,
                          color,
                          isSelected,
                          isDarkMode,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackground(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: context.isDarkMode
              ? [
                  const Color(0xFF0F0F12),
                  const Color(0xFF1A1A2E),
                  const Color(0xFF16213E),
                ]
              : [
                  const Color(0xFFE8EEF5),
                  const Color(0xFFF5F7FA),
                  const Color(0xFFE4E9F2),
                ],
        ),
      ),
    );
  }

  Widget _buildColorOption(
    BuildContext context,
    WidgetRef ref,
    AccentColorOption color,
    bool isSelected,
    bool isDarkMode,
  ) {
    final displayColor = color.getColor(isDarkMode ? Brightness.dark : Brightness.light);
    final variantColor = color.getVariantColor(isDarkMode ? Brightness.dark : Brightness.light);

    return InkWell(
      onTap: () async {
        HapticFeedback.selectionClick();
        await ref.read(accentColorProvider.notifier).setAccentColor(color);
      },
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [displayColor, variantColor],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? Colors.white.withValues(alpha: 0.6)
                : Colors.white.withValues(alpha: 0.2),
            width: isSelected ? 3 : 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: displayColor.withValues(alpha: 0.3),
              blurRadius: isSelected ? 16 : 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              left: 16,
              bottom: 16,
              right: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    color.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                      fontFamily: 'ProductSans',
                      shadows: [
                        Shadow(
                          color: Colors.black26,
                          blurRadius: 4,
                        ),
                      ],
                    ),
                  ),
                  if (isSelected) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Active',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                          fontFamily: 'ProductSans',
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (isSelected)
              Positioned(
                top: 12,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.check,
                    size: 18,
                    color: displayColor,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
