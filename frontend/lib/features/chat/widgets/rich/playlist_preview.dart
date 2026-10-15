import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

/// What a preview player reports while it runs.
class PreviewSignal {
  const PreviewSignal({
    this.position = Duration.zero,
    this.total = Duration.zero,
    this.playing = false,
    this.ended = false,
    this.failed = false,
  });

  final Duration position, total;
  final bool playing, ended, failed;
}

/// One preview playback (a real player in the app, a fake in tests).
abstract class PreviewEngine {
  /// Starts [url] and reports to [onSignal] until [stop] or the end.
  Future<void> start(String url, void Function(PreviewSignal) onSignal);

  /// Stops and releases the player. Safe to call twice.
  Future<void> stop();
}

/// The app's player: `video_player` plays audio-only AAC just as well.
class VideoPreviewEngine implements PreviewEngine {
  VideoPlayerController? _c;
  void Function()? _listener;

  @override
  Future<void> start(String url, void Function(PreviewSignal) onSignal) async {
    final c = VideoPlayerController.networkUrl(Uri.parse(url));
    _c = c;
    await c.initialize();
    void listener() {
      final v = c.value;
      final total = v.duration;
      onSignal(
        PreviewSignal(
          position: v.position,
          total: total,
          playing: v.isPlaying,
          failed: v.hasError,
          ended:
              total > Duration.zero &&
              v.position >= total - const Duration(milliseconds: 150),
        ),
      );
    }

    _listener = listener;
    c.addListener(listener);
    await c.play();
  }

  @override
  Future<void> stop() async {
    final c = _c;
    _c = null;
    if (c == null) return;
    final l = _listener;
    if (l != null) c.removeListener(l);
    try {
      await c.pause();
    } catch (_) {}
    await c.dispose();
  }
}

enum PreviewPhase { idle, loading, playing }

/// One preview at a time for the whole app: starting another stops the
/// first. Rows listen to it and show their own state by [activeId].
class PreviewController extends ChangeNotifier {
  PreviewController({PreviewEngine Function()? engine})
    : _make = engine ?? VideoPreviewEngine.new;

  /// The controller cards use; tests replace it.
  static PreviewController shared = PreviewController();

  final PreviewEngine Function() _make;
  PreviewEngine? _engine;
  int _gen = 0;

  String? _activeId;
  PreviewPhase _phase = PreviewPhase.idle;
  double _progress = 0;
  bool _failed = false;

  /// The row playing (or loading), else null.
  String? get activeId => _activeId;
  PreviewPhase get phase => _phase;

  /// 0..1 of the 30 s preview.
  double get progress => _progress;

  /// The last preview could not be played (cleared by the next tap).
  bool get failed => _failed;

  PreviewPhase phaseOf(String id) =>
      _activeId == id ? _phase : PreviewPhase.idle;

  /// Plays [url] for row [id], or stops it when that row is already playing.
  Future<void> toggle(String id, String url) async {
    if (_activeId == id) return stop();
    await stop();
    final gen = ++_gen;
    final engine = _make();
    _engine = engine;
    _activeId = id;
    _phase = PreviewPhase.loading;
    _progress = 0;
    _failed = false;
    notifyListeners();
    try {
      await engine.start(url, (s) => _onSignal(gen, s));
    } catch (_) {
      if (gen == _gen) await _finish(failed: true);
    }
  }

  void _onSignal(int gen, PreviewSignal s) {
    if (gen != _gen) return;
    if (s.failed) {
      _finish(failed: true);
      return;
    }
    if (s.ended) {
      _finish();
      return;
    }
    final next = s.total > Duration.zero
        ? (s.position.inMilliseconds / s.total.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    final phase = s.playing ? PreviewPhase.playing : PreviewPhase.loading;
    if (phase != _phase || (next - _progress).abs() > 0.005) {
      _phase = phase;
      _progress = next;
      notifyListeners();
    }
  }

  Future<void> _finish({bool failed = false}) async {
    _gen++;
    final engine = _engine;
    _engine = null;
    _activeId = null;
    _phase = PreviewPhase.idle;
    _progress = 0;
    _failed = failed;
    notifyListeners();
    await engine?.stop();
  }

  /// Stops whatever plays.
  Future<void> stop() async {
    if (_activeId == null && _engine == null) return;
    await _finish();
  }

  /// Stops only when the playing row belongs to [prefix] (a card leaving the
  /// screen must not cut off another card's preview).
  Future<void> stopOwned(String prefix) async {
    final id = _activeId;
    if (id != null && id.startsWith(prefix)) await stop();
  }
}
