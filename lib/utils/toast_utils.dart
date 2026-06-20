import 'package:flutter/material.dart';
import 'package:locker/themes/app_colors.dart';
import 'navigator_key.dart';

class ToastUtils {
  static void _show(
    String message, {
    Color? backgroundColor,
    Duration duration = const Duration(seconds: 2),
  }) {
    final context = navigatorKey.currentContext;
    if (context == null) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: backgroundColor,
          behavior: SnackBarBehavior.floating,
          duration: duration,
        ),
      );
  }

  static void showToast(String message) => _show(message);

  static void showSuccess(String message) =>
      _show(message, backgroundColor: AppColors.success);

  static void showError(String message) => _show(
        message,
        backgroundColor: AppColors.error,
        duration: const Duration(seconds: 3),
      );

  static void showInfo(String message) =>
      _show(message, backgroundColor: AppColors.info);

  static void showWarning(String message) =>
      _show(message, backgroundColor: AppColors.warning);
}
