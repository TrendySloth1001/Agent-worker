/// Constants for the ```html artifact widget.
abstract final class HtmlSizes {
  static const minHeight = 160.0;
  static const maxHeight = 480.0;
  static const expandedMaxHeight = 3000.0;
  static const maxSourceChars = 200000;

  /// Larger documents cannot be handed to the browser in an intent.
  static const maxBrowserChars = 120000;
  static const sourceMaxHeight = 420.0;
  static const titleMaxChars = 36;
  static const progressHeight = 2.0;
  static const heightEpsilon = 1.0;
}

abstract final class HtmlStrings {
  static const fullscreen = 'FULLSCREEN';
  static const source = 'SOURCE';
  static const preview = 'PREVIEW';
  static const copyHtml = 'COPY HTML';
  static const browser = 'BROWSER';
  static const expand = 'EXPAND';
  static const collapse = 'COLLAPSE';
  static const tooLarge = 'TOO LARGE TO RENDER - SOURCE ONLY';
  static const failed = 'COULD NOT RENDER - SOURCE SHOWN';
  static const browserFailed = 'Could not open the browser.';
  static const browserTooLarge = 'Page is too large to open in the browser.';
  static const screenTitle = 'HTML PAGE';
  static const sourceLanguage = 'html';
  static const separator = ' · ';
}

abstract final class HtmlWeb {
  /// Fake origin so in-page `#anchor` links resolve and stay in the document.
  static const baseUrl = 'https://html.widget.local/';
  static const channel = 'FlutterHtml';
  static const fenceMark = '```';
  static const fallbackTitle = 'HTML';

  /// Origins scripts, styles and fonts may load from.
  static const cdnScript =
      'https://cdnjs.cloudflare.com https://cdn.jsdelivr.net https://unpkg.com';
  static const cdnStyle =
      'https://cdnjs.cloudflare.com https://cdn.jsdelivr.net https://fonts.googleapis.com';
  static const cdnFont =
      'https://cdnjs.cloudflare.com https://cdn.jsdelivr.net https://fonts.gstatic.com';

  /// Icon API the iconify-icon web component fetches from.
  static const iconifyApi =
      'https://api.iconify.design https://api.simplesvg.com https://api.unisvg.com';

  static const csp =
      "default-src 'none'; img-src data: blob: https:; media-src data: blob: https:; "
      "style-src 'unsafe-inline' $cdnStyle; "
      "script-src 'unsafe-inline' $cdnScript; "
      "font-src data: $cdnFont; connect-src $iconifyApi; "
      "form-action 'none'; base-uri 'none'";

  static const charset = '<meta charset="utf-8">';

  static const viewport =
      '<meta name="viewport" content="width=device-width, initial-scale=1">';

  /// Reports the content height to the app.
  static const script =
      '''
(function(){
var ch=window.$channel;
var last=-1;
function post(){try{var d=document,h=Math.max(
 d.documentElement.getBoundingClientRect().height,
 d.body?d.body.scrollHeight:0);
 h=Math.ceil(h);if(h!==last){last=h;ch.postMessage(String(h));}}catch(e){}}
function start(){post();
 try{new ResizeObserver(post).observe(document.documentElement);}catch(e){}
 try{new MutationObserver(post).observe(document.documentElement,{childList:true,subtree:true,attributes:true});}catch(e){}
 [150,500,1200,2500].forEach(function(t){setTimeout(post,t);});}
if(document.readyState==='complete')start();else window.addEventListener('load',start);
window.addEventListener('resize',post);
})();
''';

  // Design kit (assets/html/kit.css): themed defaults, components and
  // enforcement rules, split at [kitEnforceMark]; the font block between
  // [kitFontsStart] and [kitFontsEnd] points at ../fonts/*.ttf.
  static const kitAsset = 'assets/html/kit.css';
  static const kitFontDir = 'assets/fonts/';
  static const kitEnforceMark = '/*ENFORCE*/';
  static const kitFontsStart = '/*FONTS*/';
  static const kitFontsEnd = '/*END*/';
  static const kitFontUrl = r'url\(\.\./fonts/([^)]+)\)';
  static const themeDark = 'theme-dark';
  static const themeLight = 'theme-light';

  /// Pinned so the page never changes under us; loaded only when used.
  static const iconifyTag = 'iconify-icon';
  static const iconifyScript =
      '<script src="https://cdn.jsdelivr.net/npm/iconify-icon@2.3.0/dist/iconify-icon.min.js"></script>';

  /// Web fonts for the copy opened in another app (bundled fonts are not
  /// reachable from there).
  static const exportFonts =
      '<link rel="preconnect" href="https://fonts.googleapis.com">'
      '<link rel="stylesheet" href="https://fonts.googleapis.com/css2?'
      'family=Space+Grotesk:wght@400;500;700&family=Space+Mono:wght@400;700'
      '&display=swap">';

  /// Strips emoji from text, flattens gradients the author painted.
  static const cleanScript = r'''
(function(){
var R=/(?:[\u{1F000}-\u{1FAFF}\u{2B50}\u{2B55}\u{2705}\u{274C}\u{274E}\u{2753}-\u{2755}\u{2757}\u{2795}-\u{2797}\u{27B0}\u{27BF}\u{26A0}\u{26A1}\u{2728}\u{2764}\u{231A}\u{231B}\u{23E9}-\u{23F3}\u{2614}\u{2615}\u{26BD}\u{26BE}\u{26C4}\u{26C5}\u{26D4}\u{26EA}\u{26F2}-\u{26FA}\u{26FD}]|[^\s]\uFE0F|\u200D)/gu;
var SKIP={SCRIPT:1,STYLE:1,TEXTAREA:1,NOSCRIPT:1};
function run(){try{
 var w=document.createTreeWalker(document.body,NodeFilter.SHOW_TEXT),n;
 while((n=w.nextNode())){if(SKIP[n.parentNode.nodeName])continue;
  var v=n.nodeValue,c=v.replace(R,'');if(c!==v)n.nodeValue=c.replace(/^\s{2,}/,' ');}
 var t=document.title.replace(R,'').trim();if(t!==document.title)document.title=t;
 var all=document.body.getElementsByTagName('*');
 for(var i=0;i<all.length;i++){var e=all[i];
  if(getComputedStyle(e).backgroundImage.indexOf('gradient')>-1)e.style.setProperty('background-image','none','important');}
}catch(e){}}
var timer;function soon(){clearTimeout(timer);timer=setTimeout(run,60);}
run();
try{new MutationObserver(soon).observe(document.body,{childList:true,subtree:true,characterData:true});}catch(e){}
window.addEventListener('load',soon);
})();
''';

  static String themeScript(bool dark) =>
      "document.documentElement.classList.add('${dark ? themeDark : themeLight}');";
}
