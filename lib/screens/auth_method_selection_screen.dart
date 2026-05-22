import 'package:flutter/material.dart';
import '../themes/app_colors.dart';
import '../widgets/auth_method_card.dart';
import 'pin_setup_screen.dart';
import 'password_setup_screen.dart';
import 'biometric_setup_screen.dart';
import '../services/auth_service.dart';

/// First-time authentication method selection screen
class AuthMethodSelectionScreen extends StatefulWidget {
  const AuthMethodSelectionScreen({super.key});

  @override
  State<AuthMethodSelectionScreen> createState() =>
      _AuthMethodSelectionScreenState();
}

class _AuthMethodSelectionScreenState extends State<AuthMethodSelectionScreen> {
  final AuthService _authService = AuthService();
  bool _isBiometricAvailable = false;

  @override
  void initState() {
    super.initState();
    _checkBiometricAvailability();
  }

  Future<void> _checkBiometricAvailability() async {
    final isAvailable = await _authService.isBiometricAvailable();
    setState(() {
      _isBiometricAvailable = isAvailable;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 32),

              // Welcome Title
              Text(
                'Welcome to Latch',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  color: AppColors.lightTextPrimary,
                  fontFamily: 'ProductSans',
                ),
              ),

              const SizedBox(height: 12),

              // Subtitle
              Text(
                'Choose how you want to secure your media vault',
                style: TextStyle(
                  fontSize: 16,
                  color: AppColors.lightTextSecondary,
                  fontFamily: 'ProductSans',
                ),
              ),

              const SizedBox(height: 48),

              // Authentication Method Options
              Expanded(
                child: ListView(
                  children: [
                    // PIN Option
                    AuthMethodCard(
                      icon: Icons.pin_outlined,
                      title: 'PIN',
                      description: '6-digit numeric code',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const PinSetupScreen(),
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 16),

                    // Password Option
                    AuthMethodCard(
                      icon: Icons.lock_outlined,
                      title: 'Password',
                      description: 'Alphanumeric password',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const PasswordSetupScreen(),
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 16),

                    // Biometric Option
                    AuthMethodCard(
                      icon: Icons.fingerprint,
                      title: 'Biometrics',
                      description: _isBiometricAvailable
                          ? 'Use your fingerprint'
                          : 'Not available on this device',
                      onTap: _isBiometricAvailable
                          ? () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      const BiometricSetupScreen(),
                                ),
                              );
                            }
                          : () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Biometric authentication is not available on this device',
                                    style: TextStyle(fontFamily: 'ProductSans'),
                                  ),
                                  backgroundColor: AppColors.error,
                                ),
                              );
                            },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
