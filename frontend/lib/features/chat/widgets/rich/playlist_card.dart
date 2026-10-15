import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/media_apps.dart';
import '../../../../core/constants/playlist.dart';
import '../../../../core/haptics.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../data/playlist_api.dart';
import '../../../actions/device_action.dart';
import '../../../actions/device_action_runner.dart';
import 'playful_common.dart' show PlayfulFallback;
import 'playlist_preview.dart';
import 'rich_frame.dart';

/// What the server found for one playlist source, kept so a card rebuilt
/// while scrolling does not ask again.
class _Loaded {
  List<PlaylistTrack>? tracks;
  String? playAll;
  bool playAllDone = false;
}

/// ```sparky-playlist block: songs with cover, duration, a 30 s in-app
/// preview, "open in <music app>" per song and Play all (YouTube).
class PlaylistCard extends StatefulWidget {
  const PlaylistCard({
    super.key,
    required this.source,
    this.api,
    this.preview,
    this.runner,
  });

  final String source;
  final PlaylistApi? api;
  final PreviewController? preview;
  final DeviceActionRunner? runner;

  /// How covers load; tests swap in a local image.
  static ImageProvider Function(String url) imageFor = NetworkImage.new;

  static final Map<String, _Loaded> _cache = {};
  static const _cacheLimit = 20;

  @visibleForTesting
  static void resetCache() => _cache.clear();

  @override
  State<PlaylistCard> createState() => _PlaylistCardState();
}

