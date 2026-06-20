import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';
import 'package:local_auth_darwin/local_auth_darwin.dart';

import '../models/password_entry.dart';
import '../services/password_service.dart';
import '../themes/app_colors.dart';

class AutofillSelectionScreen extends StatefulWidget {
  const AutofillSelectionScreen({super.key});

  @override
  State<AutofillSelectionScreen> createState() =>
      _AutofillSelectionScreenState();
}

class _AutofillSelectionScreenState extends State<AutofillSelectionScreen> {
  static const MethodChannel _channel =
      MethodChannel('com.mossapps.locker/autofill');

  final LocalAuthentication _localAuth = LocalAuthentication();
  final TextEditingController _searchController = TextEditingController();

  bool _isAuthenticating = true;
  bool _authFailed = false;
  bool _biometricsUnavailable = false;
  bool _isLoadingEntries = false;
  bool _isDecrypting = false;
  String? _error;

  List<PasswordEntry> _allEntries = [];
  List<PasswordEntry> _filteredEntries = [];

  @override
  void initState() {
    super.initState();
    _authenticate();
  }

  Future<void> _authenticate() async {
    setState(() {
      _isAuthenticating = true;
      _authFailed = false;
      _biometricsUnavailable = false;
      _error = null;
    });

    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      if (!canCheck) {
        setState(() {
          _biometricsUnavailable = true;
          _isAuthenticating = false;
        });
        return;
      }

      final didAuth = await _localAuth.authenticate(
        localizedReason: 'Authenticate to fill passwords',
        biometricOnly: true,
        authMessages: const <AuthMessages>[
          AndroidAuthMessages(
            signInTitle: 'Latch Autofill',
            cancelButton: 'Cancel',
          ),
          IOSAuthMessages(
            cancelButton: 'Cancel',
          ),
        ],
      );

      if (didAuth) {
        await _loadEntries();
      } else {
        setState(() {
          _authFailed = true;
          _isAuthenticating = false;
        });
      }
    } on PlatformException {
      setState(() {
        _authFailed = true;
        _isAuthenticating = false;
      });
    }
  }

  Future<void> _loadEntries() async {
    setState(() {
      _isLoadingEntries = true;
      _isAuthenticating = false;
    });

    try {
      final entries = await PasswordService.instance.loadPasswords();
      entries.sort((a, b) {
        if (a.isFavorite != b.isFavorite) return a.isFavorite ? -1 : 1;
        return b.updatedAt.compareTo(a.updatedAt);
      });
      setState(() {
        _allEntries = entries;
        _filteredEntries = entries;
        _isLoadingEntries = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load passwords';
        _isLoadingEntries = false;
      });
    }
  }

  void _filterEntries(String query) {
    final q = query.toLowerCase().trim();
    setState(() {
      _filteredEntries = q.isEmpty
          ? _allEntries
          : _allEntries
              .where((e) =>
                  e.title.toLowerCase().contains(q) ||
                  e.tags.any((t) => t.toLowerCase().contains(q)))
              .toList();
    });
  }

  Future<void> _selectEntry(PasswordEntry entry) async {
    setState(() => _isDecrypting = true);

    try {
      final content = await PasswordService.instance.decryptContent(entry);
      await _channel.invokeMethod('fillCredentials', {
        'username': content.username,
        'password': content.password,
        'title': entry.title,
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to decrypt entry';
        _isDecrypting = false;
      });
    }
  }

  Future<void> _cancel() async {
    try {
      await _channel.invokeMethod('cancel');
    } catch (_) {}
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: Scaffold(
        backgroundColor: context.backgroundColor,
        appBar: AppBar(
          backgroundColor: context.backgroundColor,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.close, color: context.textPrimary),
            onPressed: _cancel,
          ),
          title: Text(
            'Select Password',
            style: TextStyle(
              fontFamily: 'ProductSans',
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: context.textPrimary,
            ),
          ),
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isAuthenticating || _isDecrypting) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation(context.accentColor),
            ),
            const SizedBox(height: 16),
            Text(
              _isDecrypting ? 'Decrypting...' : 'Authenticating...',
              style: TextStyle(
                fontFamily: 'ProductSans',
                fontSize: 14,
                color: context.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    if (_biometricsUnavailable) {
      return _buildMessageState(
        icon: Icons.fingerprint,
        title: 'Biometrics Required',
        subtitle: 'Set up fingerprint or face unlock to use autofill',
        showRetry: false,
      );
    }

    if (_authFailed) {
      return _buildMessageState(
        icon: Icons.lock_outline,
        title: 'Authentication Failed',
        subtitle: 'Tap to try again',
        showRetry: true,
      );
    }

    if (_error != null) {
      return _buildMessageState(
        icon: Icons.error_outline,
        title: _error!,
        subtitle: 'Tap to retry',
        showRetry: true,
      );
    }

    if (_isLoadingEntries) {
      return Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation(context.accentColor),
        ),
      );
    }

    if (_allEntries.isEmpty) {
      return _buildMessageState(
        icon: Icons.password_outlined,
        title: 'No Passwords Saved',
        subtitle: 'Add passwords in Latch to use autofill',
        showRetry: false,
      );
    }

    return Column(
      children: [
        _buildSearchField(),
        Expanded(child: _buildList()),
      ],
    );
  }

  Widget _buildMessageState({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool showRetry,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: context.textTertiary),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'ProductSans',
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: context.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'ProductSans',
                fontSize: 14,
                color: context.textSecondary,
              ),
            ),
            if (showRetry) ...[
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _authenticate,
                style: FilledButton.styleFrom(
                  backgroundColor: context.accentColor,
                ),
                child: Text(
                  'Retry',
                  style: TextStyle(
                    fontFamily: 'ProductSans',
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: TextField(
        controller: _searchController,
        onChanged: _filterEntries,
        style: TextStyle(
          fontFamily: 'ProductSans',
          fontSize: 15,
          color: context.textPrimary,
        ),
        decoration: InputDecoration(
          hintText: 'Search passwords...',
          hintStyle: TextStyle(
            fontFamily: 'ProductSans',
            fontSize: 15,
            color: context.textTertiary,
          ),
          prefixIcon: Icon(Icons.search, color: context.textTertiary, size: 20),
          filled: true,
          fillColor: context.surfaceColor,
          isDense: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: context.borderColor),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: context.borderColor),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: context.accentColor),
          ),
        ),
      ),
    );
  }

  Widget _buildList() {
    if (_filteredEntries.isEmpty) {
      return Center(
        child: Text(
          'No matches',
          style: TextStyle(
            fontFamily: 'ProductSans',
            fontSize: 14,
            color: context.textTertiary,
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      itemCount: _filteredEntries.length,
      itemBuilder: (context, index) {
        final entry = _filteredEntries[index];
        return _buildEntryTile(entry);
      },
    );
  }

  Widget _buildEntryTile(PasswordEntry entry) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.borderColor),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Icon(
          entry.isFavorite ? Icons.star : Icons.lock_outline,
          color: entry.isFavorite ? context.accentColor : context.textTertiary,
          size: 22,
        ),
        title: Text(
          entry.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: 'ProductSans',
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: context.textPrimary,
          ),
        ),
        subtitle: entry.tags.isNotEmpty
            ? Text(
                entry.tags.join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'ProductSans',
                  fontSize: 12,
                  color: context.textTertiary,
                ),
              )
            : null,
        trailing: Icon(
          Icons.chevron_right,
          color: context.textTertiary,
          size: 20,
        ),
        onTap: () => _selectEntry(entry),
      ),
    );
  }
}
