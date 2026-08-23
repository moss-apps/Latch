import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/auth_service.dart';
import '../services/encryption_service.dart';
import '../themes/app_colors.dart';
import '../utils/toast_utils.dart';
import 'gallery_vault_screen.dart';

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
  bool _autofillEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadAuthMethod();
  }

  Future<void> _loadAuthMethod() async {
    final method = await _authService.getAuthMethod();
    final autofillEnabled = await _authService.isUnlockAutofillEnabled();
    if (mounted) {
      setState(() {
        _currentAuthMethod = method;
        _autofillEnabled = autofillEnabled;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Security')),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(color: context.accentColor),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                _sectionTitle('Current'),
                _currentMethodTile(),
                const SizedBox(height: 24),
                _sectionTitle('Authentication'),
                ..._authOptionTiles(),
                FutureBuilder<bool>(
                  future: _authService.isBiometricAvailable(),
                  builder: (context, snapshot) {
                    if (snapshot.data == true &&
                        _currentAuthMethod != 'biometric') {
                      return _tile(
                        icon: Icons.fingerprint,
                        title: 'Biometric Unlock',
                        subtitle: 'Use fingerprint or face to unlock',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const BiometricSetupScreen(),
                          ),
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
                const SizedBox(height: 24),
                _sectionTitle('Convenience'),
                SwitchListTile(
                  value: _autofillEnabled,
                  onChanged: _handleAutofillToggle,
                  contentPadding: EdgeInsets.zero,
                  secondary: Icon(
                    Icons.password_outlined,
                    color: context.accentColor,
                  ),
                  title: const Text('Autofill Credential'),
                  subtitle: Text(
                    'Let password managers fill your PIN or password',
                    style: TextStyle(fontSize: 12, color: context.textTertiary),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
          color: context.accentColor,
        ),
      ),
    );
  }

  Widget _currentMethodTile() {
    final (icon, label) = switch (_currentAuthMethod) {
      'password' => (Icons.lock_outline, 'Password'),
      'pin' => (Icons.pin_outlined, 'PIN'),
      'biometric' => (Icons.fingerprint, 'Biometric'),
      _ => (Icons.security, 'None'),
    };

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: context.accentColor),
      title: Text(label),
      subtitle: Text(
        'Current unlock method',
        style: TextStyle(fontSize: 12, color: context.textTertiary),
      ),
    );
  }

  List<Widget> _authOptionTiles() {
    switch (_currentAuthMethod) {
      case 'password':
        return [
          _tile(
            icon: Icons.lock_outline,
            title: 'Change Password',
            subtitle: 'Use a new password',
            onTap: _push(() => ChangePasswordScreen(
                  currentAuthMethod: _currentAuthMethod!,
                )),
          ),
          _tile(
            icon: Icons.pin_outlined,
            title: 'Switch to PIN',
            subtitle: 'Replace password with a 6-digit PIN',
            onTap: _push(() => ChangePINScreen(
                  currentAuthMethod: _currentAuthMethod!,
                )),
          ),
        ];
      case 'pin':
        return [
          _tile(
            icon: Icons.pin_outlined,
            title: 'Change PIN',
            subtitle: 'Use a new 6-digit PIN',
            onTap: _push(() => ChangePINScreen(
                  currentAuthMethod: _currentAuthMethod!,
                )),
          ),
          _tile(
            icon: Icons.lock_outline,
            title: 'Switch to Password',
            subtitle: 'Replace PIN with a password',
            onTap: _push(() => ChangePasswordScreen(
                  currentAuthMethod: _currentAuthMethod!,
                )),
          ),
        ];
      case 'biometric':
        return [
          _tile(
            icon: Icons.fingerprint,
            title: 'Change Biometric',
            subtitle: 'Re-enroll fingerprint or face',
            onTap: _push(() => const BiometricSetupScreen()),
          ),
          _tile(
            icon: Icons.lock_outline,
            title: 'Switch to Password',
            subtitle: 'Replace biometric unlock with a password',
            onTap: _push(() => ChangePasswordScreen(
                  currentAuthMethod: _currentAuthMethod!,
                )),
          ),
          _tile(
            icon: Icons.pin_outlined,
            title: 'Switch to PIN',
            subtitle: 'Replace biometric unlock with a 6-digit PIN',
            onTap: _push(() => ChangePINScreen(
                  currentAuthMethod: _currentAuthMethod!,
                )),
          ),
        ];
      default:
        return [
          _tile(
            icon: Icons.lock_outline,
            title: 'Set Password',
            subtitle: 'Create an alphanumeric password',
            onTap: _push(() => ChangePasswordScreen(
                  currentAuthMethod: _currentAuthMethod ?? 'none',
                )),
          ),
        ];
    }
  }

  VoidCallback _push(Widget Function() builder) {
    return () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => builder()),
        );
  }

  Widget _tile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: context.accentColor),
      title: Text(title),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 12, color: context.textTertiary),
      ),
      trailing: Icon(Icons.chevron_right, color: context.textTertiary),
      onTap: onTap,
    );
  }

  Future<void> _handleAutofillToggle(bool value) async {
    if (!value) {
      await _authService.setUnlockAutofillEnabled(false);
      if (mounted) setState(() => _autofillEnabled = false);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const _AutofillWarningDialog(),
    );

    if (confirmed == true && mounted) {
      await _authService.setUnlockAutofillEnabled(true);
      setState(() => _autofillEnabled = true);
    }
  }
}

