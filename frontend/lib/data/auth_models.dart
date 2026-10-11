import 'dart:convert';
import 'dart:typed_data';

/// The signed-in account (GET /auth/me `user`).
class AuthUser {
  const AuthUser({
    required this.id,
    required this.email,
    required this.name,
    required this.role,
    this.avatarUrl,
  });

  final String id, email, name, role;

  /// A data: URL (uploaded photo) or an https URL; null shows initials.
  final String? avatarUrl;

  bool get isOwner => role == 'owner';

  String get displayName => name.trim().isNotEmpty ? name.trim() : email;

  /// One or two letters for the avatar circle.
  String get initials {
    final words = displayName
        .split(RegExp(r'[\s@._-]+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return '?';
    String lead(String w) => String.fromCharCode(w.runes.first);
    return (lead(words.first) + (words.length > 1 ? lead(words[1]) : ''))
        .toUpperCase();
  }

  /// Decoded bytes of a data: URL avatar, else null.
  Uint8List? get avatarBytes {
    final url = avatarUrl;
    if (url == null || !url.startsWith('data:')) return null;
    final comma = url.indexOf(',');
    if (comma < 0) return null;
    try {
      return base64Decode(url.substring(comma + 1));
    } catch (_) {
      return null;
    }
  }

  factory AuthUser.fromJson(Map<String, dynamic> j) => AuthUser(
    id: j['id'] as String? ?? '',
    email: j['email'] as String? ?? '',
    name: j['name'] as String? ?? '',
    role: j['role'] as String? ?? 'user',
    avatarUrl: j['avatarUrl'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'name': name,
    'role': role,
    'avatarUrl': avatarUrl,
  };
}

/// Daily limits; null fields never happen, a null [DailyLimits] means unlimited.
class DailyLimits {
  const DailyLimits({
    required this.chat,
    required this.table,
    required this.uploads,
    required this.storageBytes,
  });

  final int chat, table, uploads, storageBytes;

  static DailyLimits? fromJson(Object? v) {
    if (v is! Map) return null;
    int n(String k) => (v[k] as num?)?.toInt() ?? 0;
    return DailyLimits(
      chat: n('chat'),
      table: n('table'),
      uploads: n('uploads'),
      storageBytes: n('storageBytes'),
    );
  }
}

class DailyUsage {
  const DailyUsage({
    this.chats = 0,
    this.tables = 0,
    this.uploads = 0,
    this.bytes = 0,
    this.storageBytes = 0,
  });

  final int chats, tables, uploads, bytes, storageBytes;

  factory DailyUsage.fromJson(Object? v) {
    if (v is! Map) return const DailyUsage();
    int n(String k) => (v[k] as num?)?.toInt() ?? 0;
    return DailyUsage(
      chats: n('chats'),
      tables: n('tables'),
      uploads: n('uploads'),
      bytes: n('bytes'),
      storageBytes: n('storageBytes'),
    );
  }
}

/// GET /auth/me.
class AccountInfo {
  const AccountInfo({
    required this.user,
    required this.usage,
    this.limits,
    this.resetsAt,
  });

  final AuthUser user;
  final DailyLimits? limits;
  final DailyUsage usage;
  final DateTime? resetsAt;

  bool get unlimited => limits == null;

  factory AccountInfo.fromJson(Map<String, dynamic> j) => AccountInfo(
    user: AuthUser.fromJson(j['user'] as Map<String, dynamic>),
    limits: DailyLimits.fromJson(j['limits']),
    usage: DailyUsage.fromJson(j['usage']),
    resetsAt: DateTime.tryParse(j['resetsAt'] as String? ?? '')?.toLocal(),
  );
}

/// One signed-in device (GET /auth/sessions).
class DeviceSession {
  const DeviceSession({
    required this.id,
    required this.current,
    this.device,
    this.lastUsedAt,
  });

  final String id;
  final String? device;
  final DateTime? lastUsedAt;
  final bool current;

  factory DeviceSession.fromJson(Map<String, dynamic> j) => DeviceSession(
    id: j['id'] as String? ?? '',
    device: j['device'] as String?,
    lastUsedAt: DateTime.tryParse(j['lastUsedAt'] as String? ?? '')?.toLocal(),
    current: j['current'] == true,
  );
}