class _PlaylistCardState extends State<PlaylistCard>
    with WidgetsBindingObserver {
  late PlaylistSpec? _spec = PlaylistSpec.parse(widget.source);
  late List<PlaylistTrack> _tracks = _plain();
  String? _playAll;
  List<String>? _installed;
  int? _copiedRow;
  Timer? _copiedTimer;

  PlaylistApi get _api => widget.api ?? PlaylistApi.instance;
  PreviewController get _preview => widget.preview ?? PreviewController.shared;
  DeviceActionRunner get _runner =>
      widget.runner ?? DeviceActionRunner.instance;

  /// Row ids of this card start with this, so leaving stops only its own.
  String get _prefix => 'pl${identityHashCode(this)}:';

  List<PlaylistTrack> _plain() => [
    for (final s in _spec?.songs ?? const <PlaylistSong>[])
      PlaylistTrack(title: s.title, artist: s.artist),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _checkInstalled();
  }

  @override
  void didUpdateWidget(PlaylistCard old) {
    super.didUpdateWidget(old);
    if (old.source != widget.source) {
      unawaited(_preview.stopOwned(_prefix));
      _spec = PlaylistSpec.parse(widget.source);
      _tracks = _plain();
      _playAll = null;
      _load();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      unawaited(_preview.stopOwned(_prefix));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _copiedTimer?.cancel();
    // Off screen or the chat changed: the preview must not keep playing.
    final preview = _preview;
    final prefix = _prefix;
    scheduleMicrotask(() => preview.stopOwned(prefix));
    super.dispose();
  }

  Future<void> _checkInstalled() async {
    final keys = await InstalledMediaApps.keys(runner: widget.runner);
    if (mounted && keys != null) setState(() => _installed = keys);
  }

  void _load() {
    final spec = _spec;
    if (spec == null) return;
    final source = widget.source;
    final cache = PlaylistCard._cache;
    final known = cache[source];
    if (known != null) {
      final t = known.tracks;
      if (t != null) _tracks = t;
      _playAll = known.playAll;
      if (t != null && known.playAllDone) return;
    }
    final entry = cache[source] ??= _Loaded();
    if (cache.length > PlaylistCard._cacheLimit) {
      cache.remove(cache.keys.first);
    }
    if (entry.tracks == null) {
      unawaited(
        _api
            .enrich(spec.songs)
            .then((tracks) {
              entry.tracks = tracks;
              if (mounted && widget.source == source) {
                setState(() => _tracks = tracks);
              }
            })
            .catchError((Object _) {}),
      );
    }
    if (!entry.playAllDone) {
      unawaited(
        _api
            .playAll(spec.songs)
            .then((r) {
              entry.playAll = r.url;
              entry.playAllDone = true;
              if (mounted && widget.source == source) {
                setState(() => _playAll = r.url);
              }
            })
            .catchError((Object _) {}),
      );
    }
  }

  /// The app that opens a song: the one the user named, else the first
  /// installed music app; (app, installed). With none installed the web
  /// search page of YouTube Music opens in the browser.
  (MediaApp, bool) _app() {
    final keys = _installed;
    final named = MediaApps.all
        .where((a) => a.key == _spec?.appKey && a.searchTemplate.isNotEmpty)
        .firstOrNull;
    if (named != null) return (named, keys?.contains(named.key) ?? false);
    if (keys != null) {
      for (final k in PlaylistWire.appOrder) {
        if (keys.contains(k)) {
          return (MediaApps.all.firstWhere((a) => a.key == k), true);
        }
      }
    }
    return (MediaApps.youtubeMusic, false);
  }

  Future<void> _open(MediaApp app, bool installed, PlaylistTrack t) async {
    Haptics.tap();
    final query = [t.title, t.artist].where((e) => e.isNotEmpty).join(' ');
    final outcome = await _runner.run(
      DeviceAction.link(app.searchUrl(query), app: installed ? app : null),
    );
    if (outcome != ActionOutcome.done) Haptics.error();
  }

  /// YouTube's own app plays a watch_videos list; YouTube Music is next.
  Future<void> _playAllTap() async {
    final url = _playAll;
    if (url == null) return;
    Haptics.tap();
    final keys = _installed ?? const <String>[];
    final app = keys.contains(MediaApps.youtube.key)
        ? MediaApps.youtube
        : keys.contains(MediaApps.youtubeMusic.key)
        ? MediaApps.youtubeMusic
        : null;
    final outcome = await _runner.run(DeviceAction.link(url, app: app));
    if (outcome != ActionOutcome.done) Haptics.error();
  }

  void _copyRow(int i) {
    final t = _tracks[i];
    Haptics.tap();
    unawaited(
      Clipboard.setData(
        ClipboardData(text: PlaylistStrings.copyLine(t.title, t.artist)),
      ),
    );
    setState(() => _copiedRow = i);
    _copiedTimer?.cancel();
    _copiedTimer = Timer(AppDurations.copiedFeedback, () {
      if (mounted) setState(() => _copiedRow = null);
    });
  }

  void _togglePreview(int i) {
    final url = _tracks[i].previewUrl;
    if (url == null) return;
    Haptics.tap();
    unawaited(_preview.toggle('$_prefix$i', url));
  }

  int get _minutes {
    final ms = _tracks.fold<int>(0, (sum, t) => sum + (t.durationMs ?? 0));
    return (ms / 60000).round();
  }

  @override
  Widget build(BuildContext context) {
    final spec = _spec;
    if (spec == null) {
      return PlayfulFallback(
        title: PlaylistStrings.label,
        source: widget.source,
      );
    }
    final p = context.palette;
    final t = context.text;
    final (app, installed) = _app();
    final all = [
      for (final s in _tracks) PlaylistStrings.copyLine(s.title, s.artist),
    ].join('\n');
    return RichCard(
      title: '${PlaylistStrings.label} / ${spec.title.toUpperCase()}',
      leading: AppIcon(
        PlaylistIcons.music,
        size: AppIconSize.sm,
        color: p.textSecondary,
      ),
      actions: [RichAction.copy(text: all, label: PlaylistStrings.copyAll)],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              PlaylistSizes.pad,
              PlaylistSizes.pad,
              PlaylistSizes.pad,
              AppSpacing.xs,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        spec.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: t.title,
                      ),
                      const SizedBox(height: PlaylistSizes.headerGap),
                      Text(
                        PlaylistStrings.header(_tracks.length, _minutes),
                        style: t.caption,
                      ),
                    ],
                  ),
                ),
                if (_playAll != null) ...[
                  const SizedBox(width: AppSpacing.md),
                  _PlayAllButton(onTap: _playAllTap),
                ],
              ],
            ),
          ),
          AnimatedBuilder(
            animation: _preview,
            builder: (context, _) => Column(
              children: [
                for (var i = 0; i < _tracks.length; i++)
                  _SongRow(
                    track: _tracks[i],
                    app: app,
                    installed: installed,
                    phase: _preview.phaseOf('$_prefix$i'),
                    progress: _preview.progress,
                    copied: _copiedRow == i,
                    onPreview: () => _togglePreview(i),
                    onOpen: () => _open(app, installed, _tracks[i]),
                    onCopy: () => _copyRow(i),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
      ),
    );
  }
}

