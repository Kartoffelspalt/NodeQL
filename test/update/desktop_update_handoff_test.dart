import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nodeql/core/update/desktop_update_handoff.dart';
import 'package:path/path.dart' as path;

class _UpdateTestBinding extends AutomatedTestWidgetsFlutterBinding {
  final exitRequests = <AppExitType>[];
  Future<AppExitResponse> Function(AppExitType)? onNativeExit;

  @override
  Future<AppExitResponse> exitApplication(
    AppExitType exitType, [
    int exitCode = 0,
  ]) async {
    exitRequests.add(exitType);
    if (onNativeExit != null) return onNativeExit!(exitType);
    // Reproduce Windows: cancelable exits return cancel immediately,
    // regardless of whether the app ultimately agrees to quit.
    return exitType == AppExitType.required
        ? AppExitResponse.exit
        : AppExitResponse.cancel;
  }
}

class _ExitObserver extends WidgetsBindingObserver {
  _ExitObserver(this.onExit);

  final Future<AppExitResponse> Function() onExit;

  @override
  Future<AppExitResponse> didRequestAppExit() => onExit();
}

void main() {
  final binding = _UpdateTestBinding();
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('nodeql-handoff-test-');
    binding.exitRequests.clear();
    binding.onNativeExit = null;
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  Future<bool> canceled() => File(path.join(directory.path, 'cancel')).exists();

  test(
    'hands off without falsely canceling an approved Windows exit',
    () async {
      await File(path.join(directory.path, 'ready')).create();
      final observer = _ExitObserver(() async => AppExitResponse.exit);
      binding.addObserver(observer);
      addTearDown(() => binding.removeObserver(observer));

      await finishDesktopUpdateHandoff(directory, waitForWindowsHelper: true);

      expect(binding.exitRequests, [AppExitType.required]);
      expect(await canceled(), isFalse);
    },
  );

  test('waits for exit observers before requesting native shutdown', () async {
    final decision = Completer<AppExitResponse>();
    final consulted = Completer<void>();
    final observer = _ExitObserver(() {
      consulted.complete();
      return decision.future;
    });
    binding.addObserver(observer);
    addTearDown(() => binding.removeObserver(observer));

    final handoff = finishDesktopUpdateHandoff(directory);
    await consulted.future;
    expect(binding.exitRequests, isEmpty);
    decision.complete(AppExitResponse.exit);
    await handoff;

    expect(binding.exitRequests, [AppExitType.required]);
  });

  test('cancels the helper when an exit observer refuses shutdown', () async {
    final observer = _ExitObserver(() async => AppExitResponse.cancel);
    binding.addObserver(observer);
    addTearDown(() => binding.removeObserver(observer));

    await expectLater(finishDesktopUpdateHandoff(directory), throwsStateError);

    expect(binding.exitRequests, isEmpty);
    expect(await canceled(), isTrue);
  });

  test(
    'does not close the app when the Windows helper fails to start',
    () async {
      await expectLater(
        finishDesktopUpdateHandoff(
          directory,
          waitForWindowsHelper: true,
          helperStartupTimeout: Duration.zero,
        ),
        throwsStateError,
      );

      expect(binding.exitRequests, isEmpty);
      expect(await canceled(), isTrue);
    },
  );

  test('waits for the Windows helper readiness signal', () async {
    final handoff = finishDesktopUpdateHandoff(
      directory,
      waitForWindowsHelper: true,
    );
    expect(binding.exitRequests, isEmpty);
    await File(path.join(directory.path, 'ready')).create();
    await handoff;

    expect(binding.exitRequests, [AppExitType.required]);
    expect(await canceled(), isFalse);
  });

  test('cancels the helper when the native exit fails', () async {
    binding.onNativeExit = (_) async =>
        throw PlatformException(code: 'exit_failed');

    await expectLater(
      finishDesktopUpdateHandoff(directory),
      throwsA(isA<PlatformException>()),
    );

    expect(await canceled(), isTrue);
  });
}
