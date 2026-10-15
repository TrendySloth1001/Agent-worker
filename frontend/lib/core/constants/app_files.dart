/// Limits and type tables for attachments (see docs/ATTACHMENTS.md).
abstract final class AppFiles {
  static const maxPerMessage = 10;

  /// A video re-encoded to fit storage has no link yet: the player polls.
  static const processingPoll = Duration(seconds: 3);
  static const processingPolls = 100;
  static const kb = 1024;
  static const mb = 1024 * 1024;
  static const gb = 1024 * 1024 * 1024;

  static const imageMax = 15 * 1024 * 1024;
  static const documentMax = 25 * 1024 * 1024;
  static const videoMax = 100 * 1024 * 1024;
  static const audioMax = 25 * 1024 * 1024;

  /// A signed URL lasts an hour; refresh a little earlier.
  static const urlTtl = Duration(minutes: 50);

  static const uploadTimeout = Duration(minutes: 10);
  static const requestTimeout = Duration(seconds: 30);

  /// Reading a file with a model (summary, frame descriptions) is slow.
  static const insightTimeout = Duration(seconds: 120);

  /// Characters of extracted text fetched for the text preview.
  static const textPreviewLimit = 200000;

  /// Lines per block in the text preview (keeps long files light).
  static const textBlockLines = 40;

  /// Shown in a monospaced face in the text preview.
  static const monoExtensions = {
    'csv',
    'json',
    'html',
    'css',
    'yaml',
    'yml',
    'ts',
    'js',
    'py',
    'dart',
    'java',
    'go',
    'rs',
    'sql',
    'xml',
    'sh',
    'kt',
    'c',
    'cpp',
    'h',
  };

  /// Read straight from the phone when the file is still local.
  static const localTextExtensions = {
    'txt',
    'md',
    'csv',
    'json',
    'html',
    'css',
    'yaml',
    'yml',
    'ts',
    'js',
    'py',
    'dart',
    'java',
    'go',
    'rs',
    'sql',
  };

  static const fallbackMime = 'application/octet-stream';

  /// Status the server writes into saved attachments of a deleted file.
  static const deletedStatus = 'deleted';

  /// Path of the API's signed file links (the only readable file URLs).
  static const blobPath = '/files/blob/';

  /// Sent as the text of an old message whose only files were deleted.
  static const deletedHistoryText = '(attachment deleted)';

  /// Files per page of the Storage screen (server caps at 100).
  static const listPageSize = 40;

  /// Name used when a file name has nothing usable left.
  static const fallbackName = 'file';

  static const mimeByExtension = <String, String>{
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'webp': 'image/webp',
    'gif': 'image/gif',
    'heic': 'image/heic',
    'heif': 'image/heic',
    'pdf': 'application/pdf',
    'docx':
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'txt': 'text/plain',
    'md': 'text/markdown',
    'csv': 'text/csv',
    'json': 'application/json',
    'html': 'text/html',
    'css': 'text/css',
    'yaml': 'application/yaml',
    'yml': 'application/yaml',
    'ts': 'text/plain',
    'js': 'text/javascript',
    'py': 'text/x-python',
    'dart': 'text/plain',
    'java': 'text/x-java',
    'go': 'text/plain',
    'rs': 'text/plain',
    'sql': 'text/plain',
    'mp4': 'video/mp4',
    'mov': 'video/quicktime',
    'webm': 'video/webm',
    'mkv': 'video/x-matroska',
    'm4v': 'video/x-m4v',
    '3gp': 'video/3gpp',
    'mp3': 'audio/mpeg',
    'm4a': 'audio/mp4',
    'wav': 'audio/wav',
    'ogg': 'audio/ogg',
    'opus': 'audio/opus',
    'aac': 'audio/aac',
    'flac': 'audio/flac',
  };

  static const imageExtensions = {
    'jpg',
    'jpeg',
    'png',
    'webp',
    'gif',
    'heic',
    'heif',
  };
  static const videoExtensions = {'mp4', 'mov', 'webm', 'mkv', 'm4v', '3gp'};
  static const audioExtensions = {
    'mp3',
    'm4a',
    'wav',
    'ogg',
    'opus',
    'aac',
    'flac',
  };
}