class _PlayAllButton extends StatelessWidget {
  const _PlayAllButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      button: true,
      label: PlaylistStrings.playAll,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: PlaylistSizes.playAllHeight,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          decoration: BoxDecoration(
            color: p.textPrimary,
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(
                PlaylistIcons.playAll,
                size: PlaylistSizes.playAllLogo,
                color: p.textInverse,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                PlaylistStrings.playAll,
                style: context.text.bodySmall.copyWith(
                  color: p.textInverse,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SongRow extends StatelessWidget {
  const _SongRow({
    required this.track,
    required this.app,
    required this.installed,
    required this.phase,
    required this.progress,
    required this.copied,
    required this.onPreview,
    required this.onOpen,
    required this.onCopy,
  });

  final PlaylistTrack track;
  final MediaApp app;
  final bool installed;
  final PreviewPhase phase;
  final double progress;
  final bool copied;
  final VoidCallback onPreview, onOpen, onCopy;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    return Semantics(
      container: true,
      label: PlaylistStrings.row(track.title, track.artist, track.duration),
      hint: PlaylistStrings.rowHint,
      onLongPress: onCopy,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: onCopy,
        child: Container(
          height: PlaylistSizes.rowHeight,
          padding: const EdgeInsets.symmetric(horizontal: PlaylistSizes.pad),
          child: Row(
            children: [
              _Cover(url: track.art),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: ExcludeSemantics(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.bodySmall.copyWith(
                          color: p.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (track.artist.isNotEmpty)
                        Text(
                          track.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.caption,
                        ),
                    ],
                  ),
                ),
              ),
              SizedBox(
                width: PlaylistSizes.durationWidth,
                child: ExcludeSemantics(
                  child: Text(
                    copied ? PlaylistStrings.copied : track.duration,
                    textAlign: TextAlign.end,
                    maxLines: 1,
                    style: t.caption.copyWith(color: copied ? p.accent : null),
                  ),
                ),
              ),
              if (track.previewUrl != null)
                _PreviewButton(
                  title: track.title,
                  phase: phase,
                  progress: progress,
                  onTap: onPreview,
                ),
              _OpenButton(
                title: track.title,
                app: app,
                installed: installed,
                onTap: onOpen,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final fallback = Center(
      child: AppIcon(
        PlaylistIcons.music,
        size: PlaylistSizes.coverIcon,
        color: p.textTertiary,
      ),
    );
    return Container(
      width: PlaylistSizes.cover,
      height: PlaylistSizes.cover,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(PlaylistSizes.coverRadius),
        border: Border.all(color: p.border, width: AppBorder.thin),
      ),
      child: url == null
          ? fallback
          : ExcludeSemantics(
              child: Image(
                image: PlaylistCard.imageFor(url!),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback,
              ),
            ),
    );
  }
}

class _PreviewButton extends StatelessWidget {
  const _PreviewButton({
    required this.title,
    required this.phase,
    required this.progress,
    required this.onTap,
  });

  final String title;
  final PreviewPhase phase;
  final double progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final still = MediaQuery.disableAnimationsOf(context);
    final active = phase != PreviewPhase.idle;
    final label = switch (phase) {
      PreviewPhase.idle => PlaylistStrings.preview(title),
      PreviewPhase.loading => PlaylistStrings.loadingPreview(title),
      PreviewPhase.playing => PlaylistStrings.stopPreview(title),
    };
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox.square(
          dimension: PlaylistSizes.previewButton,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (active)
                SizedBox.square(
                  dimension: PlaylistSizes.previewButton,
                  child: CircularProgressIndicator(
                    // Loading spins; reduced motion shows an empty ring.
                    value: phase == PreviewPhase.loading
                        ? (still ? 0 : null)
                        : progress,
                    strokeWidth: PlaylistSizes.ringStroke,
                    color: p.accent,
                    backgroundColor: p.border,
                  ),
                ),
              AppIcon(
                phase == PreviewPhase.playing
                    ? PlaylistIcons.pause
                    : PlaylistIcons.play,
                size: PlaylistSizes.previewIcon,
                color: p.textPrimary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OpenButton extends StatelessWidget {
  const _OpenButton({
    required this.title,
    required this.app,
    required this.installed,
    required this.onTap,
  });

  final String title;
  final MediaApp app;
  final bool installed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: PlaylistStrings.openIn(app.label, title),
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox.square(
          dimension: PlaylistSizes.openButton,
          child: Center(
            child: AppIcon(
              app.logo,
              size: PlaylistSizes.openLogo,
              color: context.palette.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
