import 'package:chitieu/auth/auth_provider.dart';
import 'package:chitieu/auth/login.dart';
import 'package:chitieu/core/budget/budget_model.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:chitieu/l10n/app_localizations.dart';

// mở trang Cài đặt Ngân sách
import 'setting/money_settings_page.dart';

// provider
import '../api/wallet/wallet_provider.dart';
import '../core/budget/budgets_provider.dart';

// hiển thị tiền
import '../core/money/widgets/money_text.dart';

// TRANG TẠO DANH MỤC
import 'budget_edit_page.dart';

// Category
import 'package:chitieu/api/category/category_provider.dart';
import 'package:chitieu/api/category/category_model.dart';

// QUẢN LÝ DANH MỤC
import 'package:chitieu/core/budget/category/category_manage_page.dart';

// TRANG PHÂN BỔ TIỀN
import 'allocate_money_page.dart';

// TRANG CHI TIẾT DANH MỤC
import 'package:chitieu/core/budget/category/category_detail_page.dart';

// === NEW: widget danh mục có thanh tiến trình + cảnh báo
import 'package:chitieu/core/budget/widgets/budget_category_tile.dart';

class BudgetsPage extends StatefulWidget {
  const BudgetsPage({super.key});

  @override
  State<BudgetsPage> createState() => _BudgetsPageState();
}

class _BudgetsPageState extends State<BudgetsPage> {
  static const double _radius = 20;
  static const double _hPad = 16;
  static const double _vGap = 20;
  static const double _maxContentWidth = 640;

  DateTime _ym = DateTime.now();
  bool _loadedOnce = false;

  // === MỚI: theo dõi thay đổi trạng thái đăng nhập để auto reload ===
  bool _wasAuthed = false;

  void _onAuthChanged() {
    final authed = context.read<AuthProvider>().isAuthenticated;
    if (authed && !_wasAuthed) {
      // vừa chuyển từ chưa login -> đã login
      _reloadAll();
    }
    _wasAuthed = authed;
  }

