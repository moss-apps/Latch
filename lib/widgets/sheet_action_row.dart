import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../themes/app_colors.dart';

/// Full-width action row for bottom sheets. Pops the enclosing sheet, then
/// fires [onTap]. Rows with a null [onTap] render dimmed and inert.
class SheetActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool isDestructive;

  const SheetActionRow({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = isDestructive ? AppColors.error : context.textSecondary;

    return Opacity(
      opacity: onTap != null ? 1 : 0.4,
      child: InkWell(
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                Navigator.pop(context);
                onTap!();
              },
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          child: Row(
            children: [
              Icon(icon, size: 22, color: color),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'ProductSans',
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: isDestructive ? color : context.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
