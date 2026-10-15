import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/preview.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/segmented.dart';
import '../../../data/files_api.dart';
import 'preview_type.dart';
import 'sparky_view.dart';

/// The two ways to look at a file: as it is, or what sparky understood.
enum PreviewView { original, sparky }

/// Office files cannot be drawn here, so they open on what sparky read;
/// everything else opens on the file itself.
PreviewView defaultViewOf(PreviewType t) =>
    t == PreviewType.office ? PreviewView.sparky : PreviewView.original;

/// Only a file the server holds has a sparky view (a picked file that is
/// not uploaded yet has nothing to read).
bool hasSparkyView(FileInfo f) =>
    f.id.isNotEmpty && !f.deleted && previewTypeOf(f) != PreviewType.unknown;

/// The last view picked for each type of file, kept on this phone.
abstract final class PreviewViewPrefs {
  static String _key(PreviewType t) => '${PreviewConfig.viewPrefsKey}${t.name}';

  static Future<PreviewView> load(PreviewType t) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_key(t));
      return PreviewView.values.firstWhere(
        (v) => v.name == saved,
        orElse: () => defaultViewOf(t),
      );
    } catch (_) {
      return defaultViewOf(t);
    }
  }

  static Future<void> save(PreviewType t, PreviewView v) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key(t), v.name);
    } catch (_) {
      /* a preference that cannot be saved is only forgotten */
    }
  }
}

/// State of a preview screen that offers both views: starts on the default
/// for the type, switches to the saved choice once read, and saves picks.
mixin PreviewViewMixin<T extends StatefulWidget> on State<T> {
  FileInfo get viewFile;

  late final PreviewType viewType = previewTypeOf(viewFile);
  late PreviewView view = hasSparkyView(viewFile)
      ? defaultViewOf(viewType)
      : PreviewView.original;
  bool _picked = false;

  bool get canSwitchView => hasSparkyView(viewFile);

  /// Call from initState.
  void loadSavedView() {
    if (!canSwitchView) return;
    PreviewViewPrefs.load(viewType).then((v) {
      if (mounted && !_picked && v != view) {
        setState(() => view = v);
        onViewChanged(v);
      }
    });
  }

  void pickView(PreviewView v) {
    if (v == view) return;
    _picked = true;
    setState(() => view = v);
    PreviewViewPrefs.save(viewType, v);
    onViewChanged(v);
  }

  /// A hook for screens that must stop something (a player) on a switch.
  void onViewChanged(PreviewView v) {}
}

/// ORIGINAL | SPARKY switch for the top bar.
class PreviewViewToggle extends StatelessWidget {
  const PreviewViewToggle({
    super.key,
    required this.view,
    required this.onChanged,
    this.dark = false,
  });

  final PreviewView view;
  final ValueChanged<PreviewView> onChanged;

  /// On a black bar (image and video stage): the dark theme's colors.
  final bool dark;

  @override
  Widget build(BuildContext context) {
    Widget toggle = Semantics(
      label: PreviewStrings.viewSemantics,
      container: true,
      child: SizedBox(
        height: PreviewSizes.toggleHeight,
        width: PreviewSizes.toggleMaxWidth,
        child: Segmented<PreviewView>(
          value: view,
          onChanged: onChanged,
          options: const [
            (PreviewView.original, PreviewStrings.viewOriginal),
            (PreviewView.sparky, PreviewStrings.viewSparky),
          ],
          icons: const {
            PreviewView.original: PreviewIcons.viewOriginal,
            PreviewView.sparky: PreviewIcons.viewSparky,
          },
        ),
      ),
    );
    if (dark) toggle = Theme(data: AppTheme.dark, child: toggle);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenPadding,
        0,
        AppSpacing.screenPadding,
        AppSpacing.sm,
      ),
      child: Center(child: toggle),
    );
  }
}

/// Both views of one file in a stack: the original keeps its state (scroll
/// position, a player) while the sparky view is shown, and the sparky view
/// is only built, and its reading only fetched, once it is first opened.
class DualBody extends StatefulWidget {
  const DualBody({
    super.key,
    required this.view,
    required this.file,
    required this.original,
  });

  final PreviewView view;
  final FileInfo file;
  final Widget original;

  @override
  State<DualBody> createState() => _DualBodyState();
}

class _DualBodyState extends State<DualBody> {
  bool _opened = false;

  @override
  Widget build(BuildContext context) {
    final sparky = widget.view == PreviewView.sparky;
    if (sparky) _opened = true;
    return Stack(
      fit: StackFit.expand,
      children: [
        Offstage(
          offstage: sparky,
          child: TickerMode(enabled: !sparky, child: widget.original),
        ),
        if (_opened)
          Offstage(
            offstage: !sparky,
            child: SparkyView(
              key: ValueKey('${widget.file.id}/${widget.file.name}'),
              file: widget.file,
            ),
          ),
      ],
    );
  }
}
