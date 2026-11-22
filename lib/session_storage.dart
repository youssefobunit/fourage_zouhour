import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Refresh tokens live in the OS credential store, not plain preferences.
class SecureSessionStorage extends LocalStorage {
  SecureSessionStorage(String projectUrl)
    : _key = 'sb-${Uri.parse(projectUrl).host.split('.').first}-auth-token';

  final String _key;
  static const _storage = FlutterSecureStorage();

  @override
  Future<void> initialize() async {
    final legacy = SharedPreferencesLocalStorage(persistSessionKey: _key);
    await legacy.initialize();
    // Require reauthentication instead of importing a potentially copied token.
    await legacy.removePersistedSession();
  }

  @override
  Future<bool> hasAccessToken() => _storage.containsKey(key: _key);
  @override
  Future<String?> accessToken() => _storage.read(key: _key);
  @override
  Future<void> persistSession(String persistSessionString) =>
      _storage.write(key: _key, value: persistSessionString);
  @override
  Future<void> removePersistedSession() => _storage.delete(key: _key);
}

/// Small non-secret settings that must survive restarting the app.
abstract final class SecureAppPreferences {
  static const _storage = FlutterSecureStorage();
  static const _dismissedUpdateKey = 'forage.dismissed_update_version.v1';

  static Future<String?> dismissedUpdateVersion() =>
      _storage.read(key: _dismissedUpdateKey);

  static Future<void> dismissUpdateVersion(String version) =>
      _storage.write(key: _dismissedUpdateKey, value: version);
}
