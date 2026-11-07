import 'dart:io';
import 'dart:ui';

import 'package:flutter/services.dart';

/// Closes the app only after its update helper is ready to take over.
Future<void> finishDesktopUpdateHandoff(
  Directory directory, {
  bool waitForWindowsHelper = false,
  Duration helperStartupTimeout = const Duration(seconds: 15),
}) async {
  try {
    if (waitForWindowsHelper) {
      final ready = File('${directory.path}${Platform.pathSeparator}ready');
      final elapsed = Stopwatch()..start();
      while (!await ready.exists()) {
        if (elapsed.elapsed >= helperStartupTimeout) {
          throw StateError('The Windows update helper did not start');
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }

    final binding = ServicesBinding.instance;
    // On Windows a cancelable native exit returns "cancel" immediately, even
    // when the framework subsequently agrees to quit. Await the actual exit
    // observers first, then request a clean, required native exit.
    if (await binding.handleRequestAppExit() == AppExitResponse.cancel) {
      throw StateError('The application did not close');
    }
    final response = await binding.exitApplication(AppExitType.required);
    if (response == AppExitResponse.cancel) {
      throw StateError('The application did not close');
    }
  } catch (_) {
    await File('${directory.path}${Platform.pathSeparator}cancel').create();
    rethrow;
  }
}
