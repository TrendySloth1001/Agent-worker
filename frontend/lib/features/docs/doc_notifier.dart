import '../../core/constants/docs.dart';
import '../../core/constants/notify_copy.dart';
import '../../core/notify/notification_center.dart';
import '../../core/notify/notify_kind.dart';
import '../../core/notify/notify_target.dart';
import '../../data/doc_models.dart';
import 'doc_controller.dart';

/// System notifications for documents, like the round table's: ongoing
/// "section x/y" progress kept alive by a foreground service while a doc is
/// written, then a "document ready" (or stopped / failed) notification that
/// opens the doc. Tracks every controller of the registry, so it keeps
/// working when the reader is closed or the chat changes.
class DocNotifier {
  DocNotifier({NotificationCenter? center, required this.onChanged})
    : _n = center ?? NotificationCenter.instance;

  final NotificationCenter _n;

  /// Called when a doc starts or stops running (the shell's chip follows).
  final void Function() onChanged;

  final _seen = <String, _Seen>{};

  /// Starts watching [c] (idempotent).
  void track(DocController c) {
    if (_seen.containsKey(c.id)) return;
    _seen[c.id] = _Seen();
    c.addListener(() => _changed(c));
    _changed(c);
  }

  void forget(String id) => _seen.remove(id);

  void _changed(DocController c) {
    final seen = _seen[c.id];
    if (seen == null) return;
    final doc = c.doc;
    if (seen.viewing != c.viewing) {
      seen.viewing = c.viewing;
      onChanged();
    }
    if (doc.isRunning) {
      _running(c, doc, seen);
    } else if (seen.running) {
      _stopped(c, doc, seen);
    }
    // The reminder is for an outline nobody has looked at yet.
    if (seen.reminded && (doc.status != DocStatus.outlineReady || c.viewing)) {
      seen.reminded = false;
      _n.cancel(NotifyKind.resume, doc.id);
    }
  }

  void _running(DocController c, Doc doc, _Seen seen) {
    final body = DocStrings.notifyProgress(
      title: doc.title,
      done: doc.done,
      total: doc.total,
      phase: doc.phase,
    );
    if (!seen.running) {
      seen.running = true;
      onChanged();
      _n.ensurePermission();
      // Only allowed while the app is visible; the service then keeps the
      // process alive after the user leaves.
      if (!_n.background.value) _keepAlive(doc, body);
    } else if (!_n.background.value) {
      // Back in the foreground after a background start: try again.
      _keepAlive(doc, body);
    }
    if (body == seen.body) return;
    seen.body = body;
    _n.progress(
      NotifyKind.doc,
      title: DocStrings.notifyProgressTitle,
      body: body,
      target: DocTarget(doc.id),
      done: doc.done,
      total: doc.total,
    );
  }

  void _keepAlive(Doc doc, String body) => _n.keepAlive(
    NotifyKind.doc,
    title: DocStrings.notifyProgressTitle,
    body: body,
    target: DocTarget(doc.id),
  );

  void _stopped(DocController c, Doc doc, _Seen seen) {
    seen.running = false;
    seen.body = '';
    onChanged();
    final title = switch (doc.status) {
      DocStatus.done => DocStrings.notifyDoneTitle,
      DocStatus.partial => DocStrings.notifyPartialTitle,
      DocStatus.outlineReady => DocStrings.notifyOutlineTitle,
      _ => DocStrings.notifyFailedTitle,
    };
    final failed =
        doc.status == DocStatus.failed || doc.status == DocStatus.interrupted;
    final body = failed
        ? (doc.error ?? DocStrings.status(doc.status))
        : DocStrings.notifyDoneBody(
            title: doc.title,
            words: doc.wordCount,
            sections: doc.body.where((s) => s.isDone).length,
          );
    // Reading the doc right now needs no notification (the center skips it
    // and still clears the progress one).
    _n.post(
      NotifyKind.doc,
      key: doc.id,
      title: title,
      body: body,
      target: DocTarget(doc.id),
      lookingAt: c.viewing,
    );
    if (doc.status == DocStatus.outlineReady && !c.viewing) {
      seen.reminded = true;
      _n.schedule(
        NotifyKind.resume,
        key: doc.id,
        title: NotifyCopy.resumeTitle,
        body: NotifyCopy.resumeBody(doc.title),
        delay: NotifyConfig.resumeDelay,
        target: DocTarget(doc.id),
      );
    }
  }
}

class _Seen {
  bool running = false;
  bool viewing = false;
  bool reminded = false;
  String body = '';
}
