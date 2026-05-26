import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../themes/app_colors.dart';
import '../services/auth_service.dart';
import '../utils/toast_utils.dart';
import 'gallery_vault_screen.dart';

/// Security option type for the change security screen
enum SecurityOption {
  changePassword,
  changePIN,
  switchToPassword,
  switchToPIN,
  enableBiometric,
}

/// Screen for changing security credentials
class ChangeSecurityScreen extends StatefulWidget {
  const ChangeSecurityScreen({super.key});

  @override
  State<ChangeSecurityScreen> createState() => _ChangeSecurityScreenState();
}

class _ChangeSecurityScreenState extends State<ChangeSecurityScreen> {
  final AuthService _authService = AuthService();
  String? _currentAuthMethod;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAuthMethod();
  }

  Future<void> _loadAuthMethod() async {
    final method = await _authService.getAuthMethod();
    if (mounted) {
      setState(() {
        _currentAuthMethod = method;
        _isLoading = false;
      });
    }
  }

  void _navigateToChangePassword() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChangePasswordScreen(
          currentAuthMethod: _currentAuthMethod!,
        ),
      ),
    );
  }

  void _navigateToChangePIN() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChangePINScreen(
          currentAuthMethod: _currentAuthMethod!,
        ),
      ),
    );
  }

  void _navigateToSetupBiometric() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const BiometricSetupScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.backgroundColor,
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: context.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Change Security',
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
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 16),
                        _buildCurrentMethodBadge(),
                        const SizedBox(height: 32),
                        if (_currentAuthMethod == 'password') ...[
                          _buildOptionCard(
                            icon: Icons.lock_outline,
                            title: 'Change Password',
                            subtitle: 'Update your current password',
                            onTap: _navigateToChangePassword,
                          ),
                          const SizedBox(height: 16),
                          _buildOptionCard(
                            icon: Icons.pin_outlined,
                            title: 'Switch to PIN',
                            subtitle: 'Change from password to 6-digit PIN',
                            onTap: _navigateToChangePIN,
                          ),
                        ] else if (_currentAuthMethod == 'pin') ...[
                          _buildOptionCard(
                            icon: Icons.pin_outlined,
                            title: 'Change PIN',
                            subtitle: 'Update your current PIN',
                            onTap: _navigateToChangePIN,
                          ),
                          const SizedBox(height: 16),
                          _buildOptionCard(
                            icon: Icons.lock_outline,
                            title: 'Switch to Password',
                            subtitle:
                                'Change from PIN to alphanumeric password',
                            onTap: _navigateToChangePassword,
                          ),
                        ] else if (_currentAuthMethod == 'biometric') ...[
                          _buildOptionCard(
                            icon: Icons.fingerprint,
                            title: 'Change Biometric',
                            subtitle: 'Update your biometric settings',
                            onTap: _navigateToSetupBiometric,
                          ),
                          const SizedBox(height: 16),
                          _buildOptionCard(
                            icon: Icons.lock_outline,
                            title: 'Switch to Password',
                            subtitle: 'Use alphanumeric password instead',
                            onTap: _navigateToChangePassword,
                          ),
                          const SizedBox(height: 16),
                          _buildOptionCard(
                            icon: Icons.pin_outlined,
                            title: 'Switch to PIN',
                            subtitle: 'Use 6-digit PIN instead',
                            onTap: _navigateToChangePIN,
                          ),
                        ],
                        const SizedBox(height: 16),
                        FutureBuilder<bool>(
                          future: _authService.isBiometricAvailable(),
                          builder: (context, snapshot) {
                            if (snapshot.data == true) {
                              return _buildOptionCard(
                                icon: Icons.fingerprint,
                                title: 'Enable Biometric',
                                subtitle: 'Use fingerprint or face to unlock',
                                onTap: _navigateToSetupBiometric,
                              );
                            }
                            return const SizedBox.shrink();
                          },
                        ),
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

  Widget _buildCurrentMethodBadge() {
    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: context.isDarkMode
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: context.isDarkMode
                    ? Colors.white.withValues(alpha: 0.15)
                    : Colors.white.withValues(alpha: 0.2),
                width: 1,
              ),
            ),
            child: Text(
              'Current: ${_currentAuthMethod!.toUpperCase()}',
              style: TextStyle(
                fontSize: 14,
                color: context.textSecondary,
                fontFamily: 'ProductSans',
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOptionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: context.isDarkMode
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: context.isDarkMode
                    ? Colors.white.withValues(alpha: 0.1)
                    : Colors.white.withValues(alpha: 0.2),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: context.accentColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: context.accentColor, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'ProductSans',
                          color: context.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 13,
                          fontFamily: 'ProductSans',
                          color: context.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: context.textTertiary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Screen for changing password
class ChangePasswordScreen extends StatefulWidget {
  final String currentAuthMethod;

  const ChangePasswordScreen({super.key, required this.currentAuthMethod});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final AuthService _authService = AuthService();
  final TextEditingController _currentCredentialController =
      TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  final FocusNode _currentPinFocusNode = FocusNode();
  int _step = 0;
  String? _errorMessage;
  bool _isLoading = false;
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _currentCredentialController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    _currentPinFocusNode.dispose();
    super.dispose();
  }

  Future<void> _handleContinue() async {
    if (_step == 0) {
      // When current auth is biometric, verify with the system biometric prompt.
      if (widget.currentAuthMethod == 'biometric') {
        final isAuthenticated = await _authService.authenticateWithBiometrics(
          reason: 'Authenticate to change your security method',
        );
        if (!isAuthenticated) {
          setState(() {
            _errorMessage = 'Biometric verification failed or was cancelled';
          });
          return;
        }
        setState(() {
          _step = 1;
          _errorMessage = null;
        });
        return;
      }

      if (_currentCredentialController.text.isEmpty) {
        setState(() {
          _errorMessage = widget.currentAuthMethod == 'password'
              ? 'Please enter your current password'
              : 'Please enter your current PIN';
        });
        return;
      }
      final isCurrentCredentialValid = widget.currentAuthMethod == 'password'
          ? await _authService.verifyPassword(_currentCredentialController.text)
          : await _authService.verifyPIN(_currentCredentialController.text);
      if (!isCurrentCredentialValid) {
        setState(() {
          _errorMessage = widget.currentAuthMethod == 'password'
              ? 'Current password is incorrect'
              : 'Current PIN is incorrect';
        });
        return;
      }
      setState(() {
        _step = 1;
        _errorMessage = null;
      });
    } else if (_step == 1) {
      if (_newPasswordController.text.isEmpty) {
        setState(() {
          _errorMessage = 'Please enter a new password';
        });
        return;
      }
      setState(() {
        _step = 2;
        _errorMessage = null;
      });
    } else {
      if (_confirmPasswordController.text.isEmpty) {
        setState(() {
          _errorMessage = 'Please confirm your new password';
        });
        return;
      }
      if (_newPasswordController.text != _confirmPasswordController.text) {
        setState(() {
          _errorMessage = 'Passwords do not match';
        });
        return;
      }

      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      bool success;
      if (widget.currentAuthMethod == 'password') {
        success = await _authService.changePassword(
          _currentCredentialController.text,
          _newPasswordController.text,
        );
      } else if (widget.currentAuthMethod == 'biometric') {
        success =
            await _authService.createPassword(_newPasswordController.text);
        // Update auth method to password
        if (success) {
          await _authService.setAuthMethod('password');
        }
      } else {
        success = await _authService.switchFromPINToPassword(
          _currentCredentialController.text,
          _newPasswordController.text,
        );
      }

      if (success && mounted) {
        ToastUtils.showSuccess('Password changed successfully');
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (context) => const GalleryVaultScreen(),
          ),
          (route) => false,
        );
      } else if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = widget.currentAuthMethod == 'password'
              ? 'Current password is incorrect'
              : 'Current PIN is incorrect';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final titles = widget.currentAuthMethod == 'biometric'
        ? ['Verify Biometric', 'New Password', 'Confirm Password']
        : widget.currentAuthMethod == 'pin'
            ? ['Verify Current PIN', 'New Password', 'Confirm Password']
        : ['Verify Current Password', 'New Password', 'Confirm Password'];
    final subtitles = [
      widget.currentAuthMethod == 'biometric'
          ? 'Use your fingerprint or face to verify'
          : widget.currentAuthMethod == 'pin'
              ? 'Enter your current 6-digit PIN to verify'
          : 'Enter your current password to verify',
      'Create a new secure password',
      'Enter your new password again to confirm',
    ];
    final controllers = [
      _currentCredentialController,
      _newPasswordController,
      _confirmPasswordController,
    ];
    final obscureValues = [_obscureCurrent, _obscureNew, _obscureConfirm];
    final obscureIcons = [
      _obscureCurrent
          ? Icons.visibility_outlined
          : Icons.visibility_off_outlined,
      _obscureNew ? Icons.visibility_outlined : Icons.visibility_off_outlined,
      _obscureConfirm
          ? Icons.visibility_outlined
          : Icons.visibility_off_outlined,
    ];
    final toggleCallbacks = [
      () => setState(() => _obscureCurrent = !_obscureCurrent),
      () => setState(() => _obscureNew = !_obscureNew),
      () => setState(() => _obscureConfirm = !_obscureConfirm),
    ];
    final labels = [
      'Device PIN',
      'New Password',
      'Confirm Password',
    ];
    final hints = [
      'Enter your device PIN',
      'Enter new password',
      'Re-enter password',
      'Enter new password',
      'Re-enter new password',
    ];

    return Scaffold(
      backgroundColor: context.backgroundColor,
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: context.textPrimary),
          onPressed: _isLoading
              ? null
              : () {
                  if (_step > 0) {
                    setState(() {
                      _step--;
                      _errorMessage = null;
                    });
                  } else {
                    Navigator.pop(context);
                  }
                },
        ),
        title: Text(
          titles[_step],
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
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Spacer(),
                        _buildIcon(),
                        const SizedBox(height: 32),
                        Text(
                          subtitles[_step],
                          style: TextStyle(
                            fontSize: 18,
                            color: context.textSecondary,
                            fontFamily: 'ProductSans',
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 48),
                        if (widget.currentAuthMethod == 'biometric' &&
                            _step == 0)
                          _buildBiometricPrompt()
                        else if (widget.currentAuthMethod == 'pin' &&
                            _step == 0)
                          _buildCurrentPINInputField()
                        else
                          _buildInputField(
                            controller: controllers[_step],
                            obscureText: obscureValues[_step],
                            label: labels[_step],
                            hint: hints[_step],
                            icon: obscureIcons[_step],
                            onToggle: toggleCallbacks[_step],
                          ),
                        const SizedBox(height: 16),
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
    return Center(
      child: Container(
        width: 100,
        height: 100,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: context.isDarkMode
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.white.withValues(alpha: 0.15),
          border: Border.all(
            color: context.isDarkMode
                ? Colors.white.withValues(alpha: 0.15)
                : Colors.white.withValues(alpha: 0.2),
            width: 1.5,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Padding(
              padding: const EdgeInsets.all(20),
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

  Widget _buildInputField({
    required TextEditingController controller,
    required bool obscureText,
    required String label,
    required String hint,
    required IconData icon,
    required VoidCallback onToggle,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.all(20),
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
            controller: controller,
            obscureText: obscureText,
            style: TextStyle(
              fontFamily: 'ProductSans',
              fontSize: 16,
              color: context.textPrimary,
            ),
            decoration: InputDecoration(
              labelText: label,
              hintText: hint,
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
                icon: Icon(icon, color: context.textTertiary),
                onPressed: onToggle,
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

  Widget _buildBiometricPrompt() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.all(20),
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
          child: Row(
            children: [
              Icon(Icons.fingerprint, color: context.accentColor, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Tap Continue to verify with biometrics',
                  style: TextStyle(
                    fontFamily: 'ProductSans',
                    fontSize: 15,
                    color: context.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentPINInputField() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.all(20),
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
          child: GestureDetector(
            onTap: () => FocusScope.of(context).requestFocus(_currentPinFocusNode),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Current PIN',
                  style: TextStyle(
                    fontFamily: 'ProductSans',
                    color: context.textSecondary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Enter your 6-digit PIN',
                  style: TextStyle(
                    fontFamily: 'ProductSans',
                    color: context.textTertiary,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(6, (index) {
                    final isFilled = index < _currentCredentialController.text.length;
                    return Container(
                      width: 44,
                      height: 52,
                      decoration: BoxDecoration(
                        color: context.isDarkMode
                            ? Colors.white.withValues(alpha: 0.05)
                            : Colors.black.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isFilled
                              ? context.accentColor.withValues(alpha: 0.8)
                              : context.isDarkMode
                                  ? Colors.white.withValues(alpha: 0.15)
                                  : Colors.black.withValues(alpha: 0.08),
                        ),
                      ),
                      child: Center(
                        child: isFilled
                            ? Text(
                                '•',
                                style: TextStyle(
                                  color: context.textPrimary,
                                  fontSize: 20,
                                  fontFamily: 'ProductSans',
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                    );
                  }),
                ),
                SizedBox(
                  width: 0,
                  height: 0,
                  child: TextField(
                    controller: _currentCredentialController,
                    focusNode: _currentPinFocusNode,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    maxLength: 6,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      counterText: '',
                    ),
                    onChanged: (_) {
                      if (_errorMessage != null) {
                        setState(() {
                          _errorMessage = null;
                        });
                      } else {
                        setState(() {});
                      }
                    },
                  ),
                ),
              ],
            ),
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
          _step == 2 ? 'Change Password' : 'Continue',
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

/// Screen for changing PIN
class ChangePINScreen extends StatefulWidget {
  final String currentAuthMethod;

  const ChangePINScreen({super.key, required this.currentAuthMethod});

  @override
  State<ChangePINScreen> createState() => _ChangePINScreenState();
}

class _ChangePINScreenState extends State<ChangePINScreen> {
  final AuthService _authService = AuthService();
  final TextEditingController _currentCredentialController =
      TextEditingController();
  final TextEditingController _newPINController = TextEditingController();
  final TextEditingController _confirmPINController = TextEditingController();
  final FocusNode _currentPinFocusNode = FocusNode();
  final FocusNode _newPinFocusNode = FocusNode();
  final FocusNode _confirmPinFocusNode = FocusNode();
  bool _showPinDigits = true;
  int _step = 0;
  String? _errorMessage;
  bool _isLoading = false;

  @override
  void dispose() {
    _currentCredentialController.dispose();
    _newPINController.dispose();
    _confirmPINController.dispose();
    _currentPinFocusNode.dispose();
    _newPinFocusNode.dispose();
    _confirmPinFocusNode.dispose();
    super.dispose();
  }

  Future<void> _handleContinue() async {
    if (_step == 0) {
      // When current auth is biometric, verify with the system biometric prompt.
      if (widget.currentAuthMethod == 'biometric') {
        final isAuthenticated = await _authService.authenticateWithBiometrics(
          reason: 'Authenticate to change your security method',
        );
        if (!isAuthenticated) {
          setState(() {
            _errorMessage = 'Biometric verification failed or was cancelled';
          });
          return;
        }
        setState(() {
          _step = 1;
          _errorMessage = null;
        });
        return;
      }

      if (_currentCredentialController.text.isEmpty) {
        setState(() {
          _errorMessage = widget.currentAuthMethod == 'pin'
              ? 'Please enter your current PIN'
              : 'Please enter your current password';
        });
        return;
      }
      final isCurrentCredentialValid = widget.currentAuthMethod == 'pin'
          ? await _authService.verifyPIN(_currentCredentialController.text)
          : await _authService.verifyPassword(_currentCredentialController.text);
      if (!isCurrentCredentialValid) {
        setState(() {
          _errorMessage = widget.currentAuthMethod == 'pin'
              ? 'Current PIN is incorrect'
              : 'Current password is incorrect';
        });
        return;
      }
      setState(() {
        _step = 1;
        _errorMessage = null;
      });
    } else if (_step == 1) {
      if (_newPINController.text.isEmpty ||
          _newPINController.text.length != 6) {
        setState(() {
          _errorMessage = 'PIN must be 6 digits';
        });
        return;
      }
      if (!RegExp(r'^[0-9]{6}$').hasMatch(_newPINController.text)) {
        setState(() {
          _errorMessage = 'PIN must contain only digits';
        });
        return;
      }
      setState(() {
        _step = 2;
        _errorMessage = null;
      });
    } else {
      if (_confirmPINController.text.isEmpty ||
          _confirmPINController.text.length != 6) {
        setState(() {
          _errorMessage = 'PIN must be 6 digits';
        });
        return;
      }
      if (_newPINController.text != _confirmPINController.text) {
        setState(() {
          _errorMessage = 'PINs do not match';
        });
        return;
      }

      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      bool success;
      if (widget.currentAuthMethod == 'pin') {
        success = await _authService.changePIN(
          _currentCredentialController.text,
          _newPINController.text,
        );
      } else if (widget.currentAuthMethod == 'biometric') {
        success = await _authService.createPIN(_newPINController.text);
        // Update auth method to PIN
        if (success) {
          await _authService.setAuthMethod('pin');
        }
      } else {
        success = await _authService.switchFromPasswordToPIN(
          _currentCredentialController.text,
          _newPINController.text,
        );
      }

      if (success && mounted) {
        ToastUtils.showSuccess('PIN changed successfully');
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (context) => const GalleryVaultScreen(),
          ),
          (route) => false,
        );
      } else if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = widget.currentAuthMethod == 'pin'
              ? 'Current PIN is incorrect'
              : 'Current password is incorrect';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final titles = widget.currentAuthMethod == 'biometric'
        ? ['Verify Biometric', 'New PIN', 'Confirm PIN']
        : widget.currentAuthMethod == 'password'
            ? ['Verify Current Password', 'New PIN', 'Confirm PIN']
            : ['Verify Current PIN', 'New PIN', 'Confirm PIN'];
    final subtitles = [
      widget.currentAuthMethod == 'biometric'
          ? 'Use your fingerprint or face to verify'
          : widget.currentAuthMethod == 'password'
              ? 'Type your current password to verify'
              : 'Enter your current PIN to verify',
      'Enter a new 6-digit PIN',
      'Enter your new PIN again to confirm',
    ];
    final controllers = [
      _currentCredentialController,
      _newPINController,
      _confirmPINController,
    ];
    final labels = [
      widget.currentAuthMethod == 'password' ? 'Current Password' : 'Current PIN',
      'New PIN',
      'Confirm PIN',
    ];
    final hints = [
      widget.currentAuthMethod == 'password'
          ? 'Type your current password'
          : 'Enter current 6-digit PIN',
      'Enter 6-digit PIN',
      'Re-enter PIN',
    ];

    return Scaffold(
      backgroundColor: context.backgroundColor,
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: context.textPrimary),
          onPressed: _isLoading
              ? null
              : () {
                  if (_step > 0) {
                    setState(() {
                      _step--;
                      _errorMessage = null;
                    });
                  } else {
                    Navigator.pop(context);
                  }
                },
        ),
        title: Text(
          titles[_step],
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
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Spacer(),
                        _buildIcon(),
                        const SizedBox(height: 32),
                        Text(
                          subtitles[_step],
                          style: TextStyle(
                            fontSize: 18,
                            color: context.textSecondary,
                            fontFamily: 'ProductSans',
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 48),
                        if (widget.currentAuthMethod == 'biometric' &&
                            _step == 0)
                          _buildBiometricPrompt()
                        else if (_step >= 1 ||
                            (widget.currentAuthMethod == 'pin' && _step == 0))
                          _buildPINInputField(
                            controller: controllers[_step],
                            label: labels[_step],
                            hint: hints[_step],
                            focusNode: _step == 0
                                ? _currentPinFocusNode
                                : _step == 1
                                    ? _newPinFocusNode
                                    : _confirmPinFocusNode,
                          )
                        else
                          _buildInputField(
                            controller: controllers[_step],
                            label: labels[_step],
                            hint: hints[_step],
                          ),
                        const SizedBox(height: 16),
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
    return Center(
      child: Container(
        width: 100,
        height: 100,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: context.isDarkMode
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.white.withValues(alpha: 0.15),
          border: Border.all(
            color: context.isDarkMode
                ? Colors.white.withValues(alpha: 0.15)
                : Colors.white.withValues(alpha: 0.2),
            width: 1.5,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Padding(
              padding: const EdgeInsets.all(20),
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

  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required String hint,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.all(20),
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
            controller: controller,
            obscureText: true,
            keyboardType: TextInputType.text,
            style: TextStyle(
              fontFamily: 'ProductSans',
              fontSize: 16,
              color: context.textPrimary,
            ),
            decoration: InputDecoration(
              labelText: label,
              hintText: hint,
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

  Widget _buildPINInputField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required FocusNode focusNode,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.all(20),
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
          child: GestureDetector(
            onTap: () => FocusScope.of(context).requestFocus(focusNode),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'ProductSans',
                    color: context.textSecondary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  hint,
                  style: TextStyle(
                    fontFamily: 'ProductSans',
                    color: context.textTertiary,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(6, (index) {
                    final isFilled = index < controller.text.length;
                    return Container(
                      width: 44,
                      height: 52,
                      decoration: BoxDecoration(
                        color: context.isDarkMode
                            ? Colors.white.withValues(alpha: 0.05)
                            : Colors.black.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isFilled
                              ? context.accentColor.withValues(alpha: 0.8)
                              : context.isDarkMode
                                  ? Colors.white.withValues(alpha: 0.15)
                                  : Colors.black.withValues(alpha: 0.08),
                        ),
                      ),
                      child: Center(
                        child: isFilled
                            ? Text(
                                _showPinDigits ? controller.text[index] : '•',
                                style: TextStyle(
                                  color: context.textPrimary,
                                  fontSize: 20,
                                  fontFamily: 'ProductSans',
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _showPinDigits = !_showPinDigits;
                      });
                    },
                    icon: Icon(
                      _showPinDigits
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 18,
                      color: context.textSecondary,
                    ),
                    label: Text(
                      _showPinDigits ? 'Hide PIN' : 'Show PIN',
                      style: TextStyle(
                        fontFamily: 'ProductSans',
                        color: context.textSecondary,
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: 0,
                  height: 0,
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    keyboardType: TextInputType.number,
                    obscureText: false,
                    maxLength: 6,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
                    decoration: const InputDecoration(
                      counterText: '',
                      border: InputBorder.none,
                    ),
                    onChanged: (_) {
                      final value = controller.text;
                      if (_errorMessage != null) {
                        setState(() {
                          _errorMessage = null;
                        });
                      } else {
                        setState(() {});
                      }

                      // Auto-advance from "New PIN" to "Confirm PIN"
                      // once 6 valid digits are entered.
                      if (_step == 1 &&
                          identical(controller, _newPINController) &&
                          value.length == 6 &&
                          RegExp(r'^[0-9]{6}$').hasMatch(value)) {
                        setState(() {
                          _step = 2;
                          _errorMessage = null;
                        });
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) {
                            FocusScope.of(context)
                                .requestFocus(_confirmPinFocusNode);
                          }
                        });
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBiometricPrompt() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.all(20),
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
          child: Row(
            children: [
              Icon(Icons.fingerprint, color: context.accentColor, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Tap Continue to verify with biometrics',
                  style: TextStyle(
                    fontFamily: 'ProductSans',
                    fontSize: 15,
                    color: context.textSecondary,
                  ),
                ),
              ),
            ],
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
          _step == 2 ? 'Change PIN' : 'Continue',
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

/// Screen for setting up biometric authentication
class BiometricSetupScreen extends StatefulWidget {
  const BiometricSetupScreen({super.key});

  @override
  State<BiometricSetupScreen> createState() => _BiometricSetupScreenState();
}

class _BiometricSetupScreenState extends State<BiometricSetupScreen> {
  final AuthService _authService = AuthService();
  bool _isLoading = false;
  String? _errorMessage;
  bool _isAvailable = false;

  @override
  void initState() {
    super.initState();
    _checkBiometricAvailability();
  }

  Future<void> _checkBiometricAvailability() async {
    final available = await _authService.isBiometricAvailable();
    if (mounted) {
      setState(() {
        _isAvailable = available;
      });
    }
  }

  Future<void> _setupBiometric() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final success = await _authService.setupBiometricAuthentication();

    if (mounted) {
      if (success) {
        ToastUtils.showSuccess('Biometric enabled successfully');
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (context) => const GalleryVaultScreen(),
          ),
          (route) => false,
        );
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Biometric setup failed or was cancelled';
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
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Enable Biometric',
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
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Spacer(),
                        _buildIcon(),
                        const SizedBox(height: 32),
                        Text(
                          'Quick & Secure Access',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: context.textPrimary,
                            fontFamily: 'ProductSans',
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Use your fingerprint or face to unlock the app quickly',
                          style: TextStyle(
                            fontSize: 16,
                            color: context.textSecondary,
                            fontFamily: 'ProductSans',
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 48),
                        if (_errorMessage != null) _buildError(),
                        const Spacer(),
                        if (_isAvailable) _buildSetupButton(),
                        if (!_isAvailable) _buildUnavailableMessage(),
                        const SizedBox(height: 24),
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
                : context.accentColor.withValues(alpha: 0.3),
            width: 2,
          ),
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
              ),
            ),
          ),
        ),
      ),
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
        onPressed: _setupBiometric,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: const Text(
          'Enable Biometric',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            fontFamily: 'ProductSans',
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildUnavailableMessage() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.isDarkMode
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: context.isDarkMode
                  ? Colors.white.withValues(alpha: 0.1)
                  : Colors.white.withValues(alpha: 0.2),
              width: 1,
            ),
          ),
          child: Text(
            'Biometric authentication is not available on this device',
            style: TextStyle(
              color: context.textSecondary,
              fontSize: 14,
              fontFamily: 'ProductSans',
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
