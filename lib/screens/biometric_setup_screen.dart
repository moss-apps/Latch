import 'dart:ui';
import 'package:flutter/material.dart';
import '../themes/app_colors.dart';
import '../services/auth_service.dart';
import '../widgets/adaptive_logo.dart';
import 'gallery_vault_screen.dart';

class BiometricSetupScreen extends StatefulWidget {
  const BiometricSetupScreen({super.key});

  @override
  State<BiometricSetupScreen> createState() => _BiometricSetupScreenState();
}

class _BiometricSetupScreenState extends State<BiometricSetupScreen> {
  final AuthService _authService = AuthService();
  bool _isLoading = false;
  String? _errorMessage;
  String _biometricType = 'Fingerprint';

  @override
  void initState() {
    super.initState();
    _loadBiometricType();
  }

  Future<void> _loadBiometricType() async {
    final biometrics = await _authService.getAvailableBiometrics();
    setState(() {
      _biometricType = _authService.getBiometricDisplayName(biometrics);
    });
  }

  Future<void> _handleSetupBiometric() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final isAvailable = await _authService.isBiometricAvailable();

    if (!isAvailable) {
      setState(() {
        _isLoading = false;
        _errorMessage =
            'Biometric authentication is not available on this device. Please ensure you have enrolled a fingerprint in your device settings.';
      });
      return;
    }

    final biometrics = await _authService.getAvailableBiometrics();

    if (biometrics.isEmpty) {
      setState(() {
        _isLoading = false;
        _errorMessage =
            'No biometric methods are enrolled. Please add a fingerprint in your device settings.';
      });
      return;
    }

    final success = await _authService.setupBiometricAuthentication();

    if (success && mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (context) => const GalleryVaultScreen(),
        ),
        (route) => false,
      );
    } else if (mounted) {
      setState(() {
        _isLoading = false;
        _errorMessage =
            'Biometric authentication setup was cancelled or failed. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.backgroundColor,
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: context.textPrimary),
          onPressed: _isLoading ? null : () => Navigator.pop(context),
        ),
        title: Text(
          'Biometric Setup',
          style: TextStyle(
            fontFamily: 'ProductSans',
            color: context.textPrimary,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Stack(
        children: [
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  const Spacer(),
                  _buildIcon(),
                  const SizedBox(height: 32),
                  _buildTitle(),
                  const SizedBox(height: 16),
                  _buildDescription(),
                  const SizedBox(height: 32),
                  if (_errorMessage != null) _buildError(),
                  const Spacer(),
                  _buildSetupButton(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIcon() {
    return Container(
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
          child: const Padding(
            padding: EdgeInsets.all(32),
            child: AdaptiveLogo(size: 76),
          ),
        ),
      ),
    );
  }

  Widget _buildTitle() {
    return Text(
      'Set up $_biometricType',
      style: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: context.textPrimary,
        fontFamily: 'ProductSans',
      ),
      textAlign: TextAlign.center,
    );
  }

  Widget _buildDescription() {
    return Text(
      'Use your device\'s $_biometricType to quickly and securely unlock your media vault.',
      style: TextStyle(
        fontSize: 16,
        color: context.textSecondary,
        fontFamily: 'ProductSans',
        height: 1.5,
      ),
      textAlign: TextAlign.center,
    );
  }

  Widget _buildError() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.error.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(14),
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

  Widget _buildSetupButton() {
    return Container(
      width: double.infinity,
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
        onPressed: _isLoading ? null : _handleSetupBiometric,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: _isLoading
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Text(
                'Set up $_biometricType',
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
