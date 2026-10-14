import 'package:flutter/material.dart';

import '../themes/app_colors.dart';
import '../widgets/toast_host.dart';

/// App-wide toast helpers. Messages are rendered by [ToastHost], which is
/// mounted next to the navigator, so toasts can be shown from any screen or
/// service without a `BuildContext`.
class ToastUtils {
  static void _show(
    String message, {
    Color? backgroundColor,
    Duration duration = const Duration(seconds: 2),
  }) {
    ToastHost.show(
      ToastMessage(
        message: message,
        backgroundColor: backgroundColor,
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
