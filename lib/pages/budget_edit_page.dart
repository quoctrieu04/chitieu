import 'dart:convert';
import 'package:chitieu/utils/safe_ui.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:chitieu/l10n/app_localizations.dart';
import 'package:chitieu/api/category/category_model.dart';
import 'package:chitieu/api/category/category_provider.dart';
import 'package:chitieu/auth/auth_provider.dart';

class BudgetEditPage extends StatefulWidget {
  /// null = tạo mới, khác null = sửa
  final Category? category;

  const BudgetEditPage({super.key, this.category});

  @override
  State<BudgetEditPage> createState() => _BudgetEditPageState();
}

class _BudgetEditPageState extends State<BudgetEditPage> {
  final _formKey = GlobalKey<FormState>();
  final _controller = TextEditingController();
  final _nameFocus = FocusNode();

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Nếu là sửa thì nạp sẵn tên cũ
    if (widget.category != null) {
      _controller.text = widget.category!.name;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _nameFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final t = AppLocalizations.of(context)!;

    if (_saving) return;
    final auth = context.read<AuthProvider>();
    if (!auth.isAuthenticated) {
      safeShowSnackBar(
        context,
        SnackBar(content: Text(t.loginRequiredMessage)),
      );
      return;
    }

    if (!(_formKey.currentState?.validate() ?? false)) {
      _nameFocus.requestFocus();
      return;
    }

    setState(() => _saving = true);
    try {
      final name = _controller.text.trim();
      final provider = context.read<CategoryProvider>();

      if (widget.category == null) {
        // === CREATE ===
        await provider.create(name);
      } else {
        // === UPDATE ===
        await provider.update(id: widget.category!.id, name: name);
      }

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      String msg = e.toString();
      // bóc lỗi JSON nếu backend trả về JSON
      try {
        final jsonStart = msg.indexOf('{');
        if (jsonStart != -1) {
          final map =
              jsonDecode(msg.substring(jsonStart)) as Map<String, dynamic>;
          msg = (map['message'] as String?) ??
              (map['errors']?.toString() ?? e.toString());
        }
      } catch (_) {}
      safeShowSnackBar(
        context,
        SnackBar(content: Text('${t.genericFailedMessage}: $msg')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmAndDelete() async {
    if (widget.category == null) return; // đang tạo mới thì không xoá
    final cat = widget.category!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Xác nhận'),
        content: Text('Bạn có chắc muốn xoá danh mục "${cat.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xoá'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _saving = true);
    try {
      await context.read<CategoryProvider>().delete(id: cat.id);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      final t = AppLocalizations.of(context)!;
      safeShowSnackBar(
        context,
        SnackBar(content: Text('${t.genericFailedMessage}: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final isEdit = widget.category != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? t.editCategoryTitle : t.createCategoryTitleForm),
        actions: [
          if (isEdit)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Xoá',
              onPressed: _saving ? null : _confirmAndDelete,
            ),
          IconButton(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.check),
            tooltip: t.saveCta,
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: Column(
              children: [
                TextFormField(
                  controller: _controller,
                  focusNode: _nameFocus,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _save(),
                  decoration: InputDecoration(
                    labelText: t.categoryNameLabel,
                    hintText: t.categoryNameHint,
                    filled: true,
                    border: const OutlineInputBorder(),
                    counterText: '',
                  ),
                  maxLength: 50,
                  enabled: !_saving,
                  validator: (value) {
                    final name = (value ?? '').trim();
                    if (name.isEmpty) return t.categoryNameRequired;
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      transitionBuilder: (child, anim) =>
                          FadeTransition(opacity: anim, child: child),
                      child: _saving
                          ? const SizedBox(
                              key: ValueKey('spinner'),
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              isEdit ? t.updateCta : t.saveCta,
                              key: const ValueKey('label'),
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
