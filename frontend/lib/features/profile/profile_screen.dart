import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/constants/error_copy.dart';
import '../../core/constants/app_icons.dart';
import '../../core/constants/app_sizes.dart';
import '../../core/constants/auth_constants.dart';
import '../../core/constants/profile_copy.dart';
import '../../core/constants/settings_copy.dart';
import '../../core/constants/sso_constants.dart';
import '../../core/haptics.dart';
import '../../core/platform/google_auth.dart';
import '../../core/theme/app_palette.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/dot_meter.dart';
import '../../core/widgets/dot_matrix_backdrop.dart';
import '../../core/widgets/user_avatar.dart';
import '../../data/account_api.dart';
import '../../data/auth_models.dart';
import '../../data/chat_api.dart';
import '../../data/sso_api.dart';
import '../about/about_screen.dart';
import '../auth/auth_controller.dart';
import '../auth/widgets/auth_widgets.dart';
import '../auth/widgets/github_device_sheet.dart';
import '../auth/widgets/github_web_sheet.dart';
import '../connections/connections_controller.dart';
import '../settings/format.dart';
import '../settings/widgets/section_header.dart';
import '../settings/widgets/settings_kit.dart';
import '../storage/storage_screen.dart';
import '../../core/constants/storage.dart';
import 'widgets/sign_in_methods.dart';

