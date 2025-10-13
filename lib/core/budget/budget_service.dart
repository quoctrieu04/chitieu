import 'package:chitieu/auth/auth_service.dart';
import 'package:dio/dio.dart';

/// Service gọi API Laravel để làm việc với ngân sách (budgets)
class BudgetService {
  final Dio dio;
  final AuthService auth;

  BudgetService(this.dio, this.auth);

  /// Lấy ngân sách theo tháng/năm
  Future<Map<String, dynamic>> getBudgets({
    required int year,
    required int month,
  }) async {
    try {
      final res = await dio.get(
        '/budgets',
        queryParameters: {'year': year, 'month': month},
        options: await _authHeader(),
      );
      return Map<String, dynamic>.from(res.data);
    } on DioException catch (e) {
      _throwHttp(e, tag: 'getBudgets');
    }
  }

  /// Gán nhiều ngân sách một lúc
  /// body: { year, month, items: [ { category_id, amount } ] }
  Future<Map<String, dynamic>> assignMany({
    required int year,
    required int month,
    required List<Map<String, dynamic>> items,
  }) async {
    try {
      final sanitizedItems = items.map((it) {
        final amt = _toInt(it['amount']);
        final cid = _toInt(it['category_id']);
        return {'category_id': cid, 'amount': amt};
      }).toList();

      final res = await dio.post(
        '/budgets/assign-many',
        data: {
          'year': year,
          'month': month,
          'items': sanitizedItems,
        },
        options: await _authHeader(),
      );
      return Map<String, dynamic>.from(res.data);
    } on DioException catch (e) {
      _throwHttp(e, tag: 'assignMany');
    }
  }

  /// Gán một ngân sách duy nhất
  /// body: { year, month, category_id, amount }
  Future<Map<String, dynamic>> setOne({
    required int year,
    required int month,
    required int categoryId,
    required dynamic amount,
  }) async {
    try {
      final res = await dio.post(
        '/budgets/set',
        data: {
          'year': year,
          'month': month,
          'category_id': categoryId,
          'amount': _toInt(amount),
        },
        options: await _authHeader(),
      );
      return Map<String, dynamic>.from(res.data);
    } on DioException catch (e) {
      _throwHttp(e, tag: 'setOne');
    }
  }

  // --- helpers ---
  int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.round();
    final s = v?.toString() ?? '';
    final onlyDigits = s.replaceAll(RegExp(r'[^\d]'), '');
    return onlyDigits.isEmpty ? 0 : int.parse(onlyDigits);
  }

  Future<Options> _authHeader() async {
    final token = await auth.getToken();
    return Options(headers: {
      'Authorization': 'Bearer $token',
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    });
  }

  Never _throwHttp(DioException e, {required String tag}) {
    final code = e.response?.statusCode;
    final body = e.response?.data;
    // In ra console để debug dễ hơn
    // ignore: avoid_print
    print('[$tag] HTTP $code -> $body');
    if (code == 422) {
      throw Exception('Dữ liệu không hợp lệ: ${body?['errors'] ?? body}');
    } else if (code == 401) {
      throw Exception('Không có quyền (401). Kiểm tra Bearer token.');
    } else {
      throw Exception('HTTP $code: $body');
    }
  }
}
