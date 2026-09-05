import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../models/vaulted_file.dart';
import '../providers/vault_providers.dart';
import '../services/desktop_link/transfer_client.dart';
import '../themes/app_colors.dart';

/// Desktop backup screen, flipped architecture (P6.1r).
///
/// The desktop's latchd web UI generates a one-time pairing code (QR +
/// address + code) while its receiver is open. This screen accepts that
/// code two equal ways, scanning the QR or typing the address and code,
/// confirms what will be sent, and pushes the encrypted vault to the
/// computer: key bundle first, missing blobs, manifest last. Centered
/// max-width flat list layout so the screen looks identical on phones
/// and tablets.
class DesktopBackupScreen extends ConsumerStatefulWidget {
  const DesktopBackupScreen({super.key});

  @override
  ConsumerState<DesktopBackupScreen> createState() =>
      _DesktopBackupScreenState();
}

enum _Mode { choose, scan, manual, checking, confirm, preparing, sending, done, error }

class _DesktopBackupScreenState extends ConsumerState<DesktopBackupScreen> {
  _Mode _mode = _Mode.choose;
  String? _error;

  Uri? _base;
  String? _token;
  ReceiverInfo? _receiver;
  DesktopVaultSnapshot? _snapshot;
  DesktopPushProgress? _progress;
  DesktopPushReport? _report;
  bool _cancelled = false;

  final _addrCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  MobileScannerController? _scanner;
  String? _lastCode;
  DateTime _lastCodeAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void dispose() {
    _teardownScanner();
    _addrCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  // Camera lifecycle: the controller exists only while the scan body is on
  // screen. Disposal happens a frame later so the MobileScanner widget is
  // unmounted first.
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
    _receiver = null;
    _snapshot = null;
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
    final client = DesktopPushClient();
    try {
      final receiver = await client.check(base: _base!, token: _token!);
      if (!mounted) return;
      setState(() {
        _receiver = receiver;
        _mode = _Mode.confirm;
      });
    } catch (e) {
      debugPrint('desktop backup: check failed: $e');
      if (!mounted) return;
      setState(() {
        _error = _friendlyError(e);
        _mode = _Mode.error;
      });
    } finally {
      client.close();
    }
  }

