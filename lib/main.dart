import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:url_launcher/url_launcher.dart';
import 'services/auto_kill_service.dart';
import 'services/screenshot_protection_service.dart';
import 'services/update_service.dart';
import 'services/vault_service.dart';
import 'themes/app_theme.dart';
import 'providers/theme_provider.dart';
import 'providers/vault_providers.dart';
import 'services/auth_service.dart';
import 'screens/auth_method_selection_screen.dart';
import 'screens/unlock_screen.dart';
import 'autofill_app.dart';
import 'utils/frame_rate_optimizer.dart';
import 'utils/navigator_key.dart';
import 'utils/performance_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  PerformanceConfig.configureHighFrameRate();
  PerformanceConfig.optimizeImageCache();

  FrameRateOptimizer().startMonitoring();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  final settings = await VaultService.instance.getSettings();
  await AutoKillService.setDelaySeconds(settings.autoKillDelaySeconds);
  await ScreenshotProtectionService.setEnabled(
    settings.screenshotProtectionEnabled,
  );

  UpdateService.instance.start();

  runApp(const ProviderScope(child: LatchApp()));
}

class LatchApp extends ConsumerWidget {
  const LatchApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final accentColor = ref.watch(accentColorProvider);

    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'Latch',
      theme: AppTheme.getLightTheme(accentColor),
      darkTheme: AppTheme.getDarkTheme(accentColor),
      themeMode: themeMode,
      home: const AppInitializer(),
    );
  }
}

class AppInitializer extends ConsumerStatefulWidget {
  const AppInitializer({super.key});

  @override
  ConsumerState<AppInitializer> createState() => _AppInitializerState();
}

class _AppInitializerState extends ConsumerState<AppInitializer> {
  final AuthService _authService = AuthService();
  bool _isLoading = true;
  bool _isFirstTime = true;
  StreamSubscription<PendingUpdate?>? _updateSub;

  @override
  void initState() {
    super.initState();
    _checkAuthStatus();

    final updateService = ref.read(updateServiceProvider);
    _updateSub = updateService.onUpdateCheck.listen((update) async {
      if (update == null) return;
      if (await updateService.isVersionSkipped(update.latestVersion)) return;
      _showUpdateDialog(update);
    });
  }

  @override
  void dispose() {
    _updateSub?.cancel();
    super.dispose();
  }

  void _showUpdateDialog(PendingUpdate update) {
    final context = navigatorKey.currentContext;
    if (context == null) return;
    final isPlayStore = update.source == InstallSource.playStore;
    final message = isPlayStore
        ? 'A new version is available on the Play Store. Update now?'
        : 'A new version${update.latestVersion != null ? ' (${update.latestVersion})' : ''}'
            ' is available on GitHub. Open the download page?';
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor:
            Theme.of(dialogContext).scaffoldBackgroundColor,
        title: const Text('Update Available',
            style: TextStyle(fontFamily: 'ProductSans')),
        content: Text(
          message,
          style: const TextStyle(fontFamily: 'ProductSans'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Later'),
          ),
          if (!isPlayStore && update.latestVersion != null)
            TextButton(
              onPressed: () {
                ref
                    .read(updateServiceProvider)
                    .skipVersion(update.latestVersion!);
                Navigator.pop(dialogContext);
              },
              child: const Text("Don't show again"),
            ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              if (isPlayStore) {
                InAppUpdate.performImmediateUpdate();
              } else {
                final url = Uri.parse(
                  update.releaseUrl ??
                      'https://github.com/moss-apps/Latch/releases/latest',
                );
                launchUrl(url, mode: LaunchMode.externalApplication);
              }
            },
            child: Text(isPlayStore ? 'Update' : 'Open'),
          ),
        ],
      ),
    );
  }

  Future<void> _checkAuthStatus() async {
    final isFirstTime = await _authService.isFirstTime();

    setState(() {
      _isFirstTime = isFirstTime;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: isDarkMode ? const Color(0xFF1A1A1D) : Colors.white,
        body: Center(
          child: CircularProgressIndicator(
            color:
                isDarkMode ? const Color(0xFF5C9CE6) : const Color(0xFF1976D2),
          ),
        ),
      );
    }

    if (_isFirstTime) {
      return const AuthMethodSelectionScreen();
    } else {
      return const UnlockScreen();
    }
  }
}

@pragma('vm:entry-point')
void autofillMain() => runApp(AutofillApp());
