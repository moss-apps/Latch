import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../themes/app_colors.dart';
import '../services/auth_service.dart';
import '../services/decoy_service.dart';
import '../widgets/pin_input_widget.dart';
import 'gallery_vault_screen.dart';

// Unlock screen for returning users.
class UnlockScreen extends StatefulWidget {
  const UnlockScreen({super.key});

  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen> {
  final AuthService _authService = AuthService();
  final DecoyService _decoyService = DecoyService.instance;
  String? _authMethod;
  String? _errorMessage;
  bool _isLoading = true;
  bool _isAuthenticating = false;
  bool _obscurePassword = true;
  String? _backupAuthMethod;
  bool _showingBackupAuth = false;
  final TextEditingController _passwordController = TextEditingController();
  final PinInputController _pinController = PinInputController();
  UnlockSecurityState _unlockSecurityState = const UnlockSecurityState();
  Timer? _lockoutTimer;

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

    if (!mounted) return;

    setState(() {
      _authMethod = method;
      _unlockSecurityState = unlockState;
      _backupAuthMethod = backupMethod;
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
    }
    await _authService.resetUnlockAttempts();

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => const GalleryVaultScreen(),
      ),
    );
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
      await _openVault(isDecoy: false);
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

    // Batch state update for loading state
    setState(() {
      _isLoading = true;
      _isAuthenticating = true;
      _errorMessage = null;
    });

