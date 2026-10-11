/// A knowledge-base source, mirrored from GET /knowledge/sources.
class KbSource {
  const KbSource({
    required this.id,
    required this.type,
    required this.uri,
    required this.title,
    required this.status,
    required this.progressDone,
    required this.progressTotal,
    required this.docCount,
    required this.chunkCount,
    required this.error,
    required this.lastIngestedAt,
  });

  final String id, type, uri, status;
  final String? title, error;
  final int? progressDone, progressTotal;
  final int docCount, chunkCount;
  final DateTime? lastIngestedAt;

  bool get isActive => status == 'queued' || status == 'running';

  factory KbSource.fromJson(Map<String, dynamic> j) {
    final progress = j['progress'];
    return KbSource(
      id: j['id'] as String,
      type: j['type'] as String? ?? 'web',
      uri: j['uri'] as String? ?? '',
      title: j['title'] as String?,
      status: j['status'] as String? ?? 'queued',
      progressDone: progress is Map ? progress['done'] as int? : null,
      progressTotal: progress is Map ? progress['total'] as int? : null,
      docCount: j['docCount'] as int? ?? 0,
      chunkCount: j['chunkCount'] as int? ?? 0,
      error: j['error'] as String?,
      lastIngestedAt: DateTime.tryParse(j['lastIngestedAt'] as String? ?? ''),
    );
  }
}
