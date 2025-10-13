import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:chitieu/l10n/app_localizations.dart';

// Providers & models
import 'package:chitieu/api/wallet/wallet_provider.dart';
import 'package:chitieu/api/category/category_provider.dart';
import 'package:chitieu/api/category/category_model.dart';

// Gọi API giao dịch & refresh ngân sách
import 'package:chitieu/api/tx/tx_provider.dart';
import 'package:chitieu/api/tx/tx_model.dart';
import 'package:chitieu/core/budget/budgets_provider.dart';

// hiển thị tiền
import 'package:chitieu/core/money/widgets/money_text.dart';

enum FlowType { out, in_ }

class NotePage extends StatefulWidget {
  const NotePage({super.key});

  @override
  State<NotePage> createState() => _NotePageState();
}

class _NotePageState extends State<NotePage> {
  FlowType type = FlowType.out;
  String amount = '';

  // lựa chọn
  dynamic selectedWallet; // đổi sang WalletModel nếu bạn có model cụ thể
  Category? selectedCategory;
  DateTime _selectedDate = DateTime.now();

  // ====== NOTE ======
  String _noteText = '';
  final TextEditingController _noteCtl = TextEditingController();

  // ====== formatter VN ======
  final NumberFormat _vi = NumberFormat.decimalPattern('vi_VN');
  String _formatVn(String raw) {
    if (raw.isEmpty) return '0';
    final n = int.tryParse(raw) ?? 0;
    return _vi.format(n);
  }

  @override
  void dispose() {
    _noteCtl.dispose();
    super.dispose();
  }

  /* ================= handlers ================= */

  void _onKey(String k) {
    setState(() {
      if (k == '.' && amount.contains('.')) return;
      amount += k;
    });
  }

  void _onBackspace() {
    if (amount.isEmpty) return;
    setState(() => amount = amount.substring(0, amount.length - 1));
  }

