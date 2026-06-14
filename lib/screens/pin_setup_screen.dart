import 'dart:ui';
import 'package:flutter/material.dart';
import '../themes/app_colors.dart';
import '../widgets/adaptive_logo.dart';
import '../widgets/pin_input_widget.dart';
import '../services/auth_service.dart';
import 'gallery_vault_screen.dart';

class PinSetupScreen extends StatefulWidget {
  const PinSetupScreen({super.key});

  @override
  State<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends State<PinSetupScreen> {
  final AuthService _authService = AuthService();
  String? _firstPin;
  bool _isConfirmation = false;
  String? _errorMessage;
  bool _isLoading = false;

  void _handlePinComplete(String pin) async {
    if (!_isConfirmation) {
      setState(() {
        _firstPin = pin;
        _isConfirmation = true;
        _errorMessage = null;
      });
    } else {
      if (pin == _firstPin) {
        setState(() {
          _isLoading = true;
          _errorMessage = null;
        });

        final success = await _authService.createPIN(pin);

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
            _errorMessage = 'Failed to save PIN. Please try again.';
            _isConfirmation = false;
            _firstPin = null;
          });
        }
      } else {
        setState(() {
          _errorMessage = 'PINs do not match. Please try again.';
          _isConfirmation = false;
          _firstPin = null;
        });
      }
    }
  }

  void _handlePinChanged() {
    if (_errorMessage != null) {
      setState(() {
        _errorMessage = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
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
                      _firstPin = null;
                      _errorMessage = null;
                    });
                  } else {
                    Navigator.pop(context);
                  }
                },
        ),
        title: Text(
          _isConfirmation ? 'Confirm PIN' : 'Create PIN',
          style: TextStyle(
            fontFamily: 'ProductSans',
            color: context.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: context.isDarkMode
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.white.withValues(alpha: 0.15),
        elevation: 0,
      ),
      body: Stack(
        children: [
          _buildBackground(),
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
                        _buildPinWidget(),
                        if (_errorMessage != null) ...[
                          const SizedBox(height: 24),
                          _buildError(),
                        ],
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
          ? 'Enter your PIN again to confirm'
          : 'Enter a 6-digit PIN',
      style: TextStyle(
        fontSize: 18,
        color: context.textSecondary,
        fontFamily: 'ProductSans',
      ),
      textAlign: TextAlign.center,
    );
  }

  Widget _buildPinWidget() {
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
          child: PinInputWidget(
            key: ValueKey(_isConfirmation),
            onPinComplete: _handlePinComplete,
            onPinChanged: _handlePinChanged,
            errorMessage: _errorMessage,
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
}
