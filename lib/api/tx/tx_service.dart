import 'package:dio/dio.dart';
import 'tx_model.dart';

class TxService {
  final Dio dio;
  TxService(this.dio);

  Future<TxResponse> create(TxRequest req) async {
    try {
      final body = req.toJson();
      final res = await dio.post(
        '/transactions',
        data: body,
        options: Options(
          headers: {'Accept': 'application/json', 'Content-Type': 'application/json'},
        ),
      );

      final code = res.statusCode ?? 0;
      if (code == 200 || code == 201) {
        final map = Map<String, dynamic>.from(res.data as Map);
        return TxResponse.fromJson(map);
      }
      throw Exception('Unexpected status: $code ${res.data}');
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      final data = e.response?.data;
      throw Exception('TxService.create error: $code $data');
    }
  }

  Future<List<TxItem>> listRecent({int limit = 5}) async {
    try {
      final res = await dio.get(
        '/transactions',
        queryParameters: {'limit': limit},
        options: Options(headers: {'Accept': 'application/json'}),
      );
      final code = res.statusCode ?? 0;
      if (code == 200) {
        final data = res.data;
        final list = (data is Map && data['data'] is List)
            ? (data['data'] as List)
            : (data as List);
        return list
            .map((e) => TxItem.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      }
      throw Exception('Unexpected status: $code ${res.data}');
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      final data = e.response?.data;
      throw Exception('GET /transactions error: $code $data');
    }
  }

  /// ===== Lọc theo ví, danh mục, tháng, loại =====
  Future<List<TxItem>> listByFilter({
    String? walletId,
    String? categoryId,
    int limit = 100,
    DateTime? from,
    DateTime? to,
    String? type,
  }) async {
    try {
      final qp = <String, dynamic>{
        'limit': limit,
        if (walletId != null) 'walletId': walletId,
        if (categoryId != null) 'categoryId': categoryId,
        if (type != null) 'type': type,
        if (from != null) 'from': from.toIso8601String(),
        if (to != null) 'to': to.toIso8601String(),
      };

      final res = await dio.get(
        '/transactions',
        queryParameters: qp,
        options: Options(headers: {'Accept': 'application/json'}),
      );

      final code = res.statusCode ?? 0;
      if (code == 200) {
        final data = res.data;
        final list = (data is Map && data['data'] is List)
            ? (data['data'] as List)
            : (data as List);
        return list
            .map((e) => TxItem.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      }
      throw Exception('Unexpected status: $code ${res.data}');
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      final data = e.response?.data;
      throw Exception('GET /transactions (filter) error: $code $data');
    }
  }
}