  @override
  void initState() {
    super.initState();
    // đăng ký listener sau frame đầu để có context hợp lệ
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final auth = context.read<AuthProvider>();
      _wasAuthed = auth.isAuthenticated;
      auth.addListener(_onAuthChanged);
    });
  }

  @override
  void dispose() {
    // gỡ listener để tránh memory leak
    try {
      context.read<AuthProvider>().removeListener(_onAuthChanged);
    } catch (_) {}
    super.dispose();
  }

  // ===== Helper: đảm bảo đã đăng nhập (có hỏi người dùng nếu chưa) =====
  Future<bool> _ensureAuthed(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    if (auth.isAuthenticated) return true;

    final t = AppLocalizations.of(context)!;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.needLogin),
        content: Text(t.needLoginBudgets),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t.login),
          ),
        ],
      ),
    );

    if (go != true || !context.mounted) return false;

    // Mở trang Login và CHỜ kết quả
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const LoginPage()),
    );

    final authedNow = ok == true && context.read<AuthProvider>().isAuthenticated;

    // === MỚI: reload toàn bộ ngay sau khi login thành công ===
    if (authedNow && context.mounted) {
      await _reloadAll();
    }

    return authedNow;
  }

  Future<void> _openCreateCategory() async {
    final ok = await _ensureAuthed(context);
    if (!ok || !mounted) return;

    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const BudgetEditPage()),
    );

    if (created == true && mounted) {
      await context.read<CategoryProvider>().refresh();
    }
  }

  Future<void> _openManageCategories() async {
    final ok = await _ensureAuthed(context);
    if (!ok || !mounted) return;

    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const CategoryManagePage()),
    );
    if (changed == true && mounted) {
      await context.read<CategoryProvider>().refresh();
    }
  }

  Future<void> _reloadAll() async {
    final futures = <Future<void>>[];
    final auth = context.read<AuthProvider>();
    if (!auth.isAuthenticated) return;

    final wallet = context.read<WalletProvider>();
    if (!wallet.loading) futures.add(wallet.fetch());

    final cat = context.read<CategoryProvider>();
    if (!cat.loading) futures.add(cat.refresh());

    final budgets = context.read<BudgetsProvider>();
    futures.add(budgets.loadForMonth(year: _ym.year, month: _ym.month));

    await Future.wait(futures);
    if (mounted) setState(() {}); // đảm bảo rebuild ngay
  }

  /// MỞ TRANG PHÂN BỔ TIỀN
  Future<void> _openAllocateMoney(num available) async {
    final ok = await _ensureAuthed(context);
    if (!ok || !mounted) return;

    // tải danh mục
    final catProv = context.read<CategoryProvider>();
    await catProv.refresh();
    final categories = catProv.items;

    // lấy phân bổ hiện có để prefill
    final budProv = context.read<BudgetsProvider>();
    final now = DateTime.now();
    final yr  = budProv.currentYear  ?? now.year;
    final mo  = budProv.currentMonth ?? now.month;

    // đảm bảo đã có dữ liệu tháng hiện tại trước khi mở trang
    await budProv.loadForMonth(year: yr, month: mo);

    // map categoryId -> số đã phân bổ
    final initialAssigned = <int, num>{
      for (final it in budProv.items)
        it.categoryId: (it.amount > 0 ? it.amount : (it as dynamic).amount ?? 0) as num
    };

    // mở trang, available không âm để tránh lỗi nhập
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AllocateMoneyPage(
          available: (available > 0 ? available : 0).toDouble(),
          categories: categories,
          initialAssigned: initialAssigned,
        ),
      ),
    );

    if (!mounted) return;

    // Trang mới sẽ lưu từng mục và thường trả 'true'
    if (result == true) {
      await budProv.loadForMonth(year: yr, month: mo);
      await context.read<WalletProvider>().fetch();
      setState(() {});
      return;
    }

    // Flow cũ: nếu trang trả về map phân bổ -> gọi assignMany
    if (result is Map) {
      final allocations = <int, double>{};
      result.forEach((k, v) {
        int id;
        if (k is int) {
          id = k;
        } else if (k is Category) {
          id = k.id;
        } else {
          id = int.tryParse(k.toString()) ?? 0;
        }
        if (id > 0) allocations[id] = (v as num).toDouble();
      });

      try {
        await budProv.assignMany(DateTime(yr, mo, 1), allocations);
        await budProv.loadForMonth(year: yr, month: mo);
        await context.read<WalletProvider>().fetch();
        setState(() {});
      } catch (e) {
        final t = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${t.errorGeneric}: $e')),
        );
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loadedOnce) {
      final authed = context.read<AuthProvider>().isAuthenticated;
      if (authed) {
        context.read<CategoryProvider>().refresh();
        context.read<BudgetsProvider>().loadForMonth(
              year: _ym.year,
              month: _ym.month,
            );
      }
      _loadedOnce = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;

    final totalBalance =
        context.select<WalletProvider, num>((w) => w.totalBalance);
    final totalAssigned =
        context.select<BudgetsProvider, num>((b) => b.totalAssigned);

    // Cho phép âm nếu đã phân bổ > số dư
    final unassigned = totalBalance - totalAssigned;

    final authed = context.select<AuthProvider, bool>((a) => a.isAuthenticated);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.settings),
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const MoneySettingsPage()),
            );
          },
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF0F6C41),
        title: _MonthPill(
          label: _formatMonthYear(context, _ym),
          onTap: () async {
            final picked = await showModalBottomSheet<DateTime>(
              context: context,
              isScrollControlled: true,
              useSafeArea: true,
              backgroundColor: Colors.transparent,
              builder: (_) => MonthPickerSheet(
                initial: _ym,
                min: DateTime(2020, 1),
                max: DateTime(2035, 12),
              ),
            );
            if (picked != null) {
              setState(() => _ym = picked);
              await context.read<BudgetsProvider>().loadForMonth(
                    year: _ym.year,
                    month: _ym.month,
                  );
            }
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: t.editCategories,
            onPressed: _openManageCategories,
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _reloadAll,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(_hPad),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: _maxContentWidth),
                  child: Column(
                    children: [
                      _overviewCard(
                        context,
                        t,
                        totalAssigned,
                        unassigned,
                        // nếu âm thì vẫn mở trang, nhưng available truyền 0
                        onAssignPressed: () => _openAllocateMoney(unassigned > 0 ? unassigned : 0),
                      ),
                      const SizedBox(height: _vGap),
                      if (authed)
                        _categorySection(context, t)
                      else
                        _askLoginCard(context, t),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _overviewCard(
    BuildContext context,
    AppLocalizations t,
    num assigned,
    num unassigned, {
    required VoidCallback onAssignPressed,
  }) {
    final walletLoading =
        context.select<WalletProvider, bool>((w) => w.loading);

    return ClipRRect(
      borderRadius: BorderRadius.circular(_radius),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.green.shade700, Colors.green.shade400],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _infoBox(context, t.moneyAssigned, assigned),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _infoBox(context, t.moneyUnassigned, unassigned),
                      ),
                    ],
                  ),

                  if (unassigned < 0) ...[
                    const SizedBox(height: 12),
                    _negativeBanner(context, debt: -unassigned),
                  ],

                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: onAssignPressed,
                      icon: const Icon(Icons.task_alt),
                      label: Text(t.assignMoneyCta),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.green.shade800,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: walletLoading
                ? Container(
                    key: const ValueKey('overlay'),
                    color: Colors.black.withOpacity(0.05),
                    alignment: Alignment.center,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(.9),
                        shape: BoxShape.circle,
                      ),
                      padding: const EdgeInsets.all(6),
                      child: const CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : const SizedBox.shrink(key: ValueKey('none')),
          ),
        ],
      ),
    );
  }

  Widget _infoBox(BuildContext context, String label, num value) {
    final isNegative = value < 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
        const SizedBox(height: 6),
        MoneyText(
          value,
          style: TextStyle(
            color: isNegative ? Colors.redAccent.shade100 : Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _negativeBanner(BuildContext context, {required num debt}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.redAccent.withOpacity(.6)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, color: Colors.redAccent),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(color: Colors.black87, fontSize: 13.5),
                children: [
                  const TextSpan(text: 'Đã phân bổ vượt số dư. Thiếu '),
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 2, right: 2),
                      child: MoneyText(
                        debt,
                        style: const TextStyle(
                          color: Colors.redAccent,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  const TextSpan(text: ' để cân bằng tháng này.'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _askLoginCard(BuildContext context, AppLocalizations t) {
    final theme = Theme.of(context);
    return Card(
      color: Colors.amber.shade50,
      elevation: 0.5,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radius)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(
              t.needLogin,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              t.needLoginContent,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }

  Widget _categorySection(BuildContext context, AppLocalizations t) {
    final theme = Theme.of(context);
    final cat = context.watch<CategoryProvider>();

    if (cat.loading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (cat.items.isEmpty) {
      return Card(
        color: Colors.amber.shade50,
        elevation: 0.5,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_radius)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Text(
                t.createCategoryTitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                t.createCategoryDescription,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _openCreateCategory,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: BorderSide(color: Colors.grey.shade400),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(t.createMyOwn),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Row(
            children: [
              Text(
                t.createCategoryTitle,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.add),
                tooltip: t.createMyOwn,
                onPressed: _openCreateCategory,
              )
            ],
          ),
        ),
        const SizedBox(height: 8),
        ...cat.items.map((c) => _categoryTile(context, c)).toList(),
        const SizedBox(height: 12),
      ],
    );
  }

  /// Liên kết Category với BudgetItem theo categoryId
  Widget _categoryTile(BuildContext context, Category c) {
    final budgets = context.watch<BudgetsProvider>();

    final item = budgets.items.firstWhere(
      (b) => b.categoryId == c.id,
      orElse: () => BudgetItem(
        id: 0,
        userId: 0,
        categoryId: c.id.toInt(),
        name: c.name,
        year: _ym.year,
        month: _ym.month,
        amount: 0,
        spent: 0, // thêm mặc định spent
      ),
    );

    return BudgetCategoryTile(
      category: c,
      item: item,
      onTap: () async {
        final updated = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) => CategoryDetailPage(
              category: c,
              year: _ym.year,
              month: _ym.month,
              initialLimit: item.amount.toDouble(),
            ),
          ),
        );

        if (updated == true && context.mounted) {
          await context.read<CategoryProvider>().refresh();
          await context.read<BudgetsProvider>().loadForMonth(
                year: _ym.year,
                month: _ym.month,
              );
          setState(() {});
        }
      },
    );
  }

  String _formatMonthYear(BuildContext ctx, DateTime ym) {
    final locale = Localizations.localeOf(ctx).toLanguageTag();
    final t = AppLocalizations.of(ctx)!;
    final monthName = DateFormat.MMMM(locale).format(ym);
    final year = DateFormat.y(locale).format(ym);
    return t.monthYearTitle(monthName, year);
  }
}

/// Pill hiển thị tháng/năm
class _MonthPill extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _MonthPill({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF165F3D),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(.6)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.keyboard_arrow_down,
                color: Colors.white, size: 18),
          ],
        ),
      ),
    );
  }
}

