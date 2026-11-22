import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:forage/security_config.dart';

void main() {
  test('rejects privileged keys and insecure backend addresses', () {
    const url = 'https://example.supabase.co';
    const publicKey = 'sb_publishable_example_public_key';
    expect(() => validatePublicBackendConfig(url, publicKey), returnsNormally);
    for (final value in [
      'http://example.supabase.co',
      'https://user:pass@example.com',
      'https://example.com?secret=x',
    ]) {
      expect(
        () => validatePublicBackendConfig(value, publicKey),
        throwsStateError,
      );
    }
    for (final role in ['service_role', 'authenticated']) {
      final payload = base64Url.encode(utf8.encode(jsonEncode({'role': role})));
      expect(
        () => validatePublicBackendConfig(url, 'header.$payload.signature'),
        throwsStateError,
      );
    }
    expect(
      () => validatePublicBackendConfig(url, 'sb_secret_invalid'),
      throwsStateError,
    );
  });

  test('updates must be HTTPS APKs in the application release repository', () {
    expect(
      isTrustedUpdateUrl(
        'https://github.com/youssefobunit/fourage_zouhour/releases/download/v1/app.apk',
      ),
      isTrue,
    );
    for (final url in [
      'javascript:alert(1)',
      'https://github.com.evil.test/app.apk',
      'https://github.com/other/repo/releases/download/v1/app.apk',
      'https://github.com@yoursite.example/app.apk',
    ]) {
      expect(isTrustedUpdateUrl(url), isFalse);
    }
  });
}
