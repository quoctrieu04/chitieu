import 'dart:collection';
import 'package:flutter/foundation.dart';

import 'budget_model.dart';
import 'budget_service.dart';

class BudgetsProvider extends ChangeNotifier {
  final BudgetService service;
  BudgetsProvider(this.service);

  // ===== Generation guard để chống ghi đè state bởi request cũ =====
  int _gen = 0;
  void _bumpGen() => _gen++;

  final List<BudgetItem> _items = <BudgetItem>[];
  UnmodifiableListView<BudgetItem> get items => UnmodifiableListView(_items);

  String? _currentUserId;
  int? _currentYear;
  int? _currentMonth;

  String? get currentUserId => _currentUserId;
  int? get currentYear => _currentYear;
  int? get currentMonth => _currentMonth;

  bool loading = false;
  String? error;

  int _totalAssigned = 0;
  int get totalAssigned => _totalAssigned;

  int _totalBalance = 0;
  int _unallocated = 0;

  int get totalBalance => _totalBalance;
  int get unallocated => _unallocated;

  /// Gọi khi logout / chưa đăng nhập để xoá sạch dữ liệu cũ
  void clear() {
    _items.clear();
    _currentUserId = null;
    _currentYear = null;
    _currentMonth = null;
    loading = false;
    error = null;
    _totalAssigned = 0;
    _totalBalance = 0;
    _unallocated = 0;

    _bumpGen();        // 🔑 Hủy mọi request đang bay
    notifyListeners(); // 🔑 ép UI cập nhật ngay
  }

  /// Đổi phạm vi xem (user/year/month) -> hủy request cũ + làm trống dữ liệu
  void setScope({
    required String userId,
    required int year,
    required int month,
  }) {
    final changed = (_currentUserId != userId) ||
        (_currentYear != year) ||
        (_currentMonth != month);

    _currentUserId = userId;
    _currentYear = year;
    _currentMonth = month;

    if (changed) {
      _items.clear();
      error = null;
      loading = false;
      _bumpGen();      // 🔑 hủy mọi request cũ thuộc scope trước
      notifyListeners();
    }
  }

  Future<void> loadForMonth({
    required int year,
    required int month,
  }) async {
    _currentYear = year;
    _currentMonth = month;

    // Chụp thế hệ hiện tại để so sánh sau await
    final g = _gen;

    loading = true;
    error = null;
    notifyListeners();

    try {
      final res = await service.getBudgets(year: year, month: month);

      // Nếu state đã bị clear/reset trong lúc đợi API -> bỏ kết quả
      if (g != _gen) return;

      final data = (res['data'] as List?) ?? const [];
      _totalAssigned = (res['total_assigned'] as num?)?.toInt() ?? 0;

      _items
        ..clear()
        ..addAll(data.map((e) {
          final m = Map<String, dynamic>.from(e as Map);
          return BudgetItem.fromJson({
            'id': m['id'],
            'userId': m['user_id'],
            'categoryId': m['category_id'],
            'name': m['name'] ?? '',
            'year': m['year'],
            'month': m['month'],
            'amount': (m['amount'] as num?)?.toInt() ?? 0,
            // Fallback: API có thể trả "used_amount" thay vì "spent"
            'spent': (m['spent'] as num?)?.toInt() ??
                (m['used_amount'] as num?)?.toInt() ??
                0,
          });
        }));

      if (kDebugMode) {
        print('[Budgets] loadForMonth: ${_items.length} items, '
            'total_assigned=$_totalAssigned (y=$year, m=$month)');
      }
    } catch (e, st) {
      // Nếu đã đổi gen (ví dụ vừa clear()) thì bỏ lỗi vì state đã invalidated
      if (g != _gen) return;

      error = 'Không tải được ngân sách: $e';
      if (kDebugMode) {
        print('BudgetsProvider.loadForMonth error: $e\n$st');
      }
      _items.clear();
      _totalAssigned = 0;
    } finally {
      if (g == _gen) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> assignMany(DateTime dt, Map<int, double> map) async {
    _currentYear ??= dt.year;
    _currentMonth ??= dt.month;

    final g = _gen;

    final items = map.entries
        .map((e) => {'category_id': e.key, 'amount': e.value.round()})
        .toList();

    await service.assignMany(
      year: _currentYear!,
      month: _currentMonth!,
      items: items,
    );

    // Nếu trong lúc assign đã có reset -> dừng
    if (g != _gen) return;

    await loadForMonth(year: _currentYear!, month: _currentMonth!);
  }

  /// Nhận snapshot từ Tx (tạo/sửa giao dịch) để cập nhật nhanh UI
  void applyTxResponse(Map<String, dynamic> txRes, {int? year, int? month}) {
    try {
      // Nếu người dùng đã đổi tháng trong lúc đợi, đừng ghi đè tháng hiện tại
      if (year != null && month != null) {
        _currentYear = year;
        _currentMonth = month;
      }

      if (txRes.containsKey('summary')) {
        final s = Map<String, dynamic>.from(txRes['summary'] as Map);
        _totalBalance = (s['total_balance'] as num?)?.toInt() ?? _totalBalance;
        _totalAssigned = (s['allocated'] as num?)?.toInt() ?? _totalAssigned;
        _unallocated = (s['unallocated'] as num?)?.toInt() ?? _unallocated;
      }

      if (txRes.containsKey('categories')) {
        final list = (txRes['categories'] as List?) ?? const [];
        replaceFromCategoriesSnapshot(list);
      }

      notifyListeners();
    } catch (e, st) {
      if (kDebugMode) {
        print('BudgetsProvider.applyTxResponse error: $e\n$st');
      }
    }
  }

  void replaceFromCategoriesSnapshot(List categories) {
    _items
      ..clear()
      ..addAll(categories.map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        return BudgetItem.fromJson({
          'id': null,
          'userId': _currentUserId,
          'categoryId': m['category_id'],
          'name': m['category_name'] ?? '',
          'year': _currentYear,
          'month': _currentMonth,
          'amount': (m['amount'] as num?)?.toInt() ?? 0,
          'spent': (m['spent'] as num?)?.toInt() ??
              (m['used_amount'] as num?)?.toInt() ??
              0,
        });
      }));
  }

  Future<void> refreshCurrent() async {
    if (_currentYear != null && _currentMonth != null) {
      await loadForMonth(year: _currentYear!, month: _currentMonth!);
    }
  }

  void setAmountLocal(int categoryId, int amount) {
    final idx = _items.indexWhere((e) => e.categoryId == categoryId);
    if (idx >= 0) {
      _items[idx] = _items[idx].copyWith(amount: amount);
      _totalAssigned = _items.fold<int>(0, (sum, it) => sum + it.amount);
      notifyListeners();
    }
  }

  void setHeader({
    int? totalBalance,
    int? allocatedOrAssigned,
    int? unallocated,
  }) {
    if (totalBalance != null) _totalBalance = totalBalance;
    if (allocatedOrAssigned != null) _totalAssigned = allocatedOrAssigned;
    if (unallocated != null) _unallocated = unallocated;
    notifyListeners();
  }

  /// helper: lấy số đã tiêu của 1 category
  int spentOf(int categoryId) {
    final it = _items.firstWhere(
      (e) => e.categoryId == categoryId,
      orElse: () => BudgetItem(
        id: 0,
        userId: 0,
        categoryId: categoryId,
        year: _currentYear ?? 0,
        month: _currentMonth ?? 0,
        amount: 0,
        spent: 0,
      ),
    );
    return it.spent;
  }
}
