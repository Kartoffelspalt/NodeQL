import 'dart:convert';
import 'package:nodeql/core/platform/storage.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:nodeql/engine/block/block_node.dart';

enum LearningPathCalloutSide { left, right }

/// The editor abstraction shown while a learning-path step is active.
///
/// Paths default to [simple] so bundles and local drafts created before this
/// field was introduced remain fully compatible.
enum LearningPathMode { simple, advanced }

class LearningPathNodeTemplate {
  const LearningPathNodeTemplate({
    required this.ref,
    required this.type,
    this.defaults = const <String, dynamic>{},
  });

  final String ref;
  final BlockType type;
  final Map<String, dynamic> defaults;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'ref': ref,
    'type': type.name,
    'defaults': defaults,
  };

  factory LearningPathNodeTemplate.fromJson(Map<String, dynamic> json) {
    return LearningPathNodeTemplate(
      ref: '${json['ref'] ?? ''}',
      type: BlockType.values.firstWhere(
        (type) => type.name == json['type'],
        orElse: () => BlockType.sqlSelect,
      ),
      defaults: Map<String, dynamic>.from(
        json['defaults'] as Map? ?? const <String, dynamic>{},
      ),
    );
  }
}

class LearningPathNodeCallout {
  const LearningPathNodeCallout({
    required this.id,
    required this.targetRef,
    required this.title,
    required this.body,
    this.side = LearningPathCalloutSide.right,
  });

  final String id;
  final String targetRef;
  final String title;
  final String body;
  final LearningPathCalloutSide side;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'targetRef': targetRef,
    'title': title,
    'body': body,
    'side': side.name,
  };

  factory LearningPathNodeCallout.fromJson(Map<String, dynamic> json) {
    return LearningPathNodeCallout(
      id: '${json['id'] ?? ''}',
      targetRef: '${json['targetRef'] ?? ''}',
      title: '${json['title'] ?? ''}',
      body: '${json['body'] ?? ''}',
      side: LearningPathCalloutSide.values.firstWhere(
        (side) => side.name == json['side'],
        orElse: () => LearningPathCalloutSide.right,
      ),
    );
  }
}

class LearningPathStep {
  const LearningPathStep({
    required this.id,
    required this.title,
    required this.instruction,
    this.hint = '',
    this.mode = LearningPathMode.simple,
    this.nodes = const <LearningPathNodeTemplate>[],
    this.callouts = const <LearningPathNodeCallout>[],
  });

  final String id;
  final String title;
  final String instruction;
  final String hint;
  final LearningPathMode mode;
  final List<LearningPathNodeTemplate> nodes;
  final List<LearningPathNodeCallout> callouts;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'title': title,
    'instruction': instruction,
    'hint': hint,
    'mode': mode.name,
    'nodes': nodes.map((node) => node.toJson()).toList(),
    'callouts': callouts.map((callout) => callout.toJson()).toList(),
  };

  factory LearningPathStep.fromJson(Map<String, dynamic> json) {
    return LearningPathStep(
      id: '${json['id'] ?? ''}',
      title: '${json['title'] ?? ''}',
      instruction: '${json['instruction'] ?? ''}',
      hint: '${json['hint'] ?? ''}',
      mode: LearningPathMode.values.firstWhere(
        (mode) => mode.name == json['mode'],
        orElse: () => LearningPathMode.simple,
      ),
      nodes: (json['nodes'] as List? ?? const <Object>[])
          .whereType<Map>()
          .map(
            (node) => LearningPathNodeTemplate.fromJson(
              Map<String, dynamic>.from(node),
            ),
          )
          .toList(growable: false),
      callouts: (json['callouts'] as List? ?? const <Object>[])
          .whereType<Map>()
          .map(
            (callout) => LearningPathNodeCallout.fromJson(
              Map<String, dynamic>.from(callout),
            ),
          )
          .toList(growable: false),
    );
  }
}

class AuthoredLearningPath {
  const AuthoredLearningPath({
    required this.id,
    required this.title,
    required this.description,
    required this.steps,
    this.titleTranslations = const <String, String>{},
    this.descriptionTranslations = const <String, String>{},
  });

  final String id;
  final String title;
  final String description;
  final List<LearningPathStep> steps;
  final Map<String, String> titleTranslations;
  final Map<String, String> descriptionTranslations;

