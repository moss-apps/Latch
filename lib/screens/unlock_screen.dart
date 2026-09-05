import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../themes/app_colors.dart';
import '../providers/vault_providers.dart';
import '../services/auth_service.dart';
import '../services/decoy_service.dart';
import '../services/encryption_service.dart';
import '../services/pb/pocketbase_runtime.dart';
import '../services/vault_service.dart';
import '../widgets/adaptive_logo.dart';
import '../widgets/pin_input_widget.dart';
import 'gallery_vault_screen.dart';

// Unlock screen for returning users.
class UnlockScreen extends ConsumerStatefulWidget {
  const UnlockScreen({super.key});

  @override
  ConsumerState<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends ConsumerState<UnlockScreen> {
  final AuthService _authService = AuthService();
  final DecoyService _decoyService = DecoyService.instance;
  String? _authMethod;
  String? _errorMessage;
  bool _isLoading = true;
  bool _isAuthenticating = false;
  bool _obscurePassword = true;
  bool _autofillEnabled = false;
  String? _backupAuthMethod;
  bool _showingBackupAuth = false;
  final TextEditingController _passwordController = TextEditingController();
  final PinInputController _pinController = PinInputController();
  UnlockSecurityState _unlockSecurityState = const UnlockSecurityState();
  Timer? _lockoutTimer;

  static const _fast = Duration(milliseconds: 200);

  @override
  void initState() {
    super.initState();
    _initializeUnlockState();
  }

  @override
  void dispose() {
    _lockoutTimer?.cancel();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _initializeUnlockState() async {
    final method = await _authService.getAuthMethod();
    final unlockState = await _authService.getUnlockSecurityState();
    final backupMethod = await _authService.getBackupAuthMethod();
    final autofillEnabled = await _authService.isUnlockAutofillEnabled();

    if (!mounted) return;

    setState(() {
      _authMethod = method;
      _unlockSecurityState = unlockState;
      _backupAuthMethod = backupMethod;
      _autofillEnabled = autofillEnabled;
      _isLoading = false;
    });

    _syncLockoutTimer();

    // Auto-trigger biometric if that's the method
    if (method == 'biometric' && !unlockState.isLockedOut) {
      _handleBiometricAuth(showError: false);
    }
  }

  void _syncLockoutTimer() {
    _lockoutTimer?.cancel();
    if (!_unlockSecurityState.isLockedOut) return;

    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      final unlockState = await _authService.getUnlockSecurityState();
      if (!mounted) return;

      setState(() {
        _unlockSecurityState = unlockState;
      });

      if (!unlockState.isLockedOut) {
        _lockoutTimer?.cancel();
      }
    });
  }

