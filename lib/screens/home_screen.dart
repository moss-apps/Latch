import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:local_auth/local_auth.dart';
import '../services/auth_service.dart';
import '../themes/app_colors.dart';
import '../utils/toast_utils.dart';
import 'gallery_vault_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final AuthService _authService = AuthService();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  bool _isLoading = true;
  bool _isFirstTime = true;
  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;
  bool _isBiometricAvailable = false;
  bool _isBiometricEnabled = false;
  List<BiometricType> _availableBiometrics = [];
  String _biometricDisplayName = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkBiometricState();
    }
  }

  Future<void> _initialize() async {
    await _checkAuthState();
    await _checkBiometricState();
    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _checkAuthState() async {
    final isFirstTime = await _authService.isFirstTime();
    setState(() {
      _isFirstTime = isFirstTime;
    });
  }

  Future<void> _checkBiometricState() async {
    final isAvailable = await _authService.isBiometricAvailable();
    final isEnabled = await _authService.isBiometricEnabled();
    final biometrics = await _authService.getAvailableBiometrics();
    final displayName = _authService.getBiometricDisplayName(biometrics);

    setState(() {
      _isBiometricAvailable = isAvailable;
      _isBiometricEnabled = isEnabled;
      _availableBiometrics = biometrics;
      _biometricDisplayName = displayName;
    });
  }

  Future<void> _createPassword() async {
    final password = _passwordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();

    if (password.isEmpty) {
      ToastUtils.showError('Please enter a password');
      return;
    }

    if (password.length < 6) {
      ToastUtils.showError('Password must be at least 6 characters');
      return;
    }

    if (password != confirmPassword) {
      ToastUtils.showError('Passwords do not match');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final success = await _authService.createPassword(password);
    if (success) {
      ToastUtils.showSuccess('Password created successfully');
      _passwordController.clear();
      _confirmPasswordController.clear();

      // Check if user wants to set up biometrics
      if (_isBiometricAvailable) {
        _showBiometricSetupDialog();
      } else {
        _navigateToMainApp();
      }
    } else {
      ToastUtils.showError('Failed to create password');
    }

    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _authenticateWithPassword() async {
    final password = _passwordController.text.trim();

    if (password.isEmpty) {
      ToastUtils.showError('Please enter your password');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final success = await _authService.verifyPassword(password);
    if (success) {
      _passwordController.clear();
      _navigateToMainApp();
    } else {
      ToastUtils.showError('Incorrect password');
      // Clear password field for security
      _passwordController.clear();
    }

    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _authenticateWithBiometrics() async {
    setState(() {
      _isLoading = true;
    });

    final success = await _authService.authenticateWithBiometrics();
    if (success) {
      _navigateToMainApp();
    } else {
      ToastUtils.showError('Biometric authentication failed');
    }

    setState(() {
      _isLoading = false;
    });
  }

  void _showBiometricSetupDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Set up $_biometricDisplayName'),
        content: Text(
          'Would you like to enable $_biometricDisplayName authentication for faster login?',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _navigateToMainApp();
            },
            child: const Text('Not now'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await _setupBiometrics();
            },
            child: const Text('Set up'),
          ),
        ],
      ),
    );
  }

  Future<void> _setupBiometrics() async {
    setState(() {
      _isLoading = true;
    });

    final success = await _authService.setupBiometricAuthentication();
    if (success) {
      ToastUtils.showSuccess('$_biometricDisplayName enabled successfully');
      await _checkBiometricState();
    } else {
      ToastUtils.showError('Failed to enable $_biometricDisplayName');
    }

    setState(() {
      _isLoading = false;
    });

    _navigateToMainApp();
  }

  void _navigateToMainApp() {
    // Navigate to the main gallery vault screen
    // Using pushReplacement to prevent going back to login screen
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => const GalleryVaultScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: context.backgroundColor,
        body: Stack(
          children: [
            _buildBackground(),
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(
                    color: context.accentColor,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Loading...',
                    style: TextStyle(
                      fontFamily: 'ProductSans',
                      color: context.textSecondary,
                    ),
                  ),
                ],
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
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Spacer(),
                  _buildLogo(),
                  const SizedBox(height: 24),
                  _buildTitle(),
                  const SizedBox(height: 12),
                  _buildSubtitle(),
                  const SizedBox(height: 48),
                  _buildPasswordFields(),
                  const SizedBox(height: 24),
                  _buildPrimaryButton(),
                  if (!_isFirstTime &&
                      _isBiometricAvailable &&
                      _isBiometricEnabled)
                    _buildBiometricSection(),
                  if (_isFirstTime) _buildHelperText(),
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
              padding: const EdgeInsets.all(28),
              child: SvgPicture.asset(
                'assets/locker_logo_nobg.svg',
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTitle() {
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

  Widget _buildSubtitle() {
    return Text(
      _isFirstTime
          ? 'Create your secure password'
          : 'Enter your password to continue',
      style: TextStyle(
        fontSize: 16,
        color: context.textSecondary,
        fontFamily: 'ProductSans',
      ),
      textAlign: TextAlign.center,
    );
  }

  Widget _buildPasswordFields() {
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
            children: [
              TextField(
                controller: _passwordController,
                obscureText: !_isPasswordVisible,
                style: TextStyle(
                  fontFamily: 'ProductSans',
                  fontSize: 16,
                  color: context.textPrimary,
                ),
                decoration: InputDecoration(
                  labelText: _isFirstTime ? 'Create Password' : 'Password',
                  labelStyle: TextStyle(
                    fontFamily: 'ProductSans',
                    color: context.textSecondary,
                  ),
                  filled: true,
                  fillColor: context.isDarkMode
                      ? Colors.white.withValues(alpha: 0.05)
                      : Colors.black.withValues(alpha: 0.03),
                  prefixIcon: Icon(
                    Icons.lock_outline,
                    color: context.textTertiary,
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _isPasswordVisible
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: context.textTertiary,
                    ),
                    onPressed: () {
                      setState(() {
                        _isPasswordVisible = !_isPasswordVisible;
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
                    borderSide: BorderSide(color: context.accentColor, width: 2),
                  ),
                ),
                onSubmitted: _isFirstTime
                    ? null
                    : (value) => _authenticateWithPassword(),
              ),
              if (_isFirstTime) ...[
                const SizedBox(height: 16),
                TextField(
                  controller: _confirmPasswordController,
                  obscureText: !_isConfirmPasswordVisible,
                  style: TextStyle(
                    fontFamily: 'ProductSans',
                    fontSize: 16,
                    color: context.textPrimary,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Confirm Password',
                    labelStyle: TextStyle(
                      fontFamily: 'ProductSans',
                      color: context.textSecondary,
                    ),
                    filled: true,
                    fillColor: context.isDarkMode
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.black.withValues(alpha: 0.03),
                    prefixIcon: Icon(
                      Icons.lock_outline,
                      color: context.textTertiary,
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _isConfirmPasswordVisible
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        color: context.textTertiary,
                      ),
                      onPressed: () {
                        setState(() {
                          _isConfirmPasswordVisible =
                              !_isConfirmPasswordVisible;
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
                  onSubmitted: (value) => _createPassword(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPrimaryButton() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: [
            context.accentColor,
            context.accentColor.withValues(alpha: 0.8),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: context.accentColor.withValues(alpha: 0.4),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed:
            _isFirstTime ? _createPassword : _authenticateWithPassword,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Text(
          _isFirstTime ? 'Create Password' : 'Unlock',
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

  Widget _buildBiometricSection() {
    return Column(
      children: [
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: Divider(
                color: context.isDarkMode
                    ? Colors.white.withValues(alpha: 0.1)
                    : Colors.black.withValues(alpha: 0.1),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'OR',
                style: TextStyle(
                  fontFamily: 'ProductSans',
                  color: context.textTertiary,
                  fontSize: 12,
                ),
              ),
            ),
            Expanded(
              child: Divider(
                color: context.isDarkMode
                    ? Colors.white.withValues(alpha: 0.1)
                    : Colors.black.withValues(alpha: 0.1),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
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
              child: OutlinedButton.icon(
                onPressed: _authenticateWithBiometrics,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  side: BorderSide.none,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: Icon(
                  _getBiometricIcon(),
                  color: context.accentColor,
                ),
                label: Text(
                  'Use $_biometricDisplayName',
                  style: TextStyle(
                    fontSize: 16,
                    fontFamily: 'ProductSans',
                    color: context.textPrimary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHelperText() {
    return Padding(
      padding: const EdgeInsets.only(top: 32),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.isDarkMode
                  ? Colors.white.withValues(alpha: 0.03)
                  : Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: context.isDarkMode
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.white.withValues(alpha: 0.15),
                width: 1,
              ),
            ),
            child: Text(
              'Your password will be securely encrypted and stored locally on your device.',
              style: TextStyle(
                fontSize: 13,
                color: context.textSecondary,
                fontFamily: 'ProductSans',
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }

  IconData _getBiometricIcon() {
    if (_availableBiometrics.contains(BiometricType.fingerprint)) {
      return Icons.fingerprint;
    } else if (_availableBiometrics.contains(BiometricType.face)) {
      return Icons.face;
    } else {
      return Icons.security;
    }
  }
}
