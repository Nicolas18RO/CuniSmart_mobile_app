/// QR payload is only the stable animal identity. No ficha fields.
class RabbitQr {
  static final RegExp _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  static String payloadFor(String uuid) => 'cunismart://rabbit/$uuid';

  static String? parseUuid(String raw) {
    final trimmed = raw.trim();
    if (_uuid.hasMatch(trimmed)) return trimmed.toLowerCase();
    final uri = Uri.tryParse(trimmed);
    if (uri == null) return null;
    if (uri.scheme != 'cunismart' || uri.host != 'rabbit') return null;
    if (uri.pathSegments.isEmpty) return null;
    final id = uri.pathSegments.first;
    if (_uuid.hasMatch(id)) return id.toLowerCase();
    return null;
  }
}