    if (await _tryOpenDecoyVault(password)) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isAuthenticating = false;
        });
      }
      return;
    }

    final isValid = await _authService.verifyPassword(password);

    if (isValid && mounted) {
      await _openVault(isDecoy: false);
    } else if (mounted) {
      await _handleFailedUnlock('Incorrect password.');
      _passwordController.clear();
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
        _isAuthenticating = false;
      });
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
      await _openVault(isDecoy: false);
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _authMethod == null) {
      return Scaffold(
        backgroundColor: context.backgroundColor,
        body: Stack(
          children: [
            _buildBackground(),
            Center(
              child: CircularProgressIndicator(
                color: context.accentColor,
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: context.backgroundColor,
      body: Stack(
        children: [
          _buildBackground(),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Spacer(),
                  _buildLogo(),
                  const SizedBox(height: 32),
                  _buildAppName(),
                  const SizedBox(height: 12),
                  _buildInstruction(),
                  if (_unlockSecurityState.protectionEnabled ||
                      _unlockSecurityState.isLockedOut) ...[
                    const SizedBox(height: 16),
                    _buildProtectionStatus(),
                  ],
                  const SizedBox(height: 64),
                  _buildAuthWidget(),
                  const Spacer(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackground() {
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

  Widget _buildLogo() {
    return Center(
      child: Container(
        width: 140,
        height: 140,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: context.isDarkMode
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.white.withValues(alpha: 0.15),
          border: Border.all(
            color: context.isDarkMode
                ? Colors.white.withValues(alpha: 0.15)
                : Colors.white.withValues(alpha: 0.2),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: context.accentColor.withValues(alpha: 0.2),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: SvgPicture.asset(
                'assets/locker_logo_nobg.svg',
                fit: BoxFit.contain,
                colorFilter: ColorFilter.mode(
                  context.isDarkMode ? const Color(0xFFF5F5F5) : Colors.black,
                  BlendMode.srcIn,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAppName() {
    return Text(
      'Latch',
      style: TextStyle(
        fontSize: 36,
        fontWeight: FontWeight.w700,
        color: context.textPrimary,
        fontFamily: 'ProductSans',
        letterSpacing: -0.5,
      ),
      textAlign: TextAlign.center,
    );
  }

  Widget _buildInstruction() {
    final label = _showingBackupAuth && _backupAuthMethod != null
        ? (_backupAuthMethod == 'pin'
            ? 'Enter your backup PIN to unlock'
            : 'Enter your backup password to unlock')
        : (_authMethod == 'pin'
            ? 'Enter your PIN to unlock'
            : _authMethod == 'password'
                ? 'Enter your password to unlock'
                : 'Use biometrics to unlock');

    return Text(
      label,
      style: TextStyle(
        fontSize: 16,
        color: context.textSecondary,
        fontFamily: 'ProductSans',
      ),
      textAlign: TextAlign.center,
    );
  }

  Widget _buildAuthWidget() {
    if (_authMethod == 'biometric' && _showingBackupAuth) {
      return _buildBackupAuthWidget();
    }
    if (_authMethod == 'pin') {
      return _buildPinAuth();
    } else if (_authMethod == 'password') {
      return _buildPasswordAuth();
    } else if (_authMethod == 'biometric') {
      return _buildBiometricAuth();
    }
    return const SizedBox.shrink();
  }

  Widget _buildPinAuth() {
    return Column(
      children: [
        PinInputWidget(
          onPinComplete: _handlePinComplete,
          onPinChanged: _handlePinChanged,
          errorMessage: _errorMessage,
          controller: _pinController,
          enabled: !_unlockSecurityState.isLockedOut,
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 16),
          _buildError(),
        ],
      ],
    );
  }

  Widget _buildPasswordAuth() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: context.isDarkMode
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: context.isDarkMode
                  ? Colors.white.withValues(alpha: 0.1)
                  : Colors.white.withValues(alpha: 0.2),
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _passwordController,
                enabled: !_unlockSecurityState.isLockedOut &&
                    !_isLoading &&
                    !_isAuthenticating,
                obscureText: _obscurePassword,
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
                  filled: true,
                  fillColor: context.isDarkMode
                      ? Colors.white.withValues(alpha: 0.05)
                      : Colors.black.withValues(alpha: 0.03),
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
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        BorderSide(color: context.accentColor, width: 2),
                  ),
                ),
                onChanged: (_) {
                  if (_errorMessage != null) {
                    setState(() => _errorMessage = null);
                  }
                },
                onSubmitted: (_) => _handlePasswordAuth(),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                _buildError(),
              ],
              const SizedBox(height: 24),
              _buildUnlockButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBiometricAuth() {
    return Column(
      children: [
        Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: context.isDarkMode
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.white.withValues(alpha: 0.15),
            border: Border.all(
              color: context.isDarkMode
                  ? Colors.white.withValues(alpha: 0.15)
                  : Colors.white.withValues(alpha: 0.2),
              width: 2,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Icon(
                Icons.fingerprint,
                size: 64,
                color:
                    context.isDarkMode ? const Color(0xFFF5F5F5) : Colors.black,
              ),
            ),
          ),
        ),
        const SizedBox(height: 32),
        if (_errorMessage != null) ...[
          _buildError(),
          const SizedBox(height: 24),
        ],
        _buildUnlockButton(isBiometric: true),
        if (_backupAuthMethod != null) ...[
          const SizedBox(height: 16),
          TextButton(
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
        ],
      ],
    );
  }

  Widget _buildBackupAuthWidget() {
    final isPin = _backupAuthMethod == 'pin';
    return Column(
      children: [
        TextButton(
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
        const SizedBox(height: 16),
        isPin ? _buildPinAuth() : _buildPasswordAuth(),
      ],
    );
  }

  Widget _buildError() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.error.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.error.withValues(alpha: 0.2),
              width: 1,
            ),
          ),
          child: Text(
            _errorMessage!,
            style: TextStyle(
              color: AppColors.error,
              fontSize: 14,
              fontFamily: 'ProductSans',
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  Widget _buildProtectionStatus() {
    final message = _unlockSecurityState.isLockedOut
        ? 'Unlock available again in ${_formatDuration(_unlockSecurityState.remainingLockout)}.'
        : 'Failed-attempt protection is enabled.';

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: context.isDarkMode
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.white.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _unlockSecurityState.isLockedOut
                  ? AppColors.error.withValues(alpha: 0.25)
                  : context.borderColor,
            ),
          ),
          child: Text(
            message,
            style: TextStyle(
              color: _unlockSecurityState.isLockedOut
                  ? AppColors.error
                  : context.textSecondary,
              fontSize: 13,
              fontFamily: 'ProductSans',
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  Widget _buildUnlockButton({bool isBiometric = false}) {
    final isEnabled =
        !_unlockSecurityState.isLockedOut && !_isLoading && !_isAuthenticating;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: [
            context.accentColor.withValues(alpha: isEnabled ? 1 : 0.45),
            context.accentColor.withValues(alpha: isEnabled ? 0.8 : 0.35),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color:
                context.accentColor.withValues(alpha: isEnabled ? 0.4 : 0.12),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: isEnabled
            ? (isBiometric ? _handleBiometricAuth : _handlePasswordAuth)
            : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 30),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Text(
          isBiometric ? 'Unlock with Biometric' : 'Unlock',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            fontFamily: 'ProductSans',
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