  Future<void> _send() async {
    setState(() => _mode = _Mode.preparing);
    try {
      final snapshot = _snapshot ??
          await DesktopVaultSnapshot.fromLiveVault(
            files: ref.read(vaultNotifierProvider).value ?? const [],
            crypto: ref.read(encryptionServiceProvider),
            deviceId: await desktopLinkDeviceId(),
          );
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _progress = null;
        _mode = _Mode.sending;
      });
      final client = DesktopPushClient();
      final DesktopPushReport report;
      try {
        report = await client.push(
          base: _base!,
          token: _token!,
          snapshot: snapshot,
          onProgress: (p) {
            if (mounted) setState(() => _progress = p);
          },
          isCancelled: () => _cancelled,
        );
      } finally {
        client.close();
      }
      if (!mounted) return;
      setState(() {
        _report = report;
        _mode = _Mode.done;
      });
    } catch (e) {
      debugPrint('desktop backup: push failed: $e');
      if (!mounted) return;
      setState(() {
        _error = _friendlyError(e);
        _mode = e is PushCancelledException ? _Mode.confirm : _Mode.error;
      });
    }
  }

  String _friendlyError(Object e) {
    if (e is PushRejectedException) {
      return 'The computer rejected this code. Pairing codes expire after '
          'five idle minutes. Generate a new code on the desktop and scan it '
          'again.';
    }
    if (e is DesktopUnreachableException) {
      final where = _base == null ? '' : ' at ${_base!.host}:${_base!.port}';
      return 'Could not reach the computer$where.\n'
          'Reason: ${e.cause}\n\n'
          'Check that the phone is on Wi-Fi (not mobile data) on the same '
          'network as the computer, that pairing is still open in the '
          'latchd web UI, and that no firewall is blocking the port.';
    }
    if (e is LegacyVaultException) {
      return 'This vault uses an older key format (legacy vault). Unlock it '
          'once in the app to migrate, then try the backup again.';
    }
    return 'Something went wrong:\n$e';
  }

  void _reset() {
    _teardownScanner();
    setState(() {
      _mode = _Mode.choose;
      _base = null;
      _token = null;
      _receiver = null;
      _snapshot = null;
      _progress = null;
      _report = null;
      _error = null;
      _cancelled = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Desktop Backup')),
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
      case _Mode.checking:
        return _busyChildren('Checking the code…');
      case _Mode.confirm:
        return _confirmChildren();
      case _Mode.preparing:
        return _busyChildren('Preparing the backup…');
      case _Mode.sending:
        return _sendingChildren();
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
        'On your computer, open the latchd web UI and start pairing. '
        'It shows a QR code plus an address and pairing code; use '
        'either here.',
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
      _sectionTitle('Know the risks'),
      _hint(
        'Plain HTTP on your local network. Anyone on the same Wi-Fi '
        'who grabs the code can copy the encrypted backup while '
        'pairing is open. Only pair on networks you trust, and close '
        'the pairing window on your computer when you are done.',
      ),
      const SizedBox(height: 16),
      _hint(
        'Pairing on the desktop closes automatically once the backup '
        'completes, or after five idle minutes.',
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

  String _computerName() {
    final host = _receiver?.host ?? '';
    if (host.isEmpty || host == 'localhost') return '';
    return ' · $host';
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
    final receiver = _receiver;
    final files =
        ref.read(vaultNotifierProvider).value ?? const <VaultedFile>[];
    final live = files.where((f) => !f.syncedDeleted).length;
    return [
      _sectionTitle('Confirm'),
      _kv('Computer', '${_base!.host}:${_base!.port}${_computerName()}'),
      _kv(
        'On the computer',
        switch ((receiver?.hasManifest ?? false,
            receiver?.blobCount ?? 0)) {
          (false, 0) => 'no backup yet, this is the first one',
          (true, var n) => 'an earlier backup exists '
              '($n encrypted files stored)',
          (_, var n) => '$n encrypted files from an interrupted pairing',
        },
      ),
      _kv('On this phone', '$live files'),
      const SizedBox(height: 16),
      _hint(
        'Only files missing on the computer are sent. The wrapped '
        'unlock key travels with them; nobody on the network can read '
        'the backup without your vault password.',
      ),
      const SizedBox(height: 16),
      _primaryButton(label: 'Send backup', icon: Icons.backup, onPressed: _send),
      _textAction(label: 'Cancel', onTap: _reset),
    ];
  }

  List<Widget> _sendingChildren() {
    final p = _progress;
    final value = (p != null && p.total > 0) ? p.sent / p.total : null;
    return [
      _sectionTitle('Sending'),
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
            ? 'Counting what the computer is missing…'
            : (p.total == 0
                ? 'The computer already has everything; refreshing the '
                    'manifest…'
                : 'Sending ${p.sent} of ${p.total} files · '
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
          'Backup sent',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 16,
            color: context.textPrimary,
          ),
        ),
      ),
      const SizedBox(height: 8),
      _hint(
        report == null || report.pushed == 0
            ? 'The computer already had everything; its backup is '
                'up to date.'
            : 'Sent ${report.pushed} new file(s)'
                '${report.alreadyPresent > 0 ? ' (${report.alreadyPresent} '
                    'were already there)' : ''} · '
                '${_formatBytes(report.bytes)}.',
      ),
      const SizedBox(height: 4),
      _hint(
        'The computer is verifying the files now. Unlock it there with '
        'your vault password to browse and export.',
      ),
      const SizedBox(height: 16),
      _primaryButton(
        label: 'Send again',
        icon: Icons.refresh,
        onPressed: () {
          _snapshot = null;
          _cancelled = false;
          _send();
        },
      ),
      _textAction(label: 'Pair with another computer', onTap: _reset),
    ];
  }

  List<Widget> _errorChildren() {
    return [
      _sectionTitle('Pairing failed'),
      const SizedBox(height: 8),
      Text(
        _error ?? 'Something went wrong.',
        style: TextStyle(fontSize: 13, color: context.textPrimary),
      ),
      const SizedBox(height: 16),
      _primaryButton(
        label: 'Try again',
        icon: Icons.refresh,
        onPressed: (_mode == _Mode.error && _base != null) ? _check : _reset,
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
