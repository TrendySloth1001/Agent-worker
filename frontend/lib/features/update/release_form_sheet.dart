import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants/app_sizes.dart';
import '../../core/constants/update.dart';
import '../../core/haptics.dart';
import '../../core/theme/app_palette.dart';
import '../../core/update/update_models.dart';
import '../../core/widgets/m3_kit_extras.dart';
import 'release_labels.dart';
import 'releases_controller.dart';

/// Picks the APK to upload; null when the owner backs out. A test seam.
typedef ApkPicker = Future<String?> Function();

Future<String?> pickApkFile() async {
  final files = await FilePicker.pickFiles();
  for (final f in files) {
    if (f.path != null) return f.path;
  }
  return null;
}

/// Bottom sheet to edit a release (kind, title, highlights, minimum build) or
/// to upload a new APK with those details.
class ReleaseFormSheet extends StatefulWidget {
  const ReleaseFormSheet.edit({super.key, required OwnerRelease this.release})
    : controller = null,
      pickApk = null;

  const ReleaseFormSheet.upload({
    super.key,
    required ReleasesController this.controller,
    required ApkPicker this.pickApk,
  }) : release = null;

  final OwnerRelease? release;
  final ReleasesController? controller;
  final ApkPicker? pickApk;

  bool get isUpload => release == null;

  /// Edit: returns the change, or null. Upload: returns true when done.
  static Future<T?> show<T>(BuildContext context, ReleaseFormSheet sheet) =>
      showM3Sheet<T>(context, builder: (_) => sheet);

  @override
  State<ReleaseFormSheet> createState() => _ReleaseFormSheetState();
}

class _ReleaseFormSheetState extends State<ReleaseFormSheet> {
  late final _version = TextEditingController();
  late final _build = TextEditingController();
  late final _title = TextEditingController(text: widget.release?.title);
  late final _notes = TextEditingController(
    text: widget.release?.notes.join('\n'),
  );
  late final _min = TextEditingController(
    text: widget.release?.minSupportedBuild?.toString(),
  );
  late UpdateKind _kind = widget.release?.kind ?? UpdateKind.feature;
  String? _path;
  bool _live = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_version, _build, _title, _notes, _min]) {
      c.dispose();
    }
    super.dispose();
  }

  List<String> get _noteList => [
    for (final l in _notes.text.split('\n'))
      if (l.trim().isNotEmpty) l.trim(),
  ].take(UpdateConfig.maxNotes).toList();

  int? get _minBuild => int.tryParse(_min.text.trim());

  Future<void> _pick() async {
    Haptics.tap();
    final path = await widget.pickApk!();
    if (path == null || !mounted) return;
    setState(() {
      _path = path;
      _error = null;
    });
  }

  Future<void> _save() async {
    Haptics.tap();
    final r = widget.release;
    if (r != null) {
      Navigator.of(context).pop(
        ReleaseEdit(
          kind: _kind,
          title: _title.text.trim(),
          notes: _noteList,
          minSupportedBuild: _minBuild,
          clearMin: _minBuild == null && r.minSupportedBuild != null,
        ),
      );
      return;
    }
    final build = int.tryParse(_build.text.trim());
    final version = _version.text.trim();
    if (_path == null) {
      setState(() => _error = UpdateStrings.needFile);
      return;
    }
    if (version.isEmpty || build == null) {
      setState(() => _error = UpdateStrings.needVersion);
      return;
    }
    setState(() => _error = null);
    final error = await widget.controller!.upload(
      path: _path!,
      version: version,
      build: build,
      kind: _kind,
      title: _title.text.trim(),
      notes: _noteList,
      minSupportedBuild: _minBuild,
      live: _live,
    );
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop(true);
    } else {
      Haptics.error();
      setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final upload = widget.isUpload;
    final controller = widget.controller;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.screenPadding,
          0,
          AppSpacing.screenPadding,
          AppSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: ListenableBuilder(
          listenable: controller ?? Listenable.merge(const []),
          builder: (context, _) {
            final progress = controller?.uploadProgress;
            final busy = progress != null;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  upload ? UpdateStrings.uploadTitle : UpdateStrings.editTitle,
                  style: context.text.title,
                ),
                const SizedBox(height: AppSpacing.lg),
                if (upload) ...[
                  OutlinedButton(
                    onPressed: busy ? null : _pick,
                    child: Text(
                      _path == null
                          ? UpdateStrings.pickApk
                          : _path!.split('/').last,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _version,
                          enabled: !busy,
                          decoration: const InputDecoration(
                            labelText: UpdateStrings.fieldVersion,
                            hintText: UpdateStrings.fieldVersionHint,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: TextField(
                          controller: _build,
                          enabled: !busy,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: const InputDecoration(
                            labelText: UpdateStrings.fieldBuild,
                            hintText: UpdateStrings.fieldBuildHint,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                Text(UpdateStrings.fieldKind, style: context.text.label),
                const SizedBox(height: AppSpacing.sm),
                SegmentedButton<UpdateKind>(
                  showSelectedIcon: false,
                  segments: [
                    for (final k in UpdateKind.values)
                      ButtonSegment(value: k, label: Text(kindLabel(k))),
                  ],
                  selected: {_kind},
                  onSelectionChanged: busy
                      ? null
                      : (v) {
                          Haptics.tap();
                          setState(() => _kind = v.first);
                        },
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _title,
                  enabled: !busy,
                  maxLength: UpdateSizes.titleMax,
                  decoration: const InputDecoration(
                    labelText: UpdateStrings.fieldTitle,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: _notes,
                  enabled: !busy,
                  minLines: 3,
                  maxLines: UpdateSizes.notesFieldLines,
                  decoration: const InputDecoration(
                    labelText: UpdateStrings.fieldNotes,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _min,
                  enabled: !busy,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: UpdateStrings.fieldMin,
                  ),
                ),
                if (upload)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(UpdateStrings.goLiveNow),
                    value: _live,
                    onChanged: busy
                        ? null
                        : (v) {
                            Haptics.tap();
                            setState(() => _live = v);
                          },
                  ),
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    _error!,
                    style: context.text.bodySmall.copyWith(color: p.error),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                if (busy) ...[
                  Text(
                    UpdateStrings.uploadingPercent((progress * 100).round()),
                    style: context.text.label.copyWith(color: p.textSecondary),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  LinearProgressIndicator(
                    value: progress,
                    minHeight: UpdateSizes.progressHeight,
                    color: p.accent,
                    backgroundColor: p.border,
                  ),
                ] else
                  FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(AppSizes.buttonHeight),
                      shape: const StadiumBorder(),
                      textStyle: context.text.body.copyWith(
                        fontVariations: const [FontVariation.weight(600)],
                      ),
                    ),
                    onPressed: _save,
                    child: Text(
                      upload ? UpdateStrings.uploadApk : UpdateStrings.save,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
