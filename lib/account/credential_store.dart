import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class CredentialStore {
  CredentialStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _emailKey = 'gvboard.email';
  static const _passwordKey = 'gvboard.password';
  static const _tokenKey = 'gvboard.token';
  static const _ossKey = 'gvboard.oss_id';
  static const _lastOnlineKey = 'gvboard.last_online_at';
  static const _apiKey = 'gvboard.api_id';

  final FlutterSecureStorage _storage;

  Future<
    ({
      String email,
      String password,
      String? token,
      String? ossId,
      String? apiId,
      int? lastOnlineAt,
    })?
  >
  read() async {
    final email = await _storage.read(key: _emailKey);
    final password = await _storage.read(key: _passwordKey);
    if (email == null ||
        password == null ||
        email.isEmpty ||
        password.isEmpty) {
      return null;
    }
    final rawLastOnline = await _storage.read(key: _lastOnlineKey);
    return (
      email: email,
      password: password,
      token: await _storage.read(key: _tokenKey),
      ossId: await _storage.read(key: _ossKey),
      apiId: await _storage.read(key: _apiKey),
      lastOnlineAt: int.tryParse(rawLastOnline ?? ''),
    );
  }

  Future<void> save({
    required String email,
    required String password,
    required String token,
    required String ossId,
    String? apiId,
    required int lastOnlineAt,
  }) async {
    await _storage.write(key: _emailKey, value: email);
    await _storage.write(key: _passwordKey, value: password);
    await _storage.write(key: _tokenKey, value: token);
    await _storage.write(key: _ossKey, value: ossId);
    if (apiId == null) {
      await _storage.delete(key: _apiKey);
    } else {
      await _storage.write(key: _apiKey, value: apiId);
    }
    await _storage.write(key: _lastOnlineKey, value: '$lastOnlineAt');
  }

  Future<void> clear() async {
    await Future.wait([
      _storage.delete(key: _emailKey),
      _storage.delete(key: _passwordKey),
      _storage.delete(key: _tokenKey),
      _storage.delete(key: _ossKey),
      _storage.delete(key: _apiKey),
      _storage.delete(key: _lastOnlineKey),
    ]);
  }

  Future<void> updatePassword(String password) async {
    await _storage.write(key: _passwordKey, value: password);
    await _storage.delete(key: _tokenKey);
  }
}
