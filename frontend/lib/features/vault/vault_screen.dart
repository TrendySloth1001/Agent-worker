import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/constants/app_sizes.dart';
import '../../core/constants/vault.dart';
import '../../core/haptics.dart';
import '../../core/platform/secure_screen.dart';
import '../../core/theme/app_palette.dart';
import '../../core/time_ago.dart';
import '../../core/vault/vault_api.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/confirm_sheet.dart';
import '../../core/widgets/input_sheet.dart';
import '../../core/widgets/m3_kit_extras.dart';
import '../../data/chat_api.dart' show ApiException;
import '../auth/auth_controller.dart';
import '../settings/settings_pages.dart' show isOwner;
import '../settings/widgets/settings_kit.dart';
import '../settings/widgets/usage_states.dart';

/// Owner-only: the server's master key behind the owner's password. Every
/// seal and reveal asks for the password again; the key is shown blurred,
/// hides itself after [VaultConfig.autoHide], and the screen is FLAG_SECURE
/// while it is visible.
class VaultScreen extends StatefulWidget {
  const VaultScreen({
    super.key,
    this.api,
    this.owner,
    this.hasPassword,
    this.autoHide = VaultConfig.autoHide,
    this.clipboardClear = VaultConfig.clipboardClear,
    this.secure,
    this.saveFile,
    this.now,
  });

  /// Test seams: the API, the owner and has-password checks, timings, the
  /// secure-screen switch, the file saver and the clock.
  final VaultApi? api;
  final bool Function()? owner;
  final bool Function()? hasPassword;
  final Duration autoHide;
  final Duration clipboardClear;
  final Future<void> Function(bool on)? secure;
  final Future<void> Function(String text)? saveFile;
  final DateTime Function()? now;

  /// Opens the screen for the owner; does nothing for anyone else.
  static Future<void> open(
    BuildContext context, {
    VaultApi? api,
    bool Function()? owner,
  }) async {
    if (!(owner ?? isOwner)()) return;
    await Navigator.push(
      context,
      settingsRoute(VaultScreen(api: api, owner: owner)),
    );
  }

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

/// Clearing outlives the screen: popping it must not leave the key on the clipboard.
Timer? _clipboardTimer;

class _VaultScreenState extends State<VaultScreen> {
  late final VaultApi _api = widget.api ?? VaultApi();
  bool get _allowed => (widget.owner ?? isOwner)();
  bool get _hasPassword =>
      (widget.hasPassword ??
      () => AuthController.instance.user?.hasPassword ?? true)();
  Future<void> _secure(bool on) => (widget.secure ?? SecureScreen.set)(on);
  DateTime get _now => (widget.now ?? DateTime.now)();

  VaultStatus? _status;
  bool _loading = false;
  bool _failed = false;
  bool _busy = false;
  String? _error;
  String? _key;
  bool _blurred = true;
  int _left = 0;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    if (_allowed) _load();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    if (_key != null) _secure(false);
    _key = null;
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final s = await _api.status();
      if (!mounted) return;
      setState(() => _status = s);
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _message(Object e) {
    if (e is ApiException) {
      switch (e.code) {
        case 'wrong_password':
          return VaultStrings.wrongPassword;
        case 'vault_locked':
          return VaultStrings.locked;
        case 'needs_reseal':
          return VaultStrings.needsResealError;
        case 'password_not_set':
          return VaultStrings.noPasswordHint;
      }
    }
    return VaultStrings.generic;
  }

  /// Asks for the password in a sheet; null when cancelled or empty.
  Future<String?> _askPassword(String title) async {
    final c = TextEditingController();
    var hidden = true;
    final ok = await InputSheet.show(
      context,
      kicker: VaultStrings.sheetKicker,
      title: title,
      body: VaultStrings.sheetBody,
      confirmLabel: title,
      field: (sheet, submit) => StatefulBuilder(
        builder: (context, setLocal) => TextField(
          key: const ValueKey('vault-password'),
          controller: c,
          autofocus: true,
          obscureText: hidden,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => submit(),
          decoration: InputDecoration(
            labelText: VaultStrings.passwordLabel,
            suffixIcon: IconButton(
              tooltip: hidden
                  ? VaultStrings.showPassword
                  : VaultStrings.hidePassword,
              icon: AppIcon(
                hidden ? VaultIcons.show : VaultIcons.hide,
                size: AppIconSize.md,
              ),
              onPressed: () {
                Haptics.tap();
                setLocal(() => hidden = !hidden);
              },
            ),
          ),
        ),
      ),
    );
    final pw = c.text;
    // Not disposed: the sheet's field is still animating out. Wiped instead.
    c.clear();
    return ok && pw.isNotEmpty ? pw : null;
  }

