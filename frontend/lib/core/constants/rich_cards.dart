import 'package:flutter/painting.dart';
import 'package:hugeicons/hugeicons.dart';

import 'app_icons.dart';

/// Strings for the rich in-chat cards (email, message, spec, diff).
abstract final class RichStrings {
  static const emailDraft = 'EMAIL DRAFT';
  static const to = 'TO';
  static const cc = 'CC';
  static const subject = 'SUBJECT';
  static const noSubject = '(NO SUBJECT)';
  static const copyBody = 'COPY BODY';
  static const openInMail = 'OPEN IN MAIL';
  static const message = 'MESSAGE';
  static const send = 'SEND';
  static const sendSms = 'OPEN SMS';
  static const sendWhatsapp = 'OPEN WHATSAPP';
  static const diff = 'DIFF';
  static const cantOpen = 'No app found to open this.';
  static const edit = 'EDIT';
  static const done = 'DONE';
  static const undo = 'UNDO';
  static const addSignature = 'ADD SIGNATURE';
  static const aiRewrite = 'AI REWRITE';
  static const rewriting = 'REWRITING…';
  static const shorter = 'SHORTER';
  static const longer = 'LONGER';
  static const formal = 'FORMAL';
  static const friendly = 'FRIENDLY';
  static const fixGrammar = 'FIX GRAMMAR';
  static const custom = 'CUSTOM';
  static const customTitle = 'REWRITE INSTRUCTION';
  static const customHint = 'e.g. Add a deadline of Friday';
  static const customGo = 'REWRITE';
  static const customMax = 500;
  static const rewriteFailed = 'Could not rewrite the email.';
  static const bcc = 'BCC';
  static const bodyHint = 'Write your message';
  static const wordsPerMinute = 200;

  /// Caption under the body, e.g. `128 WORDS · 1 MIN READ`.
  static String stats(int words, int minutes) =>
      '$words ${words == 1 ? 'WORD' : 'WORDS'} · $minutes MIN READ';
}

/// Protocol bits used to hand a draft to another app.
abstract final class RichLinks {
  static const mailto = 'mailto';
  static const sms = 'sms';
  static const whatsapp = 'https://wa.me/';
  static const mailSubject = 'subject';
  static const mailCc = 'cc';
  static const mailBcc = 'bcc';
  static const mailBody = 'body';
  static const textParam = 'text';
}

abstract final class RichIcons {
  /// Iconify brand logo on the open-in-mail action.
  static const gmail = 'logos:google-gmail';
  static const mail = HugeIcons.strokeRoundedMail01;
  static const send = HugeIcons.strokeRoundedSent;
  static const chat = AppIcons.chat;
  static const sms = HugeIcons.strokeRoundedMessage01;
  static const diff = AppIcons.code;
  static const openExternal = AppIcons.openExternal;
  static const edit = AppIcons.edit;
  static const done = AppIcons.check;
  static const undo = HugeIcons.strokeRoundedUndo;
  static const signature = AppIcons.profileSignature;
  static const shorter = HugeIcons.strokeRoundedArrowShrink;
  static const longer = HugeIcons.strokeRoundedArrowExpand01;
  static const formal = AppIcons.toneProfessional;
  static const friendly = AppIcons.toneFriendly;
  static const fix = HugeIcons.strokeRoundedSpellCheck;
  static const custom = HugeIcons.strokeRoundedSparkles;
}

/// Iconify ids of chat-platform brand marks.
abstract final class RichPlatforms {
  static const slack = 'slack';
  static const whatsapp = 'whatsapp';
  static const sms = 'sms';
  static const teams = 'teams';
  static const discord = 'discord';

  static const names = {
    slack: 'SLACK',
    whatsapp: 'WHATSAPP',
    sms: 'SMS',
    teams: 'TEAMS',
    discord: 'DISCORD',
  };

  /// (set, name) of the brand icon; absent for SMS and unknown platforms.
  static const brandIcons = {
    slack: ('logos', 'slack-icon'),
    whatsapp: ('logos', 'whatsapp-icon'),
    teams: ('logos', 'microsoft-teams'),
    discord: ('logos', 'discord-icon'),
  };
}

abstract final class RichSizes {
  static const actionMinTap = 32.0;
  static const brandIcon = 16.0;
  static const specIcon = 28.0;

  static const inlineCodeAlpha = 0.6;
  static const disabledAlpha = 0.4;
  static const progressHeight = 2.0;
  static const fieldLabelWidth = 56.0;
  static const fieldMaxLines = 20;
}

/// Strings for the ```ask and ```flow blocks.
abstract final class AskStrings {
  static const question = 'QUESTION';
  static const preparing = 'PREPARING QUESTION…';
  static const other = 'Other…';
  static const otherHint = 'Type your answer';
  static const send = 'SEND';
  static const answered = 'ANSWERED';
  static const multiHint = 'SELECT ALL THAT APPLY';
  static const separator = ', ';
  static const minOptions = 2;
  static const maxOptions = 6;
  static const otherMax = 300;
}

abstract final class FlowStrings {
  static const flow = 'FLOW';
  static const preparing = 'PREPARING FLOW…';
}

abstract final class AskIcons {
  static const question = HugeIcons.strokeRoundedHelpCircle;
  static const flow = HugeIcons.strokeRoundedWorkflowSquare01;
  static const arrowDown = HugeIcons.strokeRoundedArrowDown01;
}

abstract final class AskSizes {
  static const optionMinHeight = 44.0;
  static const mark = 18.0;
  static const markDot = 8.0;
  static const tileMinWidth = 72.0;
  static const tileMaxWidth = 120.0;
  static const arrow = 16.0;
  static const flowIcon = 20.0;
  static const fieldMaxLines = 3;
}

/// Code diff viewer (```diff cards and GitHub commit / compare diffs).
abstract final class DiffStyle {
  static const fontSize = 12.0;
  static const lineHeight = 1.5;
  static const numberWidth = 30.0;
  static const signWidth = 14.0;
  static const tabSpaces = '  ';

  /// Rows shown before SHOW ALL.
  static const maxRows = 300;

  /// Green for added lines (the palette has no green; diffs need one).
  static const addDark = Color(0xFF3FB950);
  static const addLight = Color(0xFF1A7F37);
  static const addAlpha = 0.14;
  static const removeAlpha = 0.12;

  static const wrap = 'WRAP';
  static const scroll = 'SCROLL';
  static const showAll = 'SHOW ALL';
}
