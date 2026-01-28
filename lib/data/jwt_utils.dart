import 'dart:convert';

/// Minimal JWT decode helper (no signature verification).
///
/// Used client-side only to read standard claims like `sub`.
class JwtUtils {
  static Map<String, dynamic>? tryDecodePayload(String jwt) {
    final parts = jwt.split('.');
    if (parts.length != 3) return null;

    try {
      final payload = base64Url.normalize(parts[1]);
      final bytes = base64Url.decode(payload);
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v));
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static String? tryGetSubject(String jwt) {
    final payload = tryDecodePayload(jwt);
    final sub = payload?['sub'];
    final v = sub?.toString().trim();
    return (v == null || v.isEmpty) ? null : v;
  }
}
