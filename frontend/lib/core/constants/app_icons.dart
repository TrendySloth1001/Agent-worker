import 'package:hugeicons/hugeicons.dart';

/// Icon data type used by [AppIcon] (Hugeicons stroke-rounded paths).
typedef AppIconData = List<List<dynamic>>;

/// Every icon in the app, by meaning. Hugeicons, stroke rounded.
abstract final class AppIcons {
  // Navigation and actions
  static const back = HugeIcons.strokeRoundedArrowLeft01;
  static const close = HugeIcons.strokeRoundedCancel01;
  static const add = HugeIcons.strokeRoundedAdd01;
  static const remove = HugeIcons.strokeRoundedRemove01;
  static const newChat = HugeIcons.strokeRoundedBubbleChatAdd;
  static const settings = HugeIcons.strokeRoundedSlidersHorizontal;
  static const history = HugeIcons.strokeRoundedClock01;
  static const menu = HugeIcons.strokeRoundedSidebarLeft;
  static const knowledge = HugeIcons.strokeRoundedBookOpen01;
  static const search = HugeIcons.strokeRoundedSearch01;
  static const send = HugeIcons.strokeRoundedArrowUp02;
  static const stop = HugeIcons.strokeRoundedStopCircle;
  static const mic = HugeIcons.strokeRoundedMic01;
  static const scrollDown = HugeIcons.strokeRoundedArrowDown02;
  static const expand = HugeIcons.strokeRoundedArrowDown01;
  static const collapse = HugeIcons.strokeRoundedArrowUp01;
  static const chevronRight = HugeIcons.strokeRoundedArrowRight01;
  static const copy = HugeIcons.strokeRoundedCopy01;
  static const check = HugeIcons.strokeRoundedTick02;
  static const regenerate = HugeIcons.strokeRoundedRefresh;
  static const edit = HugeIcons.strokeRoundedPencilEdit01;
  static const delete = HugeIcons.strokeRoundedDelete02;
  static const more = HugeIcons.strokeRoundedMoreVertical;
  static const pin = HugeIcons.strokeRoundedPin;
  static const unpin = HugeIcons.strokeRoundedPinOff;
  static const archive = HugeIcons.strokeRoundedArchive02;
  static const unarchive = HugeIcons.strokeRoundedArchive03;
  static const fork = HugeIcons.strokeRoundedGitFork;
  static const merge = HugeIcons.strokeRoundedGitMerge;
  static const roundTable = HugeIcons.strokeRoundedUserGroup;
  static const visit = HugeIcons.strokeRoundedGlobe02;
  static const aiFormat = HugeIcons.strokeRoundedAiMagic;
  static const undo = HugeIcons.strokeRoundedUndo02;
  static const openExternal = HugeIcons.strokeRoundedLinkSquare02;
  static const browser = HugeIcons.strokeRoundedBrowser;
  static const link = HugeIcons.strokeRoundedLink01;
  static const sortAscending = HugeIcons.strokeRoundedArrowUp01;
  static const sortDescending = HugeIcons.strokeRoundedArrowDown01;
  static const fullscreen = HugeIcons.strokeRoundedArrowExpand01;
  static const imageMissing = HugeIcons.strokeRoundedImageNotFound01;
  static const image = HugeIcons.strokeRoundedImage01;
  static const alert = HugeIcons.strokeRoundedAlertCircle;
  static const tip = HugeIcons.strokeRoundedBulb;
  static const ok = HugeIcons.strokeRoundedCheckmarkCircle02;

  // Attachments
  static const attach = HugeIcons.strokeRoundedAttachment01;
  static const camera = HugeIcons.strokeRoundedCamera01;
  static const video = HugeIcons.strokeRoundedVideo01;
  static const file = HugeIcons.strokeRoundedFile01;
  static const audio = HugeIcons.strokeRoundedMusicNote01;
  static const play = HugeIcons.strokeRoundedPlayCircle;
  static const retry = HugeIcons.strokeRoundedRefresh;
  static const playPlain = HugeIcons.strokeRoundedPlay;
  static const pause = HugeIcons.strokeRoundedPause;
  static const fileDeleted = HugeIcons.strokeRoundedFileRemove;

  // Chat
  static const web = HugeIcons.strokeRoundedGlobe02;
  static const assistant = HugeIcons.strokeRoundedAiChat02;
  static const chat = HugeIcons.strokeRoundedBubbleChat;
  static const diagram = HugeIcons.strokeRoundedFlowchart01;
  static const code = HugeIcons.strokeRoundedCodeSquare;

  /// DOC mode: a long-form document (chip, card, reader).
  static const doc = HugeIcons.strokeRoundedFile02;

