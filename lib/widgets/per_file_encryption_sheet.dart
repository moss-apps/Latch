import 'package:flutter/material.dart';
import '../models/encryption_algorithm.dart';
import '../themes/app_colors.dart';

class PerFileEncryptionSettings {
  final String fileName;
  final String filePath;
  final int fileSize;
  bool encrypt;
  EncryptionAlgorithm algorithm;

  PerFileEncryptionSettings({
    required this.fileName,
    required this.filePath,
    required this.fileSize,
    this.encrypt = true,
    this.algorithm = EncryptionAlgorithm.aes256Ctr,
  });
}

class PerFileEncryptionSheet extends StatefulWidget {
  final List<PerFileEncryptionSettings> files;
  final bool encryptionEnabled;
  final EncryptionAlgorithm defaultAlgorithm;

  const PerFileEncryptionSheet({
    super.key,
    required this.files,
    required this.encryptionEnabled,
    required this.defaultAlgorithm,
  });

  static Future<List<PerFileEncryptionSettings>?> show(
    BuildContext context, {
    required List<PerFileEncryptionSettings> files,
    required bool encryptionEnabled,
    required EncryptionAlgorithm defaultAlgorithm,
  }) {
    return showModalBottomSheet<List<PerFileEncryptionSettings>>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => PerFileEncryptionSheet(
          files: files,
          encryptionEnabled: encryptionEnabled,
          defaultAlgorithm: defaultAlgorithm,
        ),
      ),
    );
  }

  @override
  State<PerFileEncryptionSheet> createState() => _PerFileEncryptionSheetState();
}

class _PerFileEncryptionSheetState extends State<PerFileEncryptionSheet> {
  late List<PerFileEncryptionSettings> _files;
  late bool _globalEncrypt;
  late EncryptionAlgorithm _globalAlgorithm;

  @override
  void initState() {
    super.initState();
    _files = widget.files;
    _globalEncrypt = widget.encryptionEnabled;
    _globalAlgorithm = widget.defaultAlgorithm;
    for (final file in _files) {
      file.encrypt = _globalEncrypt;
      file.algorithm = _globalAlgorithm;
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: context.dividerColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Encryption Settings',
                    style: TextStyle(
                      fontFamily: 'ProductSans',
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: context.textPrimary,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                      fontFamily: 'ProductSans',
                      color: context.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => Navigator.pop(context, _files),
                  style: FilledButton.styleFrom(
                    backgroundColor: context.accentColor,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text(
                    'Confirm',
                    style: TextStyle(fontFamily: 'ProductSans'),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildGlobalToggle(),
                const SizedBox(height: 12),
                if (_globalEncrypt) _buildGlobalAlgorithm(),
                const SizedBox(height: 8),
                Text(
                  '${_files.length} file(s) selected',
                  style: TextStyle(
                    fontFamily: 'ProductSans',
                    fontSize: 12,
                    color: context.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 24),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: _files.length,
              itemBuilder: (context, index) => _buildFileItem(index),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlobalToggle() {
    return Row(
      children: [
        Icon(Icons.lock_outline, size: 20, color: context.textSecondary),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'Encrypt all files',
            style: TextStyle(
              fontFamily: 'ProductSans',
              fontSize: 16,
              color: context.textPrimary,
            ),
          ),
        ),
        Switch(
          value: _globalEncrypt,
          onChanged: (value) {
            setState(() {
              _globalEncrypt = value;
              for (final file in _files) {
                file.encrypt = value;
              }
            });
          },
          activeTrackColor: context.accentColor,
        ),
      ],
    );
  }

  Widget _buildGlobalAlgorithm() {
    return Row(
      children: [
        const SizedBox(width: 32),
        Expanded(
          child: Text(
            'Algorithm',
            style: TextStyle(
              fontFamily: 'ProductSans',
              fontSize: 14,
              color: context.textSecondary,
            ),
          ),
        ),
        DropdownButton<EncryptionAlgorithm>(
          value: _globalAlgorithm,
          underline: const SizedBox(),
          items: EncryptionAlgorithm.values.map((algo) {
            return DropdownMenuItem(
              value: algo,
              child: Text(
                algo == EncryptionAlgorithm.aes256Ctr ? 'AES-CTR' : 'AES-GCM',
                style: TextStyle(
                  fontFamily: 'ProductSans',
                  fontSize: 14,
                  color: context.textPrimary,
                ),
              ),
            );
          }).toList(),
          onChanged: (value) {
            if (value != null) {
              setState(() {
                _globalAlgorithm = value;
                for (final file in _files) {
                  file.algorithm = value;
                }
              });
            }
          },
        ),
      ],
    );
  }

  Widget _buildFileItem(int index) {
    final file = _files[index];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.surfaceColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.dividerColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        file.fileName,
                        style: TextStyle(
                          fontFamily: 'ProductSans',
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: context.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          if (file.fileSize > 50 * 1024 * 1024) ...[
                            Icon(Icons.warning_amber, size: 14, color: Colors.orange),
                            const SizedBox(width: 4),
                          ],
                          Text(
                            _formatSize(file.fileSize),
                            style: TextStyle(
                              fontFamily: 'ProductSans',
                              fontSize: 12,
                              color: context.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: file.encrypt,
                  onChanged: _globalEncrypt
                      ? null
                      : (value) {
                          setState(() {
                            file.encrypt = value;
                          });
                        },
                  activeTrackColor: context.accentColor,
                ),
              ],
            ),
            if (file.encrypt)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Text(
                      'Algorithm: ',
                      style: TextStyle(
                        fontFamily: 'ProductSans',
                        fontSize: 12,
                        color: context.textSecondary,
                      ),
                    ),
                    ChoiceChip(
                      label: const Text(
                        'CTR',
                        style: TextStyle(fontFamily: 'ProductSans', fontSize: 11),
                      ),
                      selected: file.algorithm == EncryptionAlgorithm.aes256Ctr,
                      onSelected: (selected) {
                        if (selected) {
                          setState(() {
                            file.algorithm = EncryptionAlgorithm.aes256Ctr;
                          });
                        }
                      },
                      selectedColor: context.accentColor.withValues(alpha: 0.2),
                      labelStyle: TextStyle(
                        color: file.algorithm == EncryptionAlgorithm.aes256Ctr
                            ? context.accentColor
                            : context.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 4),
                    ChoiceChip(
                      label: const Text(
                        'GCM',
                        style: TextStyle(fontFamily: 'ProductSans', fontSize: 11),
                      ),
                      selected: file.algorithm == EncryptionAlgorithm.aes256Gcm,
                      onSelected: (selected) {
                        if (selected) {
                          setState(() {
                            file.algorithm = EncryptionAlgorithm.aes256Gcm;
                          });
                        }
                      },
                      selectedColor: context.accentColor.withValues(alpha: 0.2),
                      labelStyle: TextStyle(
                        color: file.algorithm == EncryptionAlgorithm.aes256Gcm
                            ? context.accentColor
                            : context.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