  Future<void> _openVault({required bool isDecoy}) async {
    if (isDecoy) {
      await _decoyService.activateDecoyMode();
    } else {
      await _decoyService.deactivateDecoyMode();
      // Capture the notifier while still mounted; the provider is app-scoped
      // so the instance stays valid after this screen is replaced.
      final vaultNotifier = ref.read(vaultNotifierProvider.notifier);
      unawaited(_startPocketBase(vaultNotifier));
    }
    await _authService.resetUnlockAttempts();

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => const GalleryVaultScreen(),
      ),
    );
  }

  // PB holds only ciphertext, so it can't be used until the key exists — but
  // starting it must never block or fail the unlock. Recovery UI is P5.
  Future<void> _startPocketBase(VaultNotifier vaultNotifier) async {
    try {
      final settings = await VaultService.instance.getSettings();
      if (!settings.pbEnabled) return;
      await PocketBaseRuntime.instance.start();
      await VaultService.instance.activatePocketBase();
      // The gallery already rendered from the legacy index while PB was
      // starting; reload now that PB data backs the cache.
      await vaultNotifier.loadFiles();
    } catch (e) {
      debugPrint('[PB] activation failed, staying on legacy store: $e');
    }
  }

  Future<void> _handleFailedUnlock(String defaultMessage) async {
    final result = await _authService.registerFailedUnlockAttempt();
    final wipeMessage =
        result.vaultWiped ? ' Vault contents were permanently erased.' : '';
    final message = result.state.isLockedOut
        ? 'Too many failed attempts. Unlock is temporarily unavailable.$wipeMessage'
        : '$defaultMessage$wipeMessage';

    if (!mounted) return;

    setState(() {
      _unlockSecurityState = result.state;
      _errorMessage = message;
      _isLoading = false;
    });

    _syncLockoutTimer();
  }

  Future<bool> _tryOpenDecoyVault(String credential) async {
    final result = await _decoyService.checkIfDecoyCredential(credential);
    if (!result.isDecoy) return false;

    try {
      await EncryptionService.instance
          .unlockMasterKey(credential, isDecoy: true);
    } catch (e) {
      debugPrint('Decoy key unlock failed: $e');
      return false;
    }

    await _openVault(isDecoy: true);
    return true;
  }

  String _formatDuration(Duration duration) {
    final safeDuration = duration.isNegative ? Duration.zero : duration;
    final hours = safeDuration.inHours;
    final minutes = safeDuration.inMinutes.remainder(60);
    final seconds = safeDuration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }

    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _handlePinComplete(String pin) async {
    if (_unlockSecurityState.isLockedOut || _isAuthenticating) {
      _pinController.clear();
      return;
    }

    setState(() {
      _isAuthenticating = true;
      _errorMessage = null;
    });

    if (await _tryOpenDecoyVault(pin)) {
      return;
    }

    final isValid = await _authService.verifyPIN(pin);

    if (isValid && mounted) {
      try {
        await EncryptionService.instance.unlockMasterKey(pin);
        await _openVault(isDecoy: false);
      } catch (e) {
        debugPrint('Master key unlock failed: $e');
        await _handleFailedUnlock('Incorrect PIN.');
        _pinController.clear();
      }
    } else if (mounted) {
      await _handleFailedUnlock('Incorrect PIN.');
      _pinController.clear();
    }

    if (mounted) {
      setState(() {
        _isAuthenticating = false;
      });
    }
  }

  void _handlePinChanged() {
    // Only trigger rebuild if there's an error to clear
    if (_errorMessage != null) {
      setState(() => _errorMessage = null);
    }
  }

  Future<void> _handlePasswordAuth() async {
    if (_unlockSecurityState.isLockedOut || _isAuthenticating) return;

    final password = _passwordController.text;

    if (password.isEmpty) {
      setState(() => _errorMessage = 'Please enter your password');
      return;
    }

    setState(() {
      _isAuthenticating = true;
      _errorMessage = null;
    });

    if (await _tryOpenDecoyVault(password)) {
      if (mounted) {
        setState(() => _isAuthenticating = false);
      }
      return;
    }

    final isValid = await _authService.verifyPassword(password);

    if (isValid && mounted) {
      try {
        await EncryptionService.instance.unlockMasterKey(password);
        await _openVault(isDecoy: false);
      } catch (e) {
        debugPrint('Master key unlock failed: $e');
        await _handleFailedUnlock('Incorrect password.');
        _passwordController.clear();
      }
    } else if (mounted) {
      await _handleFailedUnlock('Incorrect password.');
      _passwordController.clear();
    }

    if (mounted) {
      setState(() => _isAuthenticating = false);
    }
  }

  Future<void> _handleBiometricAuth({
    bool countFailure = true,
    bool showError = true,
  }) async {
    if (_unlockSecurityState.isLockedOut || _isAuthenticating) return;

    setState(() {
      _isAuthenticating = true;
      if (showError) {
        _errorMessage = null;
      }
    });

    final result = await _authService.performBiometricAuthentication();

    if (result.isSuccess && mounted) {
      try {
        await EncryptionService.instance.unlockMasterKeyWithBiometric();
        await _openVault(isDecoy: false);
      } catch (e) {
        debugPrint('Biometric key unlock failed: $e');
        setState(() {
          _errorMessage =
              'Unable to unlock vault. Please use your backup credential.';
          _isAuthenticating = false;
        });
      }
    } else if (mounted) {
      if (countFailure && result.shouldCountAsFailedUnlock) {
        await _handleFailedUnlock('Biometric authentication failed.');
      } else if (showError) {
        setState(() {
          _errorMessage =
              result.status == BiometricAuthenticationStatus.canceled
                  ? 'Biometric authentication was cancelled.'
                  : 'Biometric authentication is currently unavailable.';
        });
      }
    }

    if (mounted) {
      setState(() {
        _isAuthenticating = false;
      });
    }
  }

  bool get _inputEnabled =>
      !_unlockSecurityState.isLockedOut && !_isAuthenticating;

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _authMethod == null) {
      return Scaffold(
        backgroundColor: context.backgroundColor,
        body: Center(
          child: CircularProgressIndicator(
            color: context.accentColor,
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: context.backgroundColor,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) => Opacity(
                opacity: value,
                child: Transform.translate(
                  offset: Offset(0, (1 - value) * 12),
                  child: child,
                ),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildLogo(),
                    const SizedBox(height: 24),
                    _buildAppName(),
                    const SizedBox(height: 8),
                    _buildInstruction(),
                    const SizedBox(height: 32),
                    _buildAuthWidget(),
                    const SizedBox(height: 16),
                    _buildErrorSlot(),
                    _buildSecuritySlot(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return Center(
      child: Container(
        width: 88,
        height: 88,
        decoration: BoxDecoration(
          color: context.surfaceColor,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: context.borderColor),
        ),
        child: const Padding(
          padding: EdgeInsets.all(20),
          child: AdaptiveLogo(size: 48),
        ),
      ),
    );
  }

  Widget _buildAppName() {
    return Text(
      'Latch',
      style: TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        color: context.textPrimary,
        fontFamily: 'ProductSans',
        letterSpacing: -0.5,
      ),
      textAlign: TextAlign.center,
    );
  }

  Widget _buildInstruction() {
    final lockedOut = _unlockSecurityState.isLockedOut;
    final String label;

    if (lockedOut) {
      label = 'Vault is temporarily locked';
    } else if (_showingBackupAuth && _backupAuthMethod != null) {
      label = _backupAuthMethod == 'pin'
          ? 'Enter your backup PIN to unlock'
          : 'Enter your backup password to unlock';
    } else {
      label = switch (_authMethod) {
        'pin' => 'Enter your PIN to unlock',
        'password' => 'Enter your password to unlock',
        _ => 'Use biometrics to unlock',
      };
    }

    return Text(
      label,
      style: TextStyle(
        fontSize: 15,
        color: context.textSecondary,
        fontFamily: 'ProductSans',
      ),
      textAlign: TextAlign.center,
    );
  }

  Widget _buildAuthWidget() {
    if (_authMethod == 'biometric' && _showingBackupAuth) {
      return _wrapAutofill(_buildBackupAuthWidget());
    }
    if (_authMethod == 'pin') {
      return _wrapAutofill(_buildPinAuth());
    } else if (_authMethod == 'password') {
      return _wrapAutofill(_buildPasswordAuth());
    } else if (_authMethod == 'biometric') {
      return _buildBiometricAuth();
    }
    return const SizedBox.shrink();
  }

  Widget _wrapAutofill(Widget child) {
    if (!_autofillEnabled) return child;
    return AutofillGroup(child: child);
  }

  Widget _buildPinAuth() {
    return PinInputWidget(
      onPinComplete: _handlePinComplete,
      onPinChanged: _handlePinChanged,
      errorMessage: _errorMessage,
      controller: _pinController,
      enabled: _inputEnabled,
      autofillEnabled: _autofillEnabled,
      isLoading: _isAuthenticating,
    );
  }

  Widget _buildPasswordAuth() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _passwordController,
          autofocus: true,
          enabled: _inputEnabled,
          obscureText: _obscurePassword,
          autofillHints:
              _autofillEnabled ? const [AutofillHints.password] : null,
          style: TextStyle(
            fontFamily: 'ProductSans',
            fontSize: 16,
            color: context.textPrimary,
          ),
          decoration: InputDecoration(
            labelText: 'Password',
            hintText: 'Enter your password',
            labelStyle: TextStyle(
              fontFamily: 'ProductSans',
              color: context.textSecondary,
            ),
            hintStyle: TextStyle(
              fontFamily: 'ProductSans',
              color: context.textTertiary,
            ),
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                color: context.textTertiary,
              ),
              onPressed: () {
                setState(() {
                  _obscurePassword = !_obscurePassword;
                });
              },
            ),
            filled: true,
            fillColor: context.backgroundSecondary,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: context.borderColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: context.borderColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: context.accentColor, width: 1.6),
            ),
          ),
          onChanged: (_) {
            if (_errorMessage != null) {
              setState(() => _errorMessage = null);
            }
          },
          onSubmitted: (_) => _handlePasswordAuth(),
        ),
        const SizedBox(height: 16),
        _buildUnlockButton(),
      ],
    );
  }

  Widget _buildBiometricAuth() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(child: _buildFingerprintButton()),
        if (_backupAuthMethod != null) ...[
          const SizedBox(height: 20),
          Center(
            child: TextButton(
              onPressed: () {
                setState(() {
                  _showingBackupAuth = true;
                  _errorMessage = null;
                });
              },
              child: Text(
                _backupAuthMethod == 'pin'
                    ? 'Use Backup PIN'
                    : 'Use Backup Password',
                style: TextStyle(
                  color: context.textSecondary,
                  fontFamily: 'ProductSans',
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildFingerprintButton() {
    return Semantics(
      button: true,
      label: 'Unlock with biometrics',
      child: Material(
        color:
            context.accentColor.withValues(alpha: _inputEnabled ? 0.12 : 0.06),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _inputEnabled ? () => _handleBiometricAuth() : null,
          child: SizedBox(
            width: 88,
            height: 88,
            child: Center(
              child: _isAuthenticating
                  ? SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: context.accentColor,
                      ),
                    )
                  : Icon(
                      Icons.fingerprint,
                      size: 44,
                      color: _inputEnabled
                          ? context.accentColor
                          : context.textTertiary,
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBackupAuthWidget() {
    final isPin = _backupAuthMethod == 'pin';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isPin) _buildPinAuth() else _buildPasswordAuth(),
        const SizedBox(height: 8),
        Center(
          child: TextButton(
            onPressed: () {
              setState(() {
                _showingBackupAuth = false;
                _errorMessage = null;
                _passwordController.clear();
                _pinController.clear();
              });
            },
            child: Text(
              'Use biometric instead',
              style: TextStyle(
                color: context.textSecondary,
                fontFamily: 'ProductSans',
                fontSize: 14,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildUnlockButton() {
    final onColor = Theme.of(context).colorScheme.onPrimary;

    return FilledButton(
      onPressed: _inputEnabled ? _handlePasswordAuth : null,
      style: FilledButton.styleFrom(
        backgroundColor: context.accentColor,
        foregroundColor: onColor,
        disabledBackgroundColor: context.accentColor.withValues(alpha: 0.35),
        minimumSize: const Size.fromHeight(52),
        textStyle: const TextStyle(
          fontFamily: 'ProductSans',
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      child: _isAuthenticating
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: onColor,
                  ),
                ),
                const SizedBox(width: 12),
                const Text('Unlocking\u2026'),
              ],
            )
          : const Text('Unlock'),
    );
  }

  Widget _buildErrorSlot() {
    return AnimatedSize(
      duration: _fast,
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: _errorMessage == null
          ? const SizedBox(width: double.infinity)
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline, size: 18, color: AppColors.error),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    _errorMessage!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.error,
                      fontSize: 14,
                      height: 1.3,
                      fontFamily: 'ProductSans',
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  // Lockout countdown / attempts-remaining notice. Only takes space when
  // there is something at stake to tell the user.
  Widget _buildSecuritySlot() {
    final state = _unlockSecurityState;
    final Color color;
    final IconData icon;
    final String message;

    if (state.isLockedOut) {
      color = AppColors.error;
      icon = Icons.lock_clock;
      message =
          'Too many failed attempts. Try again in ${_formatDuration(state.remainingLockout)}.';
    } else if (state.protectionEnabled && state.failedAttempts > 0) {
      final beforeWipe = state.attemptsRemainingBeforeWipe;
      if (beforeWipe != null) {
        color = AppColors.error;
        icon = Icons.warning_amber_rounded;
        message =
            '$beforeWipe attempts remaining before your vault is permanently erased.';
      } else {
        color = context.isDarkMode ? AppColors.darkWarning : AppColors.warning;
        icon = Icons.warning_amber_rounded;
        message =
            '${state.attemptsRemainingBeforeLockout} attempts remaining before temporary lockout.';
      }
    } else {
      return const SizedBox(width: double.infinity);
    }

    return AnimatedSize(
      duration: _fast,
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: color,
                  fontSize: 13,
                  height: 1.3,
                  fontFamily: 'ProductSans',
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
