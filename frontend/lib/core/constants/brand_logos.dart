import 'app_icons.dart';

/// Official brand and file-type logos, bundled as SVG in
/// `assets/brand/logos/` (source and license of each file:
/// `assets/brand/CREDITS.md`). Never stand a generic glyph in for a brand.
///
/// Each logo is an [AppIconData], so anything that takes an icon (AppIcon,
/// SettingsTile, M3Empty…) draws the real logo. Full-color logos keep their
/// own colors; monochrome marks (`tint`) take the icon color like a glyph.
abstract final class BrandLogos {
  /// Marker of a logo inside [AppIconData] (Hugeicons data never uses it).
  static const tag = 'brand-logo';
  static const _asset = 'asset';
  static const _tint = 'tint';
  static const _dir = 'assets/brand/logos';
  static const _models = '$_dir/models';

  // Accounts and apps.
  static const AppIconData github = [
    [
      tag,
      {_asset: '$_dir/github.svg', _tint: true},
    ],
  ];
  static const AppIconData googleDrive = [
    [
      tag,
      {_asset: '$_dir/google_drive.svg'},
    ],
  ];
  static const AppIconData googleDriveMono = [
    [
      tag,
      {_asset: '$_dir/google_drive_mono.svg', _tint: true},
    ],
  ];
  static const AppIconData googlePhotos = [
    [
      tag,
      {_asset: '$_dir/google_photos.svg'},
    ],
  ];
  static const AppIconData gmail = [
    [
      tag,
      {_asset: '$_dir/gmail.svg'},
    ],
  ];
  static const AppIconData googleCalendar = [
    [
      tag,
      {_asset: '$_dir/google_calendar.svg'},
    ],
  ];
  static const AppIconData notion = [
    [
      tag,
      {_asset: '$_dir/notion.svg'},
    ],
  ];
  static const AppIconData notionMono = [
    [
      tag,
      {_asset: '$_dir/notion_mono.svg', _tint: true},
    ],
  ];
  static const AppIconData slack = [
    [
      tag,
      {_asset: '$_dir/slack.svg'},
    ],
  ];

  // Model providers.
  static const AppIconData groq = [
    [
      tag,
      {_asset: '$_dir/groq.svg'},
    ],
  ];
  static const AppIconData groqMono = [
    [
      tag,
      {_asset: '$_dir/groq_mono.svg', _tint: true},
    ],
  ];
  static const AppIconData groqWordmark = [
    [
      tag,
      {_asset: '$_dir/groq_wordmark.svg'},
    ],
  ];
  static const AppIconData nvidia = [
    [
      tag,
      {_asset: '$_dir/nvidia.svg'},
    ],
  ];
  static const AppIconData nvidiaWordmark = [
    [
      tag,
      {_asset: '$_dir/nvidia_wordmark.svg'},
    ],
  ];
  static const AppIconData ollama = [
    [
      tag,
      {_asset: '$_dir/ollama.svg', _tint: true},
    ],
  ];
  static const AppIconData openrouter = [
    [
      tag,
      {_asset: '$_dir/openrouter.svg', _tint: true},
    ],
  ];
  static const AppIconData openrouterColor = [
    [
      tag,
      {_asset: '$_dir/openrouter_color.svg'},
    ],
  ];

  // Model families (who made the model, whichever provider serves it).
  // NVIDIA Nemotron uses [nvidia]. Pick one with `ModelLogos.forModelId`.
  static const AppIconData openai = [
    [
      tag,
      {_asset: '$_models/openai.svg', _tint: true},
    ],
  ];
  static const AppIconData gemma = [
    [
      tag,
      {_asset: '$_models/gemma.svg', _tint: true},
    ],
  ];
  static const AppIconData meta = [
    [
      tag,
      {_asset: '$_models/meta.svg'},
    ],
  ];
  static const AppIconData qwen = [
    [
      tag,
      {_asset: '$_models/qwen.svg'},
    ],
  ];
  static const AppIconData glm = [
    [
      tag,
      {_asset: '$_models/glm.svg'},
    ],
  ];
  static const AppIconData deepseek = [
    [
      tag,
      {_asset: '$_models/deepseek.svg'},
    ],
  ];
  static const AppIconData kimi = [
    [
      tag,
      {_asset: '$_models/kimi.svg', _tint: true},
    ],
  ];
  static const AppIconData mistral = [
    [
      tag,
      {_asset: '$_models/mistral.svg'},
    ],
  ];
  static const AppIconData microsoft = [
    [
      tag,
      {_asset: '$_models/microsoft.svg'},
    ],
  ];