/// Bottom-sheet chọn tháng
class MonthPickerSheet extends StatefulWidget {
  final DateTime initial, min, max;
  const MonthPickerSheet({
    super.key,
    required this.initial,
    required this.min,
    required this.max,
  });

  @override
  State<MonthPickerSheet> createState() => _MonthPickerSheetState();
}

class _MonthPickerSheetState extends State<MonthPickerSheet> {
  late int _year;

  @override
  void initState() {
    super.initState();
    _year = widget.initial.year;
  }

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    final t = AppLocalizations.of(context)!;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.black12,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: _year > widget.min.year
                    ? () => setState(() => _year--)
                    : null,
                icon: const Icon(Icons.chevron_left),
              ),
              Text(
                '$_year',
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              IconButton(
                onPressed: _year < widget.max.year
                    ? () => setState(() => _year++)
                    : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          const SizedBox(height: 8),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 2.7,
            children: List.generate(12, (i) {
              final m = i + 1;
              final dt = DateTime(_year, m);
              final enabled = dt.isAfter(
                      DateTime(widget.min.year, widget.min.month - 1)) &&
                  dt.isBefore(DateTime(widget.max.year, widget.max.month + 1));

              final monthName = DateFormat.MMMM(locale).format(dt);
              final label =
                  Localizations.of<AppLocalizations>(context, AppLocalizations)!
                              .localeName ==
                          'vi'
                      ? t.monthGridLabel(m.toString())
                      : monthName;

              final isSelected =
                  _year == widget.initial.year && m == widget.initial.month;

              return OutlinedButton(
                onPressed: enabled ? () => Navigator.pop(context, dt) : null,
                style: OutlinedButton.styleFrom(
                  backgroundColor: isSelected ? Colors.green.shade50 : null,
                  side: BorderSide(
                      color: isSelected ? Colors.green : Colors.black12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child:
                    Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
              );
            }),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}