  /// Resolves bundle metadata for the app's current language.
  ///
  /// Locally authored paths continue to use their plain string fields. A
  /// published bundle can instead provide language maps without making old
  /// exports unreadable.
  String titleFor(String languageCode) =>
      _localizedBundleText(titleTranslations, languageCode, title);

  String descriptionFor(String languageCode) =>
      _localizedBundleText(descriptionTranslations, languageCode, description);

  int get calloutCount =>
      steps.fold<int>(0, (count, step) => count + step.callouts.length);

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'title': _bundleTextJson(title, titleTranslations),
    'description': _bundleTextJson(description, descriptionTranslations),
    'steps': steps.map((step) => step.toJson()).toList(),
  };

  factory AuthoredLearningPath.fromJson(Map<String, dynamic> json) {
    final title = _decodeBundleText(json['title']);
    final description = _decodeBundleText(json['description']);
    return AuthoredLearningPath(
      id: '${json['id'] ?? ''}',
      title: title.fallback,
      description: description.fallback,
      titleTranslations: title.translations,
      descriptionTranslations: description.translations,
      steps: (json['steps'] as List? ?? const <Object>[])
          .whereType<Map>()
          .map(
            (step) =>
                LearningPathStep.fromJson(Map<String, dynamic>.from(step)),
          )
          .toList(growable: false),
    );
  }
}

class _BundleText {
  const _BundleText({required this.fallback, required this.translations});

  final String fallback;
  final Map<String, String> translations;
}

_BundleText _decodeBundleText(Object? value) {
  if (value is String) {
    return _BundleText(fallback: value, translations: const <String, String>{});
  }
  if (value is! Map) {
    return const _BundleText(fallback: '', translations: <String, String>{});
  }
  final translations = <String, String>{
    for (final entry in value.entries)
      if ('${entry.key}'.trim().isNotEmpty &&
          '${entry.value}'.trim().isNotEmpty)
        '${entry.key}'.trim().toLowerCase(): '${entry.value}'.trim(),
  };
  return _BundleText(
    fallback:
        translations['en'] ??
        translations['de'] ??
        translations.values.firstOrNull ??
        '',
    translations: Map.unmodifiable(translations),
  );
}

Object _bundleTextJson(String fallback, Map<String, String> translations) =>
    translations.isEmpty ? fallback : translations;

String _localizedBundleText(
  Map<String, String> translations,
  String languageCode,
  String fallback,
) {
  final normalized = languageCode.toLowerCase().split(RegExp('[-_]')).first;
  return translations[languageCode.toLowerCase()] ??
      translations[normalized] ??
      translations['en'] ??
      fallback;
}

class LearningPathLibraryState {
  const LearningPathLibraryState({
    this.loading = true,
    this.paths = const <AuthoredLearningPath>[],
    this.error,
  });

  final bool loading;
  final List<AuthoredLearningPath> paths;
  final String? error;
}

final learningPathLibraryProvider =
    StateNotifierProvider<
      LearningPathLibraryController,
      LearningPathLibraryState
    >((_) => LearningPathLibraryController(enableLocalDrafts: false));

