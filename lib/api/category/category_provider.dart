import 'dart:async';
import 'package:flutter/foundation.dart' hide Category;

import 'category_model.dart';
import 'category_service.dart';

class CategoryProvider with ChangeNotifier {
  final CategoryService service;
  CategoryProvider({required this.service});

  // ==== State chính ====
  final List<Category> _items = <Category>[];
  bool _loading = false;
  String? _error;

  List<Category> get items => List.unmodifiable(_items);
  bool get loading => _loading;
  String? get error => _error;

  // ==== (Tuỳ chọn) Thông tin ngân sách/summary để hiển thị nếu bạn cần ====
  // Nếu UI không dùng, vẫn có thể giữ đây để nhận update từ nơi khác.
  double _allocated = 0;
  double _unallocated = 0;
  final Map<int, double> _amountByCat = <int, double>{}; // category_id -> amount
  final Map<int, double> _usedByCat   = <int, double>{}; // category_id -> used

  double get allocated => _allocated;
  double get unallocated => _unallocated;
  double amountOf(int categoryId) => _amountByCat[categoryId] ?? 0;
  double usedOf(int categoryId)   => _usedByCat[categoryId] ?? 0;

  /// Xoá sạch dữ liệu khi chưa đăng nhập/đăng xuất
  void clear() {
    _items.clear();
    _loading = false;
    _error = null;
    _allocated = 0;
    _unallocated = 0;
    _amountByCat.clear();
    _usedByCat.clear();
    notifyListeners();
  }

  String _keyOf(Category c) => c.name.toLowerCase().trim();

  void _assign(List<Category> data) {
    final filtered = data.where((e) => e.name.trim().isNotEmpty).toList()
      ..sort((a, b) => _keyOf(a).compareTo(_keyOf(b)));
    _items
      ..clear()
      ..addAll(filtered);
  }

  Future<void> refresh() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final data = await service.getCategories()
          .timeout(const Duration(seconds: 12));
      if (kDebugMode) {
        for (final c in data) {
          if (c.name.trim().isEmpty) {
            debugPrint('[CategoryProvider] Invalid item (empty name): $c');
          }
        }
      }
      _assign(data);
    } on TimeoutException {
      _error = 'Không thể tải danh mục (quá thời gian).';
      if (kDebugMode) debugPrint(_error);
    } catch (e, st) {
      _error = 'Tải danh mục thất bại: $e';
      if (kDebugMode) debugPrint('Refresh categories failed: $e\n$st');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<Category> create(String name) async {
    try {
      final created = await service.createCategory(name);
      _items.add(created);
      _items.sort((a, b) => _keyOf(a).compareTo(_keyOf(b)));
      notifyListeners();
      return created;
    } catch (e, st) {
      if (kDebugMode) debugPrint('Create category failed: $e\n$st');
      rethrow;
    }
  }

  Future<Category> update({required int id, required String name}) async {
    try {
      final updated = await service.updateCategory(id: id, name: name);
      final i = _items.indexWhere((e) => e.id == id);
      if (i != -1) {
        _items[i] = updated;
        _items.sort((a, b) => _keyOf(a).compareTo(_keyOf(b)));
        notifyListeners();
      }
      return updated;
    } catch (e, st) {
      if (kDebugMode) debugPrint('Update category failed: $e\n$st');
      rethrow;
    }
  }

  Future<void> delete({required int id}) async {
    try {
      await service.deleteCategory(id);
      _items.removeWhere((e) => e.id == id);
      // đồng bộ map ngân sách (nếu có)
      _amountByCat.remove(id);
      _usedByCat.remove(id);
      notifyListeners();
    } catch (e, st) {
      if (kDebugMode) debugPrint('Delete category failed: $e\n$st');
      rethrow;
    }
  }

  // ========== Các hàm cập nhật ngân sách/summary (nếu nơi khác gọi) ==========
  void updateBudget(int categoryId, double amount, double used) {
    _amountByCat[categoryId] = amount;
    _usedByCat[categoryId] = used;
    notifyListeners();
  }

  void updateSummary(double allocated, double unallocated) {
    _allocated = allocated;
    _unallocated = unallocated;
    notifyListeners();
  }
}
