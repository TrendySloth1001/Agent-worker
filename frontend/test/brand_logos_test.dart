import 'dart:io';

import 'package:app/core/constants/app_icons.dart';
import 'package:app/core/constants/brand_logos.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/core/widgets/app_icon.dart';
import 'package:app/core/widgets/icon_label.dart';
import 'package:app/data/chat_event.dart';
import 'package:app/data/kb_source.dart';
import 'package:app/features/chat/widgets/markdown/citation_chip.dart';
import 'package:app/features/knowledge/widgets/source_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hugeicons/hugeicons.dart';

import 'support/shot.dart';

/// Every logo on a tonal tile, as the app shows them.
Widget _gallery(ThemeData theme) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: theme,
  home: Builder(
    builder: (context) {
      final scheme = Theme.of(context).colorScheme;
      return Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final logo in BrandLogos.all)
                SizedBox(
                  width: 82,
                  child: Column(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Center(
                          child: AppIcon(
                            logo,
                            size: 32,
                            color: scheme.onSurface,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        BrandLogos.assetOf(logo)!
                            .split('/')
                            .last
                            .replaceAll('.svg', ''),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 9, color: scheme.onSurface),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
    },
  ),
);

KbSource _src(String type, String uri, String title) => KbSource(
  id: title,
  type: type,
  uri: uri,
  title: title,
  status: 'done',
  progressDone: null,
  progressTotal: null,
  docCount: 1,
  chunkCount: 1,
  error: null,
  lastIngestedAt: null,
);

/// Logos where the app shows them: knowledge sources (no favicon stored),
/// citation favicons that failed to load, model providers.
Widget _inContext(ThemeData theme) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: theme,
  home: Scaffold(
    body: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final s in [
                _src('reddit', 'https://www.reddit.com/r/flutter', 'r/flutter'),
                _src('hackernews', 'https://news.ycombinator.com/', 'HN'),
                _src('stackoverflow', 'https://stackoverflow.com/q/1', 'SO'),
                _src('github', 'https://github.com/flutter/flutter', 'flutter'),
                _src('web', 'https://example.com', 'Example'),
                _src('file', '', 'report.pdf'),
                _src('file', '', 'brief.docx'),
                _src('file', '', 'notes.md'),
                _src('file', '', 'log.txt'),
                _src('google_drive', '', 'Q4 roadmap'),
                _src('notion', '', 'Wiki'),
              ])
                SourceIcon(source: s),
            ],
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 16,
            runSpacing: 12,
            children: [
              for (final site in [
                'stackoverflow.com',
                'github.com',
                'reddit.com',
                'news.ycombinator.com',
                'example.org',
              ])
                SiteFavicon(
                  citation: Citation(
                    id: site,
                    title: site,
                    url: 'https://$site/x',
                    site: site,
                  ),
                  size: 20,
                ),
            ],
          ),
          const SizedBox(height: 24),
          for (final id in ['groq', 'nvidia', 'ollama', 'openrouter'])
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: IconLabel(
                icon: AppIcons.provider(id),
                text: id.toUpperCase(),
                style: const TextStyle(fontFamily: 'SpaceMono', fontSize: 12),
                iconSize: 16,
              ),
            ),
        ],
      ),
    ),
  ),
);

void main() {
  setUpAll(loadAppFonts);

  test('every logo file exists, is bundled and has a credit', () {
    final credits = File('assets/brand/CREDITS.md').readAsStringSync();
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('assets/brand/logos/'));
    for (final logo in BrandLogos.all) {
      final asset = BrandLogos.assetOf(logo)!;
      expect(File(asset).existsSync(), isTrue, reason: asset);
      final svg = File(asset).readAsStringSync();
      // flutter_svg cannot size an `em` root and would draw nothing.
      expect(svg.substring(0, svg.indexOf('>')), isNot(contains('em"')));
      expect(credits, contains('| ${asset.split('/').last} |'), reason: asset);
    }
  });

  test('plain glyphs are not logos', () {
    expect(BrandLogos.assetOf(HugeIcons.strokeRoundedSearch01), isNull);
    expect(BrandLogos.assetOf(AppIcons.github), isNotNull);
  });

  test('brands and file types map to their real logos', () {
    expect(AppIcons.provider('groq'), BrandLogos.groq);
    expect(AppIcons.provider('nvidia'), BrandLogos.nvidia);
    expect(AppIcons.provider('ollama'), BrandLogos.ollama);
    expect(AppIcons.provider('openrouter'), BrandLogos.openrouter);
    expect(AppIcons.sourceKind('github'), BrandLogos.github);
    expect(AppIcons.sourceKind('reddit'), BrandLogos.reddit);
    expect(AppIcons.sourceKind('stackoverflow'), BrandLogos.stackoverflow);
    expect(AppIcons.sourceKind('hackernews'), BrandLogos.hackernews);
    expect(AppIcons.fileKind('a.PDF'), BrandLogos.pdf);
    expect(AppIcons.fileKind('a.docx'), BrandLogos.word);
    expect(AppIcons.fileKind('a.xlsx'), BrandLogos.excel);
    expect(AppIcons.fileKind('a.md'), BrandLogos.markdown);
    expect(AppIcons.fileKind('a.txt'), BrandLogos.text);
    // An unknown type stays a generic file, never a made-up logo.
    expect(AppIcons.fileKind('a.odt'), AppIcons.file);
    expect(BrandLogos.forDomain('www.reddit.com'), BrandLogos.reddit);
    expect(BrandLogos.forDomain('old.reddit.com'), BrandLogos.reddit);
    expect(BrandLogos.forDomain('news.ycombinator.com'), BrandLogos.hackernews);
    expect(BrandLogos.forDomain('stackoverflow.com'), BrandLogos.stackoverflow);
    expect(BrandLogos.forDomain('notgithub.com'), isNull);
    expect(BrandLogos.mono(BrandLogos.notion), BrandLogos.notionMono);
    expect(BrandLogos.mono(BrandLogos.slack), BrandLogos.slack);
  });

  testWidgets('AppIcon draws a logo as its SVG asset', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: AppIcon(BrandLogos.googleDrive, size: 24),
      ),
    );
    expect(find.byType(SvgPicture), findsOneWidget);
  });

  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';
    testWidgets('logo gallery ($mode)', (tester) async {
      tester.view.physicalSize = const Size(1072, 2379);
      tester.view.devicePixelRatio = 2.6;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_gallery(dark ? AppTheme.dark : AppTheme.light));
      // SVG assets decode off the test clock.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/brand_logos_$mode.png'),
      );
    });
  }

  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';
    testWidgets('logos in context ($mode)', (tester) async {
      tester.view.physicalSize = const Size(1072, 1400);
      tester.view.devicePixelRatio = 2.6;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _inContext(dark ? AppTheme.dark : AppTheme.light),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/brand_logos_context_$mode.png'),
      );
    });
  }
}
