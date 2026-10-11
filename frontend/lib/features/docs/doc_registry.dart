import '../../data/doc_models.dart';
import '../../data/docs_api.dart';
import 'doc_controller.dart';

/// Live documents by id, shared by chat cards and the reader so a doc keeps
/// streaming while the user moves between chats (like background round
/// tables). Cleared on sign-out.
class DocRegistry {
  DocRegistry({DocsApi? api}) : api = api ?? DocsApi();

  static DocRegistry instance = DocRegistry();

  /// Replaceable (tests use a fake transport).
  DocsApi api;

  final _docs = <String, DocController>{};

  /// The controller for [id], created on first use. [seed] fills it before
  /// the first snapshot (e.g. from a chat card's saved meta).
  DocController obtain(String id, {Doc? seed}) =>
      _docs[id] ??= DocController(id, api: api, seed: seed);

  DocController? peek(String id) => _docs[id];

  /// Opens the stream for a doc that may still be running.
  DocController watch(String id, {Doc? seed}) {
    final c = obtain(id, seed: seed);
    if (!c.loaded || c.doc.isRunning) c.attach();
    return c;
  }

  /// Docs whose pipeline is still working.
  Iterable<DocController> get running =>
      _docs.values.where((c) => c.doc.isRunning);

  void forget(String id) => _docs.remove(id)?.dispose();

  void clear() {
    for (final c in _docs.values) {
      c.dispose();
    }
    _docs.clear();
  }
}
