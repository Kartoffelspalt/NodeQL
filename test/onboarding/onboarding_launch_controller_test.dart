import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nodeql/features/onboarding/onboarding_launch_controller.dart';

void main() {
  test('shows only until the first walkthrough is acknowledged', () async {
    final directory = Directory.systemTemp.createTempSync('nodeql-onboarding-');
    addTearDown(() => directory.deleteSync(recursive: true));
    Future<File> storageFile() async => File('${directory.path}/state.json');

    final firstRun = OnboardingLaunchController(storageFile: storageFile);
    await firstRun.initialize();
    expect(firstRun.state.shouldShow, isTrue);

    await firstRun.markSeen();
    expect(firstRun.state.shouldShow, isFalse);

    final laterRun = OnboardingLaunchController(storageFile: storageFile);
    await laterRun.initialize();
    expect(laterRun.state.shouldShow, isFalse);
  });
}
