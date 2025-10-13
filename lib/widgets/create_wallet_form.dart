import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import 'package:chitieu/l10n/app_localizations.dart';
import 'package:chitieu/api/wallet/wallet_provider.dart';

/// Formatter để hiển thị số có dấu phẩy khi nhập
class CurrencyInputFormatter extends TextInputFormatter {
  final NumberFormat _formatter = NumberFormat.decimalPattern();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) {
      return newValue.copyWith(text: '');
    }

    // Bỏ tất cả ký tự không phải số
    String raw = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (raw.isEmpty) {
      return newValue.copyWith(text: '');
    }

    // Parse và format lại
    final value = int.parse(raw);
    final newText = _formatter.format(value);

    return TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newText.length),
    );
  }
}

class CreateWalletForm extends StatefulWidget {
  const CreateWalletForm({super.key});

  @override
  State<CreateWalletForm> createState() => _CreateWalletFormState();
}

class _CreateWalletFormState extends State<CreateWalletForm> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _amountController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final t = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);

    // parse lại về double (bỏ dấu phẩy)
    final raw = _amountController.text.trim().replaceAll(',', '');
    final amount = double.tryParse(raw) ?? 0;

    setState(() => _saving = true);
    final ok = await context
        .read<WalletProvider>()
        .createWallet(_nameController.text.trim(), amount);
    setState(() => _saving = false);

    if (!mounted) return;

    if (ok) {
      Navigator.pop(context, true);
      messenger.hideCurrentMaterialBanner();
      messenger.showMaterialBanner(
        MaterialBanner(
          content: Text(t.walletCreated),
          leading: const Icon(Icons.check_circle, color: Colors.white),
          backgroundColor: Theme.of(context).colorScheme.primary,
          contentTextStyle: TextStyle(
            color: Theme.of(context).colorScheme.onPrimary,
            fontSize: 16,
          ),
          actions: [
            TextButton(
              onPressed: () => messenger.hideCurrentMaterialBanner(),
              child: Text('OK',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onPrimary)),
            ),
          ],
        ),
      );
      Future.delayed(const Duration(seconds: 2), messenger.hideCurrentMaterialBanner);
    } else {
      final err = context.read<WalletProvider>().error ?? t.somethingWrong;
      messenger.showSnackBar(SnackBar(content: Text(err)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;

    return SafeArea(
      top: false,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(40),
                      ),
                    ),
                  ),
                  Text(
                    t.createWallet,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),

                  // Tên ví
                  TextFormField(
                    controller: _nameController,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: t.walletName,
                      border: const OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? t.requiredField : null,
                  ),
                  const SizedBox(height: 12),

                  // Số tiền ban đầu (có formatter)
                  TextFormField(
                    controller: _amountController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    textInputAction: TextInputAction.done,
                    inputFormatters: [CurrencyInputFormatter()],
                    onFieldSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: t.initialAmount,
                      hintText: '0',
                      border: const OutlineInputBorder(),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return t.requiredField;
                      final parsed = num.tryParse(v.replaceAll(',', '').trim());
                      if (parsed == null) return t.invalidNumber;
                      if (parsed < 0) return t.invalidNumber;
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),

                  // Nút lưu
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: cs.primary,
                        foregroundColor: cs.onPrimary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: _saving ? null : _submit,
                      child: _saving
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(t.save,
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
