import 'dart:convert';

/// Build variables are visible in a shipped binary; only public keys belong here.
void validatePublicBackendConfig(String url, String key) {
  final uri = Uri.tryParse(url);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment) {
    throw StateError('Une adresse HTTPS Supabase valide est requise.');
  }
  if (key.startsWith('sb_publishable_') && key.length > 20) return;
  // Support legacy anonymous JWTs, explicitly rejecting elevated credentials.
  try {
    final parts = key.split('.');
    if (parts.length == 3) {
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      if (payload is Map && payload['role'] == 'anon') return;
    }
  } catch (_) {}
  throw StateError(
    'Utilisez uniquement une clé Supabase publique dans l’application.',
  );
}

bool isTrustedUpdateUrl(String value) {
  final uri = Uri.tryParse(value);
  return uri != null &&
      uri.scheme == 'https' &&
      uri.host == 'github.com' &&
      uri.userInfo.isEmpty &&
      uri.port == 443 &&
      uri.path.startsWith(
        '/youssefobunit/fourage_zouhour/releases/download/',
      ) &&
      uri.path.toLowerCase().endsWith('.apk');
}
