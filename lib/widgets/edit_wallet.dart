import 'package:chitieu/utils/safe_ui.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:chitieu/api/wallet/wallet_provider.dart';

class EditWalletForm extends StatefulWidget {
  final int walletId;
  final String initialName;
  final double initialBalance; // vẫn nhận để giữ nguyên số dư

  const EditWalletForm({
    super.key,
    required this.walletId,
    required this.initialName,
    required this.initialBalance,
  });

  @override
  State<EditWalletForm> createState() => _EditWalletFormState();
}

class _EditWalletFormState extends State<EditWalletForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtl;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _nameCtl = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _nameCtl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final name = _nameCtl.text.trim();

    setState(() => _submitting = true);
    try {
      // Giữ nguyên số dư hiện tại, KHÔNG cho phép chỉnh ở UI
      final ok = await context.read<WalletProvider>().updateWallet(
            id: widget.walletId,
            name: name,
            balance: widget.initialBalance,
          );
      if (!mounted) return;
      if (ok) {
        Navigator.pop(context, true);
      } else {
        safeShowSnackBar(
          context,
          const SnackBar(content: Text('Cập nhật không thành công')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      safeShowSnackBar(
        context,
        SnackBar(content: Text('Lỗi cập nhật ví: $e')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận'),
        content: const Text('Bạn có chắc muốn xóa ví này không?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Xóa', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _submitting = true);
    try {
      final ok =
          await context.read<WalletProvider>().deleteWallet(widget.walletId);
      if (!mounted) return;
      if (ok) {
        Navigator.pop(context, true);
        safeShowSnackBar(
          context,
          const SnackBar(content: Text('Đã xóa ví')),
        );
      } else {
        safeShowSnackBar(
          context,
          const SnackBar(content: Text('Xóa ví thất bại')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      safeShowSnackBar(
        context,
        SnackBar(content: Text('Lỗi xóa ví: $e')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 4,
              width: 48,
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Chỉnh sửa khoản thu',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),

            // Chỉ còn tên
            TextFormField(
              controller: _nameCtl,
              decoration: const InputDecoration(labelText: 'Tên khoản thu'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Nhập tên khoản thu' : null,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
            ),

            const SizedBox(height: 16),

            // Nút lưu thay đổi
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                onPressed: _submitting ? null : _submit,
                icon: const Icon(Icons.save_outlined),
                label: Text(_submitting ? 'Đang lưu...' : 'Lưu thay đổi'),
              ),
            ),
            const SizedBox(height: 12),

            // Nút xóa ví
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                onPressed: _submitting ? null : _delete,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Xóa ví'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
