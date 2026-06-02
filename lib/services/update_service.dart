import 'dart:async';
import 'dart:io' show Platform;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:in_app_update/in_app_update.dart';

class UpdateService {
  UpdateService._();
  static final UpdateService instance = UpdateService._();

  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool _isChecking = false;

  AppUpdateInfo? _lastUpdateInfo;
  AppUpdateInfo? get lastUpdateInfo => _lastUpdateInfo;

  bool _hasPendingUpdate = false;
  bool get hasPendingUpdate => _hasPendingUpdate;

  final _updateController = StreamController<AppUpdateInfo?>.broadcast();
  Stream<AppUpdateInfo?> get onUpdateCheck => _updateController.stream;

  void start() {
    if (!Platform.isAndroid) return;

    _checkForUpdate();

    _subscription = Connectivity().onConnectivityChanged.listen((results) {
      final hasConnection = results.any((r) => r != ConnectivityResult.none);
      if (hasConnection) {
        _checkForUpdate();
      }
    });
  }

  void dispose() {
    _subscription?.cancel();
    _updateController.close();
  }

  Future<AppUpdateInfo?> checkForUpdate() async {
    await _checkForUpdate();
    return _lastUpdateInfo;
  }

  Future<void> _checkForUpdate() async {
    if (_isChecking) return;
    _isChecking = true;
    try {
      _lastUpdateInfo = await InAppUpdate.checkForUpdate();
      _hasPendingUpdate = _lastUpdateInfo?.updateAvailability ==
          UpdateAvailability.updateAvailable;
      _updateController.add(_lastUpdateInfo);
    } catch (_) {
      _lastUpdateInfo = null;
      _hasPendingUpdate = false;
      _updateController.add(null);
    } finally {
      _isChecking = false;
    }
  }
}