/// Account: name and photo, today's usage, sign-in methods, password,
/// devices, log out.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _api = const AccountApi();
  final _auth = AuthController.instance;
  AccountInfo? _info;
  List<DeviceSession>? _sessions;
  SignInMethods? _methods;
  SsoProviders? _providers;
  String? _loadError, _methodsError;

  /// Provider or identity id with a link/unlink running.
  String? _methodBusy;
  bool _savingPhoto = false;

  bool get _hasPassword =>
      _methods?.hasPassword ?? _auth.user?.hasPassword ?? true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loadError = null);
    _loadMethods();
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
      if (mounted) setState(() => _loadError = friendlyException(e));
    }
  }

  Future<void> _loadMethods() async {
    final sso = SsoApi.instance;
    sso.providers().then((p) {
      if (mounted) setState(() => _providers = p);
    }, onError: (_) {});
    try {
      final m = await sso.methods();
      if (mounted) {
        setState(() {
          _methods = m;
          _methodsError = null;
        });
      }
    } on ApiException catch (_) {
      if (mounted) setState(() => _methodsError = SsoStrings.methodsFailed);
    }
  }

  Future<void> _linkGithub() async {
    setState(() => _methodBusy = SsoProviderIds.github);
    try {
      if (_providers?.githubWeb ?? false) {
        final w = await showGithubWebSheet(
          context,
          title: SsoStrings.linkTitle,
          mode: GithubWeb.link,
        );
        if (!mounted) return;
        if (w == GithubWebSheetResult.done) {
          await _loadMethods();
          return;
        }
        if (w != GithubWebSheetResult.useCode) return;
      }
      final r = await showGithubDeviceSheet(
        context,
        title: SsoStrings.linkTitle,
        start: SsoApi.instance.startGithubLink,
        poll: SsoApi.instance.pollGithubLink,
      );
      if (r == null || !mounted) return;
      _snack(SsoStrings.linked);
      // The same grant also connected GitHub.
      ConnectionsController.instance.refresh();
      await _loadMethods();
    } finally {
      if (mounted) setState(() => _methodBusy = null);
    }
  }

  Future<void> _linkGoogle() async {
    final clientId = _providers?.googleWebClientId;
    if (clientId == null) return;
    setState(() => _methodBusy = SsoProviderIds.google);
    try {
      final token = await GoogleAuth.idToken(clientId);
      if (token == null) return;
      await SsoApi.instance.linkGoogle(token);
      Haptics.received();
      if (!mounted) return;
      _snack(SsoStrings.linked);
      await _loadMethods();
    } on ApiException catch (e) {
      Haptics.error();
      if (mounted) _snack(friendlyException(e));
    } finally {
      if (mounted) setState(() => _methodBusy = null);
    }
  }

  Future<void> _unlink(LinkedIdentity i) async {
    final name = i.provider == SsoProviderIds.github
        ? SsoStrings.githubLabel
        : SsoStrings.googleLabel;
    final p = context.palette;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: p.surface,
        title: Text(SsoStrings.unlinkTitle(name), style: context.text.title),
        content: Text(
          SsoStrings.unlinkBody(name),
          style: context.text.bodySmall,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              SsoStrings.keep,
              style: Theme.of(
                context,
              ).textTheme.labelLarge!.copyWith(color: p.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              SsoStrings.unlink,
              style: Theme.of(
                context,
              ).textTheme.labelLarge!.copyWith(color: p.error),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _methodBusy = i.id);
    try {
      await SsoApi.instance.unlink(i.id);
      Haptics.received();
      if (!mounted) return;
      _snack(SsoStrings.unlinked);
      await _loadMethods();
    } on ApiException catch (e) {
      Haptics.error();
      if (mounted) _snack(friendlyException(e));
    } finally {
      if (mounted) setState(() => _methodBusy = null);
    }
  }

  void _openPasswordSheet() => _openSheet(
    _PasswordSheet(
      api: _api,
      hasPassword: _hasPassword,
      onDone: (message) {
        _snack(message);
        _load();
      },
    ),
  );

  void _snack(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _saveName(String value) async {
    final name = value.trim();
    if (name.isEmpty || name == _auth.user?.name) return;
    try {
      await _auth.updateUser(await _api.update(name: name));
      Haptics.received();
      if (mounted) _snack(ProfileStrings.saved);
    } on ApiException catch (e) {
      Haptics.error();
      if (mounted) _snack(friendlyException(e));
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
      if (mounted) _snack(friendlyException(e));
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
              style: Theme.of(
                context,
              ).textTheme.labelLarge!.copyWith(color: p.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              ProfileStrings.logOut,
              style: Theme.of(
                context,
              ).textTheme.labelLarge!.copyWith(color: p.textPrimary),
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
    return ListenableBuilder(
      listenable: _auth,
      builder: (context, _) => SettingsScaffold(
        title: ProfileCopy.title,
        onRefresh: _load,
        children: [
          _hero(context),
          if (_loadError != null)
            _LoadError(message: _loadError!, onRetry: _load),
          const SettingsGroupHeader(ProfileCopy.accountGroup),
          SettingsGroup(
            entries: [
              GroupEntry(
                SettingsTile(
                  icon: AuthIcons.name,
                  title: ProfileCopy.nameTitle,
                  summary: _auth.user?.displayName ?? '',
                  trailing: const AppIcon(AppIcons.edit, size: AppIconSize.md),
                  onTap: _editName,
                ),
              ),
              GroupEntry(
                SettingsTile(
                  icon: AuthIcons.photo,
                  title: ProfileCopy.changePhoto,
                  onTap: _savingPhoto ? null : _pickPhoto,
                ),
              ),
              GroupEntry(
                SettingsTile(
                  icon: AuthIcons.email,
                  title: ProfileCopy.emailTitle,
                  summary: _auth.user?.email ?? '',
                ),
              ),
            ],
          ),
          const SettingsGroupHeader(ProfileCopy.todayGroup),
          SettingsGroup(
            entries: [
              GroupEntry(_UsageCard(info: _info)),
              GroupEntry(
                SettingsTile(
                  icon: StorageIcons.section,
                  title: ProfileCopy.manageStorage,
                  onTap: () => StorageScreen.open(context),
                ),
              ),
            ],
          ),
          const SettingsGroupHeader(ProfileCopy.methodsGroup),
          _methodGroup(),
          const SettingsGroupHeader(ProfileCopy.securityGroup),
          SettingsGroup(
            entries: [
              GroupEntry(
                SettingsTile(
                  icon: AuthIcons.password,
                  title: _hasPassword
                      ? ProfileCopy.changePassword
                      : ProfileCopy.setPassword,
                  onTap: _openPasswordSheet,
                ),
              ),
            ],
          ),
          const SettingsGroupHeader(ProfileCopy.devicesGroup),
          _deviceGroup(),
          const SizedBox(height: SettingsSizes.groupSpacing),
          SettingsGroup(
            entries: [
              GroupEntry(
                SettingsTile(
                  icon: AuthIcons.logOut,
                  title: ProfileCopy.logOut,
                  summary: ProfileCopy.logOutHelp,
                  onTap: _logOut,
                ),
              ),
              if (_auth.user?.isOwner == false)
                GroupEntry(
                  SettingsTile(
                    icon: AuthIcons.delete,
                    title: ProfileCopy.deleteAccount,
                    summary: ProfileCopy.deleteHelp,
                    iconColor: Theme.of(context).colorScheme.error,
                    titleColor: Theme.of(context).colorScheme.error,
                    onTap: () => _openSheet(
                      _DeleteSheet(api: _api, hasPassword: _hasPassword),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          const AboutFooterLink(),
        ],
      ),
    );
  }

  static const _ringSize =
      SettingsSizes.heroAvatar + 2 * SettingsSizes.heroRingWidth;

  /// The badge's centre sits on the avatar's bottom-right edge (45 degrees).
  static final _badgeInset =
      _ringSize / 2 -
      SettingsSizes.heroAvatar / 2 * math.cos(math.pi / 4) -
      SettingsSizes.heroBadge / 2;

  /// Shapes the dots into a ring: clear under the avatar, soft at both edges.
  static Shader _ringMask(Rect rect) {
    const r = _ringSize / 2;
    const inner = SettingsSizes.heroAvatar / 2;
    const fade = SettingsSizes.heroRingFade;
    return RadialGradient(
      radius: 0.5,
      colors: const [
        Color(0x00000000),
        Color(0x00000000),
        Color(0xFF000000),
        Color(0xFF000000),
        Color(0x00000000),
      ],
      stops: const [0, (inner - 2) / r, (inner + fade) / r, (r - fade) / r, 1],
    ).createShader(rect);
  }

  /// Large avatar in a ring of dots, name, email, and tiny mono metadata.
  Widget _hero(BuildContext context) {
    final user = _auth.user;
    final tt = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final id = user?.id ?? '';
    final shortId = id.length > ProfileCopy.idChars
        ? id.substring(0, ProfileCopy.idChars)
        : id;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Column(
        children: [
          SizedBox(
            width: SettingsSizes.heroDotField,
            height: SettingsSizes.heroDotField,
            // A thin ring of animated dots around the avatar: ink at rest,
            // red only where the opening wave or a touch passes. The avatar
            // and the edit badge sit on top (taps still work).
            child: Center(
              child: SizedBox(
                width: _ringSize,
                height: _ringSize,
                child: DotMatrixBackdrop.page(
                  spacing: SettingsSizes.heroDotSpacing,
                  glow: false,
                  mask: _ringMask,
                  child: SizedBox.square(
                    dimension: _ringSize,
                    child: Stack(
                      alignment: Alignment.center,
                      clipBehavior: Clip.none,
                      children: [
                        Semantics(
                          button: true,
                          label: ProfileCopy.changePhoto,
                          child: GestureDetector(
                            onTap: _savingPhoto ? null : _pickPhoto,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                _HeroAvatar(user: user),
                                if (_savingPhoto)
                                  const SizedBox(
                                    width: SettingsSizes.heroAvatar,
                                    height: SettingsSizes.heroAvatar,
                                    child: CircularProgressIndicator(
                                      strokeWidth: AppBorder.thick,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        Positioned(
                          right: _badgeInset,
                          bottom: _badgeInset,
                          child: _EditBadge(
                            onPressed: _savingPhoto ? null : _pickPhoto,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Text(
            user?.displayName ?? '',
            textAlign: TextAlign.center,
            style: tt.headlineSmall,
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            user?.email ?? '',
            textAlign: TextAlign.center,
            style: tt.bodyMedium!.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: AppSpacing.md,
            children: [
              SettingsMetaLabel(
                user?.isOwner == true
                    ? ProfileCopy.roleOwner
                    : ProfileCopy.roleMember,
                accent: user?.isOwner == true,
              ),
              // The account id is a support/developer detail.
              if (shortId.isNotEmpty && user?.isOwner == true)
                SettingsMetaLabel(
                  '${ProfileCopy.idLabel} ${shortId.toUpperCase()}',
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton.tonalIcon(
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, SettingsSizes.touchTarget - 8),
            ),
            onPressed: _editName,
            icon: const AppIcon(AppIcons.edit, size: AppIconSize.md),
            label: const Text(ProfileCopy.editName),
          ),
        ],
      ),
    );
  }

  Future<void> _editName() async {
    Haptics.tap();
    final value = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _NameSheet(initial: _auth.user?.name ?? ''),
    );
    if (value != null) await _saveName(value);
  }

  Widget _methodGroup() {
    final m = _methods;
    if (m == null) {
      return SettingsGroup(
        entries: [
          GroupEntry(
            _methodsError != null
                ? _LoadError(message: _methodsError!, onRetry: _loadMethods)
                : const _Skeleton(),
          ),
        ],
      );
    }
    return SignInMethodsList(
      email: _auth.user?.email ?? '',
      methods: m,
      providers: _providers,
      busy: _methodBusy,
      onSetPassword: _openPasswordSheet,
      onLinkGithub: _linkGithub,
      onLinkGoogle: _linkGoogle,
      onUnlink: _unlink,
    );
  }

  Widget _deviceGroup() {
    final sessions = _sessions;
    if (sessions == null) {
      return const SettingsGroup(entries: [GroupEntry(_Skeleton())]);
    }
    final others = sessions.where((s) => !s.current).length;
    final scheme = Theme.of(context).colorScheme;
    return SettingsGroup(
      entries: [
        for (final s in sessions)
          GroupEntry(
            SettingsTile(
              icon: AuthIcons.device,
              title: s.device ?? ProfileStrings.unknownDevice,
              summary: s.lastUsedAt == null
                  ? null
                  : '${ProfileStrings.lastActive} ${agoLabel(s.lastUsedAt!)}',
              trailing: s.current
                  ? const SettingsMetaLabel(
                      ProfileStrings.thisDevice,
                      accent: true,
                    )
                  : TextButton(
                      onPressed: () => _revoke(s),
                      style: TextButton.styleFrom(
                        foregroundColor: scheme.error,
                      ),
                      child: Text(ProfileCopy.signOutDevice),
                    ),
            ),
          ),
        if (others > 0)
          GroupEntry(
            SettingsTile(
              icon: AuthIcons.logOut,
              title: ProfileCopy.signOutOthers,
              summary: ProfileCopy.signOutOthersHelp,
              onTap: _signOutOthers,
            ),
          ),
      ],
    );
  }

  Future<void> _signOutOthers() async {
    final others = [...?_sessions?.where((s) => !s.current)];
    try {
      for (final s in others) {
        await _api.revokeSession(s.id);
      }
      if (!mounted) return;
      setState(() => _sessions = [...?_sessions?.where((s) => s.current)]);
      _snack(ProfileCopy.othersSignedOut);
    } on ApiException catch (e) {
      Haptics.error();
      if (mounted) _snack(friendlyException(e));
    }
  }
}

/// The small round "change photo" button on the avatar's edge, with a border
/// in the page colour so it reads as a separate badge.
class _EditBadge extends StatelessWidget {
  const _EditBadge({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: context.palette.background,
          width: SettingsSizes.heroBadgeBorder,
        ),
      ),
      child: IconButton.filled(
        tooltip: ProfileCopy.changePhoto,
        style: IconButton.styleFrom(
          backgroundColor: context.palette.textPrimary,
          foregroundColor: context.palette.background,
        ),
        constraints: const BoxConstraints.tightFor(
          width: SettingsSizes.heroBadge,
          height: SettingsSizes.heroBadge,
        ),
        padding: EdgeInsets.zero,
        icon: const AppIcon(AppIcons.edit, size: AppIconSize.sm),
        onPressed: onPressed,
      ),
    );
  }
}

/// Photo, or a dot-matrix monogram of the initials when there is none.
class _HeroAvatar extends StatelessWidget {
  const _HeroAvatar({required this.user});

  final AuthUser? user;

  @override
  Widget build(BuildContext context) {
    final u = user;
    if (u == null || u.avatarBytes != null || u.avatarUrl != null) {
      return UserAvatar(
        user: u,
        size: SettingsSizes.heroAvatar,
        bordered: false,
      );
    }
    return DotMonogram(
      text: u.initials,
      size: SettingsSizes.heroAvatar,
      bordered: false,
    );
  }
}

/// Bottom sheet that edits the display name; pops with the new value.
class _NameSheet extends StatefulWidget {
  const _NameSheet({required this.initial});

  final String initial;

  @override
  State<_NameSheet> createState() => _NameSheetState();
}

class _NameSheetState extends State<_NameSheet> {
  late final _name = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final v = _name.text.trim();
    if (v.isEmpty) return;
    Haptics.tap();
    Navigator.pop(context, v);
  }

  @override
  Widget build(BuildContext context) {
    return _SheetBody(
      title: ProfileCopy.editName,
      children: [
        AuthField(
          label: ProfileStrings.name,
          controller: _name,
          icon: AuthIcons.name,
          maxLength: AuthSizes.nameMax,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
        ),
        PillButton(label: ProfileStrings.save, onPressed: _submit),
      ],
    );
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
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
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

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) =>
      const SizedBox(height: SettingsSizes.touchTarget);
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: AppSpacing.lg),
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
  const _PasswordSheet({
    required this.api,
    required this.hasPassword,
    required this.onDone,
  });

  final AccountApi api;

  /// False: SET PASSWORD for a GitHub/Google account (no current password).
  final bool hasPassword;
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
      await widget.api.changePassword(
        widget.hasPassword ? _current.text : null,
        _next.text,
      );
      Haptics.received();
      if (!mounted) return;
      Navigator.pop(context);
      widget.onDone(
        widget.hasPassword
            ? ProfileStrings.passwordChanged
            : SsoStrings.passwordSet,
      );
    } on ApiException catch (e) {
      Haptics.error();
      if (mounted) setState(() => _error = friendlyException(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final set = !widget.hasPassword;
    final title = set ? SsoStrings.setPassword : ProfileStrings.changePassword;
    return _SheetBody(
      title: title,
      children: [
        if (set) ...[
          Text(SsoStrings.setPasswordHint, style: context.text.bodySmall),
          const SizedBox(height: AppSpacing.xl),
        ] else
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
        PillButton(label: title, loading: _loading, onPressed: _submit),
      ],
    );
  }
}

// ---- delete account -----------------------------------------------------

class _DeleteSheet extends StatefulWidget {
  const _DeleteSheet({required this.api, required this.hasPassword});

  final AccountApi api;

  /// False for GitHub/Google accounts: the signed-in session is the proof.
  final bool hasPassword;

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
      (!widget.hasPassword || _password.text.isNotEmpty);

  Future<void> _submit() async {
    if (!_ready) return;
    Haptics.tap();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.api.deleteAccount(
        widget.hasPassword ? _password.text : null,
      );
      Haptics.received();
      if (mounted) Navigator.pop(context);
      await AuthController.instance.signOut(callServer: false);
    } on ApiException catch (e) {
      Haptics.error();
      if (mounted) setState(() => _error = friendlyException(e));
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
        if (widget.hasPassword)
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
