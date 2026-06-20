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

  bool _isSaving = false;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _isFavorite = false;
  List<String> _tags = [];
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
      final content = await ref
          .read(passwordServiceProvider)
          .decryptContent(widget.entry!);
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
    super.dispose();
  }

  void _addTag() {
    final tag = _tagController.text.trim().toLowerCase();
    if (tag.isNotEmpty && !_tags.contains(tag)) {
      setState(() {
        _tags.add(tag);
        _tagController.clear();
      });
    }
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
      ToastUtils.showError('Title cannot be empty');
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
        await notifier.createPassword(
          title: _titleController.text.trim(),
          content: content,
          tags: _tags,
          encryptionAlgorithm: _algorithm,
          kdfIterations: _kdfIterations,
        );
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
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          isEditing ? 'Edit Entry' : 'New Entry',
          style: TextStyle(
            fontFamily: 'ProductSans',
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: context.textPrimary,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _isFavorite ? Icons.star : Icons.star_border,
              color: _isFavorite
                  ? context.accentColor
                  : context.textSecondary,
            ),
            onPressed: () => setState(() => _isFavorite = !_isFavorite),
            tooltip: 'Favorite',
          ),
          IconButton(
            icon: Icon(Icons.check, color: context.accentColor),
            onPressed: _isSaving ? null : _save,
          ),
        ],
      ),
      body: Stack(
        children: [
          _buildForm(),
          if (_isLoading || _isSaving) _buildLoadingOverlay(),
        ],
      ),
    );
  }

  Widget _buildForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTitleField(),
          const SizedBox(height: 16),
          _buildField(
            controller: _usernameController,
            label: 'Username',
            icon: Icons.person_outline,
            suffix: _usernameController.text.isNotEmpty
                ? IconButton(
                    icon: Icon(Icons.copy, size: 18, color: context.textTertiary),
                    onPressed: () =>
                        _copyField(_usernameController.text, 'Username'),
                  )
                : null,
          ),
          const SizedBox(height: 16),
          _buildPasswordField(),
          const SizedBox(height: 16),
          _buildField(
            controller: _urlController,
            label: 'URL',
            icon: Icons.link,
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 16),
          _buildField(
            controller: _notesController,
            label: 'Notes',
            icon: Icons.note_outlined,
            maxLines: 3,
          ),
          const SizedBox(height: 16),
          _buildTagsSection(),
          if (!isEditing) ...[
            const SizedBox(height: 16),
            _buildAlgorithmSection(),
            const SizedBox(height: 16),
            _buildKdfSection(),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  bool get isEditing => widget.entry != null;

  Widget _buildTitleField() {
    return TextField(
      controller: _titleController,
      style: TextStyle(
        fontFamily: 'ProductSans',
        fontSize: 22,
        fontWeight: FontWeight.w600,
        color: context.textPrimary,
      ),
      decoration: InputDecoration(
        hintText: 'Title',
        hintStyle: TextStyle(
          fontFamily: 'ProductSans',
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: context.textTertiary,
        ),
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    int maxLines = 1,
    Widget? suffix,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      style: TextStyle(
        fontFamily: 'ProductSans',
        fontSize: 15,
        color: context.textPrimary,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
          fontFamily: 'ProductSans',
          fontSize: 14,
          color: context.textTertiary,
        ),
        prefixIcon: Icon(icon, color: context.textTertiary, size: 20),
        suffixIcon: suffix,
        filled: true,
        fillColor: context.surfaceColor,
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
          borderSide: BorderSide(color: context.accentColor, width: 2),
        ),
      ),
    );
  }

  Widget _buildPasswordField() {
    return TextField(
      controller: _passwordController,
      obscureText: _obscurePassword,
      style: TextStyle(
        fontFamily: 'ProductSans',
        fontSize: 15,
        color: context.textPrimary,
      ),
      decoration: InputDecoration(
        labelText: 'Password',
        labelStyle: TextStyle(
          fontFamily: 'ProductSans',
          fontSize: 14,
          color: context.textTertiary,
        ),
        prefixIcon:
            Icon(Icons.lock_outline, color: context.textTertiary, size: 20),
        suffixIcon: Row(
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
            ),
            IconButton(
              icon: Icon(Icons.auto_awesome, size: 18, color: context.accentColor),
              onPressed: _showGenerator,
              tooltip: 'Generate',
            ),
            if (_passwordController.text.isNotEmpty)
              IconButton(
                icon: Icon(Icons.copy, size: 18, color: context.textTertiary),
                onPressed: () =>
                    _copyField(_passwordController.text, 'Password'),
              ),
          ],
        ),
        filled: true,
        fillColor: context.surfaceColor,
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
          borderSide: BorderSide(color: context.accentColor, width: 2),
        ),
      ),
    );
  }

  Widget _buildTagsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Tags',
          style: TextStyle(
            fontFamily: 'ProductSans',
            fontSize: 14,
            color: context.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        if (_tags.isNotEmpty)
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _tags.map((tag) {
              return Chip(
                label: Text(
                  tag,
                  style: TextStyle(
                    fontFamily: 'ProductSans',
                    fontSize: 12,
                    color: context.accentColor,
                  ),
                ),
                backgroundColor: context.accentColor.withValues(alpha: 0.12),
                side: BorderSide.none,
                deleteIcon: Icon(Icons.close, size: 14, color: context.textTertiary),
                onDeleted: () => setState(() => _tags.remove(tag)),
              );
            }).toList(),
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _tagController,
                style: TextStyle(
                  fontFamily: 'ProductSans',
                  fontSize: 14,
                  color: context.textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: 'Add tag...',
                  hintStyle: TextStyle(
                    fontFamily: 'ProductSans',
                    fontSize: 14,
                    color: context.textTertiary,
                  ),
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
                onSubmitted: (_) => _addTag(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: Icon(Icons.add, color: context.accentColor),
              onPressed: _addTag,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAlgorithmSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Encryption',
          style: TextStyle(
            fontFamily: 'ProductSans',
            fontSize: 14,
            color: context.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: EncryptionAlgorithm.values.map((alg) {
            final selected = _algorithm == alg;
            return ChoiceChip(
              label: Text(alg.displayName),
              selected: selected,
              selectedColor: context.accentColor.withValues(alpha: 0.2),
              labelStyle: TextStyle(
                fontFamily: 'ProductSans',
                fontSize: 13,
                color: selected ? context.accentColor : context.textSecondary,
              ),
              side: BorderSide(
                color: selected ? context.accentColor : context.borderColor,
              ),
              onSelected: (_) => setState(() => _algorithm = alg),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildKdfSection() {
    const options = [100000, 200000, 500000];
    const labels = ['100K', '200K', '500K'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Key Derivation Iterations',
          style: TextStyle(
            fontFamily: 'ProductSans',
            fontSize: 14,
            color: context.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: List.generate(options.length, (i) {
            final selected = _kdfIterations == options[i];
            return ChoiceChip(
              label: Text(labels[i]),
              selected: selected,
              selectedColor: context.accentColor.withValues(alpha: 0.2),
              labelStyle: TextStyle(
                fontFamily: 'ProductSans',
                fontSize: 13,
                color: selected ? context.accentColor : context.textSecondary,
              ),
              side: BorderSide(
                color: selected ? context.accentColor : context.borderColor,
              ),
              onSelected: (_) => setState(() => _kdfIterations = options[i]),
            );
          }),
        ),
      ],
    );
  }

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
