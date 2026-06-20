import 'package:flutter/material.dart';
import 'models/accent_color.dart';
import 'screens/autofill_selection_screen.dart';
import 'themes/app_theme.dart';

class AutofillApp extends StatelessWidget {
  const AutofillApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Latch',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.getDarkTheme(AccentColors.blue),
      home: const AutofillSelectionScreen(),
    );
  }
}