class _AutofillWarningDialog extends StatefulWidget {
  const _AutofillWarningDialog();

  @override
  State<_AutofillWarningDialog> createState() => _AutofillWarningDialogState();
}

class _AutofillWarningDialogState extends State<_AutofillWarningDialog> {
  int _countdown = 10;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_countdown > 0) {
        setState(() => _countdown--);
      } else {
        _timer?.cancel();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final errorColor = Theme.of(context).colorScheme.error;
    return AlertDialog(
      icon: Icon(Icons.warning_amber_rounded, size: 40, color: errorColor),
      title: const Text('Enable Autofill?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'This lets password managers (Google, Bitwarden, Samsung Pass) store and fill your vault PIN or password.',
          ),
          const SizedBox(height: 12),
          Text(
            'Your master credential will be stored outside Latch. If that password manager is ever compromised, your vault is at risk.',
            style: TextStyle(color: errorColor),
          ),
          const SizedBox(height: 12),
          Text(
            'Biometric unlock is the safer no-type alternative — your key never leaves the hardware Keystore.',
            style: TextStyle(
              fontSize: 13,
              color: context.textSecondary,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton.tonal(
          onPressed:
              _countdown > 0 ? null : () => Navigator.of(context).pop(true),
          child: Text(_countdown > 0 ? 'Wait ${_countdown}s' : 'Enable'),
        ),
      ],
    );
  }
}

/// Screen for changing or setting the vault password
class ChangePasswordScreen extends StatefulWidget {
  final String currentAuthMethod;

  const ChangePasswordScreen({super.key, required this.currentAuthMethod});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final AuthService _authService = AuthService();
  final TextEditingController _currentController = TextEditingController();
  final TextEditingController _newController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();
  final FocusNode _currentFocusNode = FocusNode();
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  String? _errorMessage;
  bool _isLoading = false;

  bool get _isChange => widget.currentAuthMethod == 'password';

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    _currentFocusNode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final current = _currentController.text;
    final next = _newController.text;

    if (widget.currentAuthMethod != 'biometric' && current.isEmpty) {
      _fail(widget.currentAuthMethod == 'pin'
          ? 'Enter your current PIN'
          : 'Enter your current password');
      return;
    }
    if (next.length < AuthService.minPasswordLength) {
      _fail('Use at least ${AuthService.minPasswordLength} characters');
      return;
    }
    if (next != _confirmController.text) {
      _fail('Passwords do not match');
      return;
    }

