import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../themes/app_colors.dart';

/// A viewport-filling scanner shared by backup and restore pairing.
/// The caller owns the camera controller and its lifecycle.
class PairingQrScanner extends StatelessWidget {
  const PairingQrScanner({
    super.key,
    required this.controller,
    required this.onDetect,
    required this.onManual,
  });

  final MobileScannerController controller;
  final void Function(BarcodeCapture) onDetect;
  final VoidCallback onManual;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: CustomScrollView(
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'SCAN',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                      color: context.accentColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Hold your camera up to the QR code on the computer screen.',
                    style: TextStyle(
                      fontSize: 13,
                      color: context.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    // Gives the sliver a minimum preview height to measure
                    // without asking the camera for intrinsic dimensions.
                    // Short windows and large text can then scroll instead.
                    child: SizedBox(
                      height: 240,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: ColoredBox(
                          color: Colors.black,
                          child: MobileScanner(
                            controller: controller,
                            fit: BoxFit.contain,
                            onDetect: onDetect,
                            errorBuilder: (context, error) => _ScannerError(
                              message: error.errorCode.name,
                              onManual: onManual,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: TextButton(
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, 48),
                      ),
                      onPressed: onManual,
                      child: const Text('Type the address and code instead'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScannerError extends StatelessWidget {
  const _ScannerError({required this.message, required this.onManual});

  final String message;
  final VoidCallback onManual;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.no_photography, size: 32, color: context.textTertiary),
              const SizedBox(height: 8),
              Text(
                'Camera unavailable ($message).',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: context.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                onPressed: onManual,
                child: const Text('Type the address and code instead'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
