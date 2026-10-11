import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/constants/app_icons.dart';
import '../../core/constants/app_sizes.dart';
import '../../core/constants/app_strings.dart';
import '../../core/constants/auth_constants.dart';
import '../../core/haptics.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/system_chrome.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/dot_meter.dart';
import '../../core/widgets/user_avatar.dart';
import '../../data/account_api.dart';
import '../../data/auth_models.dart';
import '../../data/chat_api.dart';
import '../auth/auth_controller.dart';
import '../auth/widgets/auth_widgets.dart';
import '../settings/format.dart';
import '../settings/widgets/section_header.dart';

/// Account: name and photo, today's usage, password, devices, log out.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _api = const AccountApi();
  final _auth = AuthController.instance;
  late final _name = TextEditingController(text: _auth.user?.name ?? '');
  AccountInfo? _info;
  List<DeviceSession>? _sessions;
  String? _loadError;
  bool _savingName = false, _savingPhoto = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      final results = await Future.wait([_api.me(), _api.sessions()]);
      if (!mounted) return;
      final info = results[0] as AccountInfo;
      setState(() {
        _info = info;
        _sessions = results[1] as List<DeviceSession>;
      });
      await _auth.updateUser(info.user);
    } on ApiException catch (e) {
      if (mounted) setState(() => _loadError = e.message);
    }
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _saveName() async {
    final name = _name.text.trim();
    if (name.isEmpty || name == _auth.user?.name) return;
    FocusScope.of(context).unfocus();
    Haptics.tap();
    setState(() => _savingName = true);
    try {
      await _auth.updateUser(await _api.update(name: name));
      Haptics.received();
      if (mounted) _snack(ProfileStrings.saved);
    } on ApiException catch (e) {
      Haptics.error();
      if (mounted) _snack(e.message);
    } finally {
      if (mounted) setState(() => _savingName = false);
    }
  }

  Future<void> _pickPhoto() async {
    Haptics.tap();
    final hasPhoto = _auth.user?.avatarUrl != null;
    final remove = hasPhoto
        ? await showModalBottomSheet<bool>(
            context: context,
            backgroundColor: context.palette.surface,
            builder: (context) => SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: const AppIcon(AuthIcons.photo),
                    title: Text(
                      ProfileStrings.changePhoto,
                      style: context.text.label,
                    ),
                    onTap: () => Navigator.pop(context, false),
                  ),
                  ListTile(
                    leading: AppIcon(
                      AuthIcons.delete,
                      color: context.palette.error,
                    ),
                    title: Text(
                      ProfileStrings.removePhoto,
                      style: context.text.label.copyWith(
                        color: context.palette.error,
                      ),
                    ),
                    onTap: () => Navigator.pop(context, true),
                  ),
                ],
              ),
            ),
          )
        : false;
    if (remove == null || !mounted) return;
    String? avatar;
    if (!remove) {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: AuthSizes.avatarUploadPx.toDouble(),
        maxHeight: AuthSizes.avatarUploadPx.toDouble(),
        imageQuality: AuthSizes.avatarQuality,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final lower = file.name.toLowerCase();
      final mime = lower.endsWith('.png')
          ? 'image/png'
          : lower.endsWith('.webp')
          ? 'image/webp'
          : 'image/jpeg';
      avatar = 'data:$mime;base64,${base64Encode(bytes)}';
    }
    setState(() => _savingPhoto = true);
    try {
      final user = await _api.update(avatar: avatar, clearAvatar: remove);
      await _auth.updateUser(user);
      Haptics.received();
    } on ApiException catch (_) {
      Haptics.error();
      if (mounted) _snack(ProfileStrings.photoFailed);
    } finally {
      if (mounted) setState(() => _savingPhoto = false);
    }
  }

  Future<void> _revoke(DeviceSession s) async {
    Haptics.tap();
    try {
      await _api.revokeSession(s.id);
      if (mounted) {
        setState(() => _sessions = [...?_sessions]..remove(s));
      }
    } on ApiException catch (e) {
      Haptics.error();
      if (mounted) _snack(e.message);
    }
  }

  Future<void> _logOut() async {
    Haptics.tap();
    final ok = await _confirm(ProfileStrings.logOutConfirm);
    if (ok) await _auth.signOut();
  }

  Future<bool> _confirm(String message) async {
    final p = context.palette;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: p.surface,
        content: Text(message, style: context.text.body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              ProfileStrings.cancel,
              style: context.text.button.copyWith(color: p.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              ProfileStrings.logOut,
              style: context.text.button.copyWith(color: p.textPrimary),
            ),
          ),
        ],
      ),
    );
    return ok == true;
  }

  void _openSheet(Widget sheet) {
    final p = context.palette;
    Haptics.tap();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: p.surface,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppRadius.lg),
        ),
        side: BorderSide(color: p.border),
      ),
      builder: (_) => sheet,
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: systemOverlayFor(context),
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const AppIcon(AppIcons.back, size: AppIconSize.md),
            tooltip: AppStrings.back,
            onPressed: () {
              Haptics.tap();
              Navigator.pop(context);
            },
          ),
          title: const Text(ProfileStrings.title),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(AppBorder.thin),
            child: Divider(color: p.border),
          ),
        ),
        body: ListenableBuilder(
          listenable: _auth,
          builder: (context, _) => RefreshIndicator(
            color: p.accent,
            backgroundColor: p.surface,
            onRefresh: _load,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(
                AppSpacing.screenPadding,
                AppSpacing.xl,
                AppSpacing.screenPadding,
                MediaQuery.paddingOf(context).bottom + AppSpacing.xxl,
              ),
              children: [
                _header(context),
                if (_loadError != null) ...[
                  const SizedBox(height: AppSpacing.lg),
                  _LoadError(message: _loadError!, onRetry: _load),
                ],
                const SectionHeader(
                  ProfileStrings.account,
                  icon: AuthIcons.account,
                ),
                _nameEditor(context),
                SectionHeader(ProfileStrings.usage, icon: AuthIcons.usage),
                _UsageCard(info: _info),
                const SectionHeader(
                  ProfileStrings.security,
                  icon: AuthIcons.security,
                ),
                _OutlinePill(
                  label: ProfileStrings.changePassword,
                  icon: AuthIcons.password,
                  onTap: () =>
                      _openSheet(_PasswordSheet(api: _api, onDone: _snack)),
                ),
                const SectionHeader(
                  ProfileStrings.sessions,
                  icon: AuthIcons.device,
                ),
                ..._sessionRows(context),
                const SizedBox(height: AppSpacing.xxl),
                _OutlinePill(
                  label: ProfileStrings.logOut,
                  icon: AuthIcons.logOut,
                  onTap: _logOut,
                ),
                if (_auth.user?.isOwner == false) ...[
                  const SizedBox(height: AppSpacing.md),
                  _OutlinePill(
                    label: ProfileStrings.deleteAccount,
                    icon: AuthIcons.delete,
                    destructive: true,
                    onTap: () => _openSheet(_DeleteSheet(api: _api)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final user = _auth.user;
    return Column(
      children: [
        GestureDetector(
          onTap: _savingPhoto ? null : _pickPhoto,
          child: Stack(
            alignment: Alignment.center,
            children: [
              UserAvatar(user: user, size: AuthSizes.avatarProfile),
              if (_savingPhoto)
                const SizedBox(
                  width: AuthSizes.avatarProfile,
                  height: AuthSizes.avatarProfile,
                  child: CircularProgressIndicator(
                    strokeWidth: AppBorder.thick,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          user?.displayName ?? '',
          textAlign: TextAlign.center,
          style: context.text.headline,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(user?.email ?? '', style: context.text.caption),
        if (user?.isOwner == true) ...[
          const SizedBox(height: AppSpacing.sm),
          const MetaChip(ProfileStrings.owner, emphasis: true),
        ],
        TextButton(
          onPressed: _savingPhoto ? null : _pickPhoto,
          child: Text(
            ProfileStrings.changePhoto,
            style: context.text.caption.copyWith(
              color: context.palette.textPrimary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _nameEditor(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _name,
      builder: (context, value, _) {
        final changed =
            value.text.trim().isNotEmpty &&
            value.text.trim() != (_auth.user?.name ?? '');
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AuthField(
              label: ProfileStrings.name,
              controller: _name,
              icon: AuthIcons.name,
              maxLength: AuthSizes.nameMax,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _saveName(),
            ),
            if (changed || _savingName)
              PillButton(
                label: ProfileStrings.save,
                loading: _savingName,
                onPressed: _saveName,
              ),
          ],
        );
      },
    );
  }

  List<Widget> _sessionRows(BuildContext context) {
    final sessions = _sessions;
    if (sessions == null) {
      return [const _Skeleton()];
    }
    final p = context.palette;
    return [
      for (final s in sessions)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: FlatCard(
            child: Row(
              children: [
                AppIcon(
                  AuthIcons.device,
                  size: AppIconSize.md,
                  color: p.textSecondary,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.device ?? ProfileStrings.unknownDevice,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.bodySmall.copyWith(
                          color: p.textPrimary,
                        ),
                      ),
                      if (s.lastUsedAt != null)
                        Text(
                          '${ProfileStrings.lastActive} '
                          '${agoLabel(s.lastUsedAt!)}',
                          style: context.text.caption,
                        ),
                    ],
                  ),
                ),
                if (s.current)
                  const MetaChip(ProfileStrings.thisDevice, emphasis: true)
                else
                  TextButton(
                    onPressed: () => _revoke(s),
                    child: Text(
                      ProfileStrings.signOutDevice,
                      style: context.text.caption.copyWith(color: p.error),
                    ),
                  ),
              ],
            ),
          ),
        ),
    ];
  }
}

// ---- usage --------------------------------------------------------------

class _UsageCard extends StatelessWidget {
  const _UsageCard({required this.info});

  final AccountInfo? info;

  static String _mb(int bytes) {
    final mb = bytes / (1024 * 1024);
    return mb >= 10 ? '${mb.round()} MB' : '${mb.toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final i = info;
    if (i == null) return const _Skeleton();
    final l = i.limits;
    final u = i.usage;
    return FlatCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (l == null) ...[
            const MetaChip(ProfileStrings.unlimited, emphasis: true),
            const SizedBox(height: AppSpacing.md),
          ],
          _Meter(label: ProfileStrings.chats, used: u.chats, limit: l?.chat),
          _Meter(label: ProfileStrings.tables, used: u.tables, limit: l?.table),
          _Meter(
            label: ProfileStrings.uploads,
            used: u.uploads,
            limit: l?.uploads,
          ),
          _Meter(
            label: ProfileStrings.storage,
            used: u.storageBytes,
            limit: l?.storageBytes,
            format: _mb,
          ),
          if (i.resetsAt != null && l != null)
            InfoRow(
              ProfileStrings.resets,
              '${i.resetsAt!.hour.toString().padLeft(2, '0')}:'
              '${i.resetsAt!.minute.toString().padLeft(2, '0')}',
            ),
        ],
      ),
    );
  }
}

class _Meter extends StatelessWidget {
  const _Meter({
    required this.label,
    required this.used,
    required this.limit,
    this.format,
  });

  final String label;
  final int used;
  final int? limit;
  final String Function(int)? format;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final f = format ?? (int v) => '$v';
    final max = limit;
    final fraction = max == null || max <= 0 ? 0.0 : used / max;
    final full = max != null && used >= max;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: context.text.caption)),
              Text(
                max == null ? f(used) : '${f(used)} / ${f(max)}',
                style: context.text.caption.copyWith(
                  color: full ? p.error : p.textPrimary,
                ),
              ),
            ],
          ),
          if (max != null) ...[
            const SizedBox(height: AppSpacing.sm),
            DotMeter(fraction: fraction, litColor: full ? p.error : null),
          ],
        ],
      ),
    );
  }
}

