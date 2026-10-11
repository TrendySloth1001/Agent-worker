import 'dart:io';

import 'package:app/features/chat/widgets/rich/html_doc.dart';
import 'package:app/features/chat/widgets/rich/html_kit.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('kit wraps pages for the app and the browser', () async {
    final kit = await HtmlKit.load();
    expect(kit.web, contains('data:font/ttf;base64,'));
    expect(kit.export, isNot(contains('data:font/ttf')));
    expect(kit.enforce, contains('!important'));

    const page =
        '<!doctype html><html><head><title>T</title><style>body{background:red}'
        '</style></head><body><h1>Hi</h1></body></html>';
    final app = HtmlDoc.prepare(
      page,
      const HtmlTheme(bg: Color(0xFF000000), dark: true),
      kit,
    );
    expect(app, contains('Content-Security-Policy'));
    expect(app, contains("classList.add('theme-dark')"));
    expect(
      app.indexOf('background:red'),
      lessThan(app.lastIndexOf('!important')),
    );

    final out = HtmlDoc.forBrowser('<h1>x</h1>', kit, dark: false);
    expect(out, contains('theme-light'));
    expect(out, contains('fonts.googleapis.com'));
    expect(out, isNot(contains('Content-Security-Policy')));
    expect(out, isNot(contains('FlutterHtml')));

    final dir = Platform.environment['KIT_DUMP_DIR'];
    final src = Platform.environment['KIT_DUMP_SRC'];
    if (dir != null && src != null) {
      for (final f in Directory(src).listSync().whereType<File>()) {
        if (!f.path.endsWith('.html')) continue;
        final name = f.uri.pathSegments.last.replaceAll('.html', '');
        final html = f.readAsStringSync();
        for (final dark in [true, false]) {
          final tag = dark ? 'dark' : 'light';
          final web =
              HtmlDoc.prepare(
                    html,
                    HtmlTheme(bg: const Color(0xFF000000), dark: dark),
                    kit,
                  )
                  .replaceAll(
                    RegExp(r'<meta http-equiv="Content-Security[^>]*>'),
                    '',
                  )
                  .replaceFirst(
                    'window.FlutterHtml',
                    '({postMessage:function(){}})',
                  );
          File('$dir/$name-$tag.html').writeAsStringSync(web);
          File(
            '$dir/$name-$tag-export.html',
          ).writeAsStringSync(HtmlDoc.forBrowser(html, kit, dark: dark));
        }
      }
    }
  });
}
