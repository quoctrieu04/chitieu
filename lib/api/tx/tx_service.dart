// lib/api/tx/tx_service.dart
import 'package:dio/dio.dart';
import 'tx_model.dart';

class TxService {
  final Dio dio;
  TxService(this.dio);

  Future<TxResponse> create(TxRequest req) async {
    try {
      final body = req.toJson();
      // ignore: avoid_print
      print('POST /transactions => $body');

      final res = await dio.post(
        '/transactions',
        data: body,
        options: Options(
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
        ),
      );

      final code = res.statusCode ?? 0;
      if (code == 200 || code == 201) {
        final map = Map<String, dynamic>.from(res.data as Map);
        // ignore: avoid_print
        print('POST /transactions <= $map');
        return TxResponse.fromJson(map);
      }
      throw Exception('Unexpected status: $code ${res.data}');
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      final data = e.response?.data;
      // ignore: avoid_print
      print('TxService.create ERROR $code => $data');
      if (code == 422) {
        final msg = (data is Map && data['message'] != null)
            ? data['message'].toString()
            : data.toString();
        throw Exception('Dữ liệu không hợp lệ (422): $msg');
      }
      if (code == 401) {
        throw Exception('Không có quyền (401). Kiểm tra Bearer token.');
      }
      if (e.response != null) {
        throw Exception('API error: $code $data');
      }
      rethrow;
    }
  }

  /// Lấy danh sách giao dịch gần nhất
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
}
