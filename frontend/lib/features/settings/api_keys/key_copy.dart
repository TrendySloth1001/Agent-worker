import '../../../core/constants/api_keys.dart';
import '../../../data/api_keys_api.dart';

/// Friendly line for a live test result.
String keyCheckText(KeyCheck r) => switch (r) {
  KeyCheck.valid => ApiKeysStrings.resultValid,
  KeyCheck.invalid => ApiKeysStrings.resultInvalid,
  KeyCheck.quota => ApiKeysStrings.resultQuota,
  KeyCheck.network => ApiKeysStrings.resultNetwork,
};

/// Short chip label for a saved key's status.
String keyStatusText(KeyStatus s) => switch (s) {
  KeyStatus.valid => ApiKeysStrings.statusValid,
  KeyStatus.invalid => ApiKeysStrings.statusInvalid,
  KeyStatus.quota => ApiKeysStrings.statusQuota,
  KeyStatus.untested => ApiKeysStrings.statusUntested,
};
