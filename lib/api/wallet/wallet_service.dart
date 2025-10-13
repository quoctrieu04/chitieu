// lib/api/wallet/wallet_service.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'wallet_model.dart';

class WalletService {
  final String baseUrl; // ví dụ: http://192.168.1.67:8000/api
  final String token;   // Bearer token từ AuthProvider

  WalletService({required this.baseUrl, required this.token});

  Map<String, String> get _headers {
    final h = {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };
    if (token.isNotEmpty) {
      h['Authorization'] = 'Bearer $token';
    }
    return h;
  }

  // ================== Helpers ==================
  List<Map<String, dynamic>> _asListOfMap(dynamic json) {
    if (json is List) {
      return json.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    if (json is Map && json['data'] is List) {
      return (json['data'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    }
    return const [];
  }

  Map<String, dynamic>? _asSingleMap(dynamic json) {
    if (json is Map<String, dynamic>) return json;
    if (json is Map && json['data'] is Map) {
      return Map<String, dynamic>.from(json['data'] as Map);
    }
    if (json is List && json.isNotEmpty && json.first is Map) {
      return Map<String, dynamic>.from(json.first as Map);
    }
    return null;
  }

  // ================== API ==================

  /// GET /wallets
  Future<List<Wallet>> getWallets() async {
    if (token.isEmpty) throw Exception('Thiếu token xác thực');

    final url = Uri.parse('$baseUrl/wallets');
    if (kDebugMode) debugPrint('[REQ] GET $url');
    final res = await http.get(url, headers: _headers);

    if (kDebugMode) {
      debugPrint('[RES] ${res.statusCode} ${res.body.substring(0, res.body.length > 500 ? 500 : res.body.length)}');
    }

    if (res.statusCode != 200) {
      throw Exception('Lỗi lấy ví: ${res.statusCode} ${res.body}');
    }

    final decoded = jsonDecode(res.body);
    final list = _asListOfMap(decoded);
    if (list.isNotEmpty) {
      return list.map(Wallet.fromJson).toList(); // ✅ không đổi đơn vị ở đây
    }
    final one = _asSingleMap(decoded);
    if (one != null) return [Wallet.fromJson(one)];
    return const [];
  }

  /// POST /wallets
  Future<Wallet> createWallet(
    String name,
    double amount, {
    String currency = 'VND',
  }) async {
    if (token.isEmpty) throw Exception('Thiếu token xác thực');

    final url = Uri.parse('$baseUrl/wallets');
    final payload = {
      'name': name,
      'initial_amount': amount, // đơn vị đồng (không nhân 100)
      'currency': currency,
    };
    if (kDebugMode) debugPrint('[REQ] POST $url body=$payload');

    final res = await http.post(url, headers: _headers, body: jsonEncode(payload));
    if (kDebugMode) debugPrint('[RES] ${res.statusCode} ${res.body}');

    if (res.statusCode != 201 && res.statusCode != 200) {
      throw Exception('Lỗi tạo ví: ${res.statusCode} ${res.body}');
    }

    final decoded = jsonDecode(res.body);
    final map = _asSingleMap(decoded);
    if (map != null) return Wallet.fromJson(map);

    final list = _asListOfMap(decoded);
    if (list.isNotEmpty) return Wallet.fromJson(list.first);

    throw Exception('Phản hồi không hợp lệ khi tạo ví: $decoded');
  }

  /// PATCH /wallets/{id}
  Future<Wallet> updateWallet({
    required int id,
    required String name,
    required double balance,
    String? currency,
    double? initialAmount,
  }) async {
    if (token.isEmpty) throw Exception('Thiếu token xác thực');

    final url = Uri.parse('$baseUrl/wallets/$id');
    final body = <String, dynamic>{
      'name': name,
      'balance': balance, // đơn vị đồng
    };
    if (currency != null) body['currency'] = currency;
    if (initialAmount != null) body['initial_amount'] = initialAmount;

    if (kDebugMode) debugPrint('[REQ] PATCH $url body=$body');

    final res = await http.patch(url, headers: _headers, body: jsonEncode(body));
    if (kDebugMode) debugPrint('[RES] ${res.statusCode} ${res.body}');

    if (res.statusCode != 200) {
      throw Exception('Lỗi cập nhật ví: ${res.statusCode} ${res.body}');
    }

    final decoded = jsonDecode(res.body);
    final map = _asSingleMap(decoded);
    if (map != null) return Wallet.fromJson(map);

    throw Exception('Phản hồi không hợp lệ khi cập nhật ví: $decoded');
  }

  /// POST /wallets/{id}/default (tuỳ API của bạn)
  Future<void> makeDefault(int id) async {
    if (token.isEmpty) throw Exception('Thiếu token xác thực');

    final url = Uri.parse('$baseUrl/wallets/$id/default');
    if (kDebugMode) debugPrint('[REQ] POST $url');

    final res = await http.post(url, headers: _headers);
    if (kDebugMode) debugPrint('[RES] ${res.statusCode} ${res.body}');

    if (res.statusCode != 200 && res.statusCode != 204) {
      throw Exception('Lỗi đặt mặc định: ${res.statusCode} ${res.body}');
    }
  }

  /// DELETE /wallets/{id}
  Future<void> deleteWallet(int id) async {
    if (token.isEmpty) throw Exception('Thiếu token xác thực');

    final url = Uri.parse('$baseUrl/wallets/$id');
    if (kDebugMode) debugPrint('[REQ] DELETE $url');

    final res = await http.delete(url, headers: _headers);
    if (kDebugMode) debugPrint('[RES] ${res.statusCode} ${res.body}');

    if (res.statusCode != 200 && res.statusCode != 204) {
      throw Exception('Lỗi xoá ví: ${res.statusCode} ${res.body}');
    }
  }
}
