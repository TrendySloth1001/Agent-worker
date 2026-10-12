import '../../core/constants/apps.dart';
import '../../core/constants/connectors.dart';
import '../apps/apps_registry.dart';

/// Official logos of the connected apps (the Apps hub's logos).
abstract final class ConnectorBrand {
  static const drive = AppBrand(AppsIcons.googleDrive);
  static const notion = AppBrand(AppsIcons.notion);

  static AppBrand of(String provider) =>
      provider == ConnectorIds.notion ? notion : drive;

  /// Knowledge-base source types that come from a connected app.
  static AppBrand? forSourceType(String type) => switch (type) {
    ConnectorIds.drive => drive,
    ConnectorIds.notion => notion,
    _ => null,
  };
}
