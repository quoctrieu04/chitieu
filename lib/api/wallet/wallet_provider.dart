import 'package:flutter/foundation.dart';

import 'wallet_model.dart';
import 'wallet_service.dart';

double _toDouble(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  if (v is String) {
    final s =
        v.trim().replaceAll(RegExp(r'[^0-9,.\-]'), '').replaceAll(',', '.');
    return double.tryParse(s) ?? 0;
  }
  return 0;
}

class WalletProvider extends ChangeNotifier {
  WalletService _service;
  WalletProvider({required WalletService service}) : _service = service;

  List<Wallet> _items = [];
  bool _loading = false;
  String? _error;

  List<Wallet> get items => _items;
  bool get loading => _loading;
  String? get error => _error;

  double get totalBalance {
    double sum = 0;
    for (final w in _items) {
      final v = _toDouble(w.balance);
      if (v.isFinite) sum += v;
    }
    return sum;
  }

  int? get defaultWalletId {
    try {
      return _items.firstWhere((w) => w.isDefault == true).id;
    } catch (_) {
      return null;
    }
  }

  Wallet? get defaultWallet {
    try {
      return _items.firstWhere((w) => w.isDefault == true);
    } catch (_) {
      return null;
    }
  }

  void updateToken(String token) {
    final t = (token == 'null') ? '' : token;
    _service = WalletService(baseUrl: _service.baseUrl, token: t);

    if (t.isEmpty) {
      reset();
    } else {
      notifyListeners();
    }
  }

  void clear() => reset();

  void reset() {
    _items = [];
    _loading = false;
    _error = null;
    notifyListeners();
  }

  Future<void> fetch() async {
    final hasToken = _service.token.isNotEmpty && _service.token != 'null';
    if (_loading || !hasToken) {
      if (!hasToken) reset();
      return;
    }

    _loading = true;
    _error = null;
    notifyListeners();

    try {
      _items = await _service.getWallets();
      for (final w in _items) {
        debugPrint('[WALLET_PROVIDER] fetch -> id=${w.id} name=${w.name} balance=${w.balance}');
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() => fetch();

  Future<bool> createWallet(String name, double amount) async {
    try {
      final w = await _service.createWallet(name, amount);
      _items.add(w);
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateWallet({
    required int id,
    required String name,
    required double balance,
  }) async {
    final idx = _items.indexWhere((w) => w.id == id);
    if (idx == -1) return false;

    final old = _items[idx];
    final optimistic = old.copyWith(name: name, balance: balance);
    _items[idx] = optimistic;
    notifyListeners();

    try {
      final updated = await _service.updateWallet(
        id: id,
        name: name,
        balance: balance,
      );
      _items[idx] = updated;
      notifyListeners();
      return true;
    } catch (e) {
      _items[idx] = old;
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  void updateWalletBalance(int id, double newBalance, {String? name}) {
    final idx = _items.indexWhere((w) => w.id == id);
    if (idx == -1) return;

    debugPrint('[WALLET_PROVIDER] updateWalletBalance BEFORE: id=$id current=${_items[idx].balance}');
    _items[idx] = _items[idx].copyWith(
      balance: newBalance,
      name: name ?? _items[idx].name,
    );
    debugPrint('[WALLET_PROVIDER] updateWalletBalance AFTER : id=$id new=${_items[idx].balance}');
    notifyListeners();
  }

  Future<bool> deleteWallet(int id) async {
    final idx = _items.indexWhere((w) => w.id == id);
    if (idx == -1) return false;

    final removed = _items[idx];
    _items.removeAt(idx);
    notifyListeners();

    try {
      await _service.deleteWallet(id);
      return true;
    } catch (e) {
      _items.insert(idx, removed);
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<void> makeDefault(int id) async {
    try {
      await _service.makeDefault(id);
      for (var i = 0; i < _items.length; i++) {
        _items[i] = _items[i].copyWith(isDefault: _items[i].id == id);
      }
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }
}