  // Knowledge and web sources.
  static const AppIconData reddit = [
    [
      tag,
      {_asset: '$_dir/reddit.svg'},
    ],
  ];
  static const AppIconData redditMono = [
    [
      tag,
      {_asset: '$_dir/reddit_mono.svg', _tint: true},
    ],
  ];
  static const AppIconData stackoverflow = [
    [
      tag,
      {_asset: '$_dir/stackoverflow.svg'},
    ],
  ];
  static const AppIconData hackernews = [
    [
      tag,
      {_asset: '$_dir/hackernews.svg'},
    ],
  ];

  // File types. Drive rows show the icon Google serves per file; these are
  // the bundled stand-ins. The 2026 Google icons rely on SVG masks and blur
  // filters flutter_svg cannot draw (Docs comes out washed out), so the
  // faithful file-shaped ones are used and the 2026 set is kept for later.
  static const AppIconData googleDocs = [
    [
      tag,
      {_asset: '$_dir/google_docs.svg'},
    ],
  ];
  static const AppIconData googleSheets = [
    [
      tag,
      {_asset: '$_dir/google_sheets.svg'},
    ],
  ];
  static const AppIconData googleSlides = [
    [
      tag,
      {_asset: '$_dir/google_slides.svg'},
    ],
  ];
  static const AppIconData googleDocs2026 = [
    [
      tag,
      {_asset: '$_dir/google_docs_2026.svg'},
    ],
  ];
  static const AppIconData googleSheets2026 = [
    [
      tag,
      {_asset: '$_dir/google_sheets_2026.svg'},
    ],
  ];
  static const AppIconData googleSlides2026 = [
    [
      tag,
      {_asset: '$_dir/google_slides_2026.svg'},
    ],
  ];
  static const AppIconData googleDocsFlat = [
    [
      tag,
      {_asset: '$_dir/google_docs_selfhst.svg'},
    ],
  ];
  static const AppIconData googleSheetsFlat = [
    [
      tag,
      {_asset: '$_dir/google_sheets_selfhst.svg'},
    ],
  ];
  static const AppIconData googleSlidesFlat = [
    [
      tag,
      {_asset: '$_dir/google_slides_selfhst.svg'},
    ],
  ];
  static const AppIconData pdf = [
    [
      tag,
      {_asset: '$_dir/pdf.svg'},
    ],
  ];
  static const AppIconData word = [
    [
      tag,
      {_asset: '$_dir/word.svg'},
    ],
  ];
  static const AppIconData excel = [
    [
      tag,
      {_asset: '$_dir/excel.svg'},
    ],
  ];
  static const AppIconData powerpoint = [
    [
      tag,
      {_asset: '$_dir/powerpoint.svg'},
    ],
  ];
  static const AppIconData text = [
    [
      tag,
      {_asset: '$_dir/text_file.svg'},
    ],
  ];
  static const AppIconData markdownFile = [
    [
      tag,
      {_asset: '$_dir/markdown_file.svg'},
    ],
  ];
  static const AppIconData markdown = [
    [
      tag,
      {_asset: '$_dir/markdown.svg', _tint: true},
    ],
  ];