    if (widget.currentAuthMethod == 'biometric') {
      final ok = await _authService.authenticateWithBiometrics(
        reason: 'Authenticate to change your security method',
      );
      if (!ok) {
        _fail('Biometric verification failed or was cancelled');
        return;
      }
    } else {
      final valid = widget.currentAuthMethod == 'password'
          ? await _authService.verifyPassword(current)
          : await _authService.verifyPIN(current);
      if (!valid) {
        _fail(widget.currentAuthMethod == 'password'
            ? 'Current password is incorrect'
            : 'Current PIN is incorrect');
        return;
      }
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    bool success;
    if (widget.currentAuthMethod == 'password') {
      success = await _authService.changePassword(current, next);
    } else if (widget.currentAuthMethod == 'biometric') {
      success = await _authService.createPassword(next);
      if (success) {
        await _authService.setAuthMethod('password');
        await EncryptionService.instance.reWrapKey(next);
        await EncryptionService.instance.removeBiometricKwk();
      }
    } else {
      success = await _authService.switchFromPINToPassword(current, next);
    }

    if (!mounted) return;
    if (success) {
      ToastUtils.showSuccess('Password changed successfully');
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const GalleryVaultScreen()),
        (route) => false,
      );
    } else {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Could not change password. Check your credentials.';
      });
    }
  }

  void _fail(String message) {
    setState(() => _errorMessage = message);
  }

  void _clearError([Object? _]) {
    if (_errorMessage != null) setState(() => _errorMessage = null);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isChange ? 'Change Password' : 'Set Password'),
        automaticallyImplyLeading: !_isLoading,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.currentAuthMethod == 'pin') ...[
                _PinField(
                  label: 'Current PIN',
                  controller: _currentController,
                  focusNode: _currentFocusNode,
                  obscure: true,
                  onChanged: _clearError,
                ),
                const SizedBox(height: 20),
              ] else if (widget.currentAuthMethod == 'password')
                _textField(
                  controller: _currentController,
                  label: 'Current password',
                  obscure: _obscureCurrent,
                  onToggle: () => setState(
                    () => _obscureCurrent = !_obscureCurrent,
                  ),
                  onChanged: _clearError,
                )
              else
                _biometricNotice(),
              const SizedBox(height: 8),
              _textField(
                controller: _newController,
                label: 'New password',
                helper:
                    'At least ${AuthService.minPasswordLength} characters',
                obscure: _obscureNew,
                onToggle: () => setState(() => _obscureNew = !_obscureNew),
                onChanged: _clearError,
              ),
              const SizedBox(height: 8),
              _textField(
                controller: _confirmController,
                label: 'Confirm new password',
                obscure: _obscureConfirm,
                onToggle: () =>
                    setState(() => _obscureConfirm = !_obscureConfirm),
                onChanged: _clearError,
                onSubmitted: (_) => _isLoading ? null : _submit(),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 8),
                Text(
                  _errorMessage!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 13,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isLoading ? null : _submit,
                child: _isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(_isChange ? 'Change Password' : 'Set Password'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String label,
    required bool obscure,
    required VoidCallback onToggle,
    ValueChanged<String>? onChanged,
    ValueChanged<String>? onSubmitted,
    String? helper,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        suffixIcon: IconButton(
          icon: Icon(
            obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
            color: context.textTertiary,
          ),
          onPressed: onToggle,
        ),
      ),
    );
  }

  Widget _biometricNotice() {
    return Row(
      children: [
        Icon(Icons.fingerprint, color: context.accentColor, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'You will verify with your fingerprint before saving.',
            style: TextStyle(fontSize: 13, color: context.textSecondary),
          ),
        ),
      ],
    );
  }
}

