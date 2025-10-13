import 'package:chitieu/utils/safe_ui.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chitieu/l10n/app_localizations.dart';
import 'package:chitieu/core/money/money_formatter.dart';
import 'package:chitieu/core/money/money_settings_provider.dart';

import 'package:chitieu/widgets/create_wallet_form.dart';
import 'package:chitieu/widgets/edit_wallet.dart';

// Auth
import 'package:chitieu/auth/auth_provider.dart';
import 'package:chitieu/auth/login.dart';

// Wallet
import 'package:chitieu/api/wallet/wallet_provider.dart';

// Tx
import 'package:chitieu/api/tx/tx_provider.dart';
import 'package:intl/intl.dart';

// Budgets
import 'package:chitieu/core/budget/budgets_provider.dart';

class AccountsPage extends StatefulWidget {
  const AccountsPage({super.key});
  @override
  State<AccountsPage> createState() => _AccountsPageState();
}

class _AccountsPageState extends State<AccountsPage> {
  static const _prefKeyHideBalance = 'pref_hide_balance';

  AuthProvider? _auth;
  bool _fetchedOnce = false;
  bool _hideBalance = false;

  @override
  void initState() {
    super.initState();
    _loadHidePref();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _auth = context.read<AuthProvider>();

      if (_auth!.isAuthenticated && !_fetchedOnce) {
        _fetchedOnce = true;
        await context.read<WalletProvider>().fetch();
        await context.read<TxProvider>().fetchRecent(limit: 5);
        await context.read<BudgetsProvider>().loadForMonth(
              year: DateTime.now().year,
              month: DateTime.now().month,
            );
      }
      _auth!.addListener(_onAuthChanged);
    });
  }

  Future<void> _loadHidePref() async {
    final sp = await SharedPreferences.getInstance();
    final v = sp.getBool(_prefKeyHideBalance) ?? false;
    if (mounted) setState(() => _hideBalance = v);
  }

  Future<void> _toggleHide() async {
    setState(() => _hideBalance = !_hideBalance);
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_prefKeyHideBalance, _hideBalance);
  }

  void _onAuthChanged() {
    if (!mounted) return;
    final auth = _auth!;
    final wallets = context.read<WalletProvider>();
    if (auth.isAuthenticated) {
      if (!_fetchedOnce) {
        _fetchedOnce = true;
        wallets.fetch();
        context.read<TxProvider>().fetchRecent(limit: 5);
        context.read<BudgetsProvider>().loadForMonth(
              year: DateTime.now().year,
              month: DateTime.now().month,
            );
      }
    } else {
      _fetchedOnce = false;
      wallets.reset();
      // context.read<BudgetsProvider>().reset();
      // context.read<TxProvider>().clear();
    }
  }

  @override
  void dispose() {
    _auth?.removeListener(_onAuthChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;

    final isLoggedIn =
        context.select<AuthProvider, bool>((a) => a.isAuthenticated);

    final walletProv = context.watch<WalletProvider>();
    final totalBalance =
        walletProv.items.fold<double>(0, (s, w) => s + w.balance);

    final moneySettings = context.watch<MoneySettingsProvider>().settings;
    String fmt(num v) => MoneyFormatter(moneySettings).format(v);

    final txProv = context.watch<TxProvider>();
    final budgetsProv = context.watch<BudgetsProvider>();

    // ====== Tính số liệu tháng hiện tại ======
    final num totalSpent =
        budgetsProv.items.fold<num>(0, (s, b) => s + b.spent);

    // GỘP "chưa phân bổ" vào "còn lại":
    // Còn lại tổng = Tổng tài sản - Đã chi
    final num combinedRemaining = totalBalance - totalSpent;

    return RefreshIndicator(
      onRefresh: () async {
        await context.read<WalletProvider>().fetch();
        await context.read<TxProvider>().fetchRecent(limit: 5);
        await context.read<BudgetsProvider>().loadForMonth(
              year: DateTime.now().year,
              month: DateTime.now().month,
            );
      },
      child: SafeArea(
        bottom: true,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ===== Header tổng tài sản =====
              HeaderCard(
                title: t.totalAssets,
                totalText: _hideBalance ? '•••' : fmt(totalBalance),
                loading: walletProv.loading || budgetsProv.loading,
                paymentText: _hideBalance ? '•••' : fmt(totalSpent),          // Đã chi
                trackingText: _hideBalance ? '•••' : fmt(combinedRemaining),  // Còn lại (đã gộp)
                onToggleEye: _toggleHide,
                isHidden: _hideBalance,
              ),

              const SizedBox(height: 16),

              // ===== Hộp gợi ý + tạo ví =====
              CreateWalletBox(
                isLoggedIn: isLoggedIn,
                title: t.startAddingMoneyTitle,
                hint: t.startAddingMoneyHint,
                buttonText: t.createWallet,
                onCreate: () async {
                  if (!isLoggedIn) {
                    final go = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: Text(AppLocalizations.of(ctx)!.needLogin),
                        content:
                            Text(AppLocalizations.of(ctx)!.needLoginContent),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: Text(AppLocalizations.of(ctx)!.cancel),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: Text(AppLocalizations.of(ctx)!.login),
                          ),
                        ],
                      ),
                    );
                    if (go == true && context.mounted) {
                      Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const LoginPage()));
                    }
                    return;
                  }

                  final created = await showModalBottomSheet<bool>(
                    context: context,
                    isScrollControlled: true,
                    useSafeArea: true,
                    shape: const RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(20)),
                    ),
                    builder: (context) => Padding(
                      padding: EdgeInsets.only(
                          bottom: MediaQuery.of(context).viewInsets.bottom),
                      child: const CreateWalletForm(),
                    ),
                  );

                  if (created == true && mounted) {
                    await context.read<WalletProvider>().fetch();
                    safeShowSnackBar(
                      context,
                      const SnackBar(content: Text('Đã thêm nguồn thu')),
                    );
                  }
                },
              ),

              // ===== Danh sách ví/nguồn thu =====
              const SizedBox(height: 18),
              const Text('Nguồn thu của bạn',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              if (walletProv.loading && walletProv.items.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: LinearProgressIndicator(minHeight: 2),
                ),
              if (!walletProv.loading && walletProv.items.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(t.noData,
                      style: TextStyle(color: cs.onSurfaceVariant)),
                ),
              Column(
                children: walletProv.items.map((w) {
                  return _WalletCard(
                    name: w.name,
                    balanceText: _hideBalance ? '•••' : fmt(w.balance),
                    isDefault: w.isDefault == true,
                    icon: Icons.account_balance_wallet_rounded,
                    onEdit: () async {
                      final updated = await showModalBottomSheet<bool>(
                        context: context,
                        isScrollControlled: true,
                        useSafeArea: true,
                        shape: const RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.vertical(top: Radius.circular(20)),
                        ),
                        builder: (context) => Padding(
                          padding: EdgeInsets.only(
                            bottom: MediaQuery.of(context).viewInsets.bottom,
                          ),
                          child: EditWalletForm(
                            walletId: w.id,
                            initialName: w.name,
                            initialBalance: w.balance,
                          ),
                        ),
                      );
                      if (updated == true && mounted) {
                        await context.read<WalletProvider>().fetch();
                        safeShowSnackBar(
                          context,
                          const SnackBar(content: Text('Đã cập nhật ví')),
                        );
                      }
                    },
                  );
                }).toList(),
              ),

              const SizedBox(height: 18),

              // ===== Lịch sử giao dịch (recent) =====
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(t.transactionHistory,
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.w800)),
                  TextButton(
                    onPressed: () =>
                        Navigator.pushNamed(context, '/transactions'),
                    child: Text(
                      t.viewAll,
                      style: TextStyle(
                        color: cs.primary,
                        fontWeight: FontWeight.w700,
                        decoration: TextDecoration.underline,
                        decorationColor: cs.primary,
                      ),
                    ),
                  ),
                ],
              ),

              if (txProv.loadingRecent)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: LinearProgressIndicator(minHeight: 2),
                )
              else if (txProv.recent.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(t.noData,
                      style: TextStyle(color: cs.onSurfaceVariant)),
                )
              else
                Column(
                  children: txProv.recent.map((tx) {
                    final isOut = tx.type == 'chi';
                    final sign = isOut ? '-' : '+';
                    final color =
                        isOut ? const Color(0xFFD64545) : const Color(0xFF1F9D4C);
                    final dateStr =
                        DateFormat('dd/MM, HH:mm').format(tx.occurredAt);

                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 0),
                      leading: CircleAvatar(
                        backgroundColor: color.withOpacity(.15),
                        child: Icon(
                          isOut
                              ? Icons.call_made_rounded
                              : Icons.call_received_rounded,
                          color: color,
                        ),
                      ),
                      title: Text(
                        tx.categoryName ??
                            tx.walletName ??
                            (isOut ? 'Chi' : 'Thu'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        (tx.note?.isNotEmpty == true) ? tx.note! : dateStr,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Text(
                        '$sign${MoneyFormatter(moneySettings).format(tx.amount)}',
                        style:
                            TextStyle(fontWeight: FontWeight.w800, color: color),
                      ),
                      onTap: () =>
                          Navigator.pushNamed(context, '/transactions'),
                    );
                  }).toList(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ================== Widgets tách riêng ==================

class HeaderCard extends StatelessWidget {
  final String title, totalText, paymentText, trackingText;
  final bool loading, isHidden;
  final VoidCallback onToggleEye;

  const HeaderCard({
    super.key,
    required this.title,
    required this.totalText,
    required this.paymentText,
    required this.trackingText,
    required this.loading,
    required this.onToggleEye,
    required this.isHidden,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final headerBg = cs.primary;
    final headerTitleBg = cs.tertiaryContainer;
    final onHeader = cs.onPrimary;
    final onHeaderTitle = cs.onTertiaryContainer;

    return Container(
      decoration: BoxDecoration(
        color: headerBg,
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        children: [
          // Title + eye toggle
          Container(
            height: 56,
            decoration: BoxDecoration(
              color: headerTitleBg,
              borderRadius: BorderRadius.circular(16),
            ),
            alignment: Alignment.center,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: onHeaderTitle,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: onToggleEye,
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.all(6.0),
                    child: Icon(
                      isHidden ? Icons.visibility_off : Icons.visibility,
                      size: 18,
                      color: onHeaderTitle,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Big number
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Text(
              totalText,
              key: ValueKey(totalText),
              style: TextStyle(
                color: onHeader,
                fontSize: 36,
                fontWeight: FontWeight.w500,
                height: 1.25,
              ),
            ),
          ),

          if (loading) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(minHeight: 2),
          ],

          const SizedBox(height: 12),

          // Payment | Tracking row (Còn lại đã gộp)
          SizedBox(
            height: 44,
            child: Row(
              children: [
                Expanded(
                  child: _Col(
                    label: 'Đã chi',
                    value: paymentText,
                    color: onHeader,
                  ),
                ),
                Container(width: 1.5, height: 24, color: onHeader),
                Expanded(
                  child: _Col(
                    label: 'Còn lại',
                    value: trackingText,
                    color: onHeader,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Col extends StatelessWidget {
  final String label, value;
  final Color color;
  const _Col({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label,
              style: TextStyle(color: color, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(color: color, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class CreateWalletBox extends StatelessWidget {
  final bool isLoggedIn;
  final String title, hint, buttonText;
  final VoidCallback onCreate;

  const CreateWalletBox({
    super.key,
    required this.isLoggedIn,
    required this.title,
    required this.hint,
    required this.buttonText,
    required this.onCreate,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(blurRadius: 6, offset: Offset(0, 2), color: Colors.black12)
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        children: [
          Text(title,
              textAlign: TextAlign.center,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(hint,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black)),
          const SizedBox(height: 16),
          SizedBox(
            height: 48,
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    isLoggedIn ? cs.secondaryContainer : cs.surfaceVariant,
                foregroundColor:
                    isLoggedIn ? cs.onSecondaryContainer : cs.onSurfaceVariant,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: onCreate,
              icon: const Icon(Icons.add),
              label: Text(buttonText,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Thẻ hiển thị "Ví thanh toán"
class _WalletCard extends StatelessWidget {
  final String name;
  final String balanceText;
  final bool isDefault;
  final IconData icon;
  final VoidCallback onEdit;

  const _WalletCard({
    required this.name,
    required this.balanceText,
    required this.isDefault,
    required this.icon,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(blurRadius: 6, offset: Offset(0, 2), color: Colors.black12)
        ],
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Row(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: cs.secondaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  width: 48,
                  height: 48,
                  child: Icon(icon, color: cs.onSecondaryContainer),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w700),
                            ),
                          ),
                          if (isDefault)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: cs.secondaryContainer,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'Mặc định',
                                style: TextStyle(
                                  color: cs.onSecondaryContainer,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(balanceText,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            right: 4,
            top: 4,
            child: IconButton(
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Chỉnh sửa nguồn thu',
            ),
          ),
        ],
      ),
    );
  }
}
