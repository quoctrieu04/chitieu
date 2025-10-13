// lib/api/tx/tx_provider.dart
import 'package:flutter/foundation.dart';
import 'tx_model.dart';
import 'tx_service.dart';
import '../wallet/wallet_provider.dart';
import '../../core/budget/budgets_provider.dart';

class TxProvider with ChangeNotifier {
  final TxService api;
  final WalletProvider wallets;
  final BudgetsProvider budgets;

  TxProvider({
    required this.api,
    required this.wallets,
    required this.budgets,
  });

  // ===== Recent =====
  List<TxItem> _recent = [];
  bool _loadingRecent = false;

  List<TxItem> get recent => _recent;
  bool get loadingRecent => _loadingRecent;

  Future<void> fetchRecent({int limit = 5}) async {
    _loadingRecent = true;
    notifyListeners();
    try {
      _recent = await api.listRecent(limit: limit);
    } finally {
      _loadingRecent = false;
      notifyListeners();
    }
  }

  /// Tạo giao dịch.
  /// Nếu giao dịch đến từ khoản đã phân bổ (server trả categoryBudget != null)
  /// thì KHÔNG cập nhật ví để tránh trừ lần thứ 2.
  Future<void> create(TxRequest req) async {
    final resp = await api.create(req);

    final bool affectsWallet = (resp.categoryBudget == null);

    if (affectsWallet) {
      wallets.updateWalletBalance(
        resp.wallet.id,
        resp.wallet.balance,
        name: resp.wallet.name,
      );
    } else {
      if (kDebugMode) {
        print('[TxProvider] Skip wallet update (allocated budget).');
      }
    }

    // cập nhật quick snapshot budgets
    final cat = resp.categoryBudget;
    budgets.applyTxResponse({
      'summary': {
        'total_balance': resp.wallet.balance,
        'allocated': resp.summary.allocated,
        'unallocated': resp.summary.unallocated,
      },
      'categories': (cat == null)
          ? const []
          : [
              {
                'category_id': cat.categoryId,
                'category_name': '',
                'amount': cat.amount,
                'spent': cat.usedAmount,
              }
            ],
    });

    // Cập nhật danh sách recent (gọi lại nhanh)
    try {
      await fetchRecent(limit: 5);
    } catch (_) {}

    notifyListeners();
  }
}
