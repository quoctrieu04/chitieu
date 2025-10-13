import 'package:flutter/foundation.dart';
import 'auth_service.dart';

class AuthProvider extends ChangeNotifier {
  final AuthService api; // dùng duy nhất instance này
  AuthProvider(this.api);

  Map<String, dynamic>? _user;
  Map<String, dynamic>? get user => _user;

  String? _token;
  String? get token => _token;

  bool get isAuthenticated => _token != null && _token!.isNotEmpty;

  // UI states
  bool loading = false;
  String? error;
  bool updatingName = false;
  bool changingPassword = false;

  /// Khởi động: NẠP token đã lưu (không xoá) và thử lấy hồ sơ
  Future<void> bootstrap() async {
    try {
      // 1) Đọc token từ storage
      _token = await AuthService.readToken();

      // 2) Nếu có token → gọi me() để có user cho UI
      if (_token != null && _token!.isNotEmpty) {
        try {
          _user = await api.me();
        } catch (e) {
          if (kDebugMode) print('Bootstrap me() error: $e');
          // token có thể hết hạn, coi như chưa đăng nhập
          _user = null;
        }
      } else {
        _user = null;
      }
      error = null;
    } catch (e) {
      if (kDebugMode) print('Bootstrap error: $e');
      _user = null;
      _token = null;
    }
    notifyListeners();
  }

  /// Làm mới hồ sơ
  Future<void> refresh() async {
    if (!isAuthenticated) return;
    try {
      _user = await api.me();
      notifyListeners();
    } catch (e) {
      if (kDebugMode) print('Refresh error: $e');
    }
  }

  /// Đăng nhập
  Future<bool> login(String email, String pass) async {
    loading = true;
    error = null;
    notifyListeners();

    try {
      // AuthService.login() trả về object user và TỰ lưu token vào SecureStorage
      final res = await api.login(email, pass);

      // Lấy token từ AuthService (đã lưu ở login)
      _token = await api.getToken();

      if (!isAuthenticated) {
        error = 'Không nhận được token từ máy chủ';
        _user = null;
        return false;
      }

      // res là user map
      _user = Map<String, dynamic>.from(res);
      error = null;
      return true;
    } catch (e) {
      if (kDebugMode) print('Login error: $e');
      error = 'Đăng nhập thất bại';
      _user = null;
      _token = null;
      return false;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// Đăng ký
  Future<bool> register(String name, String email, String pass) async {
    loading = true;
    error = null;
    notifyListeners();

    try {
      // AuthService.register() trả về user và có thể lưu token nếu backend trả token
      final res = await api.register(name, email, pass);

      // Nếu backend không auto-login, getToken() sẽ là null/empty
      _token = await api.getToken();

      if (!isAuthenticated) {
        // backend không trả token → yêu cầu user đăng nhập lại
        _user = null;
        return false;
      }

      _user = Map<String, dynamic>.from(res);
      error = null;
      return true;
    } catch (e) {
      if (kDebugMode) print('Register error: $e');
      error = 'Đăng ký thất bại';
      _user = null;
      _token = null;
      return false;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// Đăng xuất
  Future<void> logout() async {
    try {
      await api.logout();
    } catch (e) {
      if (kDebugMode) print('Logout error: $e');
    }
    await AuthService.clearToken();
    _user = null;
    _token = null;
    error = null;
    notifyListeners();
  }

  /// Cập nhật tên
  Future<bool> updateName(String newName) async {
    if (!isAuthenticated) return false;
    updatingName = true;
    notifyListeners();
    try {
      final updated = await api.updateName(newName);
      if (updated == null) return false;
      _user = {...?_user, ...updated};
      error = null;
      return true;
    } catch (e) {
      if (kDebugMode) print('UpdateName error: $e');
      return false;
    } finally {
      updatingName = false;
      notifyListeners();
    }
  }

  /// Đổi mật khẩu
  Future<bool> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    if (!isAuthenticated) return false;
    changingPassword = true;
    notifyListeners();
    try {
      return await api.changePassword(
        oldPassword: oldPassword,
        newPassword: newPassword,
      );
    } catch (e) {
      if (kDebugMode) print('ChangePassword error: $e');
      return false;
    } finally {
      changingPassword = false;
      notifyListeners();
    }
  }
}
