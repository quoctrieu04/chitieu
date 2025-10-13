double _numToDouble(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  if (v is String) {
    final s = v.trim()
        .replaceAll(RegExp(r'[^0-9,.\-]'), '') // giữ số, dấu âm, dấu , và .
        .replaceAll('.', '')                   // bỏ dấu chấm ngăn cách nghìn
        .replaceAll(',', '.');                 // còn lại dùng . làm thập phân
    return double.tryParse(s) ?? 0;
  }
  return 0;
}

class Wallet {
  final int id;
  final String name;
  final double initialAmount;
  final double balance;
  final String currency;
  final bool isDefault;

  Wallet({
    required this.id,
    required this.name,
    required this.initialAmount,
    required this.balance,
    required this.currency,
    this.isDefault = false,
  });

  /// Parse từ JSON
  factory Wallet.fromJson(Map<String, dynamic> j) => Wallet(
        id: j['id'] is int ? j['id'] : int.tryParse(j['id'].toString()) ?? 0,
        name: j['name']?.toString() ?? '',
        initialAmount: _numToDouble(j['initial_amount']),
        balance: _numToDouble(j['balance']),   // ✅ chuẩn hóa số
        currency: j['currency']?.toString() ?? 'VND',
        isDefault: j['is_default'] == 1 || j['is_default'] == true,
      );

  Wallet copyWith({
    int? id,
    String? name,
    double? initialAmount,
    double? balance,
    String? currency,
    bool? isDefault,
  }) {
    return Wallet(
      id: id ?? this.id,
      name: name ?? this.name,
      initialAmount: initialAmount ?? this.initialAmount,
      balance: balance ?? this.balance,
      currency: currency ?? this.currency,
      isDefault: isDefault ?? this.isDefault,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'initial_amount': initialAmount,
        'balance': balance,
        'currency': currency,
        'is_default': isDefault,
      };
}
