import 'dart:ui';
import 'package:flutter/material.dart';
import '../themes/app_colors.dart';
import '../services/auth_service.dart';
import '../widgets/adaptive_logo.dart';
import 'gallery_vault_screen.dart';

class PasswordSetupScreen extends StatefulWidget {
  const PasswordSetupScreen({super.key});

  @override
  State<PasswordSetupScreen> createState() => _PasswordSetupScreenState();
}

class _PasswordSetupScreenState extends State<PasswordSetupScreen> {
  final AuthService _authService = AuthService();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  bool _isConfirmation = false;
  String? _errorMessage;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleContinue() async {
    final password = _passwordController.text;

    final strength = AuthService.validatePasswordStrength(password);
    if (strength.isBlocking) {
      setState(() {
        _errorMessage = strength.label;
      });
      return;
    }

    if (!_isConfirmation) {
      setState(() {
        _isConfirmation = true;
        _errorMessage = null;
      });
    } else {
      final confirmPassword = _confirmPasswordController.text;

      if (confirmPassword != password) {
        setState(() {
          _errorMessage = 'Passwords do not match';
        });
        return;
      }

      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final success = await _authService.createPassword(password);

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
          _errorMessage = 'Failed to save password. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.backgroundColor,
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: context.textPrimary),
          onPressed: _isLoading
              ? null
              : () {
                  if (_isConfirmation) {
                    setState(() {
                      _isConfirmation = false;
                      _confirmPasswordController.clear();
                      _errorMessage = null;
                    });
                  } else {
                    Navigator.pop(context);
                  }
                },
        ),
        title: Text(
          _isConfirmation ? 'Confirm Password' : 'Create Password',
          style: TextStyle(
            fontFamily: 'ProductSans',
            color: context.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Stack(
        children: [
          _isLoading
              ? Center(
                  child: CircularProgressIndicator(
                    color: context.accentColor,
                  ),
                )
              : SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      children: [
                        const Spacer(),
                        _buildIcon(),
                        const SizedBox(height: 32),
                        _buildInstruction(),
                        const SizedBox(height: 48),
                        _buildInputField(),
                        const SizedBox(height: 24),
                        if (_errorMessage != null) _buildError(),
                        const Spacer(),
                        _buildContinueButton(),
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
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: context.accentColor.withValues(alpha: 0.15),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: const Padding(
            padding: EdgeInsets.all(24),
            child: AdaptiveLogo(size: 72),
          ),
        ),
      ),
    );
  }

  Widget _buildInstruction() {
    return Text(
      _isConfirmation
          ? 'Enter your password again to confirm'
          : 'Create a secure password',
      style: TextStyle(
        fontSize: 18,
        color: context.textSecondary,
        fontFamily: 'ProductSans',
      ),
      textAlign: TextAlign.center,
    );
  }

  Widget _buildInputField() {
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
          child: TextField(
            controller: _isConfirmation
                ? _confirmPasswordController
                : _passwordController,
            obscureText:
                _isConfirmation ? _obscureConfirmPassword : _obscurePassword,
            style: TextStyle(
              fontFamily: 'ProductSans',
              fontSize: 16,
              color: context.textPrimary,
            ),
            decoration: InputDecoration(
              labelText: _isConfirmation ? 'Confirm Password' : 'Password',
              labelStyle: TextStyle(
                fontFamily: 'ProductSans',
                color: context.textSecondary,
              ),
              hintText: _isConfirmation
                  ? 'Re-enter your password'
                  : 'Enter your password',
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
                  (_isConfirmation ? _obscureConfirmPassword : _obscurePassword)
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: context.textTertiary,
                ),
                onPressed: () {
                  setState(() {
                    if (_isConfirmation) {
                      _obscureConfirmPassword = !_obscureConfirmPassword;
                    } else {
                      _obscurePassword = !_obscurePassword;
                    }
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
            onChanged: (_) {
              if (_errorMessage != null) {
                setState(() {
                  _errorMessage = null;
                });
              }
            },
          ),
        ),
      ),
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
          ),
        ),
      ),
    );
  }

  Widget _buildContinueButton() {
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
        onPressed: _handleContinue,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Text(
          _isConfirmation ? 'Confirm' : 'Continue',
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
