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
  Future<void> create(TxRequest req) async {
    final resp = await api.create(req);

    final bool affectsWallet = (resp.categoryBudget == null);
    if (affectsWallet) {
      wallets.updateWalletBalance(
        resp.wallet.id,
        resp.wallet.balance,
        name: resp.wallet.name,
      );
    } else if (kDebugMode) {
      print('[TxProvider] Skip wallet update (allocated budget).');
    }

    // cập nhật ngân sách nhanh
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

    // cập nhật danh sách recent
    try {
      await fetchRecent(limit: 5);
    } catch (_) {}

    notifyListeners();
  }

  // ===================================================================
  // ==================  LỌC THEO BỘ LỌC + THÁNG  ======================
  // ===================================================================

  bool loadingFiltered = false;
  List<TxItem> filtered = [];

  void clearFiltered() {
    filtered = [];
    loadingFiltered = false;
    notifyListeners();
  }

  /// Lấy danh sách giao dịch theo bộ lọc (ví, danh mục, tháng, loại)
  Future<void> fetchByFilter({
    String? walletId,
    String? categoryId,
    int limit = 100,
    String? type, // 'thu' | 'chi'
    int? year,
    int? month,
  }) async {
    loadingFiltered = true;
    notifyListeners();

    try {
      // === Tính khoảng thời gian theo tháng ===
      DateTime? from;
      DateTime? to;
      if (year != null && month != null) {
        from = DateTime(year, month, 1);
        final nextMonth = (month == 12)
            ? DateTime(year + 1, 1, 1)
            : DateTime(year, month + 1, 1);
        to = nextMonth.subtract(const Duration(seconds: 1));
      }

      // === Gọi API (có thể lọc chưa đủ) ===
      final list = await api.listByFilter(
        walletId: walletId,
        categoryId: categoryId,
        limit: limit,
        type: type,
        from: from,
        to: to,
      );

      // === Lọc cục bộ BẮT BUỘC (type + id + khoảng thời gian) ===
      final wl = walletId?.toString();
      final cl = categoryId?.toString();

      filtered = list.where((tx) {
        // 1) Loại giao dịch
        if (type != null && tx.type != type) return false;

        // 2) Theo ví (nếu truyền)
        if (wl != null) {
          final txW = tx.walletId?.toString();
          if (txW != wl) return false;
        }

        // 3) Theo danh mục (nếu truyền)
        if (cl != null) {
          final txC = tx.categoryId?.toString();
          if (txC != cl) return false;
        }

        // 4) Theo tháng (nếu truyền)
        if (from != null && to != null) {
          final d = tx.occurredAt;
          if (d.isBefore(from) || d.isAfter(to)) return false;
        }
        return true;
      }).toList()
        // Sắp xếp mới nhất trước
        ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    } catch (e) {
      if (kDebugMode) {
        print('[TxProvider] fetchByFilter error: $e');
      }
      filtered = [];
    } finally {
      loadingFiltered = false;
      notifyListeners();
    }
  }
}