  // Modes
  static const modeEngineer = HugeIcons.strokeRoundedComputerTerminal01;
  static const modeDebug = HugeIcons.strokeRoundedBug01;
  static const modeReview = HugeIcons.strokeRoundedCheckList;
  static const modeArchitect = HugeIcons.strokeRoundedBuilding03;
  static const modeExplain = HugeIcons.strokeRoundedMortarboard01;

  // Settings sections and services
  static const models = HugeIcons.strokeRoundedAiBrain01;
  static const dataTools = HugeIcons.strokeRoundedDatabase01;
  static const appearance = HugeIcons.strokeRoundedPaintBoard;
  static const about = HugeIcons.strokeRoundedInformationCircle;
  static const usage = HugeIcons.strokeRoundedActivity01;
  static const key = HugeIcons.strokeRoundedKey01;
  static const github = HugeIcons.strokeRoundedGithub;
  static const embeddings = HugeIcons.strokeRoundedNeuralNetwork;
  static const server = HugeIcons.strokeRoundedServer;
  static const database = HugeIcons.strokeRoundedDatabase01;
  static const haptics = HugeIcons.strokeRoundedVibrate;
  static const timer = HugeIcons.strokeRoundedTimer01;

  // Personalization
  static const personalization = HugeIcons.strokeRoundedUserCircle;
  static const profileName = HugeIcons.strokeRoundedUser;
  static const profileRole = HugeIcons.strokeRoundedBriefcase01;
  static const profileAbout = HugeIcons.strokeRoundedNote01;
  static const profileLanguage = HugeIcons.strokeRoundedTranslate;
  static const profileInstructions = HugeIcons.strokeRoundedIdea01;
  static const profileSignature = HugeIcons.strokeRoundedPen01;
  static const toneFriendly = HugeIcons.strokeRoundedSmile;
  static const toneProfessional = HugeIcons.strokeRoundedBriefcase01;
  static const toneCasual = HugeIcons.strokeRoundedMessage01;
  static const toneDirect = HugeIcons.strokeRoundedFlash;
  static const toneEnthusiastic = HugeIcons.strokeRoundedSparkles;
  static const lengthConcise = HugeIcons.strokeRoundedMenu01;
  static const lengthBalanced = HugeIcons.strokeRoundedTextAlignLeft;
  static const lengthDetailed = HugeIcons.strokeRoundedTextAlignJustifyLeft;

  /// Icon for a reply tone id.
  static AppIconData tone(String id) => switch (id) {
    'professional' => toneProfessional,
    'casual' => toneCasual,
    'direct' => toneDirect,
    'enthusiastic' => toneEnthusiastic,
    _ => toneFriendly,
  };

  // Providers
  static const groq = HugeIcons.strokeRoundedFlash;
  static const nvidia = HugeIcons.strokeRoundedCpu;
  static const ollama = HugeIcons.strokeRoundedCloud;
  static const openrouter = HugeIcons.strokeRoundedRoute01;

  // Theme
  static const themeSystem = HugeIcons.strokeRoundedSmartPhone01;
  static const themeLight = HugeIcons.strokeRoundedSun03;
  static const themeDark = HugeIcons.strokeRoundedMoon02;

  // Knowledge source kinds
  static const sourceWeb = HugeIcons.strokeRoundedGlobe02;
  static const sourceGithub = HugeIcons.strokeRoundedGithub;
  static const sourceForum = HugeIcons.strokeRoundedComment01;
  static const sourceNews = HugeIcons.strokeRoundedNews01;
  static const sourceReddit = HugeIcons.strokeRoundedReddit;
  static const sourceNote = HugeIcons.strokeRoundedNote01;
  static const sourceAuto = HugeIcons.strokeRoundedMagicWand01;

  /// Icon for a knowledge source type id.
  static AppIconData sourceKind(String type) => switch (type) {
    'github' => sourceGithub,
    'stackoverflow' => sourceForum,
    'reddit' => sourceReddit,
    'hackernews' => sourceNews,
    'note' => sourceNote,
    'file' => file,
    'doc' => doc,
    _ => sourceWeb,
  };

  /// Icon for a chat mode id.
  static AppIconData mode(String id) => switch (id) {
    'debug' => modeDebug,
    'review' => modeReview,
    'design' => modeArchitect,
    'explain' => modeExplain,
    _ => modeEngineer,
  };

  /// Icon for a model provider id.
  static AppIconData provider(String id) => switch (id) {
    'groq' => groq,
    'nvidia' => nvidia,
    'ollama' => ollama,
    'openrouter' => openrouter,
    _ => models,
  };
}

/// Round Table waiting and research.
abstract final class TableIcons {
  static const notify = HugeIcons.strokeRoundedNotification01;
  static const answerFast = HugeIcons.strokeRoundedFlash;
  static const query = HugeIcons.strokeRoundedSearch01;
}