class LearningPathLibraryController
    extends StateNotifier<LearningPathLibraryState> {
  LearningPathLibraryController({
    Future<File> Function()? storageFile,
    Future<List<AuthoredLearningPath>> Function()? bundledPaths,
    bool enableLocalDrafts = true,
  }) : _storageFile = enableLocalDrafts
           ? (storageFile ?? _defaultStorageFile)
           : null,
       _bundledPathsLoader = bundledPaths ?? _defaultBundledPaths,
       super(const LearningPathLibraryState()) {
    initialize();
  }

  final Future<File> Function()? _storageFile;
  final Future<List<AuthoredLearningPath>> Function() _bundledPathsLoader;
  Future<void>? _initialization;
  Future<void> _pendingWrite = Future<void>.value();
  List<AuthoredLearningPath> _bundledPaths = const <AuthoredLearningPath>[];
  List<AuthoredLearningPath> _localPaths = const <AuthoredLearningPath>[];

  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    try {
      _bundledPaths = await _bundledPathsLoader();
      final storageFile = _storageFile;
      if (storageFile == null) {
        state = LearningPathLibraryState(loading: false, paths: _mergedPaths());
        return;
      }
      final file = await storageFile();
      if (!await file.exists()) {
        state = LearningPathLibraryState(loading: false, paths: _mergedPaths());
        return;
      }
      final decoded = jsonDecode(await file.readAsString());
      _localPaths = decodeLearningPathBundle(decoded);
      state = LearningPathLibraryState(loading: false, paths: _mergedPaths());
    } on Object catch (error) {
      state = LearningPathLibraryState(loading: false, error: '$error');
    }
  }

  Future<void> save(AuthoredLearningPath path) async {
    _ensureLocalDraftsEnabled();
    if (state.loading) await initialize();
    if (!_isValidPath(path)) {
      throw ArgumentError('A learning path needs an id, title and one step.');
    }
    _localPaths = <AuthoredLearningPath>[
      for (final existing in _localPaths)
        if (existing.id != path.id) existing,
      path,
    ];
    state = LearningPathLibraryState(loading: false, paths: _mergedPaths());
    await _persist();
  }

  Future<void> delete(String id) async {
    _ensureLocalDraftsEnabled();
    if (state.loading) await initialize();
    _localPaths = _localPaths
        .where((path) => path.id != id)
        .toList(growable: false);
    state = LearningPathLibraryState(loading: false, paths: _mergedPaths());
    await _persist();
  }

  Future<void> importBundle(String source) async {
    _ensureLocalDraftsEnabled();
    if (state.loading) await initialize();
    final imported = decodeLearningPathBundle(jsonDecode(source));
    for (final path in imported) {
      await save(path);
    }
  }

  String exportBundle() => encodeLearningPathBundle(state.paths);

  Future<void> _persist() {
    final storageFile = _storageFile;
    if (storageFile == null) {
      throw StateError('Published workshop libraries are read-only.');
    }
    final payload = encodeLearningPathBundle(_localPaths);
    _pendingWrite = _pendingWrite.then((_) async {
      final file = await storageFile();
      await file.parent.create(recursive: true);
      await file.writeAsString(payload, flush: true);
    });
    return _pendingWrite;
  }

  static bool _isValidPath(AuthoredLearningPath path) =>
      path.id.trim().isNotEmpty &&
      path.title.trim().isNotEmpty &&
      path.steps.isNotEmpty;

  void _ensureLocalDraftsEnabled() {
    if (_storageFile == null) {
      throw StateError('Published workshop libraries are read-only.');
    }
  }

  static Future<File> _defaultStorageFile() async {
    final support = await getApplicationSupportDirectory();
    return fileAt('${support.path}/nodeql_learning_paths.json');
  }

  static Future<List<AuthoredLearningPath>> _defaultBundledPaths() async {
    const key = 'assets/workshops/workshops.json';
    late final String source;
    try {
      source = await rootBundle.loadString(key);
    } on FlutterError {
      source = await rootBundle.loadString('packages/nodeql/$key');
    }
    return decodeLearningPathBundle(jsonDecode(source));
  }

  List<AuthoredLearningPath> _mergedPaths() {
    final byId = <String, AuthoredLearningPath>{
      for (final path in _bundledPaths) path.id: path,
      for (final path in _localPaths) path.id: path,
    };
    return List.unmodifiable(byId.values);
  }
}

String encodeLearningPathBundle(Iterable<AuthoredLearningPath> paths) =>
    const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
      'schemaVersion': 1,
      'paths': paths.map((path) => path.toJson()).toList(),
    });

List<AuthoredLearningPath> decodeLearningPathBundle(Object? decoded) {
  final rawPaths = decoded is Map ? decoded['paths'] : null;
  if (rawPaths is! List) return const <AuthoredLearningPath>[];
  return rawPaths
      .whereType<Map>()
      .map(
        (path) =>
            AuthoredLearningPath.fromJson(Map<String, dynamic>.from(path)),
      )
      .where(LearningPathLibraryController._isValidPath)
      .toList(growable: false);
}

Map<String, dynamic> learningPathNodeDefaults(BlockNode node) {
  final cloned = jsonDecode(jsonEncode(node.inputs));
  final defaults = Map<String, dynamic>.from(cloned as Map);
  defaults.remove('__width');
  defaults.remove('__height');
  return defaults;
}

String learningPathId(String title) {
  final slug = title
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  final suffix = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
  return '${slug.isEmpty ? 'learning-path' : slug}-$suffix';
}
