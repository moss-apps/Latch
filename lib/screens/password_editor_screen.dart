import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/password_entry.dart';
import '../models/encryption_algorithm.dart';
import '../providers/password_providers.dart';
import '../themes/app_colors.dart';
import '../utils/clipboard_util.dart';
import '../utils/toast_utils.dart';
import '../widgets/password_generator_sheet.dart';

class PasswordEditorScreen extends ConsumerStatefulWidget {
  final PasswordEntry? entry;

  const PasswordEditorScreen({super.key, this.entry});

  @override
  ConsumerState<PasswordEditorScreen> createState() =>
      _PasswordEditorScreenState();
}

class _PasswordEditorScreenState extends ConsumerState<PasswordEditorScreen> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _tagController = TextEditingController();
  final FocusNode _titleFocus = FocusNode();
  final FocusNode _tagFocus = FocusNode();

  bool _isSaving = false;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _isFavorite = false;
  bool _showTagInput = false;
  List<String> _tags = [];
  String? _titleError;
  EncryptionAlgorithm _algorithm = EncryptionAlgorithm.aes256Gcm;
  int _kdfIterations = 100000;

  @override
  void initState() {
    super.initState();
    if (widget.entry != null) {
      _isLoading = true;
      _titleController.text = widget.entry!.title;
      _tags = List.from(widget.entry!.tags);
      _isFavorite = widget.entry!.isFavorite;
      _algorithm = widget.entry!.encryptionAlgorithm;
      _kdfIterations = widget.entry!.kdfIterations;
      _loadContent();
    }
  }

  Future<void> _loadContent() async {
    if (widget.entry == null) return;
    try {
      final content =
          await ref.read(passwordServiceProvider).decryptContent(widget.entry!);
      if (mounted) {
        setState(() {
          _usernameController.text = content.username;
          _passwordController.text = content.password;
          _urlController.text = content.url;
          _notesController.text = content.notes;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ToastUtils.showError('Failed to load entry');
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _urlController.dispose();
    _notesController.dispose();
    _tagController.dispose();
    _titleFocus.dispose();
    _tagFocus.dispose();
    super.dispose();
  }

  void _addTag() {
    final tag = _tagController.text.trim().toLowerCase();
    if (tag.isEmpty) {
      setState(() => _showTagInput = false);
      return;
    }

    setState(() {
      if (!_tags.contains(tag)) {
        _tags.add(tag);
      }
      _tagController.clear();
      _showTagInput = false;
    });
    FocusScope.of(context).unfocus();
  }

  void _cancelTagInput() {
    setState(() {
      _tagController.clear();
      _showTagInput = false;
    });
    FocusScope.of(context).unfocus();
  }

  void _showGenerator() {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.backgroundColor,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => PasswordGeneratorSheet(
        onGenerate: (password) {
          setState(() {
            _passwordController.text = password;
            _obscurePassword = false;
          });
        },
      ),
    );
  }

  void _copyField(String value, String label) {
    if (value.isEmpty) {
      ToastUtils.showInfo('$label is empty');
      return;
    }
    ClipboardUtil.copyWithAutoClear(value);
    ToastUtils.showSuccess('$label copied - clears in 20s');
  }

  Future<void> _save() async {
    if (_titleController.text.trim().isEmpty) {
      setState(() => _titleError = 'Entry name is required');
      _titleFocus.requestFocus();
      return;
    }

    setState(() => _isSaving = true);

    try {
      final content = PasswordContent(
        username: _usernameController.text,
        password: _passwordController.text,
        url: _urlController.text,
        notes: _notesController.text,
      );

      final notifier = ref.read(passwordsNotifierProvider.notifier);
      if (widget.entry != null) {
        await notifier.updatePassword(
          widget.entry!,
          title: _titleController.text.trim(),
          content: content,
          tags: _tags,
        );
        if (widget.entry!.isFavorite != _isFavorite) {
          await notifier.toggleFavorite(widget.entry!);
        }
        if (mounted) ToastUtils.showSuccess('Entry updated');
      } else {
        final created = await notifier.createPassword(
          title: _titleController.text.trim(),
          content: content,
          tags: _tags,
          encryptionAlgorithm: _algorithm,
          kdfIterations: _kdfIterations,
        );
        if (_isFavorite) {
          await notifier.toggleFavorite(created);
        }
        if (mounted) ToastUtils.showSuccess('Entry created');
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) ToastUtils.showError('Failed to save entry');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.entry != null;

    return Scaffold(
      backgroundColor: context.backgroundColor,
      appBar: AppBar(
        backgroundColor: context.backgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: context.textPrimary),
          tooltip: 'Back',
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          isEditing ? 'Edit Entry' : 'New Entry',
          style: TextStyle(
            fontFamily: 'GoogleSansFlex',
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: context.textPrimary,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _isFavorite ? Icons.star : Icons.star_border,
              color: _isFavorite ? context.accentColor : context.textSecondary,
              size: 22,
            ),
            onPressed: _isSaving || _isLoading
                ? null
                : () => setState(() => _isFavorite = !_isFavorite),
            tooltip: _isFavorite ? 'Remove from favorites' : 'Add to favorites',
          ),
          Padding(
            padding: const EdgeInsets.only(right: 6, left: 2),
            child: TextButton(
              onPressed: _isSaving || _isLoading ? null : _save,
              style: TextButton.styleFrom(
                foregroundColor: context.accentColor,
                minimumSize: const Size(64, 48),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              child: _isSaving
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: context.accentColor,
                      ),
                    )
                  : const Text(
                      'Save',
                      style: TextStyle(
                        fontFamily: 'GoogleSansFlex',
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          _buildForm(),
          if (_isLoading) _buildLoadingOverlay(),
        ],
      ),
    );
  }

  Widget _buildForm() {
    return AbsorbPointer(
      absorbing: _isSaving,
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildField(
                      controller: _titleController,
                      focusNode: _titleFocus,
                      label: 'Entry name',
                      icon: Icons.key_outlined,
                      textInputAction: TextInputAction.next,
                      errorText: _titleError,
                      onChanged: (value) {
                        if (_titleError != null && value.trim().isNotEmpty) {
                          setState(() => _titleError = null);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    _buildField(
                      controller: _usernameController,
                      label: 'Username',
                      icon: Icons.person_outline,
                      keyboardType: TextInputType.text,
                      textInputAction: TextInputAction.next,
                      autocorrect: false,
                      enableSuggestions: false,
                      autofillHints: [
                        isEditing
                            ? AutofillHints.username
                            : AutofillHints.newUsername,
                      ],
                      onChanged: (_) => setState(() {}),
                      suffix: _usernameController.text.isNotEmpty
                          ? IconButton(
                              icon: Icon(Icons.copy,
                                  size: 18, color: context.textTertiary),
                              onPressed: () => _copyField(
                                  _usernameController.text, 'Username'),
                              tooltip: 'Copy username',
                            )
                          : null,
                    ),
                    const SizedBox(height: 12),
                    _buildPasswordField(),
                    const SizedBox(height: 12),
                    _buildField(
                      controller: _urlController,
                      label: 'Website',
                      icon: Icons.link,
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.next,
                      autocorrect: false,
                      autofillHints: const [AutofillHints.url],
                    ),
                    const SizedBox(height: 12),
                    _buildField(
                      controller: _notesController,
                      label: 'Notes',
                      icon: Icons.notes_outlined,
                      keyboardType: TextInputType.multiline,
                      minLines: 1,
                      maxLines: 5,
                    ),
                    const SizedBox(height: 24),
                    _buildTagsSection(),
                    if (!isEditing) ...[
                      const SizedBox(height: 24),
                      _buildAdvancedSection(),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool get isEditing => widget.entry != null;

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    FocusNode? focusNode,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    int minLines = 1,
    int maxLines = 1,
    Widget? suffix,
    Iterable<String>? autofillHints,
    bool autocorrect = true,
    bool enableSuggestions = true,
    ValueChanged<String>? onChanged,
    String? errorText,
  }) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      minLines: minLines,
      maxLines: maxLines,
      autocorrect: autocorrect,
      enableSuggestions: enableSuggestions,
      autofillHints: autofillHints,
      onChanged: onChanged,
      cursorColor: context.accentColor,
      style: TextStyle(
        fontFamily: 'GoogleSansFlex',
        fontSize: 15,
        height: 1.3,
        color: context.textPrimary,
      ),
      decoration: _fieldDecoration(
        label: label,
        icon: icon,
        suffix: suffix,
        errorText: errorText,
      ),
    );
  }

  Widget _buildPasswordField() {
    return TextField(
      controller: _passwordController,
      obscureText: _obscurePassword,
      keyboardType: TextInputType.visiblePassword,
      textInputAction: TextInputAction.next,
      autocorrect: false,
      enableSuggestions: false,
      autofillHints: [
        isEditing ? AutofillHints.password : AutofillHints.newPassword
      ],
      onChanged: (_) => setState(() {}),
      cursorColor: context.accentColor,
      style: TextStyle(
        fontFamily: 'GoogleSansFlex',
        fontSize: 15,
        height: 1.3,
        color: context.textPrimary,
      ),
      decoration: _fieldDecoration(
        label: 'Password',
        icon: Icons.lock_outline,
        suffix: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(
                _obscurePassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                size: 18,
                color: context.textTertiary,
              ),
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
              tooltip: _obscurePassword ? 'Show password' : 'Hide password',
            ),
            IconButton(
              icon: Icon(Icons.auto_awesome,
                  size: 18, color: context.accentColor),
              onPressed: _showGenerator,
              tooltip: 'Generate password',
            ),
            if (_passwordController.text.isNotEmpty)
              IconButton(
                icon: Icon(Icons.copy, size: 18, color: context.textTertiary),
                onPressed: () =>
                    _copyField(_passwordController.text, 'Password'),
                tooltip: 'Copy password',
              ),
          ],
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration({
    required String label,
    required IconData icon,
    Widget? suffix,
    String? errorText,
  }) {
    final accent = context.accentColor;
    final error = Theme.of(context).colorScheme.error;

    OutlineInputBorder border(Color color, [double width = 1]) {
      return OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: color, width: width),
      );
    }

    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(
        fontFamily: 'GoogleSansFlex',
        fontSize: 14,
        color: context.textTertiary,
      ),
      floatingLabelStyle: TextStyle(
        fontFamily: 'GoogleSansFlex',
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: errorText != null ? error : accent,
      ),
      prefixIcon: Icon(icon, color: context.textTertiary, size: 20),
      suffixIcon: suffix,
      filled: true,
      fillColor: _fieldFillColor,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      errorText: errorText,
      errorStyle: TextStyle(
        fontFamily: 'GoogleSansFlex',
        fontSize: 12,
        color: error,
      ),
      border: border(context.borderColor),
      enabledBorder: border(context.borderColor),
      focusedBorder: border(accent, 1.5),
      errorBorder: border(error),
      focusedErrorBorder: border(error, 1.5),
    );
  }

  Color get _fieldFillColor =>
      context.isDarkMode ? context.surfaceColor : context.backgroundSecondary;

  Widget _buildTagsSection() {
    final accent = context.accentColor;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _sectionLabel('Tags'),
            const Spacer(),
            if (!_showTagInput)
              TextButton.icon(
                onPressed: () {
                  setState(() => _showTagInput = true);
                  _tagFocus.requestFocus();
                },
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add tag'),
                style: TextButton.styleFrom(
                  foregroundColor: accent,
                  minimumSize: const Size(0, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  textStyle: const TextStyle(
                    fontFamily: 'GoogleSansFlex',
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
          ],
        ),
        if (_tags.isNotEmpty) ...[
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _tags.map((tag) {
              return Chip(
                label: Text(
                  tag,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'GoogleSansFlex',
                    fontSize: 12,
                    color: accent,
                  ),
                ),
                backgroundColor: accent.withValues(alpha: 0.10),
                side: BorderSide(color: accent.withValues(alpha: 0.22)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                deleteIcon: Icon(Icons.close,
                    size: 14, color: accent.withValues(alpha: 0.8)),
                deleteButtonTooltipMessage: 'Remove $tag',
                onDeleted: () => setState(() => _tags.remove(tag)),
              );
            }).toList(),
          ),
        ],
        if (_showTagInput) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _tagController,
                  focusNode: _tagFocus,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _addTag(),
                  cursorColor: accent,
                  style: TextStyle(
                    fontFamily: 'GoogleSansFlex',
                    fontSize: 14,
                    color: context.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Tag name',
                    hintStyle: TextStyle(
                      fontFamily: 'GoogleSansFlex',
                      fontSize: 14,
                      color: context.textTertiary,
                    ),
                    isDense: true,
                    filled: true,
                    fillColor: _fieldFillColor,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    prefixIcon: Icon(Icons.label_outline,
                        color: context.textTertiary, size: 18),
                    suffixIcon: IconButton(
                      icon: Icon(Icons.check, size: 18, color: accent),
                      onPressed: _addTag,
                      tooltip: 'Add tag',
                    ),
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
                      borderSide: BorderSide(color: accent, width: 1.5),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: Icon(Icons.close, size: 20, color: context.textSecondary),
                onPressed: _cancelTagInput,
                tooltip: 'Cancel tag',
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildAdvancedSection() {
    final summary =
        '${_algorithm.displayName} · ${_kdfIterations ~/ 1000}K iterations';

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.borderColor),
      ),
      child: ExpansionTile(
        title: Text(
          'Encryption',
          style: TextStyle(
            fontFamily: 'GoogleSansFlex',
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: context.textPrimary,
          ),
        ),
        subtitle: Text(
          summary,
          style: TextStyle(
            fontFamily: 'GoogleSansFlex',
            fontSize: 12,
            color: context.textTertiary,
          ),
        ),
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: context.accentColor.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.shield_outlined,
            size: 18,
            color: context.accentColor,
          ),
        ),
        tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        shape: const Border(),
        collapsedShape: const Border(),
        iconColor: context.accentColor,
        collapsedIconColor: context.textTertiary,
        textColor: context.textPrimary,
        collapsedTextColor: context.textPrimary,
        expandedAlignment: Alignment.centerLeft,
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        // Encryption choices only apply when the entry is first created.
        children: [
          _sectionLabel('Algorithm'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: EncryptionAlgorithm.values.map((algorithm) {
              return _buildChoiceChip(
                label: algorithm.displayName,
                selected: _algorithm == algorithm,
                onSelected: () => setState(() => _algorithm = algorithm),
              );
            }).toList(),
          ),
          const SizedBox(height: 6),
          Text(_algorithm.description, style: _helperTextStyle),
          const SizedBox(height: 18),
          _sectionLabel('Key derivation iterations'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [100000, 200000, 500000].map((iterations) {
              return _buildChoiceChip(
                label: '${iterations ~/ 1000}K',
                selected: _kdfIterations == iterations,
                onSelected: () => setState(() => _kdfIterations = iterations),
              );
            }).toList(),
          ),
          const SizedBox(height: 6),
          Text(
            'Higher values make guessing slower but add a short unlock delay.',
            style: _helperTextStyle,
          ),
        ],
      ),
    );
  }

  Widget _buildChoiceChip({
    required String label,
    required bool selected,
    required VoidCallback onSelected,
  }) {
    final accent = context.accentColor;

    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
      showCheckmark: true,
      checkmarkColor: accent,
      selectedColor: accent.withValues(alpha: 0.16),
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      side: BorderSide(
        color: selected ? accent : context.borderColor,
        width: 1.2,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(9),
      ),
      labelStyle: TextStyle(
        fontFamily: 'GoogleSansFlex',
        fontSize: 13,
        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
        color: selected ? accent : context.textSecondary,
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: TextStyle(
        fontFamily: 'GoogleSansFlex',
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
        color: context.textSecondary,
      ),
    );
  }

  TextStyle get _helperTextStyle => TextStyle(
        fontFamily: 'GoogleSansFlex',
        fontSize: 12,
        height: 1.4,
        color: context.textTertiary,
      );

  Widget _buildLoadingOverlay() {
    return Positioned.fill(
      child: Container(
        color: context.backgroundColor.withValues(alpha: 0.7),
        child: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation(context.accentColor),
          ),
        ),
      ),
    );
  }
}