  Future<void> _seed() async {
    final pw = await _askPassword(VaultStrings.sheetSetUpTitle);
    if (pw == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final s = await _api.seed(pw);
      if (!mounted) return;
      Haptics.received();
      setState(() => _status = s);
      _snack(VaultStrings.sealedDone);
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reveal() async {
    final pw = await _askPassword(VaultStrings.sheetRevealTitle);
    if (pw == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final key = await _api.reveal(pw);
      if (!mounted) return;
      await _secure(true);
      Haptics.received();
      setState(() {
        _key = key;
        _blurred = true;
        _left = widget.autoHide.inSeconds;
      });
      _hideTimer?.cancel();
      _hideTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) return t.cancel();
        if (t.tick >= widget.autoHide.inSeconds) return _hideKey();
        setState(() => _left = widget.autoHide.inSeconds - t.tick);
      });
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _hideKey() {
    _hideTimer?.cancel();
    _secure(false);
    if (mounted) setState(() => _key = null);
  }

  void _snack(String text) {
    if (!mounted) return;
    final m = ScaffoldMessenger.maybeOf(context);
    m?.hideCurrentSnackBar();
    m?.showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _copy() async {
    final key = _key;
    if (key == null) return;
    Haptics.tap();
    await Clipboard.setData(ClipboardData(text: key));
    _clipboardTimer?.cancel();
    _clipboardTimer = Timer(widget.clipboardClear, () async {
      try {
        final now = await Clipboard.getData(Clipboard.kTextPlain);
        if (now?.text == key) {
          await Clipboard.setData(const ClipboardData(text: ''));
        }
      } catch (_) {}
    });
    _snack(VaultStrings.copied);
  }

  Future<void> _save() async {
    final key = _key;
    if (key == null) return;
    Haptics.tap();
    try {
      await (widget.saveFile ?? _shareFile)(key);
    } catch (_) {
      _snack(VaultStrings.generic);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_allowed) {
      return const M3Page(
        title: VaultStrings.screenTitle,
        slivers: [
          M3Body(
            children: [
              M3Empty(icon: VaultIcons.entry, title: VaultStrings.notOwner),
            ],
          ),
        ],
      );
    }
    return M3Page(
      title: VaultStrings.screenTitle,
      onRefresh: _key == null ? _load : null,
      slivers: [M3Body(children: _children(context))],
    );
  }

  List<Widget> _children(BuildContext context) {
    final p = context.palette;
    if (_status == null) {
      if (_failed && !_loading) {
        return [
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.lg),
            child: UsageError(onRetry: _load, loading: _loading),
          ),
        ];
      }
      return [
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xl),
          child: LinearProgressIndicator(
            minHeight: AppBorder.thin,
            color: p.accent,
            backgroundColor: p.border,
          ),
        ),
      ];
    }
    final s = _status!;
    return [
      _StatusCard(status: s, now: _now),
      const SizedBox(height: AppSpacing.md),
      M3Card(
        child: Text(
          VaultStrings.explain,
          key: const ValueKey('vault-explain'),
          style: context.text.bodySmall.copyWith(color: p.textSecondary),
        ),
      ),
      const SizedBox(height: AppSpacing.md),
      if (!_hasPassword)
        M3Card(
          key: const ValueKey('vault-no-password'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(VaultStrings.noPasswordTitle, style: context.text.title),
              const SizedBox(height: AppSpacing.xs),
              Text(
                VaultStrings.noPasswordHint,
                style: context.text.bodySmall.copyWith(color: p.textSecondary),
              ),
            ],
          ),
        )
      else ...[
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Text(
              _error!,
              key: const ValueKey('vault-error'),
              style: context.text.bodySmall.copyWith(color: p.error),
            ),
          ),
        if (_key != null)
          _KeyCard(
            secret: _key!,
            blurred: _blurred,
            secondsLeft: _left,
            onToggle: () => setState(() => _blurred = !_blurred),
            onCopy: _copy,
            onSave: _save,
            onHide: _hideKey,
          )
        else
          _Actions(
            state: s.state,
            busy: _busy,
            onSeed: _seed,
            onReveal: _reveal,
          ),
      ],
    ];
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.status, required this.now});

  final VaultStatus status;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (icon, title, hint, color) = switch (status.state) {
      VaultState.sealed => (
        VaultIcons.sealed,
        VaultStrings.sealed,
        VaultStrings.sealedHint,
        p.accent,
      ),
      VaultState.notSetUp => (
        VaultIcons.notSetUp,
        VaultStrings.notSetUp,
        VaultStrings.notSetUpHint,
        p.textTertiary,
      ),
      VaultState.needsReseal => (
        VaultIcons.needsReseal,
        VaultStrings.needsReseal,
        VaultStrings.needsResealHint,
        p.error,
      ),
    };
    final at = status.updatedAt;
    return M3Card(
      key: const ValueKey('vault-status'),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppIcon(icon, size: AppIconSize.empty, color: color),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.text.title),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  hint,
                  style: context.text.bodySmall.copyWith(
                    color: p.textSecondary,
                  ),
                ),
                if (at != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '${VaultStrings.updated}: ${timeAgo(at, now)}',
                    style: context.text.caption.copyWith(color: p.textTertiary),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.state,
    required this.busy,
    required this.onSeed,
    required this.onReveal,
  });

  final VaultState state;
  final bool busy;
  final VoidCallback onSeed;
  final VoidCallback onReveal;

  @override
  Widget build(BuildContext context) {
    final pill = sheetPillStyle(context);
    final canReveal = state == VaultState.sealed;
    final seedLabel = state == VaultState.notSetUp
        ? VaultStrings.setUp
        : VaultStrings.reSeal;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (canReveal) ...[
          FilledButton(
            key: const ValueKey('vault-reveal'),
            style: pill,
            onPressed: busy ? null : onReveal,
            child: const Text(VaultStrings.reveal),
          ),
          const SizedBox(height: VaultSizes.buttonGap),
          OutlinedButton(
            key: const ValueKey('vault-seed'),
            style: pill,
            onPressed: busy ? null : onSeed,
            child: Text(seedLabel),
          ),
        ] else
          FilledButton(
            key: const ValueKey('vault-seed'),
            style: pill,
            onPressed: busy ? null : onSeed,
            child: Text(seedLabel),
          ),
      ],
    );
  }
}

