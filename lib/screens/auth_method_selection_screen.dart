import 'package:flutter/material.dart';
import '../themes/app_colors.dart';
import '../widgets/animated_latch_logo.dart';
import '../widgets/auth_method_card.dart';
import 'pin_setup_screen.dart';
import 'password_setup_screen.dart';
import 'biometric_setup_screen.dart';
import '../services/auth_service.dart';

/// First-time authentication method selection screen.
class AuthMethodSelectionScreen extends StatefulWidget {
  const AuthMethodSelectionScreen({super.key});

  @override
  State<AuthMethodSelectionScreen> createState() =>
      _AuthMethodSelectionScreenState();
}

class _AuthMethodSelectionScreenState extends State<AuthMethodSelectionScreen>
    with SingleTickerProviderStateMixin {
  static const double _logoSize = 80;

  final AuthService _authService = AuthService();
  bool _isBiometricAvailable = false;
  bool _launched = false;
  bool _liftReady = false;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  );

  // Assemble + glow: no layout dependency, so build the curves once.
  late final Animation<double> _assemble = CurvedAnimation(
      parent: _controller, curve: const Interval(0.0, 0.40, curve: Curves.easeOut));
  late final Animation<double> _glowFade = Tween(begin: 0.0, end: 0.6).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.30, curve: Curves.easeOut)));
  late final Animation<double> _glowScale = Tween(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.30, curve: Curves.easeOut)));

  // Lift: needs screen height, so it's built in didChangeDependencies.
  late Animation<double> _liftTranslate;
  late Animation<double> _liftScale;

  @override
  void initState() {
    super.initState();
    _checkBiometricAvailability();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final mq = MediaQuery.of(context);
    if (!_liftReady) {
      _liftReady = true;
      // Logo's natural center Y from screen top: safe area + 24 padding + 32 spacer + half logo.
      final logoCenterY = mq.padding.top + 24.0 + 32.0 + _logoSize / 2;
      final delta = mq.size.height / 2 - logoCenterY;
      _liftTranslate = Tween(begin: delta, end: 0.0).animate(CurvedAnimation(
          parent: _controller, curve: const Interval(0.32, 0.58, curve: Curves.easeInOutCubic)));
      _liftScale = Tween(begin: 1.3, end: 1.0).animate(CurvedAnimation(
          parent: _controller, curve: const Interval(0.32, 0.58, curve: Curves.easeInOutCubic)));
    }
    if (!_launched) {
      _launched = true;
      if (mq.disableAnimations) {
        _controller.value = 1.0;
      } else {
        _controller.forward();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _checkBiometricAvailability() async {
    final isAvailable = await _authService.isBiometricAvailable();
    if (!mounted) return;
    setState(() => _isBiometricAvailable = isAvailable);
  }

  Animation<double> _fadeIn(double a, double b, [Curve c = Curves.easeOut]) =>
      Tween(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(parent: _controller, curve: Interval(a, b, curve: c)));

  Widget _entrance({
    required double a,
    required double b,
    required double dy,
    required Widget child,
    Curve curve = Curves.easeOut,
  }) {
    final fade = _fadeIn(a, b, curve);
    final slide = _fadeIn(a, b, curve);
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, c) => Opacity(
        opacity: fade.value,
        child: Transform.translate(
          offset: Offset(0, (1 - slide.value) * dy),
          child: c,
        ),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 32),

              // Assembles at screen center, then lifts to this top slot.
              AnimatedBuilder(
                animation: _controller,
                builder: (_, child) => Transform.translate(
                  offset: Offset(0, _liftTranslate.value),
                  child: Transform.scale(scale: _liftScale.value, child: child),
                ),
                child: _LogoEntrance(
                  assemble: _assemble,
                  glowFade: _glowFade,
                  glowScale: _glowScale,
                  glowColor: context.accentColor,
                  logoColor: context.textPrimary,
                  size: _logoSize,
                ),
              ),

              const SizedBox(height: 24),

              _entrance(
                a: 0.52,
                b: 0.70,
                dy: 24,
                child: Text(
                  'Welcome to Latch',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    color: context.textPrimary,
                    fontFamily: 'ProductSans',
                  ),
                ),
              ),

              const SizedBox(height: 12),

              _entrance(
                a: 0.60,
                b: 0.76,
                dy: 20,
                child: Text(
                  'Choose how you want to secure your media vault',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: context.textSecondary,
                    fontFamily: 'ProductSans',
                  ),
                ),
              ),

              const SizedBox(height: 48),

              Expanded(
                child: ListView(
                  children: [
                    _entrance(
                      a: 0.64,
                      b: 0.80,
                      dy: 28,
                      child: AuthMethodCard(
                        icon: Icons.pin_outlined,
                        title: 'PIN',
                        description: '6-digit numeric code',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const PinSetupScreen(),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _entrance(
                      a: 0.70,
                      b: 0.84,
                      dy: 28,
                      child: AuthMethodCard(
                        icon: Icons.lock_outlined,
                        title: 'Password',
                        description: 'Alphanumeric password',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const PasswordSetupScreen(),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _entrance(
                      a: 0.76,
                      b: 0.90,
                      dy: 28,
                      child: AuthMethodCard(
                        icon: Icons.fingerprint,
                        title: 'Biometrics',
                        description: _isBiometricAvailable
                            ? 'Use your fingerprint'
                            : 'Not available on this device',
                        onTap: _isBiometricAvailable
                            ? () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        const BiometricSetupScreen(),
                                  ),
                                )
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

class _LogoEntrance extends StatelessWidget {
  final Animation<double> assemble;
  final Animation<double> glowFade;
  final Animation<double> glowScale;
  final Color glowColor;
  final Color logoColor;
  final double size;

  const _LogoEntrance({
    required this.assemble,
    required this.glowFade,
    required this.glowScale,
    required this.glowColor,
    required this.logoColor,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: glowFade,
            builder: (_, __) => Opacity(
              opacity: glowFade.value,
              child: Transform.scale(
                scale: glowScale.value,
                child: Container(
                  width: 176,
                  height: 176,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        glowColor.withValues(alpha: 0.5),
                        glowColor.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          AnimatedLatchLogo(
            progress: assemble,
            size: size,
            color: logoColor,
          ),
        ],
      ),
    );
  }
}
