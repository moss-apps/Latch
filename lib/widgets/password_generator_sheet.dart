import 'dart:math';

import 'package:flutter/material.dart';

import '../themes/app_colors.dart';

class PasswordGeneratorSheet extends StatefulWidget {
  final void Function(String password) onGenerate;

  const PasswordGeneratorSheet({
    super.key,
    required this.onGenerate,
  });

  @override
  State<PasswordGeneratorSheet> createState() => _PasswordGeneratorSheetState();
}

class _PasswordGeneratorSheetState extends State<PasswordGeneratorSheet> {
  double _length = 20;
  bool _useUpper = true;
  bool _useLower = true;
  bool _useDigits = true;
  bool _useSymbols = true;
  bool _excludeAmbiguous = true;
  String _generated = '';

  static const String _upper = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  static const String _lower = 'abcdefghijklmnopqrstuvwxyz';
  static const String _digits = '0123456789';
  static const String _symbols = '!@#\$%^&*()-_=+[]{}|;:,.<>?';
  static const String _ambiguous = 'Il1O0o';

  String get _charset {
    final chars = StringBuffer();
    if (_useUpper) chars.write(_upper);
    if (_useLower) chars.write(_lower);
    if (_useDigits) chars.write(_digits);
    if (_useSymbols) chars.write(_symbols);
    var result = chars.toString();
    if (_excludeAmbiguous) {
      result = result.split('').where((c) => !_ambiguous.contains(c)).join();
    }
    return result;
  }

  void _generate() {
    final charset = _charset;
    if (charset.isEmpty) {
      setState(() => _generated = '');
      return;
    }
    final random = Random.secure();
    final values =
        List<int>.generate(_length.round(), (_) => random.nextInt(charset.length));
    setState(() {
      _generated = String.fromCharCodes(
        values.map((i) => charset.codeUnitAt(i)),
      );
    });
  }

  String get _strengthLabel {
    final len = _generated.length;
    if (len == 0) return '';
    final pool = _charset.length;
    final entropy = len * (log(pool) / log(2));
    if (entropy < 40) return 'Weak';
    if (entropy < 60) return 'Fair';
    if (entropy < 80) return 'Strong';
    return 'Very Strong';
  }

  Color get _strengthColor {
    final len = _generated.length;
    if (len == 0) return Colors.grey;
    final pool = _charset.length;
    final entropy = len * (log(pool) / log(2));
    if (entropy < 40) return AppColors.darkError;
    if (entropy < 60) return AppColors.darkWarning;
    if (entropy < 80) return AppColors.darkSuccess;
    return AppColors.darkSuccess;
  }

  @override
  void initState() {
    super.initState();
    _generate();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        top: 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Password Generator',
            style: TextStyle(
              fontFamily: 'ProductSans',
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: context.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          _buildPreview(),
          const SizedBox(height: 16),
          _buildLengthSlider(),
          const SizedBox(height: 12),
          _buildToggleRow('Uppercase (A-Z)', _useUpper, (v) {
            setState(() => _useUpper = v);
            _generate();
          }),
          _buildToggleRow('Lowercase (a-z)', _useLower, (v) {
            setState(() => _useLower = v);
            _generate();
          }),
          _buildToggleRow('Digits (0-9)', _useDigits, (v) {
            setState(() => _useDigits = v);
            _generate();
          }),
          _buildToggleRow('Symbols (!@#...)', _useSymbols, (v) {
            setState(() => _useSymbols = v);
            _generate();
          }),
          _buildToggleRow('Exclude ambiguous (Il1O0o)',
              _excludeAmbiguous, (v) {
            setState(() => _excludeAmbiguous = v);
            _generate();
          }),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _generate,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Regenerate'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: context.accentColor,
                    side: BorderSide(color: context.borderColor),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _generated.isEmpty
                      ? null
                      : () {
                          widget.onGenerate(_generated);
                          Navigator.pop(context);
                        },
                  icon: const Icon(Icons.check),
                  label: const Text('Use'),
                  style: FilledButton.styleFrom(
                    backgroundColor: context.accentColor,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _generated.isEmpty ? 'Select at least one charset' : _generated,
            style: TextStyle(
              fontFamily: 'ProductSans',
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: _generated.isEmpty
                  ? context.textTertiary
                  : context.textPrimary,
            ),
          ),
          if (_generated.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  _strengthLabel,
                  style: TextStyle(
                    fontFamily: 'ProductSans',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _strengthColor,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: _strengthProgress,
                      backgroundColor: context.borderColor,
                      valueColor: AlwaysStoppedAnimation(_strengthColor),
                      minHeight: 4,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  double get _strengthProgress {
    final len = _generated.length;
    if (len == 0) return 0;
    final pool = _charset.length;
    final entropy = len * (log(pool) / log(2));
    return (entropy / 120).clamp(0.0, 1.0);
  }

  Widget _buildLengthSlider() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Length',
              style: TextStyle(
                fontFamily: 'ProductSans',
                fontSize: 14,
                color: context.textSecondary,
              ),
            ),
            Text(
              '${_length.round()}',
              style: TextStyle(
                fontFamily: 'ProductSans',
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: context.accentColor,
              ),
            ),
          ],
        ),
        Slider(
          value: _length,
          min: 8,
          max: 64,
          divisions: 56,
          activeColor: context.accentColor,
          onChanged: (v) {
            setState(() => _length = v);
            _generate();
          },
        ),
      ],
    );
  }

  Widget _buildToggleRow(
    String label,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontFamily: 'ProductSans',
              fontSize: 14,
              color: context.textSecondary,
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: context.accentColor,
          ),
        ],
      ),
    );
  }
}
