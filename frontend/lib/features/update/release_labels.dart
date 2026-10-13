import '../../core/constants/update.dart';
import '../../core/update/update_models.dart';

String kindLabel(UpdateKind k) => switch (k) {
  UpdateKind.patch => UpdateStrings.kindPatch,
  UpdateKind.feature => UpdateStrings.kindFeature,
  UpdateKind.major => UpdateStrings.kindMajor,
  UpdateKind.critical => UpdateStrings.kindCritical,
};

String statusLabel(ReleaseStatus s) => switch (s) {
  ReleaseStatus.draft => UpdateStrings.statusDraft,
  ReleaseStatus.live => UpdateStrings.statusLive,
  ReleaseStatus.pulled => UpdateStrings.statusPulled,
};
