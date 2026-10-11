import 'dart:io';

import 'package:app/features/chat/widgets/rich/html_doc.dart';
import 'package:app/features/chat/widgets/rich/html_kit.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('clean repairs what models get wrong', () {
    const messy =
        'Here you go:\n```html\n<!doctype html><html><head>'
        '<script src="https://cdn.tailwindcss.com"></script>'
        '<script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0"></script>'
        '<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=X">'
        '</head><body><h1>{{icon:hugeicons:home-01}} Hi</h1>'
        '<p>**bold** text</p><script>const a=2**3;</script></body></html>\n```\nEnjoy!';
    final out = HtmlDoc.clean(messy);
    expect(out, startsWith('<!doctype html>'));
    expect(out, endsWith('</html>'));
    expect(out, isNot(contains('```')));
    expect(out, isNot(contains('tailwind')));
    expect(out, contains('chart.js'));
    expect(out, isNot(contains('fonts.googleapis')));
    expect(out, contains('<iconify-icon icon="hugeicons:home-01">'));
    expect(out, contains('<strong>bold</strong>'));
    expect(out, contains('a=2**3'));
    expect(HtmlDoc.isTruncated(messy), isFalse);

    const cut = '<!doctype html><html><body><h1>T</h1><script>const x=[1,2';
    expect(HtmlDoc.isTruncated(cut), isTrue);
    expect(HtmlDoc.clean(cut), isNot(contains('<script')));
    expect(HtmlDoc.isTruncated('<html><body><td class="x'), isTrue);
    expect(HtmlDoc.isTruncated('<h1>fragment</h1><p>ok</p>'), isFalse);
  });

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
          final web = HtmlDoc.prepare(
            html,
            HtmlTheme(bg: const Color(0xFF000000), dark: dark),
            kit,
          ).replaceFirst('window.FlutterHtml', '({postMessage:function(){}})');
          File('$dir/$name-$tag.html').writeAsStringSync(web);
          File(
            '$dir/$name-$tag-export.html',
          ).writeAsStringSync(HtmlDoc.forBrowser(html, kit, dark: dark));
        }
      }
    }
  });
}
