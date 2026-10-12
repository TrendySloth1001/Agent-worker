import 'package:hugeicons/hugeicons.dart';

import 'app_icons.dart';

/// Owner-only telemetry (Settings → TELEMETRY): every model call, minute by
/// minute. Backend: `GET /admin/telemetry/{overview,timeseries,events,stream}`.

abstract final class TelemetryPaths {
  static const overview = '/admin/telemetry/overview';
  static const timeseries = '/admin/telemetry/timeseries';
  static const events = '/admin/telemetry/events';
  static const stream = '/admin/telemetry/stream';

  /// SSE event names.
  static const usageEvent = 'usage';
  static const helloEvent = 'hello';
}

/// Query values the backend accepts.
abstract final class TelemetryWindows {
  static const hour = '1h';
  static const day = '24h';
  static const week = '7d';
  static const month = '30d';
  static const all = [hour, day, week, month];
  static const fallback = day;
}

abstract final class TelemetryBuckets {
  static const minute = '1m';
  static const fiveMinutes = '5m';
  static const hour = '1h';
  static const all = [minute, fiveMinutes, hour];
}

abstract final class TelemetryStrings {
  // Settings entry.
  static const section = 'TELEMETRY';

  // Screen.
  static const title = 'Telemetry';
  static const live = 'LIVE';
  static const paused = 'PAUSED';
  static const offline = 'OFFLINE';
  static const loadFailed = 'COULD NOT LOAD TELEMETRY';
  static const retry = 'RETRY';
  static const empty = 'NO CALLS IN THIS WINDOW';
  static const emptyLog = 'NO EVENTS YET';
  static const loadMore = 'LOAD OLDER';
  static const noMore = 'END OF LOG';

  // Window labels.
  static const windowLabels = {
    TelemetryWindows.hour: '1H',
    TelemetryWindows.day: '24H',
    TelemetryWindows.week: '7D',
    TelemetryWindows.month: '30D',
  };
  static const bucketLabels = {
    TelemetryBuckets.minute: '1 MIN',
    TelemetryBuckets.fiveMinutes: '5 MIN',
    TelemetryBuckets.hour: '1 HOUR',
  };

  // Big numbers.
  static const requests = 'REQUESTS';
  static const failed = 'FAILED';
  static const failureRate = 'FAIL RATE';
  static const tokensIn = 'TOKENS IN';
  static const tokensOut = 'TOKENS OUT';
  static const p50 = 'P50';
  static const p95 = 'P95';
  static const ttft = 'TTFT';
  static const avg = 'AVG';
  static const latency = 'LATENCY';
  static const units = 'UNITS';
  static const lastCall = 'LAST CALL';

  // Sections.
  static const charts = 'PER MINUTE';
  static const chartRequests = 'REQUESTS / FAILURES';
  static const chartTokens = 'TOKENS';
  static const chartLatency = 'LATENCY P50 / TTFT';
  static const legendOk = 'OK';
  static const legendFailed = 'FAILED';
  static const legendIn = 'IN';
  static const legendOut = 'OUT';
  static const legendLatency = 'P50';
  static const legendTtft = 'TTFT';
  static const filterAll = 'ALL';
  static const filterProvider = 'PROVIDER';
  static const filterKind = 'KIND';
  static const models = 'MODELS';
  static const providers = 'PROVIDERS';
  static const kinds = 'BY KIND';
  static const users = 'USERS';
  static const topErrors = 'TOP ERRORS';
  static const log = 'LIVE LOG';
  static const failedOnly = 'FAILED ONLY';
  static const pause = 'PAUSE';
  static const resume = 'RESUME';
  static const newEvents = 'NEW';

  // Model rows.
  static const cooldown = 'COOLDOWN';
  static const idle = 'IDLE';
  static const unused = 'NO CALLS';
  static const notRouted = 'NOT IN ROUTER';
  static const lastError = 'LAST ERROR';
  static const failuresByCode = 'FAILURES BY CODE';
  static const rateLimit = 'RATE LIMIT';
  static const rateRequests = 'REQ LEFT';
  static const rateTokens = 'TOK LEFT';
  static const rateResets = 'RESETS';
  static const openDetail = 'DETAILS';
  static const recentEvents = 'RECENT EVENTS';

  // Users.
  static const today = 'TODAY';
  static const inWindow = 'IN WINDOW';
  static const system = 'SYSTEM / BACKGROUND';

