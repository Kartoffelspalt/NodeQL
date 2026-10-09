import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

class OnboardingLaunchState {
  const OnboardingLaunchState({
    this.loading = true,
    this.hasSeenOnboarding = false,
  });

  final bool loading;
  final bool hasSeenOnboarding;

  bool get shouldShow => !loading && !hasSeenOnboarding;
}

final onboardingLaunchProvider =
    StateNotifierProvider<OnboardingLaunchController, OnboardingLaunchState>(
      (_) => OnboardingLaunchController(),
    );

/// Stores only whether the automatic first-run walkthrough was acknowledged.
/// The authored walkthrough itself always stays in the imported JSON file.
class OnboardingLaunchController extends StateNotifier<OnboardingLaunchState> {
  OnboardingLaunchController({
    Future<File> Function()? storageFile,
    bool initiallySeen = false,
  }) : _storageFile = storageFile ?? _defaultStorageFile,
       super(
         initiallySeen
             ? const OnboardingLaunchState(
                 loading: false,
                 hasSeenOnboarding: true,
               )
             : const OnboardingLaunchState(),
       ) {
    if (!initiallySeen) initialize();
  }

  final Future<File> Function() _storageFile;
  Future<void>? _initialization;

  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    try {
      final file = await _storageFile();
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map && decoded['hasSeenOnboarding'] == true) {
          state = const OnboardingLaunchState(
            loading: false,
            hasSeenOnboarding: true,
          );
          return;
        }
      }
    } catch (_) {
      // A storage error must not prevent newcomers from using NodeQL.
    }
    state = const OnboardingLaunchState(loading: false);
  }

  Future<void> markSeen() async {
    if (state.loading) await initialize();
    if (!mounted || state.hasSeenOnboarding) return;
    state = const OnboardingLaunchState(
      loading: false,
      hasSeenOnboarding: true,
    );
    try {
      final file = await _storageFile();
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode(<String, Object>{
          'schemaVersion': 1,
          'hasSeenOnboarding': true,
        }),
        flush: true,
      );
    } catch (_) {}
  }

  static Future<File> _defaultStorageFile() async {
    final support = await getApplicationSupportDirectory();
    return File('${support.path}/nodeql_onboarding_state.json');
  }
}
