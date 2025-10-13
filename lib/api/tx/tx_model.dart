// lib/api/tx/tx_model.dart
import 'package:intl/intl.dart';

String _formatYmdHms(DateTime dt) =>
    DateFormat('yyyy-MM-dd HH:mm:ss').format(dt.toLocal());

// ====== Helpers ======
double _toDouble(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  if (v is String) {
    var s = v.trim();
    s = s.replaceAll(RegExp(r'[^0-9,.\-]'), '');
    final hasDot = s.contains('.');
    final hasComma = s.contains(',');
    if (hasDot && hasComma) {
      final lastDot = s.lastIndexOf('.');
      final lastComma = s.lastIndexOf(',');
      final decimalIsComma = lastComma > lastDot;
      if (decimalIsComma) {
        s = s.replaceAll('.', '').replaceAll(',', '.');
      } else {
        s = s.replaceAll(',', '');
      }
    } else if (hasComma && !hasDot) {
      s = s.replaceAll(',', '.');
    }
    return double.tryParse(s) ?? 0;
  }
  return 0;
}

int _toInt(dynamic v) => _toDouble(v).round();

// ====== REQUEST ======
class TxRequest {
  /// UI truyền: 'thu' | 'chi'
  final String type;
  final int walletId;
  final int? categoryId; // required nếu type == 'chi'
  final int amount;      // đơn vị: đồng
  final DateTime txnTime;
  final String? note;

  TxRequest({
    required this.type,
    required this.walletId,
    this.categoryId,
    required this.amount,
    required this.txnTime,
    this.note,
  });

  Map<String, dynamic> toJson() {
    final ts = _formatYmdHms(txnTime);
    return {
      'type': type,
      'wallet_id': walletId,
      if (type == 'chi') 'category_id': categoryId,
      'amount': amount,
      'txn_time': ts,
      'occurred_at': ts,
      if (note != null && note!.isNotEmpty) 'note': note,
    };
  }
}

// ====== RESPONSE DTOs ======
class WalletDto {
  final int id;
  final String name;
  final double balance;

  WalletDto({required this.id, required this.name, required this.balance});

  factory WalletDto.fromJson(Map<String, dynamic> j) => WalletDto(
        id: _toInt(j['id']),
        name: (j['name'] ?? '').toString(),
        balance: _toDouble(j['balance']),
      );
}

class CategoryBudgetDto {
  final int categoryId;
  final double amount;
  final double usedAmount;

  CategoryBudgetDto({
    required this.categoryId,
    required this.amount,
    required this.usedAmount,
  });

  factory CategoryBudgetDto.fromJson(Map<String, dynamic> j) =>
      CategoryBudgetDto(
        categoryId: _toInt(j['category_id']),
        amount: _toDouble(j['amount']),
        usedAmount: _toDouble(j['used_amount']),
      );
}

class SummaryDto {
  final double allocated;
  final double unallocated;

  SummaryDto({required this.allocated, required this.unallocated});

  factory SummaryDto.fromJson(Map<String, dynamic> j) => SummaryDto(
        allocated: _toDouble(j['allocated']),
        unallocated: _toDouble(j['unallocated']),
      );
}

class TxResponse {
  final WalletDto wallet;
  final CategoryBudgetDto? categoryBudget;
  final SummaryDto summary;
  // giữ lại transaction trả về (id, amount, type, occurred_at, note, ...)
  final Map<String, dynamic>? transactionRaw;

  TxResponse({
    required this.wallet,
    required this.categoryBudget,
    required this.summary,
    this.transactionRaw,
  });

  factory TxResponse.fromJson(Map<String, dynamic> j) => TxResponse(
        wallet: WalletDto.fromJson(Map<String, dynamic>.from(j['wallet'] as Map)),
        categoryBudget: j['category_budget'] == null
            ? null
            : CategoryBudgetDto.fromJson(
                Map<String, dynamic>.from(j['category_budget'] as Map)),
        summary: SummaryDto.fromJson(
            Map<String, dynamic>.from(j['summary'] as Map)),
        transactionRaw: j['transaction'] == null
            ? null
            : Map<String, dynamic>.from(j['transaction'] as Map),
      );
}

// ====== RECENT ITEM (cho danh sách lịch sử) ======
class TxItem {
  final int id;
  final String type; // 'thu' | 'chi'
  final int walletId;
  final int? categoryId;
  final double amount;
  final DateTime occurredAt;
  final String? note;
  final String? walletName;
  final String? categoryName;

  TxItem({
    required this.id,
    required this.type,
    required this.walletId,
    this.categoryId,
    required this.amount,
    required this.occurredAt,
    this.note,
    this.walletName,
    this.categoryName,
  });

  factory TxItem.fromJson(Map<String, dynamic> j) => TxItem(
        id: _toInt(j['id']),
        type: (j['type'] ?? '').toString(),
        walletId: _toInt(j['wallet_id']),
        categoryId: j['category_id'] == null ? null : _toInt(j['category_id']),
        amount: _toDouble(j['amount']),
        occurredAt: DateTime.tryParse((j['occurred_at'] ?? '').toString()) ??
            DateTime.now(),
        note: (j['note'] ?? '').toString().isEmpty
            ? null
            : (j['note'] ?? '').toString(),
        walletName: (j['wallet_name'] ?? '').toString().isEmpty
            ? null
            : j['wallet_name'].toString(),
        categoryName: (j['category_name'] ?? '').toString().isEmpty
            ? null
            : j['category_name'].toString(),
      );
}
