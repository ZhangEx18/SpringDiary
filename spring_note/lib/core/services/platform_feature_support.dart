import 'dart:io';

class PlatformFeatureSupport {
  const PlatformFeatureSupport._();

  static bool get supportsAutoStart => Platform.isWindows;

  static bool get supportsGlobalHotkeys => Platform.isWindows;

  static bool get supportsTray => Platform.isWindows || Platform.isMacOS;

  static bool get supportsDesktopWidget => Platform.isWindows;
}
