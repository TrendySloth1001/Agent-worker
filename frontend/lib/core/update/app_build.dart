/// The running build number (pubspec `+N`), known once startup read it.
///
/// Sent as the `x-app-build` header on API calls so the server can tell which
/// version a request came from.
abstract final class AppBuild {
  static int? current;
}