  // Event detail.
  static const fieldTime = 'TIME';
  static const fieldProvider = 'PROVIDER';
  static const fieldModel = 'MODEL';
  static const fieldKind = 'KIND';
  static const fieldPurpose = 'PURPOSE';
  static const fieldStatus = 'STATUS';
  static const fieldError = 'ERROR';
  static const fieldMessage = 'MESSAGE';
  static const fieldLatency = 'LATENCY';
  static const fieldTtft = 'TTFT';
  static const fieldTokens = 'TOKENS IN / OUT';
  static const fieldCount = 'COUNT';
  static const fieldAttempt = 'ATTEMPT';
  static const fieldUser = 'USER';
  static const fieldRequest = 'REQUEST';
  static const fieldConversation = 'CONVERSATION';
  static const fieldId = 'EVENT ID';
  static const statusOk = 'OK';
  static const statusFailed = 'FAIL';

  // Units.
  static const ms = 'MS';
  static const seconds = 'S';
  static const percent = '%';
  static const tokensShort = 'TOK';
  static const slash = ' / ';
  static const times = '×';
  static const separator = ' · ';
  static const noModel = '(no model)';
}

abstract final class TelemetrySizes {
  static const statTileMinWidth = 96.0;
  static const statColumns = 3;
  static const chartHeight = 150.0;
  static const chartLeftAxis = 36.0;
  static const chartBottomAxis = 18.0;
  static const chartXLabels = 4;
  static const chartYTicks = 3;
  static const chartLineWidth = 2.5;
  static const chartBarRadius = 3.0;
  static const chartBarFill = 0.7;
  static const chartBarMin = 1.0;
  static const chartBarMax = 10.0;
  static const chartGridAlpha = 0.5;
  static const gridDash = [1, 5];
  static const lineDash = [4, 3];

  /// Line charts draw point dots up to this many buckets.
  static const dotsMaxPoints = 24;
  static const chipHeight = 40.0;
  static const liveDot = 8.0;
  static const liveDotMinOpacity = 0.2;
  static const eventRowHeight = 44.0;
  static const eventTimeWidth = 64.0;
  static const eventStatusWidth = 44.0;
  static const eventKindMax = 96.0;
  static const errorLines = 3;
  static const rateBarDots = 20;

  /// Live events kept in the list before the oldest drop off.
  static const maxEvents = 2000;
  static const pageSize = 100;

  /// Load the next page this close to the end of the list.
  static const loadMoreThreshold = 600.0;
  static const topErrorsShown = 8;
  static const usersShown = 20;
  static const kindsShown = 16;
}

abstract final class TelemetryDurations {
  static const timeout = Duration(seconds: 15);
  static const pulse = Duration(milliseconds: 900);

  /// Live events trigger a refresh of totals and charts at most this often.
  static const liveRefresh = Duration(seconds: 8);
  static const countdownTick = Duration(seconds: 1);
  static const reconnectMin = Duration(seconds: 2);
  static const reconnectMax = Duration(seconds: 30);

  /// No ping for this long means the stream is dead (server pings every 15 s).
  static const streamIdle = Duration(seconds: 40);
}

abstract final class TelemetryIcons {
  static const section = HugeIcons.strokeRoundedAnalytics01;
  static const live = HugeIcons.strokeRoundedLiveStreaming01;
  static const chart = HugeIcons.strokeRoundedChartHistogram;
  static const tokens = HugeIcons.strokeRoundedCoins01;
  static const latency = HugeIcons.strokeRoundedDashboardSpeed01;
  static const models = AppIcons.models;
  static const providers = HugeIcons.strokeRoundedServerStack01;
  static const kinds = HugeIcons.strokeRoundedLeftToRightListBullet;
  static const users = HugeIcons.strokeRoundedUserMultiple;
  static const errors = AppIcons.alert;
  static const log = HugeIcons.strokeRoundedPulse01;
  static const filter = HugeIcons.strokeRoundedFilterHorizontal;
  static const pause = HugeIcons.strokeRoundedPauseCircle;
  static const resume = HugeIcons.strokeRoundedPlayCircle;
  static const cooldown = AppIcons.timer;
  static const ok = AppIcons.ok;
  static const failed = AppIcons.alert;
  static const chevron = AppIcons.chevronRight;
  static const expand = AppIcons.expand;
  static const collapse = AppIcons.collapse;
  static AppIconData provider(String id) => switch (id) {
    'github' => AppIcons.github,
    _ => AppIcons.provider(id),
  };
}