/// Screen for changing or setting the vault PIN
class ChangePINScreen extends StatefulWidget {
  final String currentAuthMethod;

  const ChangePINScreen({super.key, required this.currentAuthMethod});

  @override
  State<ChangePINScreen> createState() => _ChangePINScreenState();
}

class _ChangePINScreenState extends State<ChangePINScreen> {
  final AuthService _authService = AuthService();
  final TextEditingController _currentController = TextEditingController();
  final TextEditingController _newController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();
  final FocusNode _currentFocusNode = FocusNode();
  final FocusNode _newFocusNode = FocusNode();
  final FocusNode _confirmFocusNode = FocusNode();
  bool _obscureCurrentPassword = true;
  String? _errorMessage;
  bool _isLoading = false;

  bool get _isChange => widget.currentAuthMethod == 'pin';

  static bool _isSixDigits(String value) => RegExp(r'^[0-9]{6}$').hasMatch(value);

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    _currentFocusNode.dispose();
    _newFocusNode.dispose();
    _confirmFocusNode.dispose();
    super.dispose();
  }

  void _clearError([Object? _]) {
    if (_errorMessage != null) setState(() => _errorMessage = null);
  }

  Future<void> _submit() async {
    final current = _currentController.text;
    final next = _newController.text;

    if (widget.currentAuthMethod == 'password' && current.isEmpty) {
      _fail('Enter your current password');
      return;
    }
    if (widget.currentAuthMethod == 'pin' && !_isSixDigits(current)) {
      _fail('Enter your current 6-digit PIN');
      return;
    }
    if (!_isSixDigits(next)) {
      _fail('New PIN must be 6 digits');
      return;
    }
    if (next != _confirmController.text) {
      _fail('PINs do not match');
      return;
    }

    if (widget.currentAuthMethod == 'biometric') {
      final ok = await _authService.authenticateWithBiometrics(
        reason: 'Authenticate to change your security method',
      );
      if (!ok) {
        _fail('Biometric verification failed or was cancelled');
        return;
      }
    } else if (widget.currentAuthMethod == 'password') {
      if (!await _authService.verifyPassword(current)) {
        _fail('Current password is incorrect');
        return;
      }
    } else if (!await _authService.verifyPIN(current)) {
      _fail('Current PIN is incorrect');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    bool success;
    if (widget.currentAuthMethod == 'pin') {
      success = await _authService.changePIN(current, next);
    } else if (widget.currentAuthMethod == 'biometric') {
      success = await _authService.createPIN(next);
      if (success) {
        await _authService.setAuthMethod('pin');
        await EncryptionService.instance.reWrapKey(next);
        await EncryptionService.instance.removeBiometricKwk();
      }
    } else {
      success = await _authService.switchFromPasswordToPIN(current, next);
    }

    if (!mounted) return;
    if (success) {
      ToastUtils.showSuccess('PIN changed successfully');
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const GalleryVaultScreen()),
        (route) => false,
      );
    } else {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Could not change PIN. Check your credentials.';
      });
    }
  }

  void _fail(String message) {
    setState(() => _errorMessage = message);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isChange ? 'Change PIN' : 'Set PIN'),
        automaticallyImplyLeading: !_isLoading,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.currentAuthMethod == 'pin')
                _PinField(
                  label: 'Current PIN',
                  controller: _currentController,
                  focusNode: _currentFocusNode,
                  obscure: true,
                  autofocus: true,
                  onChanged: _clearError,
                  onFilled: () => _newFocusNode.requestFocus(),
                )
              else if (widget.currentAuthMethod == 'password')
                TextField(
                  controller: _currentController,
                  obscureText: _obscureCurrentPassword,
                  autofocus: true,
                  onChanged: _clearError,
                  decoration: InputDecoration(
                    labelText: 'Current password',
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureCurrentPassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: context.textTertiary,
                      ),
                      onPressed: () => setState(() => _obscureCurrentPassword =
                          !_obscureCurrentPassword),
                    ),
                  ),
                )
              else
                Row(
                  children: [
                    Icon(Icons.fingerprint,
                        color: context.accentColor, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'You will verify with your fingerprint before saving.',
                        style: TextStyle(
                            fontSize: 13, color: context.textSecondary),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 24),
              _PinField(
                label: 'New PIN',
                controller: _newController,
                focusNode: _newFocusNode,
                onChanged: _clearError,
                onFilled: () => _confirmFocusNode.requestFocus(),
              ),
              const SizedBox(height: 24),
              _PinField(
                label: 'Confirm new PIN',
                controller: _confirmController,
                focusNode: _confirmFocusNode,
                onChanged: _clearError,
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Text(
                  _errorMessage!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 13,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isLoading ? null : _submit,
                child: _isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(_isChange ? 'Change PIN' : 'Set PIN'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Six-digit PIN entry with dot boxes and a hidden text field
class _PinField extends StatefulWidget {
  final String label;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool obscure;
  final bool autofocus;
  final ValueChanged<String> onChanged;
  final VoidCallback? onFilled;

  const _PinField({
    required this.label,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    this.obscure = false,
    this.autofocus = false,
    this.onFilled,
  });

  @override
  State<_PinField> createState() => _PinFieldState();
}

class _PinFieldState extends State<_PinField> {
  void _listener() {
    if (mounted) setState(() {});
    widget.onChanged(widget.controller.text);
    if (widget.controller.text.length == 6) {
      widget.onFilled?.call();
    }
  }

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_listener);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_listener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.controller.text;
    return GestureDetector(
      onTap: () => FocusScope.of(context).requestFocus(widget.focusNode),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.label,
            style: TextStyle(fontSize: 13, color: context.textSecondary),
          ),
          const SizedBox(height: 8),
          Row(
            children: List.generate(11, (index) {
              if (index.isOdd) {
                return const SizedBox(width: 8);
              }
              final boxIndex = index ~/ 2;
              final filled = boxIndex < text.length;
              return Expanded(
                child: AspectRatio(
                  aspectRatio: 0.85,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: context.backgroundSecondary,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: filled
                            ? context.accentColor
                            : context.borderColor,
                        width: filled ? 1.5 : 1,
                      ),
                    ),
                    child: filled
                        ? Text(
                            widget.obscure ? '•' : text[boxIndex],
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              color: context.textPrimary,
                            ),
                          )
                        : null,
                  ),
                ),
              );
            }),
          ),
          SizedBox(
            width: 0,
            height: 0,
            child: TextField(
              controller: widget.controller,
              focusNode: widget.focusNode,
              autofocus: widget.autofocus,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              decoration: const InputDecoration(
                border: InputBorder.none,
                counterText: '',
              ),
            ),
          ),
        ],
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
      setState(() => _isAvailable = available);
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
          MaterialPageRoute(builder: (context) => const GalleryVaultScreen()),
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
      appBar: AppBar(
        title: const Text('Biometric Unlock'),
        automaticallyImplyLeading: !_isLoading,
      ),
      body: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            const Spacer(),
            Icon(Icons.fingerprint, size: 80, color: context.accentColor),
            const SizedBox(height: 24),
            const Text(
              'Quick & secure access',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'Use your fingerprint or face to unlock the app without typing your credential.',
              style: TextStyle(color: context.textSecondary, height: 1.4),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            if (_errorMessage != null)
              Text(
                _errorMessage!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 13,
                ),
                textAlign: TextAlign.center,
              ),
            const Spacer(),
            if (_isAvailable)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _setupBiometric,
                  child: _isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Enable Biometric'),
                ),
              )
            else
              Text(
                'Biometric authentication is not available on this device',
                style: TextStyle(color: context.textTertiary),
                textAlign: TextAlign.center,
              ),
          ],
        ),
      ),
    );
  }
}
