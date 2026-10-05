import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists small secrets (the client registration and tokens) between runs.
abstract class TokenStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// flutter_secure_storage: the Android Keystore on Android, and
/// DPAPI-encrypted storage on Windows.
///
/// On the web there is no equivalent. The package uses localStorage, and
/// encrypts each value with AES-GCM, but keeps the key unprotected beside
/// it, so that protects nothing: anything that can read the storage can
/// decrypt it. So on the web this holds only the client registration,
/// which isn't a secret, and the tokens stay in an [InMemoryTokenStore].
class SecureTokenStore implements TokenStore {
  const SecureTokenStore() : _storage = const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Keeps values only while the app runs: the web's token store, and
/// tests'.
class InMemoryTokenStore implements TokenStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}
