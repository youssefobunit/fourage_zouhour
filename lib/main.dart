// this relase is v1.1.4
// hello world
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show compute, listEquals, setEquals;
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as image;
import 'package:path/path.dart' show join;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:cryptography/cryptography.dart';
import 'package:excel_plus/excel_plus.dart' as xlsx;
import 'package:file_saver/file_saver.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'cloud_sync_client.dart';
import 'device_identity.dart';
import 'session_storage.dart';
import 'security_config.dart';
import 'security_activity_page.dart';

part 'catalog_and_filters.dart';
part 'atelier_glass.dart';
part 'atelier_liquid.dart';

late final DeviceIdentity appDevice;

/// The hosted project remains the safe fallback.  A self-hosted test or
/// production server is selected only by passing SUPABASE_URL and
/// SUPABASE_PUBLISHABLE_KEY when building/running the application.
const _supabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'https://jomxwvuackengasnteeq.supabase.co',
);
const _supabasePublishableKey = String.fromEnvironment(
  'SUPABASE_PUBLISHABLE_KEY',
  defaultValue: 'sb_publishable_Yo7doKg9rULQ4Cd6JH_qhA_wQxELhnL',
);
// Detailed server/database errors are opt-in for development only.
const _showStartupDiagnostics = bool.fromEnvironment(
  'FORAGE_DIAGNOSTICS',
  defaultValue: false,
);
const _localDatabaseName = String.fromEnvironment(
  'FORAGE_DATABASE_NAME',
  // v2 avoids opening an older on-device database containing an oversized
  // photo that Android cannot read. The cloud workspace is restored on launch.
  defaultValue: 'forage-v2.db',
);
const _appVersion = '1.1.0+18';
const _githubLatestRelease =
    'https://api.github.com/repos/youssefobunit/fourage_zouhour/releases/latest';
// This identity is also verified by Supabase in the owner migration.
const _maintenanceOwnerEmail = 'owner@younes.com';

class AppUpdate {
  const AppUpdate({required this.version, required this.downloadUrl});
  final String version;
  final String downloadUrl;
}

abstract final class GitHubUpdates {
  static Future<AppUpdate?> check() async {
    if (!Platform.isAndroid) return null;
    try {
      final request = await HttpClient().getUrl(
        Uri.parse(_githubLatestRelease),
      );
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/vnd.github+json',
      );
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'FORAGE-ZOUHOUR/$_appVersion',
      );
      final response = await request.close().timeout(
        const Duration(seconds: 8),
      );
      if (response.statusCode != 200) return null;
      final data = jsonDecode(await utf8.decoder.bind(response).join()) as Map;
      final tag = data['tag_name']?.toString() ?? '';
      final assets = (data['assets'] as List? ?? const []);
      final apk = assets.cast<Map>().firstWhere(
        (asset) =>
            asset['name']?.toString().toLowerCase().endsWith('.apk') == true,
        orElse: () => const {},
      );
      final url = apk['browser_download_url']?.toString();
      if (url == null ||
          !isTrustedUpdateUrl(url) ||
          !_isNewer(tag, _appVersion)) {
        return null;
      }
      return AppUpdate(
        version: tag.replaceFirst(RegExp('^[vV]'), ''),
        downloadUrl: url,
      );
    } catch (_) {
      return null;
    }
  }

  static bool _isNewer(String remote, String current) {
    List<int> parts(String value) =>
        RegExp(r'\d+')
            .allMatches(value)
            .map((match) => int.parse(match.group(0)!))
            .toList();
    final a = parts(remote);
    final b = parts(current);
    for (var i = 0; i < max(a.length, b.length); i++) {
      final left = i < a.length ? a[i] : 0;
      final right = i < b.length ? b[i] : 0;
      if (left != right) return left > right;
    }
    return false;
  }
}

// Android CursorWindow cannot read a database row containing multi-megabyte
// photos. Keep every stored image small enough for a row with several photos.
Uint8List compactImageForStorage(Uint8List bytes) {
  const maximumBytes = 120 * 1024;
  if (bytes.lengthInBytes <= maximumBytes) return bytes;
  final decoded = image.decodeImage(bytes);
  if (decoded == null) return bytes;
  Uint8List? last;
  for (final setting in const [
    (800, 70),
    (640, 60),
    (512, 55),
    (400, 48),
    (320, 42),
  ]) {
    final maxSide = setting.$1;
    final scale = decoded.width > decoded.height
        ? maxSide / decoded.width
        : maxSide / decoded.height;
    final resized = scale < 1
        ? image.copyResize(
            decoded,
            width: (decoded.width * scale).round(),
            height: (decoded.height * scale).round(),
          )
        : decoded;
    last = Uint8List.fromList(image.encodeJpg(resized, quality: setting.$2));
    if (last.lengthInBytes <= maximumBytes) return last;
  }
  return last ?? bytes;
}

String compactImageListJson(String value) {
  try {
    final images = (jsonDecode(value) as List)
        .whereType<String>()
        .map((item) => base64Encode(compactImageForStorage(base64Decode(item))))
        .toList();
    return jsonEncode(images);
  } catch (_) {
    return value;
  }
}

Future<String> passwordFromPattern(String email, List<int> pattern) async {
  final digest = await Sha256().hash(
    utf8.encode(
      'forage-pattern-v1:${email.trim().toLowerCase()}:${pattern.join()}',
    ),
  );
  return 'Fz1!${base64UrlEncode(digest.bytes).replaceAll('=', '')}a';
}

/// Refuses new oversized photos before they reach SQLite or Supabase.
Future<Uint8List?> readAcceptedImage(
  XFile file, {
  required int maximumBytes,
}) async {
  final bytes = await file.readAsBytes();
  return bytes.lengthInBytes <= maximumBytes ? bytes : null;
}

abstract final class SupabaseAccounts {
  static SupabaseClient get _client => Supabase.instance.client;
  static String? _loginNonce;

  static String _newLoginNonce() =>
      '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';

  static void _beginDeviceLogin() {
    _loginNonce = _newLoginNonce();
    _client.headers = {
      ..._client.headers,
      'x-forage-device-id': appDevice.id,
      'x-forage-login-nonce': _loginNonce!,
    };
  }

  static Future<List<AppUser>> loadUsers() async {
    final rows = await _client
        .from('profiles')
        .select()
        .order('full_name', ascending: true);
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(_fromProfile)
        .toList();
  }

  static Future<AppUser?> currentUser() async {
    final authUser = _client.auth.currentUser;
    if (authUser == null) return null;
    final row = await _client
        .from('profiles')
        .select()
        .eq('id', authUser.id)
        .maybeSingle();
    return row == null ? null : _fromProfile(row);
  }

  static Future<LoginResult> signIn(String email, String password) async {
    try {
      if (email.length > 254 || password.isEmpty || password.length > 128) {
        return const LoginResult.failure(LoginFailure.invalidCredentials);
      }
      final response = await _client.auth.signInWithPassword(
        email: email.trim().toLowerCase(),
        password: password,
      );
      if (response.user == null) {
        return const LoginResult.failure(LoginFailure.invalidCredentials);
      }
      _beginDeviceLogin();
      final user = await currentUser();
      if (user == null || !user.canLogIn) {
        await _client.auth.signOut();
        return const LoginResult.failure(LoginFailure.inactiveAccount);
      }
      final access = await _requestDeviceAccess();
      final status = access is Map ? access['status']?.toString() : null;
      switch (status) {
        case 'approved':
          await _recordDeviceLogin();
          return LoginResult.success(user);
        case 'outside_schedule':
          await _client.auth.signOut();
          return const LoginResult.failure(LoginFailure.outsideSchedule);
        case 'rejected':
          await _client.auth.signOut();
          return const LoginResult.failure(LoginFailure.deviceRejected);
        default:
          // Keep this short-lived authentication session while the request is
          // pending, so this screen can poll for the administrator's decision.
          return const LoginResult.failure(LoginFailure.devicePending);
      }
    } on AuthException catch (error) {
      await _clearFailedLogin();
      if (error.statusCode == '429') {
        return const LoginResult.failure(LoginFailure.temporarilyLocked);
      }
      return const LoginResult.failure(LoginFailure.invalidCredentials);
    } on PostgrestException catch (error) {
      await _clearFailedLogin();
      if (error.code == 'PGRST202') {
        return const LoginResult.failure(LoginFailure.serverSetupRequired);
      }
      return const LoginResult.failure(LoginFailure.serviceUnavailable);
    } catch (_) {
      await _clearFailedLogin();
      // A missing database function, a profile not yet created, or a network
      // outage must be reported in the login form instead of silently
      // returning the button to its idle state.
      return const LoginResult.failure(LoginFailure.serviceUnavailable);
    }
  }

  static Future<LoginResult> checkPendingDeviceLogin() async {
    final authUser = _client.auth.currentUser;
    if (authUser == null) {
      return const LoginResult.failure(LoginFailure.invalidCredentials);
    }
    if (_loginNonce == null) _beginDeviceLogin();
    final access = await _requestDeviceAccess();
    final status = access is Map ? access['status']?.toString() : null;
    if (status == 'approved') {
      final user = await currentUser();
      await _recordDeviceLogin();
      return user == null
          ? const LoginResult.failure(LoginFailure.invalidCredentials)
          : LoginResult.success(user);
    }
    if (status == 'rejected') {
      await _client.auth.signOut();
      return const LoginResult.failure(LoginFailure.deviceRejected);
    }
    if (status == 'outside_schedule') {
      await _client.auth.signOut();
      return const LoginResult.failure(LoginFailure.outsideSchedule);
    }
    return const LoginResult.failure(LoginFailure.devicePending);
  }

  static Future<void> _clearFailedLogin() async {
    _loginNonce = null;
    try {
      await _client.auth.signOut(scope: SignOutScope.local);
    } catch (_) {
      // The original sign-in failure still needs to be reported offline.
    }
  }

  static Future<LoginResult> resumeCurrentSession() async {
    if (_client.auth.currentUser == null) {
      return const LoginResult.failure(LoginFailure.invalidCredentials);
    }
    _beginDeviceLogin();
    final user = await currentUser();
    if (user == null || !user.canLogIn) {
      await _client.auth.signOut();
      return const LoginResult.failure(LoginFailure.inactiveAccount);
    }
    final access = await _requestDeviceAccess();
    final status = access is Map ? access['status']?.toString() : null;
    if (status == 'approved') return LoginResult.success(user);
    if (status == 'outside_schedule') {
      await _client.auth.signOut();
      return const LoginResult.failure(LoginFailure.outsideSchedule);
    }
    if (status == 'rejected') {
      await _client.auth.signOut();
      return const LoginResult.failure(LoginFailure.deviceRejected);
    }
    return const LoginResult.failure(LoginFailure.devicePending);
  }

  static Future<dynamic> _requestDeviceAccess() => _client.rpc(
    'request_device_access',
    params: {
      'p_device_id': appDevice.id,
      'p_device_label': appDevice.label,
      'p_login_nonce': _loginNonce,
    },
  );

  static Future<void> signOut() async {
    try {
      await _client.rpc('record_forage_device_logout');
    } catch (_) {}
    _loginNonce = null;
    await _client.auth.signOut();
  }

  static Future<void> _recordDeviceLogin() => _client.rpc(
    'record_forage_device_login',
    params: {'p_label': appDevice.label, 'p_nonce': _loginNonce ?? ''},
  );

  static Future<void> updateUser(AppUser user) async {
    if (user.password.isNotEmpty) {
      await _resetUserPassword(user.id, user.password);
    }
    await _client
        .from('profiles')
        .update({
          'full_name': user.fullName,
          'username': user.username,
          'role': user.effectiveRole.name,
          'status': switch (user.status) {
            UserStatus.active => 'active',
            UserStatus.onLeave => 'on_leave',
            UserStatus.dismissed => 'dismissed',
          },
          'allowed_pages': user.allowedPages.map((page) => page.name).toList(),
          'writable_pages': user.writablePages
              .map((page) => page.name)
              .toList(),
          'can_export': user.canExport,
          'login_start_time': user.loginStartTime,
          'login_end_time': user.loginEndTime,
        })
        .eq('id', user.id);
  }

  static Future<void> _resetUserPassword(String userId, String password) async {
    final token = _client.auth.currentSession?.accessToken;
    if (token == null) {
      throw StateError('La session administrateur a expiré.');
    }
    final request = await HttpClient().postUrl(
      Uri.parse('$_supabaseUrl/functions/v1/admin-reset-user-password'),
    );
    request.headers
      ..contentType = ContentType.json
      ..set('apikey', _supabasePublishableKey)
      ..set(HttpHeaders.authorizationHeader, 'Bearer $token');
    request.add(
      utf8.encode(jsonEncode({'userId': userId, 'password': password})),
    );
    final response = await request.close();
    final raw = await utf8.decoder.bind(response).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final payload = raw.isEmpty ? null : jsonDecode(raw);
      final reason = payload is Map ? payload['error']?.toString() : null;
      throw StateError(reason ?? 'Impossible de modifier le mot de passe.');
    }
  }

  /// The service role key stays in the Edge Function. The mobile application
  /// sends only the new member details with the administrator's normal
  /// session token.
  static Future<AppUser> createUser(AppUser draft) async {
    try {
      final token = _client.auth.currentSession?.accessToken;
      if (token == null) {
        throw StateError('La session administrateur a expiré.');
      }
      final request = await HttpClient().postUrl(
        Uri.parse('$_supabaseUrl/functions/v1/admin-create-user'),
      );
      request.headers
        ..contentType = ContentType.json
        ..set('apikey', _supabasePublishableKey)
        ..set(HttpHeaders.authorizationHeader, 'Bearer $token');
      request.add(
        utf8.encode(
          jsonEncode({
            'fullName': draft.fullName,
            'email': draft.email,
            'username': draft.username,
            'password': draft.password,
            'role': draft.effectiveRole.name,
            'allowedPages': draft.allowedPages
                .map((page) => page.name)
                .toList(),
            'writablePages': draft.writablePages
                .map((page) => page.name)
                .toList(),
          }),
        ),
      );
      final response = await request.close();
      final raw = await utf8.decoder.bind(response).join();
      final data = raw.isEmpty ? null : jsonDecode(raw);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final reason = data is Map ? data['error']?.toString() : null;
        throw StateError(reason ?? 'Erreur serveur (${response.statusCode}).');
      }
      if (data is! Map || data['profile'] is! Map) {
        throw const FormatException('Réponse serveur invalide.');
      }
      return _fromProfile(Map<String, dynamic>.from(data['profile'] as Map));
    } on StateError {
      rethrow;
    } catch (error) {
      throw StateError('Impossible de créer cet utilisateur : $error');
    }
  }

  static Future<List<DeviceAccessRequest>> pendingDeviceRequests() async {
    final rows = await _client
        .from('device_access_requests')
        .select('id, user_id, device_id, device_label, requested_at')
        .eq('status', 'pending')
        .order('requested_at', ascending: true);
    return (rows as List).cast<Map<String, dynamic>>().map((row) {
      return DeviceAccessRequest(
        id: row['id'] as String,
        userId: row['user_id'] as String,
        userLabel: row['user_id'] as String,
        deviceId: row['device_id'] as String,
        deviceLabel: row['device_label'] as String? ?? 'Appareil inconnu',
        requestedAt: DateTime.parse(row['requested_at'] as String).toLocal(),
      );
    }).toList();
  }

  static Future<void> decideDeviceRequest(
    DeviceAccessRequest request, {
    required bool approve,
    bool makePrimary = false,
  }) async {
    await _client.rpc(
      'decide_device_access_request',
      params: {
        'p_request_id': request.id,
        'p_approve': approve,
        'p_make_primary': makePrimary,
      },
    );
  }

  static Future<List<TrustedDevice>> trustedDevices() async {
    final rows = await _client.rpc('list_forage_device_activity');
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(TrustedDevice.fromRow)
        .toList();
  }

  static Future<void> setDeviceStatus(String id, String status) => _client.rpc(
    'set_forage_device_status',
    params: {'p_device_id': id, 'p_status': status},
  );

  static AppUser _fromProfile(Map<String, dynamic> row) {
    final email = (row['email'] as String? ?? '').trim();
    final username = (row['username'] as String?)?.trim();
    final roleName = row['role'] as String? ?? UserRole.visitor.name;
    final role =
        UserRole.values.where((value) => value.name == roleName).firstOrNull ??
        UserRole.visitor;
    final allowedPages = _pages(row['allowed_pages']);
    final writablePages = _pages(row['writable_pages']);
    final status = switch (row['status'] as String?) {
      'on_leave' => UserStatus.onLeave,
      'dismissed' => UserStatus.dismissed,
      _ => UserStatus.active,
    };
    return AppUser(
      id: row['id'] as String,
      username: username?.isNotEmpty == true
          ? username!
          : (email.isEmpty ? 'utilisateur' : email.split('@').first),
      password: '',
      email: email,
      fullName: (row['full_name'] as String?)?.trim().isNotEmpty == true
          ? (row['full_name'] as String).trim()
          : email,
      admin: role == UserRole.admin,
      role: role,
      roles: {role},
      allowedPages: row['allowed_pages'] == null ? null : allowedPages,
      writablePages: row['writable_pages'] == null ? null : writablePages,
      status: status,
      canExport: row['can_export'] == true,
      loginStartTime: row['login_start_time'] as String?,
      loginEndTime: row['login_end_time'] as String?,
      isPrivateOwner:
          email.toLowerCase() == _maintenanceOwnerEmail &&
          role == UserRole.admin &&
          status == UserStatus.active,
    );
  }

  static Set<AppPage> _pages(Object? raw) {
    if (raw is! List) return {};
    return raw
        .map((value) => value.toString())
        .map(
          (name) =>
              AppPage.values.where((page) => page.name == name).firstOrNull,
        )
        .whereType<AppPage>()
        .toSet();
  }
}

class DeviceAccessRequest {
  const DeviceAccessRequest({
    required this.id,
    required this.userId,
    required this.userLabel,
    required this.deviceId,
    required this.deviceLabel,
    required this.requestedAt,
  });

  final String id;
  final String userId;
  final String userLabel;
  final String deviceId;
  final String deviceLabel;
  final DateTime requestedAt;
}

class TrustedDevice {
  const TrustedDevice({
    required this.id,
    required this.userId,
    required this.label,
    required this.primary,
    required this.status,
    required this.email,
    this.lastLoginAt,
    this.lastLogoutAt,
  });
  factory TrustedDevice.fromRow(Map<String, dynamic> row) => TrustedDevice(
    id: row['id'] as String,
    userId: row['user_id'] as String,
    label: row['device_label'] as String? ?? 'Appareil inconnu',
    primary: row['is_primary'] == true,
    status: row['access_status'] as String? ?? 'active',
    email: row['email'] as String? ?? '',
    lastLoginAt: row['last_login_at'] == null
        ? null
        : DateTime.parse(row['last_login_at'] as String).toLocal(),
    lastLogoutAt: row['last_logout_at'] == null
        ? null
        : DateTime.parse(row['last_logout_at'] as String).toLocal(),
  );
  final String id;
  final String userId;
  final String label;
  final bool primary;
  final String status;
  final String email;
  final DateTime? lastLoginAt;
  final DateTime? lastLogoutAt;
}

abstract final class AppPalette {
  static const primary = Color(0xFF167CE3);
  static const primaryDark = Color(0xFF075DBA);
  static const secondary = Color(0xFF4B91F2);
  static const soft = Color(0xFFF0F8FF);
  static const background = Color(0xFFE4F3FF);
  static const text = Color(0xFF102A52);
  static const muted = Color(0xFF47688F);
  static const coral = Color(0xFFE26C8C);
  static const mint = Color(0xFF12BFA0);
  static const amber = Color(0xFFE39A32);
  static const lilac = Color(0xFF7778F4);
  static const surface = Color(0xFFF5FBFF);
  static const surfaceRaised = Color(0xFFDCEEFF);
  static const line = Color(0xFF9BC9F3);
  static const desktopRail = Color(0xFFEAF6FF);
  static const desktopCanvas = Color(0xFFDFF1FF);
  static const desktopAccent = primary;
  static const desktopAccentSoft = Color(0xFFCDE7FF);
}

/// The workshop opens in light blue by default.  Dark mode is opt-in and is
/// stored locally for the current device, so one person's choice doesn't
/// change the appearance for everyone else in the workshop.
enum ForageAppearance { light, dark }

class ForageAppearanceScope extends InheritedWidget {
  const ForageAppearanceScope({
    super.key,
    required this.appearance,
    required this.onChanged,
    required super.child,
  });

  final ForageAppearance appearance;
  final ValueChanged<ForageAppearance> onChanged;

  bool get isDark => appearance == ForageAppearance.dark;

  static ForageAppearanceScope of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<ForageAppearanceScope>();
    assert(
      scope != null,
      'ForageAppearanceScope is missing from the widget tree.',
    );
    return scope!;
  }

  void setDark(bool enabled) =>
      onChanged(enabled ? ForageAppearance.dark : ForageAppearance.light);

  void toggle() => setDark(!isDark);

  @override
  bool updateShouldNotify(covariant ForageAppearanceScope oldWidget) =>
      appearance != oldWidget.appearance || onChanged != oldWidget.onChanged;
}

/// The night presentation has its own scene and components.  It deliberately
/// does not recolour the light interface: a global colour filter makes glass
/// opaque and also damages product imagery.
class _DarkLiquidAppearance extends StatelessWidget {
  const _DarkLiquidAppearance({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

class _AppearanceCanvas extends StatelessWidget {
  const _AppearanceCanvas({required this.dark, required this.child});

  final bool dark;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      dark ? _DarkLiquidAppearance(child: child) : child;
}

/// Colours for shared components that are used outside Material controls.
/// Several catalogue pages use small reusable labels with an explicit colour;
/// deriving them here stops the dark workspace from inheriting navy text from
/// the original light palette.
Color _atelierForeground(BuildContext context) =>
    Theme.of(context).colorScheme.onSurface;

Color _atelierMuted(BuildContext context) =>
    Theme.of(context).colorScheme.onSurfaceVariant;

Color _atelierSuccess(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xFF9BE8CE)
    : const Color(0xFF166B58);

Color _atelierWarning(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xFFFFCC98)
    : const Color(0xFF92400E);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  validatePublicBackendConfig(_supabaseUrl, _supabasePublishableKey);
  // A secure-storage or device-info plugin must never prevent the UI from
  // opening. A temporary id merely requires a new approval once storage is
  // available again.
  appDevice = await DeviceIdentity.load().timeout(
    const Duration(seconds: 5),
    onTimeout: () => DeviceIdentity(
      id: 'temporary-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}',
      label: 'Appareil temporaire',
    ),
  );
  await Supabase.initialize(
    url: _supabaseUrl,
    publishableKey: _supabasePublishableKey,
    debug: false,
    authOptions: FlutterAuthClientOptions(
      localStorage: SecureSessionStorage(_supabaseUrl),
      detectSessionInUri: false,
    ),
    headers: {'x-forage-device-id': appDevice.id},
  );
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  } else {
    // Android and iOS use sqflite's native database implementation. Without
    // this assignment, the FFI factory is the only configured backend and the
    // workshop cannot open after a mobile login.
    databaseFactory = sqflite.databaseFactory;
  }
  await AppNotifications.initialize();
  runApp(const ForageApp());
}

abstract final class AppNotifications {
  static final _notifications = FlutterLocalNotificationsPlugin();

  static Future<void> initialize() async {
    try {
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      );
      await _notifications.initialize(settings);
      await _notifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    } catch (_) {
      // Notifications are optional on desktop platforms and must never block
      // the workshop from opening.
    }
  }

  static Future<void> show({
    required String title,
    required String body,
  }) async {
    try {
      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          'workshop_events',
          'Événements de l’atelier',
          channelDescription: 'Alertes de stock, opérations et contrôles',
          importance: Importance.high,
          priority: Priority.high,
        ),
      );
      await _notifications.show(
        DateTime.now().microsecondsSinceEpoch.remainder(1 << 31),
        title,
        body,
        details,
      );
    } catch (_) {
      // A missing platform capability should not interrupt the business flow.
    }
  }
}

enum UserRole { admin, operator, visitor, validation }

/// Pages are granted independently from roles. Roles remain useful shortcuts,
/// while this list lets an administrator give a person only the screens needed.
enum AppPage {
  dashboard,
  products,
  stock,
  machines,
  team,
  validation,
  analytics,
}

extension AppPageLabel on AppPage {
  String get label => switch (this) {
    AppPage.dashboard => 'Accueil',
    AppPage.products => 'Produits',
    AppPage.stock => 'Stock',
    AppPage.machines => 'Machines',
    AppPage.team => 'Équipe',
    AppPage.validation => 'Validations',
    AppPage.analytics => 'Analyses',
  };
}

enum UserStatus { active, onLeave, dismissed }

enum LoginFailure {
  invalidCredentials,
  temporarilyLocked,
  inactiveAccount,
  devicePending,
  deviceRejected,
  outsideSchedule,
  serverSetupRequired,
  serviceUnavailable,
}

class LoginResult {
  const LoginResult.success(this.user) : failure = null;
  const LoginResult.failure(this.failure) : user = null;
  final AppUser? user;
  final LoginFailure? failure;
  bool get succeeded => user != null;
}

extension UserStatusLabel on UserStatus {
  String get label => switch (this) {
    UserStatus.active => 'Actif',
    UserStatus.onLeave => 'En congé',
    UserStatus.dismissed => 'Licencié définitivement',
  };
}

extension UserRoleLabel on UserRole {
  String get label => switch (this) {
    UserRole.admin => 'Administrateur',
    UserRole.operator => 'Opérateur',
    UserRole.visitor => 'Visiteur',
    UserRole.validation => 'Validation',
  };
}

class AppUser {
  AppUser({
    required this.id,
    required this.username,
    required this.password,
    required this.fullName,
    this.email = '',
    this.admin = false,
    this.role = UserRole.operator,
    Set<UserRole>? roles,
    Set<AppPage>? allowedPages,
    Set<AppPage>? writablePages,
    this.status = UserStatus.active,
    this.leaveUntil,
    this.isPrivateOwner = false,
    this.canExport = false,
    this.loginStartTime,
    this.loginEndTime,
  }) : roles = roles ?? {if (admin) UserRole.admin else role},
       allowedPages =
           allowedPages ??
           _defaultPages(roles ?? {if (admin) UserRole.admin else role}),
       writablePages =
           writablePages ??
           _defaultWritablePages(
             roles ?? {if (admin) UserRole.admin else role},
           );
  final String id;
  final String username;
  final String password;
  final String fullName;
  final String email;
  final bool admin;

  /// Kept for compatibility with old backups. New records use [roles].
  final UserRole role;
  final Set<UserRole> roles;
  final Set<AppPage> allowedPages;
  final Set<AppPage> writablePages;
  final UserStatus status;
  final DateTime? leaveUntil;
  final bool canExport;

  /// A null pair means no daily time limit. Stored as HH:mm:ss in Supabase.
  final String? loginStartTime;
  final String? loginEndTime;

  /// The private owner account is intentionally excluded from the team list.
  /// It is the only account allowed to open the destructive maintenance area.
  final bool isPrivateOwner;

  static Set<AppPage> _defaultPages(Set<UserRole> values) {
    if (values.contains(UserRole.admin)) return AppPage.values.toSet();
    final pages = <AppPage>{AppPage.dashboard};
    if (values.contains(UserRole.operator)) pages.add(AppPage.machines);
    if (values.contains(UserRole.validation)) pages.add(AppPage.validation);
    if (values.contains(UserRole.visitor)) {
      pages.addAll({
        AppPage.dashboard,
        AppPage.products,
        AppPage.stock,
        AppPage.machines,
      });
    }
    return pages;
  }

  static Set<AppPage> _defaultWritablePages(Set<UserRole> values) {
    if (values.contains(UserRole.admin)) return AppPage.values.toSet();
    if (values.contains(UserRole.operator)) return {AppPage.machines};
    if (values.contains(UserRole.validation)) return {AppPage.validation};
    return {};
  }

  bool get isAdmin => admin || roles.contains(UserRole.admin);
  UserRole get effectiveRole => isAdmin ? UserRole.admin : roles.first;
  bool get isOperator => roles.contains(UserRole.operator);
  bool get isVisitor => roles.contains(UserRole.visitor);
  bool get canValidate => isAdmin || roles.contains(UserRole.validation);
  bool get isDeveloper => isPrivateOwner && isAdmin;

  /// Leave and dismissal block access until an administrator explicitly
  /// reactivates the account. A leave end date is informational only.
  bool get canLogIn => status == UserStatus.active;
  bool canAccess(AppPage page) {
    if (page == AppPage.team) return isAdmin;
    return isAdmin || allowedPages.contains(page);
  }

  bool canWritePage(AppPage page) => isAdmin || writablePages.contains(page);

  AppUser copyWith({
    String? password,
    Set<UserRole>? roles,
    Set<AppPage>? allowedPages,
    Set<AppPage>? writablePages,
    UserStatus? status,
    DateTime? leaveUntil,
    bool clearLeaveUntil = false,
    bool? isPrivateOwner,
    bool? canExport,
    String? loginStartTime,
    String? loginEndTime,
    bool clearLoginSchedule = false,
  }) => AppUser(
    id: id,
    username: username,
    password: password ?? this.password,
    fullName: fullName,
    email: email,
    admin: (roles ?? this.roles).contains(UserRole.admin),
    role: (roles ?? this.roles).first,
    roles: roles ?? this.roles,
    allowedPages: allowedPages ?? this.allowedPages,
    writablePages: writablePages ?? this.writablePages,
    status: status ?? this.status,
    leaveUntil: clearLeaveUntil ? null : (leaveUntil ?? this.leaveUntil),
    isPrivateOwner: isPrivateOwner ?? this.isPrivateOwner,
    canExport: canExport ?? this.canExport,
    loginStartTime: clearLoginSchedule
        ? null
        : (loginStartTime ?? this.loginStartTime),
    loginEndTime: clearLoginSchedule
        ? null
        : (loginEndTime ?? this.loginEndTime),
  );
}

class UserSession {
  const UserSession({
    required this.id,
    required this.userId,
    required this.loggedInAt,
    this.loggedOutAt,
  });
  final String id;
  final String userId;
  final DateTime loggedInAt;
  final DateTime? loggedOutAt;
}

/// Encryption helpers used only for backup files.
abstract final class PasswordSecurity {
  static const _iterations = 310000;
  static final _algorithm = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: _iterations,
    bits: 256,
  );

  static Future<Map<String, String>> encryptBackup(
    Uint8List plaintext,
    String passphrase,
  ) async {
    final salt = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    final nonce = List<int>.generate(12, (_) => Random.secure().nextInt(256));
    final key = await _algorithm.deriveKey(
      secretKey: SecretKey(utf8.encode(passphrase)),
      nonce: salt,
    );
    final box = await AesGcm.with256bits().encrypt(
      plaintext,
      secretKey: key,
      nonce: nonce,
    );
    return {
      'salt': base64UrlEncode(salt),
      'nonce': base64UrlEncode(nonce),
      'ciphertext': base64UrlEncode(box.cipherText),
      'mac': base64UrlEncode(box.mac.bytes),
    };
  }

  static Future<Uint8List> decryptBackup(
    Map<dynamic, dynamic> envelope,
    String passphrase,
  ) async {
    try {
      final salt = base64Url.decode(envelope['salt'] as String);
      final key = await _algorithm.deriveKey(
        secretKey: SecretKey(utf8.encode(passphrase)),
        nonce: salt,
      );
      final box = SecretBox(
        base64Url.decode(envelope['ciphertext'] as String),
        nonce: base64Url.decode(envelope['nonce'] as String),
        mac: Mac(base64Url.decode(envelope['mac'] as String)),
      );
      return Uint8List.fromList(
        await AesGcm.with256bits().decrypt(box, secretKey: key),
      );
    } catch (_) {
      throw const FormatException(
        'Mot de passe incorrect ou sauvegarde altérée.',
      );
    }
  }
}

/// Passwords are stored as a slow, salted one-way derivation.  This is kept
/// separate from backup encryption: a password verifier must never be usable
/// to recover the original password.
abstract final class CredentialSecurity {
  static const _prefix = r'$pbkdf2-sha256$v1$';
  static const _iterations = 600000;

  static bool isHash(String value) => value.startsWith(_prefix);

  /// Native builds run this deliberately expensive operation off the UI
  /// isolate, so a secure login never freezes the form.
  static Future<String> hash(String password) => compute(
    _hashCredentialPassword,
    password,
    debugLabel: 'Password hashing',
  );

  static Future<bool> verify(String password, String encoded) => compute(
    _verifyCredentialPassword,
    {'password': password, 'encoded': encoded},
    debugLabel: 'Password verification',
  );

  static bool _constantTimeEquals(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    var difference = 0;
    for (var index = 0; index < left.length; index++) {
      difference |= left[index] ^ right[index];
    }
    return difference == 0;
  }
}

Future<String> _hashCredentialPassword(String password) async {
  final salt = List<int>.generate(16, (_) => Random.secure().nextInt(256));
  final algorithm = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: CredentialSecurity._iterations,
    bits: 256,
  );
  final key = await algorithm.deriveKey(
    secretKey: SecretKey(utf8.encode(password)),
    nonce: salt,
  );
  final bytes = await key.extractBytes();
  return '${CredentialSecurity._prefix}${base64UrlEncode(salt)}\$${base64UrlEncode(bytes)}';
}

Future<bool> _verifyCredentialPassword(Map<String, String> input) async {
  final encoded = input['encoded'];
  final password = input['password'];
  if (encoded == null ||
      password == null ||
      !CredentialSecurity.isHash(encoded)) {
    return false;
  }
  final parts = encoded
      .substring(CredentialSecurity._prefix.length)
      .split(r'$');
  if (parts.length != 2) return false;
  try {
    final salt = base64Url.decode(parts[0]);
    final expected = base64Url.decode(parts[1]);
    if (salt.length != 16 || expected.length != 32) return false;
    final algorithm = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: CredentialSecurity._iterations,
      bits: 256,
    );
    final key = await algorithm.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );
    return CredentialSecurity._constantTimeEquals(
      await key.extractBytes(),
      expected,
    );
  } catch (_) {
    return false;
  }
}

class Product {
  const Product({
    required this.id,
    required this.name,
    required this.width,
    required this.lengthMeters,
    required this.lengthUnit,
    required this.thickness,
    required this.kind,
    required this.initialStock,
    required this.initialDepotId,
    required this.material,
    this.hoseUnit = HoseUnit.piece,
    this.metersPerPiece,
    this.diameter,
    this.diameterIsExternal = true,
    this.diameterCalculatedFromDimensions = false,
    this.reference = '',
    this.image,
    this.parentProductId,
  });
  final String id;
  final String name;

  /// Width is stored in metres and thickness in millimetres.
  final double width;

  /// The canonical value used in all calculations.
  final double lengthMeters;
  final LengthUnit lengthUnit;
  final double thickness;
  final ProductKind kind;

  /// Quantity available when the product is first created.
  final int initialStock;
  final String initialDepotId;
  final MaterialType material;
  final HoseUnit hoseUnit;

  /// Used only for pipes managed by piece: their length in metres.
  final double? metersPerPiece;

  /// Manually entered diameter in millimetres for diameter-based items.
  final double? diameter;

  /// Whether [diameter] is the outside diameter. The other diameter is
  /// calculated with the wall thickness (outside = inside + 2 × thickness).
  final bool diameterIsExternal;

  /// New diameter products use the entered length, width and thickness to
  /// calculate both diameters. Older records keep their manually entered
  /// diameter so existing data remains unchanged.
  final bool diameterCalculatedFromDimensions;
  final String reference;
  final Uint8List? image;

  /// A manufactured variant points to its dimensionless production template.
  /// Templates have no parent; each produced size gets its own product row.
  final String? parentProductId;

  double get lengthInChosenUnit => lengthMeters / lengthUnit.metres;
  bool get manufactured => kind == ProductKind.manufactured;
  bool get isManufacturedTemplate => manufactured && parentProductId == null;
  bool get isManufacturedVariant => manufactured && parentProductId != null;
  bool get isHose => kind == ProductKind.hose;
  bool get hoseManagedByMeter => isHose && hoseUnit == HoseUnit.meter;
  bool get isDiameterBased => kind == ProductKind.diameter;
  bool get canBeUsedInMachine => kind == ProductKind.standard;
  String get displayReference => reference.isEmpty ? name : reference;

  bool get hasCalculatedDiameters =>
      kind == ProductKind.standard ||
      (isDiameterBased && diameterCalculatedFromDimensions);

  /// The outside diameter is the displayed largeur divided by π. The inside
  /// diameter is the outside diameter minus twice the thickness. Every term
  /// is converted to centimetres before calculation.
  double? get outsideDiameter => hasCalculatedDiameters
      ? lengthMeters * 100 / 3.14
      : !isDiameterBased || diameter == null
      ? null
      : diameterIsExternal
      ? diameter! / 10
      : (diameter! + (2 * thickness)) / 10;
  double? get insideDiameter => hasCalculatedDiameters
      ? (outsideDiameter ?? 0) - (2 * (thickness / 10))
      : !isDiameterBased || diameter == null
      ? null
      : diameterIsExternal
      ? (diameter! - (2 * thickness)) / 10
      : diameter! / 10;
  double? get displayedDiameter => outsideDiameter;
  String get displayedDiameterUnit => 'cm';
  double get kilogramsPerPiece => kilogramsForDimensions(
    widthMeters: width,
    lengthMeters: lengthMeters,
    thicknessMillimetres: thickness,
    densityKilogramsPerCubicMeter: material.density,
  );
}

/// Result returned by the product form. Categories retain their product lists,
/// so the selected category is saved alongside a new raw product.
class ProductCreation {
  const ProductCreation({
    required this.product,
    this.categoryId,
    this.familyId,
  });

  final Product product;
  final String? categoryId;
  final String? familyId;
}

class Depot {
  const Depot({required this.id, required this.name, this.image});
  final String id;
  final String name;
  final Uint8List? image;
}

enum MaterialType { steel, pvc }

enum HoseUnit { piece, meter }

extension HoseUnitLabel on HoseUnit {
  String get label => switch (this) {
    HoseUnit.piece => 'Par pièce',
    HoseUnit.meter => 'Par mètre',
  };
}

enum ProductKind { standard, hose, manufactured, diameter }

extension ProductKindLabel on ProductKind {
  String get label => switch (this) {
    ProductKind.standard => 'Produit standard',
    ProductKind.hose => 'Tuyau',
    ProductKind.manufactured => 'Produit fabriqué en usine',
    ProductKind.diameter => 'Foret / produit par diamètre',
  };

  String get description => switch (this) {
    ProductKind.standard =>
      'Produit avec les mesures habituelles, achetable et vendable.',
    ProductKind.hose =>
      'Géré par pièce ou par mètre. Il ne passe pas par une machine.',
    ProductKind.manufactured =>
      'Produit fabriqué dans l’entreprise à partir d’une machine.',
    ProductKind.diameter => 'Produit identifié par son diamètre, comme un foret. Il ne passe pas par une machine.',
  };
}

enum InventoryUnit { piece, meter, centimeter, kilogram }

extension InventoryUnitLabel on InventoryUnit {
  String get label => switch (this) {
    InventoryUnit.piece => 'Pièce',
    InventoryUnit.meter => 'Mètre',
    InventoryUnit.centimeter => 'Centimètre',
    InventoryUnit.kilogram => 'Kilogramme',
  };

  String get shortLabel => switch (this) {
    InventoryUnit.piece => 'pièce(s)',
    InventoryUnit.meter => 'm',
    InventoryUnit.centimeter => 'cm',
    InventoryUnit.kilogram => 'kg',
  };
}

String formatQuantity(double value, InventoryUnit unit) =>
    '${formatNumber(value)} ${unit.shortLabel}';

int piecesForQuantity(Product product, double quantity, InventoryUnit unit) {
  final perPiece = switch (unit) {
    InventoryUnit.piece => 1.0,
    InventoryUnit.meter => product.lengthMeters,
    InventoryUnit.centimeter => product.lengthMeters * 100,
    InventoryUnit.kilogram => product.kilogramsPerPiece,
  };
  if (quantity <= 0 || perPiece <= 0) return 0;
  return (quantity / perPiece).ceil();
}

class Supplier {
  const Supplier({
    required this.id,
    required this.name,
    required this.company,
    required this.contact,
    required this.images,
  });
  final String id;
  final String name;
  final String company;
  final String contact;
  final List<Uint8List> images;
}

class Client {
  const Client({
    required this.id,
    required this.name,
    required this.company,
    required this.phone,
    required this.ice,
    required this.images,
  });
  final String id;
  final String name;
  final String company;
  final String phone;
  final String ice;
  final List<Uint8List> images;
}

/// Indicates who bears the delivery cost for a purchase or a sale.
enum TransportCharge { client, company, shared, none }

extension TransportChargeLabel on TransportCharge {
  String get label => switch (this) {
    TransportCharge.client => 'À la charge du client',
    TransportCharge.company => 'À la charge de la société',
    TransportCharge.shared => 'À la charge de la société et du client',
    TransportCharge.none => 'Aucune',
  };
}

class Competitor {
  const Competitor({required this.id, required this.name});
  final String id;
  final String name;
}

enum PaymentSource { forageZouhour, sousseUrban, competitor }

extension PaymentSourceLabel on PaymentSource {
  String get label => switch (this) {
    PaymentSource.forageZouhour => 'Forage Zouhour',
    PaymentSource.sousseUrban => 'Sousse Urban',
    PaymentSource.competitor => 'Compétiteur',
  };
}

/// A payment line is intentionally independent so an operation can be paid
/// by several company accounts and/or several competitors.
class PaymentAllocation {
  const PaymentAllocation({
    required this.source,
    required this.mode,
    required this.amount,
    this.competitorId,
  });
  final PaymentSource source;
  final String? competitorId;
  final String mode;
  final double amount;
}

/// Persisted payment line linked to one purchase or one sale.
class TransactionPayment {
  const TransactionPayment({
    required this.id,
    required this.source,
    required this.mode,
    required this.amount,
    required this.createdAt,
    this.saleId,
    this.stockAdditionId,
    this.competitorId,
  });
  final String id;
  final String? saleId;
  final int? stockAdditionId;
  final PaymentSource source;
  final String? competitorId;
  final String mode;
  final double amount;
  final DateTime createdAt;
}

class PaymentEntryResult {
  const PaymentEntryResult({
    required this.allocations,
    required this.newCompetitors,
  });
  final List<PaymentAllocation> allocations;
  final List<Competitor> newCompetitors;
}

class Sale {
  const Sale({
    required this.id,
    required this.productId,
    required this.depotId,
    required this.clientId,
    required this.pieces,
    required this.quantity,
    required this.unit,
    required this.images,
    required this.createdAt,
    this.draft = true,
    this.transportCharge = TransportCharge.none,
    this.payments = const [],
  });
  final String id;
  final String productId;
  final String depotId;
  final String clientId;
  final int pieces;
  final double quantity;
  final InventoryUnit unit;
  final List<Uint8List> images;
  final DateTime createdAt;
  final bool draft;
  final TransportCharge transportCharge;
  final List<PaymentAllocation> payments;
}

/// A depot-to-depot movement has no effect on stock until it is approved.
class StockTransfer {
  const StockTransfer({
    required this.id,
    required this.productId,
    required this.sourceDepotId,
    required this.destinationDepotId,
    required this.pieces,
    required this.createdAt,
    this.draft = true,
  });
  final String id;
  final String productId;
  final String sourceDepotId;
  final String destinationDepotId;
  final int pieces;
  final DateTime createdAt;
  final bool draft;
}

/// A return is kept separately from its sale so the original invoice remains
/// auditable; it becomes available in its depot only once approved.
class SaleReturn {
  const SaleReturn({
    required this.id,
    required this.saleId,
    required this.productId,
    required this.depotId,
    required this.pieces,
    required this.createdAt,
    this.status = ReturnValidationStatus.pending,
  });
  final String id;
  final String saleId;
  final String productId;
  final String depotId;
  final int pieces;
  final DateTime createdAt;
  final ReturnValidationStatus status;
}

/// A return changes stock only after it is accepted by a validator.
enum ReturnValidationStatus { pending, approved, rejected }

extension ReturnValidationStatusLabel on ReturnValidationStatus {
  String get label => switch (this) {
    ReturnValidationStatus.pending => 'En attente de validation',
    ReturnValidationStatus.approved => 'Validé',
    ReturnValidationStatus.rejected => 'Refusé',
  };
}

extension MaterialTypeLabel on MaterialType {
  String get label => this == MaterialType.steel ? 'Fer / acier' : 'PVC';
  double get density => this == MaterialType.steel ? 7850 : 1400;
  String get formulaLabel =>
      'largeur × longueur × épaisseur × ${density.toStringAsFixed(0)} kg/m³';
}

class ProductFamily {
  const ProductFamily({
    required this.id,
    required this.name,
    this.productIds = const [],
  });

  final String id;
  final String name;
  final List<String> productIds;

  factory ProductFamily.fromJson(Map<String, dynamic> json) => ProductFamily(
    id: json['id'] as String,
    name: json['name'] as String,
    productIds: List<String>.from(json['product_ids'] as List),
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'product_ids': productIds,
  };
}

class ProductCategory {
  const ProductCategory({
    required this.id,
    required this.name,
    required this.productIds,
    required this.image,
    this.families = const [],
  });
  final String id;
  final String name;
  final List<String> productIds;
  final Uint8List image;
  final List<ProductFamily> families;

  ProductCategory copyWith({
    String? name,
    List<String>? productIds,
    List<ProductFamily>? families,
  }) => ProductCategory(
    id: id,
    name: name ?? this.name,
    productIds: productIds ?? this.productIds,
    image: image,
    families: families ?? this.families,
  );

  ProductCategory withProductInFamily(String productId, String? familyId) =>
      copyWith(
        productIds: {...productIds, productId}.toList(),
        families: [
          for (final family in families)
            ProductFamily(
              id: family.id,
              name: family.name,
              productIds: [
                for (final id in family.productIds)
                  if (id != productId) id,
                if (family.id == familyId) productId,
              ],
            ),
        ],
      );
}

abstract final class PdfReports {
  static const _brand = 'FORAGE ZOUHOUR';

  static Future<void> printAllProducts({
    required List<Product> products,
    required List<Depot> depots,
    required int Function(String productId, String depotId) depotStock,
  }) async {
    final document = pw.Document();
    final rows = products.map((product) {
      final total = depots.fold<int>(
        0,
        (runningTotal, depot) =>
            runningTotal + depotStock(product.id, depot.id),
      );
      final stockByDepot = depots
          .map(
            (depot) => MapEntry(depot.name, depotStock(product.id, depot.id)),
          )
          .where((entry) => entry.value != 0)
          .map(
            (entry) =>
                '${entry.key}: ${productQuantityLabel(product, entry.value)}',
          )
          .join('\n');
      return [
        product.displayReference,
        productQuantityLabel(product, product.initialStock),
        productQuantityLabel(product, total),
        stockByDepot.isEmpty ? '—' : stockByDepot,
      ];
    }).toList();
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        header: (_) => pw.Text(
          '$_brand - Liste des produits',
          style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
        ),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text('Page ${context.pageNumber} / ${context.pagesCount}'),
        ),
        build: (_) => [
          pw.SizedBox(height: 6),
          pw.Text(
            'État des stocks imprimé le ${_dateLabel(DateTime.now())}',
            style: const pw.TextStyle(color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 16),
          pw.TableHelper.fromTextArray(
            headers: const [
              'Produit',
              'Stock initial',
              'Stock actuel',
              'Dépôts non vides',
            ],
            data: rows,
            headerStyle: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
            headerDecoration: const pw.BoxDecoration(
              color: PdfColor.fromInt(0xFF3D2BC7),
            ),
            columnWidths: const {
              0: pw.FlexColumnWidth(2),
              1: pw.FlexColumnWidth(1),
              2: pw.FlexColumnWidth(1),
              3: pw.FlexColumnWidth(3),
            },
            cellAlignment: pw.Alignment.centerLeft,
            cellPadding: const pw.EdgeInsets.all(7),
          ),
        ],
      ),
    );
    await Printing.layoutPdf(onLayout: (_) => document.save());
  }

  static Future<void> printProductDetails({
    required Product product,
    required List<ProductCategory> categories,
    required List<Depot> depots,
    required int Function(String productId, String depotId) depotStock,
  }) async {
    final document = pw.Document();
    final categoryNames = categories
        .where((category) => category.productIds.contains(product.id))
        .map((category) => category.name)
        .join(', ');
    final total = depots.fold<int>(
      0,
      (runningTotal, depot) => runningTotal + depotStock(product.id, depot.id),
    );
    final details = [
      ['Nom', product.name],
      if (product.reference.isNotEmpty) ['Référence', product.reference],
      ['Type', product.kind.label],
      ['Catégorie', categoryNames.isEmpty ? 'Aucune' : categoryNames],
      if (product.isDiameterBased) ...[
        [
          product.diameterIsExternal
              ? 'Diamètre extérieur saisi'
              : 'Diamètre intérieur saisi',
          'Ø ${formatNumber(product.displayedDiameter ?? 0)} ${product.displayedDiameterUnit}',
        ],
        [
          'Diamètre extérieur',
          'Ø ${formatNumber(product.outsideDiameter ?? 0)} cm',
        ],
        [
          'Diamètre intérieur',
          'Ø ${formatNumber(product.insideDiameter ?? 0)} cm',
        ],
        ['Épaisseur', '${formatNumber(product.thickness)} mm'],
      ] else if (product.isHose)
        ['Unité de vente', 'Mètre']
      else ...[
        [
          'Matière',
          '${product.material.label} - ${formatNumber(product.material.density)} kg/m³',
        ],
        [
          'Largeur',
          '${formatNumber(product.lengthInChosenUnit)} ${product.lengthUnit.label} (${formatNumber(product.lengthMeters)} m)',
        ],
        [
          'Diamètre intérieur calculé',
          'Ø ${formatNumber(product.insideDiameter ?? 0)} cm',
        ],
        [
          'Diamètre extérieur calculé',
          'Ø ${formatNumber(product.outsideDiameter ?? 0)} cm',
        ],
        ['Longueur', '${formatNumber(product.width)} m'],
        ['Épaisseur', '${formatNumber(product.thickness)} mm'],
        ['Poids estimé par pièce', formatWeight(product.kilogramsPerPiece)],
      ],
      ['Stock total', productQuantityLabel(product, total)],
      if (!product.isDiameterBased)
        [
          'Longueur totale en stock',
          '${formatNumber(total * product.lengthMeters)} m',
        ],
      if (!product.isHose && !product.isDiameterBased)
        [
          'Poids total en stock',
          formatWeight(total * product.kilogramsPerPiece),
        ],
    ];
    final stockRows = depots
        .map(
          (depot) => [
            depot.name,
            productQuantityLabel(product, depotStock(product.id, depot.id)),
          ],
        )
        .where((row) => row[1] != productQuantityLabel(product, 0))
        .toList();
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        header: (_) => pw.Text(
          '$_brand - Fiche produit',
          style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
        ),
        build: (_) => [
          pw.Text(
            product.name,
            style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 14),
          pw.TableHelper.fromTextArray(
            headers: const ['Information', 'Valeur'],
            data: details,
            headerStyle: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
            headerDecoration: const pw.BoxDecoration(
              color: PdfColor.fromInt(0xFF3D2BC7),
            ),
            cellPadding: const pw.EdgeInsets.all(7),
          ),
          pw.SizedBox(height: 20),
          pw.Text(
            'Répartition par dépôt',
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          if (stockRows.isEmpty)
            pw.Text('Aucun dépôt ne contient actuellement ce produit.')
          else
            pw.TableHelper.fromTextArray(
              headers: const ['Dépôt', 'Quantité'],
              data: stockRows,
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColor.fromInt(0xFF3D2BC7),
              ),
              cellPadding: const pw.EdgeInsets.all(7),
            ),
        ],
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            '$_brand · Page ${context.pageNumber} / ${context.pagesCount}',
          ),
        ),
      ),
    );
    await Printing.layoutPdf(onLayout: (_) => document.save());
  }

  static String _dateLabel(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
}

class ExcelSheetData {
  const ExcelSheetData({
    required this.name,
    required this.headers,
    required this.rows,
  });

  final String name;
  final List<String> headers;
  final List<List<Object?>> rows;
}

/// Produces a real .xlsx workbook. Values retain their Excel types so dates
/// sort correctly and quantities can be used in formulas after export.
abstract final class ExcelReports {
  static Future<void> save(List<ExcelSheetData> sheets) async {
    if (sheets.isEmpty) {
      throw const FormatException('Sélectionnez au moins une page à exporter.');
    }
    final workbook = xlsx.Excel.createExcel();
    for (final sheetData in sheets) {
      final sheet = workbook[sheetData.name];
      sheet.appendRow(sheetData.headers.map(xlsx.TextCellValue.new).toList());
      for (final row in sheetData.rows) {
        sheet.appendRow(row.map(_cell).toList());
      }
      for (var column = 0; column < sheetData.headers.length; column++) {
        sheet.setColumnWidth(column, 20);
      }
    }
    workbook.delete('Sheet1');
    final bytes = workbook.save();
    if (bytes == null) {
      throw const FormatException('Le fichier Excel est vide.');
    }
    final stamp = DateTime.now().toIso8601String().replaceAll(
      RegExp('[:.]'),
      '-',
    );
    await FileSaver.instance.saveAs(
      name: 'forage-zouhour-export-$stamp',
      bytes: Uint8List.fromList(bytes),
      fileExtension: 'xlsx',
      mimeType: MimeType.microsoftExcel,
    );
  }

  static xlsx.CellValue _cell(Object? value) => switch (value) {
    null => xlsx.TextCellValue(''),
    int value => xlsx.IntCellValue(value),
    double value => xlsx.DoubleCellValue(value),
    DateTime value => xlsx.DateTimeCellValue.fromDateTime(value),
    _ => xlsx.TextCellValue(value.toString()),
  };
}

enum LengthUnit { meter, kilometer, centimeter, millimeter }

extension LengthUnitLabel on LengthUnit {
  String get label => switch (this) {
    LengthUnit.meter => 'm',
    LengthUnit.kilometer => 'km',
    LengthUnit.centimeter => 'cm',
    LengthUnit.millimeter => 'mm',
  };

  double get metres => switch (this) {
    LengthUnit.meter => 1,
    LengthUnit.kilometer => 1000,
    LengthUnit.centimeter => .01,
    LengthUnit.millimeter => .001,
  };
}

/// Thickness is stored in millimetres, but the form may receive centimetres
/// or metres. Keeping this conversion separate from [LengthUnit] avoids
/// accidentally treating a thickness as a length in metres.
enum ThicknessUnit { millimeter, centimeter, meter }

extension ThicknessUnitLabel on ThicknessUnit {
  String get label => switch (this) {
    ThicknessUnit.millimeter => 'mm',
    ThicknessUnit.centimeter => 'cm',
    ThicknessUnit.meter => 'm',
  };

  double get millimetres => switch (this) {
    ThicknessUnit.millimeter => 1,
    ThicknessUnit.centimeter => 10,
    ThicknessUnit.meter => 1000,
  };
}

/// Dimensions are normalised to metres and millimetres before calculating a
/// mass. The resulting value is always kilograms.
double kilogramsForDimensions({
  required double widthMeters,
  required double lengthMeters,
  required double thicknessMillimetres,
  required double densityKilogramsPerCubicMeter,
}) =>
    widthMeters *
    lengthMeters *
    (thicknessMillimetres / 1000) *
    densityKilogramsPerCubicMeter;

enum MachineType { standard, roulage }

class FactoryMachine {
  const FactoryMachine({
    required this.id,
    required this.name,
    required this.type,
    required this.categoryId,
    required this.outputId,
    required this.units,
    required this.operatorIds,
    this.image,
    this.temporary = false,
    this.deadline,
    this.plannedPieces,
    this.hopperPieces,
    this.temporaryInputProductId,
    this.temporarySourceDepotId,
    this.temporaryInputPieces,
  });
  final String id;
  final String name;
  final MachineType type;
  final String categoryId;
  final String outputId;
  final List<MachineUnit> units;
  final List<String> operatorIds;

  /// Old installations have one machine picture. New machines store the
  /// picture on every [MachineUnit], while this stays as a safe fallback.
  final Uint8List? image;
  final bool temporary;
  final DateTime? deadline;
  final int? plannedPieces;

  /// Number of sheets in one hopper for a temporary rolling job.
  final int? hopperPieces;

  /// Material sent to an external temporary workshop.
  final String? temporaryInputProductId;
  final String? temporarySourceDepotId;
  final int? temporaryInputPieces;
  int get copies => units.length;
  int get usableCopies => units.where((unit) => unit.usable).length;
}

enum MachineUnitState { ready, temporarilyUnavailable, retired }

class MachineUnit {
  const MachineUnit({
    required this.number,
    this.image,
    this.state = MachineUnitState.ready,
    this.unavailableUntil,
  });
  final int number;
  final Uint8List? image;
  final MachineUnitState state;
  final DateTime? unavailableUntil;
  bool get usable =>
      state == MachineUnitState.ready ||
      (state == MachineUnitState.temporarilyUnavailable &&
          unavailableUntil != null &&
          unavailableUntil!.isBefore(DateTime.now()));
}

class Operation {
  static const hopperSheetLengthMeters = 1.5;

  Operation({
    required this.id,
    required this.machineId,
    required this.operatorId,
    required this.pieces,
    required this.productId,
    required this.sourceDepotId,
    required this.machineUnitNumber,
    required this.startedAt,
    this.hopperPieces,
    this.finishedAt,
    this.outputPieces,
    this.finalImage,
    this.remainderImage,
    this.scrapImage,
    this.outputDepotId,
    this.remainderDepotId,
    this.scrapDepotId,
    this.scrapProductId,
    this.remainderPieces = 0,
    this.needsReview = false,
    this.scrapPieces = 0,
    this.completionDraft = false,
    this.validatedAt,
    this.outputProductId,
    this.externalProduction = false,
  });
  final String id;
  final String machineId;
  final String operatorId;
  final int pieces;
  final String productId;
  final String sourceDepotId;
  final int machineUnitNumber;
  final int? hopperPieces;
  final DateTime startedAt;
  DateTime? finishedAt;
  int? outputPieces;
  Uint8List? finalImage;
  Uint8List? remainderImage;
  Uint8List? scrapImage;
  String? outputDepotId;
  String? remainderDepotId;
  String? scrapDepotId;
  String? scrapProductId;
  int remainderPieces;
  bool needsReview;
  int scrapPieces;
  bool completionDraft;
  DateTime? validatedAt;
  String? outputProductId;

  /// Work entrusted to an external workshop. It reaches stock only after
  /// validation and never belongs to an operator's payroll.
  final bool externalProduction;
  bool get active => finishedAt == null;
  double? get hopperLengthMeters =>
      hopperPieces == null ? null : hopperPieces! * hopperSheetLengthMeters;
}

class OperatorPayment {
  const OperatorPayment({
    required this.id,
    required this.operatorId,
    required this.amount,
    required this.paidAt,
  });
  final String id;
  final String operatorId;
  final double amount;
  final DateTime paidAt;
}

class WorkshopData {
  const WorkshopData({
    required this.products,
    required this.depots,
    required this.categories,
    required this.catalogFamilies,
    required this.machines,
    required this.operations,
    required this.stockAdditions,
    required this.suppliers,
    required this.clients,
    required this.competitors,
    required this.transactionPayments,
    required this.sales,
    required this.stockTransfers,
    required this.saleReturns,
    required this.payments,
    required this.received,
  });

  final List<Product> products;
  final List<Depot> depots;
  final List<ProductCategory> categories;
  final List<CatalogFamily> catalogFamilies;
  final List<FactoryMachine> machines;
  final List<Operation> operations;
  final List<StockAddition> stockAdditions;
  final List<Supplier> suppliers;
  final List<Client> clients;
  final List<Competitor> competitors;
  final List<TransactionPayment> transactionPayments;
  final List<Sale> sales;
  final List<StockTransfer> stockTransfers;
  final List<SaleReturn> saleReturns;
  final List<OperatorPayment> payments;
  final Map<String, int> received;
}

class AppDatabase {
  AppDatabase({this._databasePath, this.cloudSync});

  static const _databaseName = _localDatabaseName;
  static const _generalDepotId = 'general-depot';
  static const _backupFormat = 'forage-zouhour-backup';
  static const _encryptedBackupFormat = 'forage-zouhour-encrypted-backup';
  static const _backupVersion = 6;
  static const _maximumFailedLogins = 5;
  static const _lockoutDuration = Duration(minutes: 15);
  static const _backupTables = [
    'products',
    'categories',
    'catalog_families',
    'machines',
    'operations',
    'stock_additions',
    'suppliers',
    'clients',
    'sales',
    'competitors',
    'transaction_payments',
    'stock_transfers',
    'sale_returns',
    'operator_payments',
    'depots',
  ];
  // Authentication and device-only preferences are never copied to the
  // shared workspace. Only operational workshop records are synchronized.
  static const _syncTables = _backupTables;
  static const _binaryBackupColumns = {
    'products': {'image'},
    'categories': {'image'},
    'machines': {'image'},
    'operations': {'final_image', 'remainder_image', 'scrap_image'},
    'depots': {'image'},
  };
  final String? _databasePath;
  final CloudSyncClient? cloudSync;
  late final Future<Database> _database = _open();

  Future<Database> _open() async {
    final database = await openDatabase(
      _databasePath ?? join(await getDatabasesPath(), _databaseName),
      version: 37,
      onCreate: (database, version) async {
        await database.execute(
          "CREATE TABLE users (id TEXT PRIMARY KEY, username TEXT NOT NULL UNIQUE, password TEXT NOT NULL, full_name TEXT NOT NULL, admin INTEGER NOT NULL, role TEXT NOT NULL DEFAULT 'operator', roles TEXT NOT NULL DEFAULT '[\"operator\"]', allowed_pages TEXT NOT NULL DEFAULT '[]', writable_pages TEXT NOT NULL DEFAULT '[]', status TEXT NOT NULL DEFAULT 'active', leave_until INTEGER, failed_attempts INTEGER NOT NULL DEFAULT 0, locked_until INTEGER, is_private_owner INTEGER NOT NULL DEFAULT 0)",
        );
        await database.execute(
          'CREATE TABLE user_sessions (id TEXT PRIMARY KEY, user_id TEXT NOT NULL, logged_in_at INTEGER NOT NULL, logged_out_at INTEGER)',
        );
        await database.execute(
          'CREATE TABLE products (id TEXT PRIMARY KEY, name TEXT NOT NULL, reference TEXT NOT NULL DEFAULT \'\', width REAL NOT NULL, length_meters REAL NOT NULL, length_unit TEXT NOT NULL, thickness REAL NOT NULL, manufactured INTEGER NOT NULL, kind TEXT NOT NULL DEFAULT \'standard\', diameter REAL, diameter_is_external INTEGER NOT NULL DEFAULT 1, diameter_calculated_from_dimensions INTEGER NOT NULL DEFAULT 0, hose_unit TEXT NOT NULL DEFAULT \'piece\', meters_per_piece REAL, initial_stock INTEGER NOT NULL, initial_depot_id TEXT NOT NULL DEFAULT \'general-depot\', material_type TEXT NOT NULL DEFAULT \'steel\', image BLOB, parent_product_id TEXT)',
        );
        await database.execute(
          "CREATE TABLE categories (id TEXT PRIMARY KEY, name TEXT NOT NULL, product_ids TEXT NOT NULL, image BLOB NOT NULL, families TEXT NOT NULL DEFAULT '[]')",
        );
        await _createCatalogFamiliesTable(database);
        await database.execute(
          'CREATE TABLE machines (id TEXT PRIMARY KEY, name TEXT NOT NULL, copies INTEGER NOT NULL, type TEXT NOT NULL, inputs TEXT NOT NULL, output TEXT NOT NULL, operator_ids TEXT NOT NULL, image BLOB, category_id TEXT, units TEXT NOT NULL DEFAULT \'[]\', temporary INTEGER NOT NULL DEFAULT 0, deadline INTEGER, planned_pieces INTEGER, hopper_pieces INTEGER, temporary_input_product_id TEXT, temporary_source_depot_id TEXT, temporary_input_pieces INTEGER)',
        );
        await database.execute(
          'CREATE TABLE operations (id TEXT PRIMARY KEY, machine_id TEXT NOT NULL, operator_id TEXT NOT NULL, pieces INTEGER NOT NULL, hopper_pieces INTEGER, started_at INTEGER NOT NULL, finished_at INTEGER, output_pieces INTEGER, final_image BLOB, product_id TEXT NOT NULL, source_depot_id TEXT NOT NULL DEFAULT \'general-depot\', output_depot_id TEXT, remainder_depot_id TEXT, machine_unit_number INTEGER NOT NULL, remainder_image BLOB, needs_review INTEGER NOT NULL DEFAULT 0, scrap_pieces INTEGER NOT NULL DEFAULT 0, completion_draft INTEGER NOT NULL DEFAULT 0, validated_at INTEGER, output_product_id TEXT, external_production INTEGER NOT NULL DEFAULT 0, remainder_pieces INTEGER NOT NULL DEFAULT 0, scrap_depot_id TEXT, scrap_product_id TEXT, scrap_image BLOB)',
        );
        await database.execute(
          'CREATE TABLE stock_additions (id INTEGER PRIMARY KEY AUTOINCREMENT, product_id TEXT NOT NULL, depot_id TEXT NOT NULL DEFAULT \'general-depot\', pieces INTEGER NOT NULL, receipt_number TEXT NOT NULL, supplier_id TEXT, return_purchase_id INTEGER, quantity REAL, unit TEXT, images TEXT NOT NULL DEFAULT \'[]\', transport_charge TEXT NOT NULL DEFAULT \'none\', created_at INTEGER NOT NULL, draft INTEGER NOT NULL DEFAULT 1)',
        );
        await database.execute(
          'CREATE TABLE depots (id TEXT PRIMARY KEY, name TEXT NOT NULL, image BLOB)',
        );
        await database.execute(
          'CREATE TABLE app_settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
        );
        await _createStockPartnersTables(database);
        await _createPaymentTables(database);
        await _createStockTransfersTable(database);
        await _createSaleReturnsTable(database);
        await _createPayrollTable(database);
      },
      onUpgrade: (database, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await database.execute(
            'ALTER TABLE stock_additions ADD COLUMN created_at INTEGER NOT NULL DEFAULT 0',
          );
        }
        if (oldVersion < 3) {
          await database.execute(
            "ALTER TABLE products ADD COLUMN material_type TEXT NOT NULL DEFAULT 'steel'",
          );
          await database.execute(
            'CREATE TABLE categories (id TEXT PRIMARY KEY, name TEXT NOT NULL, product_ids TEXT NOT NULL, image BLOB)',
          );
        }
        if (oldVersion < 4) {
          await database.execute(
            'ALTER TABLE machines ADD COLUMN category_id TEXT',
          );
          await database.execute(
            "ALTER TABLE machines ADD COLUMN units TEXT NOT NULL DEFAULT '[]'",
          );
          await database.execute(
            'ALTER TABLE operations ADD COLUMN product_id TEXT',
          );
          await database.execute(
            'ALTER TABLE operations ADD COLUMN machine_unit_number INTEGER',
          );
        }
        if (oldVersion < 5) {
          await database.execute(
            'ALTER TABLE operations ADD COLUMN remainder_image BLOB',
          );
          await database.execute(
            'ALTER TABLE operations ADD COLUMN needs_review INTEGER NOT NULL DEFAULT 0',
          );
        }
        if (oldVersion < 6) {
          // Version 3 already created this column in some distributed builds.
          // A database interrupted during upgrade may still report an older
          // schema version, so never add the same column twice.
          await _addColumnIfMissing(
            database,
            table: 'categories',
            column: 'image',
            definition: 'image BLOB',
          );
        }
        if (oldVersion < 8) {
          await database.execute(
            'CREATE TABLE depots (id TEXT PRIMARY KEY, name TEXT NOT NULL, image BLOB)',
          );
          await database.execute(
            "ALTER TABLE products ADD COLUMN initial_depot_id TEXT NOT NULL DEFAULT 'general-depot'",
          );
          await database.execute(
            "ALTER TABLE stock_additions ADD COLUMN depot_id TEXT NOT NULL DEFAULT 'general-depot'",
          );
        }
        if (oldVersion < 9) {
          await database.execute(
            "ALTER TABLE operations ADD COLUMN source_depot_id TEXT NOT NULL DEFAULT 'general-depot'",
          );
          await database.execute(
            'ALTER TABLE operations ADD COLUMN output_depot_id TEXT',
          );
          await database.execute(
            'ALTER TABLE operations ADD COLUMN remainder_depot_id TEXT',
          );
        }
        if (oldVersion < 10) {
          await database.execute(
            "ALTER TABLE stock_additions ADD COLUMN receipt_number TEXT NOT NULL DEFAULT ''",
          );
        }
        if (oldVersion < 11) {
          await database.execute(
            'CREATE TABLE app_settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
          );
        }
        if (oldVersion < 12) {
          await database.execute(
            'ALTER TABLE stock_additions ADD COLUMN supplier_id TEXT',
          );
          await database.execute(
            'ALTER TABLE stock_additions ADD COLUMN quantity REAL',
          );
          await database.execute(
            'ALTER TABLE stock_additions ADD COLUMN unit TEXT',
          );
          await database.execute(
            "ALTER TABLE stock_additions ADD COLUMN images TEXT NOT NULL DEFAULT '[]'",
          );
          await _createStockPartnersTables(database);
        }
        if (oldVersion < 13) {
          await database.execute(
            "ALTER TABLE products ADD COLUMN reference TEXT NOT NULL DEFAULT ''",
          );
        }
        if (oldVersion < 14) {
          await database.execute(
            "ALTER TABLE products ADD COLUMN kind TEXT NOT NULL DEFAULT 'standard'",
          );
          await database.execute(
            "UPDATE products SET kind = 'manufactured' WHERE manufactured = 1",
          );
        }
        if (oldVersion < 15) {
          await database.execute(
            'ALTER TABLE products ADD COLUMN diameter REAL',
          );
        }
        if (oldVersion < 16) {
          await database.execute(
            "ALTER TABLE products ADD COLUMN hose_unit TEXT NOT NULL DEFAULT 'piece'",
          );
          await database.execute(
            'ALTER TABLE products ADD COLUMN meters_per_piece REAL',
          );
          await database.execute('UPDATE products SET width = 1.5');
        }
        if (oldVersion < 17) {
          // Version 16 accidentally reversed the two pipe modes. Preserve
          // existing data while aligning it with the intended meaning.
          await database.execute(
            "UPDATE products SET hose_unit = 'meter' WHERE kind = 'hose' AND meters_per_piece IS NULL",
          );
          await database.execute(
            "UPDATE products SET hose_unit = 'piece' WHERE kind = 'hose' AND meters_per_piece IS NOT NULL",
          );
        }
        if (oldVersion < 18) {
          await database.execute(
            "ALTER TABLE users ADD COLUMN role TEXT NOT NULL DEFAULT 'operator'",
          );
          await database.execute(
            "UPDATE users SET role = 'admin' WHERE admin = 1",
          );
        }
        if (oldVersion < 19) {
          await database.execute(
            'ALTER TABLE stock_additions ADD COLUMN draft INTEGER NOT NULL DEFAULT 1',
          );
          await database.execute(
            'ALTER TABLE sales ADD COLUMN draft INTEGER NOT NULL DEFAULT 1',
          );
          await database.execute(
            'ALTER TABLE operations ADD COLUMN scrap_pieces INTEGER NOT NULL DEFAULT 0',
          );
          await database.execute(
            'ALTER TABLE operations ADD COLUMN completion_draft INTEGER NOT NULL DEFAULT 0',
          );
          await database.execute('UPDATE stock_additions SET draft = 0');
          await database.execute('UPDATE sales SET draft = 0');
        }
        if (oldVersion < 20) {
          await database.execute(
            'ALTER TABLE operations ADD COLUMN validated_at INTEGER',
          );
          await _createPayrollTable(database);
          await database.execute(
            'UPDATE operations SET validated_at = finished_at WHERE finished_at IS NOT NULL AND completion_draft = 0',
          );
        }
        if (oldVersion < 21) {
          await database.execute(
            "ALTER TABLE users ADD COLUMN roles TEXT NOT NULL DEFAULT '[\"operator\"]'",
          );
          await database.execute(
            "ALTER TABLE users ADD COLUMN allowed_pages TEXT NOT NULL DEFAULT '[]'",
          );
          await database.execute(
            "ALTER TABLE users ADD COLUMN writable_pages TEXT NOT NULL DEFAULT '[]'",
          );
          await database.execute(
            "ALTER TABLE users ADD COLUMN status TEXT NOT NULL DEFAULT 'active'",
          );
          await database.execute(
            'ALTER TABLE users ADD COLUMN leave_until INTEGER',
          );
          await database.execute(
            'CREATE TABLE user_sessions (id TEXT PRIMARY KEY, user_id TEXT NOT NULL, logged_in_at INTEGER NOT NULL, logged_out_at INTEGER)',
          );
          final legacyUsers = await database.query('users');
          for (final user in legacyUsers) {
            final legacyRole = user['role'] as String? ?? 'operator';
            final isAdmin = user['admin'] == 1;
            final roles = isAdmin
                ? {UserRole.admin}
                : {UserRole.values.byName(legacyRole)};
            final model = AppUser(
              id: user['id'] as String,
              username: user['username'] as String,
              password: user['password'] as String,
              fullName: user['full_name'] as String,
              admin: isAdmin,
              role: roles.first,
              roles: roles,
            );
            await database.update(
              'users',
              {
                'roles': jsonEncode(
                  model.roles.map((role) => role.name).toList(),
                ),
                'allowed_pages': jsonEncode(
                  model.allowedPages.map((page) => page.name).toList(),
                ),
                'writable_pages': jsonEncode(
                  model.writablePages.map((page) => page.name).toList(),
                ),
              },
              where: 'id = ?',
              whereArgs: [model.id],
            );
          }
        }
        if (oldVersion < 22) {
          await database.execute(
            'ALTER TABLE users ADD COLUMN failed_attempts INTEGER NOT NULL DEFAULT 0',
          );
          await database.execute(
            'ALTER TABLE users ADD COLUMN locked_until INTEGER',
          );
        }
        if (oldVersion < 23) {
          await database.execute(
            'ALTER TABLE products ADD COLUMN parent_product_id TEXT',
          );
          await database.execute(
            'ALTER TABLE operations ADD COLUMN output_product_id TEXT',
          );
        }
        if (oldVersion < 24) {
          await _createSaleReturnsTable(database);
        }
        if (oldVersion < 25) {
          await database.execute(
            'ALTER TABLE machines ADD COLUMN temporary INTEGER NOT NULL DEFAULT 0',
          );
          await database.execute(
            'ALTER TABLE machines ADD COLUMN deadline INTEGER',
          );
          await database.execute(
            'ALTER TABLE machines ADD COLUMN planned_pieces INTEGER',
          );
          await database.execute(
            'ALTER TABLE machines ADD COLUMN hopper_pieces INTEGER',
          );
        }
        if (oldVersion < 26) {
          await database.execute(
            'ALTER TABLE operations ADD COLUMN external_production INTEGER NOT NULL DEFAULT 0',
          );
        }
        if (oldVersion < 27) {
          await database.execute(
            'ALTER TABLE machines ADD COLUMN temporary_input_product_id TEXT',
          );
          await database.execute(
            'ALTER TABLE machines ADD COLUMN temporary_source_depot_id TEXT',
          );
          await database.execute(
            'ALTER TABLE machines ADD COLUMN temporary_input_pieces INTEGER',
          );
        }
        if (oldVersion < 28) {
          // Existing returns had already affected stock before this workflow.
          await database.execute(
            "ALTER TABLE sale_returns ADD COLUMN status TEXT NOT NULL DEFAULT 'approved'",
          );
        }
        if (oldVersion < 29) {
          await database.execute(
            'ALTER TABLE users ADD COLUMN is_private_owner INTEGER NOT NULL DEFAULT 0',
          );
        }
        if (oldVersion < 30) {
          await _createStockTransfersTable(database);
        }
        if (oldVersion < 31) {
          await database.execute(
            'ALTER TABLE operations ADD COLUMN remainder_pieces INTEGER NOT NULL DEFAULT 0',
          );
          await database.execute(
            'ALTER TABLE operations ADD COLUMN scrap_depot_id TEXT',
          );
          await database.execute(
            'ALTER TABLE operations ADD COLUMN scrap_product_id TEXT',
          );
          await database.execute(
            'ALTER TABLE operations ADD COLUMN scrap_image BLOB',
          );
        }
        if (oldVersion < 32) {
          await database.execute(
            'ALTER TABLE products ADD COLUMN diameter_is_external INTEGER NOT NULL DEFAULT 1',
          );
        }
        if (oldVersion < 33) {
          await database.execute(
            'ALTER TABLE stock_additions ADD COLUMN return_purchase_id INTEGER',
          );
        }
        if (oldVersion < 34) {
          await database.execute(
            'ALTER TABLE products ADD COLUMN diameter_calculated_from_dimensions INTEGER NOT NULL DEFAULT 0',
          );
        }
        if (oldVersion < 35) {
          await database.execute(
            "ALTER TABLE stock_additions ADD COLUMN transport_charge TEXT NOT NULL DEFAULT 'none'",
          );
          await database.execute(
            "ALTER TABLE sales ADD COLUMN transport_charge TEXT NOT NULL DEFAULT 'none'",
          );
          await _createPaymentTables(database);
        }
        if (oldVersion < 36) {
          await database.execute(
            "ALTER TABLE categories ADD COLUMN families TEXT NOT NULL DEFAULT '[]'",
          );
        }
        if (oldVersion < 37) await _createCatalogFamiliesTable(database);
      },
    );
    await database.insert('depots', const {
      'id': _generalDepotId,
      'name': 'Stock général',
      'image': null,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    await _migrateLegacyRecords(database);
    await _ensurePrivateOwner(database);
    await _configureSyncTriggers(database);
    return database;
  }

  Future<void> _configureSyncTriggers(Database database) async {
    final batch = database.batch();
    for (final table in _syncTables) {
      for (final action in const ['INSERT', 'UPDATE', 'DELETE']) {
        batch.execute('''
          CREATE TRIGGER IF NOT EXISTS sync_dirty_${table}_$action
          AFTER $action ON $table
          BEGIN
            INSERT OR REPLACE INTO app_settings (key, value)
            VALUES ('cloud_sync_dirty', 'true');
          END
        ''');
      }
    }
    await batch.commit(noResult: true);
  }

  Future<void> _createCatalogFamiliesTable(DatabaseExecutor database) =>
      database.execute(
        "CREATE TABLE catalog_families (id TEXT PRIMARY KEY, name TEXT NOT NULL, category_ids TEXT NOT NULL DEFAULT '[]')",
      );

  Future<void> _addColumnIfMissing(
    DatabaseExecutor database, {
    required String table,
    required String column,
    required String definition,
  }) async {
    final columns = await database.rawQuery('PRAGMA table_info($table)');
    if (columns.any((item) => item['name'] == column)) return;
    await database.execute('ALTER TABLE $table ADD COLUMN $definition');
  }

  Future<bool> synchronizeWithCloud({bool preferRemote = false}) async {
    final client = cloudSync;
    if (client == null) return false;
    // Windows keeps a local mirror while the app is open. Full snapshots can
    // include many photos and serializing them on the UI isolate is unsafe on
    // this platform. Cloud sync still runs normally on iOS and Android.
    if (Platform.isWindows) return false;

    final database = await _database;
    final dirtyRows = await database.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: const ['cloud_sync_dirty'],
      limit: 1,
    );
    final dirty = dirtyRows.isNotEmpty && dirtyRows.single['value'] == 'true';
    final hasLocalWorkshop = await _hasLocalWorkshopRecords(database);
    final remote = await client.download();

    // A complete remote snapshot can contain product photographs. Replacing
    // every local table on *every* login was expensive enough to freeze the
    // Windows window. A mirror is restored only on a genuinely empty device;
    // afterwards this device keeps its local copy and uploads its own edits.
    if (remote != null &&
        !hasLocalWorkshop &&
        (!dirty || preferRemote)) {
      await replaceFromSyncSnapshot(remote);
    } else if (remote == null || dirty) {
      await client.upload(await exportSyncSnapshot());
    }

    await (await _database).insert('app_settings', {
      'key': 'cloud_sync_dirty',
      'value': 'false',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    return true;
  }

  Future<bool> _hasLocalWorkshopRecords(Database database) async {
    // The default depot exists even in a new installation, so it cannot be
    // used to decide whether this device already holds a workshop mirror.
    for (final table in _syncTables.where((table) => table != 'depots')) {
      final row = await database.query(table, columns: const ['id'], limit: 1);
      if (row.isNotEmpty) return true;
    }
    return false;
  }

  /// Rebuilds this device's local mirror from Supabase without ever uploading
  /// the local data. Used only after a damaged or outdated local database
  /// prevents the Windows app from starting.
  Future<bool> restoreLocalMirrorFromCloud() async {
    final client = cloudSync;
    if (client == null) return false;
    final remote = await client.download();
    if (remote == null) return false;
    await replaceFromSyncSnapshot(remote);
    await (await _database).insert('app_settings', {
      'key': 'cloud_sync_dirty',
      'value': 'false',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    return true;
  }

  Future<void> close() async {
    await (await _database).close();
  }

  /// Removes all locally stored application data, including account
  /// credentials. This must only be invoked from an authenticated recovery
  /// flow; it never creates a replacement account or password.
  Future<void> resetApplication() async {
    await (await _database).transaction((transaction) async {
      await transaction.delete('user_sessions');
      for (final table in _backupTables.reversed) {
        await transaction.delete(table);
      }
      await transaction.delete('app_settings');
      await transaction.delete('users');
      await transaction.insert('depots', const {
        'id': _generalDepotId,
        'name': 'Stock général',
        'image': null,
      });
    });
  }

  Future<List<AppUser>> loadUsers() async {
    final database = await _database;
    final rows = await database.query(
      'users',
      orderBy: 'admin DESC, full_name',
    );
    return rows.map(_userFromRow).toList();
  }

  Future<void> _createStockPartnersTables(DatabaseExecutor database) async {
    await database.execute(
      'CREATE TABLE suppliers (id TEXT PRIMARY KEY, name TEXT NOT NULL, company TEXT NOT NULL DEFAULT \'\', contact TEXT NOT NULL DEFAULT \'\', images TEXT NOT NULL DEFAULT \'[]\')',
    );
    await database.execute(
      'CREATE TABLE clients (id TEXT PRIMARY KEY, name TEXT NOT NULL DEFAULT \'\', company TEXT NOT NULL DEFAULT \'\', phone TEXT NOT NULL DEFAULT \'\', ice TEXT NOT NULL DEFAULT \'\', images TEXT NOT NULL DEFAULT \'[]\')',
    );
    await database.execute(
      'CREATE TABLE sales (id TEXT PRIMARY KEY, product_id TEXT NOT NULL, depot_id TEXT NOT NULL, client_id TEXT NOT NULL, pieces INTEGER NOT NULL, quantity REAL NOT NULL, unit TEXT NOT NULL, images TEXT NOT NULL DEFAULT \'[]\', transport_charge TEXT NOT NULL DEFAULT \'none\', created_at INTEGER NOT NULL, draft INTEGER NOT NULL DEFAULT 1)',
    );
  }

  Future<void> _createPaymentTables(DatabaseExecutor database) async {
    await database.execute(
      'CREATE TABLE competitors (id TEXT PRIMARY KEY, name TEXT NOT NULL)',
    );
    await database.execute(
      'CREATE TABLE transaction_payments (id TEXT PRIMARY KEY, sale_id TEXT, stock_addition_id INTEGER, source TEXT NOT NULL, competitor_id TEXT, payment_mode TEXT NOT NULL, amount REAL NOT NULL, created_at INTEGER NOT NULL)',
    );
  }

  Future<void> _createStockTransfersTable(DatabaseExecutor database) async {
    await database.execute(
      'CREATE TABLE stock_transfers (id TEXT PRIMARY KEY, product_id TEXT NOT NULL, source_depot_id TEXT NOT NULL, destination_depot_id TEXT NOT NULL, pieces INTEGER NOT NULL, created_at INTEGER NOT NULL, draft INTEGER NOT NULL DEFAULT 1)',
    );
  }

  /// Keep exactly one private owner: the first administrator created. Older
  /// builds may have accidentally marked more than one user as private, which
  /// would hide all of them from the team page.
  Future<void> _ensurePrivateOwner(DatabaseExecutor database) async {
    final admins = await database.query(
      'users',
      columns: ['id'],
      where: 'admin = 1',
      orderBy: 'rowid ASC',
      limit: 1,
    );
    final ownerId = admins.isEmpty ? null : admins.single['id'] as String;
    if (ownerId == null) {
      await database.update('users', {
        'is_private_owner': 0,
      }, where: 'is_private_owner != 0');
      return;
    }
    await database.update(
      'users',
      {'is_private_owner': 0},
      where: 'id != ? AND is_private_owner != 0',
      whereArgs: [ownerId],
    );
    await database.update(
      'users',
      {'is_private_owner': 1},
      where: 'id = ? AND is_private_owner != 1',
      whereArgs: [ownerId],
    );
  }

  Future<void> _createSaleReturnsTable(DatabaseExecutor database) async {
    await database.execute(
      "CREATE TABLE sale_returns (id TEXT PRIMARY KEY, sale_id TEXT NOT NULL, product_id TEXT NOT NULL, depot_id TEXT NOT NULL, pieces INTEGER NOT NULL, created_at INTEGER NOT NULL, status TEXT NOT NULL DEFAULT 'approved')",
    );
  }

  Future<void> _createPayrollTable(DatabaseExecutor database) async {
    await database.execute(
      'CREATE TABLE operator_payments (id TEXT PRIMARY KEY, operator_id TEXT NOT NULL, amount REAL NOT NULL, paid_at INTEGER NOT NULL)',
    );
  }

  Future<WorkshopData> loadWorkshop() async {
    final database = await _database;
    final products = (await database.query(
      'products',
      orderBy: 'name',
    )).map(_productFromRow).toList();
    final depots = (await database.query(
      'depots',
      orderBy: 'name',
    )).map(_depotFromRow).toList();
    final categories = (await database.query(
      'categories',
      orderBy: 'name',
    )).map(_categoryFromRow).toList();
    final catalogFamilies = (await database.query(
      'catalog_families',
      orderBy: 'name COLLATE NOCASE, id',
    )).map(CatalogFamily.fromRow).toList();
    final machines = (await database.query(
      'machines',
      orderBy: 'name',
    )).map(_machineFromRow).toList();
    final operations = (await database.query(
      'operations',
      orderBy: 'started_at',
    )).map(_operationFromRow).toList();
    final stockAdditions = (await database.query(
      'stock_additions',
      orderBy: 'created_at DESC, id DESC',
    )).map(_stockAdditionFromRow).toList();
    final suppliers = (await database.query(
      'suppliers',
      orderBy: 'name',
    )).map(_supplierFromRow).toList();
    final clients = (await database.query(
      'clients',
      orderBy: 'name, company',
    )).map(_clientFromRow).toList();
    final competitors = (await database.query(
      'competitors',
      orderBy: 'name',
    )).map(_competitorFromRow).toList();
    final transactionPayments = (await database.query(
      'transaction_payments',
      orderBy: 'created_at DESC',
    )).map(_transactionPaymentFromRow).toList();
    final sales = (await database.query(
      'sales',
      orderBy: 'created_at DESC',
    )).map(_saleFromRow).toList();
    final stockTransfers = (await database.query(
      'stock_transfers',
      orderBy: 'created_at DESC',
    )).map(_stockTransferFromRow).toList();
    final saleReturns = (await database.query(
      'sale_returns',
      orderBy: 'created_at DESC',
    )).map(_saleReturnFromRow).toList();
    final payments = (await database.query(
      'operator_payments',
      orderBy: 'paid_at DESC',
    )).map(_paymentFromRow).toList();
    final stockRows = await database.rawQuery(
      'SELECT product_id, SUM(pieces) AS pieces FROM stock_additions WHERE draft = 0 GROUP BY product_id',
    );
    final received = <String, int>{
      for (final row in stockRows)
        row['product_id'] as String: (row['pieces'] as num).toInt(),
    };
    return WorkshopData(
      products: products,
      depots: depots,
      categories: categories,
      catalogFamilies: catalogFamilies,
      machines: machines,
      operations: operations,
      stockAdditions: stockAdditions,
      suppliers: suppliers,
      clients: clients,
      competitors: competitors,
      transactionPayments: transactionPayments,
      sales: sales,
      stockTransfers: stockTransfers,
      saleReturns: saleReturns,
      payments: payments,
      received: received,
    );
  }

  Future<DateTime?> lastBackupAt() async {
    final rows = await (await _database).query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: const ['last_backup_at'],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final timestamp = int.tryParse(rows.single['value'] as String);
    return timestamp == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(timestamp);
  }

  Future<void> recordSuccessfulBackup(DateTime time) async {
    await (await _database).insert('app_settings', {
      'key': 'last_backup_at',
      'value': time.millisecondsSinceEpoch.toString(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<bool> automaticBackupsEnabled() async {
    final rows = await (await _database).query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: const ['automatic_backups_enabled'],
      limit: 1,
    );
    return rows.isNotEmpty && rows.single['value'] == 'true';
  }

  Future<void> setAutomaticBackupsEnabled(bool enabled) async {
    await (await _database).insert('app_settings', {
      'key': 'automatic_backups_enabled',
      'value': enabled.toString(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<double> meterRate() async {
    final rows = await (await _database).query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: const ['operator_meter_rate'],
      limit: 1,
    );
    return rows.isEmpty ? 7 : number(rows.single['value'] as String? ?? '7');
  }

  Future<void> setMeterRate(double rate) async {
    await (await _database).insert('app_settings', {
      'key': 'operator_meter_rate',
      'value': rate.toString(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Uint8List> createBackup(String passphrase) async {
    final database = await _database;
    final tables = <String, Object?>{};
    for (final table in _backupTables) {
      final rows = await database.query(table);
      tables[table] = _encodeBackupRows(table, rows);
    }
    final raw = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'format': _backupFormat,
          'version': _backupVersion,
          'created_at': DateTime.now().toIso8601String(),
          'tables': tables,
        }),
      ),
    );
    final envelope = await PasswordSecurity.encryptBackup(raw, passphrase);
    return Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'format': _encryptedBackupFormat,
          'version': 1,
          ...envelope,
        }),
      ),
    );
  }

  Future<void> restoreBackup(Uint8List bytes, String passphrase) async {
    final envelope = jsonDecode(utf8.decode(bytes));
    if (envelope is! Map ||
        envelope['format'] != _encryptedBackupFormat ||
        envelope['version'] != 1) {
      throw const FormatException(
        'Cette sauvegarde n’est pas chiffrée ou est invalide.',
      );
    }
    final decoded = jsonDecode(
      utf8.decode(await PasswordSecurity.decryptBackup(envelope, passphrase)),
    );
    final backupVersion = decoded is Map ? decoded['version'] : null;
    if (decoded is! Map ||
        decoded['format'] != _backupFormat ||
        backupVersion is! int ||
        backupVersion < 1 ||
        backupVersion > _backupVersion ||
        decoded['tables'] is! Map) {
      throw const FormatException(
        'Fichier de sauvegarde FORAGE ZOUHOUR invalide.',
      );
    }
    final rawTables = decoded['tables'] as Map;
    final restoredTables = <String, List<Map<String, Object?>>>{};
    for (final table in _backupTables) {
      final rawRows = rawTables[table];
      if (rawRows == null &&
          const {
            'suppliers',
            'clients',
            'sales',
            'competitors',
            'transaction_payments',
            'stock_transfers',
            'sale_returns',
            'operator_payments',
            'catalog_families',
          }.contains(table)) {
        restoredTables[table] = const [];
        continue;
      }
      if (rawRows is! List) {
        throw const FormatException('La sauvegarde est incomplète.');
      }
      restoredTables[table] = _decodeBackupRows(table, rawRows);
    }

    await (await _database).transaction((transaction) async {
      for (final table in _backupTables.reversed) {
        await transaction.delete(table);
      }
      for (final table in _backupTables) {
        for (final row in restoredTables[table]!) {
          await transaction.insert(table, row);
        }
      }
      await transaction.insert('depots', const {
        'id': _generalDepotId,
        'name': 'Stock général',
        'image': null,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    });
  }

  Future<void> clearWorkshopData() async {
    await (await _database).transaction((transaction) async {
      for (final table in _backupTables.reversed) {
        if (table == 'users') continue;
        await transaction.delete(table);
      }
      await transaction.insert('depots', const {
        'id': _generalDepotId,
        'name': 'Stock général',
        'image': null,
      });
    });
  }

  /// Returns a transport-neutral snapshot for a future sync provider.
  Future<Map<String, List<Map<String, Object?>>>> exportSyncSnapshot() async {
    final database = await _database;
    final data = <String, List<Map<String, Object?>>>{};
    for (final table in _syncTables) {
      final rows = await database.query(table);
      data[table] = rows.map((row) => _cloudRow(table, row)).toList();
    }
    return data;
  }

  /// Replaces the local mirror after a signed-in owner downloads their
  /// workspace from a trusted sync provider. It is transactional so a partial download can
  /// never leave the workshop in an inconsistent state.
  Future<void> replaceFromSyncSnapshot(
    Map<String, List<Map<String, Object?>>> cloudData,
  ) async {
    if (_syncTables.any(
      (table) => table != 'catalog_families' && !cloudData.containsKey(table),
    )) {
      throw const FormatException('La sauvegarde distante est incomplète.');
    }
    await (await _database).transaction((transaction) async {
      for (final table in _syncTables.reversed) {
        await transaction.delete(table);
      }
      for (final table in _syncTables) {
        for (final row in cloudData[table] ?? const []) {
          await transaction.insert(table, _cloudRowForDatabase(table, row));
        }
      }
      await transaction.insert('depots', const {
        'id': _generalDepotId,
        'name': 'Stock général',
        'image': null,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    });
  }

  Map<String, Object?> _cloudRow(String table, Map<String, Object?> row) {
    final result = <String, Object?>{};
    for (final entry in row.entries) {
      if (table == 'categories' &&
          entry.key == 'families' &&
          entry.value == '[]') {
        continue;
      }
      // SQLite returns BLOB values as Uint8List. JSON cannot represent raw
      // bytes, so encode them for the shared Supabase snapshot. The `images`
      // fields are already JSON arrays of Base64 strings and pass through
      // unchanged.
      result[entry.key] = entry.value is Uint8List
          ? base64Encode(compactImageForStorage(entry.value as Uint8List))
          : entry.key == 'images' && entry.value is String
          ? compactImageListJson(entry.value as String)
          : entry.value;
    }
    return result;
  }

  Map<String, Object?> _cloudRowForDatabase(
    String table,
    Map<String, Object?> row,
  ) {
    final result = Map<String, Object?>.from(row);
    final binaryColumns = _binaryBackupColumns[table] ?? const <String>{};
    for (final column in binaryColumns) {
      final value = result[column];
      if (value is String) {
        // Images were compacted before being uploaded. Re-compressing every
        // photograph while restoring a mirror can block the UI for seconds.
        result[column] = base64Decode(value);
      }
    }
    // `images` is already a compact Base64 JSON list in the snapshot.

    // These defaults preserve compatibility with snapshots produced before
    // photos were synchronized.
    if (table == 'categories' && !result.containsKey('image')) {
      result['image'] = Uint8List(0);
    }
    if (table == 'products' || table == 'depots' || table == 'machines') {
      if (!result.containsKey('image')) result['image'] = null;
    }
    if (table == 'operations') {
      for (final column in const [
        'final_image',
        'remainder_image',
        'scrap_image',
      ]) {
        if (!result.containsKey(column)) result[column] = null;
      }
    }
    return result;
  }

  List<Map<String, Object?>> _encodeBackupRows(
    String table,
    List<Map<String, Object?>> rows,
  ) {
    final binaryColumns = _binaryBackupColumns[table] ?? const <String>{};
    return rows
        .map(
          (row) => row.map(
            (key, value) => MapEntry(
              key,
              binaryColumns.contains(key) && value != null
                  ? base64Encode(value as Uint8List)
                  : value,
            ),
          ),
        )
        .toList();
  }

  List<Map<String, Object?>> _decodeBackupRows(
    String table,
    List<dynamic> rows,
  ) {
    final binaryColumns = _binaryBackupColumns[table] ?? const <String>{};
    return rows.map((rawRow) {
      if (rawRow is! Map) {
        throw const FormatException(
          'La sauvegarde contient une ligne invalide.',
        );
      }
      final row = <String, Object?>{};
      for (final entry in rawRow.entries) {
        final key = entry.key.toString();
        final value = entry.value;
        if (binaryColumns.contains(key) && value != null) {
          if (value is! String) {
            throw const FormatException(
              'Une image de sauvegarde est invalide.',
            );
          }
          row[key] = base64Decode(value);
        } else if (value is String ||
            value is num ||
            value is bool ||
            value == null) {
          row[key] = value;
        } else {
          throw const FormatException(
            'La sauvegarde contient une valeur invalide.',
          );
        }
      }
      return row;
    }).toList();
  }

  /// A category contains only the raw products a machine can consume. This
  /// also cleans category data created by older versions of the application.
  Future<AppUser> insertUser(AppUser user) async {
    final protected = user.copyWith(
      password: await _passwordForStorage(user.password),
    );
    await (await _database).insert('users', _userToRow(protected));
    return protected;
  }

  Future<AppUser> updateUser(AppUser user) async {
    final database = await _database;
    final protected = user.copyWith(
      password: await _passwordForStorage(user.password),
    );
    if (!protected.isAdmin) {
      final admins = await database.query(
        'users',
        columns: ['id'],
        where: 'admin = 1 AND id != ?',
        whereArgs: [protected.id],
        limit: 1,
      );
      final current = await database.query(
        'users',
        columns: ['admin'],
        where: 'id = ?',
        whereArgs: [protected.id],
        limit: 1,
      );
      if (current.isNotEmpty &&
          current.single['admin'] == 1 &&
          admins.isEmpty) {
        throw StateError(
          'Le dernier administrateur ne peut pas perdre ses droits.',
        );
      }
    }
    await database.update(
      'users',
      _userToRow(protected),
      where: 'id = ?',
      whereArgs: [protected.id],
    );
    return protected;
  }

  Future<LoginResult> authenticate(String username, String password) async {
    final database = await _database;
    final rows = await database.query(
      'users',
      where: 'LOWER(username) = ?',
      whereArgs: [username.trim().toLowerCase()],
      limit: 1,
    );
    if (rows.isEmpty) {
      return const LoginResult.failure(LoginFailure.invalidCredentials);
    }
    final row = rows.single;
    final user = _userFromRow(row);
    final now = DateTime.now();
    final lockedUntil = row['locked_until'] as int?;
    if (lockedUntil != null && lockedUntil > now.millisecondsSinceEpoch) {
      return const LoginResult.failure(LoginFailure.temporarilyLocked);
    }
    final storedPassword = row['password'] as String;
    // Users created before the security upgrade have a legacy plain-text
    // value. It is accepted once and immediately replaced with a hash.
    final verified = CredentialSecurity.isHash(storedPassword)
        ? await CredentialSecurity.verify(password, storedPassword)
        : _legacyConstantTimeEquals(password, storedPassword);
    if (!verified) {
      final attempts = (row['failed_attempts'] as int? ?? 0) + 1;
      final lockUntil = attempts >= _maximumFailedLogins
          ? now.add(_lockoutDuration).millisecondsSinceEpoch
          : null;
      await database.update(
        'users',
        {'failed_attempts': attempts, 'locked_until': lockUntil},
        where: 'id = ?',
        whereArgs: [user.id],
      );
      if (lockUntil != null) {
        return const LoginResult.failure(LoginFailure.temporarilyLocked);
      }
      return const LoginResult.failure(LoginFailure.invalidCredentials);
    }
    if (!user.canLogIn) {
      return const LoginResult.failure(LoginFailure.inactiveAccount);
    }
    final protected = CredentialSecurity.isHash(storedPassword)
        ? user
        : user.copyWith(password: await CredentialSecurity.hash(password));
    await database.update(
      'users',
      {
        'password': protected.password,
        'failed_attempts': 0,
        'locked_until': null,
      },
      where: 'id = ?',
      whereArgs: [user.id],
    );
    await recordLogin(user.id);
    return LoginResult.success(protected);
  }

  Future<String> _passwordForStorage(String value) =>
      CredentialSecurity.isHash(value)
      ? Future.value(value)
      : CredentialSecurity.hash(value);

  bool _legacyConstantTimeEquals(String left, String right) {
    final leftBytes = utf8.encode(left);
    final rightBytes = utf8.encode(right);
    if (leftBytes.length != rightBytes.length) return false;
    var difference = 0;
    for (var index = 0; index < leftBytes.length; index++) {
      difference |= leftBytes[index] ^ rightBytes[index];
    }
    return difference == 0;
  }

  Future<void> recordLogin(String userId) async {
    final database = await _database;
    final now = DateTime.now();
    // A previous application shutdown may not have emitted logout. Close that
    // stale session before starting a new, auditable one.
    await database.update(
      'user_sessions',
      {'logged_out_at': now.millisecondsSinceEpoch},
      where: 'user_id = ? AND logged_out_at IS NULL',
      whereArgs: [userId],
    );
    await database.insert('user_sessions', {
      'id': now.microsecondsSinceEpoch.toString(),
      'user_id': userId,
      'logged_in_at': now.millisecondsSinceEpoch,
    });
  }

  Future<void> recordLogout(String userId) async {
    final database = await _database;
    final sessions = await database.query(
      'user_sessions',
      where: 'user_id = ? AND logged_out_at IS NULL',
      whereArgs: [userId],
      orderBy: 'logged_in_at DESC',
      limit: 1,
    );
    if (sessions.isNotEmpty) {
      await database.update(
        'user_sessions',
        {'logged_out_at': DateTime.now().millisecondsSinceEpoch},
        where: 'id = ?',
        whereArgs: [sessions.first['id']],
      );
    }
  }

  Future<List<UserSession>> loadUserSessions(String userId) async =>
      (await _database)
          .query(
            'user_sessions',
            where: 'user_id = ?',
            whereArgs: [userId],
            orderBy: 'logged_in_at DESC',
          )
          .then(
            (rows) => rows
                .map(
                  (row) => UserSession(
                    id: row['id'] as String,
                    userId: row['user_id'] as String,
                    loggedInAt: DateTime.fromMillisecondsSinceEpoch(
                      row['logged_in_at'] as int,
                    ),
                    loggedOutAt: row['logged_out_at'] == null
                        ? null
                        : DateTime.fromMillisecondsSinceEpoch(
                            row['logged_out_at'] as int,
                          ),
                  ),
                )
                .toList(),
          );
  Future<void> insertProduct(Product product) async =>
      (await _database).insert('products', _productToRow(product));

  Future<ProductCategory?> insertCatalogProduct(
    Product product,
    String? categoryId,
    String? familyId,
  ) async {
    return (await _database).transaction((transaction) async {
      await transaction.insert('products', _productToRow(product));
      if (categoryId == null) return null;
      final rows = await transaction.query(
        'categories',
        where: 'id = ?',
        whereArgs: [categoryId],
      );
      if (rows.isEmpty) throw StateError('Catégorie introuvable.');
      final category = _categoryFromRow(rows.single);
      if (familyId != null && !category.families.any((f) => f.id == familyId)) {
        throw StateError('Famille introuvable.');
      }
      final updated = category.withProductInFamily(product.id, familyId);
      await transaction.update(
        'categories',
        _categoryToRow(updated),
        where: 'id = ?',
        whereArgs: [categoryId],
      );
      return updated;
    });
  }

  Future<void> updateProduct(Product product) async => (await _database).update(
    'products',
    _productToRow(product),
    where: 'id = ?',
    whereArgs: [product.id],
  );
  Future<void> insertDepot(Depot depot) async =>
      (await _database).insert('depots', _depotToRow(depot));
  Future<void> insertCategory(ProductCategory category) async =>
      (await _database).insert('categories', _categoryToRow(category));

  Future<void> saveCatalogFamily(CatalogFamily family) async {
    final database = await _database;
    await database.transaction((transaction) async {
      final uniqueName = (await transaction.query('catalog_families')).every(
        (row) =>
            row['id'] == family.id ||
            (row['name'] as String).toLowerCase() != family.name.toLowerCase(),
      );
      if (!uniqueName) throw StateError('Ce nom de famille existe déjà.');
      final assigned = family.categoryIds.toSet();
      final valid = (await transaction.query(
        'categories',
        columns: ['id'],
      )).map((row) => row['id'] as String).toSet();
      if (!valid.containsAll(assigned)) {
        throw StateError('Une catégorie sélectionnée est introuvable.');
      }
      for (final row in await transaction.query('catalog_families')) {
        final other = CatalogFamily.fromRow(row);
        if (other.id == family.id) continue;
        final remaining = other.categoryIds
            .where((id) => !assigned.contains(id))
            .toList();
        if (remaining.length != other.categoryIds.length) {
          await transaction.update(
            'catalog_families',
            {'category_ids': jsonEncode(remaining)},
            where: 'id = ?',
            whereArgs: [other.id],
          );
        }
      }
      await transaction.insert(
        'catalog_families',
        family.toRow(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  Future<void> insertCategoryInFamily(
    ProductCategory category,
    String familyId,
  ) async {
    await (await _database).transaction((transaction) async {
      final rows = await transaction.query(
        'catalog_families',
        where: 'id = ?',
        whereArgs: [familyId],
      );
      if (rows.isEmpty) throw StateError('Famille introuvable.');
      final family = CatalogFamily.fromRow(rows.single);
      await transaction.insert('categories', _categoryToRow(category));
      await transaction.update(
        'catalog_families',
        {
          'category_ids': jsonEncode([...family.categoryIds, category.id]),
        },
        where: 'id = ?',
        whereArgs: [familyId],
      );
    });
  }

  Future<void> updateCategory(ProductCategory category) async =>
      (await _database).update(
        'categories',
        _categoryToRow(category),
        where: 'id = ?',
        whereArgs: [category.id],
      );
  Future<void> insertMachine(FactoryMachine machine) async =>
      (await _database).insert('machines', _machineToRow(machine));
  Future<void> updateMachine(FactoryMachine machine) async =>
      (await _database).update(
        'machines',
        _machineToRow(machine),
        where: 'id = ?',
        whereArgs: [machine.id],
      );
  Future<void> deleteMachine(String id) async =>
      (await _database).delete('machines', where: 'id = ?', whereArgs: [id]);
  Future<void> updateDepot(Depot depot) async => (await _database).update(
    'depots',
    _depotToRow(depot),
    where: 'id = ?',
    whereArgs: [depot.id],
  );
  Future<void> deleteDepot(String id) async {
    if (id == _generalDepotId) {
      throw StateError('Le dépôt général ne peut pas être supprimé.');
    }
    await (await _database).delete('depots', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> insertOperation(Operation operation) async =>
      (await _database).insert('operations', _operationToRow(operation));
  Future<void> insertSupplier(Supplier supplier) async =>
      (await _database).insert('suppliers', _supplierToRow(supplier));
  Future<void> insertClient(Client client) async =>
      (await _database).insert('clients', _clientToRow(client));
  Future<void> insertCompetitor(Competitor competitor) async =>
      (await _database).insert('competitors', _competitorToRow(competitor));
  Future<void> insertTransactionPayments({
    String? saleId,
    int? stockAdditionId,
    required List<PaymentAllocation> allocations,
  }) async {
    if (allocations.isEmpty) return;
    final database = await _database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = database.batch();
    for (final allocation in allocations) {
      batch.insert('transaction_payments', {
        'id': '$now-${Random.secure().nextInt(1 << 32)}',
        'sale_id': saleId,
        'stock_addition_id': stockAdditionId,
        'source': allocation.source.name,
        'competitor_id': allocation.competitorId,
        'payment_mode': allocation.mode,
        'amount': allocation.amount,
        'created_at': now,
      });
    }
    await batch.commit(noResult: true);
  }

  Future<List<TransactionPayment>> loadTransactionPayments() async =>
      (await (await _database).query(
        'transaction_payments',
        orderBy: 'created_at DESC',
      )).map(_transactionPaymentFromRow).toList();
  Future<void> insertSale(Sale sale) async =>
      (await _database).insert('sales', _saleToRow(sale));
  Future<void> insertSaleReturn(SaleReturn saleReturn) async =>
      (await _database).insert('sale_returns', _saleReturnToRow(saleReturn));
  Future<void> updateSaleReturn(SaleReturn saleReturn) async =>
      (await _database).update(
        'sale_returns',
        _saleReturnToRow(saleReturn),
        where: 'id = ?',
        whereArgs: [saleReturn.id],
      );
  Future<void> insertOperatorPayment(OperatorPayment payment) async =>
      (await _database).insert('operator_payments', _paymentToRow(payment));
  Future<StockAddition> addStock(StockAddition addition) async {
    final id = await (await _database).insert('stock_additions', {
      'product_id': addition.productId,
      'depot_id': addition.depotId,
      'pieces': addition.pieces,
      'receipt_number': addition.receiptNumber,
      'supplier_id': addition.supplierId,
      'return_purchase_id': addition.returnOfPurchaseId,
      'quantity': addition.quantity,
      'unit': addition.unit.name,
      'images': _imagesToJson(addition.images),
      'transport_charge': addition.transportCharge.name,
      'created_at': addition.addedAt.millisecondsSinceEpoch,
      'draft': addition.draft ? 1 : 0,
    });
    return StockAddition(
      id: id,
      productId: addition.productId,
      depotId: addition.depotId,
      pieces: addition.pieces,
      receiptNumber: addition.receiptNumber,
      supplierId: addition.supplierId,
      returnOfPurchaseId: addition.returnOfPurchaseId,
      quantity: addition.quantity,
      unit: addition.unit,
      images: addition.images,
      addedAt: addition.addedAt,
      draft: addition.draft,
      transportCharge: addition.transportCharge,
      payments: addition.payments,
    );
  }

  Future<void> updateStockAddition(StockAddition addition) async =>
      (await _database).update(
        'stock_additions',
        {
          'pieces': addition.pieces,
          'receipt_number': addition.receiptNumber,
          'quantity': addition.quantity,
          'unit': addition.unit.name,
          'return_purchase_id': addition.returnOfPurchaseId,
          'transport_charge': addition.transportCharge.name,
          'draft': addition.draft ? 1 : 0,
        },
        where: 'id = ?',
        whereArgs: [addition.id],
      );
  Future<void> updateSale(Sale sale) async => (await _database).update(
    'sales',
    _saleToRow(sale),
    where: 'id = ?',
    whereArgs: [sale.id],
  );
  Future<void> insertStockTransfer(StockTransfer transfer) async =>
      (await _database).insert(
        'stock_transfers',
        _stockTransferToRow(transfer),
      );
  Future<void> updateStockTransfer(StockTransfer transfer) async =>
      (await _database).update(
        'stock_transfers',
        _stockTransferToRow(transfer),
        where: 'id = ?',
        whereArgs: [transfer.id],
      );
  Future<void> deleteStockAddition(int id) async {
    final database = await _database;
    await database.transaction((transaction) async {
      await transaction.rawDelete(
        'DELETE FROM transaction_payments WHERE stock_addition_id = ? OR stock_addition_id IN (SELECT id FROM stock_additions WHERE return_purchase_id = ?)',
        [id, id],
      );
      await transaction.delete(
        'stock_additions',
        where: 'return_purchase_id = ?',
        whereArgs: [id],
      );
      await transaction.delete(
        'stock_additions',
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  Future<void> deleteStockTransfer(String id) async => (await _database).delete(
    'stock_transfers',
    where: 'id = ?',
    whereArgs: [id],
  );
  Future<void> deleteSaleReturn(String id) async => (await _database).delete(
    'sale_returns',
    where: 'id = ?',
    whereArgs: [id],
  );
  Future<void> deleteOperation(String id) async =>
      (await _database).delete('operations', where: 'id = ?', whereArgs: [id]);
  Future<void> deleteSaleAndReturns(String id) async {
    await (await _database).transaction((transaction) async {
      await transaction.delete(
        'transaction_payments',
        where: 'sale_id = ?',
        whereArgs: [id],
      );
      await transaction.delete(
        'sale_returns',
        where: 'sale_id = ?',
        whereArgs: [id],
      );
      await transaction.delete('sales', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<void> deleteCategory(String id) async {
    await (await _database).transaction((transaction) async {
      for (final row in await transaction.query('catalog_families')) {
        final family = CatalogFamily.fromRow(row);
        if (!family.categoryIds.contains(id)) continue;
        await transaction.update(
          'catalog_families',
          {
            'category_ids': jsonEncode(
              family.categoryIds.where((value) => value != id).toList(),
            ),
          },
          where: 'id = ?',
          whereArgs: [family.id],
        );
      }
      await transaction.delete('categories', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<void> deleteProductAndHistory(String id) async {
    final database = await _database;
    final machines = await database.query(
      'machines',
      columns: ['id'],
      where: 'output = ? OR inputs LIKE ?',
      whereArgs: [id, '%$id%'],
      limit: 1,
    );
    if (machines.isNotEmpty) {
      throw StateError(
        'Supprimez ou modifiez d’abord les machines liées à ce produit.',
      );
    }
    await database.transaction((transaction) async {
      await transaction.rawDelete(
        'DELETE FROM transaction_payments WHERE sale_id IN (SELECT id FROM sales WHERE product_id = ?) OR stock_addition_id IN (SELECT id FROM stock_additions WHERE product_id = ?)',
        [id, id],
      );
      await transaction.delete(
        'stock_transfers',
        where: 'product_id = ?',
        whereArgs: [id],
      );
      await transaction.delete(
        'sale_returns',
        where: 'product_id = ?',
        whereArgs: [id],
      );
      await transaction.delete(
        'sales',
        where: 'product_id = ?',
        whereArgs: [id],
      );
      await transaction.delete(
        'stock_additions',
        where: 'product_id = ?',
        whereArgs: [id],
      );
      await transaction.delete(
        'operations',
        where: 'product_id = ? OR output_product_id = ?',
        whereArgs: [id, id],
      );
      final categories = await transaction.query('categories');
      for (final row in categories) {
        final category = _categoryFromRow(row);
        if (!category.productIds.contains(id)) continue;
        final updated = category
            .withProductInFamily(id, null)
            .copyWith(
              productIds: category.productIds
                  .where((item) => item != id)
                  .toList(),
            );
        await transaction.update(
          'categories',
          _categoryToRow(updated),
          where: 'id = ?',
          whereArgs: [category.id],
        );
      }
      await transaction.delete('products', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<void> adjustStock({
    required String productId,
    required String depotId,
    required int pieces,
  }) async {
    if (pieces == 0) return;
    await (await _database).insert('stock_additions', {
      'product_id': productId,
      'depot_id': depotId,
      'pieces': pieces,
      'receipt_number': 'Correction développeur',
      'quantity': pieces.toDouble(),
      'unit': InventoryUnit.piece.name,
      'images': '[]',
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'draft': 0,
    });
  }

  Future<void> updateOperation(Operation operation) async =>
      (await _database).update(
        'operations',
        _operationToRow(operation),
        where: 'id = ?',
        whereArgs: [operation.id],
      );

  Map<String, Object?> _userToRow(AppUser user) => {
    'id': user.id,
    'username': user.username,
    'password': user.password,
    'full_name': user.fullName,
    'admin': user.isAdmin ? 1 : 0,
    'role': user.effectiveRole.name,
    'roles': jsonEncode(user.roles.map((role) => role.name).toList()),
    'allowed_pages': jsonEncode(
      user.allowedPages.map((page) => page.name).toList(),
    ),
    'writable_pages': jsonEncode(
      user.writablePages.map((page) => page.name).toList(),
    ),
    'status': user.status.name,
    'leave_until': user.leaveUntil?.millisecondsSinceEpoch,
    'is_private_owner': user.isPrivateOwner ? 1 : 0,
  };
  AppUser _userFromRow(Map<String, Object?> row) => AppUser(
    id: row['id'] as String,
    username: row['username'] as String,
    password: row['password'] as String,
    fullName: row['full_name'] as String,
    admin: row['admin'] == 1,
    role: UserRole.values.byName(
      (row['role'] as String?) ??
          (row['admin'] == 1 ? UserRole.admin.name : UserRole.operator.name),
    ),
    roles: _rolesFromJson(
      row['roles'] as String?,
      row['role'] as String?,
      row['admin'] == 1,
    ),
    allowedPages: _pagesFromJson(row['allowed_pages'] as String?),
    writablePages: _pagesFromJson(row['writable_pages'] as String?),
    status: UserStatus.values.byName(
      row['status'] as String? ?? UserStatus.active.name,
    ),
    leaveUntil: row['leave_until'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(row['leave_until'] as int),
    isPrivateOwner: row['is_private_owner'] == 1,
  );

  Set<UserRole> _rolesFromJson(
    String? value,
    String? fallbackRole,
    bool isAdmin,
  ) {
    if (value != null) {
      final decoded = jsonDecode(value) as List;
      if (decoded.isNotEmpty) {
        return decoded
            .map((item) => UserRole.values.byName(item as String))
            .toSet();
      }
    }
    return {
      isAdmin
          ? UserRole.admin
          : UserRole.values.byName(fallbackRole ?? UserRole.operator.name),
    };
  }

  Set<AppPage>? _pagesFromJson(String? value) {
    if (value == null) return null;
    final decoded = jsonDecode(value) as List;
    if (decoded.isEmpty) return null;
    return decoded.map((item) => AppPage.values.byName(item as String)).toSet();
  }

  Map<String, Object?> _productToRow(Product product) => {
    'id': product.id,
    'name': product.name,
    'reference': product.reference,
    'width': product.width,
    'length_meters': product.lengthMeters,
    'length_unit': product.lengthUnit.name,
    'thickness': product.thickness,
    'manufactured': product.manufactured ? 1 : 0,
    'kind': product.kind.name,
    'diameter': product.diameter,
    'diameter_is_external': product.diameterIsExternal ? 1 : 0,
    'diameter_calculated_from_dimensions':
        product.diameterCalculatedFromDimensions ? 1 : 0,
    'hose_unit': product.hoseUnit.name,
    'meters_per_piece': product.metersPerPiece,
    'initial_stock': product.initialStock,
    'initial_depot_id': product.initialDepotId,
    'material_type': product.material.name,
    'image': product.image,
    'parent_product_id': product.parentProductId,
  };
  Product _productFromRow(Map<String, Object?> row) => Product(
    id: row['id'] as String,
    name: row['name'] as String,
    reference: row['reference'] as String? ?? '',
    width: (row['width'] as num).toDouble(),
    lengthMeters: (row['length_meters'] as num).toDouble(),
    lengthUnit: LengthUnit.values.byName(row['length_unit'] as String),
    thickness: (row['thickness'] as num).toDouble(),
    kind: row['kind'] == null
        ? (row['manufactured'] == 1
              ? ProductKind.manufactured
              : ProductKind.standard)
        : ProductKind.values.byName(row['kind'] as String),
    diameter: (row['diameter'] as num?)?.toDouble(),
    diameterIsExternal: row['diameter_is_external'] != 0,
    diameterCalculatedFromDimensions:
        row['diameter_calculated_from_dimensions'] == 1,
    hoseUnit: HoseUnit.values.byName(
      (row['hose_unit'] as String?) ?? HoseUnit.piece.name,
    ),
    metersPerPiece: (row['meters_per_piece'] as num?)?.toDouble(),
    initialStock: row['initial_stock'] as int,
    initialDepotId: row['initial_depot_id'] as String? ?? _generalDepotId,
    material: MaterialType.values.byName(
      (row['material_type'] as String?) ?? MaterialType.steel.name,
    ),
    image: row['image'] as Uint8List?,
    parentProductId: row['parent_product_id'] as String?,
  );

  Map<String, Object?> _depotToRow(Depot depot) => {
    'id': depot.id,
    'name': depot.name,
    'image': depot.image,
  };
  Depot _depotFromRow(Map<String, Object?> row) => Depot(
    id: row['id'] as String,
    name: row['name'] as String,
    image: row['image'] as Uint8List?,
  );

  Map<String, Object?> _categoryToRow(ProductCategory category) => {
    'id': category.id,
    'name': category.name,
    'product_ids': jsonEncode(category.productIds),
    'families': jsonEncode(category.families),
    'image': category.image,
  };
  ProductCategory _categoryFromRow(Map<String, Object?> row) => ProductCategory(
    id: row['id'] as String,
    name: row['name'] as String,
    productIds: List<String>.from(
      jsonDecode(row['product_ids'] as String) as List,
    ),
    image: row['image'] as Uint8List? ?? Uint8List(0),
    families: [
      for (final item in jsonDecode(row['families'] as String? ?? '[]') as List)
        ProductFamily.fromJson(item as Map<String, dynamic>),
    ],
  );

  StockAddition _stockAdditionFromRow(Map<String, Object?> row) =>
      StockAddition(
        id: row['id'] as int?,
        productId: row['product_id'] as String,
        depotId: row['depot_id'] as String? ?? _generalDepotId,
        pieces: row['pieces'] as int,
        receiptNumber: row['receipt_number'] as String? ?? '',
        supplierId: row['supplier_id'] as String?,
        returnOfPurchaseId: row['return_purchase_id'] as int?,
        quantity:
            (row['quantity'] as num?)?.toDouble() ??
            (row['pieces'] as num).toDouble(),
        unit: InventoryUnit.values.byName(
          (row['unit'] as String?) ?? InventoryUnit.piece.name,
        ),
        images: _imagesFromJson(row['images'] as String? ?? '[]'),
        addedAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
        draft: row['draft'] == 1,
        transportCharge: TransportCharge.values.byName(
          row['transport_charge'] as String? ?? TransportCharge.none.name,
        ),
      );

  Map<String, Object?> _supplierToRow(Supplier supplier) => {
    'id': supplier.id,
    'name': supplier.name,
    'company': supplier.company,
    'contact': supplier.contact,
    'images': _imagesToJson(supplier.images),
  };
  Supplier _supplierFromRow(Map<String, Object?> row) => Supplier(
    id: row['id'] as String,
    name: row['name'] as String,
    company: row['company'] as String? ?? '',
    contact: row['contact'] as String? ?? '',
    images: _imagesFromJson(row['images'] as String? ?? '[]'),
  );

  Map<String, Object?> _clientToRow(Client client) => {
    'id': client.id,
    'name': client.name,
    'company': client.company,
    'phone': client.phone,
    'ice': client.ice,
    'images': _imagesToJson(client.images),
  };
  Client _clientFromRow(Map<String, Object?> row) => Client(
    id: row['id'] as String,
    name: row['name'] as String? ?? '',
    company: row['company'] as String? ?? '',
    phone: row['phone'] as String? ?? '',
    ice: row['ice'] as String? ?? '',
    images: _imagesFromJson(row['images'] as String? ?? '[]'),
  );
  Map<String, Object?> _competitorToRow(Competitor competitor) => {
    'id': competitor.id,
    'name': competitor.name,
  };
  Competitor _competitorFromRow(Map<String, Object?> row) =>
      Competitor(id: row['id'] as String, name: row['name'] as String);
  TransactionPayment _transactionPaymentFromRow(Map<String, Object?> row) =>
      TransactionPayment(
        id: row['id'] as String,
        saleId: row['sale_id'] as String?,
        stockAdditionId: row['stock_addition_id'] as int?,
        source: PaymentSource.values.byName(row['source'] as String),
        competitorId: row['competitor_id'] as String?,
        mode: row['payment_mode'] as String,
        amount: (row['amount'] as num).toDouble(),
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          row['created_at'] as int,
        ),
      );

  Map<String, Object?> _saleToRow(Sale sale) => {
    'id': sale.id,
    'product_id': sale.productId,
    'depot_id': sale.depotId,
    'client_id': sale.clientId,
    'pieces': sale.pieces,
    'quantity': sale.quantity,
    'unit': sale.unit.name,
    'images': _imagesToJson(sale.images),
    'transport_charge': sale.transportCharge.name,
    'created_at': sale.createdAt.millisecondsSinceEpoch,
    'draft': sale.draft ? 1 : 0,
  };
  Sale _saleFromRow(Map<String, Object?> row) => Sale(
    id: row['id'] as String,
    productId: row['product_id'] as String,
    depotId: row['depot_id'] as String,
    clientId: row['client_id'] as String,
    pieces: row['pieces'] as int,
    quantity: (row['quantity'] as num).toDouble(),
    unit: InventoryUnit.values.byName(row['unit'] as String),
    images: _imagesFromJson(row['images'] as String? ?? '[]'),
    createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
    draft: row['draft'] == 1,
    transportCharge: TransportCharge.values.byName(
      row['transport_charge'] as String? ?? TransportCharge.none.name,
    ),
  );
  Map<String, Object?> _stockTransferToRow(StockTransfer transfer) => {
    'id': transfer.id,
    'product_id': transfer.productId,
    'source_depot_id': transfer.sourceDepotId,
    'destination_depot_id': transfer.destinationDepotId,
    'pieces': transfer.pieces,
    'created_at': transfer.createdAt.millisecondsSinceEpoch,
    'draft': transfer.draft ? 1 : 0,
  };
  StockTransfer _stockTransferFromRow(Map<String, Object?> row) =>
      StockTransfer(
        id: row['id'] as String,
        productId: row['product_id'] as String,
        sourceDepotId: row['source_depot_id'] as String,
        destinationDepotId: row['destination_depot_id'] as String,
        pieces: row['pieces'] as int,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          row['created_at'] as int,
        ),
        draft: row['draft'] == 1,
      );
  Map<String, Object?> _saleReturnToRow(SaleReturn saleReturn) => {
    'id': saleReturn.id,
    'sale_id': saleReturn.saleId,
    'product_id': saleReturn.productId,
    'depot_id': saleReturn.depotId,
    'pieces': saleReturn.pieces,
    'created_at': saleReturn.createdAt.millisecondsSinceEpoch,
    'status': saleReturn.status.name,
  };
  SaleReturn _saleReturnFromRow(Map<String, Object?> row) => SaleReturn(
    id: row['id'] as String,
    saleId: row['sale_id'] as String,
    productId: row['product_id'] as String,
    depotId: row['depot_id'] as String,
    pieces: row['pieces'] as int,
    createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
    status: switch (row['status'] as String? ?? 'approved') {
      'pending' => ReturnValidationStatus.pending,
      'rejected' => ReturnValidationStatus.rejected,
      _ => ReturnValidationStatus.approved,
    },
  );

  Map<String, Object?> _paymentToRow(OperatorPayment payment) => {
    'id': payment.id,
    'operator_id': payment.operatorId,
    'amount': payment.amount,
    'paid_at': payment.paidAt.millisecondsSinceEpoch,
  };
  OperatorPayment _paymentFromRow(Map<String, Object?> row) => OperatorPayment(
    id: row['id'] as String,
    operatorId: row['operator_id'] as String,
    amount: (row['amount'] as num).toDouble(),
    paidAt: DateTime.fromMillisecondsSinceEpoch(row['paid_at'] as int),
  );

  String _imagesToJson(List<Uint8List> images) =>
      jsonEncode(images.map(base64Encode).toList());
  List<Uint8List> _imagesFromJson(String value) {
    try {
      return (jsonDecode(value) as List)
          .whereType<String>()
          .map(base64Decode)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Map<String, Object?> _machineToRow(FactoryMachine machine) => {
    'id': machine.id,
    'name': machine.name,
    'copies': machine.copies,
    'type': machine.type.name,
    // Kept so installations created with the first version stay readable.
    'inputs': '[]',
    'output': machine.outputId,
    'operator_ids': jsonEncode(machine.operatorIds),
    // The legacy column must remain populated on old databases. Individual
    // pictures live in `units`; an empty blob represents a temporary machine.
    'image': machine.image ?? Uint8List(0),
    'category_id': machine.categoryId,
    'temporary': machine.temporary ? 1 : 0,
    'deadline': machine.deadline?.millisecondsSinceEpoch,
    'planned_pieces': machine.plannedPieces,
    'hopper_pieces': machine.hopperPieces,
    'temporary_input_product_id': machine.temporaryInputProductId,
    'temporary_source_depot_id': machine.temporarySourceDepotId,
    'temporary_input_pieces': machine.temporaryInputPieces,
    'units': jsonEncode(
      machine.units
          .map(
            (unit) => {
              'number': unit.number,
              'image': unit.image == null ? null : base64Encode(unit.image!),
              'state': unit.state.name,
              'until': unit.unavailableUntil?.millisecondsSinceEpoch,
            },
          )
          .toList(),
    ),
  };
  FactoryMachine _machineFromRow(Map<String, Object?> row) => FactoryMachine(
    id: row['id'] as String,
    name: row['name'] as String,
    type: MachineType.values.byName(row['type'] as String),
    categoryId: row['category_id'] as String? ?? 'legacy-category',
    outputId: row['output'] as String,
    units: _unitsFromJson(row['units'] as String? ?? '[]'),
    operatorIds: List<String>.from(
      jsonDecode(row['operator_ids'] as String) as List,
    ),
    image: (row['image'] as Uint8List?)?.isEmpty == true
        ? null
        : row['image'] as Uint8List?,
    temporary: row['temporary'] == 1,
    deadline: row['deadline'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(row['deadline'] as int),
    plannedPieces: row['planned_pieces'] as int?,
    hopperPieces: row['hopper_pieces'] as int?,
    temporaryInputProductId: row['temporary_input_product_id'] as String?,
    temporarySourceDepotId: row['temporary_source_depot_id'] as String?,
    temporaryInputPieces: row['temporary_input_pieces'] as int?,
  );

  List<MachineUnit> _unitsFromJson(String value) {
    final decoded = jsonDecode(value) as List;
    return decoded.map((item) {
      final map = Map<String, dynamic>.from(item as Map);
      return MachineUnit(
        number: map['number'] as int,
        image: map['image'] is String
            ? base64Decode(map['image'] as String)
            : null,
        state: MachineUnitState.values.byName(map['state'] as String),
        unavailableUntil: map['until'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(map['until'] as int),
      );
    }).toList();
  }

  Map<String, Object?> _operationToRow(Operation operation) => {
    'id': operation.id,
    'machine_id': operation.machineId,
    'operator_id': operation.operatorId,
    'pieces': operation.pieces,
    'product_id': operation.productId,
    'source_depot_id': operation.sourceDepotId,
    'output_depot_id': operation.outputDepotId,
    'remainder_depot_id': operation.remainderDepotId,
    'scrap_depot_id': operation.scrapDepotId,
    'scrap_product_id': operation.scrapProductId,
    'machine_unit_number': operation.machineUnitNumber,
    'hopper_pieces': operation.hopperPieces,
    'started_at': operation.startedAt.millisecondsSinceEpoch,
    'finished_at': operation.finishedAt?.millisecondsSinceEpoch,
    'output_pieces': operation.outputPieces,
    'final_image': operation.finalImage,
    'remainder_image': operation.remainderImage,
    'scrap_image': operation.scrapImage,
    'needs_review': operation.needsReview ? 1 : 0,
    'scrap_pieces': operation.scrapPieces,
    'remainder_pieces': operation.remainderPieces,
    'completion_draft': operation.completionDraft ? 1 : 0,
    'validated_at': operation.validatedAt?.millisecondsSinceEpoch,
    'output_product_id': operation.outputProductId,
    'external_production': operation.externalProduction ? 1 : 0,
  };
  Operation _operationFromRow(Map<String, Object?> row) => Operation(
    id: row['id'] as String,
    machineId: row['machine_id'] as String,
    operatorId: row['operator_id'] as String,
    pieces: row['pieces'] as int,
    productId: row['product_id'] as String,
    sourceDepotId: row['source_depot_id'] as String? ?? _generalDepotId,
    machineUnitNumber: row['machine_unit_number'] as int,
    hopperPieces: row['hopper_pieces'] as int?,
    startedAt: DateTime.fromMillisecondsSinceEpoch(row['started_at'] as int),
    finishedAt: row['finished_at'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(row['finished_at'] as int),
    outputPieces: row['output_pieces'] as int?,
    finalImage: row['final_image'] as Uint8List?,
    remainderImage: row['remainder_image'] as Uint8List?,
    scrapImage: row['scrap_image'] as Uint8List?,
    outputDepotId: row['output_depot_id'] as String?,
    remainderDepotId: row['remainder_depot_id'] as String?,
    scrapDepotId: row['scrap_depot_id'] as String?,
    scrapProductId: row['scrap_product_id'] as String?,
    needsReview: row['needs_review'] == 1,
    scrapPieces: row['scrap_pieces'] as int? ?? 0,
    remainderPieces: row['remainder_pieces'] as int? ?? 0,
    completionDraft: row['completion_draft'] == 1,
    validatedAt: row['validated_at'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(row['validated_at'] as int),
    outputProductId: row['output_product_id'] as String?,
    externalProduction: row['external_production'] == 1,
  );

  Future<void> _migrateLegacyRecords(Database database) async {
    const categoryId = 'legacy-category';
    final category = await database.query(
      'categories',
      where: 'id = ?',
      whereArgs: [categoryId],
    );
    if (category.isEmpty) {
      final products = await database.query('products', columns: ['id']);
      await database.insert('categories', {
        'id': categoryId,
        'name': 'Produits existants',
        'product_ids': jsonEncode(products.map((row) => row['id']).toList()),
        'image': Uint8List(0),
      });
    }
    final machines = await database.query('machines');
    for (final machine in machines) {
      final copies = machine['copies'] as int;
      final rawUnits = machine['units'] as String? ?? '[]';
      if (machine['category_id'] == null || rawUnits == '[]') {
        final units = rawUnits == '[]'
            ? List.generate(
                copies,
                (index) => {'number': index + 1, 'state': 'ready'},
              )
            : jsonDecode(rawUnits);
        await database.update(
          'machines',
          {'category_id': categoryId, 'units': jsonEncode(units)},
          where: 'id = ?',
          whereArgs: [machine['id']],
        );
      }
    }
    final operations = await database.query('operations');
    for (final operation in operations) {
      if (operation['product_id'] == null ||
          operation['machine_unit_number'] == null) {
        final machineRows = await database.query(
          'machines',
          columns: ['output'],
          where: 'id = ?',
          whereArgs: [operation['machine_id']],
        );
        final productId = machineRows.isEmpty
            ? ''
            : machineRows.first['output'] as String;
        await database.update(
          'operations',
          {'product_id': productId, 'machine_unit_number': 1},
          where: 'id = ?',
          whereArgs: [operation['id']],
        );
      }
    }
  }
}

class ForageApp extends StatefulWidget {
  const ForageApp({super.key, this.database});

  final AppDatabase? database;

  @override
  State<ForageApp> createState() => _ForageAppState();
}

class _ForageAppState extends State<ForageApp> {
  late final AppDatabase database;
  bool get _usesCloud => widget.database == null;
  var users = <AppUser>[];
  AppUser? current;
  var loading = true;
  String? startupError;
  AppUpdate? update;
  var appearance = ForageAppearance.light;

  @override
  void initState() {
    super.initState();
    database =
        widget.database ??
        AppDatabase(
          cloudSync: SupabaseCloudSyncClient(Supabase.instance.client),
        );
    loadUsers();
    _checkForUpdate();
    _loadAppearance();
  }

  Future<void> _loadAppearance() async {
    final saved = await SecureAppPreferences.darkAppearance();
    if (!mounted || saved == null) return;
    setState(() {
      appearance = saved ? ForageAppearance.dark : ForageAppearance.light;
    });
  }

  void _setAppearance(ForageAppearance next) {
    if (appearance == next) return;
    setState(() => appearance = next);
    // Persisting the preference must never delay the visible mode change.
    unawaited(
      SecureAppPreferences.saveDarkAppearance(next == ForageAppearance.dark),
    );
  }

  Future<void> _checkForUpdate() async {
    final available = await GitHubUpdates.check();
    if (available == null) return;
    final dismissed = await SecureAppPreferences.dismissedUpdateVersion();
    if (!mounted || dismissed == available.version) return;
    setState(() => update = available);
  }

  Future<void> _startUpdate(AppUpdate available) async {
    await SecureAppPreferences.dismissUpdateVersion(available.version);
    if (mounted) setState(() => update = null);
  }

  Future<void> loadUsers() async {
    var savedUsers = <AppUser>[];
    AppUser? signedIn;
    String? error;
    try {
      if (_usesCloud) {
        // A new launch must always show the login form.  The app clears a
        // previously stored Supabase session here; signing in later during
        // this run still works normally.
        try {
          await SupabaseAccounts.signOut();
        } catch (_) {}
        signedIn = null;
        savedUsers = <AppUser>[];
      } else {
        savedUsers = await database.loadUsers();
      }
    } catch (_) {
      // A connection problem must lead to the login screen, never to a
      // permanent splash screen. Local mode keeps the failure visible.
      if (!_usesCloud) {
        error = 'Impossible d’ouvrir les données locales. Réessayez.';
      }
    }
    if (mounted) {
      setState(() {
        users = savedUsers;
        current = signedIn;
        startupError = error;
        loading = false;
      });
    }
  }

  Future<AppUser> addUser(AppUser user) async {
    final protected = _usesCloud
        ? await SupabaseAccounts.createUser(user)
        : await database.insertUser(user);
    if (mounted) setState(() => users.add(protected));
    return protected;
  }

  Future<void> createFirstAdmin(AppUser user) async {
    if (_usesCloud) {
      throw StateError('Le premier administrateur est géré dans Supabase.');
    }
    if (users.isNotEmpty) {
      throw StateError('Un compte administrateur existe déjà.');
    }
    final protected = await database.insertUser(user);
    if (!mounted) return;
    setState(() {
      users.add(protected);
      current = protected;
    });
  }

  Future<void> updateUser(AppUser user) async {
    late final AppUser protected;
    if (_usesCloud) {
      await SupabaseAccounts.updateUser(user);
      // Never retain a newly entered password in application state.
      protected = user.copyWith(password: '');
    } else {
      protected = await database.updateUser(user);
    }
    if (!mounted) return;
    setState(() {
      final index = users.indexWhere((item) => item.id == user.id);
      if (index >= 0) users[index] = protected;
      if (current?.id == user.id) current = protected;
    });
  }

  Future<LoginResult> login(String username, String password) async {
    final result = _usesCloud
        ? await SupabaseAccounts.signIn(username, password)
        : await database.authenticate(username, password);
    if (result.succeeded && mounted) setState(() => current = result.user);
    if (result.succeeded && _usesCloud) {
      final cloudUsers = await SupabaseAccounts.loadUsers();
      if (mounted) setState(() => users = cloudUsers);
    }
    return result;
  }

  /// Finishes a device-login request which was approved while the login page
  /// was open.  We deliberately do not call [login] again here: doing that
  /// would create a new device request and require a second approval.
  Future<void> acceptApprovedDeviceLogin(LoginResult result) async {
    if (!result.succeeded || !mounted) return;
    setState(() => current = result.user);
    if (_usesCloud) {
      final cloudUsers = await SupabaseAccounts.loadUsers();
      if (mounted) setState(() => users = cloudUsers);
    }
  }

  Future<void> logout() async {
    if (_usesCloud) {
      try {
        await SupabaseAccounts.signOut();
      } finally {
        if (mounted) setState(() => current = null);
      }
    } else {
      final user = current;
      if (user != null) await database.recordLogout(user.id);
    }
    if (mounted) setState(() => current = null);
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'FORAGE ZOUHOUR',
    theme: atelierTheme(),
    darkTheme: atelierDarkTheme(),
    themeMode: appearance == ForageAppearance.dark
        ? ThemeMode.dark
        : ThemeMode.light,
    builder: (context, child) => ForageAppearanceScope(
      appearance: appearance,
      onChanged: _setAppearance,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: appearance == ForageAppearance.dark
              ? Brightness.light
              : Brightness.dark,
          statusBarBrightness: appearance == ForageAppearance.dark
              ? Brightness.dark
              : Brightness.light,
          systemNavigationBarColor: appearance == ForageAppearance.dark
              ? const Color(0xFF11001C)
              : AppPalette.background,
          systemNavigationBarIconBrightness: appearance == ForageAppearance.dark
              ? Brightness.light
              : Brightness.dark,
        ),
        child: AtelierLiquidStage(
          dark: appearance == ForageAppearance.dark,
          child: _AppearanceCanvas(
            dark: appearance == ForageAppearance.dark,
            child: Stack(
              children: [
                child ?? const SizedBox.shrink(),
                if (update != null)
                  SafeArea(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: _UpdateBanner(
                        update: update!,
                        onDismiss: () => setState(() => update = null),
                        onStartUpdate: _startUpdate,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
    home: loading
        ? const Scaffold(body: Center(child: CircularProgressIndicator()))
        : startupError != null
        ? _StartupFailure(
            message: startupError!,
            onRetry: () {
              setState(() {
                loading = true;
                startupError = null;
              });
              loadUsers();
            },
          )
        : current == null
        ? _usesCloud
              ? LoginPage(
                  onLogin: login,
                  onApprovedDeviceLogin: acceptApprovedDeviceLogin,
                )
              : users.isEmpty
              ? InitialAdminSetup(onCreate: createFirstAdmin)
              : LoginPage(
                  onLogin: login,
                  onApprovedDeviceLogin: acceptApprovedDeviceLogin,
                )
        : ForageHome(
            user: current!,
            users: users,
            database: database,
            onUserAdded: addUser,
            onUserUpdated: updateUser,
            onLogout: logout,
          ),
  );
}

class _StartupFailure extends StatelessWidget {
  const _StartupFailure({
    required this.message,
    required this.onRetry,
    this.onRestoreLocalCache,
  });
  final String message;
  final VoidCallback onRetry;
  final Future<void> Function()? onRestoreLocalCache;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Aura(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Glass(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    color: AppPalette.coral,
                    size: 44,
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Démarrage impossible',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20),
                  ),
                  const SizedBox(height: 8),
                  Text(message, textAlign: TextAlign.center),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Réessayer'),
                  ),
                  if (onRestoreLocalCache != null) ...[
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () => onRestoreLocalCache!(),
                      icon: const Icon(Icons.cloud_download_outlined),
                      label: const Text('Restaurer depuis le serveur'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _UpdateBanner extends StatelessWidget {
  const _UpdateBanner({
    required this.update,
    required this.onDismiss,
    required this.onStartUpdate,
  });
  final AppUpdate update;
  final VoidCallback onDismiss;
  final Future<void> Function(AppUpdate update) onStartUpdate;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final action = FilledButton(
            onPressed: () async {
              await onStartUpdate(update);
              await launchUrl(
                Uri.parse(update.downloadUrl),
                mode: LaunchMode.externalApplication,
              );
            },
            child: const Text('Mise à jour'),
          );
          final heading = Row(
            children: [
              Icon(
                Icons.system_update_rounded,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Mise à jour ${update.version} disponible',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                tooltip: 'Fermer',
                onPressed: onDismiss,
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          );
          if (constraints.maxWidth < 520) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                heading,
                const SizedBox(height: 8),
                Align(alignment: Alignment.centerRight, child: action),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: heading),
              action,
            ],
          );
        },
      ),
    ),
  );
}

class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    required this.onLogin,
    required this.onApprovedDeviceLogin,
  });
  final Future<LoginResult> Function(String username, String password) onLogin;
  final Future<void> Function(LoginResult result) onApprovedDeviceLogin;
  @override
  State<LoginPage> createState() => _LoginPageState();
}

/// First-run bootstrap. It is only displayed when the local database has no
/// users, so there is no hard-coded administrator or factory password.
class InitialAdminSetup extends StatefulWidget {
  const InitialAdminSetup({super.key, required this.onCreate});
  final Future<void> Function(AppUser) onCreate;
  @override
  State<InitialAdminSetup> createState() => _InitialAdminSetupState();
}

class _InitialAdminSetupState extends State<InitialAdminSetup> {
  final form = GlobalKey<FormState>();
  final fullName = TextEditingController();
  final username = TextEditingController();
  final password = TextEditingController();
  final confirmation = TextEditingController();
  bool saving = false;
  String? error;

  Future<void> create() async {
    if (!(form.currentState?.validate() ?? false)) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.onCreate(
        AppUser(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          username: username.text.trim(),
          password: password.text,
          fullName: fullName.text.trim(),
          admin: true,
          role: UserRole.admin,
          roles: {UserRole.admin},
          isPrivateOwner: true,
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Impossible de créer le compte. Vérifiez les informations saisies.',
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Aura(
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Glass(
                padding: const EdgeInsets.all(22),
                child: Form(
                  key: form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(
                        Icons.admin_panel_settings_outlined,
                        size: 48,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Créer le compte administrateur',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Cette étape n’apparaît qu’au premier lancement. Conservez ce mot de passe dans un gestionnaire sécurisé.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: _atelierMuted(context)),
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: fullName,
                        decoration: const InputDecoration(
                          labelText: 'Nom complet *',
                        ),
                        validator: required,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: username,
                        decoration: const InputDecoration(
                          labelText: 'Nom d’utilisateur *',
                        ),
                        validator: usernameValidator,
                      ),
                      const SizedBox(height: 12),
                      _GlassPasswordField(
                        controller: password,
                        decoration: const InputDecoration(
                          labelText: 'Mot de passe *',
                        ),
                        validator: securePasswordValidator,
                      ),
                      const SizedBox(height: 12),
                      _GlassPasswordField(
                        controller: confirmation,
                        decoration: const InputDecoration(
                          labelText: 'Confirmer le mot de passe *',
                        ),
                        validator: (value) => value == password.text
                            ? null
                            : 'Les mots de passe ne correspondent pas.',
                      ),
                      if (error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            error!,
                            style: const TextStyle(color: Color(0xFFB42318)),
                          ),
                        ),
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: saving ? null : create,
                        child: saving
                            ? const CircularProgressIndicator()
                            : const Text('Créer et continuer'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _LoginPageState extends State<LoginPage> {
  final email = TextEditingController();
  final password = TextEditingController();
  final pattern = <int>[];
  var usesPattern = false;
  String? error;
  var authenticating = false;
  var awaitingApproval = false;
  Timer? _approvalTimer;

  Future<void> login() async {
    if (authenticating) return;
    setState(() {
      authenticating = true;
      error = null;
      awaitingApproval = false;
    });
    try {
      if (usesPattern && pattern.length < 4) {
        setState(() => error = 'Reliez au moins 4 points.');
        return;
      }
      final secret = usesPattern
          ? await passwordFromPattern(email.text, pattern)
          : password.text;
      final result = await widget.onLogin(email.text, secret);
      if (!mounted || result.succeeded) return;
      if (result.failure == LoginFailure.devicePending) {
        setState(() => awaitingApproval = true);
        _waitForAdministratorApproval();
      }
      setState(
        () => error = switch (result.failure!) {
          LoginFailure.invalidCredentials =>
            'E-mail ou mot de passe incorrect.',
          LoginFailure.temporarilyLocked =>
            'Compte temporairement verrouillé. Réessayez dans 15 minutes.',
          LoginFailure.inactiveAccount =>
            'Ce compte est en congé ou désactivé.',
          LoginFailure.devicePending => 'Demande envoyée à l’administrateur. Attendez son autorisation sur cet appareil.',
          LoginFailure.deviceRejected =>
            'Cet appareil a été refusé par l’administrateur.',
          LoginFailure.outsideSchedule =>
            'La plage horaire autorisée pour ce compte est terminée.',
          LoginFailure.serverSetupRequired => 'Le serveur doit être initialisé : appliquez la migration Supabase de contrôle des appareils.',
          LoginFailure.serviceUnavailable => 'Connexion impossible au serveur. Vérifiez Internet et la configuration Supabase.',
        },
      );
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              error = 'Connexion impossible. Vérifiez Internet puis réessayez.',
        );
      }
    } finally {
      if (mounted) setState(() => authenticating = false);
    }
  }

  void _waitForAdministratorApproval() {
    _approvalTimer?.cancel();
    _approvalTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      try {
        final result = await SupabaseAccounts.checkPendingDeviceLogin();
        if (!mounted || !result.succeeded) {
          if (mounted && result.failure == LoginFailure.deviceRejected) {
            _approvalTimer?.cancel();
            setState(() {
              awaitingApproval = false;
              error = 'Cet appareil a été refusé par l’administrateur.';
            });
          }
          if (mounted && result.failure == LoginFailure.outsideSchedule) {
            _approvalTimer?.cancel();
            setState(() {
              awaitingApproval = false;
              error = 'La plage horaire autorisée pour ce compte est terminée.';
            });
          }
          return;
        }
        _approvalTimer?.cancel();
        if (mounted) await widget.onApprovedDeviceLogin(result);
      } catch (_) {
        // Network interruptions keep the pending request intact. Poll again.
      }
    });
  }

  @override
  void dispose() {
    _approvalTimer?.cancel();
    email.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: LayoutBuilder(
      builder: (context, constraints) =>
          _buildScene(context, wide: constraints.maxWidth >= 880),
    ),
  );

  Widget _buildScene(BuildContext context, {required bool wide}) {
    final dark = ForageAppearanceScope.of(context).isDark;
    final accent = dark ? const Color(0xFFE46AFF) : const Color(0xFF427CAA);
    final foreground = dark ? const Color(0xFFFFF4FF) : AppPalette.text;
    final muted = dark ? const Color(0xFFDFC3E9) : AppPalette.muted;
    final spaciousDaylight = wide && !dark;
    final signIn = _LoginGlassPanel(
      radius: spaciousDaylight ? 54 : wide ? 40 : 30,
      accent: accent,
      padding: EdgeInsets.all(spaciousDaylight ? 42 : wide ? 34 : 20),
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (dark) ...[
                  _LoginFeatureMark(
                    Icons.shield_outlined,
                    accent: accent,
                    size: wide ? 64 : 48,
                  ),
                  SizedBox(width: wide ? 18 : 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: dark
                        ? CrossAxisAlignment.start
                        : CrossAxisAlignment.center,
                    children: [
                      Text(
                        'Connexion sécurisée',
                        textAlign: dark ? TextAlign.start : TextAlign.center,
                        style: TextStyle(
                          fontSize: spaciousDaylight ? 38 : wide ? 30 : 23,
                          letterSpacing: -.55,
                          fontWeight: FontWeight.w800,
                          color: foreground,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'Accédez à votre espace atelier',
                        textAlign: dark ? TextAlign.start : TextAlign.center,
                        style: TextStyle(
                          color: muted,
                          fontSize: spaciousDaylight ? 18 : wide ? 15 : 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: spaciousDaylight ? 35 : wide ? 30 : 20),
            TextField(
              controller: email,
              enabled: !authenticating && !awaitingApproval,
              textInputAction: TextInputAction.next,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.username],
              decoration: const InputDecoration(
                labelText: 'Adresse e-mail',
                prefixIcon: Icon(Icons.email_outlined),
              ),
            ),
            SizedBox(height: spaciousDaylight ? 16 : 12),
            Glass(
              accent: accent,
              child: SegmentedButton<bool>(
                style: dark
                    ? null
                    : SegmentedButton.styleFrom(
                        backgroundColor: const Color(0xAEEBF8FF),
                        selectedBackgroundColor: const Color(0xEB1261C4),
                        selectedForegroundColor: Colors.white,
                        side: const BorderSide(color: Color(0xA5FFFFFF)),
                        shape: const StadiumBorder(),
                        minimumSize: Size(0, spaciousDaylight ? 52 : 44),
                      ),
                segments: const [
                  ButtonSegment(
                    value: false,
                    icon: Icon(Icons.lock_outline_rounded),
                    label: Text('Mot de passe'),
                  ),
                  ButtonSegment(
                    value: true,
                    icon: Icon(Icons.gesture_rounded),
                    label: Text('Schéma'),
                  ),
                ],
                selected: {usesPattern},
                onSelectionChanged: authenticating || awaitingApproval
                    ? null
                    : (value) => setState(() => usesPattern = value.first),
              ),
            ),
            SizedBox(height: spaciousDaylight ? 16 : 12),
            if (usesPattern)
              PatternPad(
                pattern: pattern,
                onChanged: authenticating || awaitingApproval
                    ? null
                    : (value) => setState(() {
                        pattern
                          ..clear()
                          ..addAll(value);
                      }),
              )
            else
              _GlassPasswordField(
                controller: password,
                enabled: !authenticating && !awaitingApproval,
                autofillHints: const [AutofillHints.password],
                onSubmitted: authenticating ? null : (_) => login(),
                decoration: const InputDecoration(
                  labelText: 'Mot de passe',
                  prefixIcon: Icon(Icons.lock_outline_rounded),
                ),
              ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: awaitingApproval
                        ? accent.withValues(alpha: .13)
                        : AppPalette.coral.withValues(alpha: .13),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: awaitingApproval
                          ? accent.withValues(alpha: .42)
                          : AppPalette.coral.withValues(alpha: .42),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        awaitingApproval
                            ? Icons.hourglass_top_rounded
                            : Icons.error_outline_rounded,
                        color: awaitingApproval
                            ? accent
                            : AppPalette.coral,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          error!,
                          style: TextStyle(
                            color: awaitingApproval
                                ? foreground
                                : AppPalette.coral,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Padding(
              padding: EdgeInsets.symmetric(vertical: spaciousDaylight ? 18 : 5),
              child: Text(
                'Contactez un administrateur pour toute récupération d’accès.',
                style: TextStyle(fontSize: spaciousDaylight ? 14 : 12, color: muted),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: authenticating || awaitingApproval ? null : login,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  foregroundColor: Colors.white,
                  minimumSize: Size.fromHeight(spaciousDaylight ? 68 : wide ? 58 : 52),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontSize: wide ? 19 : 16,
                    fontWeight: FontWeight.w800,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28),
                  ),
                ).copyWith(
                  backgroundBuilder: _loginButtonSurface,
                ),
                child: authenticating
                    ? SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: accent,
                        ),
                      )
                    : awaitingApproval
                    ? const Text('En attente d’autorisation')
                    : const Row(
                        children: [
                          SizedBox(width: 23),
                          Expanded(
                            child: Text('Connexion', textAlign: TextAlign.center),
                          ),
                          Icon(Icons.arrow_forward_rounded, size: 23),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
    final baseTheme = Theme.of(context);
    final daylightBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(28),
      borderSide: const BorderSide(color: Color(0xD9FFFFFF), width: 1.4),
    );
    final pageTheme = dark
        ? baseTheme.copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFFE46AFF),
              onPrimary: Colors.white,
              surface: Color(0xFF22052E),
              onSurface: Color(0xFFFFF4FF),
              outline: Color(0xFFCE94E6),
            ),
            textTheme: baseTheme.textTheme.apply(
              bodyColor: foreground,
              displayColor: foreground,
            ),
            inputDecorationTheme: baseTheme.inputDecorationTheme.copyWith(
              filled: true,
              fillColor: const Color(0xCC2A0B39),
              labelStyle: TextStyle(color: muted),
              floatingLabelStyle: TextStyle(color: accent),
              prefixIconColor: accent,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Color(0xFFAE61C9)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Color(0xFFF0B2FF), width: 1.5),
              ),
            ),
          )
        : baseTheme.copyWith(
            inputDecorationTheme: baseTheme.inputDecorationTheme.copyWith(
              fillColor: const Color(0xAEEBF7FF),
              constraints: BoxConstraints(minHeight: spaciousDaylight ? 65 : 53),
              prefixIconColor: accent,
              enabledBorder: daylightBorder,
              focusedBorder: daylightBorder.copyWith(
                borderSide: BorderSide(color: accent, width: 1.5),
              ),
            ),
          );
    return Theme(
      data: pageTheme,
      child: _LoginScene(wide: wide, signIn: signIn),
    );
  }
}

class ForageHome extends StatefulWidget {
  const ForageHome({
    super.key,
    required this.user,
    required this.users,
    required this.database,
    required this.onUserAdded,
    required this.onUserUpdated,
    required this.onLogout,
  });
  final AppUser user;
  final List<AppUser> users;
  final AppDatabase database;
  final Future<AppUser> Function(AppUser) onUserAdded;
  final Future<void> Function(AppUser) onUserUpdated;
  final VoidCallback onLogout;
  @override
  State<ForageHome> createState() => _ForageHomeState();
}

class _ForageHomeState extends State<ForageHome> {
  int section = 0;
  var products = <Product>[];
  var depots = <Depot>[];
  var categories = <ProductCategory>[];
  var catalogFamilies = <CatalogFamily>[];
  var machines = <FactoryMachine>[];
  var operations = <Operation>[];
  var stockAdditions = <StockAddition>[];
  var suppliers = <Supplier>[];
  var clients = <Client>[];
  var competitors = <Competitor>[];
  var transactionPayments = <TransactionPayment>[];
  var sales = <Sale>[];
  var stockTransfers = <StockTransfer>[];
  var saleReturns = <SaleReturn>[];
  var payments = <OperatorPayment>[];
  var meterRate = 7.0;
  var received = <String, int>{};
  var loading = true;
  String? loadError;
  var _automaticBackupChecked = false;
  Timer? _cloudSyncTimer;
  Timer? _deviceRequestTimer;
  var _cloudSyncInProgress = false;
  bool _syncDeniedShown = false;
  final _announcedDeviceRequests = <String>{};

  @override
  void initState() {
    super.initState();
    _startWorkshop();
  }

  Future<void> _startWorkshop() async {
    // Show the local workshop immediately after login.  A full cloud mirror
    // can be large because it contains pictures, so it must not hold the
    // first usable frame hostage.
    await loadWorkshop();
    if (!mounted) return;
    // The full snapshot synchronizer is intentionally disabled for Windows
    // startup. A workshop with images can make the Windows process consume
    // all CPU while it serializes the snapshot, leaving the native window
    // marked as "not responding". Mobile keeps automatic cloud sync; Windows
    // stays immediately usable and opens its local mirror first.
    if (Platform.isWindows) {
      if (widget.user.isAdmin) unawaited(_pollDeviceRequests());
      return;
    }
    _cloudSyncTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _synchronizeWorkshop(),
    );
    Timer(const Duration(milliseconds: 900), () {
      if (mounted) unawaited(_synchronizeWorkshop(preferRemote: true));
    });
    if (widget.user.isAdmin) {
      await _pollDeviceRequests();
      _deviceRequestTimer = Timer.periodic(
        const Duration(seconds: 10),
        (_) => _pollDeviceRequests(),
      );
    }
  }

  Future<void> _pollDeviceRequests() async {
    try {
      final requests = await SupabaseAccounts.pendingDeviceRequests();
      for (final request in requests) {
        if (!_announcedDeviceRequests.add(request.id)) continue;
        await AppNotifications.show(
          title: 'Nouvelle demande d’appareil',
          body:
              '${appUser(request.userId)?.fullName ?? 'Un utilisateur'} souhaite se connecter depuis ${request.deviceLabel}.',
        );
      }
    } catch (_) {
      // A temporary network failure is retried on the next polling pass.
    }
  }

  Future<void> _synchronizeWorkshop({bool preferRemote = false}) async {
    if (_cloudSyncInProgress) return;
    _cloudSyncInProgress = true;
    try {
      if (widget.database.cloudSync != null) {
        final current = await SupabaseAccounts.currentUser();
        if (current == null ||
            !current.canLogIn ||
            current.effectiveRole != widget.user.effectiveRole ||
            !setEquals(current.allowedPages, widget.user.allowedPages) ||
            !setEquals(current.writablePages, widget.user.writablePages)) {
          widget.onLogout();
          return;
        }
      }
      await widget.database
          .synchronizeWithCloud(preferRemote: preferRemote)
          .timeout(const Duration(seconds: 10));
      _syncDeniedShown = false;
    } on PostgrestException catch (error) {
      if (mounted && !_syncDeniedShown) {
        _syncDeniedShown = true;
        message(
          context,
          'Le serveur a refusé la synchronisation. Vos modifications ne sont pas enregistrées sur le serveur. Contactez l’administrateur.',
        );
      }
      if (error.code == '42501' && mounted) {
        widget.onLogout();
        return;
      }
    } catch (_) {
      // The local database remains usable while a device is offline. The
      // periodic retry will upload the pending changes after reconnection.
    } finally {
      _cloudSyncInProgress = false;
    }
    if (mounted) await loadWorkshop();
  }

  @override
  void dispose() {
    _cloudSyncTimer?.cancel();
    _deviceRequestTimer?.cancel();
    super.dispose();
  }

  Future<void> loadWorkshop() async {
    try {
      // Never leave the whole native window on an endless loading screen.
      // A locked/corrupt local SQLite file is reported to the user instead
      // of blocking navigation forever after a successful login.
      final data = await widget.database
          .loadWorkshop()
          .timeout(const Duration(seconds: 12));
      final savedMeterRate = await widget.database
          .meterRate()
          .timeout(const Duration(seconds: 5));
      if (!mounted) return;
      setState(() {
        products = data.products;
        depots = data.depots;
        categories = data.categories;
        catalogFamilies = data.catalogFamilies;
        machines = data.machines;
        operations = data.operations;
        stockAdditions = data.stockAdditions;
        suppliers = data.suppliers;
        clients = data.clients;
        competitors = data.competitors;
        transactionPayments = data.transactionPayments;
        sales = data.sales;
        stockTransfers = data.stockTransfers;
        saleReturns = data.saleReturns;
        payments = data.payments;
        meterRate = savedMeterRate > 0 ? savedMeterRate : 7;
        received = data.received;
        loadError = null;
        loading = false;
      });
      if (widget.user.isAdmin && !_automaticBackupChecked) {
        _automaticBackupChecked = true;
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _checkAutomaticBackup(),
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        loadError = _showStartupDiagnostics
            ? 'Impossible de charger les données de l’atelier.\n\n$error'
            : 'Impossible de charger les données de l’atelier.';
        loading = false;
      });
    }
  }

  Future<bool> _downloadBackup({bool showSuccess = true}) async {
    try {
      final passphrase = await _requestBackupPassphrase(
        title: 'Chiffrer la sauvegarde',
        confirm: true,
      );
      if (passphrase == null) return false;
      final now = DateTime.now();
      final stamp = now.toIso8601String().replaceAll(RegExp('[:.]'), '-');
      final savedFile = await FilePicker.saveFile(
        dialogTitle: 'Télécharger la sauvegarde FORAGE ZOUHOUR',
        fileName: 'forage-zouhour-backup-$stamp.json',
        bytes: await widget.database.createBackup(passphrase),
        mimeType: 'application/json',
      );
      if (savedFile == null) return false;
      await widget.database.recordSuccessfulBackup(now);
      if (mounted && showSuccess) {
        message(context, 'Sauvegarde téléchargée avec succès.');
      }
      return true;
    } catch (_) {
      if (mounted) {
        message(context, 'Impossible de télécharger la sauvegarde. Réessayez.');
      }
      return false;
    }
  }

  Future<void> _restoreBackup() async {
    try {
      final file = await FilePicker.pickFile(
        dialogTitle: 'Importer une sauvegarde FORAGE ZOUHOUR',
        type: FileType.custom,
        allowedExtensions: const ['json'],
      );
      if (file == null) return;
      final passphrase = await _requestBackupPassphrase(
        title: 'Ouvrir la sauvegarde',
      );
      if (passphrase == null) return;
      await widget.database.restoreBackup(await file.readAsBytes(), passphrase);
      await loadWorkshop();
      if (mounted) message(context, 'La sauvegarde a été restaurée.');
    } on FormatException catch (error) {
      if (mounted) message(context, error.message);
    } catch (_) {
      if (mounted) {
        message(context, 'Impossible de restaurer cette sauvegarde.');
      }
    }
  }

  Future<bool> _clearWorkshopData() async {
    final lastBackup = await widget.database.lastBackupAt();
    final hasRecentBackup =
        lastBackup != null && DateTime.now().difference(lastBackup).inDays < 5;
    if (!hasRecentBackup) {
      if (mounted) {
        message(
          context,
          'Téléchargez d’abord une nouvelle sauvegarde avant de supprimer les données.',
        );
      }
      return false;
    }
    await widget.database.clearWorkshopData();
    await loadWorkshop();
    if (mounted) {
      message(context, 'Les données de l’atelier ont été supprimées.');
    }
    return true;
  }

  Future<void> _checkAutomaticBackup() async {
    // An encrypted backup needs a passphrase and must never retain it on the
    // device. For that reason scheduled unencrypted exports are disabled.
    await widget.database.setAutomaticBackupsEnabled(false);
  }

  Future<String?> _requestBackupPassphrase({
    required String title,
    bool confirm = false,
  }) async {
    final password = TextEditingController();
    final confirmation = TextEditingController();
    String? error;
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Utilisez un mot de passe robuste et conservez-le en lieu sûr : '
                'la sauvegarde ne peut pas être récupérée sans lui.',
              ),
              const SizedBox(height: 12),
              _GlassPasswordField(
                controller: password,
                decoration: const InputDecoration(labelText: 'Mot de passe *'),
              ),
              if (confirm) ...[
                const SizedBox(height: 10),
                _GlassPasswordField(
                  controller: confirmation,
                  decoration: const InputDecoration(
                    labelText: 'Confirmer le mot de passe *',
                  ),
                ),
              ],
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    error!,
                    style: const TextStyle(color: Color(0xFFB42318)),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () {
                final validation = securePasswordValidator(password.text);
                if (validation != null) {
                  setState(() => error = validation);
                  return;
                }
                if (confirm && password.text != confirmation.text) {
                  setState(
                    () => error = 'Les mots de passe ne correspondent pas.',
                  );
                  return;
                }
                Navigator.pop(dialogContext, password.text);
              },
              child: const Text('Continuer'),
            ),
          ],
        ),
      ),
    );
  }

  int stock(String productId) {
    return depots.fold(
      0,
      (total, depot) => total + depotStock(productId, depot.id),
    );
  }

  int depotStock(String productId, String depotId) {
    final initial = product(productId)?.initialDepotId == depotId
        ? product(productId)?.initialStock ?? 0
        : 0;
    final added = stockAdditions
        .where(
          (item) =>
              !item.draft &&
              item.productId == productId &&
              item.depotId == depotId,
        )
        .fold(0, (total, item) => total + item.pieces);
    final manufactured = operations
        .where(
          (op) =>
              !op.active &&
              !op.completionDraft &&
              (op.outputProductId ?? machine(op.machineId)?.outputId) ==
                  productId &&
              (op.outputDepotId ?? 'general-depot') == depotId,
        )
        .fold(0, (total, op) => total + (op.outputPieces ?? 0));
    final consumed = operations
        .where(
          (op) =>
              op.productId == productId &&
              op.sourceDepotId == depotId &&
              // An external job is only a proposal until the validator confirms
              // it; then its source material is deducted with the output entry.
              (!op.externalProduction || !op.completionDraft),
        )
        .fold(0, (total, op) => total + op.pieces);
    final returned = operations
        .where(
          (op) =>
              !op.active &&
              !op.completionDraft &&
              op.productId == productId &&
              op.remainderDepotId == depotId,
        )
        .fold(0, (total, op) => total + op.remainderPieces);
    final scrap = operations
        .where(
          (op) =>
              !op.active &&
              !op.completionDraft &&
              op.scrapProductId == productId &&
              op.scrapDepotId == depotId,
        )
        .fold(0, (total, op) => total + op.scrapPieces);
    final sold = sales
        .where(
          (sale) =>
              !sale.draft &&
              sale.productId == productId &&
              sale.depotId == depotId,
        )
        .fold(0, (total, sale) => total + sale.pieces);
    final returnedByClients = saleReturns
        .where(
          (item) =>
              item.status == ReturnValidationStatus.approved &&
              item.productId == productId &&
              item.depotId == depotId,
        )
        .fold(0, (total, item) => total + item.pieces);
    final transferredOut = stockTransfers
        .where(
          (item) =>
              !item.draft &&
              item.productId == productId &&
              item.sourceDepotId == depotId,
        )
        .fold(0, (total, item) => total + item.pieces);
    final transferredIn = stockTransfers
        .where(
          (item) =>
              !item.draft &&
              item.productId == productId &&
              item.destinationDepotId == depotId,
        )
        .fold(0, (total, item) => total + item.pieces);
    return initial +
        added +
        manufactured -
        consumed +
        returned +
        scrap -
        sold +
        returnedByClients -
        transferredOut +
        transferredIn;
  }

  FactoryMachine? machine(String id) {
    for (final item in machines) {
      if (item.id == id) return item;
    }
    return null;
  }

  Product? product(String id) {
    for (final item in products) {
      if (item.id == id) return item;
    }
    return null;
  }

  ProductCategory? category(String id) {
    for (final item in categories) {
      if (item.id == id) return item;
    }
    return null;
  }

  Depot? depot(String id) {
    for (final item in depots) {
      if (item.id == id) return item;
    }
    return null;
  }

  AppUser? appUser(String id) {
    for (final item in widget.users) {
      if (item.id == id) return item;
    }
    return null;
  }

  Supplier? supplier(String id) {
    for (final item in suppliers) {
      if (item.id == id) return item;
    }
    return null;
  }

  Client? client(String id) {
    for (final item in clients) {
      if (item.id == id) return item;
    }
    return null;
  }

  bool get hasMyActiveOperation =>
      operations.any((op) => op.operatorId == widget.user.id && op.active);

  Product _producedVariant(Product template, Product source) {
    for (final product in products) {
      if (product.parentProductId == template.id &&
          product.width == source.width &&
          product.lengthMeters == source.lengthMeters &&
          product.lengthUnit == source.lengthUnit &&
          product.thickness == source.thickness &&
          product.material == source.material) {
        return product;
      }
    }
    final measures =
        '${formatNumber(source.lengthInChosenUnit)} ${source.lengthUnit.label} · '
        '${formatNumber(source.thickness)} mm';
    final variantName = '${template.name} · $measures';
    return Product(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: variantName,
      reference: variantName,
      width: source.width,
      lengthMeters: source.lengthMeters,
      lengthUnit: source.lengthUnit,
      thickness: source.thickness,
      kind: ProductKind.manufactured,
      initialStock: 0,
      initialDepotId: 'general-depot',
      material: source.material,
      image: template.image,
      parentProductId: template.id,
    );
  }

  /// Waste is stocked independently from usable raw material.  One reusable
  /// waste product is kept for each source product, while every operation
  /// still records the depot and the picture that prove where it was placed.
  Product _scrapVariant(Product source) {
    final id = 'scrap-${source.id}';
    return products.firstWhere(
      (product) => product.id == id,
      orElse: () => Product(
        id: id,
        name: 'Déchets · ${source.name}',
        reference: source.reference,
        width: source.width,
        lengthMeters: source.lengthMeters,
        lengthUnit: source.lengthUnit,
        thickness: source.thickness,
        kind: ProductKind.standard,
        initialStock: 0,
        initialDepotId: 'general-depot',
        material: source.material,
        image: source.image,
        parentProductId: source.id,
      ),
    );
  }

  Future<void> addProduct() async {
    if (!widget.user.canWritePage(AppPage.products)) {
      return forbidden('Seul l’administrateur peut ajouter un produit.');
    }
    final kind = await Navigator.push<ProductKind>(
      context,
      MaterialPageRoute(builder: (_) => const ProductKindPage()),
    );
    if (kind == null || !mounted) return;
    final item = await Navigator.push<ProductCreation>(
      context,
      MaterialPageRoute(
        builder: (_) => ProductForm(
          kind: kind,
          depots: depots,
          categories: categories,
          catalogFamilies: catalogFamilies,
        ),
      ),
    );
    if (!mounted || item == null) return;
    final updatedCategory = await widget.database.insertCatalogProduct(
      item.product,
      item.categoryId,
      item.familyId,
    );
    if (!mounted) return;
    setState(() {
      final index = categories.indexWhere(
        (value) => value.id == item.categoryId,
      );
      if (index >= 0 && updatedCategory != null) {
        categories[index] = updatedCategory;
      }
      products.add(item.product);
    });
    if (item.product.initialStock > 0) {
      await AppNotifications.show(
        title: 'Stock initial ajouté',
        body:
            '${productQuantityLabel(item.product, item.product.initialStock)} de ${item.product.displayReference} ont été ajoutés.',
      );
    }
  }

  Future<void> addStock({String? initialProductId}) async {
    if (!widget.user.canWritePage(AppPage.stock)) {
      return forbidden('Seul l’administrateur peut ajouter du stock.');
    }
    final item = await Navigator.push<StockAddition>(
      context,
      MaterialPageRoute(
        builder: (_) => StockForm(
          products: products.where((p) => !p.manufactured).toList(),
          categories: categories,
          catalogFamilies: catalogFamilies,
          stock: stock,
          depots: depots,
          suppliers: suppliers,
          onAddSupplier: addSupplier,
          // Purchase documents are selected from the device gallery for every
          // user; they are not evidence that must be taken live.
          allowGallery: true,
          canPreviewAttachments: widget.user.isAdmin,
          initialProductId: initialProductId,
        ),
      ),
    );
    if (!mounted || item == null) return;
    final payment = await Navigator.push<PaymentEntryResult>(
      context,
      MaterialPageRoute(builder: (_) => PaymentForm(competitors: competitors)),
    );
    if (payment == null) return;
    for (final competitor in payment.newCompetitors) {
      await widget.database.insertCompetitor(competitor);
    }
    final draft = await widget.database.addStock(
      StockAddition(
        productId: item.productId,
        depotId: item.depotId,
        pieces: item.pieces,
        receiptNumber: item.receiptNumber,
        supplierId: item.supplierId,
        returnOfPurchaseId: item.returnOfPurchaseId,
        quantity: item.quantity,
        unit: item.unit,
        images: item.images,
        addedAt: item.addedAt,
        draft: item.draft,
        transportCharge: item.transportCharge,
        payments: payment.allocations,
      ),
    );
    await widget.database.insertTransactionPayments(
      stockAdditionId: draft.id,
      allocations: payment.allocations,
    );
    final refreshedPayments = await widget.database.loadTransactionPayments();
    if (mounted) {
      setState(() {
        competitors = [...competitors, ...payment.newCompetitors];
        stockAdditions = [draft, ...stockAdditions];
        transactionPayments = refreshedPayments;
      });
      final productName =
          product(draft.productId)?.displayReference ?? 'Produit';
      message(
        context,
        'Achat enregistré comme brouillon : validation requise.',
      );
      await AppNotifications.show(
        title: 'Achat en brouillon',
        body:
            '${formatQuantity(draft.quantity, draft.unit)} de $productName attend une validation.',
      );
    }
  }

  Future<void> addStockFor(Product product) async {
    if (product.manufactured) {
      return forbidden(
        'Le stock des produits fabriqués est ajouté à la fin d’une opération.',
      );
    }
    await addStock(initialProductId: product.id);
  }

  Future<Supplier?> addSupplier() async {
    final item = await Navigator.push<Supplier>(
      context,
      MaterialPageRoute(builder: (_) => const SupplierForm()),
    );
    if (item != null) {
      await widget.database.insertSupplier(item);
      if (mounted) setState(() => suppliers.add(item));
    }
    return item;
  }

  Future<Client?> addClient() async {
    final item = await Navigator.push<Client>(
      context,
      MaterialPageRoute(builder: (_) => const ClientForm()),
    );
    if (item != null) {
      await widget.database.insertClient(item);
      if (mounted) setState(() => clients.add(item));
    }
    return item;
  }

  Future<void> addSale() async {
    if (!widget.user.canWritePage(AppPage.stock)) {
      return forbidden('Seul l’administrateur peut enregistrer une vente.');
    }
    final item = await Navigator.push<Sale>(
      context,
      MaterialPageRoute(
        builder: (_) => SaleForm(
          products: products,
          categories: categories,
          catalogFamilies: catalogFamilies,
          depots: depots,
          clients: clients,
          available: depotStock,
          onAddClient: addClient,
          allowGallery: widget.user.isAdmin,
          canPreviewAttachments: widget.user.isAdmin,
        ),
      ),
    );
    if (!mounted || item == null) return;
    final payment = await Navigator.push<PaymentEntryResult>(
      context,
      MaterialPageRoute(builder: (_) => PaymentForm(competitors: competitors)),
    );
    if (payment == null) return;
    for (final competitor in payment.newCompetitors) {
      await widget.database.insertCompetitor(competitor);
    }
    await widget.database.insertSale(item);
    await widget.database.insertTransactionPayments(
      saleId: item.id,
      allocations: payment.allocations,
    );
    final refreshedPayments = await widget.database.loadTransactionPayments();
    if (mounted) {
      setState(() {
        competitors = [...competitors, ...payment.newCompetitors];
        sales = [item, ...sales];
        transactionPayments = refreshedPayments;
      });
      message(
        context,
        'Vente enregistrée comme brouillon : validation requise.',
      );
    }
  }

  Future<SaleReturn?> returnSale(Sale sale, int pieces) async {
    if (!widget.user.canWritePage(AppPage.stock)) {
      forbidden('Vous n’avez pas le droit d’enregistrer un retour.');
      return null;
    }
    if (sale.draft) {
      forbidden('Validez d’abord cette vente avant d’enregistrer un retour.');
      return null;
    }
    final alreadyReturned = saleReturns
        .where(
          (item) =>
              item.saleId == sale.id &&
              item.status != ReturnValidationStatus.rejected,
        )
        .fold(0, (total, item) => total + item.pieces);
    final remaining = sale.pieces - alreadyReturned;
    if (pieces <= 0 || pieces > remaining) {
      forbidden(
        'La quantité retournée doit être comprise entre 1 et $remaining.',
      );
      return null;
    }
    final item = SaleReturn(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      saleId: sale.id,
      productId: sale.productId,
      depotId: sale.depotId,
      pieces: pieces,
      createdAt: DateTime.now(),
      status: ReturnValidationStatus.pending,
    );
    await widget.database.insertSaleReturn(item);
    if (mounted) {
      setState(() => saleReturns = [item, ...saleReturns]);
      message(
        context,
        'Retour envoyé à la validation : le stock ne changera qu’après acceptation.',
      );
      await AppNotifications.show(
        title: 'Retour client à valider',
        body:
            'Un retour de ${product(sale.productId)?.displayReference ?? 'produit'} attend votre contrôle.',
      );
    }
    return item;
  }

  Future<StockAddition?> returnPurchase(
    StockAddition purchase,
    int pieces,
  ) async {
    if (!widget.user.canWritePage(AppPage.stock)) {
      forbidden(
        'Vous n’avez pas le droit d’enregistrer un retour fournisseur.',
      );
      return null;
    }
    if (purchase.id == null ||
        purchase.draft ||
        purchase.returnOfPurchaseId != null) {
      forbidden('Validez d’abord l’achat d’origine avant de créer un retour.');
      return null;
    }
    final alreadyReturned = stockAdditions
        .where((item) => item.returnOfPurchaseId == purchase.id)
        .fold(0, (total, item) => total + item.pieces.abs());
    final remaining = purchase.pieces - alreadyReturned;
    if (pieces <= 0 || pieces > remaining) {
      forbidden('La quantité retournée dépasse la quantité achetée restante.');
      return null;
    }
    if (pieces > depotStock(purchase.productId, purchase.depotId)) {
      forbidden('Le stock disponible dans ce dépôt est insuffisant.');
      return null;
    }
    final item = await widget.database.addStock(
      StockAddition(
        productId: purchase.productId,
        depotId: purchase.depotId,
        pieces: -pieces,
        receiptNumber: 'Retour achat #${purchase.id}',
        supplierId: purchase.supplierId,
        returnOfPurchaseId: purchase.id,
        quantity: -pieces.toDouble(),
        unit: InventoryUnit.piece,
        images: const [],
        addedAt: DateTime.now(),
      ),
    );
    if (!mounted) return null;
    setState(() => stockAdditions = [item, ...stockAdditions]);
    message(context, 'Retour fournisseur envoyé à la validation.');
    return item;
  }

  void openStockRecords() {
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => StockRecordsPage(
          products: products,
          additions: stockAdditions,
          sales: sales,
          transfers: stockTransfers,
          depots: depots,
          saleReturns: saleReturns,
          suppliers: suppliers,
          clients: clients,
          depotName: (id) => depot(id)?.name ?? 'Stock général',
          canReturn: widget.user.canWritePage(AppPage.stock),
          onReturn: returnSale,
          canReturnPurchase: widget.user.canWritePage(AppPage.stock),
          onReturnPurchase: returnPurchase,
          onOpenAttachments: widget.user.isAdmin ? _openTransactionPhotos : null,
        ),
      ),
    );
  }

  void openTransactionPayments() {
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => TransactionPaymentsPage(
          payments: transactionPayments,
          sales: sales,
          purchases: stockAdditions,
          products: products,
          clients: clients,
          suppliers: suppliers,
          competitors: competitors,
          depotName: (id) => depot(id)?.name ?? 'Stock général',
          onOpenAttachments: widget.user.isAdmin ? _openTransactionPhotos : null,
        ),
      ),
    );
  }

  void _openTransactionPhotos(
    BuildContext context,
    bool sale,
    String? id,
    List<Uint8List> images,
  ) {
    if (!widget.user.isAdmin) return;
    final sync = widget.database.cloudSync;
    final photos = images.isEmpty && id != null && sync is SupabaseCloudSyncClient
        ? sync.loadTransactionPhotos(sale: sale, id: id)
        : Future.value(images);
    _showTransactionPhotos(context, photos);
  }

  Future<void> openExcelExport() async {
    if (!widget.user.isAdmin && !widget.user.canExport) {
      return forbidden('Vous n’avez pas le droit d’exporter les données.');
    }
    await showDialog<void>(
      context: context,
      builder: (_) => ExcelExportDialog(
        products: products,
        categories: categories,
        catalogFamilies: catalogFamilies,
        depots: depots,
        stockAdditions: stockAdditions,
        sales: sales,
        operations: operations,
        transfers: stockTransfers,
        returns: saleReturns,
        machines: machines,
        suppliers: suppliers,
        clients: clients,
        productName: (id) => product(id)?.displayReference ?? id,
        depotName: (id) => depot(id)?.name ?? id,
        clientName: (id) => client(id)?.name ?? id,
        supplierName: (id) => supplier(id)?.name ?? id,
      ),
    );
  }

  Future<void> openDeviceRequests() async {
    if (!widget.user.isAdmin) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            DeviceRequestsPage(userName: (id) => appUser(id)?.fullName ?? id),
      ),
    );
  }

  Future<void> addDepot() async {
    if (!widget.user.canWritePage(AppPage.stock)) {
      return forbidden('Vous n’avez pas le droit de modifier les dépôts.');
    }
    final item = await Navigator.push<Depot>(
      context,
      MaterialPageRoute(
        builder: (_) => DepotForm(allowGallery: widget.user.isAdmin),
      ),
    );
    if (item != null) {
      await widget.database.insertDepot(item);
      if (mounted) setState(() => depots.add(item));
    }
  }

  Future<void> createStockTransfer() async {
    if (!widget.user.isAdmin) {
      return forbidden('Seul l’administrateur peut demander un transfert.');
    }
    final transfer = await Navigator.push<StockTransfer>(
      context,
      MaterialPageRoute(
        builder: (_) => StockTransferForm(
          products: products,
          categories: categories,
          catalogFamilies: catalogFamilies,
          depots: depots,
          available: depotStock,
        ),
      ),
    );
    if (transfer == null) return;
    await widget.database.insertStockTransfer(transfer);
    if (mounted) {
      setState(() => stockTransfers = [transfer, ...stockTransfers]);
      message(
        context,
        'Transfert enregistré en brouillon : validation requise.',
      );
    }
  }

  Future<void> addMachine() async {
    if (!widget.user.canWritePage(AppPage.machines)) {
      return forbidden('Seul l’administrateur peut ajouter une machine.');
    }
    final item = await Navigator.push<FactoryMachine>(
      context,
      MaterialPageRoute(
        builder: (_) => MachineForm(
          categories: categories,
          products: products,
          users: widget.users,
          onUserAdded: widget.onUserAdded,
          canManageUsers: widget.user.isAdmin,
          canCreateTemporary: widget.user.isAdmin,
          // A machine record needs a live, current photo of every unit.
          allowGallery: false,
          depots: depots,
          available: depotStock,
        ),
      ),
    );
    if (item != null) {
      final same = machines.where(
        (machine) =>
            machine.name.trim().toLowerCase() ==
                item.name.trim().toLowerCase() &&
            machine.categoryId == item.categoryId,
      );
      if (same.isNotEmpty && !item.temporary) {
        final existing = same.first;
        final startNumber = existing.units.length;
        final merged = FactoryMachine(
          id: existing.id,
          name: existing.name,
          type: existing.type,
          categoryId: existing.categoryId,
          outputId: existing.outputId,
          units: [
            ...existing.units,
            ...List.generate(
              item.copies,
              (index) => MachineUnit(
                number: startNumber + index + 1,
                image: item.units[index].image,
              ),
            ),
          ],
          operatorIds: existing.operatorIds,
          image: existing.image,
        );
        await widget.database.updateMachine(merged);
        if (mounted) {
          setState(() => machines[machines.indexOf(existing)] = merged);
        }
        if (mounted) {
          message(context, 'Exemplaires ajoutés à ${existing.name}.');
        }
      } else {
        await widget.database.insertMachine(item);
        if (mounted) setState(() => machines.add(item));
        if (item.temporary) {
          final outputQuantity = item.plannedPieces ?? 0;
          final inputQuantity = item.temporaryInputPieces ?? 0;
          final operation = Operation(
            id: '${item.id}-external',
            machineId: item.id,
            operatorId: '',
            productId: item.temporaryInputProductId!,
            sourceDepotId: item.temporarySourceDepotId!,
            machineUnitNumber: 1,
            pieces: inputQuantity,
            hopperPieces: item.hopperPieces,
            startedAt: DateTime.now(),
            finishedAt: DateTime.now(),
            outputPieces: outputQuantity,
            outputDepotId: 'general-depot',
            completionDraft: true,
            outputProductId: item.outputId,
            externalProduction: true,
          );
          await widget.database.insertOperation(operation);
          if (mounted) setState(() => operations.add(operation));
          await AppNotifications.show(
            title: 'Travail externe à valider',
            body: '${item.name} attend la validation administrative.',
          );
        }
      }
    }
  }

  Future<void> addCategory(String familyId) async {
    if (!widget.user.canWritePage(AppPage.products)) {
      return forbidden('Vous n’avez pas le droit de modifier les produits.');
    }
    final item = await Navigator.push<ProductCategory>(
      context,
      MaterialPageRoute(builder: (_) => const CategoryForm()),
    );
    if (item != null) {
      await widget.database.insertCategoryInFamily(item, familyId);
      if (mounted) await loadWorkshop();
    }
  }

  Future<void> editCategory(ProductCategory value) async {
    if (!widget.user.canWritePage(AppPage.products)) {
      return forbidden('Vous n’avez pas le droit de modifier les produits.');
    }
    final item = await Navigator.push<ProductCategory>(
      context,
      MaterialPageRoute(builder: (_) => CategoryForm(initial: value)),
    );
    if (item != null) {
      await widget.database.updateCategory(item);
      if (mounted) {
        final index = categories.indexWhere(
          (category) => category.id == item.id,
        );
        if (index >= 0) setState(() => categories[index] = item);
      }
    }
  }

  Future<void> saveCatalogFamily(CatalogFamily family) async {
    if (!widget.user.canWritePage(AppPage.products)) {
      return forbidden('Vous n’avez pas le droit de modifier les produits.');
    }
    try {
      await widget.database.saveCatalogFamily(family);
      if (mounted) await loadWorkshop();
    } on StateError catch (error) {
      if (mounted) message(context, error.message.toString());
    }
  }

  Future<void> manageMachine(FactoryMachine value) async {
    if (!widget.user.canWritePage(AppPage.machines)) {
      return forbidden('Vous n’avez pas le droit de gérer les machines.');
    }
    final updated = await Navigator.push<FactoryMachine>(
      context,
      MaterialPageRoute(builder: (_) => MachineUnitsPage(machine: value)),
    );
    if (updated != null) {
      await widget.database.updateMachine(updated);
      if (mounted) setState(() => machines[machines.indexOf(value)] = updated);
    }
  }

  void forbidden(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  Future<void> start(FactoryMachine item, MachineUnit unit) async {
    if (!widget.user.isOperator ||
        !widget.user.canWritePage(AppPage.machines) ||
        !item.operatorIds.contains(widget.user.id)) {
      return forbidden('Cette machine est réservée à son opérateur assigné.');
    }
    final operation = await Navigator.push<Operation>(
      context,
      MaterialPageRoute(
        builder: (_) => StartOperation(
          machine: item,
          available: depotStock,
          user: widget.user,
          category: category(item.categoryId),
          products: products,
          depots: depots,
          unitNumber: unit.number,
        ),
      ),
    );
    if (operation != null) {
      await widget.database.insertOperation(operation);
      if (mounted) setState(() => operations.add(operation));
      await AppNotifications.show(
        title: 'Opération démarrée',
        body:
            '${widget.user.fullName} a démarré une opération sur ${item.name}.',
      );
    }
  }

  Future<void> finish(Operation operation) async {
    if (!widget.user.isOperator ||
        !widget.user.canWritePage(AppPage.machines) ||
        operation.operatorId != widget.user.id) {
      return forbidden(
        'Seul l’opérateur ayant démarré cette opération peut la terminer.',
      );
    }
    final item = machine(operation.machineId)!;
    final template = product(item.outputId)!;
    final source = product(operation.productId)!;
    final completion = await Navigator.push<Completion>(
      context,
      MaterialPageRoute(
        builder: (_) => FinishOperation(
          operation: operation,
          machine: item,
          output: template,
          depots: depots,
        ),
      ),
    );
    if (completion == null) return;
    final output = _producedVariant(template, source);
    if (!products.any((product) => product.id == output.id)) {
      await widget.database.insertProduct(output);
      if (mounted) setState(() => products.add(output));
    }
    Product? scrapProduct;
    if (completion.scrapPieces > 0) {
      final wasteProduct = _scrapVariant(source);
      scrapProduct = wasteProduct;
      if (!products.any((product) => product.id == wasteProduct.id)) {
        await widget.database.insertProduct(wasteProduct);
        if (mounted) setState(() => products.add(wasteProduct));
      }
    }
    setState(() {
      operation.outputPieces = completion.outputPieces;
      operation.scrapPieces = completion.scrapPieces;
      operation.finalImage = completion.image;
      operation.remainderImage = completion.remainderImage;
      operation.scrapImage = completion.scrapImage;
      operation.needsReview = false;
      operation.completionDraft = true;
      operation.outputDepotId = completion.outputDepotId;
      operation.remainderDepotId = completion.remainderDepotId;
      operation.remainderPieces = completion.remainderPieces;
      operation.scrapDepotId = completion.scrapDepotId;
      operation.scrapProductId = scrapProduct?.id;
      operation.finishedAt = completion.finishedAt;
      operation.outputProductId = output.id;
    });
    await widget.database.updateOperation(operation);
    await AppNotifications.show(
      title: 'Fin de production en brouillon',
      body: 'L’opération sur ${item.name} attend la validation finale.',
    );
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => Receipt(
        operation: operation,
        machine: item,
        output: output,
        operator: widget.user,
      ),
    );
  }

  Future<void> approveReview(Operation operation, String depotId) async {
    if (!widget.user.isAdmin) {
      return forbidden('Seul l’administrateur peut valider ce contrôle.');
    }
    operation.remainderDepotId = depotId;
    operation.needsReview = false;
    await widget.database.updateOperation(operation);
    await AppNotifications.show(
      title: 'Contrôle validé',
      body:
          'Les pièces restantes ont été affectées au dépôt ${depot(depotId)?.name ?? 'sélectionné'}.',
    );
    if (!mounted) return;
    setState(() {});
    message(context, 'Le reste a été accepté et l’opération est terminée.');
  }

  Future<void> approveStockDraft(StockAddition draft) async {
    if (!widget.user.canValidate ||
        !widget.user.canWritePage(AppPage.validation)) {
      return forbidden('Vous n’avez pas le droit de valider.');
    }
    if (draft.returnOfPurchaseId != null) {
      final purchase = stockAdditions
          .where((item) => item.id == draft.returnOfPurchaseId)
          .firstOrNull;
      final otherReturns = stockAdditions
          .where(
            (item) =>
                item.returnOfPurchaseId == draft.returnOfPurchaseId &&
                item.id != draft.id,
          )
          .fold(0, (total, item) => total + item.pieces.abs());
      if (purchase == null ||
          draft.pieces >= 0 ||
          draft.pieces.abs() > purchase.pieces - otherReturns) {
        return forbidden(
          'Ce retour fournisseur dépasse la quantité de l’achat d’origine.',
        );
      }
      if (draft.pieces.abs() > depotStock(draft.productId, draft.depotId)) {
        return forbidden(
          'Le stock disponible est insuffisant pour valider ce retour fournisseur.',
        );
      }
    }
    final approved = StockAddition(
      id: draft.id,
      productId: draft.productId,
      depotId: draft.depotId,
      pieces: draft.pieces,
      receiptNumber: draft.receiptNumber,
      supplierId: draft.supplierId,
      returnOfPurchaseId: draft.returnOfPurchaseId,
      quantity: draft.quantity,
      unit: draft.unit,
      images: draft.images,
      addedAt: draft.addedAt,
      draft: false,
      transportCharge: draft.transportCharge,
    );
    await widget.database.updateStockAddition(approved);
    if (!mounted) return;
    setState(() {
      stockAdditions[stockAdditions.indexWhere((item) => item.id == draft.id)] =
          approved;
      received[approved.productId] =
          (received[approved.productId] ?? 0) + approved.pieces;
    });
    message(
      context,
      approved.returnOfPurchaseId == null
          ? 'Achat validé et ajouté au stock.'
          : 'Retour fournisseur validé et déduit du stock.',
    );
  }

  Future<void> updateStockDraft(StockAddition draft) async {
    if (!widget.user.canValidate ||
        !widget.user.canWritePage(AppPage.validation)) {
      return forbidden('Vous n’avez pas le droit de modifier ce brouillon.');
    }
    if (draft.returnOfPurchaseId != null) {
      final purchase = stockAdditions
          .where((item) => item.id == draft.returnOfPurchaseId)
          .firstOrNull;
      final otherReturns = stockAdditions
          .where(
            (item) =>
                item.returnOfPurchaseId == draft.returnOfPurchaseId &&
                item.id != draft.id,
          )
          .fold(0, (total, item) => total + item.pieces.abs());
      if (purchase == null ||
          draft.pieces >= 0 ||
          draft.pieces.abs() > purchase.pieces - otherReturns) {
        return forbidden(
          'Ce retour fournisseur dépasse la quantité de l’achat d’origine.',
        );
      }
    }
    await widget.database.updateStockAddition(draft);
    if (!mounted) return;
    setState(
      () =>
          stockAdditions[stockAdditions.indexWhere(
                (item) => item.id == draft.id,
              )] =
              draft,
    );
  }

  Future<void> cancelStockDraft(StockAddition draft) async {
    if (!widget.user.canValidate ||
        !widget.user.canWritePage(AppPage.validation)) {
      return forbidden('Vous n’avez pas le droit d’annuler ce brouillon.');
    }
    if (draft.id == null) return;
    await widget.database.deleteStockAddition(draft.id!);
    if (mounted) {
      setState(() => stockAdditions.removeWhere((item) => item.id == draft.id));
    }
  }

  Future<void> approveSaleDraft(Sale draft) async {
    if (!widget.user.canValidate ||
        !widget.user.canWritePage(AppPage.validation)) {
      return forbidden('Vous n’avez pas le droit de valider.');
    }
    if (draft.pieces > depotStock(draft.productId, draft.depotId)) {
      return forbidden(
        'Le stock disponible est insuffisant pour valider cette vente.',
      );
    }
    final approved = Sale(
      id: draft.id,
      productId: draft.productId,
      depotId: draft.depotId,
      clientId: draft.clientId,
      pieces: draft.pieces,
      quantity: draft.quantity,
      unit: draft.unit,
      images: draft.images,
      createdAt: draft.createdAt,
      draft: false,
      transportCharge: draft.transportCharge,
    );
    await widget.database.updateSale(approved);
    if (!mounted) return;
    setState(
      () => sales[sales.indexWhere((item) => item.id == draft.id)] = approved,
    );
    message(context, 'Vente validée et déduite du stock.');
  }

  Future<void> approveStockTransfer(StockTransfer draft) async {
    if (!widget.user.canValidate ||
        !widget.user.canWritePage(AppPage.validation)) {
      return forbidden('Vous n’avez pas le droit de valider.');
    }
    if (draft.pieces <= 0 ||
        draft.sourceDepotId == draft.destinationDepotId ||
        draft.pieces > depotStock(draft.productId, draft.sourceDepotId)) {
      return forbidden(
        'Le stock disponible dans le dépôt de départ est insuffisant.',
      );
    }
    final approved = StockTransfer(
      id: draft.id,
      productId: draft.productId,
      sourceDepotId: draft.sourceDepotId,
      destinationDepotId: draft.destinationDepotId,
      pieces: draft.pieces,
      createdAt: draft.createdAt,
      draft: false,
    );
    await widget.database.updateStockTransfer(approved);
    if (mounted) {
      setState(
        () =>
            stockTransfers[stockTransfers.indexWhere(
                  (item) => item.id == draft.id,
                )] =
                approved,
      );
      message(context, 'Transfert validé : le stock a été déplacé.');
    }
  }

  Future<void> updateSaleDraft(Sale draft) async {
    if (!widget.user.canValidate ||
        !widget.user.canWritePage(AppPage.validation)) {
      return forbidden('Vous n’avez pas le droit de modifier ce brouillon.');
    }
    await widget.database.updateSale(draft);
    if (!mounted) return;
    setState(
      () => sales[sales.indexWhere((item) => item.id == draft.id)] = draft,
    );
  }

  Future<void> updateStockTransferDraft(StockTransfer draft) async {
    if (!widget.user.canValidate ||
        !widget.user.canWritePage(AppPage.validation)) {
      return forbidden('Vous n’avez pas le droit de modifier ce transfert.');
    }
    if (draft.pieces <= 0 || draft.sourceDepotId == draft.destinationDepotId) {
      return forbidden(
        'Le transfert doit avoir une quantité valide et deux dépôts différents.',
      );
    }
    await widget.database.updateStockTransfer(draft);
    if (!mounted) return;
    setState(() {
      stockTransfers[stockTransfers.indexWhere((item) => item.id == draft.id)] =
          draft;
    });
  }

  Future<void> cancelSaleDraft(Sale draft) async {
    if (!widget.user.canValidate ||
        !widget.user.canWritePage(AppPage.validation)) {
      return forbidden('Vous n’avez pas le droit d’annuler ce brouillon.');
    }
    await widget.database.deleteSaleAndReturns(draft.id);
    if (mounted) {
      setState(() {
        sales.removeWhere((item) => item.id == draft.id);
        saleReturns.removeWhere((item) => item.saleId == draft.id);
      });
    }
  }

  Future<void> approveSaleReturn(SaleReturn draft) async {
    if (!widget.user.canValidate ||
        !widget.user.canWritePage(AppPage.validation)) {
      return forbidden('Vous n’avez pas le droit de valider.');
    }
    final sale = sales.where((item) => item.id == draft.saleId).firstOrNull;
    if (sale == null || sale.draft) {
      return forbidden('La vente associée à ce retour n’est pas valide.');
    }
    final otherReturns = saleReturns
        .where(
          (item) =>
              item.saleId == draft.saleId &&
              item.id != draft.id &&
              item.status != ReturnValidationStatus.rejected,
        )
        .fold(0, (total, item) => total + item.pieces);
    if (draft.pieces <= 0 || otherReturns + draft.pieces > sale.pieces) {
      return forbidden('La quantité retournée dépasse la quantité vendue.');
    }
    final approved = SaleReturn(
      id: draft.id,
      saleId: draft.saleId,
      productId: draft.productId,
      depotId: draft.depotId,
      pieces: draft.pieces,
      createdAt: draft.createdAt,
      status: ReturnValidationStatus.approved,
    );
    await widget.database.updateSaleReturn(approved);
    if (!mounted) return;
    setState(
      () => saleReturns[saleReturns.indexWhere((item) => item.id == draft.id)] =
          approved,
    );
    message(context, 'Retour validé et ajouté au stock.');
  }

  Future<void> updateSaleReturn(SaleReturn draft) async {
    if (!widget.user.canValidate ||
        !widget.user.canWritePage(AppPage.validation)) {
      return forbidden('Vous n’avez pas le droit de modifier ce retour.');
    }
    final sale = sales.where((item) => item.id == draft.saleId).firstOrNull;
    final otherReturns = saleReturns
        .where(
          (item) =>
              item.saleId == draft.saleId &&
              item.id != draft.id &&
              item.status != ReturnValidationStatus.rejected,
        )
        .fold(0, (total, item) => total + item.pieces);
    if (sale == null ||
        draft.pieces <= 0 ||
        otherReturns + draft.pieces > sale.pieces) {
      return forbidden('La quantité retournée dépasse la quantité vendue.');
    }
    await widget.database.updateSaleReturn(draft);
    if (!mounted) return;
    setState(
      () => saleReturns[saleReturns.indexWhere((item) => item.id == draft.id)] =
          draft,
    );
  }

  Future<void> rejectSaleReturn(SaleReturn draft) async {
    if (!widget.user.canValidate ||
        !widget.user.canWritePage(AppPage.validation)) {
      return forbidden('Vous n’avez pas le droit de refuser ce retour.');
    }
    final rejected = SaleReturn(
      id: draft.id,
      saleId: draft.saleId,
      productId: draft.productId,
      depotId: draft.depotId,
      pieces: draft.pieces,
      createdAt: draft.createdAt,
      status: ReturnValidationStatus.rejected,
    );
    await widget.database.updateSaleReturn(rejected);
    if (!mounted) return;
    setState(
      () => saleReturns[saleReturns.indexWhere((item) => item.id == draft.id)] =
          rejected,
    );
    message(context, 'Retour refusé : le stock reste inchangé.');
  }

  Future<void> cancelSaleReturn(SaleReturn draft) async {
    if (!widget.user.canValidate ||
        !widget.user.canWritePage(AppPage.validation)) {
      return forbidden('Vous n’avez pas le droit d’annuler ce retour.');
    }
    await widget.database.deleteSaleReturn(draft.id);
    if (mounted) {
      setState(() => saleReturns.removeWhere((item) => item.id == draft.id));
    }
  }

  Future<void> approveOperationDraft(Operation draft) async {
    if (!widget.user.canValidate ||
        !widget.user.canWritePage(AppPage.validation)) {
      return forbidden('Vous n’avez pas le droit de valider.');
    }
    draft.completionDraft = false;
    draft.validatedAt = DateTime.now();
    await widget.database.updateOperation(draft);
    if (draft.externalProduction) {
      // A temporary external machine represents one shipment only. The
      // operation remains in the history, while its temporary card vanishes.
      await widget.database.deleteMachine(draft.machineId);
    }
    if (!mounted) return;
    setState(() {
      if (draft.externalProduction) {
        machines.removeWhere((machine) => machine.id == draft.machineId);
      }
    });
    message(
      context,
      draft.externalProduction
          ? 'Travail externe validé : le stock a été mis à jour et la machine temporaire supprimée.'
          : 'Production validée et ajoutée au stock.',
    );
  }

  Future<void> updateOperationDraft(Operation draft) async {
    if (!widget.user.canValidate ||
        !widget.user.canWritePage(AppPage.validation)) {
      return forbidden('Vous n’avez pas le droit de modifier ce brouillon.');
    }
    await widget.database.updateOperation(draft);
    if (mounted) setState(() {});
  }

  Future<void> cancelOperationDraft(Operation draft) async {
    if (!widget.user.canValidate ||
        !widget.user.canWritePage(AppPage.validation)) {
      return forbidden('Vous n’avez pas le droit d’annuler cette production.');
    }
    await widget.database.deleteOperation(draft.id);
    if (draft.externalProduction) {
      await widget.database.deleteMachine(draft.machineId);
    }
    if (mounted) {
      setState(() {
        operations.removeWhere((item) => item.id == draft.id);
        if (draft.externalProduction) {
          machines.removeWhere((item) => item.id == draft.machineId);
        }
      });
    }
  }

  Future<void> cancelStockTransfer(StockTransfer draft) async {
    if (!widget.user.canValidate ||
        !widget.user.canWritePage(AppPage.validation)) {
      return forbidden('Vous n’avez pas le droit d’annuler ce transfert.');
    }
    await widget.database.deleteStockTransfer(draft.id);
    if (mounted) {
      setState(() => stockTransfers.removeWhere((item) => item.id == draft.id));
    }
  }

  Future<void> addOperatorPayment(String operatorId, double amount) async {
    final payment = OperatorPayment(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      operatorId: operatorId,
      amount: amount,
      paidAt: DateTime.now(),
    );
    await widget.database.insertOperatorPayment(payment);
    if (mounted) setState(() => payments = [payment, ...payments]);
  }

  Future<void> changeMeterRate(double rate) async {
    if (rate <= 0) return;
    await widget.database.setMeterRate(rate);
    if (mounted) setState(() => meterRate = rate);
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (loadError != null) {
      return _StartupFailure(
        message: loadError!,
        onRetry: () {
          setState(() {
            loading = true;
            loadError = null;
          });
          _synchronizeWorkshop();
        },
        onRestoreLocalCache: () async {
          setState(() {
            loading = true;
            loadError = null;
          });
          try {
            await widget.database.resetApplication();
            final restored = await widget.database
                .restoreLocalMirrorFromCloud();
            if (!restored) {
              throw StateError('Aucune copie distante disponible.');
            }
            await loadWorkshop();
          } catch (_) {
            if (mounted) {
              setState(() {
                loadError =
                    'Impossible de restaurer les données depuis le serveur.';
                loading = false;
              });
            }
          }
        },
      );
    }
    final visibleOperations = widget.user.isAdmin
        ? operations
        : operations
              .where((operation) => operation.operatorId == widget.user.id)
              .toList();
    if (widget.user.isOperator &&
        widget.user.allowedPages.length == 1 &&
        widget.user.allowedPages.contains(AppPage.machines)) {
      return Scaffold(
        body: Aura(
          child: SafeArea(
            child: Column(
              children: [
                AppHeader(
                  title: 'Machines',
                  user: widget.user,
                  onLogout: widget.onLogout,
                  onOpenTeam: () {},
                  onOpenBackups: () {},
                  onOpenAnalytics: () => _openAnalytics(context),
                  onOpenActivity: () => _openReviews(context),
                  canAccessAnalytics: widget.user.canAccess(AppPage.analytics),
                  canExport: widget.user.isAdmin || widget.user.canExport,
                  onOpenExport: openExcelExport,
                ),
                Expanded(
                  child: MachinesPage(
                    machines: machines,
                    operations: visibleOperations,
                    user: widget.user,
                    userName: (id) => appUser(id)?.fullName ?? '—',
                    categoryName: (id) =>
                        category(id)?.name ?? 'Sans catégorie',
                    productName: (id) =>
                        product(id)?.displayReference ?? 'Produit introuvable',
                    hasActive: hasMyActiveOperation,
                    onAdd: addMachine,
                    onStart: start,
                    onFinish: finish,
                    onManage: manageMachine,
                    pendingReviews: 0,
                    onOpenReviews: () {},
                    showReviews: false,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (widget.user.canValidate &&
        widget.user.allowedPages.length == 1 &&
        widget.user.allowedPages.contains(AppPage.validation)) {
      return Scaffold(
        body: Aura(
          child: SafeArea(
            child: Column(
              children: [
                AppHeader(
                  title: 'Validations',
                  user: widget.user,
                  onLogout: widget.onLogout,
                  onOpenTeam: () {},
                  onOpenBackups: () {},
                  onOpenAnalytics: () => _openAnalytics(context),
                  canAccessAnalytics: widget.user.canAccess(AppPage.analytics),
                  canExport: widget.user.isAdmin || widget.user.canExport,
                  onOpenExport: openExcelExport,
                ),
                Expanded(
                  child: ValidationPage(
                    products: products,
                    depots: depots,
                    stockDrafts: stockAdditions
                        .where((item) => item.draft)
                        .toList(),
                    saleDrafts: sales.where((item) => item.draft).toList(),
                    returnDrafts: saleReturns
                        .where(
                          (item) =>
                              item.status == ReturnValidationStatus.pending,
                        )
                        .toList(),
                    operationDrafts: operations
                        .where((item) => !item.active && item.completionDraft)
                        .toList(),
                    transferDrafts: stockTransfers
                        .where((item) => item.draft)
                        .toList(),
                    onApproveStock: approveStockDraft,
                    onEditStock: updateStockDraft,
                    onCancelStock: cancelStockDraft,
                    onApproveSale: approveSaleDraft,
                    onEditSale: updateSaleDraft,
                    onCancelSale: cancelSaleDraft,
                    onApproveReturn: approveSaleReturn,
                    onEditReturn: updateSaleReturn,
                    onRejectReturn: rejectSaleReturn,
                    onCancelReturn: cancelSaleReturn,
                    onApproveOperation: approveOperationDraft,
                    onEditOperation: updateOperationDraft,
                    onCancelOperation: cancelOperationDraft,
                    onApproveTransfer: approveStockTransfer,
                    onEditTransfer: updateStockTransferDraft,
                    onCancelTransfer: cancelStockTransfer,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final pages = [
      DashboardPage(
        user: widget.user,
        productCount: products.length,
        machineCount: machines.length,
        pendingReviews: operations.where((op) => op.needsReview).length,
        onProducts: () => setState(() => section = 1),
        onStock: () => setState(() => section = 2),
        onMachines: () => setState(() => section = 3),
        onTeam: () => setState(() => section = 4),
        onValidation: () => setState(() => section = 5),
        onCategories: () => _openCategories(context),
        onReviews: () => _openReviews(context),
      ),
      ProductsPage(
        products: products,
        categories: categories,
        catalogFamilies: catalogFamilies,
        stock: stock,
        depots: depots,
        depotStock: depotStock,
        canEdit: widget.user.canWritePage(AppPage.products),
        onAdd: addProduct,
        onAddStock: addStockFor,
        onOpenCategories: () => _openCategories(context),
      ),
      StockPage(
        products: products,
        categories: categories,
        catalogFamilies: catalogFamilies,
        stock: stock,
        draftCount:
            stockAdditions.where((item) => item.draft).length +
            sales.where((item) => item.draft).length +
            saleReturns
                .where((item) => item.status == ReturnValidationStatus.pending)
                .length +
            stockTransfers.where((item) => item.draft).length,
        canEdit: widget.user.canWritePage(AppPage.stock),
        onPurchase: addStock,
        onSale: addSale,
        onOpenDepots: () => _openDepots(context),
        onOpenRecords: openStockRecords,
        onOpenPayments: openTransactionPayments,
      ),
      MachinesPage(
        machines: machines,
        operations: visibleOperations,
        user: widget.user,
        userName: (id) => appUser(id)?.fullName ?? '—',
        categoryName: (id) => category(id)?.name ?? 'Sans catégorie',
        productName: (id) =>
            product(id)?.displayReference ?? 'Produit introuvable',
        hasActive: hasMyActiveOperation,
        onAdd: addMachine,
        onStart: start,
        onFinish: finish,
        onManage: manageMachine,
        pendingReviews: operations.where((op) => op.needsReview).length,
        onOpenReviews: () => _openReviews(context),
      ),
      UsersPage(
        users: widget.user.isAdmin ? widget.users : [widget.user],
        admin: widget.user.isAdmin,
        onAdd: widget.onUserAdded,
        onUpdate: widget.onUserUpdated,
        onLoadSessions: widget.database.loadUserSessions,
        onOpenPayroll: () => _openPayroll(context),
        onOpenDeviceRequests: openDeviceRequests,
      ),
      ValidationPage(
        products: products,
        depots: depots,
        stockDrafts: stockAdditions.where((item) => item.draft).toList(),
        saleDrafts: sales.where((item) => item.draft).toList(),
        returnDrafts: saleReturns
            .where((item) => item.status == ReturnValidationStatus.pending)
            .toList(),
        operationDrafts: operations
            .where((item) => !item.active && item.completionDraft)
            .toList(),
        transferDrafts: stockTransfers.where((item) => item.draft).toList(),
        onApproveStock: approveStockDraft,
        onEditStock: updateStockDraft,
        onCancelStock: cancelStockDraft,
        onApproveSale: approveSaleDraft,
        onEditSale: updateSaleDraft,
        onCancelSale: cancelSaleDraft,
        onApproveReturn: approveSaleReturn,
        onEditReturn: updateSaleReturn,
        onRejectReturn: rejectSaleReturn,
        onCancelReturn: cancelSaleReturn,
        onApproveOperation: approveOperationDraft,
        onEditOperation: updateOperationDraft,
        onCancelOperation: cancelOperationDraft,
        onApproveTransfer: approveStockTransfer,
        onEditTransfer: updateStockTransferDraft,
        onCancelTransfer: cancelStockTransfer,
      ),
    ];
    final pageKeys = [
      AppPage.dashboard,
      AppPage.products,
      AppPage.stock,
      AppPage.machines,
      AppPage.team,
      AppPage.validation,
    ];
    final titles = [
      'Accueil',
      'Produits',
      'Stock',
      'Machines',
      'Équipe',
      'Validations',
    ];
    final currentPage = widget.user.canAccess(pageKeys[section])
        ? pages[section]
        : _PageAccessDenied(page: pageKeys[section]);
    final isWindows = _usesWorkspaceRail(context);
    return Scaffold(
      extendBody: !isWindows,
      body: Aura(
        child: SafeArea(
          child: isWindows
              ? WindowsWorkspaceShell(
                  title: titles[section],
                  user: widget.user,
                  section: section,
                  onSectionChanged: (value) => setState(() => section = value),
                  onLogout: widget.onLogout,
                  onOpenTeam: () => setState(() => section = 4),
                  onOpenBackups: () => _openBackups(context),
                  onOpenAnalytics: () => _openAnalytics(context),
                  canAccessAnalytics: widget.user.canAccess(AppPage.analytics),
                  canExport: widget.user.isAdmin || widget.user.canExport,
                  onOpenExport: openExcelExport,
                  onOpenDeveloper: () => _openDeveloper(context),
                  child: currentPage,
                )
              : Column(
                  children: [
                    AppHeader(
                      title: titles[section],
                      user: widget.user,
                      onLogout: widget.onLogout,
                      onOpenTeam: () => setState(() => section = 4),
                      onOpenBackups: () => _openBackups(context),
                      onOpenAnalytics: () => _openAnalytics(context),
                      onOpenActivity: () => _openReviews(context),
                      canAccessAnalytics: widget.user.canAccess(
                        AppPage.analytics,
                      ),
                      canExport: widget.user.isAdmin || widget.user.canExport,
                      onOpenExport: openExcelExport,
                      onOpenDeveloper: () => _openDeveloper(context),
                    ),
                    Expanded(child: currentPage),
                  ],
                ),
        ),
      ),
      bottomNavigationBar: isWindows
          ? null
          : MobileGlassNavigation(
              index: section,
              onTap: (value) => setState(() => section = value),
              showTeam: widget.user.isAdmin,
            ),
    );
  }

  Future<void> _openCategories(BuildContext context) => Navigator.push<void>(
    context,
    MaterialPageRoute(
      builder: (_) => ManagementScreen(
        title: 'Familles',
        child: CatalogFamiliesPage(
          loadCategories: () => categories,
          loadFamilies: () => catalogFamilies,
          admin: widget.user.canWritePage(AppPage.products),
          onSaveFamily: saveCatalogFamily,
          onAddCategory: addCategory,
          onEditCategory: editCategory,
        ),
      ),
    ),
  );

  Future<void> _openDepots(BuildContext context) => Navigator.push<void>(
    context,
    MaterialPageRoute(
      builder: (_) => ManagementScreen(
        title: 'Dépôts',
        child: DepotsPage(
          depots: depots,
          products: products,
          categories: categories,
          catalogFamilies: catalogFamilies,
          stock: depotStock,
          canEdit: widget.user.canWritePage(AppPage.stock),
          canTransfer: widget.user.isAdmin,
          onAdd: addDepot,
          onTransfer: createStockTransfer,
        ),
      ),
    ),
  );

  Future<void> _openReviews(BuildContext context) => Navigator.push<void>(
    context,
    MaterialPageRoute(
      builder: (_) => ManagementScreen(
        title: 'Contrôles',
        child: ReviewsPage(
          operations: operations.where((op) => op.needsReview).toList(),
          product: product,
          userName: (id) => appUser(id)?.fullName ?? '—',
          depots: depots,
          admin: widget.user.isAdmin,
          onApprove: approveReview,
        ),
      ),
    ),
  );

  Future<void> _openBackups(BuildContext context) => Navigator.push<void>(
    context,
    MaterialPageRoute(
      builder: (_) => BackupPage(
        lastBackupAt: widget.database.lastBackupAt,
        onDownload: () => _downloadBackup(),
        onRestore: _restoreBackup,
        onClearData: _clearWorkshopData,
      ),
    ),
  );

  Future<void> _openAnalytics(BuildContext context) {
    if (!widget.user.canAccess(AppPage.analytics)) {
      forbidden('Vous n’avez pas le droit d’accéder aux analyses.');
      return Future<void>.value();
    }
    return Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => AnalyticsPage(
          products: products,
          operations: operations,
          sales: sales,
          purchases: stockAdditions,
          stock: stock,
        ),
      ),
    );
  }

  Future<void> _openDeveloper(BuildContext context) {
    if (!widget.user.isDeveloper) return Future<void>.value();
    return Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => DeveloperModePage(
          products: products,
          categories: categories,
          depots: depots,
          purchases: stockAdditions,
          sales: sales,
          machines: machines,
          operations: operations,
          transfers: stockTransfers,
          returns: saleReturns,
          database: widget.database,
          onChanged: loadWorkshop,
        ),
      ),
    );
  }

  Future<void> _openPayroll(BuildContext context) => Navigator.push<void>(
    context,
    MaterialPageRoute(
      builder: (_) => ManagementScreen(
        title: 'Paiements des opérateurs',
        child: PayrollPage(
          users: widget.users,
          products: products,
          operations: operations,
          payments: payments,
          meterRate: meterRate,
          onPay: addOperatorPayment,
          onRateChanged: changeMeterRate,
        ),
      ),
    ),
  );
}

class Aura extends StatelessWidget {
  const Aura({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      const RepaintBoundary(child: _LiquidWallpaper()),
      child,
    ],
  );
}

class _PageAccessDenied extends StatelessWidget {
  const _PageAccessDenied({required this.page});
  final AppPage page;
  @override
  Widget build(BuildContext context) => Center(
    child: Glass(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.lock_outline_rounded,
            size: 42,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 12),
          Text(
            'Accès à « ${page.label} » non autorisé',
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            'Demandez au responsable de modifier vos droits.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _atelierMuted(context)),
          ),
        ],
      ),
    ),
  );
}

enum ExportDataset {
  products,
  purchases,
  sales,
  operations,
  transfers,
  returns,
  machines,
  suppliers,
  clients,
}

extension ExportDatasetLabel on ExportDataset {
  String get label => switch (this) {
    ExportDataset.products => 'Produits',
    ExportDataset.purchases => 'Achats',
    ExportDataset.sales => 'Ventes',
    ExportDataset.operations => 'Opérations',
    ExportDataset.transfers => 'Transferts',
    ExportDataset.returns => 'Retours clients',
    ExportDataset.machines => 'Machines',
    ExportDataset.suppliers => 'Fournisseurs',
    ExportDataset.clients => 'Clients',
  };
}

class ExcelExportDialog extends StatefulWidget {
  const ExcelExportDialog({
    super.key,
    required this.products,
    required this.categories,
    this.catalogFamilies = const [],
    required this.depots,
    required this.stockAdditions,
    required this.sales,
    required this.operations,
    required this.transfers,
    required this.returns,
    required this.machines,
    required this.suppliers,
    required this.clients,
    required this.productName,
    required this.depotName,
    required this.clientName,
    required this.supplierName,
    this.saveSheets = ExcelReports.save,
  });

  final List<Product> products;
  final List<ProductCategory> categories;
  final List<CatalogFamily> catalogFamilies;
  final List<Depot> depots;
  final List<StockAddition> stockAdditions;
  final List<Sale> sales;
  final List<Operation> operations;
  final List<StockTransfer> transfers;
  final List<SaleReturn> returns;
  final List<FactoryMachine> machines;
  final List<Supplier> suppliers;
  final List<Client> clients;
  final String Function(String id) productName;
  final String Function(String id) depotName;
  final String Function(String id) clientName;
  final String Function(String id) supplierName;
  final Future<void> Function(List<ExcelSheetData>) saveSheets;

  @override
  State<ExcelExportDialog> createState() => _ExcelExportDialogState();
}

class _ExcelExportDialogState extends State<ExcelExportDialog> {
  final selected = <ExportDataset>{};
  DateTimeRange? period;
  final selections = <ExportDataset, Set<String>>{};
  Set<String> productFamilyIds = const {};
  var saving = false;
  String? firstDepot;
  String? secondDepot;

  bool matches(ExportDataset dataset, String? id) {
    final ids = selections[dataset];
    return ids == null || ids.isEmpty || ids.contains(id);
  }

  Iterable<ProductCategory> categoriesFor(Product item) =>
      widget.categories.where(
        (category) => category.productIds.contains(_catalogMembershipId(item)),
      );

  List<_CatalogGroup> get productGroups => _catalogGroups(
    widget.categories,
    widget.catalogFamilies,
    products: widget.products,
  );

  Iterable<_CatalogSection> productSections(List<_CatalogGroup> groups) =>
      groups
          .where(
            (group) =>
                productFamilyIds.isEmpty || productFamilyIds.contains(group.id),
          )
          .expand((group) => group.sections);

  bool inRange(DateTime value) {
    final range = period;
    if (range == null) return true;
    final exclusiveEnd = DateTime(
      range.end.year,
      range.end.month,
      range.end.day + 1,
    );
    return !value.isBefore(range.start) && value.isBefore(exclusiveEnd);
  }

  Future<void> pickPeriod() async {
    final range = await showDateRangePicker(
      context: context,
      initialDateRange: period,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (range != null && mounted) setState(() => period = range);
  }

  Widget dateFilter() {
    final range = period;
    final localizations = MaterialLocalizations.of(context);
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: saving ? null : pickPeriod,
            icon: const Icon(Icons.date_range),
            label: Text(
              range == null
                  ? 'Toutes les dates'
                  : '${localizations.formatShortDate(range.start)} – ${localizations.formatShortDate(range.end)}',
            ),
          ),
        ),
        if (range != null)
          IconButton(
            tooltip: 'Effacer la période',
            icon: const Icon(Icons.clear),
            onPressed: saving ? null : () => setState(() => period = null),
          ),
      ],
    );
  }

  Widget datasetFilters(ExportDataset dataset) {
    final groups = dataset == ExportDataset.products
        ? productGroups
        : const <_CatalogGroup>[];
    final suppliers = _choices(
      widget.suppliers,
      (item) => item.id,
      (item) => _partnerLabel(item.name, item.company),
    );
    final clients = _choices(
      widget.clients,
      (item) => item.id,
      (item) => _partnerLabel(item.name, item.company),
    );
    final (label, options) = switch (dataset) {
      ExportDataset.products => (
        'Catégories',
        {
          for (final section in productSections(groups))
            section.category.id: section.category.name,
        },
      ),
      ExportDataset.machines => (
        'Catégories',
        _choices(widget.categories, (item) => item.id, (item) => item.name),
      ),
      ExportDataset.purchases => (
        'Fournisseurs',
        {
          ...suppliers,
          for (final id
              in widget.stockAdditions
                  .map((item) => item.supplierId)
                  .whereType<String>()
                  .toSet())
            if (id.isNotEmpty && !suppliers.containsKey(id))
              id: widget.supplierName(id),
        },
      ),
      ExportDataset.suppliers => ('Fournisseurs', suppliers),
      ExportDataset.sales => (
        'Clients',
        {
          ...clients,
          for (final id in widget.sales.map((item) => item.clientId).toSet())
            if (id.isNotEmpty && !clients.containsKey(id))
              id: widget.clientName(id),
        },
      ),
      ExportDataset.returns || ExportDataset.clients => ('Clients', clients),
      ExportDataset.operations => (
        'Machines',
        _choices(widget.machines, (item) => item.id, (item) => item.name),
      ),
      ExportDataset.transfers => ('', const <String, String>{}),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (groups.isNotEmpty) ...[
            SearchChoiceField(
              label: 'Familles',
              options: _choices(
                groups,
                (group) => group.id,
                (group) => group.name,
              ),
              selected: productFamilyIds,
              multiple: true,
              onChanged: (ids) => setState(() {
                productFamilyIds = ids;
                final available = productSections(groups)
                    .map((section) => section.category.id)
                    .toSet();
                selections[dataset] = (selections[dataset] ?? const <String>{})
                    .intersection(available);
              }),
            ),
            if (options.isNotEmpty) const SizedBox(height: 8),
          ],
          if (options.isNotEmpty)
            SearchChoiceField(
              label: label,
              options: options,
              selected: selections[dataset] ?? const {},
              multiple: true,
              onChanged: (ids) => setState(() => selections[dataset] = ids),
            )
          else if (dataset == ExportDataset.purchases ||
              dataset == ExportDataset.sales)
            InputDecorator(
              decoration: InputDecoration(labelText: label, enabled: false),
              child: Text(
                dataset == ExportDataset.purchases
                    ? 'Aucun fournisseur disponible'
                    : 'Aucun client disponible',
              ),
            ),
          if (dataset == ExportDataset.transfers)
            _TransferDepotFields(
              depots: widget.depots,
              first: firstDepot,
              second: secondDepot,
              onChanged: (first, second) => setState(() {
                firstDepot = first;
                secondDepot = second;
              }),
            ),
        ],
      ),
    );
  }

  Future<void> export() async {
    if (selected.isEmpty || saving) return;
    setState(() => saving = true);
    try {
      final sheets = <ExcelSheetData>[];
      final clientBySale = {
        for (final sale in widget.sales) sale.id: sale.clientId,
      };
      if (selected.contains(ExportDataset.products)) {
        final filterProducts =
            productFamilyIds.isNotEmpty ||
            selections[ExportDataset.products]?.isNotEmpty == true;
        final matchingIds = filterProducts
            ? productSections(productGroups)
                  .where(
                    (section) =>
                        matches(ExportDataset.products, section.category.id),
                  )
                  .expand((section) => section.productIds)
                  .toSet()
            : null;
        sheets.add(
          ExcelSheetData(
            name: 'Produits',
            headers: const [
              'Référence',
              'Produit',
              'Catégorie',
              'Type',
              'Matière',
              'Longueur (m)',
              'Épaisseur (mm)',
            ],
            rows: widget.products
                .where(
                  (item) =>
                      matchingIds == null ||
                      matchingIds.contains(_catalogMembershipId(item)),
                )
                .map(
                  (item) => [
                    item.reference,
                    item.name,
                    categoriesFor(item)
                        .map((category) => category.name)
                        .join(', '),
                    item.kind.label,
                    item.material.label,
                    item.lengthMeters,
                    item.thickness,
                  ],
                )
                .toList(),
          ),
        );
      }
      if (selected.contains(ExportDataset.purchases)) {
        sheets.add(
          ExcelSheetData(
            name: 'Achats',
            headers: const [
              'Date',
              'Produit',
              'Dépôt',
              'Quantité',
              'Unité',
              'Pièces',
              'Bon',
              'Fournisseur',
              'Statut',
            ],
            rows: widget.stockAdditions
                .where(
                  (item) =>
                      inRange(item.addedAt) &&
                      matches(ExportDataset.purchases, item.supplierId),
                )
                .map(
                  (item) => [
                    item.addedAt,
                    widget.productName(item.productId),
                    widget.depotName(item.depotId),
                    item.quantity,
                    item.unit.shortLabel,
                    item.pieces,
                    item.receiptNumber,
                    item.supplierId == null
                        ? ''
                        : widget.supplierName(item.supplierId!),
                    item.draft ? 'Brouillon' : 'Validé',
                  ],
                )
                .toList(),
          ),
        );
      }
      if (selected.contains(ExportDataset.sales)) {
        sheets.add(
          ExcelSheetData(
            name: 'Ventes',
            headers: const [
              'Date',
              'Produit',
              'Dépôt',
              'Client',
              'Quantité',
              'Unité',
              'Pièces',
              'Statut',
            ],
            rows: widget.sales
                .where(
                  (item) =>
                      inRange(item.createdAt) &&
                      matches(ExportDataset.sales, item.clientId),
                )
                .map(
                  (item) => [
                    item.createdAt,
                    widget.productName(item.productId),
                    widget.depotName(item.depotId),
                    widget.clientName(item.clientId),
                    item.quantity,
                    item.unit.shortLabel,
                    item.pieces,
                    item.draft ? 'Brouillon' : 'Validé',
                  ],
                )
                .toList(),
          ),
        );
      }
      if (selected.contains(ExportDataset.operations)) {
        sheets.add(
          ExcelSheetData(
            name: 'Opérations',
            headers: const [
              'Début',
              'Fin',
              'Machine',
              'Produit',
              'Entrée',
              'Sortie',
              'Rebut',
              'Statut',
            ],
            rows: widget.operations
                .where(
                  (item) =>
                      inRange(item.startedAt) &&
                      matches(ExportDataset.operations, item.machineId),
                )
                .map(
                  (item) => [
                    item.startedAt,
                    item.finishedAt,
                    item.machineId,
                    widget.productName(item.productId),
                    item.pieces,
                    item.outputPieces,
                    item.scrapPieces,
                    item.active
                        ? 'En cours'
                        : (item.completionDraft ? 'Brouillon' : 'Terminée'),
                  ],
                )
                .toList(),
          ),
        );
      }
      if (selected.contains(ExportDataset.transfers)) {
        sheets.add(
          ExcelSheetData(
            name: 'Transferts',
            headers: const [
              'Date',
              'Produit',
              'Dépôt départ',
              'Dépôt arrivée',
              'Pièces',
              'Statut',
            ],
            rows: widget.transfers
                .where(
                  (item) =>
                      inRange(item.createdAt) &&
                      transferMatchesDepots(item, firstDepot, secondDepot),
                )
                .map(
                  (item) => [
                    item.createdAt,
                    widget.productName(item.productId),
                    widget.depotName(item.sourceDepotId),
                    widget.depotName(item.destinationDepotId),
                    item.pieces,
                    item.draft ? 'Brouillon' : 'Validé',
                  ],
                )
                .toList(),
          ),
        );
      }
      if (selected.contains(ExportDataset.returns)) {
        sheets.add(
          ExcelSheetData(
            name: 'Retours',
            headers: const [
              'Date',
              'Vente',
              'Produit',
              'Dépôt',
              'Pièces',
              'Statut',
            ],
            rows: widget.returns
                .where(
                  (item) =>
                      inRange(item.createdAt) &&
                      matches(ExportDataset.returns, clientBySale[item.saleId]),
                )
                .map(
                  (item) => [
                    item.createdAt,
                    item.saleId,
                    widget.productName(item.productId),
                    widget.depotName(item.depotId),
                    item.pieces,
                    item.status.label,
                  ],
                )
                .toList(),
          ),
        );
      }
      if (selected.contains(ExportDataset.machines)) {
        sheets.add(
          ExcelSheetData(
            name: 'Machines',
            headers: const [
              'Machine',
              'Type',
              'Unités',
              'Produit de sortie',
              'Temporaire',
            ],
            rows: widget.machines
                .where(
                  (item) => matches(ExportDataset.machines, item.categoryId),
                )
                .map(
                  (item) => [
                    item.name,
                    item.type.name,
                    item.units.length,
                    widget.productName(item.outputId),
                    item.temporary ? 'Oui' : 'Non',
                  ],
                )
                .toList(),
          ),
        );
      }
      if (selected.contains(ExportDataset.suppliers)) {
        sheets.add(
          ExcelSheetData(
            name: 'Fournisseurs',
            headers: const ['Nom', 'Société', 'Contact'],
            rows: widget.suppliers
                .where((item) => matches(ExportDataset.suppliers, item.id))
                .map((item) => [item.name, item.company, item.contact])
                .toList(),
          ),
        );
      }
      if (selected.contains(ExportDataset.clients)) {
        sheets.add(
          ExcelSheetData(
            name: 'Clients',
            headers: const ['Nom', 'Société', 'Téléphone', 'ICE'],
            rows: widget.clients
                .where((item) => matches(ExportDataset.clients, item.id))
                .map((item) => [item.name, item.company, item.phone, item.ice])
                .toList(),
          ),
        );
      }
      await widget.saveSheets(sheets);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) message(context, 'Impossible de créer le fichier Excel.');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Exporter vers Excel'),
    content: SizedBox(
      width: 520,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          dateFilter(),
          const SizedBox(height: 8),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final dataset in ExportDataset.values) ...[
                    CheckboxListTile(
                      value: selected.contains(dataset),
                      title: Text(dataset.label),
                      onChanged: saving
                          ? null
                          : (checked) => setState(() {
                              if (checked == true) {
                                selected.add(dataset);
                              } else {
                                selected.remove(dataset);
                              }
                            }),
                    ),
                    if (selected.contains(dataset)) datasetFilters(dataset),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: saving ? null : () => Navigator.pop(context),
        child: const Text('Annuler'),
      ),
      FilledButton.icon(
        onPressed: saving || selected.isEmpty ? null : export,
        icon: const Icon(Icons.table_view_rounded),
        label: Text(saving ? 'Création…' : 'Créer le fichier Excel'),
      ),
    ],
  );
}

class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.padding,
    this.radius = 24,
    this.accent = AppPalette.secondary,
    this.frosted = false,
    this.depth,
    this.opacity,
  });

  final Widget child;
  final EdgeInsets? padding;
  final double radius;
  final Color accent;
  final bool frosted;

  /// Allows floating UI such as the phone navigation to reveal the content
  /// scrolling underneath it, without changing normal glass panels.
  final double? depth;
  final double? opacity;

  @override
  Widget build(BuildContext context) {
    final rounded = BorderRadius.circular(radius);
    final panel = _LiquidLayer(
      radius: radius,
      accent: accent,
      depth: depth ?? (frosted ? 1.58 : 1.23),
      opacity: opacity ?? (frosted ? .93 : .87),
      child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
    );
    if (!frosted) return panel;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: rounded,
        boxShadow: [
          BoxShadow(
            color: dark ? const Color(0x440B000F) : const Color(0x244170A3),
            blurRadius: 20,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: panel,
    );
  }
}

class AppHeader extends StatelessWidget {
  const AppHeader({
    super.key,
    required this.title,
    required this.user,
    required this.onLogout,
    required this.onOpenTeam,
    required this.onOpenBackups,
    required this.onOpenAnalytics,
    required this.canAccessAnalytics,
    required this.canExport,
    required this.onOpenExport,
    this.onOpenActivity,
    this.onOpenDeveloper,
  });
  final String title;
  final AppUser user;
  final VoidCallback onLogout;
  final VoidCallback onOpenTeam;
  final VoidCallback onOpenBackups;
  final VoidCallback onOpenAnalytics;
  final bool canAccessAnalytics;
  final bool canExport;
  final VoidCallback onOpenExport;
  final VoidCallback? onOpenActivity;
  final VoidCallback? onOpenDeveloper;

  void _showProfile(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .85,
      ),
      builder: (sheetContext) {
        VoidCallback closeThen(VoidCallback action) => () {
          Navigator.pop(sheetContext);
          action();
        };
        return ProfileSheet(
          user: user,
          onOpenTeam: closeThen(onOpenTeam),
          onOpenBackups: closeThen(onOpenBackups),
          onOpenExport: onOpenActivity != null && canExport
              ? closeThen(onOpenExport)
              : null,
          onOpenDeveloper:
              onOpenActivity != null &&
                  user.isDeveloper &&
                  onOpenDeveloper != null
              ? closeThen(onOpenDeveloper!)
              : null,
          onLogout: closeThen(onLogout),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = ForageAppearanceScope.of(context).isDark;
    final foreground = dark ? const Color(0xFFFFF5FF) : AppPalette.text;
    final secondary = dark ? const Color(0xFFE0BFEA) : AppPalette.muted;
    return Padding(
    padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
    child: IconTheme(
      data: IconThemeData(color: foreground),
      child: Glass(
      radius: 28,
      frosted: true,
      depth: 1.72,
      opacity: .80,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 20,
                    letterSpacing: -.6,
                    fontWeight: FontWeight.w800,
                    color: foreground,
                  ),
                ),
                Text(
                  user.effectiveRole.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: secondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          if (canAccessAnalytics) ...[
            _DashboardHeaderButton(
              label: 'Analyses',
              onTap: onOpenAnalytics,
              child: const Icon(Icons.bar_chart_rounded, size: 21),
            ),
            const SizedBox(width: 7),
          ],
          if (onOpenActivity case final openActivity?) ...[
            _DashboardHeaderButton(
              label: 'Notifications et contrôles',
              onTap: openActivity,
              child: const Icon(Icons.notifications_none_rounded, size: 21),
            ),
            const SizedBox(width: 7),
          ],
          if (onOpenActivity == null &&
              user.isDeveloper &&
              onOpenDeveloper != null) ...[
            Tooltip(
              message: 'Mode développeur',
              child: IconButton(
                onPressed: onOpenDeveloper,
                icon: const Icon(Icons.admin_panel_settings_rounded),
                color: AppPalette.coral,
                style: IconButton.styleFrom(
                  side: const BorderSide(color: AppPalette.coral),
                ),
              ),
            ),
            const SizedBox(width: 4),
          ],
          Builder(
            builder: (context) {
              final appearance = ForageAppearanceScope.of(context);
              return _DashboardHeaderButton(
                label: appearance.isDark ? 'Mode clair' : 'Mode sombre',
                onTap: appearance.toggle,
                child: Icon(
                  appearance.isDark
                      ? Icons.light_mode_rounded
                      : Icons.dark_mode_rounded,
                  size: 20,
                ),
              );
            },
          ),
          const SizedBox(width: 7),
          _DashboardHeaderButton(
            label: 'Profil',
            onTap: () => _showProfile(context),
            child: Text(
              user.fullName.characters.first.toUpperCase(),
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: foreground),
            ),
          ),
        ],
      ),
    ),
    ),
  );
  }
}

class ProfileSheet extends StatelessWidget {
  const ProfileSheet({
    super.key,
    required this.user,
    required this.onOpenTeam,
    required this.onOpenBackups,
    required this.onLogout,
    this.onOpenExport,
    this.onOpenDeveloper,
  });
  final AppUser user;
  final VoidCallback onOpenTeam;
  final VoidCallback onOpenBackups;
  final VoidCallback onLogout;
  final VoidCallback? onOpenExport;
  final VoidCallback? onOpenDeveloper;

  @override
  Widget build(BuildContext context) {
    final dark = ForageAppearanceScope.of(context).isDark;
    final foreground = dark ? const Color(0xFFFFF3FF) : AppPalette.text;
    final muted = dark ? const Color(0xFFE3C5ED) : AppPalette.muted;
    final accent = dark ? const Color(0xFFE46AFF) : AppPalette.primary;
    final tileSurface = dark
        ? const Color(0xE8280638)
        : AppPalette.surfaceRaised.withValues(alpha: .82);
    return SafeArea(
    top: false,
    child: TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 340),
      curve: Curves.easeOutCubic,
      tween: Tween(begin: 0, end: 1),
      builder: (context, value, child) => Transform.translate(
        offset: Offset(0, 28 * (1 - value)),
        child: Opacity(opacity: value, child: child),
      ),
      child: SingleChildScrollView(
        child: Glass(
          radius: 32,
          frosted: true,
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: dark ? const Color(0xFFBC76D6) : AppPalette.line,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(height: 22),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      dark
                          ? const Color(0xFF351047)
                          : AppPalette.desktopAccentSoft,
                      dark ? const Color(0xFF21052F) : AppPalette.surfaceRaised,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 29,
                      backgroundColor: accent.withValues(
                        alpha: .16,
                      ),
                      foregroundColor: accent,
                      child: Text(
                        user.fullName.substring(0, 1).toUpperCase(),
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user.fullName,
                            style: TextStyle(
                              color: foreground,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '@${user.username}',
                            style: TextStyle(color: muted),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            user.effectiveRole.label,
                            style: TextStyle(
                              color: muted,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Builder(
                builder: (context) {
                  final appearance = ForageAppearanceScope.of(context);
                  return ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    tileColor: tileSurface,
                    leading: Icon(
                      appearance.isDark
                          ? Icons.dark_mode_rounded
                          : Icons.light_mode_rounded,
                      color: accent,
                    ),
                    title: const Text(
                      'Apparence',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(
                      appearance.isDark
                          ? 'Mode sombre violet'
                          : 'Mode clair bleu',
                    ),
                    trailing: Switch.adaptive(
                      value: appearance.isDark,
                      onChanged: appearance.setDark,
                    ),
                    onTap: appearance.toggle,
                  );
                },
              ),
              const SizedBox(height: 8),
              if (user.isAdmin) ...[
                ListTile(
                  onTap: onOpenTeam,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  tileColor: tileSurface,
                  leading: Icon(
                    Icons.groups_rounded,
                    color: accent,
                  ),
                  title: const Text(
                    'Équipe',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: const Text('Gérer les membres de l’atelier'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                ),
                const SizedBox(height: 8),
              ],
              if (user.isAdmin) ...[
                ListTile(
                  onTap: onOpenBackups,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  tileColor: tileSurface,
                  leading: Icon(
                    Icons.backup_rounded,
                    color: accent,
                  ),
                  title: const Text(
                    'Sauvegardes',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: const Text(
                    'Télécharger, restaurer ou supprimer les données',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                ),
                const SizedBox(height: 8),
              ],
              if (onOpenExport case final export?)
                ListTile(
                  onTap: export,
                  leading: Icon(
                    Icons.table_view_rounded,
                    color: accent,
                  ),
                  title: const Text('Exporter vers Excel'),
                ),
              if (onOpenDeveloper case final developer?)
                ListTile(
                  onTap: developer,
                  leading: const Icon(
                    Icons.admin_panel_settings_rounded,
                    color: AppPalette.coral,
                  ),
                  title: const Text('Mode développeur'),
                ),
              ListTile(
                onTap: onLogout,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                leading: const Icon(
                  Icons.logout_rounded,
                  color: AppPalette.coral,
                ),
                title: const Text(
                  'Se déconnecter',
                  style: TextStyle(
                    color: AppPalette.coral,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }
}

class BackupPage extends StatefulWidget {
  const BackupPage({
    super.key,
    required this.lastBackupAt,
    required this.onDownload,
    required this.onRestore,
    required this.onClearData,
  });

  final Future<DateTime?> Function() lastBackupAt;
  final Future<bool> Function() onDownload;
  final Future<void> Function() onRestore;
  final Future<bool> Function() onClearData;

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  DateTime? lastBackup;
  var loading = true;
  var busy = false;

  bool get hasRecentBackup =>
      lastBackup != null && DateTime.now().difference(lastBackup!).inDays < 5;

  @override
  void initState() {
    super.initState();
    _refreshBackupStatus();
  }

  Future<void> _refreshBackupStatus() async {
    final value = await widget.lastBackupAt();
    if (mounted) {
      setState(() {
        lastBackup = value;
        loading = false;
      });
    }
  }

  Future<void> _download() async {
    setState(() => busy = true);
    await widget.onDownload();
    await _refreshBackupStatus();
    if (mounted) setState(() => busy = false);
  }

  Future<bool> _confirm({
    required String title,
    required String detail,
    required String action,
    required Color color,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(detail),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Annuler'),
              ),
              FilledButton(
                style: color == AppPalette.coral ? _criticalActionStyle : null,
                onPressed: () => Navigator.pop(context, true),
                child: Text(action),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _restore() async {
    final confirmed = await _confirm(
      title: 'Restaurer la sauvegarde ?',
      detail: 'Les données actuelles de l’atelier seront remplacées par celles du fichier choisi.',
      action: 'Importer',
      color: Theme.of(context).colorScheme.primary,
    );
    if (!confirmed || !mounted) return;
    setState(() => busy = true);
    await widget.onRestore();
    await _refreshBackupStatus();
    if (mounted) setState(() => busy = false);
  }

  Future<void> _clearData() async {
    final confirmed = await _confirm(
      title: 'Supprimer les données de l’atelier ?',
      detail: 'Cette action supprimera les produits, catégories, machines, opérations, dépôts et ajouts de stock. Les comptes utilisateurs seront conservés.',
      action: 'Supprimer',
      color: AppPalette.coral,
    );
    if (!confirmed || !mounted) return;
    setState(() => busy = true);
    await widget.onClearData();
    await _refreshBackupStatus();
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => FormShell(
    title: 'Sauvegardes',
    subtitle: 'Protection des données de FORAGE ZOUHOUR',
    child: loading
        ? const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(),
            ),
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Glass(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: hasRecentBackup
                            ? const Color(0xFFDCFCE7)
                            : const Color(0xFFFFEDD5),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        hasRecentBackup
                            ? Icons.verified_user_rounded
                            : Icons.warning_amber_rounded,
                        color: hasRecentBackup
                            ? const Color(0xFF15803D)
                            : const Color(0xFFB45309),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            hasRecentBackup
                                ? 'Sauvegarde automatique à jour'
                                : 'Sauvegarde à effectuer',
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            lastBackup == null
                                ? 'Aucune sauvegarde n’a encore été téléchargée.'
                                : 'Dernier téléchargement : ${dateText(lastBackup!)}',
                            style: TextStyle(color: _atelierMuted(context)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Glass(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Icon(Icons.lock_outline_rounded, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Les sauvegardes automatiques sont volontairement désactivées : '
                        'chaque sauvegarde est chiffrée avec un mot de passe que '
                        'l’application ne conserve pas.',
                        style: TextStyle(fontSize: 12, color: _atelierMuted(context)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Télécharger une sauvegarde',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
              Text(
                'Enregistre un fichier JSON complet que vous pourrez conserver et réimporter plus tard.',
                style: TextStyle(color: _atelierMuted(context)),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: busy ? null : _download,
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('Télécharger la sauvegarde'),
                ),
              ),
              const SizedBox(height: 22),
              const Text(
                'Restaurer une sauvegarde',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
              Text(
                'Importez un fichier de sauvegarde FORAGE ZOUHOUR pour remplacer les données actuelles.',
                style: TextStyle(color: _atelierMuted(context)),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: busy ? null : _restore,
                  icon: const Icon(Icons.upload_file_rounded),
                  label: const Text('Importer une sauvegarde'),
                ),
              ),
              const SizedBox(height: 22),
              Text(
                'Zone sensible',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                hasRecentBackup
                    ? 'Une sauvegarde récente a été téléchargée : vous pouvez supprimer les informations de l’atelier.'
                    : 'La suppression reste bloquée tant qu’une nouvelle sauvegarde n’a pas été téléchargée.',
                style: TextStyle(color: _atelierMuted(context)),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: _criticalActionStyle,
                  onPressed: busy || !hasRecentBackup ? null : _clearData,
                  icon: const Icon(Icons.delete_forever_rounded),
                  label: const Text('Supprimer les données de l’atelier'),
                ),
              ),
            ],
          ),
  );
}

class DashboardPage extends StatelessWidget {
  const DashboardPage({
    super.key,
    required this.user,
    required this.productCount,
    required this.machineCount,
    required this.pendingReviews,
    required this.onProducts,
    required this.onStock,
    required this.onMachines,
    required this.onTeam,
    required this.onValidation,
    required this.onCategories,
    required this.onReviews,
    this.forceDesktopLayout = false,
  });

  final AppUser user;
  final int productCount;
  final int machineCount;
  final int pendingReviews;
  final VoidCallback onProducts;
  final VoidCallback onStock;
  final VoidCallback onMachines;
  final VoidCallback onTeam;
  final VoidCallback onValidation;
  final VoidCallback onCategories;
  final VoidCallback onReviews;
  final bool forceDesktopLayout;

  @override
  Widget build(BuildContext context) {
    // Keep one responsive dashboard tree in both appearances. The old
    // dark-only tree could collapse on phone after changing appearance,
    // leaving the wallpaper and navigation visible without any Home content.
    final desktop =
        forceDesktopLayout ||
        (_usesWorkspaceRail(context) &&
            MediaQuery.sizeOf(context).width >= 1380);
    return Page(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (desktop)
            _DesktopDashboardWelcome(
              firstName: user.fullName.trim().split(RegExp(r'\s+')).first,
            ),
          if (desktop) const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final hero = _AtelierOverview(
                firstName: user.fullName.trim().split(RegExp(r'\s+')).first,
                machineCount: machineCount,
                desktop: desktop,
              );
              final products = _DashboardMetric(
                icon: Icons.view_in_ar_outlined,
                label: 'Produits',
                value: productCount,
                accent: AppPalette.secondary,
              );
              final reviews = _DashboardMetric(
                icon: Icons.schedule_rounded,
                label: 'Contrôles en attente',
                value: pendingReviews,
                accent: pendingReviews > 0
                    ? AppPalette.amber
                    : AppPalette.primary,
              );
              if (constraints.maxWidth >= (desktop ? 780 : 690)) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: hero),
                    const SizedBox(width: 14),
                    Expanded(
                      flex: 2,
                      child: Column(
                        children: [
                          products,
                          const SizedBox(height: 12),
                          reviews,
                        ],
                      ),
                    ),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  hero,
                  const SizedBox(height: 12),
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: products),
                        const SizedBox(width: 10),
                        Expanded(child: reviews),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 19),
          Text(
            'Accès rapide',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -.4),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= (desktop ? 940 : 670)
                  ? 6
                  : constraints.maxWidth >= 670
                  ? 3
                  : constraints.maxWidth >= 290
                  ? 2
                  : 1;
              const gap = 10.0;
              final width =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;
              final shortcuts = [
                _DashboardAction(
                  icon: Icons.inventory_2_outlined,
                  color: const Color(0xFF1A95E8),
                  label: 'Produits',
                  onTap: onProducts,
                ),
                _DashboardAction(
                  icon: Icons.warehouse_outlined,
                  color: const Color(0xFF2FB9E8),
                  label: 'Stock',
                  onTap: onStock,
                ),
                _DashboardAction(
                  icon: Icons.precision_manufacturing_outlined,
                  color: const Color(0xFF4A7EEA),
                  label: 'Machines',
                  onTap: onMachines,
                ),
                _DashboardAction(
                  icon: Icons.folder_outlined,
                  color: const Color(0xFF258DD8),
                  label: 'Familles',
                  onTap: onCategories,
                ),
                _DashboardAction(
                  icon: user.canValidate
                      ? Icons.verified_user_outlined
                      : Icons.fact_check_outlined,
                  color: const Color(0xFF38A8E6),
                  label: user.canValidate ? 'Validations' : 'Contrôles',
                  onTap: user.canValidate ? onValidation : onReviews,
                ),
                if (user.isAdmin)
                  _DashboardAction(
                    icon: Icons.groups_outlined,
                    color: const Color(0xFF668AEF),
                    label: 'Équipe',
                    onTap: onTeam,
                  ),
              ];
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final shortcut in shortcuts)
                    SizedBox(
                      width: width,
                      child: _DashboardAction(
                        icon: shortcut.icon,
                        color: shortcut.color,
                        label: shortcut.label,
                        onTap: shortcut.onTap,
                        desktop: desktop,
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Purpose-built midnight presentation.  This is not a colour-filtered copy
/// of the light dashboard: the panels, typography and reflections are drawn
/// for the dark material itself.
// ignore: unused_element
class _DarkDashboardPage extends StatelessWidget {
  const _DarkDashboardPage({
    required this.user,
    required this.productCount,
    required this.machineCount,
    required this.pendingReviews,
    required this.onProducts,
    required this.onStock,
    required this.onMachines,
    required this.onTeam,
    required this.onValidation,
    required this.onCategories,
    required this.onReviews,
    required this.forceDesktopLayout,
  });

  final AppUser user;
  final int productCount;
  final int machineCount;
  final int pendingReviews;
  final VoidCallback onProducts;
  final VoidCallback onStock;
  final VoidCallback onMachines;
  final VoidCallback onTeam;
  final VoidCallback onValidation;
  final VoidCallback onCategories;
  final VoidCallback onReviews;
  final bool forceDesktopLayout;

  @override
  Widget build(BuildContext context) {
    final desktop = forceDesktopLayout ||
        (_usesWorkspaceRail(context) && MediaQuery.sizeOf(context).width >= 1100);
    final name = user.fullName.trim().split(RegExp(r'\s+')).first;
    final actions = <({IconData icon, String label, Color accent, VoidCallback tap})>[
      (icon: Icons.inventory_2_outlined, label: 'Produits', accent: const Color(0xFFE65CFF), tap: onProducts),
      (icon: Icons.warehouse_outlined, label: 'Stock', accent: const Color(0xFFCBADFF), tap: onStock),
      (icon: Icons.precision_manufacturing_outlined, label: 'Machines', accent: const Color(0xFFF2A4FF), tap: onMachines),
      (icon: Icons.folder_outlined, label: 'Familles', accent: const Color(0xFFFFC18F), tap: onCategories),
      (icon: user.canValidate ? Icons.verified_user_outlined : Icons.fact_check_outlined, label: user.canValidate ? 'Validations' : 'Contrôles', accent: const Color(0xFFF3D3FF), tap: user.canValidate ? onValidation : onReviews),
      if (user.isAdmin) (icon: Icons.groups_outlined, label: 'Équipe', accent: const Color(0xFFFF80EC), tap: onTeam),
    ];
    return Page(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = desktop && constraints.maxWidth >= 820;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (desktop) _DarkDashboardIntro(firstName: name),
              if (desktop) const SizedBox(height: 15),
              if (wide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 13, child: _DarkOverviewCard(firstName: name, machines: machineCount)),
                    const SizedBox(width: 14),
                    Expanded(
                      flex: 9,
                      child: Column(
                        children: [
                          _DarkMetric(icon: Icons.view_in_ar_outlined, value: productCount, label: 'Produits', accent: const Color(0xFFE95CFF)),
                          const SizedBox(height: 12),
                          _DarkMetric(icon: Icons.schedule_rounded, value: pendingReviews, label: 'Contrôles en attente', accent: const Color(0xFFFF9D68)),
                        ],
                      ),
                    ),
                  ],
                )
              else ...[
                _DarkOverviewCard(firstName: name, machines: machineCount),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _DarkMetric(icon: Icons.view_in_ar_outlined, value: productCount, label: 'Produits', accent: const Color(0xFFE95CFF))),
                    const SizedBox(width: 10),
                    Expanded(child: _DarkMetric(icon: Icons.schedule_rounded, value: pendingReviews, label: 'Contrôles en attente', accent: const Color(0xFFFF9D68))),
                  ],
                ),
              ],
              const SizedBox(height: 21),
              const Text('Accès rapide', style: TextStyle(color: Color(0xFFFFF5FF), fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -.5)),
              const SizedBox(height: 11),
              LayoutBuilder(
                builder: (context, quick) {
                  final columns = wide ? min(6, actions.length) : 2;
                  const gap = 10.0;
                  final width = (quick.maxWidth - (columns - 1) * gap) / columns;
                  return Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      for (final action in actions)
                        SizedBox(
                          width: width,
                          child: _DarkQuickAction(
                            icon: action.icon,
                            label: action.label,
                            accent: action.accent,
                            onTap: action.tap,
                            desktop: wide,
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DarkGlassPanel extends StatelessWidget {
  const _DarkGlassPanel({
    super.key,
    required this.child,
    this.radius = 26,
    this.accent = const Color(0xFFE9B1FF),
    this.padding,
    this.onTap,
  });

  final Widget child;
  final double radius;
  final Color accent;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final panel = Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: const Color(0xFFF4C8FF).withValues(alpha: .58), width: 1.1),
        boxShadow: [
          BoxShadow(color: accent.withValues(alpha: .23), blurRadius: 24, spreadRadius: -5, offset: const Offset(0, 10)),
          const BoxShadow(color: Color(0xA8000010), blurRadius: 19, offset: Offset(0, 12)),
        ],
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(const Color(0xFF6A2788), accent, .15)!.withValues(alpha: .78),
            const Color(0xD01C062A),
            const Color(0xE4380B51),
          ],
          stops: const [0, .44, 1],
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius - 1),
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: const Alignment(-.9, -1),
                      end: const Alignment(.55, .2),
                      colors: [Colors.white.withValues(alpha: .27), Colors.white.withValues(alpha: .035), Colors.transparent],
                      stops: const [0, .18, .58],
                    ),
                  ),
                ),
              ),
            ),
            // The content must be a normal Stack child.  When it is wrapped
            // in Positioned.fill it no longer participates in layout; a
            // panel made only of positioned children receives a zero size on
            // Windows. That was why Accueil looked completely empty.
            child,
          ],
        ),
      ),
    );
    if (onTap == null) return panel;
    return Material(color: Colors.transparent, child: InkWell(borderRadius: BorderRadius.circular(radius), onTap: onTap, splashFactory: NoSplash.splashFactory, child: panel));
  }
}

class _DarkDashboardIntro extends StatelessWidget {
  const _DarkDashboardIntro({required this.firstName});
  final String firstName;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 3, 8, 2),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('VUE D’ENSEMBLE', style: TextStyle(color: Color(0xFFE78BFF), fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 2.2)),
        const SizedBox(height: 6),
        Text(firstName.isEmpty ? 'Bonjour' : 'Bonjour, $firstName 👋', style: const TextStyle(color: Color(0xFFFFF7FF), fontSize: 31, height: 1, fontWeight: FontWeight.w800, letterSpacing: -1.1)),
        const SizedBox(height: 7),
        const Text('Voici un aperçu de votre atelier aujourd’hui.', style: TextStyle(color: Color(0xFFD8B6E5), fontSize: 14, fontWeight: FontWeight.w600)),
      ],
    ),
  );
}

class _DarkOverviewCard extends StatelessWidget {
  const _DarkOverviewCard({required this.firstName, required this.machines});
  final String firstName;
  final int machines;

  @override
  Widget build(BuildContext context) => _DarkGlassPanel(
    key: const ValueKey('dark-dashboard-overview'),
    radius: 31,
    accent: const Color(0xFFD94CFF),
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 211),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(right: -28, bottom: -53, child: _DarkOrbitalGear()),
          Positioned(left: 20, top: 16, child: _DarkGlassLabel()),
          Positioned(
            left: 21,
            bottom: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (MediaQuery.sizeOf(context).width < 620) ...[
                  Text(firstName.isEmpty ? 'Bonjour' : 'Bonjour, $firstName', style: const TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.w800, letterSpacing: -.8)),
                  const SizedBox(height: 15),
                ],
                ShaderMask(
                  shaderCallback: (rect) => const LinearGradient(colors: [Color(0xFFF5C9FF), Color(0xFFC253FF), Color(0xFFEF6CFF)]).createShader(rect),
                  child: Text('$machines', style: const TextStyle(color: Colors.white, fontSize: 57, height: .9, fontWeight: FontWeight.w800, letterSpacing: -3)),
                ),
                const SizedBox(height: 7),
                const Text('Machines de l’atelier', style: TextStyle(color: Color(0xFFF1DDF7), fontSize: 13, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _DarkGlassLabel extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.white.withValues(alpha: .32)),
      gradient: LinearGradient(colors: [const Color(0xD9C65DFF), const Color(0x803D1459)]),
    ),
    child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.grid_view_rounded, color: Colors.white, size: 13), SizedBox(width: 6), Text('VUE D’ENSEMBLE', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.05))]),
  );
}

class _DarkOrbitalGear extends StatelessWidget {
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 186,
    height: 186,
    child: Stack(alignment: Alignment.center, children: [
      Transform.rotate(angle: -.48, child: Container(width: 176, height: 112, decoration: BoxDecoration(borderRadius: BorderRadius.circular(70), border: Border.all(color: const Color(0xFFD99CFF).withValues(alpha: .54), width: 1.2), gradient: RadialGradient(colors: [const Color(0x559D2FE4), Colors.transparent])))),
      Transform.rotate(angle: .42, child: Container(width: 102, height: 102, decoration: BoxDecoration(borderRadius: BorderRadius.circular(34), border: Border.all(color: const Color(0xFFF6D8FF).withValues(alpha: .7), width: 1.2), boxShadow: [BoxShadow(color: const Color(0xFFDF54FF).withValues(alpha: .36), blurRadius: 24)], gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFB34BE1), Color(0xFF4D126F), Color(0xFF9C3FD3)])), child: Transform.rotate(angle: -.42, child: const Icon(Icons.settings_outlined, color: Colors.white, size: 42)))),
    ]),
  );
}

class _DarkMetric extends StatelessWidget {
  const _DarkMetric({required this.icon, required this.value, required this.label, required this.accent});
  final IconData icon;
  final int value;
  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) => _DarkGlassPanel(
    radius: 25,
    accent: accent,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    child: SizedBox(
      height: 64,
      child: Row(children: [
        _DarkIcon(icon: icon, color: accent),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('$value', style: const TextStyle(color: Colors.white, fontSize: 26, height: .96, fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()])),
          const SizedBox(height: 4),
          Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFFF0DDF5), fontSize: 11, height: 1.05, fontWeight: FontWeight.w600)),
        ])),
      ]),
    ),
  );
}

class _DarkQuickAction extends StatelessWidget {
  const _DarkQuickAction({required this.icon, required this.label, required this.accent, required this.onTap, required this.desktop});
  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback onTap;
  final bool desktop;

  @override
  Widget build(BuildContext context) => _DarkGlassPanel(
    radius: desktop ? 25 : 23,
    accent: accent,
    onTap: onTap,
    padding: EdgeInsets.symmetric(horizontal: desktop ? 11 : 12, vertical: desktop ? 16 : 9),
    child: desktop
        ? SizedBox(height: 108, child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [_DarkIcon(icon: icon, color: accent, size: 44), const SizedBox(height: 10), Text(label, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800)), const SizedBox(height: 7), const Icon(Icons.arrow_forward_rounded, color: Color(0xFFEEDCFA), size: 16)]))
        : SizedBox(height: 56, child: Row(children: [_DarkIcon(icon: icon, color: accent, size: 36), const SizedBox(width: 10), Expanded(child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800))), const Icon(Icons.chevron_right_rounded, color: Color(0xFFF2DDFC), size: 18)])),
  );
}

class _DarkIcon extends StatelessWidget {
  const _DarkIcon({required this.icon, required this.color, this.size = 40});
  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(borderRadius: BorderRadius.circular(size * .31), border: Border.all(color: Colors.white.withValues(alpha: .38)), boxShadow: [BoxShadow(color: color.withValues(alpha: .44), blurRadius: 14)], gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color.lerp(color, Colors.white, .33)!, color.withValues(alpha: .76), const Color(0xFF42105C)])),
    child: Icon(icon, size: size * .55, color: Colors.white, shadows: const [Shadow(color: Color(0x990E0018), blurRadius: 4, offset: Offset(0, 2))]),
  );
}

class MobileGlassNavigation extends StatelessWidget {
  const MobileGlassNavigation({
    super.key,
    required this.index,
    required this.onTap,
    required this.showTeam,
  });
  final int index;
  final ValueChanged<int> onTap;
  final bool showTeam;
  static const _labels = ['Accueil', 'Produits', 'Stock', 'Machines', 'Équipe'];
  static const _icons = [
    Icons.home_rounded,
    Icons.grid_view_outlined,
    Icons.inventory_2_outlined,
    Icons.precision_manufacturing_outlined,
    Icons.people_outline,
  ];
  @override
  Widget build(BuildContext context) {
    final indexes = showTeam ? const [0, 1, 2, 3, 4] : const [0, 1, 2, 3];
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Glass(
        radius: 26,
        accent: AppPalette.primary,
        frosted: true,
        depth: 1.58,
        // The navigator stays above the page, but the page is intentionally
        // visible underneath it instead of being hidden by an opaque bar.
        opacity: .64,
        padding: const EdgeInsets.all(5),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth / indexes.length;
            final active = indexes.indexOf(index);
            final duration = MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 350);
            return Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedPositionedDirectional(
                  duration: duration,
                  curve: Curves.easeOutBack,
                  start: max(0, active) * width + 2,
                  top: 1,
                  bottom: 1,
                  width: max(0.0, width - 4),
                  child: IgnorePointer(
                    child: AnimatedOpacity(
                      opacity: active < 0 ? 0 : 1,
                      duration: duration,
                      child: const _AtelierNavCapsule(),
                    ),
                  ),
                ),
                Row(
                  children: [
                    for (final pageIndex in indexes)
                      Expanded(
                        child: _AtelierNavItem(
                          label: _labels[pageIndex],
                          icon: _icons[pageIndex],
                          selected: pageIndex == index,
                          onTap: () => onTap(pageIndex),
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Desktop-only workspace.  The phone keeps the compact bottom navigation,
/// while Windows gets a persistent rail and a calmer, card-based canvas.
class WindowsWorkspaceShell extends StatefulWidget {
  const WindowsWorkspaceShell({
    super.key,
    required this.title,
    required this.user,
    required this.section,
    required this.onSectionChanged,
    required this.onLogout,
    required this.onOpenTeam,
    required this.onOpenBackups,
    required this.onOpenAnalytics,
    required this.canAccessAnalytics,
    required this.canExport,
    required this.onOpenExport,
    required this.onOpenDeveloper,
    required this.child,
  });

  final String title;
  final AppUser user;
  final int section;
  final ValueChanged<int> onSectionChanged;
  final VoidCallback onLogout;
  final VoidCallback onOpenTeam;
  final VoidCallback onOpenBackups;
  final VoidCallback onOpenAnalytics;
  final bool canAccessAnalytics;
  final bool canExport;
  final VoidCallback onOpenExport;
  final VoidCallback onOpenDeveloper;
  final Widget child;

  @override
  State<WindowsWorkspaceShell> createState() => _WindowsWorkspaceShellState();
}

class _WindowsWorkspaceShellState extends State<WindowsWorkspaceShell> {
  var collapsed = false;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      _WindowsNavigationRail(
        user: widget.user,
        selectedIndex: widget.section,
        compact: collapsed,
        onToggle: () => setState(() => collapsed = !collapsed),
        onSelected: widget.onSectionChanged,
        onLogout: widget.onLogout,
      ),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 22, 18),
          child: Column(
            children: [
              _WindowsTopBar(
                title: widget.title,
                user: widget.user,
                onOpenAnalytics: widget.onOpenAnalytics,
                canAccessAnalytics: widget.canAccessAnalytics,
                canExport: widget.canExport,
                onOpenExport: widget.onOpenExport,
                onOpenProfile: () => _showWindowsProfile(context),
              ),
              const SizedBox(height: 12),
              Expanded(
                // A previous AnimatedSwitcher occasionally retained an
                // outgoing transparent page on Windows after a quick click,
                // leaving the workspace apparently empty.  The new page is
                // deliberately installed immediately; individual controls
                // still keep their own small press animations.
                child: KeyedSubtree(
                  key: ValueKey(widget.section),
                  child: widget.child,
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  );

  void _showWindowsProfile(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      constraints: const BoxConstraints(maxWidth: 460),
      builder: (sheetContext) {
        VoidCallback closeThen(VoidCallback action) => () {
          Navigator.pop(sheetContext);
          action();
        };
        return ProfileSheet(
          user: widget.user,
          onOpenTeam: closeThen(widget.onOpenTeam),
          onOpenBackups: closeThen(widget.onOpenBackups),
          onOpenExport: widget.canExport
              ? closeThen(widget.onOpenExport)
              : null,
          onOpenDeveloper: widget.user.isDeveloper
              ? closeThen(widget.onOpenDeveloper)
              : null,
          onLogout: closeThen(widget.onLogout),
        );
      },
    );
  }
}

class _WindowsTopBar extends StatefulWidget {
  const _WindowsTopBar({
    required this.title,
    required this.user,
    required this.onOpenAnalytics,
    required this.canAccessAnalytics,
    required this.canExport,
    required this.onOpenExport,
    required this.onOpenProfile,
  });

  final String title;
  final AppUser user;
  final VoidCallback onOpenAnalytics;
  final bool canAccessAnalytics;
  final bool canExport;
  final VoidCallback onOpenExport;
  final VoidCallback onOpenProfile;

  @override
  State<_WindowsTopBar> createState() => _WindowsTopBarState();
}

class _WindowsTopBarState extends State<_WindowsTopBar> {
  final searchFocus = FocusNode();

  @override
  void dispose() {
    searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = ForageAppearanceScope.of(context).isDark;
    final foreground = dark ? const Color(0xFFFFF5FF) : AppPalette.text;
    final muted = dark ? const Color(0xFFDDBFE8) : AppPalette.muted;
    return CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.keyK, control: true):
          searchFocus.requestFocus,
    },
    child: Focus(
      // Do not steal keyboard focus during login/page changes on Windows.
      // The previous autofocus could race the native text-input channel.
      autofocus: false,
      child: Glass(
        radius: 28,
        accent: AppPalette.primary,
        frosted: true,
        // A lighter lens makes the wallpaper visibly refract under the
        // desktop header instead of reading as a plain white panel.
        depth: 1.87,
        opacity: .80,
        padding: const EdgeInsets.fromLTRB(18, 8, 10, 8),
        child: Row(
          children: [
            SizedBox(
              width: 150,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 20,
                      letterSpacing: -.6,
                      fontWeight: FontWeight.w800,
                      color: foreground,
                    ),
                  ),
                  Text(
                    widget.user.effectiveRole.label,
                    style: TextStyle(
                      color: muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 470),
                  child: SizedBox(
                    height: 42,
                    child: TextField(
                      focusNode: searchFocus,
                      textInputAction: TextInputAction.search,
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        isDense: true,
                        filled: true,
                        fillColor: dark
                            ? const Color(0x55340B50)
                            : AppPalette.surface.withValues(alpha: .48),
                        hintText: 'Rechercher un produit, une machine, …',
                        hintStyle: TextStyle(
                          color: muted,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        prefixIcon: const Icon(Icons.search_rounded, size: 20),
                        suffixIcon: SizedBox(
                          width: 58,
                          child: Container(
                            margin: const EdgeInsets.all(7),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                                color: (dark
                                        ? const Color(0xFFCA69EF)
                                        : AppPalette.primary)
                                    .withValues(alpha: .18),
                              borderRadius: BorderRadius.circular(7),
                              border: Border.all(
                                color: (dark
                                        ? const Color(0xFFCA69EF)
                                        : AppPalette.primary)
                                    .withValues(
                                  alpha: .42,
                                ),
                              ),
                            ),
                            child: Text(
                              'Ctrl K',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: foreground,
                              ),
                            ),
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 9,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            if (widget.canExport)
              _DashboardHeaderButton(
                label: 'Exporter vers Excel',
                onTap: widget.onOpenExport,
                child: const Icon(Icons.table_view_rounded, size: 21),
              ),
            if (widget.canAccessAnalytics) ...[
              const SizedBox(width: 7),
              _DashboardHeaderButton(
                label: 'Analyses',
                onTap: widget.onOpenAnalytics,
                child: const Icon(Icons.bar_chart_rounded, size: 21),
              ),
            ],
            const SizedBox(width: 7),
            Builder(
              builder: (context) {
                final appearance = ForageAppearanceScope.of(context);
                return _DashboardHeaderButton(
                  label: appearance.isDark ? 'Mode clair' : 'Mode sombre',
                  onTap: appearance.toggle,
                  child: Icon(
                    appearance.isDark
                        ? Icons.light_mode_rounded
                        : Icons.dark_mode_rounded,
                    size: 20,
                  ),
                );
              },
            ),
            const SizedBox(width: 7),
            _DashboardHeaderButton(
              label: 'Profil',
              onTap: widget.onOpenProfile,
              child: Text(
                widget.user.fullName.characters.first.toUpperCase(),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
    );
  }
}

class _WindowsNavigationRail extends StatelessWidget {
  const _WindowsNavigationRail({
    required this.user,
    required this.selectedIndex,
    required this.compact,
    required this.onToggle,
    required this.onSelected,
    required this.onLogout,
  });

  final AppUser user;
  final int selectedIndex;
  final bool compact;
  final VoidCallback onToggle;
  final ValueChanged<int> onSelected;
  final VoidCallback onLogout;

  static const _entries = <_DesktopNavigationEntry>[
    _DesktopNavigationEntry('Vue générale', Icons.grid_view_rounded),
    _DesktopNavigationEntry('Produits', Icons.view_in_ar_outlined),
    _DesktopNavigationEntry('Stock', Icons.inventory_2_rounded),
    _DesktopNavigationEntry('Machines', Icons.precision_manufacturing_rounded),
    _DesktopNavigationEntry('Équipe', Icons.groups_outlined),
    _DesktopNavigationEntry('Validations', Icons.verified_user_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final dark = ForageAppearanceScope.of(context).isDark;
    final muted = dark ? const Color(0xFFDEC0E9) : AppPalette.muted;
    return AnimatedContainer(
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 280),
    curve: Curves.easeOutCubic,
    width: compact ? 76 : 246,
    margin: const EdgeInsets.fromLTRB(14, 12, 0, 18),
    child: Glass(
      radius: 28,
      depth: 1.75,
      opacity: .82,
      frosted: true,
      padding: EdgeInsets.fromLTRB(
          compact ? 8 : 12,
          12,
          compact ? 8 : 12,
          12,
        ),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DesktopBrand(compact: compact, onToggle: onToggle),
            SizedBox(height: compact ? 20 : 26),
            if (!compact) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  'ESPACE DE TRAVAIL',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    color: muted,
                    letterSpacing: 1.25,
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
            ..._entries.indexed
                .where((entry) {
                  final index = entry.$1;
                  if (index == 4 && !user.isAdmin) return false;
                  return user.canAccess(AppPage.values[index]);
                })
                .map(
                  (entry) => _DesktopNavigationButton(
                    entry: entry.$2,
                    selected: selectedIndex == entry.$1,
                    compact: compact,
                    onTap: () => onSelected(entry.$1),
                  ),
                ),
            const Spacer(),
            Glass(
              radius: 18,
              depth: 1.32,
              opacity: .72,
              padding: EdgeInsets.all(compact ? 7 : 12),
              child: compact
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(
                          radius: 17,
                          backgroundColor: dark
                              ? const Color(0xFF61247F)
                              : AppPalette.desktopAccentSoft,
                          foregroundColor: dark
                              ? const Color(0xFFFFE9FF)
                              : AppPalette.desktopAccent,
                          child: Text(
                            user.fullName.substring(0, 1).toUpperCase(),
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                        const SizedBox(height: 6),
                        IconButton(
                          tooltip: 'Déconnexion',
                          onPressed: onLogout,
                          icon: const Icon(Icons.logout_rounded, size: 18),
                          color: muted,
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        CircleAvatar(
                          radius: 17,
                          backgroundColor: dark
                              ? const Color(0xFF61247F)
                              : AppPalette.desktopAccentSoft,
                          foregroundColor: dark
                              ? const Color(0xFFFFE9FF)
                              : AppPalette.desktopAccent,
                          child: Text(
                            user.fullName.substring(0, 1).toUpperCase(),
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                user.fullName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: dark
                                      ? const Color(0xFFFFF5FF)
                                      : AppPalette.text,
                                ),
                              ),
                              Text(
                                user.effectiveRole.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: muted,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Déconnexion',
                          onPressed: onLogout,
                          icon: const Icon(Icons.logout_rounded, size: 18),
                          color: muted,
                        ),
                      ],
                    ),
            ),
          ],
        ),
    ),
    );
  }
}

class _DesktopBrand extends StatelessWidget {
  const _DesktopBrand({required this.compact, required this.onToggle});
  final bool compact;
  final VoidCallback onToggle;

  Widget _mark(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Glass(
      radius: 13,
      accent: scheme.primary,
      depth: 1.44,
      child: SizedBox.square(
        dimension: 40,
        child: Icon(
          Icons.precision_manufacturing_rounded,
          color: scheme.onSurface,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = ForageAppearanceScope.of(context).isDark;
    final foreground = dark ? const Color(0xFFFFF5FF) : AppPalette.text;
    final muted = dark ? const Color(0xFFE1BEEB) : AppPalette.muted;
    final accent = dark ? const Color(0xFFE77BFF) : AppPalette.desktopAccent;
    return Glass(
    radius: 20,
    accent: AppPalette.primary,
    frosted: true,
    depth: 1.34,
    opacity: .72,
    padding: const EdgeInsets.all(6),
    child: compact
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Agrandir le menu',
                onPressed: onToggle,
                icon: const Icon(Icons.keyboard_double_arrow_right_rounded),
                iconSize: 16,
                color: muted,
              ),
              const SizedBox(height: 4),
              _mark(context),
            ],
          )
        : Row(
            children: [
              _mark(context),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'FORAGE',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: foreground,
                      ),
                    ),
                    Text(
                      'WORKSPACE',
                      style: TextStyle(
                        fontSize: 10,
                        color: accent,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Réduire le menu',
                onPressed: onToggle,
                icon: const Icon(Icons.keyboard_double_arrow_left_rounded),
                iconSize: 16,
                color: muted,
              ),
            ],
          ),
    );
  }
}

class _DesktopNavigationEntry {
  const _DesktopNavigationEntry(this.label, this.icon);
  final String label;
  final IconData icon;
}

class _DesktopNavigationButton extends StatelessWidget {
  const _DesktopNavigationButton({
    required this.entry,
    required this.selected,
    required this.compact,
    required this.onTap,
  });

  final _DesktopNavigationEntry entry;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = ForageAppearanceScope.of(context).isDark;
    final foreground = dark ? const Color(0xFFFFF6FF) : AppPalette.text;
    final muted = dark ? const Color(0xFFE2C4ED) : AppPalette.muted;
    final accent = dark ? const Color(0xFFE65CFF) : AppPalette.desktopAccent;
    final button = Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: _LiquidTapTarget(
        radius: 14,
        selected: selected,
        accent: selected
            ? accent
            : (dark ? const Color(0xFF9868AA) : AppPalette.secondary),
        idleOpacity: .49,
        selectedOpacity: .86,
        onTap: onTap,
        child: Padding(
          padding: compact
              ? const EdgeInsets.symmetric(vertical: 11)
              : const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: compact
              ? Center(
                  child: AnimatedScale(
                    duration: const Duration(milliseconds: 240),
                    curve: Curves.easeOutBack,
                    scale: selected ? 1.1 : 1,
                    child: Icon(
                      entry.icon,
                      color: selected
                          ? accent
                          : muted,
                      size: 21,
                    ),
                  ),
                )
              : Row(
                  children: [
                    AnimatedScale(
                      duration: const Duration(milliseconds: 240),
                      curve: Curves.easeOutBack,
                      scale: selected ? 1.08 : 1,
                      child: Icon(
                        entry.icon,
                        color: selected
                            ? accent
                            : muted,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    AnimatedOpacity(
                      duration: const Duration(milliseconds: 180),
                      opacity: selected ? 1 : .86,
                      child: Text(
                        entry.label,
                        style: TextStyle(
                          color: selected ? foreground : muted,
                          fontWeight: selected
                              ? FontWeight.w900
                              : FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const Spacer(),
                    AnimatedOpacity(
                      duration: const Duration(milliseconds: 160),
                      opacity: selected ? 1 : 0,
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
    return compact ? Tooltip(message: entry.label, child: button) : button;
  }
}

class Page extends StatelessWidget {
  const Page({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final isWindows = _usesWorkspaceRail(context);
    return SingleChildScrollView(
      padding: isWindows
          ? const EdgeInsets.fromLTRB(28, 8, 28, 32)
          : const EdgeInsets.fromLTRB(16, 13, 16, 100),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: isWindows ? 1260 : 1050),
          // Windows section changes are immediate. Besides feeling more
          // responsive, this prevents a failed entrance animation from
          // leaving the desktop content at zero opacity.
          child: isWindows ? child : AppEntrance(child: child),
        ),
      ),
    );
  }
}

class SectionHero extends StatelessWidget {
  const SectionHero({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final foreground = _atelierForeground(context);
    final muted = _atelierMuted(context);
    return Glass(
      padding: const EdgeInsets.all(17),
      radius: 26,
      accent: AppPalette.primary,
      frosted: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AtelierIcon(icon, size: 47),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: foreground,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: muted,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    );
  }
}

class ManagementScreen extends StatelessWidget {
  const ManagementScreen({super.key, required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.transparent,
    body: Aura(
      child: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
                child: _AtelierBackButton(tooltip: 'Retour à $title'),
              ),
            ),
            Expanded(child: child),
          ],
        ),
      ),
    ),
  );
}

/// Animation partagée pour l'entrée douce des écrans et des nouveaux contenus.
class AppEntrance extends StatefulWidget {
  const AppEntrance({super.key, required this.child});
  final Widget child;
  @override
  State<AppEntrance> createState() => _AppEntranceState();
}

class _AppEntranceState extends State<AppEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );
  late final Animation<double> opacity = controller.drive(
    CurveTween(curve: Curves.easeOutCubic),
  );
  late final Animation<Offset> position = controller.drive(
    Tween(
      begin: const Offset(0, .018),
      end: Offset.zero,
    ).chain(CurveTween(curve: Curves.easeOutBack)),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      controller.value = 1;
    } else if (controller.isDismissed) {
      controller.forward();
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: opacity,
    child: SlideTransition(position: position, child: widget.child),
  );
}

class Dashboard extends StatelessWidget {
  const Dashboard({
    super.key,
    required this.products,
    required this.depots,
    required this.operations,
    required this.stock,
  });
  final List<Product> products;
  final List<Depot> depots;
  final List<Operation> operations;
  final int Function(String) stock;
  @override
  Widget build(BuildContext context) => Page(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Glass(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Votre atelier, en un seul regard',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              const Text(
                'Gérez les produits, le stock, les machines et les opérations en cours.',
              ),
              const SizedBox(height: 16),
              Text(
                '${operations.where((op) => op.active).length} opération(s) en cours',
                style: const TextStyle(
                  color: Color(0xFF7E22CE),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          'Stock disponible',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: products
              .map(
                (p) => SizedBox(
                  width: 185,
                  child: Glass(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          productQuantityLabel(p, stock(p.id)),
                          style: const TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
              .toList(),
        ),
      ],
    ),
  );
}

class ProductsPage extends StatefulWidget {
  const ProductsPage({
    super.key,
    required this.products,
    required this.categories,
    this.catalogFamilies = const [],
    required this.stock,
    required this.depots,
    required this.depotStock,
    required this.canEdit,
    required this.onAdd,
    required this.onAddStock,
    required this.onOpenCategories,
  });
  final List<Product> products;
  final List<ProductCategory> categories;
  final List<CatalogFamily> catalogFamilies;
  final int Function(String) stock;
  final List<Depot> depots;
  final int Function(String, String) depotStock;
  final bool canEdit;
  final VoidCallback onAdd;
  final ValueChanged<Product> onAddStock;
  final VoidCallback onOpenCategories;
  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<ProductsPage> {
  final search = TextEditingController();
  String? categoryId;
  var showFilters = false;

  bool get hasFilters => categoryId != null || search.text.trim().isNotEmpty;

  List<Product> get filteredProducts {
    final query = search.text.trim().toLowerCase();
    final allowed = categoryId == null
        ? null
        : widget.categories
              .where((category) => category.id == categoryId)
              .expand((category) => category.productIds)
              .toSet();
    return widget.products.where((product) {
      // Produced dimensions belong below their manufacturing template instead
      // of competing with the normal catalogue.
      return !product.isManufacturedVariant &&
          (query.isEmpty ||
              '${product.name} ${product.displayReference}'
                  .toLowerCase()
                  .contains(query)) &&
          (allowed == null || allowed.contains(product.id));
    }).toList();
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Page(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHero(
          icon: Icons.inventory_2_rounded,
          title: 'Catalogue des produits',
          subtitle:
              '${widget.products.where((product) => !product.isManufacturedVariant).length} produits principaux organisés pour votre atelier.',
        ),
        const SizedBox(height: 16),
        const Text(
          'Gérer le catalogue',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            IconButton.filledTonal(
              onPressed: () => setState(() => showFilters = !showFilters),
              icon: Icon(
                showFilters ? Icons.filter_list_off : Icons.tune_rounded,
              ),
              tooltip: 'Filtres',
            ),
            const Spacer(),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: widget.onOpenCategories,
              icon: const Icon(Icons.category_outlined),
              label: const Text('Familles'),
            ),
            if (widget.canEdit)
              IconButton.filled(
                onPressed: widget.onAdd,
                icon: const Icon(Icons.add),
                tooltip: 'Ajouter un produit',
              ),
          ],
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          child: showFilters
              ? Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Glass(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      children: [
                        TextField(
                          controller: search,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            labelText: 'Filtrer par nom de produit',
                            prefixIcon: Icon(Icons.search_rounded),
                          ),
                        ),
                        const SizedBox(height: 10),
                        LiquidSelectFormField<String>(
                          initialValue: categoryId,
                          decoration: const InputDecoration(
                            labelText: 'Filtrer par catégorie',
                            prefixIcon: Icon(Icons.category_outlined),
                          ),
                          items: [
                            const DropdownMenuItem<String>(
                              value: null,
                              child: Text('Toutes les catégories'),
                            ),
                            ...widget.categories.map(
                              (category) => DropdownMenuItem(
                                value: category.id,
                                child: Text(category.name),
                              ),
                            ),
                          ],
                          onChanged: (value) =>
                              setState(() => categoryId = value),
                        ),
                      ],
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
        const SizedBox(height: 16),
        if (widget.products.isEmpty && widget.categories.isEmpty)
          const Empty(
            icon: Icons.photo_library_outlined,
            title: 'Aucun produit',
            detail: 'Ajoutez votre premier produit.',
          )
        else if (filteredProducts.isEmpty && hasFilters)
          const Empty(
            icon: Icons.search_off_rounded,
            title: 'Aucun résultat',
            detail: 'Modifiez le nom ou la catégorie sélectionnée.',
          )
        else
          CatalogProductBrowser(
            key: ValueKey((categoryId, search.text.trim().toLowerCase())),
            products: filteredProducts,
            categories: widget.categories,
            catalogFamilies: widget.catalogFamilies,
            showEmptyCategories: !hasFilters,
            buildProducts: (products) => LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 400;
                const spacing = 12.0;
                final cardWidth = compact
                    ? (constraints.maxWidth - spacing) / 2
                    : 180.0;
                return Wrap(
                  spacing: compact ? spacing : 14,
                  runSpacing: compact ? spacing : 14,
                  children: products
                      .map(
                        (product) => SizedBox(
                          width: cardWidth,
                          child: ProductCard(
                            product: product,
                            onTap: () => Navigator.of(context).push(
                              PageRouteBuilder<void>(
                                pageBuilder:
                                    (context, animation, secondaryAnimation) =>
                                        ProductDetailsPage(
                                          product: product,
                                          stockPieces: widget.stock(product.id),
                                          allProducts: widget.products,
                                          stock: widget.stock,
                                          categories: widget.categories,
                                          depots: widget.depots,
                                          depotStock: widget.depotStock,
                                          canEdit: widget.canEdit,
                                          onAddStock: widget.onAddStock,
                                        ),
                                transitionsBuilder:
                                    (
                                      context,
                                      animation,
                                      secondaryAnimation,
                                      child,
                                    ) => FadeTransition(
                                      opacity: animation,
                                      child: ScaleTransition(
                                        scale: Tween<double>(begin: .92, end: 1)
                                            .animate(
                                              CurvedAnimation(
                                                parent: animation,
                                                curve: Curves.easeOutCubic,
                                              ),
                                            ),
                                        child: child,
                                      ),
                                    ),
                              ),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                );
              },
            ),
          ),
      ],
    ),
  );
}

class ProductCard extends StatelessWidget {
  const ProductCard({super.key, required this.product, required this.onTap});
  final Product product;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(28),
    child: Glass(
      padding: const EdgeInsets.all(10),
      child: AspectRatio(
        aspectRatio: .92,
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: Hero(
                  tag: 'product-image-${product.id}',
                  child: ProductImage(
                    product: product,
                    height: 124,
                    circular: true,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              product.displayReference,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 3),
            Text(
              productSpecification(product),
              style: TextStyle(color: _atelierMuted(context), fontSize: 12),
            ),
          ],
        ),
      ),
    ),
  );
}

class ProductImage extends StatelessWidget {
  const ProductImage({
    super.key,
    required this.product,
    required this.height,
    this.circular = false,
  });
  final Product product;
  final double height;
  final bool circular;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final image = SizedBox(
      height: height,
      width: circular ? height : double.infinity,
      child: product.image == null
          ? DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [scheme.primaryContainer, scheme.surface],
                ),
              ),
              child: Icon(
                Icons.layers_rounded,
                color: scheme.primary,
                size: 44,
              ),
            )
          : Image.memory(product.image!, fit: BoxFit.cover),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(circular ? height / 2 : 16),
      child: image,
    );
  }
}

class CategoryImage extends StatelessWidget {
  const CategoryImage({super.key, required this.category, required this.size});
  final ProductCategory category;
  final double size;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(14),
    child: SizedBox(
      width: size,
      height: size,
      child: category.image.isEmpty
          ? _AtelierIcon(Icons.category_rounded, size: size)
          : Image.memory(category.image, fit: BoxFit.cover),
    ),
  );
}

class ProductDetailsPage extends StatelessWidget {
  const ProductDetailsPage({
    super.key,
    required this.product,
    required this.stockPieces,
    required this.allProducts,
    required this.stock,
    required this.categories,
    required this.depots,
    required this.depotStock,
    required this.canEdit,
    required this.onAddStock,
  });
  final Product product;
  final int stockPieces;
  final List<Product> allProducts;
  final int Function(String) stock;
  final List<ProductCategory> categories;
  final List<Depot> depots;
  final int Function(String, String) depotStock;
  final bool canEdit;
  final ValueChanged<Product> onAddStock;

  @override
  Widget build(BuildContext context) {
    final derivedProducts = allProducts
        .where((item) => item.parentProductId == product.id)
        .toList();
    // A template represents the sum of the sizes manufactured from it. Its
    // own row is only a recipe, so it must not inflate the displayed total.
    final displayedStock = derivedProducts.isEmpty
        ? stockPieces
        : derivedProducts.fold<int>(0, (total, item) => total + stock(item.id));
    final stockMeters = derivedProducts.isEmpty
        ? displayedStock * product.lengthMeters
        : derivedProducts.fold<double>(
            0,
            (total, item) => total + stock(item.id) * item.lengthMeters,
          );
    final stockKilograms = derivedProducts.isEmpty
        ? displayedStock * product.kilogramsPerPiece
        : derivedProducts.fold<double>(
            0,
            (total, item) => total + stock(item.id) * item.kilogramsPerPiece,
          );

    void openProduct(Product item) => Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProductDetailsPage(
          product: item,
          stockPieces: stock(item.id),
          allProducts: allProducts,
          stock: stock,
          categories: categories,
          depots: depots,
          depotStock: depotStock,
          canEdit: canEdit,
          onAddStock: onAddStock,
        ),
      ),
    );
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Aura(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 12, 18, 8),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        product.name,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 42),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 620),
                      child: Glass(
                        padding: const EdgeInsets.all(22),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Center(
                              child: Hero(
                                tag: 'product-image-${product.id}',
                                child: ProductImage(
                                  product: product,
                                  height: 190,
                                  circular: true,
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              product.name,
                              style: const TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              product.kind.label,
                              style: TextStyle(color: _atelierMuted(context)),
                            ),
                            if (product.reference.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              _InfoRow(
                                icon: Icons.tag_rounded,
                                label: 'Référence',
                                value: product.reference,
                              ),
                            ],
                            const SizedBox(height: 10),
                            if (!product.isDiameterBased && !product.isHose)
                              _InfoRow(
                                icon: Icons.science_outlined,
                                label: 'Matière',
                                value:
                                    '${product.material.label} · ${formatNumber(product.material.density)} kg/m³',
                              ),
                            const SizedBox(height: 20),
                            if (product.isDiameterBased) ...[
                              _InfoRow(
                                icon: Icons.architecture_outlined,
                                label: product.diameterIsExternal
                                    ? 'Diamètre extérieur saisi'
                                    : 'Diamètre intérieur saisi',
                                value:
                                    'Ø ${formatNumber(product.displayedDiameter ?? 0)} ${product.displayedDiameterUnit}',
                              ),
                              _InfoRow(
                                icon: Icons.open_in_full_rounded,
                                label: 'Diamètre extérieur',
                                value:
                                    'Ø ${formatNumber(product.outsideDiameter ?? 0)} cm',
                              ),
                              _InfoRow(
                                icon: Icons.close_fullscreen_rounded,
                                label: 'Diamètre intérieur',
                                value:
                                    'Ø ${formatNumber(product.insideDiameter ?? 0)} cm',
                              ),
                              _InfoRow(
                                icon: Icons.layers_outlined,
                                label: 'Épaisseur',
                                value: '${formatNumber(product.thickness)} mm',
                              ),
                            ] else if (product.isHose)
                              const _InfoRow(
                                icon: Icons.water_drop_outlined,
                                label: 'Unité de vente',
                                value: 'Mètre',
                              )
                            else ...[
                              _InfoRow(
                                icon: Icons.straighten_rounded,
                                label: 'Largeur',
                                value:
                                    '${formatNumber(product.lengthInChosenUnit)} ${product.lengthUnit.label} (${formatNumber(product.lengthMeters)} m)',
                              ),
                              _InfoRow(
                                icon: Icons.layers_outlined,
                                label: 'Épaisseur',
                                value: '${formatNumber(product.thickness)} mm',
                              ),
                              _InfoRow(
                                icon: Icons.close_fullscreen_rounded,
                                label: 'Diamètre intérieur calculé',
                                value:
                                    'Ø ${formatNumber(product.insideDiameter ?? 0)} cm',
                              ),
                              _InfoRow(
                                icon: Icons.open_in_full_rounded,
                                label: 'Diamètre extérieur calculé',
                                value:
                                    'Ø ${formatNumber(product.outsideDiameter ?? 0)} cm',
                              ),
                              _InfoRow(
                                icon: Icons.view_week_outlined,
                                label: 'Longueur',
                                value: '${formatNumber(product.width)} m',
                              ),
                            ],
                            const Divider(height: 28),
                            const Text(
                              'Stock disponible',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 10),
                            _InfoRow(
                              icon: Icons.inventory_2_outlined,
                              label: 'Quantité',
                              value: productQuantityLabel(
                                product,
                                displayedStock,
                              ),
                            ),
                            if (!product.isDiameterBased) ...[
                              _InfoRow(
                                icon: Icons.route_outlined,
                                label: 'Longueur totale',
                                value: '${formatNumber(stockMeters)} m',
                              ),
                              if (!product.isHose)
                                _InfoRow(
                                  icon: Icons.scale_outlined,
                                  label: 'Poids estimé',
                                  value: formatWeight(stockKilograms),
                                ),
                            ],
                            const SizedBox(height: 14),
                            const Text(
                              'Répartition par dépôt',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 8),
                            ...depots.map((depot) {
                              final pieces = derivedProducts.isEmpty
                                  ? depotStock(product.id, depot.id)
                                  : derivedProducts.fold<int>(
                                      0,
                                      (total, item) =>
                                          total + depotStock(item.id, depot.id),
                                    );
                              return _InfoRow(
                                icon: Icons.warehouse_outlined,
                                label: depot.name,
                                value: productQuantityLabel(product, pieces),
                              );
                            }),
                            if (derivedProducts.isNotEmpty) ...[
                              const SizedBox(height: 22),
                              Text(
                                'Produits dérivés (${derivedProducts.length})',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Ces dimensions ne figurent pas dans la liste générale. Leur stock est inclus dans le total ci-dessus.',
                                style: TextStyle(
                                  color: _atelierMuted(context),
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 10),
                              ...derivedProducts.map(
                                (item) => Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: _DerivedProductTile(
                                    product: item,
                                    pieces: stock(item.id),
                                    onTap: () => openProduct(item),
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 18),
                            if (canEdit)
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  onPressed: product.manufactured
                                      ? null
                                      : () {
                                          Navigator.pop(context);
                                          onAddStock(product);
                                        },
                                  icon: const Icon(Icons.add_box_outlined),
                                  label: Text(
                                    product.manufactured
                                        ? 'Ajout automatique par production'
                                        : 'Ajouter au stock',
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DerivedProductTile extends StatelessWidget {
  const _DerivedProductTile({
    required this.product,
    required this.pieces,
    required this.onTap,
  });
  final Product product;
  final int pieces;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Theme.of(context).colorScheme.outline),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 46,
                height: 46,
                child: ProductImage(product: product, height: 46),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                product.displayReference,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              productQuantityLabel(product, pieces),
              style: const TextStyle(
                color: Color(0xFF15803D),
                fontWeight: FontWeight.w900,
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: _atelierMuted(context)),
          ],
        ),
      ),
    ),
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      children: [
        Icon(icon, color: const Color(0xFF7E22CE)),
        const SizedBox(width: 10),
        Expanded(child: Text(label)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
      ],
    ),
  );
}

class StockAddition {
  const StockAddition({
    this.id,
    required this.productId,
    required this.depotId,
    required this.pieces,
    required this.receiptNumber,
    required this.quantity,
    required this.unit,
    required this.images,
    this.supplierId,
    this.returnOfPurchaseId,
    required this.addedAt,
    this.draft = true,
    this.transportCharge = TransportCharge.none,
    this.payments = const [],
  });
  final int? id;
  final String productId;
  final String depotId;
  final int pieces;
  final String receiptNumber;
  final String? supplierId;

  /// Set only for a supplier return. Its quantity is stored as a negative
  /// stock movement and is still validated through the normal workflow.
  final int? returnOfPurchaseId;
  final double quantity;
  final InventoryUnit unit;
  final List<Uint8List> images;
  final DateTime addedAt;
  final bool draft;
  final TransportCharge transportCharge;
  final List<PaymentAllocation> payments;
}

class AnalyticsPage extends StatelessWidget {
  const AnalyticsPage({
    super.key,
    required this.products,
    required this.operations,
    required this.sales,
    required this.purchases,
    required this.stock,
  });

  final List<Product> products;
  final List<Operation> operations;
  final List<Sale> sales;
  final List<StockAddition> purchases;
  final int Function(String) stock;

  @override
  Widget build(BuildContext context) {
    final totalPieces = products.fold<int>(
      0,
      (total, product) => total + stock(product.id),
    );
    final available = products.where((product) => stock(product.id) > 0).length;
    final activeOperations = operations
        .where((operation) => operation.active)
        .length;
    final produced = operations
        .where((operation) => !operation.active && !operation.completionDraft)
        .fold<int>(
          0,
          (total, operation) => total + (operation.outputPieces ?? 0),
        );
    final sold = sales
        .where((sale) => !sale.draft)
        .fold<int>(0, (total, sale) => total + sale.pieces);
    final topProducts = [...products]
      ..sort((a, b) => stock(b.id).compareTo(stock(a.id)));

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Aura(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 22, 16),
                child: Row(
                  children: [
                    const _AtelierBackButton(),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Analyses',
                        style: TextStyle(
                          color: _atelierForeground(context),
                          fontSize: 23,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Page(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Glass(
                        radius: 28,
                        padding: const EdgeInsets.all(20),
                        accent: AppPalette.secondary,
                        frosted: true,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                _AtelierIcon(
                                  Icons.insights_rounded,
                                  color: Theme.of(context).colorScheme.secondary,
                                ),
                                const Spacer(),
                                Text(
                                  '$available produits disponibles',
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.secondary,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            Text(
                              'Vue d’ensemble de l’atelier',
                              style: TextStyle(
                                color: _atelierForeground(context),
                                fontSize: 23,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              '$totalPieces unités actuellement suivies dans le stock.',
                              style: TextStyle(color: _atelierMuted(context)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          const spacing = 12.0;
                          final metricWidth =
                              (constraints.maxWidth - spacing) / 2;
                          return Wrap(
                            spacing: spacing,
                            runSpacing: spacing,
                            children: [
                              _AnalyticsMetric(
                                width: metricWidth,
                                icon: Icons.inventory_2_rounded,
                                value: '$totalPieces',
                                label: 'Unités en stock',
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              _AnalyticsMetric(
                                width: metricWidth,
                                icon: Icons.precision_manufacturing_rounded,
                                value: '$produced',
                                label: 'Unités produites',
                                color: AppPalette.mint,
                              ),
                              _AnalyticsMetric(
                                width: metricWidth,
                                icon: Icons.point_of_sale_rounded,
                                value: '$sold',
                                label: 'Unités vendues',
                                color: AppPalette.coral,
                              ),
                              _AnalyticsMetric(
                                width: metricWidth,
                                icon: Icons.play_circle_outline_rounded,
                                value: '$activeOperations',
                                label: 'Opérations en cours',
                                color: Theme.of(context).colorScheme.secondary,
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 22),
                      _PurchaseSaleChart(purchases: purchases, sales: sales),
                      const SizedBox(height: 22),
                      const Text(
                        'Produits les plus disponibles',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (topProducts.isEmpty)
                        const Empty(
                          icon: Icons.bar_chart_rounded,
                          title: 'Pas encore de données',
                          detail: 'Ajoutez des produits et du stock pour voir les analyses.',
                        )
                      else
                        Glass(
                          child: Column(
                            children: topProducts.take(5).map((product) {
                              final quantity = stock(product.id);
                              return ListTile(
                                leading: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: SizedBox(
                                    width: 42,
                                    height: 42,
                                    child: ProductImage(
                                      product: product,
                                      height: 42,
                                    ),
                                  ),
                                ),
                                title: Text(
                                  product.displayReference,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                subtitle: Text(product.kind.label),
                                trailing: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 7,
                                  ),
                                  decoration: BoxDecoration(
                                    color: (quantity > 0
                                            ? AppPalette.mint
                                            : AppPalette.coral)
                                        .withValues(alpha: .16),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Text(
                                    productQuantityLabel(product, quantity),
                                    style: TextStyle(
                                      color: quantity > 0
                                          ? _atelierSuccess(context)
                                          : Theme.of(context).colorScheme.error,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PurchaseSaleChart extends StatelessWidget {
  const _PurchaseSaleChart({required this.purchases, required this.sales});

  final List<StockAddition> purchases;
  final List<Sale> sales;

  static const _monthLabels = [
    'Jan',
    'Fév',
    'Mar',
    'Avr',
    'Mai',
    'Juin',
    'Juil',
    'Août',
    'Sep',
    'Oct',
    'Nov',
    'Déc',
  ];

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final scheme = Theme.of(context).colorScheme;
    final months = List.generate(
      6,
      (index) => DateTime(today.year, today.month - 5 + index),
    );
    final purchaseValues = months
        .map(
          (month) => purchases
              .where(
                (item) =>
                    !item.draft &&
                    item.addedAt.year == month.year &&
                    item.addedAt.month == month.month,
              )
              .fold<int>(0, (total, item) => total + item.pieces),
        )
        .toList();
    final saleValues = months
        .map(
          (month) => sales
              .where(
                (item) =>
                    !item.draft &&
                    item.createdAt.year == month.year &&
                    item.createdAt.month == month.month,
              )
              .fold<int>(0, (total, item) => total + item.pieces),
        )
        .toList();
    final purchasesTotal = purchaseValues.fold<int>(
      0,
      (total, value) => total + value,
    );
    final salesTotal = saleValues.fold<int>(0, (total, value) => total + value);

    return Glass(
      padding: const EdgeInsets.fromLTRB(15, 15, 15, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Achats et ventes',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 3),
          Text(
            'Comparaison mensuelle des unités validées — 6 derniers mois.',
            style: TextStyle(color: _atelierMuted(context), fontSize: 12),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _ChartLegend(
                color: const Color(0xFFFF5F7E),
                label: 'Achats · $purchasesTotal unités',
              ),
              _ChartLegend(
                color: const Color(0xFF25A97D),
                label: 'Ventes · $salesTotal unités',
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (purchasesTotal == 0 && salesTotal == 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'Aucun achat ou vente validé sur cette période',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ),
            )
          else
            SizedBox(
              height: 210,
              width: double.infinity,
              child: CustomPaint(
                painter: _PurchaseSalePainter(
                  purchaseValues: purchaseValues,
                  saleValues: saleValues,
                  labelStyle: DefaultTextStyle.of(context).style.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                  gridColor: scheme.outline.withValues(alpha: .32),
                  labels: months
                      .map((month) => _monthLabels[month.month - 1])
                      .toList(),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ChartLegend extends StatelessWidget {
  const _ChartLegend({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 6),
      Text(
        label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
      ),
    ],
  );
}

class _PurchaseSalePainter extends CustomPainter {
  const _PurchaseSalePainter({
    required this.purchaseValues,
    required this.saleValues,
    required this.labels,
    required this.labelStyle,
    required this.gridColor,
  });

  final List<int> purchaseValues;
  final List<int> saleValues;
  final List<String> labels;
  final TextStyle labelStyle;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 7.0;
    const right = 7.0;
    const top = 10.0;
    const bottom = 28.0;
    final chartHeight = size.height - top - bottom;
    final baseline = size.height - bottom;
    final count = labels.length;
    final width = size.width - left - right;
    var highest = 0;
    for (final value in [...purchaseValues, ...saleValues]) {
      if (value > highest) highest = value;
    }
    final scale = highest == 0 ? 1.0 : highest.toDouble();

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var step = 0; step <= 4; step++) {
      final y = top + chartHeight * step / 4;
      canvas.drawLine(
        Offset(left, y),
        Offset(size.width - right, y),
        gridPaint,
      );
    }
    if (highest > 0) {
      _drawSeries(
        canvas: canvas,
        values: purchaseValues,
        color: const Color(0xFFFF5F7E),
        left: left,
        width: width,
        baseline: baseline,
        chartHeight: chartHeight,
        scale: scale,
      );
      _drawSeries(
        canvas: canvas,
        values: saleValues,
        color: const Color(0xFF25A97D),
        left: left,
        width: width,
        baseline: baseline,
        chartHeight: chartHeight,
        scale: scale,
      );
    }
    for (var index = 0; index < count; index++) {
      final x = count == 1
          ? size.width / 2
          : left + width * index / (count - 1);
      final text = TextPainter(
        text: TextSpan(
          text: labels[index],
          style: labelStyle,
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final textX = (x - text.width / 2)
          .clamp(0.0, max(0.0, size.width - text.width))
          .toDouble();
      text.paint(canvas, Offset(textX, baseline + 9));
      text.dispose();
    }
  }

  void _drawSeries({
    required Canvas canvas,
    required List<int> values,
    required Color color,
    required double left,
    required double width,
    required double baseline,
    required double chartHeight,
    required double scale,
  }) {
    Offset pointAt(int index) => Offset(
      values.length == 1
          ? left + width / 2
          : left + width * index / (values.length - 1),
      baseline - values[index] / scale * chartHeight,
    );
    final points = List.generate(values.length, pointAt);
    final area = Path()
      ..moveTo(points.first.dx, baseline)
      ..lineTo(points.first.dx, points.first.dy);
    final line = Path()..moveTo(points.first.dx, points.first.dy);
    for (var index = 1; index < points.length; index++) {
      final previous = points[index - 1];
      final current = points[index];
      final middleX = (previous.dx + current.dx) / 2;
      line.quadraticBezierTo(
        previous.dx,
        previous.dy,
        middleX,
        (previous.dy + current.dy) / 2,
      );
      area.quadraticBezierTo(
        previous.dx,
        previous.dy,
        middleX,
        (previous.dy + current.dy) / 2,
      );
    }
    line.lineTo(points.last.dx, points.last.dy);
    area
      ..lineTo(points.last.dx, points.last.dy)
      ..lineTo(points.last.dx, baseline)
      ..close();
    canvas.drawPath(area, Paint()..color = color.withValues(alpha: .16));
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    final dotPaint = Paint()..color = color;
    for (final point in points) {
      canvas.drawCircle(point, 4.5, Paint()..color = Colors.white);
      canvas.drawCircle(point, 3, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _PurchaseSalePainter oldDelegate) =>
      oldDelegate.purchaseValues != purchaseValues ||
      oldDelegate.saleValues != saleValues ||
      oldDelegate.labels != labels ||
      oldDelegate.labelStyle != labelStyle ||
      oldDelegate.gridColor != gridColor;
}

class _AnalyticsMetric extends StatelessWidget {
  const _AnalyticsMetric({
    required this.width,
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  final double width;
  final IconData icon;
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Glass(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: .14),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(height: 14),
          Text(
            value,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(color: _atelierMuted(context), fontSize: 12),
          ),
        ],
      ),
    ),
  );
}

class StockPage extends StatelessWidget {
  const StockPage({
    super.key,
    required this.products,
    required this.categories,
    this.catalogFamilies = const [],
    required this.stock,
    required this.draftCount,
    required this.canEdit,
    required this.onPurchase,
    required this.onSale,
    required this.onOpenDepots,
    required this.onOpenRecords,
    required this.onOpenPayments,
  });
  final List<Product> products;
  final List<ProductCategory> categories;
  final List<CatalogFamily> catalogFamilies;
  final int Function(String) stock;
  final int draftCount;
  final bool canEdit;
  final VoidCallback onPurchase;
  final VoidCallback onSale;
  final VoidCallback onOpenDepots;
  final VoidCallback onOpenRecords;
  final VoidCallback onOpenPayments;
  @override
  Widget build(BuildContext context) {
    final muted = _atelierMuted(context);
    final availableProducts = products
        .where((product) => stock(product.id) > 0)
        .length;
    final totalPieces = products.fold<int>(
      0,
      (total, product) => total + stock(product.id),
    );

    return Page(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Glass(
            padding: const EdgeInsets.all(18),
            radius: 28,
            accent: AppPalette.primary,
            frosted: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const _AtelierIcon(Icons.inventory_2_outlined, size: 42),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Inventaire',
                            style: TextStyle(
                              fontSize: 23,
                              letterSpacing: -.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            '$availableProducts disponibles sur ${products.length}',
                            style: TextStyle(color: muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 17),
                const Divider(height: 1),
                const SizedBox(height: 14),
                Row(
                  children: [
                    _StockMetric(
                      value: '$totalPieces',
                      label: 'Unités en stock',
                    ),
                    _StockMetric(value: '$draftCount', label: 'En attente'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (canEdit) ...[
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                'Actions rapides',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _StockActionButton(
                    icon: Icons.add_shopping_cart_rounded,
                    title: 'Nouvel achat',
                    subtitle: 'Entrée de stock',
                    accent: AppPalette.primary,
                    onTap: onPurchase,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StockActionButton(
                    icon: Icons.point_of_sale_rounded,
                    title: 'Nouvelle vente',
                    subtitle: 'Sortie de stock',
                    accent: AppPalette.secondary,
                    onTap: onSale,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
          ],
          Row(
            children: [
              Expanded(
                child: _StockSecondaryAction(
                  icon: Icons.warehouse_rounded,
                  label: 'Dépôts',
                  color: AppPalette.mint,
                  onTap: onOpenDepots,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StockSecondaryAction(
                  icon: Icons.receipt_long_rounded,
                  label: 'Registres',
                  color: Theme.of(context).colorScheme.secondary,
                  onTap: onOpenRecords,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _StockSecondaryAction(
            icon: Icons.account_balance_wallet_rounded,
            label: 'Paiements',
            color: Theme.of(context).colorScheme.primary,
            onTap: onOpenPayments,
          ),
          if (draftCount > 0) ...[
            const SizedBox(height: 14),
            Glass(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      color: Color(0xFF3A3215),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.edit_note_rounded,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      '$draftCount brouillon(s) attendent votre validation.',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'Disponibilité des produits',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(height: 10),
          CatalogProductBrowser(
            products: products,
            categories: categories,
            catalogFamilies: catalogFamilies,
            buildProducts: (items) => Column(
              children: [
                for (final product in items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _StockProductTile(
                      product: product,
                      pieces: stock(product.id),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class TransactionPaymentsPage extends StatefulWidget {
  const TransactionPaymentsPage({
    super.key,
    required this.payments,
    required this.sales,
    required this.purchases,
    required this.products,
    required this.clients,
    required this.suppliers,
    required this.competitors,
    required this.depotName,
    this.onOpenAttachments,
  });
  final OpenTransactionPhotos? onOpenAttachments;
  final List<TransactionPayment> payments;
  final List<Sale> sales;
  final List<StockAddition> purchases;
  final List<Product> products;
  final List<Client> clients;
  final List<Supplier> suppliers;
  final List<Competitor> competitors;
  final String Function(String id) depotName;

  @override
  State<TransactionPaymentsPage> createState() =>
      _TransactionPaymentsPageState();
}

class _TransactionPaymentsPageState extends State<TransactionPaymentsPage> {
  PaymentSource? selectedSource;
  var showSales = true;

  double totalFor(PaymentSource source) => widget.payments
      .where((payment) => payment.source == source)
      .fold(0, (total, payment) => total + payment.amount);

  Sale? saleFor(String? id) {
    for (final sale in widget.sales) {
      if (sale.id == id) return sale;
    }
    return null;
  }

  StockAddition? purchaseFor(int? id) {
    for (final purchase in widget.purchases) {
      if (purchase.id == id) return purchase;
    }
    return null;
  }

  Product? productFor(String id) {
    for (final product in widget.products) {
      if (product.id == id) return product;
    }
    return null;
  }

  String clientName(String id) {
    for (final client in widget.clients) {
      if (client.id == id) {
        return client.company.isEmpty ? client.name : client.company;
      }
    }
    return 'Client inconnu';
  }

  String supplierName(String? id) {
    for (final supplier in widget.suppliers) {
      if (supplier.id == id) {
        return supplier.company.isEmpty ? supplier.name : supplier.company;
      }
    }
    return 'Fournisseur inconnu';
  }

  String competitorName(String? id) {
    for (final competitor in widget.competitors) {
      if (competitor.id == id) return competitor.name;
    }
    return 'Compétiteur';
  }

  void showDetails(TransactionPayment payment) {
    final sale = saleFor(payment.saleId);
    final purchase = purchaseFor(payment.stockAdditionId);
    final bool isSale;
    final String productId;
    final String partner;
    final String depotId;
    final double quantity;
    final InventoryUnit unit;
    final TransportCharge transport;
    final DateTime date;
    final bool draft;
    final String? receiptNumber;
    if (sale != null) {
      isSale = true;
      productId = sale.productId;
      partner = clientName(sale.clientId);
      depotId = sale.depotId;
      quantity = sale.quantity;
      unit = sale.unit;
      transport = sale.transportCharge;
      date = sale.createdAt;
      draft = sale.draft;
      receiptNumber = null;
    } else if (purchase != null) {
      isSale = false;
      productId = purchase.productId;
      partner = supplierName(purchase.supplierId);
      depotId = purchase.depotId;
      quantity = purchase.quantity;
      unit = purchase.unit;
      transport = purchase.transportCharge;
      date = purchase.addedAt;
      draft = purchase.draft;
      receiptNumber = purchase.receiptNumber;
    } else {
      return;
    }
    final product = productFor(productId);
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isSale ? 'Détails de la vente' : 'Détails de l’achat'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PaymentDetail(
                label: 'Produit',
                value: product?.displayReference ?? 'Produit supprimé',
              ),
              _PaymentDetail(
                label: isSale ? 'Client' : 'Fournisseur',
                value: partner,
              ),
              _PaymentDetail(label: 'Dépôt', value: widget.depotName(depotId)),
              _PaymentDetail(
                label: 'Quantité',
                value: formatQuantity(quantity, unit),
              ),
              _PaymentDetail(label: 'Transport', value: transport.label),
              _PaymentDetail(
                label: 'Date de l’opération',
                value: dateText(date),
              ),
              _PaymentDetail(
                label: 'Statut',
                value: draft ? 'Brouillon à valider' : 'Validé',
              ),
              if (!isSale)
                _PaymentDetail(
                  label: 'N° de bon',
                  value: receiptNumber == null || receiptNumber.isEmpty
                      ? 'Non renseigné'
                      : receiptNumber,
                ),
              if (widget.onOpenAttachments case final open?)
                OutlinedButton.icon(
                  onPressed: () => open(
                    context,
                    isSale,
                    sale?.id ?? purchase?.id?.toString(),
                    sale?.images ?? purchase?.images ?? const [],
                  ),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Photos jointes'),
                ),
              _PaymentDetail(
                label: 'Source de paiement',
                value: payment.source.label,
              ),
              if (payment.source == PaymentSource.competitor)
                _PaymentDetail(
                  label: 'Compétiteur',
                  value: competitorName(payment.competitorId),
                ),
              _PaymentDetail(label: 'Mode de paiement', value: payment.mode),
              _PaymentDetail(
                label: 'Montant',
                value: '${formatNumber(payment.amount)} DH',
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = selectedSource == null
        ? const <TransactionPayment>[]
        : widget.payments
              .where(
                (payment) =>
                    payment.source == selectedSource &&
                    (showSales
                        ? payment.saleId != null
                        : payment.stockAdditionId != null),
              )
              .toList();
    return FormShell(
      title: selectedSource == null ? 'Paiements' : selectedSource!.label,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (selectedSource == null) ...[
            Text(
              'Montants enregistrés par source de paiement.',
              style: TextStyle(color: _atelierMuted(context)),
            ),
            const SizedBox(height: 16),
            ...PaymentSource.values.map(
              (source) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _PaymentSourceCard(
                  source: source,
                  total: totalFor(source),
                  onTap: () => setState(() => selectedSource = source),
                ),
              ),
            ),
          ] else ...[
            TextButton.icon(
              onPressed: () => setState(() => selectedSource = null),
              icon: const Icon(Icons.arrow_back_rounded),
              label: const Text('Toutes les sources'),
            ),
            const SizedBox(height: 4),
            Glass(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    Icons.account_balance_wallet_rounded,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Total : ${formatNumber(totalFor(selectedSource!))} DH',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: true,
                  icon: Icon(Icons.point_of_sale_rounded),
                  label: Text('Ventes'),
                ),
                ButtonSegment(
                  value: false,
                  icon: Icon(Icons.add_shopping_cart_rounded),
                  label: Text('Achats'),
                ),
              ],
              selected: {showSales},
              onSelectionChanged: (value) =>
                  setState(() => showSales = value.first),
            ),
            const SizedBox(height: 14),
            if (visible.isEmpty)
              const Glass(
                padding: EdgeInsets.all(20),
                child: Center(child: Text('Aucune opération pour ce choix.')),
              )
            else
              ...visible.map((payment) {
                final sale = saleFor(payment.saleId);
                final purchase = purchaseFor(payment.stockAdditionId);
                final productId = sale?.productId ?? purchase?.productId;
                final partner = sale != null
                    ? clientName(sale.clientId)
                    : supplierName(purchase?.supplierId);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => showDetails(payment),
                      child: Glass(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            Icon(
                              sale != null
                                  ? Icons.point_of_sale_rounded
                                  : Icons.add_shopping_cart_rounded,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    productId == null
                                        ? 'Opération supprimée'
                                        : productFor(productId)
                                                  ?.displayReference ??
                                              'Produit',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    '$partner · ${dateText(payment.createdAt)}',
                                    style: TextStyle(
                                      color: _atelierMuted(context),
                                      fontSize: 12,
                                    ),
                                  ),
                                  Text(
                                    payment.mode,
                                    style: TextStyle(
                                      color: _atelierMuted(context),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              '${formatNumber(payment.amount)} DH',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
          ],
        ],
      ),
    );
  }
}

class _PaymentSourceCard extends StatelessWidget {
  const _PaymentSourceCard({
    required this.source,
    required this.total,
    required this.onTap,
  });
  final PaymentSource source;
  final double total;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Glass(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: .14),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.payments_rounded,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                source.label,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            Text(
              '${formatNumber(total)} DH',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, color: _atelierMuted(context)),
          ],
        ),
      ),
    ),
  );
}

class _PaymentDetail extends StatelessWidget {
  const _PaymentDetail({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: _atelierMuted(context), fontSize: 12),
        ),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
      ],
    ),
  );
}

class _StockActionButton extends StatelessWidget {
  const _StockActionButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _LiquidTapTarget(
    radius: 22,
    accent: accent,
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.all(13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AtelierIcon(icon, color: accent, size: 36),
          const SizedBox(height: 12),
          Text(
            title,
            style: TextStyle(
              color: _atelierForeground(context),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            style: TextStyle(color: _atelierMuted(context), fontSize: 11),
          ),
        ],
      ),
    ),
  );
}

class _StockMetric extends StatelessWidget {
  const _StockMetric({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              color: _atelierForeground(context),
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: _atelierMuted(context),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    ),
  );
}

class _StockSecondaryAction extends StatelessWidget {
  const _StockSecondaryAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = scheme.brightness == Brightness.dark &&
            (color == AppPalette.primary || color == AppPalette.secondary)
        ? scheme.primary
        : color;
    return _LiquidTapTarget(
      radius: 20,
      accent: accent,
      onTap: onTap,
      child: SizedBox(
        height: 66,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: .16),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: accent, size: 20),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StockProductTile extends StatelessWidget {
  const _StockProductTile({required this.product, required this.pieces});
  final Product product;
  final int pieces;

  @override
  Widget build(BuildContext context) {
    final isEmpty = pieces <= 0;
    final subtitle = product.isHose
        ? productSpecification(product)
        : product.isDiameterBased
        ? productSpecification(product)
        : '${formatNumber(pieces * product.lengthMeters)} m · ${formatWeight(pieces * product.kilogramsPerPiece)}';

    return Glass(
      padding: const EdgeInsets.all(11),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              width: 58,
              height: 58,
              child: ProductImage(product: product, height: 58),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.displayReference,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: _atelierMuted(context), fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            constraints: const BoxConstraints(maxWidth: 82),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
            decoration: BoxDecoration(
              color: isEmpty
                  ? const Color(0xFFFFEDF0)
                  : const Color(0xFFE8F8F4),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              productQuantityLabel(product, pieces),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isEmpty
                    ? const Color(0xFFD85B74)
                    : const Color(0xFF2A9B83),
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

typedef OpenTransactionPhotos = void Function(
  BuildContext context,
  bool sale,
  String? id,
  List<Uint8List> images,
);

void _showTransactionPhotos(BuildContext context, Future<List<Uint8List>> photos) {
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Photos jointes'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 440),
        child: FutureBuilder<List<Uint8List>>(
          future: photos,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const SizedBox(
                width: 180,
                height: 100,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasError) return const Text('Photos indisponibles.');
            final images = snapshot.data ?? const <Uint8List>[];
            if (images.isEmpty) return const Text('Aucune photo jointe.');
            return SizedBox(
              width: 600,
              height: min(420, MediaQuery.sizeOf(context).height * .52),
              child: ListView.separated(
                itemCount: images.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) => AspectRatio(
                  aspectRatio: 4 / 3,
                  child: InteractiveViewer(
                    child: Image.memory(
                      images[index],
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => const Center(
                        child: Text('Photo illisible.'),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Fermer'),
        ),
      ],
    ),
  );
}

class StockRecordsPage extends StatefulWidget {
  const StockRecordsPage({
    super.key,
    required this.products,
    required this.additions,
    required this.sales,
    required this.transfers,
    required this.depots,
    required this.saleReturns,
    required this.suppliers,
    required this.clients,
    required this.depotName,
    required this.canReturn,
    required this.onReturn,
    required this.canReturnPurchase,
    required this.onReturnPurchase,
    this.onOpenAttachments,
  });

  final List<Product> products;
  final OpenTransactionPhotos? onOpenAttachments;
  final List<StockAddition> additions;
  final List<Sale> sales;
  final List<StockTransfer> transfers;
  final List<Depot> depots;
  final List<SaleReturn> saleReturns;
  final List<Supplier> suppliers;
  final List<Client> clients;
  final String Function(String) depotName;
  final bool canReturn;
  final Future<SaleReturn?> Function(Sale sale, int pieces) onReturn;
  final bool canReturnPurchase;
  final Future<StockAddition?> Function(StockAddition purchase, int pieces)
  onReturnPurchase;

  @override
  State<StockRecordsPage> createState() => _StockRecordsPageState();
}

enum _StockRecordSection { purchases, sales, transfers }

class _StockRecordsPageState extends State<StockRecordsPage> {
  _StockRecordSection section = _StockRecordSection.purchases;
  final activeFilters = <_StockRecordSection>{};
  Set<String> supplierFilter = {};
  Set<String> clientFilter = {};
  String? firstDepot;
  String? secondDepot;
  late List<SaleReturn> saleReturns;
  late List<StockAddition> additions;

  Widget? _recordActions({
    required bool sale,
    required String? id,
    required List<Uint8List> images,
    Widget? returnAction,
  }) {
    final open = widget.onOpenAttachments;
    if (open == null) return returnAction;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Voir les photos jointes',
          onPressed: () => open(context, sale, id, images),
          icon: const Icon(Icons.photo_library_outlined),
        ),
        ?returnAction,
      ],
    );
  }

  Widget recordFilters() => switch (section) {
    _StockRecordSection.purchases => SearchChoiceField(
      label: 'Fournisseurs',
      options: _choices(
        widget.suppliers,
        (item) => item.id,
        (item) => _partnerLabel(item.name, item.company),
      ),
      selected: supplierFilter,
      multiple: true,
      onChanged: (ids) => setState(() => supplierFilter = ids),
    ),
    _StockRecordSection.sales => SearchChoiceField(
      label: 'Clients',
      options: _choices(
        widget.clients,
        (item) => item.id,
        (item) => _partnerLabel(item.name, item.company),
      ),
      selected: clientFilter,
      multiple: true,
      onChanged: (ids) => setState(() => clientFilter = ids),
    ),
    _StockRecordSection.transfers => _TransferDepotFields(
      depots: widget.depots,
      first: firstDepot,
      second: secondDepot,
      onChanged: (first, second) => setState(() {
        firstDepot = first;
        secondDepot = second;
      }),
    ),
  };

  Widget _transferTile(StockTransfer item) {
    final itemProduct = product(item.productId);
    return ListTile(
      leading: const Icon(Icons.swap_horiz),
      title: Text(itemProduct?.displayReference ?? 'Produit'),
      subtitle: Text(
        '${widget.depotName(item.sourceDepotId)} → ${widget.depotName(item.destinationDepotId)}\n'
        '${dateText(item.createdAt)} · ${item.draft ? 'Brouillon' : 'Validé'}',
      ),
      isThreeLine: true,
      trailing: Text(
        itemProduct == null
            ? '${item.pieces} pièces'
            : productQuantityLabel(itemProduct, item.pieces),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    saleReturns = [...widget.saleReturns];
    additions = [...widget.additions];
  }

  Product? product(String id) {
    for (final item in widget.products) {
      if (item.id == id) return item;
    }
    return null;
  }

  Supplier? supplier(String? id) {
    for (final item in widget.suppliers) {
      if (item.id == id) return item;
    }
    return null;
  }

  Client? client(String id) {
    for (final item in widget.clients) {
      if (item.id == id) return item;
    }
    return null;
  }

  String supplierName(String? id) {
    final item = supplier(id);
    if (item == null) return 'Fournisseur non précisé';
    return item.company.isEmpty ? item.name : item.company;
  }

  String clientName(String id) {
    final item = client(id);
    if (item == null) return 'Client introuvable';
    return item.company.isEmpty ? item.name : item.company;
  }

  @override
  Widget build(BuildContext context) {
    final filtering = activeFilters.contains(section);
    final records = switch (section) {
      _StockRecordSection.purchases =>
        additions
            .where(
              (item) =>
                  !filtering ||
                  supplierFilter.isEmpty ||
                  supplierFilter.contains(item.supplierId),
            )
            .map(_purchaseTile)
            .toList(),
      _StockRecordSection.sales =>
        widget.sales
            .where(
              (item) =>
                  !filtering ||
                  clientFilter.isEmpty ||
                  clientFilter.contains(item.clientId),
            )
            .map(_saleTile)
            .toList(),
      _StockRecordSection.transfers =>
        widget.transfers
            .where(
              (item) =>
                  !filtering ||
                  transferMatchesDepots(item, firstDepot, secondDepot),
            )
            .map(_transferTile)
            .toList(),
    };
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Aura(
        child: SafeArea(
          child: Column(
            children: [
              SizedBox(
                height: 122,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 22, 20),
                  child: Row(
                    children: [
                      const _AtelierBackButton(),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Registres du stock',
                              style: TextStyle(
                                fontSize: 21,
                                fontWeight: FontWeight.w900,
                                color: _atelierForeground(context),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Achats, ventes et transferts entre dépôts.',
                              style: TextStyle(color: _atelierMuted(context)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Page(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: SegmentedButton<_StockRecordSection>(
                          segments: const [
                            ButtonSegment(
                              value: _StockRecordSection.purchases,
                              label: Text('Achats'),
                            ),
                            ButtonSegment(
                              value: _StockRecordSection.sales,
                              label: Text('Ventes'),
                            ),
                            ButtonSegment(
                              value: _StockRecordSection.transfers,
                              label: Text('Transferts'),
                            ),
                          ],
                          selected: {section},
                          onSelectionChanged: (selection) =>
                              setState(() => section = selection.first),
                        ),
                      ),
                      CheckboxListTile(
                        value: filtering,
                        title: const Text('Filtrer cette section'),
                        onChanged: (enabled) => setState(() {
                          if (enabled == true) {
                            activeFilters.add(section);
                          } else {
                            activeFilters.remove(section);
                          }
                        }),
                      ),
                      if (filtering) recordFilters(),
                      const SizedBox(height: 12),
                      if (records.isEmpty)
                        const Empty(
                          icon: Icons.receipt_long_outlined,
                          title: 'Aucun enregistrement',
                          detail: 'Les enregistrements correspondant à cette section apparaîtront ici.',
                        )
                      else
                        Glass(child: Column(children: records)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  int returnedPurchasePieces(StockAddition purchase) => additions
      .where((item) => item.returnOfPurchaseId == purchase.id)
      .fold(0, (total, item) => total + item.pieces.abs());

  Future<void> _returnPurchase(StockAddition purchase) async {
    final maximum = purchase.pieces - returnedPurchasePieces(purchase);
    if (maximum <= 0) return;
    final controller = TextEditingController();
    final selectedProduct = product(purchase.productId);
    final pieces = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Retour fournisseur'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Maximum retournable : ${selectedProduct == null ? maximum : productQuantityLabel(selectedProduct, maximum)}.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Quantité retournée *',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              final value = int.tryParse(controller.text);
              if (value == null || value <= 0 || value > maximum) return;
              Navigator.pop(dialogContext, value);
            },
            child: const Text('Envoyer à la validation'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (pieces == null) return;
    final request = await widget.onReturnPurchase(purchase, pieces);
    if (mounted && request != null) {
      setState(() => additions = [request, ...additions]);
    }
  }

  Widget _purchaseTile(StockAddition addition) {
    final isReturn = addition.returnOfPurchaseId != null;
    final returnable =
        !isReturn &&
        !addition.draft &&
        addition.pieces - returnedPurchasePieces(addition) > 0;
    return ListTile(
      leading: Icon(
        isReturn
            ? Icons.assignment_return_outlined
            : Icons.add_circle_outline_rounded,
        color: isReturn ? const Color(0xFFB45309) : const Color(0xFF7E22CE),
      ),
      title: Text(
        isReturn
            ? '-${formatQuantity(addition.quantity.abs(), addition.unit)} retourné au fournisseur'
            : '+${formatQuantity(addition.quantity, addition.unit)} acheté',
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: Text(
        '${product(addition.productId)?.displayReference ?? 'Produit'} · ${widget.depotName(addition.depotId)}\n${supplierName(addition.supplierId)} · ${addition.receiptNumber.isEmpty ? 'Sans n° de bon' : 'Bon n° ${addition.receiptNumber}'} · ${addition.draft ? 'Brouillon à valider' : 'Validé'} · ${addition.addedAt.millisecondsSinceEpoch == 0 ? 'Ajout antérieur' : dateText(addition.addedAt)}',
      ),
      isThreeLine: true,
      trailing: _recordActions(
        sale: false,
        id: addition.id?.toString(),
        images: addition.images,
        returnAction: widget.canReturnPurchase && returnable
          ? IconButton(
              tooltip: 'Retourner au fournisseur',
              onPressed: () => _returnPurchase(addition),
              icon: const Icon(
                Icons.assignment_return_outlined,
                color: Color(0xFFB45309),
              ),
            )
            : null,
      ),
    );
  }

  int returnedPieces(Sale sale) => saleReturns
      .where(
        (item) =>
            item.saleId == sale.id &&
            item.status != ReturnValidationStatus.rejected,
      )
      .fold(0, (total, item) => total + item.pieces);

  Future<void> _returnSale(Sale sale) async {
    final maximum = sale.pieces - returnedPieces(sale);
    if (maximum <= 0) return;
    final controller = TextEditingController();
    final selectedProduct = product(sale.productId);
    final pieces = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Retour client'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Maximum retournable : ${selectedProduct == null ? maximum : productQuantityLabel(selectedProduct, maximum)}.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Quantité retournée *',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              final value = int.tryParse(controller.text);
              if (value == null || value <= 0 || value > maximum) return;
              Navigator.pop(dialogContext, value);
            },
            child: const Text('Envoyer à la validation'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (pieces == null) return;
    final returnRequest = await widget.onReturn(sale, pieces);
    if (mounted && returnRequest != null) {
      setState(() => saleReturns = [returnRequest, ...saleReturns]);
    }
  }

  Widget _saleTile(Sale sale) {
    final approved = saleReturns
        .where(
          (item) =>
              item.saleId == sale.id &&
              item.status == ReturnValidationStatus.approved,
        )
        .fold(0, (total, item) => total + item.pieces);
    final pending = saleReturns
        .where(
          (item) =>
              item.saleId == sale.id &&
              item.status == ReturnValidationStatus.pending,
        )
        .fold(0, (total, item) => total + item.pieces);
    final remaining = sale.pieces - approved - pending;
    final canReturnSale = widget.canReturn && !sale.draft && remaining > 0;
    return ListTile(
      leading: const Icon(
        Icons.remove_circle_outline_rounded,
        color: Color(0xFFB91C1C),
      ),
      title: Text(
        '-${formatQuantity(sale.quantity, sale.unit)} vendu',
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: Text(
        '${product(sale.productId)?.displayReference ?? 'Produit'} · ${widget.depotName(sale.depotId)}\n${clientName(sale.clientId)} · ${dateText(sale.createdAt)}${approved > 0 ? '\nRetour validé : ${product(sale.productId) == null ? approved : productQuantityLabel(product(sale.productId)!, approved)}' : ''}${pending > 0 ? '\nRetour en attente : ${product(sale.productId) == null ? pending : productQuantityLabel(product(sale.productId)!, pending)}' : ''}',
      ),
      isThreeLine: approved > 0 || pending > 0,
      trailing: _recordActions(
        sale: true,
        id: sale.id,
        images: sale.images,
        returnAction: canReturnSale
          ? IconButton(
              tooltip: 'Retourner au stock',
              onPressed: () => _returnSale(sale),
              icon: const Icon(
                Icons.assignment_return_rounded,
                color: Color(0xFF15803D),
              ),
            )
            : null,
      ),
    );
  }
}

class DepotsPage extends StatelessWidget {
  const DepotsPage({
    super.key,
    required this.depots,
    required this.products,
    required this.categories,
    this.catalogFamilies = const [],
    required this.stock,
    required this.canEdit,
    required this.canTransfer,
    required this.onAdd,
    required this.onTransfer,
  });
  final List<Depot> depots;
  final List<Product> products;
  final List<ProductCategory> categories;
  final List<CatalogFamily> catalogFamilies;
  final int Function(String, String) stock;
  final bool canEdit;
  final bool canTransfer;
  final VoidCallback onAdd;
  final VoidCallback onTransfer;

  @override
  Widget build(BuildContext context) => Page(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHero(
          icon: Icons.warehouse_rounded,
          title: 'Dépôts',
          subtitle: 'Consultez les emplacements et le stock disponible.',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (canTransfer)
                IconButton.filledTonal(
                  onPressed: onTransfer,
                  icon: const Icon(Icons.swap_horiz_rounded),
                  tooltip: 'Transférer le stock',
                ),
              if (canTransfer && canEdit) const SizedBox(width: 8),
              if (canEdit)
                IconButton.filled(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add),
                  tooltip: 'Ajouter un dépôt',
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (depots.isEmpty)
          const Empty(
            icon: Icons.warehouse_outlined,
            title: 'Aucun dépôt',
            detail: 'Ajoutez un dépôt avant de répartir le stock.',
          )
        else
          LayoutBuilder(
            builder: (context, constraints) => Wrap(
              spacing: 14,
              runSpacing: 14,
              children: depots.map((depot) {
                final pieces = products.fold(
                  0,
                  (total, product) => total + stock(product.id, depot.id),
                );
                return SizedBox(
                  width: constraints.maxWidth < 540
                      ? constraints.maxWidth
                      : 250,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(24),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => DepotDetailsPage(
                          depot: depot,
                          products: products,
                          categories: categories,
                          catalogFamilies: catalogFamilies,
                          stock: stock,
                        ),
                      ),
                    ),
                    child: Glass(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          DepotImage(depot: depot, size: 62),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  depot.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 17,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '$pieces pièce(s)',
                                  style: TextStyle(
                                    color: _atelierMuted(context),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surfaceContainerHigh,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.chevron_right_rounded,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
      ],
    ),
  );
}

class DepotDetailsPage extends StatelessWidget {
  const DepotDetailsPage({
    super.key,
    required this.depot,
    required this.products,
    required this.categories,
    this.catalogFamilies = const [],
    required this.stock,
  });
  final Depot depot;
  final List<Product> products;
  final List<ProductCategory> categories;
  final List<CatalogFamily> catalogFamilies;
  final int Function(String, String) stock;

  @override
  Widget build(BuildContext context) {
    final stored = products
        .where((product) => stock(product.id, depot.id) != 0)
        .toList();
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Aura(
        child: SafeArea(
          child: Page(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back),
                ),
                Glass(
                  child: Row(
                    children: [
                      DepotImage(depot: depot, size: 82),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          depot.name,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Produits dans ce dépôt',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                if (stored.isEmpty)
                  const Empty(
                    icon: Icons.inventory_2_outlined,
                    title: 'Aucun produit',
                    detail:
                        'Aucun stock n’est actuellement attribué à ce dépôt.',
                  )
                else
                  CatalogProductBrowser(
                    products: stored,
                    categories: categories,
                    catalogFamilies: catalogFamilies,
                    buildProducts: (items) => Glass(
                      child: Column(
                        children: items
                            .map(
                              (product) => ListTile(
                                leading: SizedBox(
                                  width: 48,
                                  child: ProductImage(
                                    product: product,
                                    height: 48,
                                  ),
                                ),
                                title: Text(
                                  product.displayReference,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                subtitle: Text(
                                  '${formatNumber(stock(product.id, depot.id) * product.lengthMeters)} m',
                                ),
                                trailing: Text(
                                  '${stock(product.id, depot.id)} pièces',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class DepotImage extends StatelessWidget {
  const DepotImage({super.key, required this.depot, required this.size});
  final Depot depot;
  final double size;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(14),
    child: SizedBox(
      width: size,
      height: size,
      child: depot.image == null
          ? const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFFDDD6FE), Color(0xFF6B21A8)],
                ),
              ),
              child: Icon(Icons.warehouse_rounded, color: Colors.white),
            )
          : Image.memory(depot.image!, fit: BoxFit.cover),
    ),
  );
}

class MachinesPage extends StatelessWidget {
  const MachinesPage({
    super.key,
    required this.machines,
    required this.operations,
    required this.user,
    required this.userName,
    required this.categoryName,
    required this.productName,
    required this.hasActive,
    required this.onAdd,
    required this.onStart,
    required this.onFinish,
    required this.onManage,
    required this.pendingReviews,
    required this.onOpenReviews,
    this.showReviews = true,
  });
  final List<FactoryMachine> machines;
  final List<Operation> operations;
  final AppUser user;
  final String Function(String) userName;
  final String Function(String) categoryName;
  final String Function(String) productName;
  final bool hasActive;
  final VoidCallback onAdd;
  final void Function(FactoryMachine, MachineUnit) onStart;
  final ValueChanged<Operation> onFinish;
  final ValueChanged<FactoryMachine> onManage;
  final int pendingReviews;
  final VoidCallback onOpenReviews;
  final bool showReviews;
  @override
  Widget build(BuildContext context) => Page(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHero(
          icon: Icons.precision_manufacturing_rounded,
          title: 'Machines',
          subtitle:
              '${machines.where((machine) => !machine.temporary).fold<int>(0, (total, machine) => total + machine.copies)} exemplaire(s) · ${machines.where((machine) => machine.temporary).length} travail(s) externe(s) · ${operations.where((operation) => operation.active).length} opération(s) en cours',
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            const Spacer(),
            if (showReviews)
              Badge(
                isLabelVisible: pendingReviews > 0,
                label: Text('$pendingReviews'),
                child: Tooltip(
                  message: pendingReviews == 0
                      ? 'Contrôles'
                      : '$pendingReviews contrôle(s) à vérifier',
                  child: OutlinedButton.icon(
                    onPressed: onOpenReviews,
                    icon: const Icon(Icons.fact_check_outlined),
                    label: const Text('Contrôles'),
                  ),
                ),
              ),
            if (user.canWritePage(AppPage.machines))
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: FilledButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add),
                  label: const Text('Ajouter'),
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        if (hasActive)
          Glass(
            padding: const EdgeInsets.all(14),
            child: const Row(
              children: [
                Icon(Icons.engineering_rounded, color: Color(0xFF7E22CE)),
                SizedBox(width: 9),
                Expanded(
                  child: Text(
                    'Une opération est en cours. Terminez-la avant d’en démarrer une autre.',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 14),
        if (machines.isEmpty)
          const Empty(
            icon: Icons.precision_manufacturing_outlined,
            title: 'Aucune machine',
            detail: 'Ajoutez une machine et son opérateur responsable.',
          )
        else
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: machines
                .expand(
                  (m) => m.units.map((unit) {
                    final allowed =
                        user.isOperator && m.operatorIds.contains(user.id);
                    return SizedBox(
                      width: 330,
                      child: Glass(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (!m.temporary && (unit.image ?? m.image) != null)
                              ClipRRect(
                                borderRadius: BorderRadius.circular(17),
                                child: Image.memory(
                                  unit.image ?? m.image!,
                                  height: 130,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                ),
                              )
                            else
                              Container(
                                height: 130,
                                width: double.infinity,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: m.temporary
                                      ? Theme.of(context).colorScheme.tertiaryContainer
                                      : Theme.of(context).colorScheme.surfaceContainerHigh,
                                  borderRadius: BorderRadius.circular(17),
                                ),
                                child: Icon(
                                  m.temporary ? Icons.local_shipping_outlined : Icons.precision_manufacturing_outlined,
                                  size: 48,
                                  color: m.temporary
                                      ? Theme.of(context).colorScheme.onTertiaryContainer
                                      : Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            const SizedBox(height: 10),
                            Text(
                              m.temporary
                                  ? '${m.name} · travail externe'
                                  : '${m.name} · exemplaire n°${unit.number}',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            Text(
                              m.temporary
                                  ? 'Fin prévue : ${m.deadline == null ? 'non définie' : dateText(m.deadline!)} · ${m.type == MachineType.roulage ? 'Roulage' : 'Standard'}'
                                  : 'Exemplaire ${unit.usable ? 'disponible' : 'indisponible'} · ${m.type == MachineType.roulage ? 'Roulage' : 'Standard'}',
                              style: TextStyle(color: _atelierMuted(context)),
                            ),
                            Text(
                              'Catégorie : ${categoryName(m.categoryId)}',
                              style: TextStyle(color: _atelierMuted(context)),
                            ),
                            Text(
                              'Produit fabriqué : ${productName(m.outputId)}',
                              style: TextStyle(
                                color: _atelierSuccess(context),
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 8),
                            if (m.temporary) ...[
                              Text(
                                'Matière envoyée : ${productName(m.temporaryInputProductId ?? '')} · ${m.temporaryInputPieces ?? 0} pièce(s)',
                                maxLines: 2,
                              ),
                              Text(
                                'Quantité attendue : ${m.plannedPieces ?? 0}${m.hopperPieces == null ? ' pièces' : ' cadous · ${m.hopperPieces} tôle(s)/cadous'}',
                                maxLines: 2,
                              ),
                            ] else
                              Text(
                                'Responsable : ${m.operatorIds.map(userName).join(', ')}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            const SizedBox(height: 12),
                            if (m.temporary)
                              const Text(
                                'À la validation : matière déduite et production ajoutée au stock.',
                                style: TextStyle(
                                  color: Color(0xFFB45309),
                                  fontWeight: FontWeight.w700,
                                ),
                              )
                            else if (allowed && unit.usable)
                              FilledButton.icon(
                                onPressed: hasActive
                                    ? null
                                    : () => onStart(m, unit),
                                icon: const Icon(Icons.play_arrow_rounded),
                                label: const Text('Démarrer'),
                              )
                            else if (allowed)
                              const Text(
                                'Cet exemplaire est indisponible',
                                style: TextStyle(
                                  color: Color(0xFFB45309),
                                  fontWeight: FontWeight.w700,
                                ),
                              )
                            else
                              Text(
                                'Accès réservé à l’opérateur assigné',
                                style: TextStyle(
                                  color: _atelierMuted(context),
                                  fontSize: 12,
                                ),
                              ),
                            if (user.canWritePage(AppPage.machines) &&
                                !m.temporary)
                              TextButton.icon(
                                onPressed: () => onManage(m),
                                icon: const Icon(Icons.build_circle_outlined),
                                label: const Text('Gérer les exemplaires'),
                              ),
                          ],
                        ),
                      ),
                    );
                  }),
                )
                .toList(),
          ),
        const SizedBox(height: 24),
        if (operations.isNotEmpty)
          const Text(
            'Suivi des opérations',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
        const SizedBox(height: 8),
        if (operations.isNotEmpty)
          Glass(
            child: Column(
              children: operations.reversed.map((op) {
                final mine = op.operatorId == user.id;
                return ListTile(
                  leading: Icon(
                    op.active
                        ? Icons.play_circle_fill_rounded
                        : op.completionDraft
                        ? Icons.edit_note_rounded
                        : op.needsReview
                        ? Icons.warning_amber_rounded
                        : Icons.verified_rounded,
                    color: op.active
                        ? const Color(0xFF9333EA)
                        : op.completionDraft
                        ? const Color(0xFFF59E0B)
                        : op.needsReview
                        ? const Color(0xFFB45309)
                        : const Color(0xFF15803D),
                  ),
                  title: Text(
                    op.externalProduction
                        ? 'Travail externe temporaire'
                        : op.active
                        ? 'Opération en cours'
                        : op.completionDraft
                        ? 'Brouillon à valider'
                        : op.needsReview
                        ? 'Contrôle requis'
                        : 'Opération terminée',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    op.externalProduction
                        ? 'À ajouter au stock après validation'
                        : '${userName(op.operatorId)} · début ${dateText(op.startedAt)}',
                  ),
                  trailing: op.active && mine
                      ? FilledButton(
                          onPressed: () => onFinish(op),
                          child: const Text('Terminer'),
                        )
                      : Text(
                          op.active
                              ? 'En cours'
                              : op.completionDraft
                              ? 'En attente de validation'
                              : op.hopperPieces == null
                              ? '${op.outputPieces} pièces'
                              : '${op.outputPieces} cadous',
                        ),
                );
              }).toList(),
            ),
          ),
      ],
    ),
  );
}

class CategoryForm extends StatefulWidget {
  const CategoryForm({super.key, this.initial});
  final ProductCategory? initial;
  @override
  State<CategoryForm> createState() => _CategoryFormState();
}

class _CategoryFormState extends State<CategoryForm> {
  final name = TextEditingController();
  Uint8List? image;
  @override
  void initState() {
    super.initState();
    name.text = widget.initial?.name ?? '';
    if (widget.initial != null && widget.initial!.image.isNotEmpty) {
      image = widget.initial!.image;
    }
  }

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> pickImage() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 82,
      maxWidth: 1600,
    );
    if (file == null) return;
    final bytes = await readAcceptedImage(file, maximumBytes: 600 * 1024);
    if (!mounted) return;
    if (bytes == null) {
      return message(
        context,
        'Cette image est trop grande. Choisissez-en une autre.',
      );
    }
    setState(() => image = bytes);
  }

  void save() {
    if (name.text.trim().isEmpty) {
      message(context, 'Indiquez le nom de la catégorie.');
      return;
    }
    Navigator.pop(
      context,
      ProductCategory(
        id:
            widget.initial?.id ??
            DateTime.now().microsecondsSinceEpoch.toString(),
        name: name.text.trim(),
        productIds: widget.initial?.productIds ?? const [],
        image: image ?? Uint8List(0),
        families: widget.initial?.families ?? const [],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => FormShell(
    title: widget.initial == null
        ? 'Ajouter une catégorie'
        : 'Modifier la catégorie',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: name,
          decoration: const InputDecoration(labelText: 'Nom de la catégorie *'),
        ),
        const SizedBox(height: 14),
        ImageInput(
          bytes: image,
          label: 'Photo de la catégorie',
          onTap: pickImage,
        ),
        const SizedBox(height: 12),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: save,
            child: const Text('Enregistrer la catégorie'),
          ),
        ),
      ],
    ),
  );
}

class MachineUnitsPage extends StatefulWidget {
  const MachineUnitsPage({super.key, required this.machine});
  final FactoryMachine machine;
  @override
  State<MachineUnitsPage> createState() => _MachineUnitsPageState();
}

class _MachineUnitsPageState extends State<MachineUnitsPage> {
  late List<MachineUnit> units;
  @override
  void initState() {
    super.initState();
    units = [...widget.machine.units];
  }

  Future<void> changeState(MachineUnit unit) async {
    final choice = await showModalBottomSheet<MachineUnitState>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(
                Icons.check_circle_outline,
                color: Color(0xFF15803D),
              ),
              title: const Text('Disponible'),
              onTap: () => Navigator.pop(context, MachineUnitState.ready),
            ),
            ListTile(
              leading: const Icon(
                Icons.schedule_outlined,
                color: Color(0xFFB45309),
              ),
              title: const Text('Panne temporaire (24 h)'),
              onTap: () => Navigator.pop(
                context,
                MachineUnitState.temporarilyUnavailable,
              ),
            ),
            ListTile(
              leading: const Icon(
                Icons.block_outlined,
                color: Color(0xFFB42318),
              ),
              title: const Text('Retiré définitivement'),
              onTap: () => Navigator.pop(context, MachineUnitState.retired),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    var unavailableUntil = choice == MachineUnitState.temporarilyUnavailable
        ? DateTime.now().add(const Duration(hours: 24))
        : null;
    if (choice == MachineUnitState.temporarilyUnavailable) {
      final hours = TextEditingController(text: '24');
      final duration = await showDialog<int>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Durée de la panne'),
          content: TextField(
            controller: hours,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Nombre d’heures'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, int.tryParse(hours.text)),
              child: const Text('Confirmer'),
            ),
          ],
        ),
      );
      if (!mounted || duration == null || duration <= 0) return;
      unavailableUntil = DateTime.now().add(Duration(hours: duration));
    }
    setState(() {
      final index = units.indexOf(unit);
      units[index] = MachineUnit(
        number: unit.number,
        image: unit.image,
        state: choice,
        unavailableUntil: unavailableUntil,
      );
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Aura(
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back),
                  ),
                  Expanded(
                    child: Text(
                      'Exemplaires · ${widget.machine.name}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: units.map((unit) {
                  final usable = unit.usable;
                  final text = usable
                      ? 'Disponible'
                      : unit.state == MachineUnitState.retired
                      ? 'Retiré définitivement'
                      : 'En panne jusqu’au ${dateText(unit.unavailableUntil!)}';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Glass(
                      child: ListTile(
                        leading: Icon(
                          usable
                              ? Icons.check_circle_rounded
                              : Icons.warning_amber_rounded,
                          color: usable
                              ? const Color(0xFF15803D)
                              : const Color(0xFFB45309),
                        ),
                        title: Text(
                          'Exemplaire n°${unit.number}',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        subtitle: Text(text),
                        trailing: const Icon(Icons.edit_outlined),
                        onTap: () => changeState(unit),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(
                    context,
                    FactoryMachine(
                      id: widget.machine.id,
                      name: widget.machine.name,
                      type: widget.machine.type,
                      categoryId: widget.machine.categoryId,
                      outputId: widget.machine.outputId,
                      units: units,
                      operatorIds: widget.machine.operatorIds,
                      image: widget.machine.image,
                      temporary: widget.machine.temporary,
                      deadline: widget.machine.deadline,
                      plannedPieces: widget.machine.plannedPieces,
                      hopperPieces: widget.machine.hopperPieces,
                      temporaryInputProductId:
                          widget.machine.temporaryInputProductId,
                      temporarySourceDepotId:
                          widget.machine.temporarySourceDepotId,
                      temporaryInputPieces: widget.machine.temporaryInputPieces,
                    ),
                  ),
                  child: const Text('Enregistrer les états'),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class ReviewsPage extends StatefulWidget {
  const ReviewsPage({
    super.key,
    required this.operations,
    required this.product,
    required this.userName,
    required this.depots,
    required this.admin,
    required this.onApprove,
  });
  final List<Operation> operations;
  final Product? Function(String) product;
  final String Function(String) userName;
  final List<Depot> depots;
  final bool admin;
  final Future<void> Function(Operation operation, String depotId) onApprove;

  @override
  State<ReviewsPage> createState() => _ReviewsPageState();
}

class _ReviewsPageState extends State<ReviewsPage> {
  final selectedDepots = <String, String>{};

  @override
  Widget build(BuildContext context) {
    final pendingOperations = widget.operations
        .where((operation) => operation.needsReview)
        .toList();
    return Page(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHero(
            icon: pendingOperations.isEmpty
                ? Icons.verified_rounded
                : Icons.fact_check_rounded,
            title: 'Contrôles',
            subtitle: pendingOperations.isEmpty
                ? 'Tout est vérifié. Aucune action n’est nécessaire.'
                : '${pendingOperations.length} opération(s) demandent votre attention.',
          ),
          const SizedBox(height: 18),
          if (pendingOperations.isEmpty)
            Glass(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
              child: Center(
                child: Column(
                  children: [
                    const Icon(
                      Icons.task_alt_rounded,
                      color: Color(0xFF16A34A),
                      size: 48,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Aucun contrôle en attente',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Les opérations à contrôler apparaîtront ici.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: _atelierMuted(context)),
                    ),
                  ],
                ),
              ),
            )
          else
            ...pendingOperations.reversed.map(
              (operation) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Glass(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            color: Color(0xFFB45309),
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Pièces restantes à contrôler',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '${widget.product(operation.productId)?.displayReference ?? 'Produit'} · ${operation.pieces - (operation.outputPieces ?? 0)} pièce(s) · ${widget.userName(operation.operatorId)}',
                      ),
                      if (operation.remainderImage != null) ...[
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Image.memory(
                            operation.remainderImage!,
                            height: 150,
                            width: double.infinity,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ],
                      if (widget.admin) ...[
                        const SizedBox(height: 12),
                        LiquidSelectFormField<String>(
                          initialValue: selectedDepots[operation.id],
                          decoration: const InputDecoration(
                            labelText:
                                'Dépôt qui reçoit les pièces restantes *',
                          ),
                          items: widget.depots
                              .map(
                                (depot) => DropdownMenuItem(
                                  value: depot.id,
                                  child: Text(depot.name),
                                ),
                              )
                              .toList(),
                          onChanged: (value) => setState(
                            () => selectedDepots[operation.id] = value!,
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: selectedDepots[operation.id] == null
                                ? null
                                : () async {
                                    await widget.onApprove(
                                      operation,
                                      selectedDepots[operation.id]!,
                                    );
                                    if (mounted) setState(() {});
                                  },
                            icon: const Icon(Icons.task_alt_rounded),
                            label: const Text(
                              'Accepter et terminer l’opération',
                            ),
                          ),
                        ),
                      ] else
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            'En attente de l’approbation du responsable.',
                            style: TextStyle(color: _atelierMuted(context)),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class ValidationPage extends StatelessWidget {
  const ValidationPage({
    super.key,
    required this.products,
    required this.depots,
    required this.stockDrafts,
    required this.saleDrafts,
    required this.returnDrafts,
    required this.operationDrafts,
    required this.transferDrafts,
    required this.onApproveStock,
    required this.onEditStock,
    required this.onCancelStock,
    required this.onApproveSale,
    required this.onEditSale,
    required this.onCancelSale,
    required this.onApproveReturn,
    required this.onEditReturn,
    required this.onRejectReturn,
    required this.onCancelReturn,
    required this.onApproveOperation,
    required this.onEditOperation,
    required this.onCancelOperation,
    required this.onApproveTransfer,
    required this.onEditTransfer,
    required this.onCancelTransfer,
  });
  final List<Product> products;
  final List<Depot> depots;
  final List<StockAddition> stockDrafts;
  final List<Sale> saleDrafts;
  final List<SaleReturn> returnDrafts;
  final List<Operation> operationDrafts;
  final List<StockTransfer> transferDrafts;
  final Future<void> Function(StockAddition) onApproveStock;
  final Future<void> Function(StockAddition) onEditStock;
  final Future<void> Function(StockAddition) onCancelStock;
  final Future<void> Function(Sale) onApproveSale;
  final Future<void> Function(Sale) onEditSale;
  final Future<void> Function(Sale) onCancelSale;
  final Future<void> Function(SaleReturn) onApproveReturn;
  final Future<void> Function(SaleReturn) onEditReturn;
  final Future<void> Function(SaleReturn) onRejectReturn;
  final Future<void> Function(SaleReturn) onCancelReturn;
  final Future<void> Function(Operation) onApproveOperation;
  final Future<void> Function(Operation) onEditOperation;
  final Future<void> Function(Operation) onCancelOperation;
  final Future<void> Function(StockTransfer) onApproveTransfer;
  final Future<void> Function(StockTransfer) onEditTransfer;
  final Future<void> Function(StockTransfer) onCancelTransfer;

  Product? _product(String id) {
    for (final product in products) {
      if (product.id == id) return product;
    }
    return null;
  }

  String _depotName(String id) =>
      depots
          .where((depot) => depot.id == id)
          .map((depot) => depot.name)
          .firstOrNull ??
      'Dépôt inconnu';

  Future<void> _editStock(BuildContext context, StockAddition item) async {
    final isPurchaseReturn = item.returnOfPurchaseId != null;
    final quantity = TextEditingController(
      text: formatNumber(
        isPurchaseReturn ? item.quantity.abs() : item.quantity,
      ),
    );
    final receipt = TextEditingController(text: item.receiptNumber);
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          isPurchaseReturn
              ? 'Corriger le retour fournisseur'
              : 'Corriger l’achat',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: quantity,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Quantité (${item.unit.shortLabel})',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: receipt,
              decoration: const InputDecoration(labelText: 'N° de bon'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    final product = _product(item.productId);
    final entered = number(quantity.text);
    if (saved != true ||
        product == null ||
        entered <= 0 ||
        receipt.text.trim().isEmpty) {
      return;
    }
    await onEditStock(
      StockAddition(
        id: item.id,
        productId: item.productId,
        depotId: item.depotId,
        pieces: isPurchaseReturn
            ? -piecesForQuantity(product, entered, item.unit)
            : piecesForQuantity(product, entered, item.unit),
        receiptNumber: receipt.text.trim(),
        supplierId: item.supplierId,
        returnOfPurchaseId: item.returnOfPurchaseId,
        quantity: isPurchaseReturn ? -entered : entered,
        unit: item.unit,
        images: item.images,
        addedAt: item.addedAt,
        transportCharge: item.transportCharge,
      ),
    );
  }

  Future<void> _editSale(BuildContext context, Sale item) async {
    final quantity = TextEditingController(text: formatNumber(item.quantity));
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Corriger la vente'),
        content: TextField(
          controller: quantity,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Quantité (${item.unit.shortLabel})',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    final product = _product(item.productId);
    final entered = number(quantity.text);
    if (saved != true || product == null || entered <= 0) return;
    await onEditSale(
      Sale(
        id: item.id,
        productId: item.productId,
        depotId: item.depotId,
        clientId: item.clientId,
        pieces: piecesForQuantity(product, entered, item.unit),
        quantity: entered,
        unit: item.unit,
        images: item.images,
        createdAt: item.createdAt,
        transportCharge: item.transportCharge,
      ),
    );
  }

  Future<void> _editReturn(BuildContext context, SaleReturn item) async {
    final pieces = TextEditingController(text: '${item.pieces}');
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Corriger le retour'),
        content: TextField(
          controller: pieces,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(labelText: 'Pièces retournées'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    final value = int.tryParse(pieces.text);
    if (saved != true || value == null || value <= 0) return;
    await onEditReturn(
      SaleReturn(
        id: item.id,
        saleId: item.saleId,
        productId: item.productId,
        depotId: item.depotId,
        pieces: value,
        createdAt: item.createdAt,
        status: ReturnValidationStatus.pending,
      ),
    );
  }

  Future<void> _editOperation(BuildContext context, Operation operation) async {
    final output = TextEditingController(
      text: '${operation.outputPieces ?? 0}',
    );
    final remainder = TextEditingController(
      text: '${operation.remainderPieces}',
    );
    final scrap = TextEditingController(text: '${operation.scrapPieces}');
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Corriger la production'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: output,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Pièces fabriquées'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: remainder,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Pièces restantes (retour au stock)',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: scrap,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Pièces perdues / déchets',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    final outputPieces = int.tryParse(output.text);
    final remainderPieces = int.tryParse(remainder.text);
    final scrapPieces = int.tryParse(scrap.text);
    if (saved != true ||
        outputPieces == null ||
        remainderPieces == null ||
        scrapPieces == null ||
        outputPieces < 0 ||
        remainderPieces < 0 ||
        scrapPieces < 0 ||
        (remainderPieces > 0 && operation.remainderDepotId == null) ||
        (scrapPieces > 0 && operation.scrapDepotId == null) ||
        (!operation.externalProduction &&
            (operation.hopperPieces == null
                    ? outputPieces + remainderPieces + scrapPieces
                    : outputPieces * operation.hopperPieces! +
                          remainderPieces +
                          scrapPieces) !=
                operation.pieces)) {
      return;
    }
    operation.outputPieces = outputPieces;
    operation.remainderPieces = remainderPieces;
    operation.scrapPieces = scrapPieces;
    await onEditOperation(operation);
  }

  Future<void> _editTransfer(BuildContext context, StockTransfer item) async {
    final pieces = TextEditingController(text: '${item.pieces}');
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Corriger le transfert'),
        content: TextField(
          controller: pieces,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(labelText: 'Nombre de pièces'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    final quantity = int.tryParse(pieces.text);
    if (saved != true || quantity == null || quantity <= 0) return;
    await onEditTransfer(
      StockTransfer(
        id: item.id,
        productId: item.productId,
        sourceDepotId: item.sourceDepotId,
        destinationDepotId: item.destinationDepotId,
        pieces: quantity,
        createdAt: item.createdAt,
        draft: true,
      ),
    );
  }

  Widget _draftCard(BuildContext context, {
    required IconData icon,
    required String title,
    required String detail,
    VoidCallback? onEdit,
    required Future<void> Function() onApprove,
    Future<void> Function()? onReject,
    Future<void> Function()? onCancel,
  }) => Glass(
    padding: const EdgeInsets.all(14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: const Color(0xFFF59E0B)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  Text(detail, style: TextStyle(color: _atelierMuted(context))),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (onReject != null)
              OutlinedButton.icon(
                onPressed: () async => onReject(),
                icon: const Icon(Icons.block_outlined, size: 18),
                label: const Text('Refuser'),
              ),
            if (onCancel != null)
              OutlinedButton.icon(
                onPressed: () async => onCancel(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppPalette.coral,
                ),
                icon: const Icon(Icons.cancel_outlined, size: 18),
                label: const Text('Annuler'),
              ),
            if (onEdit != null)
              OutlinedButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Modifier'),
              ),
            FilledButton.icon(
              onPressed: () async => onApprove(),
              icon: const Icon(Icons.task_alt_rounded, size: 18),
              label: const Text('Valider'),
            ),
          ],
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final total =
        stockDrafts.length +
        saleDrafts.length +
        returnDrafts.length +
        operationDrafts.length +
        transferDrafts.length;
    return Page(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHero(
            icon: Icons.verified_user_rounded,
            title: 'Validations',
            subtitle: total == 0
                ? 'Toutes les opérations sont à jour.'
                : '$total brouillon(s) attendent votre contrôle.',
          ),
          const SizedBox(height: 16),
          Text(
            'Brouillons à valider ($total)',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            'Chaque brouillon peut être corrigé, validé ou annulé. Une annulation ne modifie pas le stock.',
            style: TextStyle(color: _atelierMuted(context)),
          ),
          const SizedBox(height: 16),
          if (total == 0)
            const Empty(
              icon: Icons.task_alt_rounded,
              title: 'Aucun brouillon',
              detail: 'Toutes les opérations sont validées.',
            )
          else ...[
            ...stockDrafts.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _draftCard(
                  context,
                  icon: item.returnOfPurchaseId == null
                      ? Icons.shopping_cart_checkout_rounded
                      : Icons.assignment_return_outlined,
                  title:
                      '${item.returnOfPurchaseId == null ? 'Achat' : 'Retour fournisseur'} · ${_product(item.productId)?.displayReference ?? 'Produit'}',
                  detail:
                      '${formatQuantity(item.quantity.abs(), item.unit)} · Bon ${item.receiptNumber}',
                  onEdit: () => _editStock(context, item),
                  onCancel: () => onCancelStock(item),
                  onApprove: () => onApproveStock(item),
                ),
              ),
            ),
            ...saleDrafts.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _draftCard(
                  context,
                  icon: Icons.point_of_sale_rounded,
                  title:
                      'Vente · ${_product(item.productId)?.displayReference ?? 'Produit'}',
                  detail: formatQuantity(item.quantity, item.unit),
                  onEdit: () => _editSale(context, item),
                  onCancel: () => onCancelSale(item),
                  onApprove: () => onApproveSale(item),
                ),
              ),
            ),
            ...returnDrafts.map((item) {
              final product = _product(item.productId);
              final quantity = product == null
                  ? '${item.pieces} pièce(s)'
                  : productQuantityLabel(product, item.pieces);
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _draftCard(
                  context,
                  icon: Icons.assignment_return_rounded,
                  title:
                      'Retour client · ${product?.displayReference ?? 'Produit'}',
                  detail: '$quantity · en attente',
                  onEdit: () => _editReturn(context, item),
                  onApprove: () => onApproveReturn(item),
                  onReject: () => onRejectReturn(item),
                  onCancel: () => onCancelReturn(item),
                ),
              );
            }),
            ...operationDrafts.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _draftCard(
                  context,
                  icon: item.externalProduction
                      ? Icons.local_shipping_outlined
                      : Icons.precision_manufacturing_rounded,
                  title: item.externalProduction
                      ? 'Travail externe · ${_product(item.outputProductId ?? item.productId)?.displayReference ?? 'Produit'}'
                      : 'Production · ${_product(item.productId)?.displayReference ?? 'Produit'}',
                  detail: item.externalProduction
                      ? '${item.outputPieces ?? 0} à ajouter au stock · sans opérateur'
                      : '${item.outputPieces ?? 0} fabriquées · ${item.remainderPieces} restantes · ${item.scrapPieces} déchet(s)',
                  onEdit: () => _editOperation(context, item),
                  onCancel: () => onCancelOperation(item),
                  onApprove: () => onApproveOperation(item),
                ),
              ),
            ),
            ...transferDrafts.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _draftCard(
                  context,
                  icon: Icons.swap_horiz_rounded,
                  title:
                      'Transfert · ${_product(item.productId)?.displayReference ?? 'Produit'}',
                  detail:
                      '${item.pieces} pièce(s) · ${_depotName(item.sourceDepotId)} → ${_depotName(item.destinationDepotId)}',
                  onEdit: () => _editTransfer(context, item),
                  onCancel: () => onCancelTransfer(item),
                  onApprove: () => onApproveTransfer(item),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class PayrollPage extends StatefulWidget {
  const PayrollPage({
    super.key,
    required this.users,
    required this.products,
    required this.operations,
    required this.payments,
    required this.meterRate,
    required this.onPay,
    required this.onRateChanged,
  });

  final List<AppUser> users;
  final List<Product> products;
  final List<Operation> operations;
  final List<OperatorPayment> payments;
  final double meterRate;
  final Future<void> Function(String operatorId, double amount) onPay;
  final Future<void> Function(double rate) onRateChanged;

  @override
  State<PayrollPage> createState() => _PayrollPageState();
}

class _PayrollPageState extends State<PayrollPage> {
  late double meterRate = widget.meterRate;

  Product? _product(String id) {
    for (final product in widget.products) {
      if (product.id == id) return product;
    }
    return null;
  }

  double _meters(Operation operation) =>
      operation.pieces * (_product(operation.productId)?.lengthMeters ?? 0);

  bool _inMonth(DateTime value, DateTime month) =>
      value.year == month.year && value.month == month.month;

  Future<void> _pay(BuildContext context, AppUser operator) async {
    final amount = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Paiement · ${operator.fullName}'),
        content: TextField(
          controller: amount,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Montant payé (DH)'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    final value = number(amount.text);
    if (confirmed != true || value <= 0) return;
    await widget.onPay(operator.id, value);
  }

  Future<void> _changeRate() async {
    final value = TextEditingController(text: formatNumber(meterRate));
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Modifier le prix du mètre'),
        content: TextField(
          controller: value,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Prix par mètre (DH)'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    final rate = number(value.text);
    if (confirmed != true || rate <= 0) return;
    await widget.onRateChanged(rate);
    if (mounted) setState(() => meterRate = rate);
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final operators = widget.users.where((user) => user.isOperator).toList();
    return Page(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHero(
            icon: Icons.payments_rounded,
            title: 'Paie des opérateurs',
            subtitle:
                'Seules les opérations validées comptent · ${formatNumber(meterRate)} DH par mètre.',
            trailing: OutlinedButton.icon(
              onPressed: _changeRate,
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Prix'),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Le paiement est facultatif : un montant supérieur crée une avance, un montant inférieur laisse un reste à payer.',
            style: TextStyle(color: _atelierMuted(context)),
          ),
          const SizedBox(height: 16),
          if (operators.isEmpty)
            const Empty(
              icon: Icons.engineering_outlined,
              title: 'Aucun opérateur',
              detail: 'Ajoutez un utilisateur avec le rôle Opérateur.',
            )
          else
            ...operators.map((operator) {
              final approved = widget.operations
                  .where(
                    (operation) =>
                        operation.operatorId == operator.id &&
                        operation.validatedAt != null &&
                        !operation.completionDraft,
                  )
                  .toList();
              final meters = approved.fold<double>(
                0,
                (total, operation) => total + _meters(operation),
              );
              final monthMeters = approved
                  .where((operation) => _inMonth(operation.validatedAt!, now))
                  .fold<double>(
                    0,
                    (total, operation) => total + _meters(operation),
                  );
              final earned = meters * meterRate;
              final paid = widget.payments
                  .where((payment) => payment.operatorId == operator.id)
                  .fold<double>(0, (total, payment) => total + payment.amount);
              final balance = earned - paid;
              final showWarning = now.day >= 25 && balance > 0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Glass(
                  padding: const EdgeInsets.all(15),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                            foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
                            child: Text(
                              operator.fullName.substring(0, 1).toUpperCase(),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              operator.fullName,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          FilledButton.icon(
                            onPressed: () => _pay(context, operator),
                            icon: const Icon(Icons.add_card_rounded),
                            label: const Text('Payer'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Ce mois : ${formatNumber(monthMeters)} m · ${formatNumber(monthMeters * meterRate)} DH',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        'Total validé : ${formatNumber(meters)} m · ${formatNumber(earned)} DH',
                      ),
                      Text('Total payé : ${formatNumber(paid)} DH'),
                      const SizedBox(height: 8),
                      if (balance > 0)
                        Text(
                          'Reste à payer : ${formatNumber(balance)} DH',
                          style: TextStyle(
                            color: _atelierWarning(context),
                            fontWeight: FontWeight.w900,
                          ),
                        )
                      else if (balance < 0)
                        Text(
                          'Avance : ${formatNumber(-balance)} DH · équivaut à ${formatNumber((-balance) / meterRate)} m',
                          style: TextStyle(
                            color: _atelierSuccess(context),
                            fontWeight: FontWeight.w900,
                          ),
                        )
                      else
                        Text(
                          'Solde réglé',
                          style: TextStyle(
                            color: _atelierSuccess(context),
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      if (showWarning) ...[
                        const SizedBox(height: 9),
                        const Row(
                          children: [
                            Icon(
                              Icons.warning_amber_rounded,
                              color: Color(0xFFF59E0B),
                            ),
                            SizedBox(width: 7),
                            Expanded(
                              child: Text(
                                'Fin de mois : reste de paie à suivre.',
                                style: TextStyle(
                                  color: Color(0xFF92400E),
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}

class DeveloperModePage extends StatefulWidget {
  const DeveloperModePage({
    super.key,
    required this.products,
    required this.categories,
    required this.depots,
    required this.purchases,
    required this.sales,
    required this.machines,
    required this.operations,
    required this.transfers,
    required this.returns,
    required this.database,
    required this.onChanged,
  });
  final List<Product> products;
  final List<ProductCategory> categories;
  final List<Depot> depots;
  final List<StockAddition> purchases;
  final List<Sale> sales;
  final List<FactoryMachine> machines;
  final List<Operation> operations;
  final List<StockTransfer> transfers;
  final List<SaleReturn> returns;
  final AppDatabase database;
  final Future<void> Function() onChanged;
  @override
  State<DeveloperModePage> createState() => _DeveloperModePageState();
}

class _DeveloperModePageState extends State<DeveloperModePage> {
  Future<T?> _select<T>({
    required String title,
    required List<T> values,
    required String Function(T) label,
  }) async {
    T? selected;
    return showDialog<T>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(title),
          content: LiquidSelectFormField<T>(
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Élément'),
            items: values
                .map(
                  (value) => DropdownMenuItem(
                    value: value,
                    child: Text(label(value), overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
            onChanged: (value) => setDialogState(() => selected = value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: selected == null
                  ? null
                  : () => Navigator.pop(context, selected),
              style: _criticalActionStyle,
              child: const Text('Continuer'),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _confirm(String text) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Confirmer l’action irréversible'),
          content: Text(text),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: _criticalActionStyle,
              child: const Text('Supprimer'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _finish(String text) async {
    await widget.onChanged();
    if (!mounted) return;
    message(context, text);
    Navigator.pop(context);
  }

  Future<void> _deleteProduct() async {
    final product = await _select(
      title: 'Supprimer un produit',
      values: widget.products,
      label: (item) => item.displayReference,
    );
    if (product == null ||
        !await _confirm(
          'Le produit et tous ses achats, ventes, transferts et opérations associés seront supprimés.',
        )) {
      return;
    }
    try {
      await widget.database.deleteProductAndHistory(product.id);
      await _finish('Produit supprimé.');
    } on StateError catch (error) {
      if (mounted) message(context, error.message);
    }
  }

  Future<void> _deleteCategory() async {
    final category = await _select(
      title: 'Supprimer une catégorie',
      values: widget.categories,
      label: (item) => item.name,
    );
    if (category == null ||
        !await _confirm('La catégorie sera supprimée définitivement.')) {
      return;
    }
    await widget.database.deleteCategory(category.id);
    await _finish('Catégorie supprimée.');
  }

  Future<void> _deletePurchase() async {
    final purchase = await _select(
      title: 'Supprimer un achat',
      values: widget.purchases,
      label: (item) => 'Achat #${item.id ?? '—'} · ${item.pieces} pièce(s)',
    );
    if (purchase?.id == null ||
        !await _confirm('Cet achat sera supprimé définitivement.')) {
      return;
    }
    await widget.database.deleteStockAddition(purchase!.id!);
    await _finish('Achat supprimé.');
  }

  Future<void> _editPurchase() async {
    final item = await _select(
      title: 'Modifier un achat',
      values: widget.purchases,
      label: (item) => 'Achat #${item.id ?? '—'} · ${item.pieces} pièce(s)',
    );
    if (item == null) return;
    final pieces = await _editPieces('Modifier l’achat', item.pieces);
    if (pieces == null || pieces <= 0) return;
    await widget.database.updateStockAddition(
      StockAddition(
        id: item.id,
        productId: item.productId,
        depotId: item.depotId,
        pieces: pieces,
        receiptNumber: item.receiptNumber,
        supplierId: item.supplierId,
        returnOfPurchaseId: item.returnOfPurchaseId,
        quantity: pieces.toDouble(),
        unit: InventoryUnit.piece,
        images: item.images,
        addedAt: item.addedAt,
        draft: item.draft,
        transportCharge: item.transportCharge,
      ),
    );
    await _finish('Achat modifié.');
  }

  Future<void> _deleteSale() async {
    final sale = await _select(
      title: 'Supprimer une vente',
      values: widget.sales,
      label: (item) =>
          'Vente · ${item.pieces} pièce(s) · ${dateText(item.createdAt)}',
    );
    if (sale == null ||
        !await _confirm(
          'La vente et ses éventuels retours seront supprimés définitivement.',
        )) {
      return;
    }
    await widget.database.deleteSaleAndReturns(sale.id);
    await _finish('Vente supprimée.');
  }

  Future<void> _editSale() async {
    final item = await _select(
      title: 'Modifier une vente',
      values: widget.sales,
      label: (item) =>
          'Vente · ${item.pieces} pièce(s) · ${dateText(item.createdAt)}',
    );
    if (item == null) return;
    final pieces = await _editPieces('Modifier la vente', item.pieces);
    if (pieces == null || pieces <= 0) return;
    await widget.database.updateSale(
      Sale(
        id: item.id,
        productId: item.productId,
        depotId: item.depotId,
        clientId: item.clientId,
        pieces: pieces,
        quantity: pieces.toDouble(),
        unit: InventoryUnit.piece,
        images: item.images,
        createdAt: item.createdAt,
        draft: item.draft,
        transportCharge: item.transportCharge,
      ),
    );
    await _finish('Vente modifiée.');
  }

  Future<String?> _editText(String title, String initial, String label) async {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: label),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
  }

  Future<int?> _editPieces(String title, int initial) async {
    final value = await _editText(title, '$initial', 'Quantité en pièces');
    final pieces = int.tryParse(value ?? '');
    return pieces != null && pieces >= 0 ? pieces : null;
  }

  Future<void> _editCategory() async {
    final item = await _select(
      title: 'Modifier une catégorie',
      values: widget.categories,
      label: (item) => item.name,
    );
    if (item == null) return;
    final name = await _editText(
      'Modifier la catégorie',
      item.name,
      'Nom de la catégorie',
    );
    if (name == null || name.isEmpty) return;
    await widget.database.updateCategory(item.copyWith(name: name));
    await _finish('Catégorie modifiée.');
  }

  Future<void> _editProduct() async {
    final item = await _select(
      title: 'Modifier un produit',
      values: widget.products,
      label: (item) => item.displayReference,
    );
    if (item == null) return;
    final name = await _editText(
      'Modifier le produit',
      item.name,
      'Nom du produit',
    );
    if (name == null || name.isEmpty) return;
    await widget.database.updateProduct(
      Product(
        id: item.id,
        name: name,
        reference: item.reference,
        width: item.width,
        lengthMeters: item.lengthMeters,
        lengthUnit: item.lengthUnit,
        thickness: item.thickness,
        kind: item.kind,
        initialStock: item.initialStock,
        initialDepotId: item.initialDepotId,
        material: item.material,
        hoseUnit: item.hoseUnit,
        metersPerPiece: item.metersPerPiece,
        diameter: item.diameter,
        diameterIsExternal: item.diameterIsExternal,
        diameterCalculatedFromDimensions: item.diameterCalculatedFromDimensions,
        image: item.image,
        parentProductId: item.parentProductId,
      ),
    );
    await _finish('Produit modifié.');
  }

  Future<void> _editDepot() async {
    final item = await _select(
      title: 'Modifier un dépôt',
      values: widget.depots,
      label: (item) => item.name,
    );
    if (item == null) return;
    final name = await _editText(
      'Modifier le dépôt',
      item.name,
      'Nom du dépôt',
    );
    if (name == null || name.isEmpty) return;
    await widget.database.updateDepot(
      Depot(id: item.id, name: name, image: item.image),
    );
    await _finish('Dépôt modifié.');
  }

  Future<void> _deleteDepot() async {
    final item = await _select(
      title: 'Supprimer un dépôt',
      values: widget.depots
          .where((item) => item.id != 'general-depot')
          .toList(),
      label: (item) => item.name,
    );
    if (item == null ||
        !await _confirm(
          'Ce dépôt sera supprimé. Vérifiez qu’aucun stock ou historique ne l’utilise encore.',
        )) {
      return;
    }
    try {
      await widget.database.deleteDepot(item.id);
      await _finish('Dépôt supprimé.');
    } on StateError catch (error) {
      if (mounted) message(context, error.message);
    }
  }

  Future<void> _deleteMachine() async {
    final item = await _select(
      title: 'Supprimer une machine',
      values: widget.machines,
      label: (item) => item.name,
    );
    if (item == null ||
        !await _confirm(
          'La machine sera supprimée. Les opérations restent dans l’historique.',
        )) {
      return;
    }
    await widget.database.deleteMachine(item.id);
    await _finish('Machine supprimée.');
  }

  Future<void> _editMachine() async {
    final item = await _select(
      title: 'Modifier une machine',
      values: widget.machines,
      label: (item) => item.name,
    );
    if (item == null) return;
    final name = await _editText(
      'Modifier la machine',
      item.name,
      'Nom de la machine',
    );
    if (name == null || name.isEmpty) return;
    await widget.database.updateMachine(
      FactoryMachine(
        id: item.id,
        name: name,
        type: item.type,
        categoryId: item.categoryId,
        outputId: item.outputId,
        units: item.units,
        operatorIds: item.operatorIds,
        image: item.image,
        temporary: item.temporary,
        deadline: item.deadline,
        plannedPieces: item.plannedPieces,
        hopperPieces: item.hopperPieces,
        temporaryInputProductId: item.temporaryInputProductId,
        temporarySourceDepotId: item.temporarySourceDepotId,
        temporaryInputPieces: item.temporaryInputPieces,
      ),
    );
    await _finish('Machine modifiée.');
  }

  Future<void> _deleteOperation() async {
    final item = await _select(
      title: 'Supprimer une opération',
      values: widget.operations,
      label: (item) => '${item.id} · ${item.pieces} pièce(s)',
    );
    if (item == null ||
        !await _confirm(
          'Cette opération sera supprimée et sa réservation de stock sera annulée.',
        )) {
      return;
    }
    await widget.database.deleteOperation(item.id);
    await _finish('Opération supprimée.');
  }

  Future<void> _editOperation() async {
    final item = await _select(
      title: 'Modifier une opération',
      values: widget.operations,
      label: (item) => '${item.id} · ${item.pieces} pièce(s)',
    );
    if (item == null) return;
    final pieces = await _editPieces(
      'Modifier la quantité réservée',
      item.pieces,
    );
    if (pieces == null || pieces == 0) return;
    await widget.database.updateOperation(
      Operation(
        id: item.id,
        machineId: item.machineId,
        operatorId: item.operatorId,
        pieces: pieces,
        productId: item.productId,
        sourceDepotId: item.sourceDepotId,
        machineUnitNumber: item.machineUnitNumber,
        startedAt: item.startedAt,
        hopperPieces: item.hopperPieces,
        finishedAt: item.finishedAt,
        outputPieces: item.outputPieces,
        finalImage: item.finalImage,
        remainderImage: item.remainderImage,
        scrapImage: item.scrapImage,
        outputDepotId: item.outputDepotId,
        remainderDepotId: item.remainderDepotId,
        scrapDepotId: item.scrapDepotId,
        scrapProductId: item.scrapProductId,
        remainderPieces: item.remainderPieces,
        needsReview: item.needsReview,
        scrapPieces: item.scrapPieces,
        completionDraft: item.completionDraft,
        validatedAt: item.validatedAt,
        outputProductId: item.outputProductId,
        externalProduction: item.externalProduction,
      ),
    );
    await _finish('Opération modifiée.');
  }

  Future<void> _deleteTransfer() async {
    final item = await _select(
      title: 'Supprimer un transfert',
      values: widget.transfers,
      label: (item) => '${item.pieces} pièce(s) · ${dateText(item.createdAt)}',
    );
    if (item == null ||
        !await _confirm('Ce transfert sera supprimé définitivement.')) {
      return;
    }
    await widget.database.deleteStockTransfer(item.id);
    await _finish('Transfert supprimé.');
  }

  Future<void> _editTransfer() async {
    final item = await _select(
      title: 'Modifier un transfert',
      values: widget.transfers,
      label: (item) => '${item.pieces} pièce(s) · ${dateText(item.createdAt)}',
    );
    if (item == null) return;
    final pieces = await _editPieces('Modifier le transfert', item.pieces);
    if (pieces == null || pieces == 0) return;
    await widget.database.updateStockTransfer(
      StockTransfer(
        id: item.id,
        productId: item.productId,
        sourceDepotId: item.sourceDepotId,
        destinationDepotId: item.destinationDepotId,
        pieces: pieces,
        createdAt: item.createdAt,
        draft: item.draft,
      ),
    );
    await _finish('Transfert modifié.');
  }

  Future<void> _deleteReturn() async {
    final item = await _select(
      title: 'Supprimer un retour client',
      values: widget.returns,
      label: (item) => '${item.pieces} pièce(s) · ${dateText(item.createdAt)}',
    );
    if (item == null ||
        !await _confirm('Ce retour sera supprimé définitivement.')) {
      return;
    }
    await widget.database.deleteSaleReturn(item.id);
    await _finish('Retour supprimé.');
  }

  Future<void> _editReturn() async {
    final item = await _select(
      title: 'Modifier un retour client',
      values: widget.returns,
      label: (item) => '${item.pieces} pièce(s) · ${dateText(item.createdAt)}',
    );
    if (item == null) return;
    final pieces = await _editPieces('Modifier le retour', item.pieces);
    if (pieces == null || pieces == 0) return;
    await widget.database.updateSaleReturn(
      SaleReturn(
        id: item.id,
        saleId: item.saleId,
        productId: item.productId,
        depotId: item.depotId,
        pieces: pieces,
        createdAt: item.createdAt,
        status: item.status,
      ),
    );
    await _finish('Retour modifié.');
  }

  Future<void> _adjustStock() async {
    Product? product;
    Depot? depot;
    final quantity = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Correction exceptionnelle du stock'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LiquidSelectFormField<Product>(
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Produit'),
                items: widget.products
                    .map(
                      (item) => DropdownMenuItem(
                        value: item,
                        child: Text(
                          item.displayReference,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setDialogState(() => product = value),
              ),
              const SizedBox(height: 12),
              LiquidSelectFormField<Depot>(
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Dépôt'),
                items: widget.depots
                    .map(
                      (item) =>
                          DropdownMenuItem(value: item, child: Text(item.name)),
                    )
                    .toList(),
                onChanged: (value) => setDialogState(() => depot = value),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: quantity,
                keyboardType: const TextInputType.numberWithOptions(
                  signed: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Écart en pièces (+ ou -)',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
    final delta = int.tryParse(quantity.text);
    if (accepted != true ||
        product == null ||
        depot == null ||
        delta == null ||
        delta == 0) {
      return;
    }
    await widget.database.adjustStock(
      productId: product!.id,
      depotId: depot!.id,
      pieces: delta,
    );
    await _finish('Correction de stock enregistrée.');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Aura(
      child: SafeArea(
        child: Page(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: Icon(Icons.arrow_back, color: Theme.of(context).colorScheme.primary),
              ),
              Text(
                'Mode développeur',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: _atelierForeground(context),
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Zone réservée au propriétaire. Modifiez ou supprimez tout élément ; les suppressions sont définitives.',
                style: TextStyle(color: AppPalette.coral),
              ),
              const SizedBox(height: 22),
              Glass(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(
                        Icons.tune_rounded,
                        color: Color(0xFFB91C1C),
                      ),
                      title: const Text('Corriger le stock'),
                      subtitle: const Text(
                        'Ajoute ou retire un écart traçable.',
                      ),
                      onTap: _adjustStock,
                    ),
                    const Divider(),
                    ListTile(
                      leading: Icon(
                        Icons.edit_outlined,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      title: const Text('Modifier un produit'),
                      onTap: _editProduct,
                    ),
                    const Divider(),
                    ListTile(
                      leading: const Icon(
                        Icons.delete_forever_rounded,
                        color: Color(0xFFB91C1C),
                      ),
                      title: const Text('Supprimer un produit'),
                      onTap: _deleteProduct,
                    ),
                    const Divider(),
                    ListTile(
                      leading: Icon(
                        Icons.edit_location_alt_outlined,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      title: const Text('Modifier un dépôt'),
                      onTap: _editDepot,
                    ),
                    const Divider(),
                    ListTile(
                      leading: const Icon(
                        Icons.delete_sweep_outlined,
                        color: Color(0xFFB91C1C),
                      ),
                      title: const Text('Supprimer un dépôt'),
                      onTap: _deleteDepot,
                    ),
                    const Divider(),
                    ListTile(
                      leading: Icon(
                        Icons.edit_outlined,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      title: const Text('Modifier une catégorie'),
                      onTap: _editCategory,
                    ),
                    const Divider(),
                    ListTile(
                      leading: const Icon(
                        Icons.category_outlined,
                        color: Color(0xFFB91C1C),
                      ),
                      title: const Text('Supprimer une catégorie'),
                      onTap: _deleteCategory,
                    ),
                    const Divider(),
                    ListTile(
                      leading: const Icon(
                        Icons.shopping_cart_checkout_rounded,
                        color: Color(0xFFB91C1C),
                      ),
                      title: const Text('Supprimer un achat'),
                      onTap: _deletePurchase,
                    ),
                    const Divider(),
                    ListTile(
                      leading: Icon(
                        Icons.edit_outlined,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      title: const Text('Modifier un achat'),
                      onTap: _editPurchase,
                    ),
                    const Divider(),
                    ListTile(
                      leading: const Icon(
                        Icons.point_of_sale_rounded,
                        color: Color(0xFFB91C1C),
                      ),
                      title: const Text('Supprimer une vente'),
                      onTap: _deleteSale,
                    ),
                    const Divider(),
                    ListTile(
                      leading: Icon(
                        Icons.edit_outlined,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      title: const Text('Modifier une vente'),
                      onTap: _editSale,
                    ),
                    const Divider(),
                    ListTile(
                      leading: const Icon(
                        Icons.precision_manufacturing_outlined,
                        color: Color(0xFFB91C1C),
                      ),
                      title: const Text('Supprimer une machine'),
                      onTap: _deleteMachine,
                    ),
                    const Divider(),
                    ListTile(
                      leading: Icon(
                        Icons.edit_outlined,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      title: const Text('Modifier une machine'),
                      onTap: _editMachine,
                    ),
                    const Divider(),
                    ListTile(
                      leading: const Icon(
                        Icons.pending_actions_outlined,
                        color: Color(0xFFB91C1C),
                      ),
                      title: const Text('Supprimer une opération'),
                      onTap: _deleteOperation,
                    ),
                    const Divider(),
                    ListTile(
                      leading: Icon(
                        Icons.edit_outlined,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      title: const Text('Modifier une opération'),
                      onTap: _editOperation,
                    ),
                    const Divider(),
                    ListTile(
                      leading: const Icon(
                        Icons.swap_horiz_rounded,
                        color: Color(0xFFB91C1C),
                      ),
                      title: const Text('Supprimer un transfert'),
                      onTap: _deleteTransfer,
                    ),
                    const Divider(),
                    ListTile(
                      leading: Icon(
                        Icons.edit_outlined,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      title: const Text('Modifier un transfert'),
                      onTap: _editTransfer,
                    ),
                    const Divider(),
                    ListTile(
                      leading: const Icon(
                        Icons.assignment_return_outlined,
                        color: Color(0xFFB91C1C),
                      ),
                      title: const Text('Supprimer un retour client'),
                      onTap: _deleteReturn,
                    ),
                    const Divider(),
                    ListTile(
                      leading: Icon(
                        Icons.edit_outlined,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      title: const Text('Modifier un retour client'),
                      onTap: _editReturn,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class DeviceRequestsPage extends StatefulWidget {
  const DeviceRequestsPage({
    super.key,
    required this.userName,
    this.loadRequests = SupabaseAccounts.pendingDeviceRequests,
    this.loadDevices = SupabaseAccounts.trustedDevices,
  });

  final String Function(String userId) userName;
  final Future<List<DeviceAccessRequest>> Function() loadRequests;
  final Future<List<TrustedDevice>> Function() loadDevices;

  @override
  State<DeviceRequestsPage> createState() => _DeviceRequestsPageState();
}

class _DeviceRequestsPageState extends State<DeviceRequestsPage> {
  late Future<List<DeviceAccessRequest>> requests;
  late Future<List<TrustedDevice>> devices;

  @override
  void initState() {
    super.initState();
    requests = widget.loadRequests();
    devices = widget.loadDevices();
  }

  void reload() => setState(() {
    requests = widget.loadRequests();
    devices = widget.loadDevices();
  });

  Future<void> changeStatus(TrustedDevice device, String status) async {
    await SupabaseAccounts.setDeviceStatus(device.id, status);
    reload();
  }

  Future<void> decide(
    DeviceAccessRequest request, {
    required bool approve,
    bool makePrimary = false,
  }) async {
    try {
      await SupabaseAccounts.decideDeviceRequest(
        request,
        approve: approve,
        makePrimary: makePrimary,
      );
      if (mounted) {
        message(
          context,
          approve
              ? (makePrimary
                    ? 'Appareil principal approuvé.'
                    : 'Appareil secondaire autorisé.')
              : 'Appareil refusé.',
        );
      }
      reload();
    } catch (_) {
      if (mounted) {
        message(
          context,
          'Impossible de traiter la demande. Vérifiez la limite de deux appareils principaux.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Demandes d’appareil'),
      actions: [
        IconButton(onPressed: reload, icon: const Icon(Icons.refresh_rounded)),
      ],
    ),
    body: Aura(child: _buildBody()),
  );

  Widget _buildBody() => FutureBuilder<List<DeviceAccessRequest>>(
      future: requests,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: FilledButton.icon(
              onPressed: reload,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Réessayer'),
            ),
          );
        }
        final values = snapshot.data ?? const <DeviceAccessRequest>[];
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: values.length + 1,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            if (index == values.length) {
              return FutureBuilder<List<TrustedDevice>>(
                future: devices,
                builder: (context, deviceSnapshot) {
                  final items = deviceSnapshot.data ?? const <TrustedDevice>[];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Appareils autorisés',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (items.isEmpty) const Text('Aucun appareil approuvé.'),
                      ...items.map(
                        (device) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Glass(
                            radius: 22,
                            frosted: true,
                            padding: const EdgeInsets.all(4),
                            child: ListTile(
                              leading: Icon(
                                device.primary
                                    ? Icons.star_rounded
                                    : Icons.phone_android_rounded,
                              ),
                              title: Text(device.label),
                              subtitle: Text(
                                '${device.email}\n'
                                '${device.primary ? 'Principal' : 'Secondaire'} · ${device.status}\n'
                                'Entrée : ${device.lastLoginAt == null ? '—' : dateText(device.lastLoginAt!)} · '
                                'Sortie : ${device.lastLogoutAt == null ? 'En cours' : dateText(device.lastLogoutAt!)}',
                              ),
                              isThreeLine: true,
                              trailing: PopupMenuButton<String>(
                                onSelected: (value) =>
                                    changeStatus(device, value),
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: 'active',
                                    child: Text('Autoriser'),
                                  ),
                                  PopupMenuItem(
                                    value: 'suspended',
                                    child: Text('Suspendre'),
                                  ),
                                  PopupMenuItem(
                                    value: 'blocked',
                                    child: Text('Bloquer'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              );
            }
            final request = values[index];
            return Glass(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.phonelink_lock_outlined),
                      title: Text(widget.userName(request.userId)),
                      subtitle: Text(
                        '${request.deviceLabel}\nDemandé le ${dateText(request.requestedAt)}',
                      ),
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.end,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => decide(request, approve: false),
                          icon: const Icon(Icons.close_rounded),
                          label: const Text('Refuser'),
                        ),
                        FilledButton.icon(
                          onPressed: () => decide(request, approve: true),
                          icon: const Icon(Icons.check_rounded),
                          label: const Text('Autoriser cet appareil'),
                        ),
                        FilledButton.icon(
                          onPressed: () =>
                              decide(request, approve: true, makePrimary: true),
                          icon: const Icon(Icons.star_rounded),
                          label: const Text('Rendre principal'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
  );
}

class UsersPage extends StatefulWidget {
  const UsersPage({
    super.key,
    required this.users,
    required this.admin,
    required this.onAdd,
    required this.onUpdate,
    required this.onLoadSessions,
    required this.onOpenPayroll,
    required this.onOpenDeviceRequests,
  });
  final List<AppUser> users;
  final bool admin;
  final Future<AppUser> Function(AppUser) onAdd;
  final Future<void> Function(AppUser) onUpdate;
  final Future<List<UserSession>> Function(String) onLoadSessions;
  final VoidCallback onOpenPayroll;
  final VoidCallback onOpenDeviceRequests;
  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  Future<void> add() async {
    final user = await Navigator.push<AppUser>(
      context,
      MaterialPageRoute(builder: (_) => const UserForm()),
    );
    if (user != null) {
      try {
        await widget.onAdd(user);
        if (mounted) setState(() {});
      } on StateError catch (error) {
        if (mounted) message(context, error.message);
      }
    }
  }

  Future<void> open(AppUser user) async {
    final changed = await Navigator.push<AppUser>(
      context,
      MaterialPageRoute(
        builder: (_) => UserDetailsPage(
          user: user,
          canManage: widget.admin,
          loadSessions: widget.onLoadSessions,
        ),
      ),
    );
    if (changed != null) {
      try {
        await widget.onUpdate(changed);
        if (mounted) setState(() {});
      } on StateError catch (error) {
        if (mounted) message(context, error.message);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final visibleUsers = widget.users
        .where((user) => !user.isPrivateOwner)
        .toList();
    final scheme = Theme.of(context).colorScheme;
    return Page(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHero(
            icon: Icons.groups_rounded,
            title: 'Équipe',
            subtitle: '${visibleUsers.length} membre(s) de l’atelier.',
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                'Gérer les membres',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
              if (widget.admin) ...[
                OutlinedButton.icon(
                  onPressed: widget.onOpenPayroll,
                  icon: const Icon(Icons.payments_outlined),
                  label: const Text('Paie'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: widget.onOpenDeviceRequests,
                  icon: const Icon(Icons.phonelink_lock_outlined),
                  label: const Text('Appareils'),
                ),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SecurityActivityPage(),
                    ),
                  ),
                  icon: const Icon(Icons.security_rounded),
                  label: const Text('Sécurité'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: add,
                  icon: const Icon(Icons.person_add_alt_1),
                  label: const Text('Ajouter'),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          Glass(
            child: Column(
              children: visibleUsers
                  .map(
                    (u) => ListTile(
                      onTap: () => open(u),
                      leading: CircleAvatar(
                        backgroundColor: scheme.primary.withValues(
                          alpha: .16,
                        ),
                        foregroundColor: scheme.brightness == Brightness.dark
                            ? scheme.onPrimaryContainer
                            : AppPalette.primaryDark,
                        child: Text(u.fullName.substring(0, 1).toUpperCase()),
                      ),
                      title: Text(
                        u.fullName,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text('@${u.username} · ${u.status.label}'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class DepotForm extends StatefulWidget {
  const DepotForm({super.key, required this.allowGallery});
  final bool allowGallery;
  @override
  State<DepotForm> createState() => _DepotFormState();
}

class StockTransferForm extends StatefulWidget {
  const StockTransferForm({
    super.key,
    required this.products,
    required this.categories,
    this.catalogFamilies = const [],
    required this.depots,
    required this.available,
  });
  final List<Product> products;
  final List<ProductCategory> categories;
  final List<CatalogFamily> catalogFamilies;
  final List<Depot> depots;
  final int Function(String productId, String depotId) available;
  @override
  State<StockTransferForm> createState() => _StockTransferFormState();
}

class _StockTransferFormState extends State<StockTransferForm> {
  final form = GlobalKey<FormState>();
  final pieces = TextEditingController();
  String? productId;
  String? sourceDepotId;
  String? destinationDepotId;

  void save() {
    if (!(form.currentState?.validate() ?? false)) return;
    if (productId == null) {
      message(context, 'Choisissez un produit.');
      return;
    }
    final quantity = int.tryParse(pieces.text) ?? 0;
    if (sourceDepotId == null ||
        destinationDepotId == null ||
        sourceDepotId == destinationDepotId ||
        quantity <= 0 ||
        quantity > widget.available(productId!, sourceDepotId!)) {
      message(context, 'Vérifiez les dépôts et la quantité disponible.');
      return;
    }
    Navigator.pop(
      context,
      StockTransfer(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        productId: productId!,
        sourceDepotId: sourceDepotId!,
        destinationDepotId: destinationDepotId!,
        pieces: quantity,
        createdAt: DateTime.now(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => FormShell(
    title: 'Transférer le stock',
    subtitle: 'Le transfert reste en brouillon jusqu’à sa validation.',
    child: Form(
      key: form,
      child: Column(
        children: [
          CatalogProductBrowser(
            products: widget.products,
            categories: widget.categories,
            catalogFamilies: widget.catalogFamilies,
            buildProducts: (products) => ProductPicker(
              products: products,
              selected: productId == null ? <String>{} : {productId!},
              onTap: (product) => setState(() => productId = product.id),
            ),
          ),
          if (widget.products
                  .where((product) => product.id == productId)
                  .firstOrNull
              case final product?)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Produit sélectionné : ${product.displayReference}'),
            ),
          const SizedBox(height: 12),
          LiquidSelectFormField<String>(
            initialValue: sourceDepotId,
            decoration: const InputDecoration(labelText: 'Dépôt de départ *'),
            items: widget.depots
                .map(
                  (item) =>
                      DropdownMenuItem(value: item.id, child: Text(item.name)),
                )
                .toList(),
            onChanged: (value) => setState(() => sourceDepotId = value),
            validator: (value) =>
                value == null ? 'Choisissez le dépôt de départ.' : null,
          ),
          const SizedBox(height: 12),
          LiquidSelectFormField<String>(
            initialValue: destinationDepotId,
            decoration: const InputDecoration(labelText: 'Dépôt d’arrivée *'),
            items: widget.depots
                .map(
                  (item) =>
                      DropdownMenuItem(value: item.id, child: Text(item.name)),
                )
                .toList(),
            onChanged: (value) => setState(() => destinationDepotId = value),
            validator: (value) =>
                value == null ? 'Choisissez le dépôt d’arrivée.' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: pieces,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: 'Quantité (pièces) *',
              helperText: productId != null && sourceDepotId != null
                  ? 'Disponible : ${widget.available(productId!, sourceDepotId!)} pièce(s)'
                  : null,
            ),
            validator: (value) => (int.tryParse(value ?? '') ?? 0) > 0
                ? null
                : 'Indiquez une quantité valide.',
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: save,
              icon: const Icon(Icons.send_rounded),
              label: const Text('Envoyer à la validation'),
            ),
          ),
        ],
      ),
    ),
  );
}

class _DepotFormState extends State<DepotForm> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController();
  Uint8List? image;

  Future<void> pick() async {
    final file = await ImagePicker().pickImage(
      source: widget.allowGallery ? ImageSource.gallery : ImageSource.camera,
      imageQuality: 82,
      maxWidth: 1600,
    );
    if (file != null) {
      final bytes = await readAcceptedImage(file, maximumBytes: 600 * 1024);
      if (!mounted) return;
      if (bytes == null) {
        return message(
          context,
          'Cette image est trop grande. Choisissez-en une autre.',
        );
      }
      setState(() => image = bytes);
    }
  }

  void save() {
    if (!(form.currentState?.validate() ?? false) || image == null) {
      message(context, 'Prenez une photo du dépôt avant de continuer.');
      return;
    }
    Navigator.pop(
      context,
      Depot(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: name.text.trim(),
        image: image,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => FormShell(
    title: 'Ajouter un dépôt',
    child: Form(
      key: form,
      child: Column(
        children: [
          TextFormField(
            controller: name,
            decoration: const InputDecoration(labelText: 'Nom du dépôt *'),
            validator: required,
          ),
          const SizedBox(height: 14),
          ImageInput(
            bytes: image,
            label: widget.allowGallery
                ? 'Photo du dépôt * (galerie)'
                : 'Photo du dépôt * (caméra)',
            onTap: pick,
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: save,
              child: const Text('Enregistrer le dépôt'),
            ),
          ),
        ],
      ),
    ),
  );
}

class ProductKindPage extends StatelessWidget {
  const ProductKindPage({super.key});

  @override
  Widget build(BuildContext context) => FormShell(
    title: 'Type de produit',
    subtitle: 'Choisissez le type avant de renseigner le produit.',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: ProductKind.values
          .map(
            (kind) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => Navigator.pop(context, kind),
                child: Glass(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(switch (kind) {
                        ProductKind.standard => Icons.inventory_2_outlined,
                        ProductKind.hose => Icons.water_drop_outlined,
                        ProductKind.manufactured =>
                          Icons.precision_manufacturing_outlined,
                        ProductKind.diameter => Icons.architecture_outlined,
                      }, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              kind.label,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              kind.description,
                              style: TextStyle(
                                color: _atelierMuted(context),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded),
                    ],
                  ),
                ),
              ),
            ),
          )
          .toList(),
    ),
  );
}

class ProductForm extends StatefulWidget {
  const ProductForm({
    super.key,
    required this.kind,
    required this.depots,
    required this.categories,
    this.catalogFamilies = const [],
  });
  final ProductKind kind;
  final List<Depot> depots;
  final List<ProductCategory> categories;
  final List<CatalogFamily> catalogFamilies;

  @override
  State<ProductForm> createState() => _ProductFormState();
}

class _ProductFormState extends State<ProductForm> {
  final form = GlobalKey<FormState>();
  final manufacturedName = TextEditingController();
  final reference = TextEditingController();
  final length = TextEditingController();
  final width = TextEditingController();
  final metersPerPiece = TextEditingController();
  final thickness = TextEditingController();
  final initialStock = TextEditingController(text: '0');
  Uint8List? image;
  String? initialDepotId;
  String? categoryId;
  String? familyId;
  MaterialType material = MaterialType.steel;
  LengthUnit lengthUnit = LengthUnit.meter;
  LengthUnit widthUnit = LengthUnit.meter;
  ThicknessUnit thicknessUnit = ThicknessUnit.millimeter;
  HoseUnit hoseUnit = HoseUnit.piece;

  @override
  void dispose() {
    manufacturedName.dispose();
    reference.dispose();
    length.dispose();
    width.dispose();
    metersPerPiece.dispose();
    thickness.dispose();
    initialStock.dispose();
    super.dispose();
  }

  bool get isManufactured => widget.kind == ProductKind.manufactured;
  bool get hasStandardMeasurements => widget.kind == ProductKind.standard;
  bool get isHose => widget.kind == ProductKind.hose;
  bool get isDiameterBased => widget.kind == ProductKind.diameter;
  bool get usesDimensionFields => hasStandardMeasurements || isDiameterBased;
  double get lengthMeters => isHose
      ? (hoseUnit == HoseUnit.piece ? number(metersPerPiece.text) : 1)
      : number(length.text) * lengthUnit.metres;
  double get widthMeters => number(width.text) * widthUnit.metres;
  double get thicknessMillimetres =>
      number(thickness.text) * thicknessUnit.millimetres;
  // The field bound to [length] is intentionally labelled "Largeur" in the
  // form. Use one explicit canonical unit for the diameter formulas.
  double get enteredLengthCentimetres => widthMeters * 100;
  double get enteredWidthCentimetres => lengthMeters * 100;
  double get enteredThicknessCentimetres => thicknessMillimetres / 10;
  double get estimatedKilograms => kilogramsForDimensions(
    widthMeters: widthMeters,
    lengthMeters: lengthMeters,
    thicknessMillimetres: thicknessMillimetres,
    densityKilogramsPerCubicMeter: material.density,
  );
  double? get calculatedOutsideDiameter =>
      usesDimensionFields && number(length.text) > 0
      ? enteredWidthCentimetres / 3.14
      : null;
  double? get calculatedInsideDiameter => calculatedOutsideDiameter == null
      ? null
      : calculatedOutsideDiameter! - (2 * enteredThicknessCentimetres);
  List<_CatalogGroup> get groups =>
      _catalogGroups(widget.categories, widget.catalogFamilies);
  _CatalogGroup? get selectedGroup =>
      groups.where((group) => group.id == familyId).firstOrNull;
  _CatalogSection? get selectedSection => selectedGroup?.sections
      .where((section) => section.category.id == categoryId)
      .firstOrNull;

  String get categoryName => selectedSection?.category.name ?? 'Produit';
  String get productName {
    if (isManufactured) return manufacturedName.text.trim();
    if (!usesDimensionFields) return categoryName;
    // Width is displayed as "Longueur" and length as "Largeur" in this UI.
    return '$categoryName ${formatNumber(widthMeters * 1000)}*${formatNumber(lengthMeters * 1000)}*${formatNumber(thicknessMillimetres)}';
  }

  Future<void> pick() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Prendre une photo'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choisir depuis le téléphone'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    final file = await ImagePicker().pickImage(
      source: source,
      imageQuality: 82,
      maxWidth: 1600,
    );
    if (file != null) {
      final bytes = await readAcceptedImage(file, maximumBytes: 600 * 1024);
      if (!mounted) return;
      if (bytes == null) {
        return message(
          context,
          'Cette image est trop grande. Choisissez-en une autre.',
        );
      }
      setState(() => image = bytes);
    }
  }

  void save() {
    if (!(form.currentState?.validate() ?? false) || image == null) {
      message(
        context,
        'Ajoutez une photo et remplissez les champs obligatoires.',
      );
      return;
    }
    Navigator.pop(
      context,
      ProductCreation(
        categoryId: categoryId,
        familyId: selectedSection?.legacyFamilyId,
        product: Product(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          name: productName,
          reference: hasStandardMeasurements
              ? productName
              : reference.text.trim(),
          width: usesDimensionFields ? widthMeters : 1.5,
          lengthMeters: lengthMeters,
          lengthUnit: isHose ? LengthUnit.meter : lengthUnit,
          thickness: usesDimensionFields ? thicknessMillimetres : 0,
          kind: widget.kind,
          hoseUnit: hoseUnit,
          metersPerPiece: isHose && hoseUnit == HoseUnit.piece
              ? lengthMeters
              : null,
          diameter: isDiameterBased ? calculatedOutsideDiameter : null,
          diameterIsExternal: true,
          diameterCalculatedFromDimensions: isDiameterBased,
          initialStock: int.parse(initialStock.text),
          initialDepotId: initialDepotId ?? 'general-depot',
          material: isHose ? MaterialType.pvc : material,
          image: image,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => FormShell(
    title: 'Ajouter un produit',
    subtitle: widget.kind.label,
    child: Form(
      key: form,
      child: Column(
        children: [
          ImageInput(bytes: image, label: 'Photo du produit *', onTap: pick),
          const SizedBox(height: 14),
          if (!isManufactured ||
              widget.categories.isNotEmpty ||
              widget.catalogFamilies.isNotEmpty) ...[
            LiquidSelectFormField<String>(
              initialValue: familyId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Famille *'),
              items: [
                for (final family in groups)
                  DropdownMenuItem(value: family.id, child: Text(family.name)),
              ],
              onChanged: (value) => setState(() {
                familyId = value;
                categoryId = null;
              }),
              validator: (value) =>
                  value == null ? 'Choisissez une famille.' : null,
            ),
            if (selectedGroup case final family?) ...[
              const SizedBox(height: 14),
              LiquidSelectFormField<String>(
                key: ValueKey(family.id),
                initialValue: categoryId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Catégorie *'),
                items: [
                  for (final section in family.sections)
                    DropdownMenuItem(
                      value: section.category.id,
                      child: Text(section.category.name),
                    ),
                ],
                onChanged: (value) => setState(() => categoryId = value),
                validator: (value) =>
                    value == null ? 'Choisissez une catégorie.' : null,
              ),
              if (family.sections.isEmpty)
                const Text('Ajoutez d’abord une catégorie à cette famille.'),
            ],
            const SizedBox(height: 14),
          ],
          if (!hasStandardMeasurements) ...[
            TextFormField(
              controller: reference,
              decoration: const InputDecoration(labelText: 'Référence *'),
              validator: required,
            ),
            const SizedBox(height: 14),
          ],
          if (isHose) ...[
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Unité du tuyau *',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(height: 8),
            SegmentedButton<HoseUnit>(
              segments: const [
                ButtonSegment(value: HoseUnit.piece, label: Text('Pièce')),
                ButtonSegment(value: HoseUnit.meter, label: Text('Mètre')),
              ],
              selected: {hoseUnit},
              onSelectionChanged: (value) =>
                  setState(() => hoseUnit = value.first),
            ),
            const SizedBox(height: 12),
            if (hoseUnit == HoseUnit.piece) ...[
              TextFormField(
                controller: metersPerPiece,
                decoration: const InputDecoration(
                  labelText: 'Mètres dans chaque pièce *',
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: positive,
              ),
              const SizedBox(height: 12),
            ],
            Glass(
              padding: const EdgeInsets.all(14),
              child: Text(
                hoseUnit == HoseUnit.piece
                    ? 'Indiquez les mètres dans chaque pièce. Le stock initial sera saisi en pièces et le total en mètres sera calculé automatiquement.'
                    : 'Le stock initial de ce tuyau sera saisi directement en mètres.',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ] else if (isManufactured) ...[
            TextFormField(
              controller: manufacturedName,
              decoration: const InputDecoration(
                labelText: 'Nom du produit *',
                helperText: 'Saisissez un seul mot.',
              ),
              textCapitalization: TextCapitalization.words,
              validator: (value) {
                final words = (value ?? '')
                    .trim()
                    .split(RegExp(r'\s+'))
                    .where((word) => word.isNotEmpty);
                if (words.isEmpty) return 'Saisissez le nom du produit.';
                if (words.length > 1) {
                  return 'Le nom ne doit contenir qu’un seul mot.';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            const Glass(
              padding: EdgeInsets.all(14),
              child: Text(
                'Ce produit est un modèle de fabrication. Il ne demande ni longueur, ni largeur, ni épaisseur : chaque production ajoutera les mesures du produit brut au nom saisi ci-dessus.',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ] else ...[
            if (hasStandardMeasurements) ...[
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Matière du produit *',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              const SizedBox(height: 8),
              SegmentedButton<MaterialType>(
                segments: const [
                  ButtonSegment(
                    value: MaterialType.steel,
                    label: Text('Fer / acier'),
                  ),
                  ButtonSegment(value: MaterialType.pvc, label: Text('PVC')),
                ],
                selected: {material},
                onSelectionChanged: (value) =>
                    setState(() => material = value.first),
              ),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: width,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(labelText: 'Longueur *'),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: positive,
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 112,
                  child: LiquidSelectFormField<LengthUnit>(
                    initialValue: widthUnit,
                    decoration: const InputDecoration(labelText: 'Unité'),
                    items: LengthUnit.values
                        .map(
                          (unit) => DropdownMenuItem(
                            value: unit,
                            child: Text(unit.label),
                          ),
                        )
                        .toList(),
                    onChanged: (unit) => setState(() => widthUnit = unit!),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: length,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(labelText: 'Largeur *'),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: positive,
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 112,
                  child: LiquidSelectFormField<LengthUnit>(
                    initialValue: lengthUnit,
                    decoration: const InputDecoration(labelText: 'Unité'),
                    items: LengthUnit.values
                        .map(
                          (unit) => DropdownMenuItem(
                            value: unit,
                            child: Text(unit.label),
                          ),
                        )
                        .toList(),
                    onChanged: (unit) => setState(() => lengthUnit = unit!),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: thickness,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(labelText: 'Épaisseur *'),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: positive,
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 112,
                  child: LiquidSelectFormField<ThicknessUnit>(
                    initialValue: thicknessUnit,
                    decoration: const InputDecoration(labelText: 'Unité'),
                    items: ThicknessUnit.values
                        .map(
                          (unit) => DropdownMenuItem(
                            value: unit,
                            child: Text(unit.label),
                          ),
                        )
                        .toList(),
                    onChanged: (unit) => setState(() => thicknessUnit = unit!),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Glass(
              padding: const EdgeInsets.all(14),
              child: Text(
                calculatedInsideDiameter == null ||
                        calculatedOutsideDiameter == null
                    ? 'Saisissez la longueur, la largeur et l’épaisseur pour afficher le résultat.'
                    : 'Conversions utilisées\n'
                          'Longueur : ${formatNumber(number(width.text))} ${widthUnit.label} = ${formatNumber(enteredLengthCentimetres)} cm\n'
                          'Largeur : ${formatNumber(number(length.text))} ${lengthUnit.label} = ${formatNumber(enteredWidthCentimetres)} cm\n'
                          'Épaisseur : ${formatNumber(number(thickness.text))} ${thicknessUnit.label} = ${formatNumber(enteredThicknessCentimetres)} cm\n\n'
                          'Diamètre extérieur : ${formatNumber(enteredWidthCentimetres)} ÷ π = Ø ${formatNumber(calculatedOutsideDiameter!)} cm\n'
                          'Diamètre intérieur : ${formatNumber(calculatedOutsideDiameter!)} − (2 × ${formatNumber(enteredThicknessCentimetres)}) = Ø ${formatNumber(calculatedInsideDiameter!)} cm'
                          '${hasStandardMeasurements ? '\n\nRéférence : $productName' : ''}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 12),
            Glass(
              padding: const EdgeInsets.all(14),
              child: Text(
                'Poids estimé : ${formatWeight(estimatedKilograms)} / pièce',
              ),
            ),
          ],
          const SizedBox(height: 12),
          TextFormField(
            controller: initialStock,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: isHose && hoseUnit == HoseUnit.meter
                  ? 'Stock initial (mètres) *'
                  : 'Stock initial (pièces) *',
              helperText: isManufactured
                  ? 'Quantité déjà disponible avant les nouvelles productions.'
                  : null,
            ),
            validator: (value) {
              final count = int.tryParse(value ?? '');
              return count == null || count < 0
                  ? 'Indiquez une quantité valide.'
                  : null;
            },
          ),
          const SizedBox(height: 12),
          LiquidSelectFormField<String>(
            initialValue: initialDepotId,
            decoration: const InputDecoration(
              labelText: 'Dépôt du stock initial *',
            ),
            items: widget.depots
                .map(
                  (depot) => DropdownMenuItem(
                    value: depot.id,
                    child: Text(depot.name),
                  ),
                )
                .toList(),
            onChanged: (value) => setState(() => initialDepotId = value),
            validator: (value) => value == null ? 'Choisissez un dépôt.' : null,
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: save,
              child: const Text('Enregistrer le produit'),
            ),
          ),
        ],
      ),
    ),
  );
}

class StockForm extends StatefulWidget {
  const StockForm({
    super.key,
    required this.products,
    required this.categories,
    this.catalogFamilies = const [],
    required this.stock,
    required this.depots,
    required this.suppliers,
    required this.onAddSupplier,
    required this.allowGallery,
    this.canPreviewAttachments = false,
    this.initialProductId,
  });
  final List<Product> products;
  final List<ProductCategory> categories;
  final List<CatalogFamily> catalogFamilies;
  final int Function(String) stock;
  final List<Depot> depots;
  final List<Supplier> suppliers;
  final Future<Supplier?> Function() onAddSupplier;
  final bool allowGallery;
  final bool canPreviewAttachments;
  final String? initialProductId;

  @override
  State<StockForm> createState() => _StockFormState();
}

class SupplierForm extends StatefulWidget {
  const SupplierForm({super.key});

  @override
  State<SupplierForm> createState() => _SupplierFormState();
}

class _SupplierFormState extends State<SupplierForm> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController();
  final company = TextEditingController();
  final contact = TextEditingController();
  final images = <Uint8List>[];

  Future<void> pickImages() async {
    final available = 10 - images.length;
    if (available <= 0) return message(context, 'Maximum : 10 photos.');
    final picked = await ImagePicker().pickMultiImage(
      imageQuality: 82,
      maxWidth: 1600,
    );
    if (picked.isEmpty) return;
    final selected = await Future.wait(
      picked
          .take(available)
          .map((file) => readAcceptedImage(file, maximumBytes: 120 * 1024)),
    );
    final bytes = selected.whereType<Uint8List>().toList();
    if (bytes.isEmpty) return;
    if (mounted) setState(() => images.addAll(bytes));
    if (picked.length > available && mounted) {
      message(context, 'Maximum : 10 photos.');
    }
  }

  void save() {
    if (!(form.currentState?.validate() ?? false)) return;
    Navigator.pop(
      context,
      Supplier(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: name.text.trim(),
        company: company.text.trim(),
        contact: contact.text.trim(),
        images: images,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => FormShell(
    title: 'Ajouter un fournisseur',
    child: Form(
      key: form,
      child: Column(
        children: [
          TextFormField(
            controller: name,
            decoration: const InputDecoration(
              labelText: 'Nom du fournisseur *',
            ),
            validator: required,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: company,
            decoration: const InputDecoration(
              hintText: 'Société',
              labelText: 'Nom de société',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: contact,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Contact (facultatif)',
            ),
          ),
          const SizedBox(height: 12),
          MultiImageInput(
            images: images,
            label: 'Photos du fournisseur (${images.length}/10)',
            onTap: pickImages,
            onRemove: (index) => setState(() => images.removeAt(index)),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: save,
              child: const Text('Enregistrer le fournisseur'),
            ),
          ),
        ],
      ),
    ),
  );
}

class ClientForm extends StatefulWidget {
  const ClientForm({super.key});

  @override
  State<ClientForm> createState() => _ClientFormState();
}

class _ClientFormState extends State<ClientForm> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController();
  final company = TextEditingController();
  final phone = TextEditingController();
  final ice = TextEditingController();
  final images = <Uint8List>[];

  Future<void> pickImages() async {
    final available = 10 - images.length;
    if (available <= 0) return message(context, 'Maximum : 10 photos.');
    final picked = await ImagePicker().pickMultiImage(
      imageQuality: 82,
      maxWidth: 1600,
    );
    if (picked.isEmpty) return;
    final selected = await Future.wait(
      picked
          .take(available)
          .map((file) => readAcceptedImage(file, maximumBytes: 120 * 1024)),
    );
    final bytes = selected.whereType<Uint8List>().toList();
    if (bytes.isEmpty) return;
    if (mounted) setState(() => images.addAll(bytes));
    if (picked.length > available && mounted) {
      message(context, 'Maximum : 10 photos.');
    }
  }

  void save() {
    if (name.text.trim().isEmpty && company.text.trim().isEmpty) {
      message(context, 'Indiquez au moins le nom ou la société du client.');
      return;
    }
    Navigator.pop(
      context,
      Client(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: name.text.trim(),
        company: company.text.trim(),
        phone: phone.text.trim(),
        ice: ice.text.trim(),
        images: images,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => FormShell(
    title: 'Ajouter un client',
    child: Form(
      key: form,
      child: Column(
        children: [
          TextFormField(
            controller: name,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Nom'),
          ),
          if (name.text.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            TextField(
              controller: phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'N° de téléphone (facultatif)',
              ),
            ),
          ],
          const SizedBox(height: 12),
          TextFormField(
            controller: company,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: 'Société',
              labelText: 'Nom de société',
            ),
          ),
          if (company.text.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            TextField(
              controller: ice,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'ICE (facultatif)'),
            ),
          ],
          const SizedBox(height: 12),
          MultiImageInput(
            images: images,
            label: 'Photos du client (${images.length}/10)',
            onTap: pickImages,
            onRemove: (index) => setState(() => images.removeAt(index)),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: save,
              child: const Text('Enregistrer le client'),
            ),
          ),
        ],
      ),
    ),
  );
}

class SaleForm extends StatefulWidget {
  const SaleForm({
    super.key,
    required this.products,
    required this.categories,
    this.catalogFamilies = const [],
    required this.depots,
    required this.clients,
    required this.available,
    required this.onAddClient,
    required this.allowGallery,
    this.canPreviewAttachments = false,
  });
  final List<Product> products;
  final List<ProductCategory> categories;
  final List<CatalogFamily> catalogFamilies;
  final List<Depot> depots;
  final List<Client> clients;
  final int Function(String, String) available;
  final Future<Client?> Function() onAddClient;
  final bool allowGallery;
  final bool canPreviewAttachments;

  @override
  State<SaleForm> createState() => _SaleFormState();
}

class _SaleFormState extends State<SaleForm> {
  String? productId;
  String? openedProductFamilyId;
  String? depotId;
  String? clientId;
  final quantity = TextEditingController();
  final images = <Uint8List>[];
  InventoryUnit unit = InventoryUnit.piece;
  TransportCharge transportCharge = TransportCharge.none;

  Product? get selectedProduct {
    for (final product in widget.products) {
      if (product.id == productId) return product;
    }
    return null;
  }

  Product? get openedProductFamily {
    for (final product in widget.products) {
      if (product.id == openedProductFamilyId) return product;
    }
    return null;
  }

  List<Product> get catalogProducts => widget.products
      .where((product) => !product.isManufacturedVariant)
      .toList();

  List<Product> derivedFrom(Product product) => widget.products
      .where((item) => item.parentProductId == product.id)
      .toList();

  void chooseProduct(Product product) {
    final variants = derivedFrom(product);
    if (openedProductFamilyId == null && variants.isNotEmpty) {
      setState(() {
        // Selecting a manufactured base product is navigation, not a sale:
        // only one of its actual dimensions can be sold.
        openedProductFamilyId = product.id;
        productId = null;
        depotId = null;
        quantity.clear();
      });
      return;
    }
    setState(() {
      productId = product.id;
      depotId = null;
      unit = product.hoseManagedByMeter
          ? InventoryUnit.meter
          : InventoryUnit.piece;
    });
  }

  int get pieces => selectedProduct == null
      ? 0
      : piecesForQuantity(selectedProduct!, number(quantity.text), unit);

  List<InventoryUnit> get availableUnits {
    final product = selectedProduct;
    if (product?.isHose != true) return InventoryUnit.values;
    return product!.hoseManagedByMeter
        ? const [InventoryUnit.meter]
        : const [InventoryUnit.piece];
  }

  Future<void> addClient() async {
    final added = await widget.onAddClient();
    if (added != null && mounted) setState(() => clientId = added.id);
  }

  Future<void> pickImages() async {
    final available = 10 - images.length;
    if (available <= 0) return message(context, 'Maximum : 10 photos.');
    final selectedImages = widget.allowGallery
        ? await Future.wait(
            (await ImagePicker().pickMultiImage(
                  imageQuality: 82,
                  maxWidth: 1600,
                ))
                .take(available)
                .map(
                  (file) => readAcceptedImage(file, maximumBytes: 120 * 1024),
                ),
          )
        : await (() async {
            final file = await ImagePicker().pickImage(
              source: ImageSource.camera,
              imageQuality: 82,
              maxWidth: 1600,
            );
            return file == null
                ? <Uint8List?>[]
                : [await readAcceptedImage(file, maximumBytes: 120 * 1024)];
          })();
    final bytes = selectedImages.whereType<Uint8List>().toList();
    if (bytes.isEmpty) return;
    if (mounted) setState(() => images.addAll(bytes));
  }

  void save() {
    final entered = number(quantity.text);
    if (productId == null ||
        depotId == null ||
        clientId == null ||
        entered <= 0 ||
        pieces <= 0 ||
        images.isEmpty) {
      return message(
        context,
        'Prenez une photo, puis choisissez un client, un produit, un dépôt et une quantité valide.',
      );
    }
    if (pieces > widget.available(productId!, depotId!)) {
      return message(
        context,
        'La quantité demandée dépasse le stock disponible dans ce dépôt.',
      );
    }
    Navigator.pop(
      context,
      Sale(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        productId: productId!,
        depotId: depotId!,
        clientId: clientId!,
        pieces: pieces,
        quantity: entered,
        unit: unit,
        images: images,
        createdAt: DateTime.now(),
        transportCharge: transportCharge,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => FormShell(
    title: 'Vente',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: SearchChoiceField(
                label: 'Client *',
                options: _choices(
                  widget.clients,
                  (client) => client.id,
                  (client) => _partnerLabel(client.name, client.company),
                ),
                selected: {?clientId},
                allowClear: false,
                onChanged: (ids) => setState(() => clientId = ids.first),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              onPressed: addClient,
              icon: const Icon(Icons.person_add_alt_1_rounded),
              tooltip: 'Ajouter un client',
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Text(
                openedProductFamily == null
                    ? 'Produit à vendre *'
                    : 'Dimensions de ${openedProductFamily!.displayReference}',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            if (openedProductFamily != null)
              TextButton.icon(
                onPressed: () => setState(() {
                  openedProductFamilyId = null;
                  productId = null;
                  depotId = null;
                  quantity.clear();
                }),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Produits'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Visibility(
          visible: openedProductFamily == null,
          maintainState: true,
          child: CatalogProductBrowser(
            products: catalogProducts,
            categories: widget.categories,
            catalogFamilies: widget.catalogFamilies,
            buildProducts: (products) => ProductPicker(
              products: products,
              selected: productId == null ? <String>{} : {productId!},
              onTap: chooseProduct,
            ),
          ),
        ),
        if (openedProductFamily case final product?)
          ProductPicker(
            products: derivedFrom(product),
            selected: productId == null ? <String>{} : {productId!},
            onTap: chooseProduct,
          ),
        if (selectedProduct case final product?)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Produit sélectionné : ${product.displayReference}'),
          ),
        if (productId != null) ...[
          const SizedBox(height: 12),
          LiquidSelectFormField<String>(
            initialValue: depotId,
            decoration: const InputDecoration(labelText: 'Dépôt de sortie *'),
            items: widget.depots
                .map(
                  (depot) => DropdownMenuItem(
                    value: depot.id,
                    child: Text(
                      '${depot.name} (${productQuantityLabel(selectedProduct!, widget.available(productId!, depot.id))})',
                    ),
                  ),
                )
                .toList(),
            onChanged: (value) => setState(() => depotId = value),
          ),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: quantity,
                onChanged: (_) => setState(() {}),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: selectedProduct?.isHose == true
                    ? [FilteringTextInputFormatter.digitsOnly]
                    : null,
                decoration: InputDecoration(
                  labelText: selectedProduct?.isHose == true
                      ? selectedProduct!.hoseManagedByMeter
                            ? 'Longueur vendue (m) *'
                            : 'Pièces vendues *'
                      : 'Quantité vendue *',
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 145,
              child: LiquidSelectFormField<InventoryUnit>(
                initialValue: unit,
                decoration: const InputDecoration(labelText: 'Unité'),
                items: availableUnits
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: Text(value.label),
                      ),
                    )
                    .toList(),
                onChanged: selectedProduct?.isHose == true
                    ? null
                    : (value) => setState(() => unit = value!),
              ),
            ),
          ],
        ),
        if (selectedProduct != null && number(quantity.text) > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              selectedProduct?.hoseManagedByMeter == true
                  ? 'Sortie de stock : $pieces mètre(s)'
                  : selectedProduct?.isHose == true
                  ? 'Sortie de stock : $pieces pièce(s) = ${formatNumber(pieces * selectedProduct!.lengthMeters)} m'
                  : 'Sortie de stock : $pieces pièce(s)',
              style: TextStyle(
                color: _atelierMuted(context),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        const SizedBox(height: 12),
        LiquidSelectFormField<TransportCharge>(
          initialValue: transportCharge,
          decoration: const InputDecoration(labelText: 'Transport *'),
          items: TransportCharge.values
              .map(
                (value) =>
                    DropdownMenuItem(value: value, child: Text(value.label)),
              )
              .toList(),
          onChanged: (value) => setState(() => transportCharge = value!),
        ),
        const SizedBox(height: 12),
        MultiImageInput(
          images: images,
          label: widget.allowGallery
              ? 'Photos des pièces / accessoires * (${images.length}/10)'
              : 'Prendre une photo * (${images.length}/10)',
          showPreviews: widget.canPreviewAttachments,
          onPreview: widget.canPreviewAttachments
              ? () => _showTransactionPhotos(context, Future.value(List.of(images)))
              : null,
          onTap: pickImages,
          onRemove: (index) => setState(() => images.removeAt(index)),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: save,
            icon: const Icon(Icons.point_of_sale_rounded),
            label: const Text('Enregistrer la vente'),
          ),
        ),
      ],
    ),
  );
}

class _StockFormState extends State<StockForm> {
  String? selected;
  String? depotId;
  String? supplierId;
  final pieces = TextEditingController();
  final receiptNumber = TextEditingController();
  final images = <Uint8List>[];
  InventoryUnit unit = InventoryUnit.piece;
  TransportCharge transportCharge = TransportCharge.none;

  Product? get selectedProduct {
    for (final product in widget.products) {
      if (product.id == selected) return product;
    }
    return null;
  }

  double get enteredQuantity => number(pieces.text);
  int get addedPieces => selectedProduct == null
      ? 0
      : piecesForQuantity(selectedProduct!, enteredQuantity, unit);

  List<InventoryUnit> get availableUnits {
    final product = selectedProduct;
    if (product?.isHose != true) return InventoryUnit.values;
    return product!.hoseManagedByMeter
        ? const [InventoryUnit.meter]
        : const [InventoryUnit.piece];
  }

  Future<void> addSupplier() async {
    final added = await widget.onAddSupplier();
    if (added != null && mounted) setState(() => supplierId = added.id);
  }

  Future<void> pickImages() async {
    final available = 10 - images.length;
    if (available <= 0) {
      message(context, 'Vous pouvez ajouter au maximum 10 photos.');
      return;
    }
    final selectedImages = widget.allowGallery
        ? await Future.wait(
            (await ImagePicker().pickMultiImage(
                  imageQuality: 82,
                  maxWidth: 1600,
                ))
                .take(available)
                .map(
                  (file) => readAcceptedImage(file, maximumBytes: 120 * 1024),
                ),
          )
        : await (() async {
            final file = await ImagePicker().pickImage(
              source: ImageSource.camera,
              imageQuality: 82,
              maxWidth: 1600,
            );
            return file == null
                ? <Uint8List?>[]
                : [await readAcceptedImage(file, maximumBytes: 120 * 1024)];
          })();
    final newImages = selectedImages.whereType<Uint8List>().toList();
    if (newImages.isEmpty) return;
    if (mounted) setState(() => images.addAll(newImages));
  }

  @override
  void initState() {
    super.initState();
    if (widget.products.any(
      (product) => product.id == widget.initialProductId,
    )) {
      selected = widget.initialProductId;
      if (selectedProduct?.isHose == true) {
        unit = selectedProduct!.hoseManagedByMeter
            ? InventoryUnit.meter
            : InventoryUnit.piece;
      }
    }
  }

  void save() {
    final count = addedPieces;
    if (selected == null ||
        depotId == null ||
        count <= 0 ||
        supplierId == null ||
        receiptNumber.text.trim().isEmpty ||
        images.isEmpty) {
      message(
        context,
        'Ajoutez une photo, puis choisissez un produit, un fournisseur, un dépôt, une quantité valide et le n° de bon.',
      );
      return;
    }
    Navigator.pop(
      context,
      StockAddition(
        productId: selected!,
        depotId: depotId!,
        pieces: count,
        receiptNumber: receiptNumber.text.trim(),
        supplierId: supplierId,
        quantity: enteredQuantity,
        unit: unit,
        images: images,
        addedAt: DateTime.now(),
        transportCharge: transportCharge,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => FormShell(
    title: 'Achat · Ajouter au stock',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Choisissez un produit',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 10),
        CatalogProductBrowser(
          products: widget.products,
          categories: widget.categories,
          catalogFamilies: widget.catalogFamilies,
          initialProductId: widget.initialProductId,
          buildProducts: (products) => ProductPicker(
            products: products,
            selected: selected == null ? <String>{} : {selected!},
            onTap: (product) => setState(() {
              selected = product.id;
              unit = product.hoseManagedByMeter
                  ? InventoryUnit.meter
                  : InventoryUnit.piece;
            }),
          ),
        ),
        if (selectedProduct case final product?)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Produit sélectionné : ${product.displayReference}'),
          ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: SearchChoiceField(
                label: 'Fournisseur *',
                options: _choices(
                  widget.suppliers,
                  (supplier) => supplier.id,
                  (supplier) => _partnerLabel(supplier.name, supplier.company),
                ),
                selected: {?supplierId},
                allowClear: false,
                onChanged: (ids) => setState(() => supplierId = ids.first),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              onPressed: addSupplier,
              tooltip: 'Ajouter un fournisseur',
              icon: const Icon(Icons.person_add_alt_1_rounded),
            ),
          ],
        ),
        const SizedBox(height: 12),
        LiquidSelectFormField<String>(
          initialValue: depotId,
          decoration: const InputDecoration(
            labelText: 'Dépôt de destination *',
          ),
          items: widget.depots
              .map(
                (depot) =>
                    DropdownMenuItem(value: depot.id, child: Text(depot.name)),
              )
              .toList(),
          onChanged: (value) => setState(() => depotId = value),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: receiptNumber,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(labelText: 'N° de bon *'),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: pieces,
                onChanged: (_) => setState(() {}),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: selectedProduct?.isHose == true
                    ? [FilteringTextInputFormatter.digitsOnly]
                    : null,
                decoration: InputDecoration(
                  labelText: selectedProduct?.isHose == true
                      ? selectedProduct!.hoseManagedByMeter
                            ? 'Longueur à ajouter (m) *'
                            : 'Nombre de pièces à ajouter *'
                      : 'Quantité achetée *',
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 145,
              child: LiquidSelectFormField<InventoryUnit>(
                initialValue: unit,
                decoration: const InputDecoration(labelText: 'Unité'),
                items: availableUnits
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: Text(value.label),
                      ),
                    )
                    .toList(),
                onChanged: selectedProduct?.isHose == true
                    ? null
                    : (value) => setState(() => unit = value!),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        LiquidSelectFormField<TransportCharge>(
          initialValue: transportCharge,
          decoration: const InputDecoration(labelText: 'Transport *'),
          items: TransportCharge.values
              .map(
                (value) =>
                    DropdownMenuItem(value: value, child: Text(value.label)),
              )
              .toList(),
          onChanged: (value) => setState(() => transportCharge = value!),
        ),
        const SizedBox(height: 12),
        MultiImageInput(
          images: images,
          label: widget.allowGallery
              ? 'Photos des pièces / accessoires * (${images.length}/10)'
              : 'Prendre une photo * (${images.length}/10)',
          showPreviews: widget.canPreviewAttachments,
          onPreview: widget.canPreviewAttachments
              ? () => _showTransactionPhotos(context, Future.value(List.of(images)))
              : null,
          onTap: pickImages,
          onRemove: (index) => setState(() => images.removeAt(index)),
        ),
        if (selectedProduct != null) ...[
          const SizedBox(height: 16),
          Glass(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Résumé de l’ajout',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                Text(
                  selectedProduct!.hoseManagedByMeter
                      ? 'Entrée : +$addedPieces mètre(s)'
                      : selectedProduct!.isHose
                      ? 'Entrée : +$addedPieces pièce(s) = ${formatNumber(addedPieces * selectedProduct!.lengthMeters)} m'
                      : 'Entrée : +${formatQuantity(enteredQuantity, unit)} · équivaut à $addedPieces pièce(s)',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                if (!selectedProduct!.isHose)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: .14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'Le stock est conservé en pièces : ${formatQuantity(enteredQuantity, unit)} est converti en $addedPieces pièce(s) pour ce produit.',
                      style: TextStyle(
                        fontSize: 12,
                        color: _atelierForeground(context),
                      ),
                    ),
                  ),
                if (!selectedProduct!.isHose) const SizedBox(height: 4),
                if (!selectedProduct!.isHose)
                  Text(
                    'Stock après ajout : ${formatWeight((widget.stock(selectedProduct!.id) + addedPieces) * selectedProduct!.kilogramsPerPiece)}',
                  ),
                const SizedBox(height: 4),
                Text(
                  '${productQuantityLabel(selectedProduct!, widget.stock(selectedProduct!.id) + addedPieces)} au total',
                  style: TextStyle(fontSize: 12, color: _atelierMuted(context)),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: save,
            child: const Text('Ajouter au stock'),
          ),
        ),
      ],
    ),
  );
}

class _CompetitorPaymentLine {
  _CompetitorPaymentLine(this.competitorId);
  String? competitorId;
  final mode = TextEditingController();
  final amount = TextEditingController();

  void dispose() {
    mode.dispose();
    amount.dispose();
  }
}

/// The payment step is shared by purchases and sales. Each selected source
/// gets its own mode and amount, which makes split payments explicit.
class PaymentForm extends StatefulWidget {
  const PaymentForm({super.key, required this.competitors});
  final List<Competitor> competitors;

  @override
  State<PaymentForm> createState() => _PaymentFormState();
}

class _PaymentFormState extends State<PaymentForm> {
  var forageSelected = false;
  var sousseSelected = false;
  final forageMode = TextEditingController();
  final forageAmount = TextEditingController();
  final sousseMode = TextEditingController();
  final sousseAmount = TextEditingController();
  final addedCompetitors = <Competitor>[];
  final competitorLines = <_CompetitorPaymentLine>[];

  List<Competitor> get allCompetitors => [
    ...widget.competitors,
    ...addedCompetitors,
  ];

  @override
  void dispose() {
    forageMode.dispose();
    forageAmount.dispose();
    sousseMode.dispose();
    sousseAmount.dispose();
    for (final line in competitorLines) {
      line.dispose();
    }
    super.dispose();
  }

  Future<void> addCompetitor() async {
    final name = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ajouter un compétiteur'),
        content: TextField(
          controller: name,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Nom du compétiteur *'),
          onSubmitted: (value) => Navigator.pop(context, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, name.text.trim()),
            child: const Text('Ajouter'),
          ),
        ],
      ),
    );
    name.dispose();
    if (result == null || result.isEmpty) return;
    final competitor = Competitor(
      id: 'competitor-${DateTime.now().microsecondsSinceEpoch}',
      name: result,
    );
    if (!mounted) return;
    setState(() {
      addedCompetitors.add(competitor);
      competitorLines.add(_CompetitorPaymentLine(competitor.id));
    });
  }

  Widget accountPaymentFields({
    required String title,
    required TextEditingController mode,
    required TextEditingController amount,
  }) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Glass(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          TextField(
            controller: mode,
            decoration: const InputDecoration(labelText: 'Mode de paiement *'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Montant *'),
          ),
        ],
      ),
    ),
  );

  void save() {
    final allocations = <PaymentAllocation>[];
    bool addAccount(
      bool selected,
      PaymentSource source,
      TextEditingController mode,
      TextEditingController amount,
    ) {
      if (!selected) return true;
      final value = number(amount.text);
      if (mode.text.trim().isEmpty || value <= 0) return false;
      allocations.add(
        PaymentAllocation(
          source: source,
          mode: mode.text.trim(),
          amount: value,
        ),
      );
      return true;
    }

    if (!addAccount(
          forageSelected,
          PaymentSource.forageZouhour,
          forageMode,
          forageAmount,
        ) ||
        !addAccount(
          sousseSelected,
          PaymentSource.sousseUrban,
          sousseMode,
          sousseAmount,
        )) {
      return message(context, 'Indiquez le mode de paiement et le montant.');
    }
    for (final line in competitorLines) {
      final value = number(line.amount.text);
      if (line.competitorId == null ||
          line.mode.text.trim().isEmpty ||
          value <= 0) {
        return message(
          context,
          'Chaque compétiteur doit avoir un nom, un mode et un montant.',
        );
      }
      allocations.add(
        PaymentAllocation(
          source: PaymentSource.competitor,
          competitorId: line.competitorId,
          mode: line.mode.text.trim(),
          amount: value,
        ),
      );
    }
    if (allocations.isEmpty) {
      return message(context, 'Choisissez au moins une source de paiement.');
    }
    Navigator.pop(
      context,
      PaymentEntryResult(
        allocations: allocations,
        newCompetitors: addedCompetitors,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => FormShell(
    title: 'Paiement',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Vous pouvez répartir le paiement entre plusieurs sources.',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 14),
        CheckboxListTile(
          value: forageSelected,
          contentPadding: EdgeInsets.zero,
          title: const Text('Forage Zouhour'),
          onChanged: (value) => setState(() => forageSelected = value ?? false),
        ),
        if (forageSelected)
          accountPaymentFields(
            title: 'Forage Zouhour',
            mode: forageMode,
            amount: forageAmount,
          ),
        CheckboxListTile(
          value: sousseSelected,
          contentPadding: EdgeInsets.zero,
          title: const Text('Sousse Urban'),
          onChanged: (value) => setState(() => sousseSelected = value ?? false),
        ),
        if (sousseSelected)
          accountPaymentFields(
            title: 'Sousse Urban',
            mode: sousseMode,
            amount: sousseAmount,
          ),
        const SizedBox(height: 12),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Paiement par compétiteur',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            TextButton.icon(
              onPressed: addCompetitor,
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('Ajouter compétiteur'),
            ),
          ],
        ),
        ...competitorLines.asMap().entries.map((entry) {
          final index = entry.key;
          final line = entry.value;
          return Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Glass(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: LiquidSelectFormField<String>(
                          initialValue: line.competitorId,
                          decoration: const InputDecoration(
                            labelText: 'Compétiteur *',
                          ),
                          items: allCompetitors
                              .map(
                                (competitor) => DropdownMenuItem(
                                  value: competitor.id,
                                  child: Text(competitor.name),
                                ),
                              )
                              .toList(),
                          onChanged: (value) =>
                              setState(() => line.competitorId = value),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Retirer',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => setState(() {
                          competitorLines.removeAt(index).dispose();
                        }),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: line.mode,
                    decoration: const InputDecoration(
                      labelText: 'Mode de paiement *',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: line.amount,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Montant *'),
                  ),
                ],
              ),
            ),
          );
        }),
        TextButton.icon(
          onPressed: allCompetitors.isEmpty
              ? addCompetitor
              : () => setState(
                  () => competitorLines.add(_CompetitorPaymentLine(null)),
                ),
          icon: const Icon(Icons.add_circle_outline_rounded),
          label: const Text('Ajouter un paiement compétiteur'),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: save,
            icon: const Icon(Icons.payments_rounded),
            label: const Text('Confirmer le paiement'),
          ),
        ),
      ],
    ),
  );
}

class MachineForm extends StatefulWidget {
  const MachineForm({
    super.key,
    required this.categories,
    required this.products,
    required this.users,
    required this.onUserAdded,
    required this.canManageUsers,
    required this.canCreateTemporary,
    required this.allowGallery,
    required this.depots,
    required this.available,
  });
  final List<ProductCategory> categories;
  final List<Product> products;
  final List<AppUser> users;
  final Future<AppUser> Function(AppUser) onUserAdded;
  final bool canManageUsers;
  final bool canCreateTemporary;
  final bool allowGallery;
  final List<Depot> depots;
  final int Function(String, String) available;
  @override
  State<MachineForm> createState() => _MachineFormState();
}

class _MachineFormState extends State<MachineForm> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController();
  final copies = TextEditingController(text: '1');
  final plannedPieces = TextEditingController();
  final temporaryInputPieces = TextEditingController();
  final hopperPieces = TextEditingController();
  final operators = <String>{};
  String? categoryId;
  String? outputId;
  String? temporaryInputProductId;
  String? temporarySourceDepotId;
  List<Uint8List?> unitImages = [null];
  MachineType type = MachineType.standard;
  bool temporary = false;
  DateTime? deadline;
  late final List<AppUser> availableUsers;

  @override
  void initState() {
    super.initState();
    // This form stays open while the administrator creates an operator.
    // Keep a local list so that the new operator becomes selectable
    // immediately, without waiting for the parent page to be rebuilt.
    availableUsers = List<AppUser>.of(widget.users);
  }

  List<Product> get manufacturedProducts => widget.products
      .where((product) => product.isManufacturedTemplate)
      .toList();

  List<Product> get temporaryMaterials => widget.products
      .where(
        (product) =>
            product.canBeUsedInMachine &&
            (widget.categories
                .where((category) => category.id == categoryId)
                .expand((category) => category.productIds)
                .contains(product.id)),
      )
      .toList();

  void syncUnitImages() {
    final count = int.tryParse(copies.text) ?? 1;
    unitImages = List.generate(
      count,
      (index) => index < unitImages.length ? unitImages[index] : null,
    );
  }

  Future<void> pickUnitImage(int index) async {
    final file = await ImagePicker().pickImage(
      source: widget.allowGallery ? ImageSource.gallery : ImageSource.camera,
      imageQuality: 82,
      maxWidth: 1600,
    );
    if (file != null) {
      final bytes = await readAcceptedImage(file, maximumBytes: 600 * 1024);
      if (!mounted) return;
      if (bytes == null) {
        return message(
          context,
          'Cette image est trop grande. Choisissez-en une autre.',
        );
      }
      setState(() => unitImages[index] = bytes);
    }
  }

  Future<void> selectDeadline() async {
    final value = await showDatePicker(
      context: context,
      initialDate: deadline ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (value != null && mounted) setState(() => deadline = value);
  }

  Future<void> addUser() async {
    if (!widget.canManageUsers) return;
    final user = await Navigator.push<AppUser>(
      context,
      MaterialPageRoute(builder: (_) => const UserForm()),
    );
    if (user != null && mounted) {
      final created = await widget.onUserAdded(user);
      if (!mounted) return;
      if (!created.isOperator) {
        message(
          context,
          'Seul un utilisateur avec le rôle Opérateur peut être affecté à une machine.',
        );
        return;
      }
      setState(() {
        if (!availableUsers.any((item) => item.id == created.id)) {
          availableUsers.add(created);
        }
        operators.add(created.id);
      });
    }
  }

  void save() {
    if (!(form.currentState?.validate() ?? false)) return;
    syncUnitImages();
    final missing = <String>[
      if (unitImages.any((image) => image == null))
        'photo de chaque exemplaire',
      if (categoryId == null) 'catégorie',
      if (outputId == null) 'produit fabriqué',
      if (!temporary && operators.isEmpty) 'opérateur',
      if (temporary && deadline == null) 'date de fin',
      if (temporary && (int.tryParse(plannedPieces.text) ?? 0) <= 0)
        'quantité à recevoir',
      if (temporary && temporaryInputProductId == null) 'matière première',
      if (temporary && temporarySourceDepotId == null) 'dépôt de départ',
      if (temporary && (int.tryParse(temporaryInputPieces.text) ?? 0) <= 0)
        'quantité de matière première envoyée',
      if (temporary &&
          type == MachineType.roulage &&
          (int.tryParse(hopperPieces.text) ?? 0) <= 0)
        'tôles par cadous',
    ];
    if (missing.isNotEmpty) {
      message(context, 'Il manque : ${missing.join(', ')}.');
      return;
    }
    if (temporary &&
        int.parse(temporaryInputPieces.text) >
            widget.available(
              temporaryInputProductId!,
              temporarySourceDepotId!,
            )) {
      message(
        context,
        'La quantité de matière première dépasse le stock disponible dans ce dépôt.',
      );
      return;
    }
    Navigator.pop(
      context,
      FactoryMachine(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: name.text.trim(),
        type: type,
        categoryId: categoryId ?? '',
        outputId: outputId!,
        units: List.generate(
          temporary ? 1 : int.parse(copies.text),
          (index) => MachineUnit(number: index + 1, image: unitImages[index]),
        ),
        operatorIds: operators.toList(),
        image: unitImages.first,
        temporary: temporary,
        deadline: deadline,
        plannedPieces: temporary ? int.parse(plannedPieces.text) : null,
        hopperPieces: temporary && type == MachineType.roulage
            ? int.parse(hopperPieces.text)
            : null,
        temporaryInputProductId: temporary ? temporaryInputProductId : null,
        temporarySourceDepotId: temporary ? temporarySourceDepotId : null,
        temporaryInputPieces: temporary
            ? int.parse(temporaryInputPieces.text)
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FormShell(
      title: 'Ajouter une machine',
      child: Form(
        key: form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.canCreateTemporary)
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Machine normale')),
                  ButtonSegment(
                    value: true,
                    label: Text('Travail externe temporaire'),
                  ),
                ],
                selected: {temporary},
                onSelectionChanged: (value) =>
                    setState(() => temporary = value.first),
              ),
            const SizedBox(height: 14),
            TextFormField(
              controller: name,
              decoration: const InputDecoration(
                labelText: 'Nom de la machine *',
              ),
              validator: required,
            ),
            const SizedBox(height: 12),
            if (!temporary) ...[
              Text(
                'Chaque exemplaire a sa propre photo et sa propre carte.',
                style: TextStyle(color: _atelierMuted(context)),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: copies,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Nombre d’exemplaires *',
                ),
                validator: positive,
                onChanged: (_) => setState(syncUnitImages),
              ),
              const SizedBox(height: 12),
              ...List.generate(
                unitImages.length,
                (index) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: ImageInput(
                    bytes: unitImages[index],
                    label: widget.allowGallery
                        ? 'Photo de l’exemplaire n°${index + 1} * (galerie)'
                        : 'Photo de l’exemplaire n°${index + 1} * (caméra)',
                    onTap: () => pickUnitImage(index),
                  ),
                ),
              ),
            ] else ...[
              Text(
                'À utiliser quand des pièces sont envoyées chez un voisin. Une photo est requise ; le stock ne sera crédité qu’après validation.',
                style: TextStyle(color: _atelierMuted(context)),
              ),
              const SizedBox(height: 12),
              ImageInput(
                bytes: unitImages.first,
                label: widget.allowGallery
                    ? 'Photo du travail externe * (galerie)'
                    : 'Photo du travail externe * (caméra)',
                onTap: () => pickUnitImage(0),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: plannedPieces,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Quantité attendue au retour *',
                ),
                validator: positive,
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: selectDeadline,
                icon: const Icon(Icons.event_outlined),
                label: Text(
                  deadline == null
                      ? 'Choisir la date de fin *'
                      : 'Fin prévue : ${dateText(deadline!)}',
                ),
              ),
            ],
            const SizedBox(height: 14),
            SegmentedButton<MachineType>(
              segments: const [
                ButtonSegment(
                  value: MachineType.standard,
                  label: Text('Standard'),
                ),
                ButtonSegment(
                  value: MachineType.roulage,
                  label: Text('Roulage'),
                ),
              ],
              selected: {type},
              onSelectionChanged: (v) => setState(() => type = v.first),
            ),
            if (temporary && type == MachineType.roulage) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: hopperPieces,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Nombre de tôles par cadous *',
                ),
                validator: positive,
              ),
            ],
            const SizedBox(height: 20),
            Text(
              temporary
                  ? 'Catégorie de la matière première *'
                  : 'Catégorie traitée *',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            CategoryPicker(
              categories: widget.categories,
              selected: categoryId,
              onTap: (category) => setState(() {
                categoryId = category.id;
                temporaryInputProductId = null;
                temporarySourceDepotId = null;
              }),
            ),
            const SizedBox(height: 6),
            Text(
              temporary
                  ? 'Choisissez ensuite la matière envoyée : elle sera déduite du stock à la validation.'
                  : 'Le travailleur choisira le produit de cette catégorie au démarrage.',
              style: TextStyle(fontSize: 12, color: _atelierMuted(context)),
            ),
            if (temporary && categoryId != null) ...[
              const SizedBox(height: 16),
              const Text(
                'Matière première envoyée *',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              if (temporaryMaterials.isEmpty)
                const Text(
                  'Cette catégorie ne contient aucune matière première utilisable.',
                  style: TextStyle(
                    color: Color(0xFFB45309),
                    fontWeight: FontWeight.w700,
                  ),
                )
              else
                ProductPicker(
                  products: temporaryMaterials,
                  selected: temporaryInputProductId == null
                      ? <String>{}
                      : {temporaryInputProductId!},
                  onTap: (product) => setState(() {
                    temporaryInputProductId = product.id;
                    temporarySourceDepotId = null;
                  }),
                ),
              if (temporaryInputProductId != null) ...[
                const SizedBox(height: 12),
                LiquidSelectFormField<String>(
                  initialValue: temporarySourceDepotId,
                  decoration: const InputDecoration(
                    labelText: 'Dépôt de départ *',
                  ),
                  items: widget.depots
                      .map(
                        (depot) => DropdownMenuItem(
                          value: depot.id,
                          child: Text(
                            '${depot.name} (${widget.available(temporaryInputProductId!, depot.id)} pièces)',
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) =>
                      setState(() => temporarySourceDepotId = value),
                ),
              ],
              if (temporaryInputProductId != null &&
                  temporarySourceDepotId != null) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: temporaryInputPieces,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: 'Quantité envoyée *',
                    helperText:
                        'Disponible : ${widget.available(temporaryInputProductId!, temporarySourceDepotId!)} pièce(s)',
                  ),
                  validator: positive,
                ),
              ],
            ],
            const SizedBox(height: 18),
            const Text(
              'Produit fabriqué par la machine *',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            if (manufacturedProducts.isEmpty)
              const Text(
                'Créez d’abord un produit marqué « fabriqué en usine », puis sélectionnez-le ici comme résultat de cette machine.',
                style: TextStyle(
                  color: Color(0xFFB45309),
                  fontWeight: FontWeight.w700,
                ),
              )
            else
              ProductPicker(
                products: manufacturedProducts,
                selected: outputId == null ? <String>{} : {outputId!},
                onTap: (product) => setState(() => outputId = product.id),
              ),
            const SizedBox(height: 18),
            if (!temporary)
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Opérateur responsable *',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  if (widget.canManageUsers)
                    TextButton.icon(
                      onPressed: addUser,
                      icon: const Icon(Icons.person_add_alt_1),
                      label: const Text('Ajouter'),
                    ),
                ],
              ),
            if (!temporary)
              ...availableUsers
                  .where((u) => u.isOperator)
                  .map(
                    (u) => CheckboxListTile(
                      value: operators.contains(u.id),
                      contentPadding: EdgeInsets.zero,
                      title: Text(u.fullName),
                      subtitle: Text('@${u.username}'),
                      onChanged: (v) => setState(
                        () => v == true
                            ? operators.add(u.id)
                            : operators.remove(u.id),
                      ),
                    ),
                  ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: save,
                child: Text(
                  temporary
                      ? 'Envoyer à la validation'
                      : 'Enregistrer la machine',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ProductPicker extends StatelessWidget {
  const ProductPicker({
    super.key,
    required this.products,
    required this.selected,
    required this.onTap,
  });
  final List<Product> products;
  final Set<String> selected;
  final ValueChanged<Product> onTap;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 10,
    runSpacing: 10,
    children: products.map((product) {
      final isSelected = selected.contains(product.id);
      final scheme = Theme.of(context).colorScheme;
      return SizedBox(
        width: 145,
        child: InkWell(
          onTap: () => onTap(product),
          borderRadius: BorderRadius.circular(18),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: isSelected
                  ? scheme.primaryContainer
                  : scheme.surfaceContainerHigh.withValues(alpha: .56),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: isSelected ? scheme.primary : scheme.outline,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: AnimatedScale(
              duration: const Duration(milliseconds: 220),
              scale: isSelected ? 1.02 : 1,
              child: Column(
                children: [
                  ProductImage(product: product, height: 68),
                  const SizedBox(height: 5),
                  Text(
                    product.displayReference,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }).toList(),
  );
}

class CatalogProductBrowser extends StatefulWidget {
  const CatalogProductBrowser({
    super.key,
    required this.products,
    required this.categories,
    this.catalogFamilies = const [],
    required this.buildProducts,
    this.initialProductId,
    this.showEmptyCategories = false,
  });

  final List<Product> products;
  final List<ProductCategory> categories;
  final List<CatalogFamily> catalogFamilies;
  final Widget Function(List<Product> products) buildProducts;
  final String? initialProductId;
  final bool showEmptyCategories;

  @override
  State<CatalogProductBrowser> createState() => _CatalogProductBrowserState();
}

class _CatalogProductBrowserState extends State<CatalogProductBrowser> {
  String? familyId;
  String? categoryId;

  List<_CatalogGroup> get groups => _catalogGroups(
    widget.categories,
    widget.catalogFamilies,
    products: widget.products,
  );

  @override
  void initState() {
    super.initState();
    final product = widget.products
        .where((item) => item.id == widget.initialProductId)
        .firstOrNull;
    if (product == null) return;
    for (final group in groups) {
      final section = group.sections
          .where(
            (item) => item.productIds.contains(_catalogMembershipId(product)),
          )
          .firstOrNull;
      if (section == null) continue;
      familyId = group.id;
      categoryId = section.category.id;
      break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final availableIds = widget.products.map(_catalogMembershipId).toSet();
    final allGroups = groups;
    final family = allGroups.where((group) => group.id == familyId).firstOrNull;
    if (family == null) {
      return _catalogCards([
        for (final group in allGroups)
          if (widget.showEmptyCategories ||
              group.sections.any(
                (section) => section.productIds.any(availableIds.contains),
              ))
            _CatalogGroupCard(
              name: group.name,
              preview: group.sections
                  .take(2)
                  .map((section) => section.category.name)
                  .toList(),
              onTap: () => setState(() {
                familyId = group.id;
                categoryId = null;
              }),
            ),
      ]);
    }
    final section = family.sections
        .where((item) => item.category.id == categoryId)
        .firstOrNull;
    final products = section == null
        ? const <Product>[]
        : widget.products
              .where(
                (item) =>
                    section.productIds.contains(_catalogMembershipId(item)),
              )
              .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton.icon(
          icon: const Icon(Icons.arrow_back_rounded),
          label: Text(section == null ? 'Familles' : 'Catégories'),
          onPressed: () => setState(() {
            if (section == null) familyId = null;
            categoryId = null;
          }),
        ),
        Text(
          section == null
              ? family.name
              : '${family.name} · ${section.category.name}',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 10),
        if (section != null)
          if (products.isEmpty)
            const Text('Aucun produit dans cette catégorie.')
          else
            widget.buildProducts(products)
        else if (family.sections.isEmpty)
          const Text('Aucune catégorie dans cette famille.')
        else
          _catalogCards([
            for (final item in family.sections)
              _CatalogGroupCard(
                name: item.category.name,
                onTap: () => setState(() => categoryId = item.category.id),
              ),
          ]),
      ],
    );
  }

  Widget _catalogCards(List<_CatalogGroupCard> cards) => cards.isEmpty
      ? const Text('Aucun produit disponible.')
      : LayoutBuilder(
          builder: (context, constraints) {
            const gap = 12.0;
            final width = min(144.0, (constraints.maxWidth - gap) / 2);
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final card in cards) SizedBox(width: width, child: card),
              ],
            );
          },
        );
}

class _CatalogGroupCard extends StatelessWidget {
  const _CatalogGroupCard({
    required this.name,
    required this.onTap,
    this.preview = const [],
  });

  final String name;
  final List<String> preview;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(16),
    child: Column(
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: Glass(
            radius: 22,
            accent: AppPalette.primary,
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const _AtelierIcon(Icons.folder_outlined, size: 38),
                for (final label in preview)
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      style: TextStyle(
                        color: _atelierMuted(context),
                        fontSize: 12,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 5),
        Text(
          name,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ],
    ),
  );
}

class CategoryPicker extends StatelessWidget {
  const CategoryPicker({
    super.key,
    required this.categories,
    required this.selected,
    required this.onTap,
  });
  final List<ProductCategory> categories;
  final String? selected;
  final ValueChanged<ProductCategory> onTap;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 10,
    runSpacing: 10,
    children: categories.map((category) {
      final isSelected = category.id == selected;
      return SizedBox(
        width: 145,
        child: _LiquidTapTarget(
          radius: 18,
          selected: isSelected,
          accent: isSelected ? AppPalette.primary : AppPalette.secondary,
          onTap: () => onTap(category),
          child: Padding(
            padding: const EdgeInsets.all(7),
            child: Column(
              children: [
                CategoryImage(category: category, size: 68),
                const SizedBox(height: 5),
                Text(
                  category.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ),
      );
    }).toList(),
  );
}

class StartOperation extends StatefulWidget {
  const StartOperation({
    super.key,
    required this.machine,
    required this.available,
    required this.user,
    required this.category,
    required this.products,
    required this.depots,
    required this.unitNumber,
  });
  final FactoryMachine machine;
  final int Function(String, String) available;
  final AppUser user;
  final ProductCategory? category;
  final List<Product> products;
  final List<Depot> depots;
  final int unitNumber;
  @override
  State<StartOperation> createState() => _StartOperationState();
}

class _StartOperationState extends State<StartOperation> {
  final pieces = TextEditingController();
  final hopper = TextEditingController();
  String? productId;
  String? depotId;
  List<Product> get categoryProducts => widget.products
      .where(
        (product) =>
            product.canBeUsedInMachine &&
            (widget.category?.productIds.contains(product.id) ?? false),
      )
      .toList();

  Product? get outputProduct {
    for (final product in widget.products) {
      if (product.id == widget.machine.outputId) return product;
    }
    return null;
  }

  void start() {
    final n = int.tryParse(pieces.text);
    final h = int.tryParse(hopper.text);
    if (n == null ||
        n <= 0 ||
        productId == null ||
        depotId == null ||
        n > widget.available(productId!, depotId!) ||
        (widget.machine.type == MachineType.roulage && (h == null || h <= 0))) {
      message(
        context,
        'Vérifiez la quantité disponible et la capacité du chariot.',
      );
      return;
    }
    Navigator.pop(
      context,
      Operation(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        machineId: widget.machine.id,
        operatorId: widget.user.id,
        pieces: n,
        productId: productId!,
        sourceDepotId: depotId!,
        machineUnitNumber: widget.unitNumber,
        hopperPieces: widget.machine.type == MachineType.roulage ? h : null,
        startedAt: DateTime.now(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => FormShell(
    title: 'Démarrer une opération',
    subtitle: widget.machine.name,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Choisissez le produit de la catégorie puis la quantité à travailler.',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 14),
        if (widget.category != null) ...[
          Glass(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                CategoryImage(category: widget.category!, size: 50),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Catégorie : ${widget.category!.name}',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
        Glass(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const Icon(Icons.inventory_2_outlined, color: Color(0xFF15803D)),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  'Produit qui sera fabriqué : ${outputProduct?.displayReference ?? 'Non défini'}',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (categoryProducts.isEmpty)
          const Text(
            'Cette catégorie ne contient encore aucun produit.',
            style: TextStyle(
              color: Color(0xFFB45309),
              fontWeight: FontWeight.w800,
            ),
          )
        else ...[
          const Text(
            'Produit à travailler *',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          ProductPicker(
            products: categoryProducts,
            selected: productId == null ? <String>{} : {productId!},
            onTap: (product) => setState(() {
              productId = product.id;
              depotId = null;
            }),
          ),
          if (productId != null) ...[
            const SizedBox(height: 12),
            LiquidSelectFormField<String>(
              initialValue: depotId,
              decoration: const InputDecoration(
                labelText: 'Dépôt où se trouve le produit *',
              ),
              items: widget.depots
                  .map(
                    (depot) => DropdownMenuItem(
                      value: depot.id,
                      child: Text(
                        '${depot.name} (${widget.available(productId!, depot.id)} pièces)',
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => depotId = value),
            ),
          ],
          if (productId != null && depotId != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Stock disponible dans ce dépôt : ${widget.available(productId!, depotId!)} pièce(s)',
                style: TextStyle(color: _atelierMuted(context)),
              ),
            ),
        ],
        const SizedBox(height: 12),
        Glass(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              const Icon(Icons.precision_manufacturing_outlined),
              const SizedBox(width: 8),
              Text(
                'Exemplaire n°${widget.unitNumber}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: pieces,
          onChanged: (_) => setState(() {}),
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            labelText: 'Nombre de pièces à travailler *',
          ),
        ),
        if (widget.machine.type == MachineType.roulage) ...[
          const SizedBox(height: 12),
          TextField(
            controller: hopper,
            onChanged: (_) => setState(() {}),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Nombre de tôles dans le cadous *',
            ),
          ),
          if ((int.tryParse(hopper.text) ?? 0) > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Longueur calculée du cadous : ${formatNumber((int.parse(hopper.text)) * Operation.hopperSheetLengthMeters)} m '
                '(${hopper.text} tôle(s) × ${formatNumber(Operation.hopperSheetLengthMeters)} m)',
                style: TextStyle(
                  color: _atelierMuted(context),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          if ((int.tryParse(hopper.text) ?? 0) > 0 &&
              (int.tryParse(pieces.text) ?? 0) > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Avec ${pieces.text} tôle(s) et ${hopper.text} tôle(s) par cadous : maximum ${int.parse(pieces.text) ~/ int.parse(hopper.text)} cadous, avec ${int.parse(pieces.text) % int.parse(hopper.text)} tôle(s) restante(s).',
                style: const TextStyle(
                  color: Color(0xFF15803D),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
        const SizedBox(height: 14),
        Text(
          'Le stock sera réservé immédiatement et l’opération sera affichée comme « en cours ».',
          style: TextStyle(fontSize: 12, color: _atelierMuted(context)),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: start,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Démarrer le travail'),
          ),
        ),
      ],
    ),
  );
}

class Completion {
  const Completion({
    required this.outputPieces,
    this.image,
    required this.finishedAt,
    required this.outputDepotId,
    required this.scrapPieces,
    required this.remainderPieces,
    this.remainderImage,
    this.remainderDepotId,
    this.scrapImage,
    this.scrapDepotId,
  });
  final int outputPieces;
  final Uint8List? image;
  final DateTime finishedAt;
  final Uint8List? remainderImage;
  final String outputDepotId;
  final String? remainderDepotId;
  final int scrapPieces;
  final int remainderPieces;
  final Uint8List? scrapImage;
  final String? scrapDepotId;
}

class FinishOperation extends StatefulWidget {
  const FinishOperation({
    super.key,
    required this.operation,
    required this.machine,
    required this.output,
    required this.depots,
  });
  final Operation operation;
  final FactoryMachine machine;
  final Product output;
  final List<Depot> depots;
  @override
  State<FinishOperation> createState() => _FinishOperationState();
}

class _FinishOperationState extends State<FinishOperation> {
  final pieces = TextEditingController();
  final remainderPieces = TextEditingController(text: '0');
  final scrapPieces = TextEditingController(text: '0');
  Uint8List? image;
  Uint8List? remainderImage;
  Uint8List? scrapImage;
  String? outputDepotId;
  String? remainderDepotId;
  String? scrapDepotId;
  int step = 0;

  Future<void> pick(ValueChanged<Uint8List> onPicked) async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 82,
      maxWidth: 1600,
    );
    if (file != null) {
      final bytes = await readAcceptedImage(file, maximumBytes: 600 * 1024);
      if (!mounted) return;
      if (bytes == null) {
        return message(
          context,
          'Cette image est trop grande. Choisissez-en une autre.',
        );
      }
      onPicked(bytes);
    }
  }

  void finish() {
    final n = int.tryParse(pieces.text);
    final remainder = int.tryParse(remainderPieces.text) ?? -1;
    final scrap = int.tryParse(scrapPieces.text) ?? 0;
    final isRoulage = widget.machine.type == MachineType.roulage;
    final hopperSize = widget.operation.hopperPieces;
    final used = n == null
        ? -1
        : isRoulage
        ? n * (hopperSize ?? 0)
        : n;
    final balanced =
        n != null &&
        n >= 0 &&
        used >= 0 &&
        used + remainder + scrap == widget.operation.pieces;
    final outputComplete = n == 0 || (outputDepotId != null && image != null);
    final remainderComplete =
        remainder == 0 || (remainderDepotId != null && remainderImage != null);
    final scrapComplete =
        scrap == 0 || (scrapDepotId != null && scrapImage != null);
    if (!balanced ||
        remainder < 0 ||
        scrap < 0 ||
        !outputComplete ||
        !remainderComplete ||
        !scrapComplete) {
      setState(() => step = 0);
      message(
        context,
        'Les calculs ou les informations de dépôt sont incomplets. Revenez aux pages : fabriqué + restant + déchets doit égaler ${widget.operation.pieces}.',
      );
      return;
    }
    Navigator.pop(
      context,
      Completion(
        outputPieces: n,
        image: image,
        finishedAt: DateTime.now(),
        outputDepotId: outputDepotId ?? 'general-depot',
        scrapPieces: scrap,
        remainderPieces: remainder,
        remainderImage: remainderImage,
        remainderDepotId: remainderDepotId,
        scrapImage: scrapImage,
        scrapDepotId: scrapDepotId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final made = int.tryParse(pieces.text) ?? 0;
    final remaining = int.tryParse(remainderPieces.text) ?? 0;
    final waste = int.tryParse(scrapPieces.text) ?? 0;
    final used = widget.machine.type == MachineType.roulage
        ? made * (widget.operation.hopperPieces ?? 0)
        : made;
    final difference = widget.operation.pieces - used - remaining - waste;
    final body = switch (step) {
      0 => Column(
        children: [
          TextField(
            controller: pieces,
            onChanged: (_) => setState(() {}),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: widget.machine.type == MachineType.roulage
                  ? 'Nombre de cadous fabriqués *'
                  : 'Quantité de ${widget.output.name} fabriquée *',
            ),
          ),
          if (made > 0) ...[
            const SizedBox(height: 12),
            LiquidSelectFormField<String>(
              initialValue: outputDepotId,
              decoration: InputDecoration(
                labelText: 'Dépôt du produit fini ${widget.output.name} *',
              ),
              items: widget.depots
                  .map(
                    (depot) => DropdownMenuItem(
                      value: depot.id,
                      child: Text(depot.name),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => outputDepotId = value),
            ),
            const SizedBox(height: 14),
            ImageInput(
              bytes: image,
              label: 'Photo du produit fabriqué *',
              onTap: () => pick((value) => image = value),
            ),
          ] else
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                'Indiquez une quantité fabriquée supérieure à zéro pour choisir son dépôt et sa photo.',
                style: TextStyle(color: _atelierMuted(context)),
              ),
            ),
        ],
      ),
      1 => Column(
        children: [
          const Text(
            'Déclarez uniquement les pièces non travaillées. Elles retourneront au stock de matière première.',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: remainderPieces,
            onChanged: (_) => setState(() {}),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Pièces restantes non travaillées',
            ),
          ),
          if (remaining > 0) ...[
            const SizedBox(height: 12),
            LiquidSelectFormField<String>(
              initialValue: remainderDepotId,
              decoration: const InputDecoration(
                labelText: 'Dépôt qui reçoit les pièces restantes *',
              ),
              items: widget.depots
                  .map(
                    (depot) => DropdownMenuItem(
                      value: depot.id,
                      child: Text(depot.name),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => remainderDepotId = value),
            ),
            const SizedBox(height: 14),
            ImageInput(
              bytes: remainderImage,
              label: 'Photo des pièces dans le dépôt *',
              onTap: () => pick((value) => remainderImage = value),
            ),
          ],
        ],
      ),
      _ => Column(
        children: [
          const Text(
            'Les déchets sont stockés comme un produit « Déchets » séparé.',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: scrapPieces,
            onChanged: (_) => setState(() {}),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Quantité de déchets'),
          ),
          if (waste > 0) ...[
            const SizedBox(height: 12),
            LiquidSelectFormField<String>(
              initialValue: scrapDepotId,
              decoration: const InputDecoration(
                labelText: 'Dépôt qui reçoit les déchets *',
              ),
              items: widget.depots
                  .map(
                    (depot) => DropdownMenuItem(
                      value: depot.id,
                      child: Text(depot.name),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => scrapDepotId = value),
            ),
            const SizedBox(height: 14),
            ImageInput(
              bytes: scrapImage,
              label: 'Photo des déchets dans le dépôt *',
              onTap: () => pick((value) => scrapImage = value),
            ),
          ],
          const SizedBox(height: 14),
          Glass(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(
                  difference == 0
                      ? Icons.task_alt_rounded
                      : Icons.calculate_outlined,
                  color: difference == 0
                      ? const Color(0xFF15803D)
                      : const Color(0xFFB45309),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Fabriqué : $used + restant : $remaining + déchets : $waste = ${used + remaining + waste} sur ${widget.operation.pieces}${difference == 0 ? ' · équilibre exact' : ' · écart : $difference'}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    };
    return FormShell(
      title: 'Terminer l’opération · ${step + 1}/3',
      subtitle: widget.machine.name,
      child: Column(
        children: [
          Text(
            widget.machine.type == MachineType.roulage
                ? 'Matière initiale : ${widget.operation.pieces} tôles · ${widget.operation.hopperPieces} tôles par cadous'
                : 'Quantité initiale : ${widget.operation.pieces} pièce(s)',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 16),
          body,
          const SizedBox(height: 20),
          Row(
            children: [
              if (step > 0)
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() => step--),
                    child: const Text('Précédent'),
                  ),
                ),
              if (step > 0) const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: step == 2 ? finish : () => setState(() => step++),
                  icon: Icon(
                    step == 2
                        ? Icons.task_alt_rounded
                        : Icons.arrow_forward_rounded,
                  ),
                  label: Text(step == 2 ? 'Vérifier et terminer' : 'Continuer'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class Receipt extends StatelessWidget {
  const Receipt({
    super.key,
    required this.operation,
    required this.machine,
    required this.output,
    required this.operator,
  });
  final Operation operation;
  final FactoryMachine machine;
  final Product output;
  final AppUser operator;
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Row(
      children: [
        Icon(Icons.receipt_long_rounded, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        const Text('Bon de production'),
      ],
    ),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            machine.name,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
          ),
          const Divider(),
          Text('Opérateur : ${operator.fullName}'),
          Text('Début : ${dateText(operation.startedAt)}'),
          Text('Fin : ${dateText(operation.finishedAt!)}'),
          Text('Matière réservée : ${operation.pieces} pièce(s)'),
          if (operation.hopperPieces != null)
            Text(
              'Cadous : ${operation.hopperPieces} tôle(s) · '
              '${formatNumber(operation.hopperLengthMeters!)} m',
            ),
          Text('Produit fini : ${output.name}'),
          Text(
            operation.hopperPieces == null
                ? 'Fabriquées : ${operation.outputPieces} · restantes : ${operation.remainderPieces} · déchets : ${operation.scrapPieces}'
                : 'Cadous fabriqués : ${operation.outputPieces} · tôles restantes : ${operation.remainderPieces} · déchets : ${operation.scrapPieces}',
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          if (operation.needsReview) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _atelierWarning(context).withValues(alpha: .16),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 18,
                    color: _atelierWarning(context),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${operation.pieces - (operation.outputPieces ?? 0)} pièce(s) restante(s) photographiée(s) et envoyée(s) au contrôle.',
                      style: TextStyle(
                        color: _atelierWarning(context),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (operation.finalImage != null) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.memory(
                operation.finalImage!,
                height: 150,
                width: 270,
                fit: BoxFit.cover,
              ),
            ),
          ],
          if (operation.remainderImage != null) ...[
            const SizedBox(height: 10),
            const Text(
              'Photo des pièces restantes',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 5),
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.memory(
                operation.remainderImage!,
                height: 120,
                width: 270,
                fit: BoxFit.cover,
              ),
            ),
          ],
          if (operation.scrapImage != null) ...[
            const SizedBox(height: 10),
            const Text(
              'Photo des déchets',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 5),
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.memory(
                operation.scrapImage!,
                height: 120,
                width: 270,
                fit: BoxFit.cover,
              ),
            ),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Fermer'),
      ),
    ],
  );
}

class UserDetailsPage extends StatefulWidget {
  const UserDetailsPage({
    super.key,
    required this.user,
    required this.canManage,
    required this.loadSessions,
  });
  final AppUser user;
  final bool canManage;
  final Future<List<UserSession>> Function(String) loadSessions;
  @override
  State<UserDetailsPage> createState() => _UserDetailsPageState();
}

class _UserDetailsPageState extends State<UserDetailsPage> {
  late Set<UserRole> roles;
  late Set<AppPage> pages;
  late Set<AppPage> writablePages;
  late UserStatus status;
  DateTime? leaveUntil;
  late bool canExport;
  String? loginStartTime;
  String? loginEndTime;
  String? pendingPassword;
  late Future<List<UserSession>> sessions;

  @override
  void initState() {
    super.initState();
    roles = {...widget.user.roles};
    pages = {...widget.user.allowedPages};
    writablePages = {...widget.user.writablePages};
    status = widget.user.status;
    leaveUntil = widget.user.leaveUntil;
    canExport = widget.user.canExport;
    loginStartTime = widget.user.loginStartTime;
    loginEndTime = widget.user.loginEndTime;
    sessions = widget.loadSessions(widget.user.id);
  }

  Future<void> setLeave() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: leaveUntil ?? DateTime.now().add(const Duration(days: 7)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (selected != null) {
      setState(() {
        status = UserStatus.onLeave;
        leaveUntil = selected;
      });
    }
  }

  Future<void> setLoginTime(bool isStart) async {
    final current = isStart ? loginStartTime : loginEndTime;
    final parts = current?.split(':');
    final initial = parts?.length == 3
        ? TimeOfDay(hour: int.parse(parts![0]), minute: int.parse(parts[1]))
        : const TimeOfDay(hour: 8, minute: 0);
    final value = await showTimePicker(context: context, initialTime: initial);
    if (value == null) return;
    final text =
        '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}:00';
    setState(() {
      if (isStart) {
        loginStartTime = text;
      } else {
        loginEndTime = text;
      }
    });
  }

  String displayTime(String? value) =>
      value == null ? 'Non défini' : value.substring(0, 5);

  Future<void> setPassword() async {
    final password = TextEditingController();
    final confirmation = TextEditingController();
    String? error;
    final next = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Nouveau mot de passe'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Définissez un nouveau mot de passe pour ${widget.user.fullName}.',
              ),
              const SizedBox(height: 12),
              _GlassPasswordField(
                controller: password,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Nouveau mot de passe',
                ),
              ),
              const SizedBox(height: 10),
              _GlassPasswordField(
                controller: confirmation,
                decoration: const InputDecoration(
                  labelText: 'Confirmer le mot de passe',
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error!, style: const TextStyle(color: AppPalette.coral)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () {
                final validation = securePasswordValidator(password.text);
                if (validation != null) {
                  setDialogState(() => error = validation);
                  return;
                }
                if (password.text != confirmation.text) {
                  setDialogState(
                    () => error = 'Les mots de passe ne correspondent pas.',
                  );
                  return;
                }
                Navigator.pop(dialogContext, password.text);
              },
              child: const Text('Définir'),
            ),
          ],
        ),
      ),
    );
    password.dispose();
    confirmation.dispose();
    if (next != null && mounted) setState(() => pendingPassword = next);
  }

  void save() {
    if (roles.isEmpty) {
      message(context, 'Choisissez au moins un rôle pour cet utilisateur.');
      return;
    }
    Navigator.pop(
      context,
      widget.user.copyWith(
        password: pendingPassword ?? widget.user.password,
        roles: roles,
        allowedPages: pages,
        writablePages: writablePages,
        status: status,
        leaveUntil: leaveUntil,
        clearLeaveUntil: status != UserStatus.onLeave,
        canExport: canExport,
        loginStartTime: loginStartTime,
        loginEndTime: loginEndTime,
        clearLoginSchedule: loginStartTime == null || loginEndTime == null,
      ),
    );
  }

  Widget accessCheck(AppPage page) => CheckboxListTile(
    dense: true,
    contentPadding: EdgeInsets.zero,
    value: pages.contains(page),
    title: Text(page.label),
    subtitle: Text(
      writablePages.contains(page)
          ? 'Accès et ajout/modification'
          : 'Consultation seulement',
    ),
    onChanged: !widget.canManage
        ? null
        : (value) => setState(() {
            if (value ?? false) {
              pages.add(page);
            } else {
              pages.remove(page);
              writablePages.remove(page);
            }
          }),
    secondary: IconButton(
      tooltip: 'Autoriser l’ajout et la modification',
      onPressed: !widget.canManage || !pages.contains(page)
          ? null
          : () => setState(() {
              if (writablePages.contains(page)) {
                writablePages.remove(page);
              } else {
                writablePages.add(page);
              }
            }),
      icon: Icon(
        writablePages.contains(page)
            ? Icons.edit_rounded
            : Icons.visibility_outlined,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Fiche utilisateur')),
    body: Aura(child: _buildBody(context)),
  );

  Widget _buildBody(BuildContext context) => SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Glass(
            child: ListTile(
              leading: CircleAvatar(
                child: Text(widget.user.fullName.substring(0, 1).toUpperCase()),
              ),
              title: Text(
                widget.user.fullName,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              subtitle: Text('@${widget.user.username}'),
            ),
          ),
          if (widget.canManage) ...[
            const SizedBox(height: 12),
            Glass(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.lock_reset_rounded,
                  color: Theme.of(context).colorScheme.primary,
                ),
                title: const Text('Mot de passe'),
                subtitle: Text(
                  pendingPassword == null
                      ? 'Définir un nouveau mot de passe pour cet utilisateur.'
                      : 'Un nouveau mot de passe sera enregistré.',
                ),
                trailing: OutlinedButton(
                  onPressed: setPassword,
                  child: Text(pendingPassword == null ? 'Modifier' : 'Changer'),
                ),
              ),
            ),
          ],
          const SizedBox(height: 18),
          const Text(
            'Rôles (cumulables)',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
          ),
          ...UserRole.values.map(
            (role) => CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(role.label),
              value: roles.contains(role),
              onChanged: !widget.canManage
                  ? null
                  : (value) => setState(() {
                      if (value ?? false) {
                        roles.add(role);
                      } else {
                        roles.remove(role);
                      }
                    }),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Pages et droit d’ajout',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
          ),
          Text(
            'L’icône œil signifie lecture seule ; le crayon autorise aussi les ajouts et modifications.',
            style: TextStyle(color: _atelierMuted(context), fontSize: 12),
          ),
          const SizedBox(height: 6),
          ...AppPage.values.map(accessCheck),
          if (widget.canManage) ...[
            const SizedBox(height: 18),
            const Text(
              'Export Excel',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: canExport,
              title: const Text('Autoriser l’export Excel'),
              subtitle: const Text('L’administrateur a toujours ce droit.'),
              onChanged: (value) => setState(() => canExport = value),
            ),
            const SizedBox(height: 12),
            const Text(
              'Plage quotidienne de connexion',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
            ),
            Text(
              'En dehors de cette plage, le compte ne peut pas accéder à l’application.',
              style: TextStyle(color: _atelierMuted(context), fontSize: 12),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => setLoginTime(true),
                  icon: const Icon(Icons.schedule_rounded),
                  label: Text('Début ${displayTime(loginStartTime)}'),
                ),
                OutlinedButton.icon(
                  onPressed: () => setLoginTime(false),
                  icon: const Icon(Icons.schedule_rounded),
                  label: Text('Fin ${displayTime(loginEndTime)}'),
                ),
                TextButton(
                  onPressed: () => setState(() {
                    loginStartTime = null;
                    loginEndTime = null;
                  }),
                  child: const Text('Retirer la limite'),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          const Text(
            'Statut du compte',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
          ),
          ListTile(
            leading: const Icon(Icons.event_available_outlined),
            title: Text(
              status == UserStatus.onLeave && leaveUntil != null
                  ? 'En congé jusqu’au ${dateText(leaveUntil!)}'
                  : status.label,
            ),
            trailing: widget.canManage
                ? OutlinedButton(
                    onPressed: setLeave,
                    child: const Text('Donner congé'),
                  )
                : null,
          ),
          if (widget.canManage)
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => setState(() {
                    status = UserStatus.active;
                    leaveUntil = null;
                  }),
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Réactiver'),
                ),
                OutlinedButton.icon(
                  onPressed: () => setState(() {
                    status = UserStatus.dismissed;
                    leaveUntil = null;
                  }),
                  icon: const Icon(Icons.person_off_outlined),
                  label: const Text('Licencier définitivement'),
                ),
              ],
            ),
          const SizedBox(height: 20),
          const Text(
            'Historique de connexion',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
          ),
          FutureBuilder<List<UserSession>>(
            future: sessions,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snapshot.data!.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('Aucune connexion enregistrée.'),
                );
              }
              return Glass(
                child: Column(
                  children: snapshot.data!
                      .map(
                        (session) => ListTile(
                          leading: const Icon(Icons.login_rounded),
                          title: Text(
                            'Entrée : ${dateText(session.loggedInAt)}',
                          ),
                          subtitle: Text(
                            session.loggedOutAt == null
                                ? 'Session en cours'
                                : 'Sortie : ${dateText(session.loggedOutAt!)}',
                          ),
                        ),
                      )
                      .toList(),
                ),
              );
            },
          ),
          if (widget.canManage) ...[
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: save,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Enregistrer les droits'),
            ),
          ],
        ],
      ),
  );
}

class UserForm extends StatefulWidget {
  const UserForm({super.key});
  @override
  State<UserForm> createState() => _UserFormState();
}

class _UserFormState extends State<UserForm> {
  final form = GlobalKey<FormState>();
  final full = TextEditingController();
  final email = TextEditingController();
  final user = TextEditingController();
  final password = TextEditingController();
  UserRole role = UserRole.operator;
  Future<void> save() async {
    if (!(form.currentState?.validate() ?? false)) return;
    if (!mounted) return;
    Navigator.pop(
      context,
      AppUser(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        username: user.text.trim(),
        password: password.text,
        fullName: full.text.trim(),
        email: email.text.trim().toLowerCase(),
        role: role,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => FormShell(
    title: 'Ajouter un utilisateur',
    child: Form(
      key: form,
      child: Column(
        children: [
          TextFormField(
            controller: full,
            decoration: const InputDecoration(labelText: 'Nom réel *'),
            validator: required,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: user,
            decoration: const InputDecoration(labelText: 'Nom d’utilisateur *'),
            validator: usernameValidator,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Adresse e-mail *'),
            validator: emailValidator,
          ),
          const SizedBox(height: 12),
          _GlassPasswordField(
            controller: password,
            decoration: const InputDecoration(labelText: 'Mot de passe *'),
            validator: securePasswordValidator,
          ),
          const SizedBox(height: 18),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Rôle *',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(height: 8),
          SegmentedButton<UserRole>(
            showSelectedIcon: MediaQuery.sizeOf(context).width >= 440,
            segments: const [
              ButtonSegment(value: UserRole.operator, label: Text('Opérateur')),
              ButtonSegment(value: UserRole.visitor, label: Text('Visiteur')),
              ButtonSegment(
                value: UserRole.validation,
                label: Text('Validation'),
              ),
            ],
            selected: {role},
            onSelectionChanged: (value) => setState(() => role = value.first),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: save,
              child: const Text('Créer l’utilisateur'),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Nine-point pattern input drawn with one continuous finger gesture.
class PatternPad extends StatelessWidget {
  const PatternPad({super.key, required this.pattern, required this.onChanged});
  final List<int> pattern;
  final ValueChanged<List<int>>? onChanged;

  int? _pointAt(Offset offset, double side) {
    const count = 3;
    final gap = side / count;
    for (var index = 0; index < 9; index++) {
      final center = Offset(
        (index % count + .5) * gap,
        (index ~/ count + .5) * gap,
      );
      if ((offset - center).distance <= gap * .3) return index;
    }
    return null;
  }

  void _add(Offset offset, double side, {bool reset = false}) {
    if (onChanged == null) return;
    final point = _pointAt(offset, side);
    if (point == null) return;
    final next = reset ? <int>[] : List<int>.of(pattern);
    if (!next.contains(point)) next.add(point);
    onChanged!(next);
  }

  @override
  Widget build(BuildContext context) {
    final dark = ForageAppearanceScope.of(context).isDark;
    return Column(
      children: [
        Text(
          'Glissez le doigt entre les points (4 minimum).',
          style: TextStyle(color: dark ? const Color(0xFFE4C7EE) : null),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: 230,
          height: 230,
          child: LayoutBuilder(
            builder: (context, constraints) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: onChanged == null
                  ? null
                  : (details) => _add(
                      details.localPosition,
                      constraints.maxWidth,
                      reset: true,
                    ),
              onPanUpdate: onChanged == null
                  ? null
                  : (details) =>
                        _add(details.localPosition, constraints.maxWidth),
              child: CustomPaint(
                painter: _PatternPadPainter(pattern, dark: dark),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
        TextButton.icon(
          onPressed: onChanged == null ? null : () => onChanged!(const []),
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Effacer le schéma'),
        ),
      ],
    );
  }
}

class _PatternPadPainter extends CustomPainter {
  const _PatternPadPainter(this.pattern, {required this.dark});
  final List<int> pattern;
  final bool dark;

  Offset _center(int index, double side) =>
      Offset((index % 3 + .5) * side / 3, (index ~/ 3 + .5) * side / 3);

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide;
    final accent = dark ? const Color(0xFFE46AFF) : AppPalette.primary;
    final idleFill = dark ? const Color(0xFF30103F) : AppPalette.soft;
    final idleBorder = dark ? const Color(0xFFE7B5FF) : AppPalette.line;
    final line = Paint()
      ..color = accent
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    final path = Path();
    for (var i = 0; i < pattern.length; i++) {
      final point = _center(pattern[i], side);
      i == 0
          ? path.moveTo(point.dx, point.dy)
          : path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(path, line);
    for (var i = 0; i < 9; i++) {
      final selected = pattern.contains(i);
      final point = _center(i, side);
      canvas.drawCircle(
        point,
        side / 11,
        Paint()..color = selected ? accent : idleFill,
      );
      canvas.drawCircle(
        point,
        side / 11,
        Paint()
          ..color = selected ? accent : idleBorder
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(_PatternPadPainter oldDelegate) =>
      !listEquals(pattern, oldDelegate.pattern) || oldDelegate.dark != dark;
}

class ImageInput extends StatelessWidget {
  const ImageInput({
    super.key,
    required this.bytes,
    required this.label,
    required this.onTap,
  });
  final Uint8List? bytes;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final image = bytes;
    return Semantics(
      button: true,
      label: image == null ? null : label,
      child: _LiquidTapTarget(
        onTap: onTap,
        radius: 18,
        accent: scheme.primary,
        child: AnimatedSize(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 220),
          child: image == null
              ? Container(
                  constraints: const BoxConstraints(minHeight: 118),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const _AtelierIcon(Icons.add_a_photo_outlined, size: 46),
                      const SizedBox(width: 14),
                      Flexible(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              label,
                              style: TextStyle(
                                color: scheme.onSurface,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Touchez pour choisir une image',
                              style: TextStyle(
                                color: scheme.onSurfaceVariant,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.all(3),
                  child: SizedBox(
                    height: 168,
                    width: double.infinity,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(15),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.memory(
                            image,
                            fit: BoxFit.cover,
                            excludeFromSemantics: true,
                          ),
                          const Positioned(
                            right: 10,
                            bottom: 10,
                            child: _AtelierIcon(Icons.edit_rounded, size: 36),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

class MultiImageInput extends StatelessWidget {
  const MultiImageInput({
    super.key,
    required this.images,
    required this.label,
    required this.onTap,
    required this.onRemove,
    this.showPreviews = true,
    this.onPreview,
  });
  final List<Uint8List> images;
  final String label;
  final VoidCallback onTap;
  final ValueChanged<int> onRemove;
  final bool showPreviews;
  final VoidCallback? onPreview;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      OutlinedButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.add_photo_alternate_outlined),
        label: Text(label),
      ),
      if (images.isNotEmpty && !showPreviews)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: List.generate(
              images.length,
              (index) => InputChip(
                label: Text('Photo ${index + 1}'),
                onDeleted: () => onRemove(index),
              ),
            ),
          ),
        ),
      if (images.isNotEmpty && showPreviews) ...[
        const SizedBox(height: 8),
        SizedBox(
          height: 92,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: images.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) => Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    onTap: onPreview,
                    child: Image.memory(
                      images[index],
                      width: 92,
                      height: 92,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                Positioned(
                  top: 2,
                  right: 2,
                  child: Material(
                    color: Colors.white,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => onRemove(index),
                      child: const Padding(
                        padding: EdgeInsets.all(3),
                        child: Icon(
                          Icons.close_rounded,
                          size: 17,
                          color: Color(0xFFB91C1C),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ],
  );
}

class FormShell extends StatelessWidget {
  const FormShell({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
  });
  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.transparent,
    body: Aura(
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Glass(
                radius: 22,
                depth: 1.65,
                opacity: .81,
                padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
                child: Row(
                  children: [
                    const _AtelierBackButton(),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (subtitle case final description?) ...[
                            const SizedBox(height: 3),
                            Text(
                              description,
                              style: TextStyle(color: _atelierMuted(context)),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 30),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 620),
                    child: Glass(
                      padding: const EdgeInsets.all(18),
                      child: child,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class Empty extends StatelessWidget {
  const Empty({
    super.key,
    required this.icon,
    required this.title,
    required this.detail,
  });
  final IconData icon;
  final String title;
  final String detail;
  @override
  Widget build(BuildContext context) => Glass(
    padding: const EdgeInsets.all(32),
    child: Center(
      child: Column(
        children: [
          Icon(icon, size: 46, color: const Color(0xFF7E22CE)),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 5),
          Text(detail, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}

void message(BuildContext context, String value) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
String? required(String? value) =>
    value == null || value.trim().isEmpty ? 'Champ obligatoire' : null;

String? usernameValidator(String? value) {
  final name = value?.trim() ?? '';
  if (!RegExp(r'^[a-zA-Z0-9._-]{3,32}$').hasMatch(name)) {
    return '3 à 32 caractères : lettres, chiffres, point, tiret ou _.';
  }
  return null;
}

String? emailValidator(String? value) {
  final email = value?.trim() ?? '';
  if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
    return 'Adresse e-mail invalide.';
  }
  return null;
}

String? securePasswordValidator(String? value) {
  final password = value ?? '';
  if (password.length < 12) return 'Utilisez au moins 12 caractères.';
  if (password.length > 128) return 'Utilisez au plus 128 caractères.';
  if (utf8.encode(password).length > 72) {
    return 'Ce mot de passe est trop long en octets (72 maximum).';
  }
  if (!RegExp(r'[a-z]').hasMatch(password) ||
      !RegExp(r'[A-Z]').hasMatch(password) ||
      !RegExp(r'[0-9]').hasMatch(password)) {
    return 'Utilisez au moins une minuscule, une majuscule et un chiffre.';
  }
  return null;
}

String? positive(String? value) =>
    number(value ?? '') <= 0 ? 'Nombre invalide' : null;
double number(String value) => double.tryParse(value.replaceAll(',', '.')) ?? 0;
String formatNumber(num value) {
  final rounded = value.toStringAsFixed(2);
  return rounded
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

String formatWeight(num kilograms) => kilograms >= 1000
    ? '${formatNumber(kilograms / 1000)} t'
    : '${formatNumber(kilograms)} kg';

String productQuantityLabel(Product product, int quantity) {
  if (product.hoseManagedByMeter) {
    return '$quantity m';
  }
  if (product.isHose) {
    return '$quantity pièce(s) · ${formatNumber(quantity * product.lengthMeters)} m';
  }
  return '$quantity pièce(s)';
}

String productSpecification(Product product) {
  if (product.isHose) {
    return product.hoseManagedByMeter
        ? 'Tuyau au mètre'
        : 'Tuyau à la pièce · ${formatNumber(product.lengthMeters)} m / pièce';
  }
  if (product.isDiameterBased) {
    return 'Ø ext. ${formatNumber(product.outsideDiameter ?? 0)} cm · '
        'int. ${formatNumber(product.insideDiameter ?? 0)} cm · '
        '${formatNumber(product.thickness)} mm';
  }
  return 'Ø ext. ${formatNumber(product.outsideDiameter ?? 0)} cm · '
      'int. ${formatNumber(product.insideDiameter ?? 0)} cm';
}

String dateText(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year} · ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
