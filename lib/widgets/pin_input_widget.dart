import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../themes/app_colors.dart';

// Custom PIN input widget with numeric keypad.
class PinInputController {
  VoidCallback? _clear;

  void _attach({required VoidCallback clear}) {
    _clear = clear;
  }

  void _detach() {
    _clear = null;
  }

  void clear() {
    _clear?.call();
  }
}

class PinInputWidget extends StatefulWidget {
  final Function(String) onPinComplete;
  final VoidCallback? onPinChanged;
  final String? errorMessage;
  final PinInputController? controller;
  final bool enabled;
  final bool autofillEnabled;
  final bool isLoading;

  const PinInputWidget({
    super.key,
    required this.onPinComplete,
    this.onPinChanged,
    this.errorMessage,
    this.controller,
    this.enabled = true,
    this.autofillEnabled = false,
    this.isLoading = false,
  });

  @override
  State<PinInputWidget> createState() => _PinInputWidgetState();
}

class _PinInputWidgetState extends State<PinInputWidget> {
  String _pin = '';
  final int _pinLength = 6;
  final FocusNode _focusNode = FocusNode();
  final TextEditingController _textController = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.controller?._attach(clear: clearPin);
  }

  @override
  void didUpdateWidget(covariant PinInputWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller?._detach();
    widget.controller?._attach(clear: clearPin);
  }

  @override
  void dispose() {
    widget.controller?._detach();
    _focusNode.dispose();
    _textController.dispose();
    super.dispose();
  }

  void _handlePinChanged(String value) {
    final nextPin =
        value.length > _pinLength ? value.substring(0, _pinLength) : value;
    if (nextPin == _pin) return;

    setState(() {
      _pin = nextPin;
    });
    widget.onPinChanged?.call();

    if (_pin.length == _pinLength) {
      widget.onPinComplete(_pin);
    }
  }

  void _clearPin() {
    setState(() {
      _pin = '';
    });
    _textController.clear();
    FocusScope.of(context).requestFocus(_focusNode);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor),
      ),
      child: GestureDetector(
        onTap: widget.enabled
            ? () => FocusScope.of(context).requestFocus(_focusNode)
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'PIN',
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
            if (widget.isLoading)
              const SizedBox(
                height: 48,
                width: double.infinity,
                child: Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  ),
                ),
              )
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(_pinLength, (index) {
                  final isFilled = index < _pin.length;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    curve: Curves.easeOut,
                    width: 40,
                    height: 48,
                    decoration: BoxDecoration(
                      color: isFilled
                          ? context.accentColor.withValues(alpha: 0.12)
                          : context.backgroundSecondary,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isFilled
                            ? context.accentColor
                            : context.dividerColor,
                        width: isFilled ? 1.4 : 1,
                      ),
                    ),
                    child: Center(
                      child: AnimatedScale(
                        scale: isFilled ? 1 : 0,
                        duration: const Duration(milliseconds: 120),
                        curve: Curves.easeOut,
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: context.accentColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            SizedBox(
              width: 0,
              height: 0,
              child: TextField(
                controller: _textController,
                focusNode: _focusNode,
                enabled: widget.enabled,
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: _pinLength,
                autofillHints: widget.autofillEnabled
                    ? const [AutofillHints.password]
                    : null,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(_pinLength),
                ],
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  counterText: '',
                ),
                onChanged: _handlePinChanged,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Method to expose clear function
  void clearPin() {
    _clearPin();
  }
}