// ---- small pieces -------------------------------------------------------

class _OutlinePill extends StatelessWidget {
  const _OutlinePill({
    required this.label,
    required this.icon,
    required this.onTap,
    this.destructive = false,
  });

  final String label;
  final AppIconData icon;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final color = destructive ? p.error : p.textPrimary;
    return SizedBox(
      height: AppSizes.buttonHeight,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          shape: const StadiumBorder(),
          side: BorderSide(
            color: destructive ? p.error : p.borderStrong,
            width: AppBorder.thin,
          ),
          foregroundColor: color,
        ),
        onPressed: onTap,
        icon: AppIcon(icon, size: AppIconSize.sm, color: color),
        label: Text(label, style: context.text.button.copyWith(color: color)),
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) => Container(
    height: AppSizes.rowHeight,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(AppRadius.md),
      border: Border.all(color: context.palette.border),
    ),
  );
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        FormError('${ProfileStrings.loadFailed} $message'),
        TextButton(onPressed: onRetry, child: const Text(ProfileStrings.retry)),
      ],
    );
  }
}

/// Bottom-sheet body that stays above the keyboard.
class _SheetBody extends StatelessWidget {
  const _SheetBody({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: context.text.label),
              const SizedBox(height: AppSpacing.xl),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

// ---- change password ----------------------------------------------------

class _PasswordSheet extends StatefulWidget {
  const _PasswordSheet({required this.api, required this.onDone});

  final AccountApi api;
  final ValueChanged<String> onDone;

  @override
  State<_PasswordSheet> createState() => _PasswordSheetState();
}

class _PasswordSheetState extends State<_PasswordSheet> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  String? _nextError, _error;
  bool _loading = false;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_next.text.length < AuthSizes.minPassword) {
      Haptics.error();
      setState(() => _nextError = AuthStrings.errPasswordShort);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.api.changePassword(_current.text, _next.text);
      Haptics.received();
      if (!mounted) return;
      Navigator.pop(context);
      widget.onDone(ProfileStrings.passwordChanged);
    } on ApiException catch (e) {
      Haptics.error();
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SheetBody(
      title: ProfileStrings.changePassword,
      children: [
        AuthField(
          label: ProfileStrings.currentPassword,
          controller: _current,
          icon: AuthIcons.password,
          obscure: true,
          enabled: !_loading,
          autofillHints: const [AutofillHints.password],
        ),
        AuthField(
          label: ProfileStrings.newPassword,
          hint: AuthStrings.passwordHint,
          controller: _next,
          icon: AuthIcons.password,
          obscure: true,
          enabled: !_loading,
          error: _nextError,
          autofillHints: const [AutofillHints.newPassword],
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
          onChanged: (_) => setState(() => _nextError = null),
        ),
        if (_next.text.isNotEmpty) StrengthHint(password: _next.text),
        FormError(_error),
        PillButton(
          label: ProfileStrings.changePassword,
          loading: _loading,
          onPressed: _submit,
        ),
      ],
    );
  }
}

