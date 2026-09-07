import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:pointycastle/export.dart' show InvalidCipherTextException;

import '../services/desktop_link/restore_controller.dart';
import '../services/desktop_link/transfer_client.dart';
import '../services/desktop_link/usb_link.dart';
import '../services/encryption_service.dart';
import '../services/vault_service.dart';
import '../themes/app_colors.dart';
import 'auth_method_selection_screen.dart';

/// Restore-before-setup (P6.3, mode 2). Fresh install, no vault yet: the user
/// scans the desktop's restore-session QR (or types address + code), types the
/// ORIGINAL vault password to prove ownership — the received keybundle is
/// unwrapped with it and installed as this device's key material — and the
/// manifest + blobs are pulled into the fresh vault. Setup (PIN / password /
/// biometric choice) resumes right after, and the chosen credential re-wraps
/// the restored key.
class RestoreSetupScreen extends StatefulWidget {
  const RestoreSetupScreen({super.key});

  @override
  State<RestoreSetupScreen> createState() => _RestoreSetupScreenState();
}

enum _Mode { choose, scan, manual, usb, checking, confirm, restoring, done, error }

class _RestoreSetupScreenState extends State<RestoreSetupScreen> {
  _Mode _mode = _Mode.choose;
  String? _error;

  Uri? _base;
  String? _token;
  RestoreSourceInfo? _source;
  Map<String, dynamic>? _keybundle;
  RestoreProgress? _progress;
  DesktopRestoreReport? _report;
  bool _cancelled = false;
  bool _enteredViaUsb = false;
  bool _usbFound = false;

