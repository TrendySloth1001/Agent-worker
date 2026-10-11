import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../core/constants/app_icons.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../data/files_api.dart';
import '../widgets/attachment_views.dart';
import '../widgets/image_strip.dart';
import 'preview_actions.dart';

/// In-app player for videos and audio files (local file or signed URL).
class MediaPreviewScreen extends StatefulWidget {
  const MediaPreviewScreen({super.key, required this.file});

  final FileInfo file;

  @override
  State<MediaPreviewScreen> createState() => _MediaPreviewScreenState();
}

class _MediaPreviewScreenState extends State<MediaPreviewScreen> {
  VideoPlayerController? _video;
  bool _failed = false;
  bool _dragging = false;
  double _dragMs = 0;
  String? _transcript;
  bool _transcriptDone = false;

  bool get _isAudio => widget.file.kind == FileKind.audio;

  @override
  void initState() {
    super.initState();
    _start();
    if (_isAudio) _loadTranscript();
  }

  Future<void> _start({bool force = false}) async {
    final f = widget.file;
    VideoPlayerController? c;
    final local = f.localPath;
    if (local != null && File(local).existsSync()) {
      c = VideoPlayerController.file(File(local));
    } else {
      final url = await resolveFileUrl(f, force: force);
      if (url == null) {
        if (mounted) setState(() => _failed = true);
        return;
      }
      c = VideoPlayerController.networkUrl(Uri.parse(url));
    }
    if (!mounted) {
      await c.dispose();
      return;
    }
    c.addListener(_tick);
    setState(() {
      _video = c;
      _failed = false;
    });
    try {
      await c.initialize();
      await c.setLooping(false);
      if (!mounted) return;
      setState(() {});
      await c.play();
    } catch (_) {
      // A stale signed URL: fetch a fresh one once.
      if (!force && local == null && mounted) {
        c.removeListener(_tick);
        await c.dispose();
        _video = null;
        return _start(force: true);
      }
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _loadTranscript() async {
    if (widget.file.id.isEmpty) {
      setState(() => _transcriptDone = true);
      return;
    }
    try {
      final t = await FilesApi.instance.text(widget.file.id);
      if (mounted) setState(() => _transcript = t.text.trim());
    } catch (_) {}
    if (mounted) setState(() => _transcriptDone = true);
  }

  void _tick() {
    if (mounted && !_dragging) setState(() {});
  }

  @override
  void dispose() {
    _video?.removeListener(_tick);
    _video?.dispose();
    super.dispose();
  }

  void _toggle() {
    final c = _video;
    if (c == null || !c.value.isInitialized) return;
    Haptics.tap();
    final v = c.value;
    if (v.isPlaying) {
      c.pause();
    } else {
      if (v.position >= v.duration) c.seekTo(Duration.zero);
      c.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      appBar: PreviewBar(file: widget.file),
      body: Column(
        children: [
          Expanded(child: _isAudio ? _audioBody(p) : _videoBody(p)),
          _controls(p),
        ],
      ),
    );
  }

  Widget _poster() {
    final thumb = widget.file.thumbUrl;
    return thumb == null
        ? const SizedBox.shrink()
        : NetImage(url: thumb, fit: BoxFit.contain);
  }

  Widget _videoBody(AppPalette p) {
    final c = _video;
    final ready = c != null && c.value.isInitialized;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggle,
      child: Container(
        alignment: Alignment.center,
        child: _failed
            ? _error(p)
            : Stack(
                alignment: Alignment.center,
                children: [
                  if (ready)
                    AspectRatio(
                      aspectRatio: c.value.aspectRatio,
                      child: VideoPlayer(c),
                    )
                  else ...[
                    Positioned.fill(child: _poster()),
                    SizedBox(
                      width: AppIconSize.md,
                      height: AppIconSize.md,
                      child: CircularProgressIndicator(
                        strokeWidth: AppSizes.attachProgress,
                        color: p.accent,
                      ),
                    ),
                  ],
                  if (ready && !c.value.isPlaying)
                    AppIcon(
                      AppIcons.play,
                      size: AppSizes.previewAudioIcon,
                      color: p.textPrimary,
                    ),
                ],
              ),
      ),
    );
  }

  Widget _audioBody(AppPalette p) {
    final t = context.text;
    return Column(
      children: [
        Expanded(
          child: Center(
            child: _failed
                ? _error(p)
                : AppIcon(
                    AppIcons.audio,
                    size: AppSizes.previewAudioIcon,
                    color: p.textTertiary,
                  ),
          ),
        ),
        Container(
          constraints: const BoxConstraints(
            maxHeight: AppSizes.previewTranscriptMax,
          ),
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.screenPadding),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: p.border)),
          ),
          child: !_transcriptDone
              ? Text(AppStrings.previewTranscript, style: t.caption)
              : (_transcript == null || _transcript!.isEmpty)
              ? Text(AppStrings.previewNoTranscript, style: t.caption)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(AppStrings.previewTranscript, style: t.caption),
                    const SizedBox(height: AppSpacing.xs),
                    Flexible(
                      child: SingleChildScrollView(
                        child: SelectableText(_transcript!, style: t.bodySmall),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _error(AppPalette p) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        AppStrings.previewLoadFailed,
        style: context.text.label.copyWith(color: p.error),
      ),
      const SizedBox(height: AppSpacing.sm),
      TextButton(
        onPressed: () {
          Haptics.tap();
          _video?.dispose();
          setState(() {
            _video = null;
            _failed = false;
          });
          _start(force: true);
        },
        child: Text(
          AppStrings.retry,
          style: context.text.label.copyWith(color: p.accent),
        ),
      ),
    ],
  );

  Widget _controls(AppPalette p) {
    final c = _video;
    final ready = c != null && c.value.isInitialized;
    final total = ready ? c.value.duration.inMilliseconds.toDouble() : 0.0;
    final pos = ready
        ? (_dragging ? _dragMs : c.value.position.inMilliseconds.toDouble())
              .clamp(0.0, total)
        : 0.0;
    final t = context.text;
    return SafeArea(
      top: false,
      child: Container(
        height: AppSizes.previewControlsHeight,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: p.border)),
        ),
        child: Row(
          children: [
            IconButton(
              icon: AppIcon(
                ready && c.value.isPlaying
                    ? AppIcons.pause
                    : AppIcons.playPlain,
                size: AppIconSize.lg,
                color: p.textPrimary,
              ),
              onPressed: ready ? _toggle : null,
            ),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: AppSizes.previewSeekTrack,
                  activeTrackColor: p.accent,
                  inactiveTrackColor: p.border,
                  thumbColor: p.accent,
                  overlayShape: SliderComponentShape.noOverlay,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: AppSizes.previewSeekThumb,
                    elevation: 0,
                    pressedElevation: 0,
                  ),
                ),
                child: Slider(
                  min: 0,
                  max: total <= 0 ? 1 : total,
                  value: pos,
                  onChangeStart: ready ? (_) => _dragging = true : null,
                  onChanged: ready ? (v) => setState(() => _dragMs = v) : null,
                  onChangeEnd: ready
                      ? (v) async {
                          Haptics.tap();
                          await c.seekTo(Duration(milliseconds: v.round()));
                          _dragging = false;
                          if (mounted) setState(() {});
                        }
                      : null,
                ),
              ),
            ),
            Text(
              '${formatDuration(pos / 1000)} / ${formatDuration(total / 1000)}',
              style: t.caption,
            ),
            const SizedBox(width: AppSpacing.xs),
          ],
        ),
      ),
    );
  }
}
