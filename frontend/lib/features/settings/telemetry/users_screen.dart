import 'package:flutter/material.dart';

import '../../../core/constants/app_config.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/m3_copy.dart';
import '../../../core/constants/settings_copy.dart';
import '../../../core/constants/telemetry.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/m3_kit_extras.dart';
import '../../../data/telemetry_api.dart';
import '../widgets/usage_states.dart';
import 'telemetry_controller.dart';
import 'telemetry_widgets.dart';

/// Owner only: everyone using sparky in the telemetry window, most active
/// first. Moved out of Telemetry so model health and people stay apart.
class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key, this.api});

  final TelemetryApi? api;

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  late final TelemetryController _c;

  @override
  void initState() {
    super.initState();
    _c = TelemetryController(widget.api ?? TelemetryApi(AppConfig.apiBaseUrl))
      ..start();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) => M3Page(
        title: SettingsStrings.catUsers,
        onRefresh: _c.reload,
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenPadding,
            ),
            sliver: SliverToBoxAdapter(child: _body(context)),
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    final o = _c.overview;
    if (o == null) {
      if (_c.error != null && !_c.loading) {
        return Padding(
          padding: const EdgeInsets.only(top: AppSpacing.lg),
          child: UsageError(onRetry: _c.reload, loading: _c.loading),
        );
      }
      return Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xl),
        child: LinearProgressIndicator(
          minHeight: AppBorder.thin,
          color: context.palette.accent,
          backgroundColor: context.palette.border,
        ),
      );
    }
    if (o.users.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xl),
        child: Text(SettingsStrings.usersEmpty, style: context.text.bodySmall),
      );
    }
    return TSection(
      title: TelemetryCopy.users,
      icon: TelemetryIcons.users,
      child: PlainList(children: [for (final u in o.users) UserRow(user: u)]),
    );
  }
}