  /// NHẤN ✓ → gọi API tạo giao dịch + refresh ngân sách
  Future<void> _submit() async {
    final isOut = type == FlowType.out;
    final amt = int.tryParse(amount) ?? 0;

    // Lấy id ví được chọn (nếu có)
    final selectedWalletId = (selectedWallet as dynamic)?.id ?? 0;

    // Với TIỀN RA: nếu không chọn ví thì dùng ví đầu tiên (mặc định)
    final wProv = context.read<WalletProvider>();
    if (!wProv.loading && wProv.items.isEmpty) {
      await wProv.fetch();
    }
    final defaultWalletId =
        wProv.items.isNotEmpty ? (wProv.items.first as dynamic).id as int : 0;
    final effectiveWalletId =
        isOut ? (selectedWalletId != 0 ? selectedWalletId : defaultWalletId) : selectedWalletId;

    final categoryId = selectedCategory?.id ?? 0;

    // Validate
    if (amt <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng nhập số tiền > 0.')),
      );
      return;
    }
    if (!isOut && effectiveWalletId == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng chọn ví.')),
      );
      return;
    }
    if (isOut && categoryId == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng chọn danh mục.')),
      );
      return;
    }
    if (effectiveWalletId == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bạn cần tạo ít nhất một ví trước.')),
      );
      return;
    }

    // NOTE: cắt ghi chú tối đa 300 ký tự cho khớp validate backend
    final trimmedNote = _noteText.trim();
    final safeNote = trimmedNote.isEmpty
        ? null
        : (trimmedNote.length <= 300 ? trimmedNote : trimmedNote.substring(0, 300));

    // Chuẩn bị request theo schema tx_model.dart
    final req = TxRequest(
      type: isOut ? 'chi' : 'thu',
      walletId: effectiveWalletId,
      categoryId: isOut ? categoryId : null,
      amount: amt,
      txnTime: _selectedDate,
      note: safeNote, // <-- gửi note
    );

    try {
      await context.read<TxProvider>().create(req);
      // đảm bảo “Đã tiêu” cập nhật trên BudgetsPage
      await context.read<BudgetsProvider>().refreshCurrent();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Lỗi tạo giao dịch: $e')));
    }
  }

  /* ================= pickers ================= */

  Future<void> _openWalletPicker() async {
    final wProv = context.read<WalletProvider>();
    if (!wProv.loading && (wProv.items.isEmpty)) {
      await wProv.fetch();
    }

    final picked = await showModalBottomSheet<dynamic>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _WalletPickerSheet(
        items: wProv.items,
        selectedId: selectedWallet?.id,
        onTopUp: (wallet) async {
          final controller = TextEditingController();
          final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Nạp tiền vào ví'),
              content: TextField(
                controller: controller,
                decoration: const InputDecoration(
                  hintText: 'Nhập số tiền',
                  prefixText: 'đ ',
                ),
                keyboardType: TextInputType.number,
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Xác nhận')),
              ],
            ),
          );
          if (ok == true) {
            final value = num.tryParse(
                  controller.text.replaceAll('.', '').replaceAll(',', ''),
                ) ??
                0;
            if (value > 0) {
              try {
                try {
                  await (wProv as dynamic).topUp(wallet.id, value);
                } catch (_) {
                  try {
                    await (wProv as dynamic).deposit(wallet.id, value);
                  } catch (_) {
                    await (wProv as dynamic).addMoney(wallet.id, value);
                  }
                }
                if (!mounted) return;
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('Đã nạp tiền')));
                await wProv.fetch();
                setState(() {});
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Lỗi nạp tiền: $e')),
                );
              }
            }
          }
        },
      ),
    );

    if (picked != null && mounted) {
      setState(() => selectedWallet = picked);
    }
  }

  Future<void> _openCategoryPicker() async {
    final catProv = context.read<CategoryProvider>();
    if (!catProv.loading && catProv.items.isEmpty) {
      await catProv.refresh();
    }

    final picked = await showModalBottomSheet<Category>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _CategoryPickerSheet(
        items: catProv.items,
        selectedId: selectedCategory?.id,
      ),
    );

    if (picked != null && mounted) {
      setState(() => selectedCategory = picked);
    }
  }

  Future<void> _openDatePicker() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020, 1),
      lastDate: DateTime(2035, 12),
      helpText: 'Chọn ngày',
    );
    if (picked != null && mounted) {
      setState(() => _selectedDate = picked);
    }
  }

  // ====== NOTE editor (bottom sheet) ======
  Future<void> _openNoteEditor() async {
    _noteCtl.text = _noteText;
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 12,
            bottom: 16 + MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  height: 4,
                  width: 40,
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text('Ghi chú', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              TextField(
                controller: _noteCtl,
                maxLines: 3,
                maxLength: 300, // NOTE: khớp validate backend
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  hintText: 'Thêm mô tả cho giao dịch',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Hủy'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, _noteCtl.text.trim()),
                    child: const Text('Lưu'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
    if (result != null && mounted) {
      setState(() => _noteText = result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;

    final dateLabel = DateFormat('dd/MM/yyyy').format(_selectedDate);

    const bg = Color(0xFFFBF5E8);
    const yellow = Color(0xFFF7CF54);
    const yellowSoft = Color(0xFFFFF1BE);
    const borderGrey = Color(0xFFDBD5C9);

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          children: [
            // App bar + segmented
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Row(
                children: [
                  _circleIcon(
                    icon: Icons.close_rounded,
                    onTap: () => Navigator.maybePop(context),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _FlowSegmented(
                      value: type,
                      onChanged: (v) => setState(() {
                        type = v;
                        if (type == FlowType.out) selectedWallet = null; // xoá ví khi chuyển sang Tiền ra
                        if (type == FlowType.in_) selectedCategory = null; // tiền vào không cần danh mục
                      }),
                      borderColor: borderGrey,
                      selectedColor: yellow,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const SizedBox(width: 32),
                ],
              ),
            ),

            const SizedBox(height: 28),
            _categoryIcon(),
            const SizedBox(height: 12),
            _amountText(context: context, type: type, amount: amount),
            const SizedBox(height: 8),

            // NOTE: dòng mô tả/ghi chú (tap để sửa)
            InkWell(
              onTap: _openNoteEditor,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Text(
                  _noteText.isEmpty ? t.noteAddDescription : _noteText,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodyMedium?.copyWith(
                    color: _noteText.isEmpty ? Colors.black38 : Colors.black87,
                    fontWeight: _noteText.isEmpty ? FontWeight.w400 : FontWeight.w600,
                  ),
                ),
              ),
            ),

            const Spacer(),

            // Tool chips
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: const BoxDecoration(
                color: yellowSoft,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  // CHỌN VÍ: chỉ hiện khi TIỀN VÀO
                  if (type == FlowType.in_)
                    Expanded(
                      child: _ToolChip(
                        icon: Icons.account_balance_wallet_rounded,
                        label: (selectedWallet?.name ?? selectedWallet?.title ?? t.cash),
                        onTap: _openWalletPicker,
                      ),
                    ),
                  if (type == FlowType.in_) const SizedBox(width: 10),

                  // Danh mục: chỉ hiển thị khi là TIỀN RA
                  if (type == FlowType.out)
                    Expanded(
                      child: _ToolChip(
                        icon: Icons.add_box_outlined,
                        label: selectedCategory?.name ?? t.category,
                        onTap: _openCategoryPicker,
                      ),
                    ),
                  if (type == FlowType.out) const SizedBox(width: 10),

                  // Chip Ghi chú nhanh
                  Expanded(
                    child: _ToolChip(
                      icon: Icons.edit_note_rounded,
                      label: _noteText.isEmpty ? 'Ghi chú' : 'Sửa ghi chú',
                      onTap: _openNoteEditor,
                    ),
                  ),
                  const SizedBox(width: 10),

                  Expanded(
                    child: _ToolChip(
                      icon: Icons.calendar_month_rounded,
                      label: dateLabel,
                      onTap: _openDatePicker,
                    ),
                  ),
                ],
              ),
            ),

            _KeypadBar(
              onTap: _onKey,
              onBack: _onBackspace,
              onConfirm: _submit, // <<< GỌI API Ở ĐÂY
            ),
          ],
        ),
      ),
    );
  }

  /* ================= UI helpers ================= */

  Widget _categoryIcon() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1BE),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFF2D985)),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 2)],
      ),
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: const Color(0xFFF5B735),
          borderRadius: BorderRadius.circular(100),
        ),
        alignment: Alignment.center,
        child: const Text('•‿•', style: TextStyle(fontSize: 18, color: Colors.white)),
      ),
    );
  }

  Widget _amountText({
    required BuildContext context,
    required FlowType type,
    required String amount,
  }) {
    final isOut = type == FlowType.out;
    final base =
        Theme.of(context).textTheme.displaySmall ?? const TextStyle(fontSize: 40);

    final formattedCore = amount.isEmpty ? '0' : _formatVn(amount);
    final text = amount.isEmpty ? 'đ0' : (isOut ? '-đ$formattedCore' : '+đ$formattedCore');

    return RichText(
      text: TextSpan(
        style: base.copyWith(fontWeight: FontWeight.w800),
        children: [
          TextSpan(
            text: text,
            style: base.copyWith(
              fontWeight: FontWeight.w800,
              color: isOut ? const Color(0xFFD64545) : const Color(0xFF1F9D4C),
              decoration: TextDecoration.underline,
              decorationThickness: 4,
              decorationColor: Colors.black12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _circleIcon({required IconData icon, required VoidCallback onTap}) {
    return Material(
      color: const Color(0xFFEDE6D9),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 18, color: Colors.black54),
        ),
      ),
    );
  }
}

/* ================= Segmented ================= */

class _FlowSegmented extends StatelessWidget {
  const _FlowSegmented({
    required this.value,
    required this.onChanged,
    required this.borderColor,
    required this.selectedColor,
  });

  final FlowType value;
  final ValueChanged<FlowType> onChanged;
  final Color borderColor;
  final Color selectedColor;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;

    const selectedText = TextStyle(
      fontWeight: FontWeight.w700,
      color: Colors.black87,
    );
    final normalText = TextStyle(
      fontWeight: FontWeight.w600,
      color: Colors.black87,
    );

    return Container(
      height: 44,
      decoration: BoxDecoration(
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(28),
        color: Colors.white,
      ),
      child: Row(
        children: [
          Expanded(
            child: _SegmentTile(
              icon: Icons.call_made_rounded,
              label: t.moneyOut,
              selected: value == FlowType.out,
              selectedColor: selectedColor,
              textStyle: value == FlowType.out ? selectedText : normalText,
              onTap: () => onChanged(FlowType.out),
              left: true,
            ),
          ),
          Expanded(
            child: _SegmentTile(
              icon: Icons.call_received_rounded,
              label: t.moneyIn,
              selected: value == FlowType.in_,
              selectedColor: selectedColor,
              textStyle: value == FlowType.in_ ? selectedText : normalText,
              onTap: () => onChanged(FlowType.in_),
              right: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _SegmentTile extends StatelessWidget {
  const _SegmentTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.selectedColor,
    required this.textStyle,
    required this.onTap,
    this.left = false,
    this.right = false,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final Color selectedColor;
  final TextStyle textStyle;
  final VoidCallback onTap;
  final bool left;
  final bool right;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      margin: EdgeInsets.only(left: left ? 4 : 2, right: right ? 4 : 2, top: 4, bottom: 4),
      decoration: BoxDecoration(
        color: selected ? selectedColor : Colors.transparent,
        borderRadius: BorderRadius.horizontal(
          left: left ? const Radius.circular(24) : Radius.zero,
          right: right ? const Radius.circular(24) : Radius.zero,
        ),
        boxShadow: selected
            ? const [BoxShadow(color: Color(0x22A58B00), offset: Offset(0, 2), blurRadius: 4)]
            : null,
      ),
      child: InkWell(
        borderRadius: BorderRadius.horizontal(
          left: left ? const Radius.circular(24) : Radius.zero,
          right: right ? const Radius.circular(24) : Radius.zero,
        ),
        onTap: onTap,
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: Colors.black87),
              const SizedBox(width: 6),
              Text(label, style: textStyle),
            ],
          ),
        ),
      ),
    );
  }
}

/* ================= Tool chip ================= */

class _ToolChip extends StatelessWidget {
  const _ToolChip({required this.icon, required this.label, this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 46,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 2)],
          ),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: Colors.brown.shade600),
                const SizedBox(width: 6),
                Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/* ================= Keypad ================= */

class _KeypadBar extends StatelessWidget {
  const _KeypadBar({
    required this.onTap,
    required this.onBack,
    required this.onConfirm,
  });

  final ValueChanged<String> onTap;
  final VoidCallback onBack;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    const grey = Color(0xFFE9E7E5);
    const green = Color(0xFF2DBE60);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      decoration: const BoxDecoration(
        color: Color(0xFFF2F1EF),
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SizedBox(
        height: 260,
        child: Row(
          children: [
            // lưới phím
            Expanded(
              flex: 3,
              child: GridView.count(
                crossAxisCount: 3,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.25,
                children: [
                  for (final n in ['1','2','3','4','5','6','7','8','9'])
                    _PadKey(label: n, onTap: () => onTap(n)),
                  _PadKey(label: '000', onTap: () => onTap('000')),
                  _PadKey(label: '0', onTap: () => onTap('0')),
                  _PadKey(icon: Icons.backspace_outlined, onTap: onBack, bg: grey),
                ],
              ),
            ),
            const SizedBox(width: 10),
            // nút xác nhận cao
            Expanded(
              child: Column(
                children: [
                  Expanded(
                    child: _PadKey(
                      bg: green,
                      child: const Icon(Icons.check_rounded, color: Colors.white, size: 36),
                      onTap: onConfirm,
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

class _PadKey extends StatelessWidget {
  const _PadKey({
    this.label,
    this.icon,
    this.child,
    required this.onTap,
    this.bg = Colors.white,
  });

  final String? label;
  final IconData? icon;
  final Widget? child;
  final VoidCallback onTap;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    final content = child ??
        (icon != null
            ? Icon(icon, color: Colors.black87)
            : Text(label!, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600)));

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Center(child: content),
      ),
    );
  }
}

/* ================= Bottom sheets ================= */

class _WalletPickerSheet extends StatelessWidget {
  const _WalletPickerSheet({
    required this.items,
    required this.selectedId,
    required this.onTopUp,
  });

  final List<dynamic> items;
  final dynamic selectedId;
  final Future<void> Function(dynamic wallet) onTopUp;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 4,
                width: 40,
                decoration:
                    BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: 12),
              const Text('Chọn ví / Nạp tiền',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),

              for (final w in items)
                Card(
                  elevation: .4,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: ListTile(
                    leading:
                        const CircleAvatar(child: Icon(Icons.account_balance_wallet_rounded)),
                    title: Text(
                      (w as dynamic).name ?? (w as dynamic).title ?? '—',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Row(children: [
                      const Text('Số dư: '),
                      MoneyText((w as dynamic).balance ?? (w as dynamic).amount ?? 0),
                    ]),
                    trailing: Wrap(
                      spacing: 8,
                      children: [
                        IconButton(
                          tooltip: 'Nạp',
                          icon: const Icon(Icons.add_card_rounded),
                          onPressed: () => onTopUp(w),
                        ),
                        if ((w as dynamic).id == selectedId)
                          const Icon(Icons.check_rounded, color: Color(0xFF2DBE60)),
                      ],
                    ),
                    onTap: () => Navigator.pop(context, w), // chọn ví
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryPickerSheet extends StatelessWidget {
  const _CategoryPickerSheet({required this.items, required this.selectedId});
  final List<Category> items;
  final int? selectedId;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
                height: 4,
                width: 40,
                decoration:
                    BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 12),
            const Text('Chọn danh mục', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),

            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: items.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3, childAspectRatio: 1.15, mainAxisSpacing: 8, crossAxisSpacing: 8),
              itemBuilder: (_, i) {
                final c = items[i];
                final selected = c.id == selectedId;

                // avatar = chữ cái đầu của tên danh mục
                final first = (c.name.isNotEmpty ? c.name[0] : '•').toUpperCase();

                return Material(
                  color: selected ? Colors.green.withOpacity(.08) : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => Navigator.pop(_, c),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: Colors.green.withOpacity(.1),
                          child: Text(first, style: const TextStyle(fontWeight: FontWeight.w800)),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          c.name,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: selected ? Colors.green : Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
