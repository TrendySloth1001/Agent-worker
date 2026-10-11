import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_scope.dart';
import '../../core/constants/app_sizes.dart';
import '../../core/constants/app_strings.dart';
import '../../core/haptics.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/system_chrome.dart';
import '../../data/knowledge_api.dart';
import 'knowledge_controller.dart';
import 'widgets/add_source_sheet.dart';
import 'widgets/source_tile.dart';
import '../../core/constants/app_icons.dart';
import '../../core/widgets/app_icon.dart';

class KnowledgeScreen extends StatefulWidget {
  const KnowledgeScreen({super.key});

  @override
  State<KnowledgeScreen> createState() => _KnowledgeScreenState();
}

class _KnowledgeScreenState extends State<KnowledgeScreen> {
  KnowledgeController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    _controller = KnowledgeController(
      KnowledgeApi(AppScope.of(context).baseUrl),
    )..load();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<bool> _confirmDelete() async {
    final p = context.palette;
    Haptics.tap();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: p.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: BorderSide(color: p.border),
        ),
        title: Text(AppStrings.deleteSourceTitle, style: context.text.label),
        content: Text(
          AppStrings.deleteSourceBody,
          style: context.text.bodySmall,
        ),
        actions: [
          TextButton(
            onPressed: () {
              Haptics.tap();
              Navigator.pop(context, false);
            },
            child: Text(AppStrings.cancel, style: context.text.caption),
          ),
          TextButton(
            onPressed: () {
              Haptics.tap();
              Navigator.pop(context, true);
            },
            child: Text(
              AppStrings.deleteSource,
              style: context.text.caption.copyWith(color: p.accent),
            ),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller!;
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
          title: const Text(AppStrings.knowledge),
          actions: [
            IconButton(
              icon: const AppIcon(AppIcons.add, size: AppIconSize.md),
              tooltip: AppStrings.addSource,
              onPressed: () {
                Haptics.tap();
                showAddSourceSheet(context, controller);
              },
            ),
            const SizedBox(width: AppSpacing.xs),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(AppBorder.thin),
            child: Divider(color: p.border),
          ),
        ),
        body: ListenableBuilder(
          listenable: controller,
          builder: (context, _) => RefreshIndicator(
            color: p.accent,
            backgroundColor: p.surface,
            onRefresh: controller.load,
            child: _body(context, controller),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, KnowledgeController controller) {
    final padding = EdgeInsets.fromLTRB(
      AppSpacing.screenPadding,
      AppSpacing.sm,
      AppSpacing.screenPadding,
      MediaQuery.paddingOf(context).bottom + AppSpacing.xl,
    );
    if (controller.loading) {
      return ListView(padding: padding);
    }
    if (controller.sources.isEmpty) {
      final failed = controller.loadError != null;
      return ListView(
        padding: padding,
        children: [
          const SizedBox(height: AppSpacing.xxl),
          AppIcon(
            failed ? AppIcons.alert : AppIcons.knowledge,
            size: AppIconSize.empty,
            color: failed
                ? context.palette.accent
                : context.palette.textTertiary,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            failed ? controller.loadError! : AppStrings.knowledgeEmpty,
            style: context.text.bodySmall.copyWith(
              color: failed ? context.palette.accent : null,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Align(
            alignment: Alignment.centerLeft,
            child: failed
                ? _textButton(context, AppStrings.retry, controller.load)
                : _textButton(
                    context,
                    AppStrings.addSource,
                    () => showAddSourceSheet(context, controller),
                  ),
          ),
        ],
      );
    }
    return ListView.builder(
      padding: padding,
      itemCount: controller.sources.length,
      itemBuilder: (context, index) {
        final source = controller.sources[index];
        return Dismissible(
          key: ValueKey(source.id),
          direction: DismissDirection.endToStart,
          confirmDismiss: (_) => _confirmDelete(),
          onDismissed: (_) => controller.delete(source.id),
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: AppSpacing.lg),
            color: context.palette.surfaceHigh,
            child: Text(
              AppStrings.deleteSource,
              style: context.text.caption.copyWith(
                color: context.palette.accent,
              ),
            ),
          ),
          child: SourceTile(
            source: source,
            onRefresh: () {
              Haptics.tap();
              controller.refresh(source.id);
            },
            onLongPress: () async {
              if (await _confirmDelete()) controller.delete(source.id);
            },
          ),
        );
      },
    );
  }

  Widget _textButton(BuildContext context, String label, VoidCallback onTap) {
    final p = context.palette;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        Haptics.tap();
        onTap();
      },
      child: Container(
        height: AppSizes.chipHeight + AppSpacing.sm,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: p.borderStrong, width: AppBorder.thin),
        ),
        child: Text(
          label,
          style: context.text.caption.copyWith(color: p.textPrimary),
        ),
      ),
    );
  }
}
