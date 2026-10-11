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

  /// Fade over the bottom of a collapsed page that continues below.
  static const fadeHeight = 48.0;

  /// Pixels per `vh` unit in the in-app page: the WebView is as tall as its
  /// content, so viewport units would feed the auto-height loop.
  static const vhPx = 5;
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
  static const truncated = 'RESPONSE WAS CUT OFF - ASK AGAIN FOR THE FULL PAGE';

  /// Shown inside the page (kit `.kit-notice`).
  static const scriptError = 'Part of this page did not run: ';
  static const emptyPage =
      'This page came out empty. Ask again to regenerate it.';
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

  /// Hosts a page may load scripts and stylesheets from; anything else is
  /// removed before rendering (the CSP would block it anyway).
  static const allowedHosts = {
    'cdnjs.cloudflare.com',
    'cdn.jsdelivr.net',
    'unpkg.com',
  };

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

  /// In-app only: no scrollbars (the card sizes itself to the content).
  static const webStyle =
      'html{scrollbar-width:none}::-webkit-scrollbar{display:none}';

  /// Runs first: collects script errors, hides broken images, themes
  /// Chart.js if the page loads it, and after load shows a notice instead of
  /// a blank or half-working page.
  static String guardScript() =>
      '''
(function(){
var errs=[];
addEventListener('error',function(e){var t=e.target;
 if(t&&t!==window){if(t.tagName==='IMG')t.style.display='none';return;}
 errs.push(String(e.message||'error'));},true);
addEventListener('unhandledrejection',function(e){errs.push(String(e.reason&&e.reason.message||e.reason||'error'));});
function tok(n){return getComputedStyle(document.documentElement).getPropertyValue(n).trim();}
function kitChart(C){try{var d=C.defaults;d.color=tok('--text-2');d.borderColor=tok('--border');
 if(d.font)d.font.family='Space Mono, monospace';
 var pal=[tok('--accent'),tok('--text'),tok('--text-2'),tok('--text-3'),tok('--border-strong')];
 C.register({id:'kit',beforeUpdate:function(c){var round=/pie|doughnut|polar/.test(c.config.type);
  (c.data.datasets||[]).forEach(function(ds,i){if(round){ds.backgroundColor=(c.data.labels||[]).map(function(_,j){return pal[j%pal.length];});ds.borderColor=tok('--bg');}
   else{ds.backgroundColor=pal[i%pal.length];ds.borderColor=pal[i%pal.length];}});}});}catch(e){}}
var C;try{Object.defineProperty(window,'Chart',{configurable:true,get:function(){return C;},set:function(v){C=v;kitChart(v);}});}catch(e){}
function notice(text){var b=document.body;if(!b||document.querySelector('[data-kit-notice]'))return;
 var n=document.createElement('div');n.className='kit-notice';n.setAttribute('data-kit-notice','');n.setAttribute('role','status');
 n.textContent=text;b.insertBefore(n,b.firstChild);}
function check(){var b=document.body;if(!b)return;
 if(errs.length){notice('${HtmlStrings.scriptError}'+errs[0].slice(0,120));return;}
 var text=(b.innerText||'').trim().length,media=b.querySelector('img,svg,canvas,video,iframe,iconify-icon');
 if(!text&&!media)notice('${HtmlStrings.emptyPage}');}
addEventListener('load',function(){setTimeout(check,400);});
})();
''';

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

  /// Repairs what the author got wrong after the page is built: strips
  /// emoji, flattens gradients, maps off-theme colours to kit tokens (light
  /// boxes in dark mode, unreadable text, stray brand colours), wraps tables
  /// in a scroller and unfolds layouts wider than the screen. Re-runs when the
  /// page's scripts change the DOM.
  static const cleanScript = r'''
(function(){
var R=/(?:[\u{1F000}-\u{1FAFF}\u{2B50}\u{2B55}\u{2705}\u{274C}\u{274E}\u{2753}-\u{2755}\u{2757}\u{2795}-\u{2797}\u{27B0}\u{27BF}\u{26A0}\u{26A1}\u{2728}\u{2764}\u{231A}\u{231B}\u{23E9}-\u{23F3}\u{2614}\u{2615}\u{26BD}\u{26BE}\u{26C4}\u{26C5}\u{26D4}\u{26EA}\u{26F2}-\u{26FA}\u{26FD}]|[^\s]️|‍)/gu;
var SKIP={SCRIPT:1,STYLE:1,TEXTAREA:1,NOSCRIPT:1};
var D=document.documentElement;
function rgb(s){var m=/rgba?\(([^)]+)\)/.exec(s||'');if(!m)return null;
 var p=m[1].split(/[\s,\/]+/).filter(Boolean).map(parseFloat);
 return {r:p[0],g:p[1],b:p[2],a:p.length>3?p[3]:1};}
function lum(c){function f(v){v/=255;return v<=.03928?v/12.92:Math.pow((v+.055)/1.055,2.4);}
 return .2126*f(c.r)+.7152*f(c.g)+.0722*f(c.b);}
function con(a,b){var x=lum(a),y=lum(b);return (Math.max(x,y)+.05)/(Math.min(x,y)+.05);}
function chroma(c){return Math.max(c.r,c.g,c.b)-Math.min(c.r,c.g,c.b);}
function near(a,b){return a&&b&&Math.abs(a.r-b.r)+Math.abs(a.g-b.g)+Math.abs(a.b-b.b)<60;}
function set(e,k,v){e.style.setProperty(k,v,'important');}
function bgOf(e){for(;e&&e.nodeType===1;e=e.parentElement){var c=rgb(getComputedStyle(e).backgroundColor);if(c&&c.a>.5)return c;}
 return rgb(getComputedStyle(document.body).backgroundColor)||{r:0,g:0,b:0,a:1};}
function ownText(e){for(var n=e.firstChild;n;n=n.nextSibling)if(n.nodeType===3&&n.nodeValue.trim())return true;return false;}
function colours(){
 var page=bgOf(document.body),dark=lum(page)<.4;
 var probe=document.createElement('i');probe.style.color='var(--accent)';document.body.appendChild(probe);
 var acc=rgb(getComputedStyle(probe).color);probe.remove();
 var all=document.body.getElementsByTagName('*');
 for(var i=0;i<all.length;i++){var e=all[i];
  if(SKIP[e.nodeName]||e.closest('svg,[data-kit-notice]'))continue;
  var cs=getComputedStyle(e);
  if(cs.backgroundImage.indexOf('gradient')>-1)set(e,'background-image','none');
  var bg=rgb(cs.backgroundColor);
  if(bg&&bg.a>.3&&!near(bg,acc)){
   if(chroma(bg)<40){var L=lum(bg);if(dark?L>.2:L<.25)set(e,'background-color','var(--surface-2)');}
   else{var r=e.getBoundingClientRect();set(e,'background-color',r.width*r.height<15000?'var(--accent)':'var(--surface-2)');}}
  if(parseFloat(cs.borderTopWidth)+parseFloat(cs.borderLeftWidth)+parseFloat(cs.borderBottomWidth)>0){
   var bc=rgb(cs.borderLeftColor)||rgb(cs.borderTopColor);
   if(bc&&bc.a>.3&&!near(bc,acc)&&(chroma(bc)>=40||(dark?lum(bc)>.35:lum(bc)<.08)))set(e,'border-color','var(--border)');}
  if(!ownText(e)&&!/^(INPUT|SELECT|TEXTAREA|BUTTON)$/.test(e.nodeName))continue;
  var fg=rgb(getComputedStyle(e).color),under=bgOf(e);if(!fg)continue;
  if(chroma(fg)>=60&&!near(fg,acc)){set(e,'color','var(--accent)');fg=rgb(getComputedStyle(e).color);}
  if(con(fg,under)<3)set(e,'color',near(under,acc)?'var(--accent-ink)':'var(--text)');}}
function tables(){var t=document.body.getElementsByTagName('table');
 for(var i=t.length-1;i>=0;i--){var x=t[i],p=x.parentElement;
  if(!p||p.classList.contains('table-wrap')||x.closest('td,th'))continue;
  var w=document.createElement('div');w.className='table-wrap';p.insertBefore(w,x);w.appendChild(x);}}
function fit(){var vw=D.clientWidth;
 var all=document.body.getElementsByTagName('*');
 for(var i=0;i<all.length;i++){var e=all[i];if(e.closest('.table-wrap,pre,svg'))continue;
  var r=e.getBoundingClientRect();if(r.right<=vw+1)continue;
  var cs=getComputedStyle(e);if(cs.position==='fixed'||cs.position==='absolute')continue;
  var up=e.parentElement;if(up&&up!==document.body&&getComputedStyle(up).display.indexOf('grid')>-1)set(up,'grid-template-columns','minmax(0,1fr)');
  if(cs.display.indexOf('grid')>-1)set(e,'grid-template-columns','minmax(0,1fr)');
  if(cs.display.indexOf('flex')>-1&&cs.flexDirection.indexOf('row')===0)set(e,'flex-wrap','wrap');
  if(parseFloat(cs.width)>vw)set(e,'width','auto');
  set(e,'min-width','0');}}
var busy=false;
function run(){if(busy)return;busy=true;try{
 var w=document.createTreeWalker(document.body,NodeFilter.SHOW_TEXT),n;
 while((n=w.nextNode())){if(SKIP[n.parentNode.nodeName])continue;
  var v=n.nodeValue,c=v.replace(R,'');if(c!==v)n.nodeValue=c.replace(/^\s{2,}/,' ');}
 var t=document.title.replace(R,'').trim();if(t!==document.title)document.title=t;
 tables();colours();fit();
}catch(e){}setTimeout(function(){busy=false;},0);}
var timer;function soon(){if(busy)return;clearTimeout(timer);timer=setTimeout(run,60);}
run();
try{new MutationObserver(soon).observe(document.body,{childList:true,subtree:true,characterData:true});}catch(e){}
window.addEventListener('load',soon);
})();
''';

  static String themeScript(bool dark) =>
      "document.documentElement.classList.add('${dark ? themeDark : themeLight}');";
}
