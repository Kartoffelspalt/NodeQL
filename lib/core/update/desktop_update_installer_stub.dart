import 'github_release_update_service.dart';

class DesktopUpdateInstaller {
  bool canInstall(AppUpdate update) => false;

  Future<void> install(AppUpdate update) =>
      throw UnsupportedError('Desktop updates are unavailable');
}