class _KeyCard extends StatelessWidget {
  const _KeyCard({
    required this.secret,
    required this.blurred,
    required this.secondsLeft,
    required this.onToggle,
    required this.onCopy,
    required this.onSave,
    required this.onHide,
  });

  final String secret;
  final bool blurred;
  final int secondsLeft;
  final VoidCallback onToggle;
  final VoidCallback onCopy;
  final VoidCallback onSave;
  final VoidCallback onHide;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final pill = sheetPillStyle(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SettingsGroupHeader(VaultStrings.keyHeader),
        GestureDetector(
          key: const ValueKey('vault-key-box'),
          behavior: HitTestBehavior.opaque,
          onTap: () {
            Haptics.tap();
            onToggle();
          },
          child: Container(
            constraints: const BoxConstraints(
              minHeight: VaultSizes.keyBoxMinHeight,
            ),
            padding: const EdgeInsets.all(VaultSizes.keyBoxPadding),
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: p.border),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                ImageFiltered(
                  enabled: blurred,
                  imageFilter: ImageFilter.blur(
                    sigmaX: VaultSizes.blurSigma,
                    sigmaY: VaultSizes.blurSigma,
                  ),
                  child: SelectableText(
                    secret,
                    key: const ValueKey('vault-key-text'),
                    style: context.text.code.copyWith(color: p.textPrimary),
                  ),
                ),
                if (blurred)
                  Text(
                    VaultStrings.tapToShow,
                    style: context.text.caption.copyWith(
                      color: p.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          '${VaultStrings.hidesIn} ${VaultStrings.seconds(secondsLeft)}',
          key: const ValueKey('vault-countdown'),
          style: context.text.caption.copyWith(color: p.textTertiary),
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                key: const ValueKey('vault-copy'),
                style: pill,
                onPressed: onCopy,
                icon: const AppIcon(VaultIcons.copy, size: AppIconSize.md),
                label: const Text(VaultStrings.copy),
              ),
            ),
            const SizedBox(width: VaultSizes.buttonGap),
            Expanded(
              child: OutlinedButton.icon(
                key: const ValueKey('vault-save'),
                style: pill,
                onPressed: onSave,
                icon: const AppIcon(VaultIcons.save, size: AppIconSize.md),
                label: const Text(VaultStrings.saveFile),
              ),
            ),
          ],
        ),
        const SizedBox(height: VaultSizes.buttonGap),
        TextButton(
          key: const ValueKey('vault-hide'),
          onPressed: onHide,
          child: const Text(VaultStrings.hide),
        ),
      ],
    );
  }
}

/// Writes the key to a temp file and opens the system share/save sheet, then
/// deletes the file again.
Future<void> _shareFile(String text) async {
  final dir = await getTemporaryDirectory();
  final f = File('${dir.path}${Platform.pathSeparator}${VaultConfig.fileName}');
  await f.writeAsString(text, flush: true);
  try {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(f.path, mimeType: VaultConfig.fileMime)],
        fileNameOverrides: const [VaultConfig.fileName],
      ),
    );
  } finally {
    try {
      await f.delete();
    } catch (_) {}
  }
}
