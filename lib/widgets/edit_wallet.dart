import 'package:chitieu/utils/safe_ui.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:chitieu/api/wallet/wallet_provider.dart';

class EditWalletForm extends StatefulWidget {
  final int walletId;
  final String initialName;
  final double initialBalance;

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
  late final TextEditingController _balanceCtl;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _nameCtl = TextEditingController(text: widget.initialName);
    _balanceCtl = TextEditingController(
      text: widget.initialBalance.toStringAsFixed(0),
    );
  }

  @override
  void dispose() {
    _nameCtl.dispose();
    _balanceCtl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final name = _nameCtl.text.trim();
    final bal = double.tryParse(
          _balanceCtl.text.replaceAll(',', '').replaceAll(' ', ''),
        ) ??
        0;

    setState(() => _submitting = true);
    try {
      final ok = await context.read<WalletProvider>().updateWallet(
            id: widget.walletId,
            name: name,
            balance: bal,
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
              'Chỉnh sửa ví',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _nameCtl,
              decoration: const InputDecoration(labelText: 'Tên ví'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Nhập tên ví' : null,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _balanceCtl,
              decoration: const InputDecoration(labelText: 'Số dư'),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              validator: (v) {
                final n = double.tryParse(
                    (v ?? '').replaceAll(',', '').replaceAll(' ', ''));
                if (n == null) return 'Số dư không hợp lệ';
                if (n < 0) return 'Số dư phải >= 0';
                return null;
              },
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
