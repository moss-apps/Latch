import 'package:flutter/material.dart';

import '../models/encryption_algorithm.dart';
import '../models/note.dart';
import '../themes/app_colors.dart';

class NoteSaveOptions {
  const NoteSaveOptions({
    this.format = NoteFileFormat.plainText,
    this.encrypt = false,
    this.algorithm = EncryptionAlgorithm.aes256Gcm,
    this.kdfIterations = 100000,
  });

  final NoteFileFormat format;
  final bool encrypt;
  final EncryptionAlgorithm algorithm;
  final int kdfIterations;
}

class NoteSaveOptionsSheet extends StatefulWidget {
  const NoteSaveOptionsSheet({
    super.key,
    required this.initialOptions,
    this.existingNote,
    this.resolveExistingFormat,
  });

  final NoteSaveOptions initialOptions;
  final Note? existingNote;
  final Future<NoteFileFormat> Function()? resolveExistingFormat;

  @override
  State<NoteSaveOptionsSheet> createState() => _NoteSaveOptionsSheetState();
}

class _NoteSaveOptionsSheetState extends State<NoteSaveOptionsSheet> {
  static const _iterationOptions = [100000, 200000, 500000];
  late NoteFileFormat _format = widget.initialOptions.format;
  late bool _encrypt = widget.initialOptions.encrypt;
  late EncryptionAlgorithm _algorithm = widget.initialOptions.algorithm;
  late int _iterations = widget.initialOptions.kdfIterations;
  late final _existingFormat = widget.resolveExistingFormat?.call();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final note = widget.existingNote;
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: MediaQuery.sizeOf(context).height * 0.78,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Save options', style: theme.titleLarge),
              const SizedBox(height: 16),
              if (note != null)
                _buildSavedSettings(context, note)
              else ...[
                Text('File format', style: theme.titleSmall),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final format in NoteFileFormat.values)
                      _OptionChip(
                        label: '${format.label} (.${format.extension})',
                        selected: _format == format,
                        onSelected: () => setState(() => _format = format),
                      ),
                  ],
                ),
                if (_format == NoteFileFormat.html)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: _description('Saves what you type as HTML source.'),
                  ),
                const SizedBox(height: 8),
                const Divider(),
                SwitchListTile(
                  title: const Text('Encrypt note'),
                  subtitle: const Text(
                    'Encrypts the note body. The title stays searchable.',
                  ),
                  contentPadding: EdgeInsets.zero,
                  value: _encrypt,
                  onChanged: (value) => setState(() => _encrypt = value),
                ),
                if (_encrypt) _buildAdvancedOptions(context),
              ],
              const SizedBox(height: 16),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: FilledButton(
                  onPressed: note == null
                      ? () => Navigator.pop(
                            context,
                            NoteSaveOptions(
                              format: _format,
                              encrypt: _encrypt,
                              algorithm: _algorithm,
                              kdfIterations: _iterations,
                            ),
                          )
                      : () => Navigator.pop(context),
                  child: Text(note == null ? 'Apply options' : 'Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSavedSettings(BuildContext context, Note note) {
    final theme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('File format', style: theme.titleSmall),
        const SizedBox(height: 4),
        FutureBuilder<NoteFileFormat>(
          future: _existingFormat,
          initialData: note.fileFormat,
          builder: (context, snapshot) {
            final format = snapshot.data;
            return _description(
              format != null
                  ? '${format.label} (.${format.extension})'
                  : snapshot.hasError
                      ? 'Could not read the saved format'
                      : 'Checking saved format…',
            );
          },
        ),
        const SizedBox(height: 12),
        Text('Encryption', style: theme.titleSmall),
        const SizedBox(height: 4),
        _description(
          note.isEncrypted
              ? '${note.encryptionAlgorithm.displayName} · '
                  '${note.kdfIterations} KDF iterations'
              : 'Not encrypted',
        ),
        const SizedBox(height: 12),
        _description('Editing this note keeps its format and encryption.'),
      ],
    );
  }

  Widget _buildAdvancedOptions(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return ExpansionTile(
      title: const Text('Advanced encryption'),
      tilePadding: EdgeInsets.zero,
      // ExpansionTile draws divider-colored borders above and below the
      // expanded body by default; keep the sheet to a single separator.
      shape: const Border(),
      collapsedShape: const Border(),
      childrenPadding: const EdgeInsets.only(top: 4, bottom: 4),
      expandedAlignment: AlignmentDirectional.centerStart,
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Algorithm', style: theme.titleSmall),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final algorithm in EncryptionAlgorithm.values.reversed)
              _OptionChip(
                label: algorithm.displayName,
                selected: _algorithm == algorithm,
                onSelected: () => setState(() => _algorithm = algorithm),
              ),
          ],
        ),
        _description(_algorithm.description),
        const SizedBox(height: 12),
        Text('KDF iterations', style: theme.titleSmall),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final iterations in _iterationOptions)
              _OptionChip(
                label: '${iterations ~/ 1000}K',
                selected: _iterations == iterations,
                onSelected: () => setState(() => _iterations = iterations),
              ),
          ],
        ),
      ],
    );
  }

  Widget _description(String text) => Text(
        text,
        style: Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(color: context.textSecondary),
      );
}

/// A single-choice chip whose checkmark only occupies space when selected.
class _OptionChip extends StatelessWidget {
  const _OptionChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final accent = context.accentColor;
    return ChoiceChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (selected) ...[
            Icon(Icons.check, size: 16, color: accent),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      showCheckmark: false,
      selected: selected,
      onSelected: (_) => onSelected(),
      backgroundColor: Colors.transparent,
      selectedColor: accent.withValues(alpha: 0.18),
      surfaceTintColor: Colors.transparent,
      side: BorderSide(
        color: selected ? accent : context.borderColor,
        // Keep the width fixed so the chip does not resize when selected.
        width: 1.2,
      ),
      labelStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: selected ? accent : context.textSecondary,
          ),
      checkmarkColor: accent,
    );
  }
}
