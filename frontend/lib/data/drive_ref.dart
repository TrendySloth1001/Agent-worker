import '../core/constants/app_config.dart';
import 'connect_api.dart';
import 'files_api.dart';

/// A Google Drive file shown in the unified file preview. It is a [FileInfo]
/// whose id is `drive:<fileId>:<modifiedTime in ms>`: stable for one version
/// of the file (the cache key), different once it is edited. Bytes, text and
/// the sparky reading come from sparky's backend (`/connect/google_drive`),
/// never straight from Google, and no Google token is ever on the phone.
abstract final class DriveRef {
  static const prefix = 'drive:';
  static const _gdoc = 'application/vnd.google-apps.document';
  static const _gsheet = 'application/vnd.google-apps.spreadsheet';
  static const _gslides = 'application/vnd.google-apps.presentation';
  static const _gdrawing = 'application/vnd.google-apps.drawing';
  static const _googleNative = {_gdoc, _gsheet, _gslides, _gdrawing};

  /// What [toFileInfo] built, by id (the preview needs its link and name).
  static final _known = <String, FileInfo>{};

  static bool isDrive(String id) => id.startsWith(prefix);

  /// The cache key / file id for one version of a Drive file.
  static String idFor(String fileId, DateTime? modified) =>
      '$prefix$fileId:${modified?.toUtc().millisecondsSinceEpoch ?? 0}';

  /// The Drive file id inside [id].
  static String fileIdOf(String id) {
    final rest = id.substring(prefix.length);
    final i = rest.indexOf(':');
    return i < 0 ? rest : rest.substring(0, i);
  }

  /// A cache-safe directory name for [id].
  static String dirName(String id) =>
      id.replaceAll(RegExp('[^A-Za-z0-9._-]'), '_');

  /// The authed backend endpoint that streams the file (or its PDF export).
  static String proxyUrl(String id) =>
      '${AppConfig.apiBaseUrl}/connect/google_drive/files/${Uri.encodeComponent(fileIdOf(id))}/raw';

  /// Google Docs, Sheets and Slides are previewed as their exported PDF.
  static bool isExported(String mime) => _googleNative.contains(mime);

  static FileInfo? known(String id) => _known[id];

  /// The preview's view of a Drive item.
  static FileInfo toFileInfo(DriveFile f) {
    final exported = isExported(f.mimeType);
    final mime = exported ? 'application/pdf' : f.mimeType;
    var name = f.name.isEmpty ? 'Untitled' : f.name;
    if (exported && !name.toLowerCase().endsWith('.pdf')) name = '$name.pdf';
    final kind = mime.startsWith('image/')
        ? FileKind.image
        : mime.startsWith('video/')
        ? FileKind.video
        : mime.startsWith('audio/')
        ? FileKind.audio
        : FileKind.document;
    final info = FileInfo(
      id: idFor(f.id, f.modified),
      name: name,
      mime: mime,
      size: f.size ?? 0,
      kind: kind,
      status: FileStatus.ready,
      url: f.webViewLink,
      meta: {'drive': true, 'driveFileId': f.id, 'webViewLink': ?f.webViewLink},
      createdAt: f.modified,
    );
    _known[info.id] = info;
    return info;
  }
}

extension DriveFileInfo on FileInfo {
  bool get isDrive => DriveRef.isDrive(id);

  /// The Drive file id behind a Drive preview, else null.
  String? get driveFileId => isDrive ? DriveRef.fileIdOf(id) : null;
}