  // Media, shopping and maps apps ("Open in YouTube Music" chips and cards).
  static const AppIconData youtube = [
    [
      tag,
      {_asset: '$_dir/youtube.svg'},
    ],
  ];
  static const AppIconData youtubeMusic = [
    [
      tag,
      {_asset: '$_dir/youtube_music.svg'},
    ],
  ];
  static const AppIconData spotify = [
    [
      tag,
      {_asset: '$_dir/spotify.svg'},
    ],
  ];
  static const AppIconData jiosaavn = [
    [
      tag,
      {_asset: '$_dir/jiosaavn.svg', _tint: true},
    ],
  ];
  static const AppIconData gaana = [
    [
      tag,
      {_asset: '$_dir/gaana.svg', _tint: true},
    ],
  ];
  static const AppIconData appleMusic = [
    [
      tag,
      {_asset: '$_dir/apple_music.svg'},
    ],
  ];
  static const AppIconData amazon = [
    [
      tag,
      {_asset: '$_dir/amazon.svg'},
    ],
  ];
  static const AppIconData flipkart = [
    [
      tag,
      {_asset: '$_dir/flipkart.svg'},
    ],
  ];
  static const AppIconData googleMaps = [
    [
      tag,
      {_asset: '$_dir/google_maps.svg'},
    ],
  ];

  // Credits.
  static const AppIconData flutter = [
    [
      tag,
      {_asset: '$_dir/flutter.svg'},
    ],
  ];

  /// Every bundled logo (the gallery test renders them all).
  static const all = <AppIconData>[
    github,
    googleDrive,
    googleDriveMono,
    googlePhotos,
    gmail,
    googleCalendar,
    notion,
    notionMono,
    slack,
    groq,
    groqMono,
    groqWordmark,
    nvidia,
    nvidiaWordmark,
    ollama,
    openrouter,
    openrouterColor,
    openai,
    gemma,
    meta,
    qwen,
    glm,
    deepseek,
    kimi,
    mistral,
    microsoft,
    reddit,
    redditMono,
    stackoverflow,
    hackernews,
    googleDocs,
    googleSheets,
    googleSlides,
    googleDocs2026,
    googleSheets2026,
    googleSlides2026,
    googleDocsFlat,
    googleSheetsFlat,
    googleSlidesFlat,
    pdf,
    word,
    excel,
    powerpoint,
    text,
    markdownFile,
    markdown,
    youtube,
    youtubeMusic,
    spotify,
    jiosaavn,
    gaana,
    appleMusic,
    amazon,
    flipkart,
    googleMaps,
    flutter,
  ];

  static Map<dynamic, dynamic>? _spec(AppIconData icon) =>
      icon.length == 1 && icon.first.length == 2 && icon.first.first == tag
      ? icon.first.last as Map<dynamic, dynamic>
      : null;

  /// The logo's asset path, or null for a plain glyph.
  static String? assetOf(AppIconData icon) => _spec(icon)?[_asset] as String?;

  /// A monochrome mark drawn in the icon color.
  static bool tinted(AppIconData icon) => _spec(icon)?[_tint] == true;

  /// The single-color version of a logo, for spots that force one color
  /// (a filled button); a logo without one is returned as is.
  static AppIconData mono(AppIconData logo) => switch (logo) {
    _ when identical(logo, googleDrive) => googleDriveMono,
    _ when identical(logo, notion) => notionMono,
    _ when identical(logo, groq) => groqMono,
    _ when identical(logo, reddit) => redditMono,
    _ => logo,
  };

  /// Office / PDF / text / Markdown file logo by extension, else null.
  static AppIconData? forExtension(String? ext) => switch (ext) {
    'pdf' => pdf,
    'doc' || 'docx' => word,
    'xls' || 'xlsx' => excel,
    'ppt' || 'pptx' => powerpoint,
    'txt' || 'text' || 'log' => text,
    // The Markdown mark in the ink color: the colored file icon is brown
    // on brown and vanishes on the dark theme.
    'md' || 'markdown' => markdown,
    _ => null,
  };

  /// Real logo of a well-known site, for a web source with no favicon.
  static AppIconData? forDomain(String host) {
    final h = host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
    bool on(String d) => h == d || h.endsWith('.$d');
    if (on('github.com')) return github;
    if (on('reddit.com') || h == 'redd.it') return reddit;
    if (on('stackoverflow.com')) return stackoverflow;
    if (h == 'news.ycombinator.com') return hackernews;
    if (h == 'drive.google.com') return googleDrive;
    if (h == 'docs.google.com') return googleDocs;
    if (on('notion.so') || on('notion.site')) return notion;
    return null;
  }
}