// ---- delete account -----------------------------------------------------

class _DeleteSheet extends StatefulWidget {
  const _DeleteSheet({required this.api});

  final AccountApi api;

  @override
  State<_DeleteSheet> createState() => _DeleteSheetState();
}

class _DeleteSheetState extends State<_DeleteSheet> {
  final _word = TextEditingController();
  final _password = TextEditingController();
  String? _error;
  bool _loading = false;

  @override
  void dispose() {
    _word.dispose();
    _password.dispose();
    super.dispose();
  }

  bool get _ready =>
      _word.text.trim() == ProfileStrings.deleteWord &&
      _password.text.isNotEmpty;

  Future<void> _submit() async {
    if (!_ready) return;
    Haptics.tap();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.api.deleteAccount(_password.text);
      Haptics.received();
      if (mounted) Navigator.pop(context);
      await AuthController.instance.signOut(callServer: false);
    } on ApiException catch (e) {
      Haptics.error();
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return _SheetBody(
      title: ProfileStrings.deleteAccount,
      children: [
        Text(
          ProfileStrings.deleteWarning,
          style: context.text.bodySmall.copyWith(color: p.textPrimary),
        ),
        const SizedBox(height: AppSpacing.xl),
        AuthField(
          label: ProfileStrings.deleteTypeHint.toUpperCase(),
          hint: ProfileStrings.deleteWord,
          controller: _word,
          icon: AuthIcons.delete,
          enabled: !_loading,
          textCapitalization: TextCapitalization.characters,
          onChanged: (_) => setState(() {}),
        ),
        AuthField(
          label: AuthStrings.password,
          hint: ProfileStrings.deletePassword,
          controller: _password,
          icon: AuthIcons.password,
          obscure: true,
          enabled: !_loading,
          textInputAction: TextInputAction.done,
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _submit(),
        ),
        FormError(_error),
        PillButton(
          label: ProfileStrings.deleteAccount,
          destructive: true,
          loading: _loading,
          onPressed: _ready ? _submit : null,
        ),
      ],
    );
  }
}
