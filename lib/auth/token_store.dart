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
/// On the web there is no equivalent. The package encrypts each value with
/// AES-GCM, but keeps the key unprotected beside it in the same browser
/// storage, so that protects nothing: anything that can read the storage
/// can decrypt it. What storage is used is what matters there, so pick it
/// with [SecureTokenStore.forSession] or [SecureTokenStore.persistent].
class SecureTokenStore implements TokenStore {
  /// On the web, sessionStorage: gone when the tab closes, and never
  /// shared with other tabs. Elsewhere the platform's secure storage.
  const SecureTokenStore.forSession()
    : _storage = const FlutterSecureStorage(
        webOptions: WebOptions(useSessionStorage: true),
      );

  /// On the web, localStorage: kept until cleared. Elsewhere the
  /// platform's secure storage.
  const SecureTokenStore.persistent() : _storage = const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class InMemoryTokenStore implements TokenStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}
