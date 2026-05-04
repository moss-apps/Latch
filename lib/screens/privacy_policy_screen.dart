import 'package:flutter/material.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor(context),
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: _textPrimary(context)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Privacy Policy',
          style: TextStyle(
            fontFamily: 'ProductSans',
            color: _textPrimary(context),
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          _buildLastUpdated(context),
          const SizedBox(height: 20),
          _buildSection(context, 'Our Commitment',
              'Locker is built with privacy as its core principle. We believe your personal data should stay on your device, not on our servers. This app does not collect, store, transmit, or share any personal information.'),
          const SizedBox(height: 20),
          _buildSection(context, 'Data We Do Not Collect',
              'Locker does not collect any data whatsoever. Specifically:\n\n'
              '• No personal information (name, email, phone number, etc.)\n'
              '• No usage analytics or telemetry\n'
              '• No crash reports or diagnostics sent externally\n'
              '• No advertising identifiers or tracking data\n'
              '• No location data\n'
              '• No device identifiers\n'
              '• No contacts, messages, or call logs\n'
              '• No browsing history or app usage data\n\n'
              'Everything you do in Locker stays on your device.'),
          const SizedBox(height: 20),
          _buildSection(context, 'Camera Access',
              'Locker may request camera permission only when you choose to scan a QR code or take a photo to import into your vault. The camera is used solely for these purposes:\n\n'
              '• QR code scanning for quick vault access\n'
              '• Capturing photos to store in your vault\n\n'
              'Camera access is never used in the background. No photos or video from your camera are transmitted to any server. All captured media is stored locally and encrypted on your device.'),
          const SizedBox(height: 20),
          _buildSection(context, 'Media & Files',
              'Locker is a secure media vault. Files you import into Locker are encrypted using AES-256 encryption and stored locally on your device. We do not:\n\n'
              '• Upload your files to any cloud or server\n'
              '• Scan or analyze your files\n'
              '• Share your files with any third party\n'
              '• Access your files without your explicit action\n\n'
              'Your vault key never leaves your device.'),
          const SizedBox(height: 20),
          _buildSection(context, 'Storage Permission',
              'Locker requires storage permission to read files you want to vault and to save encrypted files to your device. This permission is used only when you explicitly choose to import or export files.'),
          const SizedBox(height: 20),
          _buildSection(context, 'Biometric Authentication',
              'If you choose to use fingerprint or face unlock, biometric data is handled entirely by your device operating system. Locker only receives a success or failure signal — it never stores or accesses your biometric data.'),
          const SizedBox(height: 20),
          _buildSection(context, 'Third-Party Services',
              'Locker does not integrate with any third-party analytics, advertising, or tracking services. The only external connection is:\n\n'
              '• Play Store update check (optional, triggered by you)\n'
              '• Donation link to Ko-fi (optional, opened in your browser)\n\n'
              'Neither of these transmits any personal data from Locker.'),
          const SizedBox(height: 20),
          _buildSection(context, 'Local Backups',
              'If you choose to create a local backup, the backup file is saved to a location you select on your device. Locker does not upload backups anywhere. You are responsible for securing your backup files.'),
          const SizedBox(height: 20),
          _buildSection(context, 'Children\'s Privacy',
              'Locker does not knowingly collect any information from anyone, including children under 13. Since no data is collected at all, there is no risk of personal information being gathered from minors.'),
          const SizedBox(height: 20),
          _buildSection(context, 'Changes to This Policy',
              'If we update this Privacy Policy, the changes will be reflected in the app. We encourage you to review this policy periodically.'),
          const SizedBox(height: 20),
          _buildSection(context, 'Contact',
              'If you have any questions about this Privacy Policy, please reach out through the project repository.'),
        ],
      ),
    );
  }

  Widget _buildSection(
      BuildContext context, String title, String content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontFamily: 'ProductSans',
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: _textPrimary(context),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          content,
          style: TextStyle(
            fontFamily: 'ProductSans',
            fontSize: 14,
            color: _textSecondary(context),
            height: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _buildLastUpdated(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _accentColor(context).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _accentColor(context).withValues(alpha: 0.18),
        ),
      ),
      child: Text(
        'Last updated: May 4, 2026',
        style: TextStyle(
          fontFamily: 'ProductSans',
          fontSize: 12,
          color: _accentColor(context),
        ),
      ),
    );
  }

  Color _backgroundColor(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return brightness == Brightness.dark
        ? const Color(0xFF121212)
        : const Color(0xFFFFFFFF);
  }

  Color _textPrimary(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return brightness == Brightness.dark
        ? const Color(0xFFE5E5E5)
        : const Color(0xFF1A1A1A);
  }

  Color _textSecondary(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return brightness == Brightness.dark
        ? const Color(0xFFA0A0A0)
        : const Color(0xFF555555);
  }

  Color _accentColor(BuildContext context) {
    return Theme.of(context).colorScheme.primary;
  }
}