  final _addrCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _passwordFocus = FocusNode();
  MobileScannerController? _scanner;
  String? _lastCode;
  DateTime _lastCodeAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void dispose() {
    _teardownScanner();
    _addrCtrl.dispose();
    _codeCtrl.dispose();
    _passwordCtrl.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  void _teardownScanner() {
    final scanner = _scanner;
    if (scanner == null) return;
    _scanner = null;
    WidgetsBinding.instance.addPostFrameCallback((_) => scanner.dispose());
  }

  void _enterScan() {
    _teardownScanner();
    _scanner = MobileScannerController();
    setState(() => _mode = _Mode.scan);
  }

  void _enterManual() {
    _teardownScanner();
    setState(() => _mode = _Mode.manual);
  }

  void _startUsb() {
    setState(() {
      _enteredViaUsb = true;
      _usbFound = false;
      _cancelled = false;
      _error = null;
      _mode = _Mode.usb;
    });
    _connectUsb();
  }

  // Tap-to-approve USB: probe the cable for a restore session, wait for
  // Allow on the computer, then join the normal check/confirm flow with
  // the received token. Nothing typed.
  Future<void> _connectUsb() async {
    final link = UsbLink();
    try {
      final label = await UsbLink.deviceLabel();
      if (!mounted) return;
      final (base, token) = await link.connect(
        mode: 'restore',
        deviceLabel: label,
        onSessionFound: () {
          if (mounted) setState(() => _usbFound = true);
        },
        isCancelled: () => _cancelled,
      );
      if (!mounted) return;
      _beginSession(base, token);
    } on UsbCancelledException {
      // Backed out; _reset already moved on.
    } catch (e) {
      debugPrint('restore setup: usb connect failed: $e');
      if (!mounted) return;
      setState(() {
        _error = _friendlyUsbError(e);
        _mode = _Mode.error;
      });
    } finally {
      link.close();
    }
  }

  String _friendlyUsbError(Object e) {
    if (e is UsbNoRouteException) {
      return 'No computer answered over USB.\n\n'
          'Check the cable is seated, USB debugging is on, and the adb '
          'reverse command from the desktop web UI ("On a USB cable '
          'instead of Wi-Fi?") is in place — `adb reverse --list` on the '
          'computer shows live routes.';
    }
    if (e is UsbDeniedException) {
      return 'Denied on the computer. Tap Connect via USB again if that '
          'was a mistake.';
    }
    if (e is UsbApprovalTimeoutException) {
      return 'Nobody tapped Allow in time. Tap Connect via USB again '
          'while you sit at the computer.';
    }
    if (e is UsbModeMismatchException) {
      return e.message;
    }
    return _friendlyError(e);
  }

  void _note(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _acceptCode(String raw) {
    final parsed = DesktopPushClient.parsePairingUrl(raw);
    if (parsed == null) {
      _note('That is not a Latch pairing link. It looks like '
          'http://192.168.1.24:39371/#…');
      return;
    }
    final (base, token) = parsed;
    _beginSession(base, token);
  }

  void _beginSession(Uri base, String token) {
    _base = base;
    _token = token;
    _source = null;
    _keybundle = null;
    _report = null;
    _cancelled = false;
    _teardownScanner();
    _check();
  }

  void _onDetect(BarcodeCapture capture) {
    final raw = capture.barcodes
        .map((b) => b.rawValue)
        .whereType<String>()
        .where((v) => v.startsWith('http'))
        .firstOrNull;
    if (raw == null || raw.isEmpty) return;
    final recent = DateTime.now().difference(_lastCodeAt) <
        const Duration(seconds: 3);
    if (recent && raw == _lastCode) return;
    _lastCode = raw;
    _lastCodeAt = DateTime.now();
    _acceptCode(raw);
  }

  Future<void> _check() async {
    setState(() => _mode = _Mode.checking);
    final client = DesktopRestoreClient();
    try {
      final source = await client.check(base: _base!, token: _token!);
      if (!source.isRestoreSession) {
        _fail(
          'The computer is receiving a backup, not serving one. In the '
          'latchd web UI switch the session to "Restore to phone" and try '
          'again.',
        );
        return;
      }
      if (!source.hasManifest) {
        _fail('The computer has no backup to restore. Make a backup first.');
        return;
      }
      if (!source.hasKeybundle) {
        _fail('The backup on the computer has no unlock key, so it cannot '
            'be restored onto a fresh install.');
        return;
      }
      final keybundle = await client.fetchKeybundle(
        base: _base!,
        token: _token!,
      );
      if (keybundle == null) {
        _fail('The computer no longer offers the unlock key. Restart the '
            'restore session and try again.');
        return;
      }
      if (!mounted) return;
      setState(() {
        _source = source;
        _keybundle = keybundle;
        _mode = _Mode.confirm;
      });
    } catch (e) {
      debugPrint('restore setup: check failed: $e');
      _fail(_friendlyError(e));
    } finally {
      client.close();
    }
  }

  Future<void> _restore() async {
    final password = _passwordCtrl.text;
    if (password.isEmpty) {
      _note('Type the vault password you used on your old device.');
      return;
    }
    setState(() {
      _progress = null;
      _cancelled = false;
      _mode = _Mode.restoring;
    });
    final client = DesktopRestoreClient();
    final controller = RestoreController(
      VaultService.instance.store,
      EncryptionService.instance,
    );
    try {
      final report = await controller.restoreFresh(
        client: client,
        base: _base!,
        token: _token!,
        keybundle: _keybundle!,
        originalPassword: password,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
        isCancelled: () => _cancelled,
      );
      if (!mounted) return;
      setState(() {
        _report = report;
        _mode = _Mode.done;
      });
    } catch (e) {
      debugPrint('restore setup: restore failed: $e');
      if (!mounted) return;
      setState(() {
        _error = _friendlyError(e);
        _mode = e is RestoreCancelledException ? _Mode.confirm : _Mode.error;
      });
    } finally {
      client.close();
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _error = message;
      _mode = _Mode.error;
    });
  }

  String _friendlyError(Object e) {
    if (e is PushRejectedException) {
      return 'The computer rejected this code. Restore sessions expire '
          'after five idle minutes. Generate a new code on the desktop and '
          'scan it again.';
    }
    if (e is DesktopUnreachableException) {
      final where = _base == null ? '' : ' at ${_base!.host}:${_base!.port}';
      final usb = _base != null &&
              (_base!.host == '127.0.0.1' || _base!.host == 'localhost')
          ? 'The USB link dropped: check the cable is seated and USB '
              'debugging is still on, then re-run the adb reverse command '
              'shown in the desktop web UI (`adb reverse --list` shows '
              'live routes) and try again.\n\n'
          : 'On a USB cable instead of Wi-Fi: plug in, run the adb reverse '
              'command shown in the desktop web UI ("On a USB cable instead '
              'of Wi-Fi?") and tap Connect via USB — no typing.\n\n';
      return 'Could not reach the computer$where.\n'
          'Reason: ${e.cause}\n\n'
          '$usb'
          'Check that the phone is on Wi-Fi (not mobile data) on the same '
          'network as the computer, that the restore session is still open '
          'in the latchd web UI, and that no firewall is blocking the port.';
    }
    if (e is InvalidCipherTextException) {
      return 'That password does not unlock the backup. Type the vault '
          'password you used on the device the backup came from.';
    }
    return 'Something went wrong:\n$e';
  }

  void _reset() {
    _teardownScanner();
    setState(() {
      _mode = _Mode.choose;
      _base = null;
      _token = null;
      _source = null;
      _keybundle = null;
      _progress = null;
      _report = null;
      _error = null;
      _cancelled = false;
      _enteredViaUsb = false;
      _usbFound = false;
    });
  }

  void _continueSetup() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthMethodSelectionScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Restore from Desktop Backup')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: _buildBody(),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildBody() {
    switch (_mode) {
      case _Mode.choose:
        return _chooseChildren();
      case _Mode.scan:
        return _scanChildren();
      case _Mode.manual:
        return _manualChildren();
      case _Mode.usb:
        return _usbChildren();
      case _Mode.checking:
        return _busyChildren('Checking the code…');
      case _Mode.confirm:
        return _confirmChildren();
      case _Mode.restoring:
        return _restoringChildren();
      case _Mode.done:
        return _doneChildren();
      case _Mode.error:
        return _errorChildren();
    }
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

  Widget _hint(String text) {
    return Text(
      text,
      style: TextStyle(fontSize: 13, color: context.textSecondary),
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

  Widget _textAction({required String label, required VoidCallback onTap}) {
    return Center(
      child: TextButton(onPressed: onTap, child: Text(label)),
    );
  }

  Widget _primaryButton({
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }

  List<Widget> _chooseChildren() {
    return [
      _sectionTitle('Connect'),
      _hint(
        'On your computer, open the latchd web UI and switch the session '
        'to "Restore to phone". It shows a QR code plus an address and '
        'code; use either here. On a USB cable, Connect via USB needs no '
        'typing — just approve on the computer.',
      ),
      const SizedBox(height: 8),
      _tile(
        icon: Icons.usb,
        title: 'Connect via USB',
        subtitle: 'Cable + approve on the computer, no typing',
        onTap: _startUsb,
      ),
      const SizedBox(height: 8),
      _tile(
        icon: Icons.qr_code_scanner,
        title: 'Scan the QR code',
        subtitle: 'Point your camera at the desktop screen',
        onTap: _enterScan,
      ),
      _tile(
        icon: Icons.keyboard,
        title: 'Type the address and code',
        subtitle: 'Enter what is shown under the QR code',
        onTap: _enterManual,
      ),
      const SizedBox(height: 24),
      _sectionTitle('What happens'),
      _hint(
        'The encrypted backup is copied to this phone, and its unlock key '
        'becomes this device\'s vault key once you confirm it with the '
        'ORIGINAL vault password. You then choose how to unlock the vault '
        'here (PIN, password or biometrics) — that choice replaces the '
        'old password on this device.',
      ),
      const SizedBox(height: 16),
      _hint(
        'Plain HTTP on your local network. Only restore on networks you '
        'trust, and close the session on your computer when you are done.',
      ),
    ];
  }

  List<Widget> _scanChildren() {
    return [
      _sectionTitle('Scan'),
      _hint('Hold your camera up to the QR code on the computer screen.'),
      const SizedBox(height: 16),
      ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: 240,
          width: double.infinity,
          child: MobileScanner(
            controller: _scanner,
            onDetect: _onDetect,
            errorBuilder: (context, error) => _ScannerError(
              message: error.errorCode.name,
              onManual: _enterManual,
            ),
          ),
        ),
      ),
      const SizedBox(height: 8),
      _textAction(label: 'Type the address and code instead', onTap: _enterManual),
    ];
  }

  List<Widget> _manualChildren() {
    return [
      _sectionTitle('Connect'),
      _hint('Copy the two lines shown under the QR code on your computer.'),
      const SizedBox(height: 8),
      _hint(
        'On a USB cable, Connect via USB needs no typing — prefer that. '
        'Manual fallback: run the adb reverse command shown in the '
        'desktop web UI, then enter address 127.0.0.1:<port> here.',
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _addrCtrl,
        keyboardType: TextInputType.url,
        autocorrect: false,
        enableSuggestions: false,
        decoration: const InputDecoration(
          labelText: 'Address',
          hintText: '192.168.1.24:39371',
        ),
        onSubmitted: (_) => _submitManual(),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _codeCtrl,
        autocorrect: false,
        enableSuggestions: false,
        maxLines: 1,
        decoration: const InputDecoration(
          labelText: 'Pairing code',
          hintText: 'The 64-character code under the QR',
        ),
        onSubmitted: (_) => _submitManual(),
      ),
      const SizedBox(height: 16),
      _primaryButton(label: 'Connect', icon: Icons.link, onPressed: _submitManual),
      _textAction(label: 'Scan the QR code instead', onTap: _enterScan),
    ];
  }

  // Accepts a bare host:port plus the separate code field, and stays paste
  // friendly: a full link dropped into the address field also works.
  void _submitManual() {
    FocusManager.instance.primaryFocus?.unfocus();
    var addr = _addrCtrl.text.trim();
    final code = _codeCtrl.text
        .replaceAll(RegExp(r'[\s\-]'), '')
        .toLowerCase();
    if (addr.isEmpty) {
      _note('Type the address shown on the computer, like 192.168.1.24:39371.');
      return;
    }

    Uri base;
    String token;
    if (addr.contains('#')) {
      final parsed = DesktopPushClient.parsePairingUrl(addr);
      if (parsed == null) {
        _note('That pairing link does not look right. It looks like '
            'http://192.168.1.24:39371/#…');
        return;
      }
      final (b, t) = parsed;
      base = b;
      token = t;
    } else {
      final scheme = RegExp(r'^https?://');
      if (scheme.hasMatch(addr)) addr = addr.replaceFirst(scheme, '');
      addr = addr.replaceAll(RegExp(r'/+$'), '');
      if (!addr.contains(':')) {
        _note('Include the port too, like 192.168.1.24:39371.');
        return;
      }
      if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(code)) {
        _note('The pairing code is the 64 characters shown under the QR '
            'code. Copy all of it.');
        return;
      }
      final uri = Uri.tryParse('http://$addr');
      if (uri == null || uri.host.isEmpty || uri.port <= 0) {
        _note('That address does not look right. It looks like '
            '192.168.1.24:39371.');
        return;
      }
      base = Uri(scheme: 'http', host: uri.host, port: uri.port);
      token = code;
    }
    _beginSession(base, token);
  }

  List<Widget> _usbChildren() {
    return [
      _sectionTitle('USB'),
      const SizedBox(height: 24),
      Center(
        child: Column(
          children: [
            CircularProgressIndicator(color: context.accentColor),
            const SizedBox(height: 16),
            Text(
              _usbFound
                  ? 'Approve on your computer — tap Allow once in the latchd web UI.'
                  : 'Looking for the computer over USB…',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
      const SizedBox(height: 8),
      _hint(
        'Plug in with USB debugging on and run the adb reverse command '
        'shown in the desktop web UI. Nothing to type: the approval '
        'happens on the computer.',
      ),
      const SizedBox(height: 8),
      _textAction(
        label: 'Cancel',
        onTap: () {
          _cancelled = true;
          _reset();
        },
      ),
    ];
  }

  List<Widget> _busyChildren(String message) {
    return [
      const SizedBox(height: 40),
      Center(
        child: Column(
          children: [
            CircularProgressIndicator(color: context.accentColor),
            const SizedBox(height: 16),
            Text(message),
          ],
        ),
      ),
    ];
  }

  Widget _kv(String label, String value) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(
        label,
        style: TextStyle(fontSize: 12, color: context.textTertiary),
      ),
      subtitle: Text(
        value,
        style: TextStyle(fontSize: 13, color: context.textPrimary),
      ),
    );
  }

  List<Widget> _confirmChildren() {
    final source = _source;
    return [
      _sectionTitle('Confirm'),
      _kv('Computer', '${_base!.host}:${_base!.port}'),
      _kv(
        'On the computer',
        'a backup with ${source?.blobCount ?? 0} encrypted file(s)',
      ),
      const SizedBox(height: 16),
      _sectionTitle('Original vault password'),
      _hint(
        'The password this vault used on the device the backup came from. '
        'It is checked against the backup before anything is written; a '
        'wrong password changes nothing.',
      ),
      const SizedBox(height: 8),
      TextField(
        controller: _passwordCtrl,
        focusNode: _passwordFocus,
        obscureText: true,
        autocorrect: false,
        enableSuggestions: false,
        onSubmitted: (_) => _restore(),
        decoration: const InputDecoration(
          labelText: 'Vault password',
        ),
      ),
      const SizedBox(height: 16),
      _primaryButton(
        label: 'Restore backup',
        icon: Icons.settings_backup_restore,
        onPressed: _restore,
      ),
      _textAction(label: 'Cancel', onTap: _reset),
    ];
  }

  List<Widget> _restoringChildren() {
    final p = _progress;
    final value = (p != null && p.total > 0) ? p.restored / p.total : null;
    return [
      _sectionTitle('Restoring'),
      const SizedBox(height: 16),
      LinearProgressIndicator(
        value: value,
        minHeight: 6,
        borderRadius: BorderRadius.circular(3),
        color: context.accentColor,
        backgroundColor: context.textTertiary.withValues(alpha: 0.2),
      ),
      const SizedBox(height: 12),
      _hint(
        p == null
            ? 'Checking the unlock key and counting files…'
            : (p.total == 0
                ? 'The backup is empty; finishing…'
                : 'Restoring ${p.restored} of ${p.total} files · '
                    '${_formatBytes(p.bytes)}'),
      ),
      const SizedBox(height: 8),
      _textAction(
        label: 'Cancel',
        onTap: () => _cancelled = true,
      ),
    ];
  }

  List<Widget> _doneChildren() {
    final report = _report;
    return [
      _sectionTitle('Done'),
      const SizedBox(height: 16),
      Icon(Icons.check_circle, color: context.accentColor, size: 44),
      const SizedBox(height: 12),
      Center(
        child: Text(
          'Backup restored',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 16,
            color: context.textPrimary,
          ),
        ),
      ),
      const SizedBox(height: 8),
      _hint(
        report == null || report.restored == 0
            ? 'The backup contained no files to restore.'
            : 'Restored ${report.restored} file(s)'
                '${report.skipped > 0 ? ' (${report.skipped} were missing '
                    'from the backup)' : ''} · '
                '${_formatBytes(report.bytes)}.',
      ),
      const SizedBox(height: 4),
      _hint(
        'One more step: choose how to unlock the vault on this phone. The '
        'vault key stays wrapped with the original password until then.',
      ),
      const SizedBox(height: 16),
      _primaryButton(
        label: 'Continue setup',
        icon: Icons.arrow_forward,
        onPressed: _continueSetup,
      ),
    ];
  }

  List<Widget> _errorChildren() {
    return [
      _sectionTitle('Restore failed'),
      const SizedBox(height: 8),
      Text(
        _error ?? 'Something went wrong.',
        style: TextStyle(fontSize: 13, color: context.textPrimary),
      ),
      const SizedBox(height: 16),
      _primaryButton(
        label: 'Try again',
        icon: Icons.refresh,
        onPressed: (_mode == _Mode.error && _base != null)
            ? _check
            : (_enteredViaUsb ? _startUsb : _reset),
      ),
      _textAction(label: 'Start over', onTap: _reset),
    ];
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

/// Camera-unavailable fallback inside the scanner box.
class _ScannerError extends StatelessWidget {
  const _ScannerError({required this.message, required this.onManual});

  final String message;
  final VoidCallback onManual;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      padding: const EdgeInsets.all(16),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.no_photography,
                size: 32, color: context.textTertiary),
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
              onPressed: onManual,
              child: const Text('Type the address and code instead'),
            ),
          ],
        ),
      ),
    );
  }
}
