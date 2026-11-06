import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:nodeql/core/platform/storage.dart';
import 'package:nodeql/engine/block/block_node.dart';
import 'package:path/path.dart' as p;

import 'classroom_workshop_code.dart';
import 'classroom_workshop_transport.dart';
import 'learning_path_authoring.dart';

const _maxBundleBytes = 256 * 1024;
const _maxInstalled = 20;
const _idPrefix = 'downloaded:';
final _digestPattern = RegExp(r'^[0-9a-f]{64}$');
final _idPattern = RegExp(r'^[A-Za-z0-9_-]{1,100}$');

bool isDownloadedWorkshop(AuthoredLearningPath path) =>
    path.id.startsWith(_idPrefix);

class WorkshopDownloadLink {
  WorkshopDownloadLink._(this.uri, this.digest);

  final Uri uri;
  final String digest;

  factory WorkshopDownloadLink.parse(String source) {
    final link = source.length <= 2048 ? Uri.tryParse(source.trim()) : null;
    if (link == null ||
        link.scheme != 'https' ||
        !(link.host == 'raw.githubusercontent.com' ||
            link.host.endsWith('.github.io')) ||
        link.authority != link.host ||
        link.hasQuery ||
        !link.path.endsWith('.json') ||
        !link.fragment.startsWith('sha256=') ||
        !_digestPattern.hasMatch(link.fragment.substring(7))) {
      throw const FormatException('Invalid workshop link.');
    }
    return WorkshopDownloadLink._(
      link.removeFragment(),
      link.fragment.substring(7),
    );
  }
}

class WorkshopDownload {
  WorkshopDownload._(this._bytes, this._digest, this.path);

  final Uint8List _bytes;
  final String _digest;
  final AuthoredLearningPath path;
}

/// The link pins exact bytes. Only verified, validated bytes enter the cache.
class RemoteWorkshopRepository {
  RemoteWorkshopRepository({
    http.Client Function()? createClient,
    http.Client Function()? createClassroomClient,
    Future<Directory> Function()? supportDirectory,
  }) : _createClient = createClient ?? http.Client.new,
       _createClassroomClient =
           createClassroomClient ?? createClassroomWorkshopClient,
       _supportDirectory = supportDirectory ?? getApplicationSupportDirectory;

  final http.Client Function() _createClient;
  final http.Client Function() _createClassroomClient;
  final Future<Directory> Function() _supportDirectory;
  Future<void> _pendingWrite = Future<void>.value();

  Future<WorkshopDownload> download(WorkshopDownloadLink link) async {
    final bytes = await _fetch(
      _createClient(),
      link.uri,
      maxBytes: _maxBundleBytes,
      accept: 'application/json',
    );
    return _verify(bytes, link.digest);
  }

  Future<WorkshopDownload> downloadClassroom(ClassroomWorkshopCode code) async {
    final sealed = await _fetch(
      _createClassroomClient(),
      code.requestUri,
      maxBytes: _maxBundleBytes + ClassroomWorkshopCode.encryptionOverhead,
      accept: 'application/octet-stream',
    );
    return _verify(await code.open(sealed), code.digest);
  }

  Future<WorkshopDownload> readFile(Stream<List<int>> contents) async {
    final bytes = await _readBounded(
      contents.timeout(const Duration(seconds: 15)),
    );
    return _verify(bytes);
  }

  Future<Uint8List> _fetch(
    http.Client client,
    Uri uri, {
    required int maxBytes,
    required String accept,
  }) async {
    try {
      return await _receive(
        client,
        uri,
        maxBytes: maxBytes,
        accept: accept,
      ).timeout(const Duration(seconds: 15));
    } finally {
      client.close();
    }
  }

  Future<Uint8List> _receive(
    http.Client client,
    Uri uri, {
    required int maxBytes,
    required String accept,
  }) async {
    final request = http.Request('GET', uri)
      ..followRedirects = false
      ..headers['Accept'] = accept;
    final response = await client.send(request);
    if (response.statusCode != 200 ||
        (response.contentLength ?? 0) > maxBytes) {
      throw const FormatException('Workshop download rejected.');
    }
    return _readBounded(response.stream, maxBytes: maxBytes);
  }

  Future<List<AuthoredLearningPath>> load() async {
    final directory = await _directory();
    if (!await directory.exists()) return [];
    final paths = <AuthoredLearningPath>[];
    await for (final entity in directory.list(followLinks: false)) {
      final digest = p.basenameWithoutExtension(entity.path);
      if (entity is! File ||
          p.extension(entity.path) != '.json' ||
          !_digestPattern.hasMatch(digest)) {
        continue;
      }
      try {
        final bytes = await _readBounded(entity.openRead());
        paths.add(_verify(bytes, digest).path);
        if (paths.length == _maxInstalled) break;
      } on Exception {
        // A damaged cache entry should never hide valid downloads.
      }
    }
    paths.sort((first, second) => first.title.compareTo(second.title));
    return paths;
  }

  Future<void> install(WorkshopDownload bundle) => _serializeWrite(() async {
    final directory = await _directory();
    await directory.create(recursive: true);
    final destination = _file(directory, bundle._digest);
    final installed = await load();
    if (installed.any((path) => path.id == bundle.path.id)) return;
    if (installed.length >= _maxInstalled) {
      throw const WorkshopLibraryFull();
    }
    final temporary = await directory.createTemp('incoming-');
    try {
      final file = fileAt(p.join(temporary.path, 'bundle.json'));
      await file.writeAsBytes(bundle._bytes, flush: true);
      await file.rename(destination.path);
    } finally {
      await temporary.delete(recursive: true);
    }
  });

  Future<void> remove(AuthoredLearningPath path) => _serializeWrite(() async {
    final parts = path.id.split(':');
    if (parts.length != 3 ||
        !isDownloadedWorkshop(path) ||
        !_digestPattern.hasMatch(parts[1])) {
      throw const FormatException('Invalid downloaded workshop ID.');
    }
    final file = _file(await _directory(), parts[1]);
    if (await file.exists()) await file.delete();
  });

  Future<void> _serializeWrite(Future<void> Function() write) {
    final result = _pendingWrite.then((_) => write());
    _pendingWrite = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<Directory> _directory() async => directoryAt(
    p.join((await _supportDirectory()).path, 'nodeql_workshop_downloads'),
  );

  File _file(Directory directory, String digest) =>
      fileAt(p.join(directory.path, '$digest.json'));

  static Future<Uint8List> _readBounded(
    Stream<List<int>> stream, {
    int maxBytes = _maxBundleBytes,
  }) async {
    final buffer = BytesBuilder(copy: false);
    await for (final chunk in stream) {
      if (buffer.length + chunk.length > maxBytes) {
        throw const FormatException('Workshop bundle exceeds the size limit.');
      }
      buffer.add(chunk);
    }
    return buffer.takeBytes();
  }

  static WorkshopDownload _verify(Uint8List bytes, [String? expectedDigest]) {
    final digest = sha256.convert(bytes).toString();
    if (expectedDigest != null && digest != expectedDigest) {
      throw const FormatException('Workshop checksum does not match.');
    }
    final path = validateRemoteWorkshopBundle(utf8.decode(bytes));
    return WorkshopDownload._(
      bytes,
      digest,
      AuthoredLearningPath(
        id: '$_idPrefix$digest:${path.id}',
        title: path.title,
        description: path.description,
        steps: path.steps,
        titleTranslations: path.titleTranslations,
        descriptionTranslations: path.descriptionTranslations,
      ),
    );
  }
}

class WorkshopLibraryFull implements Exception {
  const WorkshopLibraryFull();
}

/// Strict wire format for downloads. The bundled catalog and local Studio
/// drafts still use the backwards-compatible learning path decoder.
AuthoredLearningPath validateRemoteWorkshopBundle(String source) {
  if (utf8.encode(source).length > _maxBundleBytes) {
    throw const FormatException('Workshop bundle exceeds the size limit.');
  }
  _checkJsonDepth(source);
  final bundle = _object(jsonDecode(source), const {'schemaVersion', 'paths'});
  final version = bundle['schemaVersion'];
  _require(version is int && (version == 1 || version == 2));
  final paths = _list(bundle['paths'], max: 1, min: 1);
  final path = _object(paths.single, const {
    'id',
    'title',
    'description',
    'steps',
  });
  _id(path['id']);
  _localizedText(path['title'], 160);
  _localizedText(path['description'], 1500, requiredText: false);
  final stepIds = <String>{};
  for (final raw in _list(path['steps'], max: 32, min: 1)) {
    final step = _object(raw, {
      'id',
      'title',
      'instruction',
      'hint',
      'mode',
      'nodes',
      'callouts',
      if (version == 2) ...{'highlights', 'requirements'},
    });
    _require(stepIds.add(_id(step['id'])));
    _text(step['title'], 160);
    _text(step['instruction'], 2000);
    _text(step['hint'] ?? '', 2000, requiredText: false);
    _require(const {'simple', 'advanced'}.contains(step['mode'] ?? 'simple'));
    final nodeRefs = <String>{};
    for (final raw in _list(step['nodes'] ?? [], max: 16)) {
      final node = _object(raw, const {'ref', 'type', 'defaults'});
      final ref = _id(node['ref']);
      _require(nodeRefs.add(ref));
      final inputs = _nodeInputs[node['type']];
      if (inputs == null) {
        throw const FormatException('Unsupported node in downloaded workshop.');
      }
      final defaults = _object(node['defaults'] ?? {}, inputs.keys.toSet());
      for (final entry in defaults.entries) {
        _require(inputs[entry.key]!(entry.value));
      }
    }
    _validateStepInteractions(step, nodeRefs);
    final calloutIds = <String>{};
    for (final raw in _list(step['callouts'] ?? [], max: 16)) {
      final callout = _object(raw, const {
        'id',
        'targetRef',
        'title',
        'body',
        'side',
      });
      _require(calloutIds.add(_id(callout['id'])));
      _require(nodeRefs.contains(_id(callout['targetRef'])));
      _text(callout['title'], 160);
      _text(callout['body'], 1500);
      _require(const {'left', 'right'}.contains(callout['side'] ?? 'right'));
    }
  }
  return AuthoredLearningPath.fromJson(path);
}

void _validateStepInteractions(Map<String, dynamic> step, Set<String> refs) {
  final highlights = <String>{};
  for (final raw in _list(step['highlights'] ?? [], max: 16)) {
    final ref = _id(raw);
    _require(refs.contains(ref) && highlights.add(ref));
  }
  for (final raw in _list(step['requirements'] ?? [], max: 16)) {
    final rule = _object(raw, const {
      'action',
      'nodeRef',
      'otherRef',
      'input',
      'value',
    });
    final action = LearningPathAction.values
        .where((action) => action.name == rule['action'])
        .firstOrNull;
    if (action == null)
      throw const FormatException('Unsupported workshop action.');
    _require(
      action.needsNode
          ? refs.contains(_id(rule['nodeRef']))
          : !rule.containsKey('nodeRef'),
    );
    _require(
      action.needsOtherNode
          ? refs.contains(_id(rule['otherRef'])) &&
                rule['nodeRef'] != rule['otherRef']
          : !rule.containsKey('otherRef'),
    );
    final input = rule['input'];
    _require(
      action.needsInput
          ? input is String &&
                RegExp(r'^[A-Za-z][A-Za-z0-9_]{0,63}$').hasMatch(input)
          : !rule.containsKey('input'),
    );
    if (rule.containsKey('value')) {
      _require(action == LearningPathAction.enterInput);
      _text(rule['value'], 512);
    }
  }
}

// Bound nesting before the JSON decoder constructs any collections.
void _checkJsonDepth(String source) {
  var depth = 0;
  var inString = false;
  var escaped = false;
  for (final char in source.codeUnits) {
    if (inString) {
      if (!escaped && char == 0x22) inString = false;
      escaped = !escaped && char == 0x5c;
    } else if (char == 0x22) {
      inString = true;
    } else if (char == 0x7b || char == 0x5b) {
      _require(++depth <= 10);
    } else if (char == 0x7d || char == 0x5d) {
      _require(--depth >= 0);
    }
  }
}

Map<String, dynamic> _object(Object? value, Set<String> keys) {
  if (value is Map<String, dynamic> && value.keys.every(keys.contains)) {
    return value;
  }
  throw const FormatException('Invalid workshop fields.');
}

List<Object?> _list(Object? value, {required int max, int min = 0}) {
  if (value is List && value.length >= min && value.length <= max) return value;
  throw const FormatException('Invalid workshop list.');
}

String _id(Object? value) {
  if (value is String && _idPattern.hasMatch(value)) return value;
  throw const FormatException('Invalid workshop identifier.');
}

final _controlCharacters = RegExp(
  r'[\x00-\x08\x0b-\x1f\x7f\u202a-\u202e\u2066-\u2069]',
);
bool _safeText(Object? value, int max) =>
    value is String &&
    value.length <= max &&
    !_controlCharacters.hasMatch(value);

void _text(Object? value, int max, {bool requiredText = true}) {
  _require(
    _safeText(value, max) &&
        (!requiredText || (value as String).trim().isNotEmpty),
  );
}

void _localizedText(Object? value, int max, {bool requiredText = true}) {
  if (value is Map<String, dynamic>) {
    _require(value.isNotEmpty && value.length <= 20);
    for (final entry in value.entries) {
      _require(
        RegExp(r'^[a-z]{2,3}(-[a-zA-Z0-9]{2,8}){0,2}$').hasMatch(entry.key),
      );
      _text(entry.value, max, requiredText: requiredText);
    }
  } else {
    _text(value, max, requiredText: requiredText);
  }
}

void _require(bool condition) {
  if (!condition) throw const FormatException('Invalid workshop schema.');
}

typedef _InputCheck = bool Function(Object?);

final _columnPattern = RegExp(
  r'^(?:[A-Za-z_][A-Za-z0-9_]*\.)?(?:[A-Za-z_][A-Za-z0-9_]*|\*)$',
);
bool _column(Object? value) =>
    _safeText(value, 100) && _columnPattern.hasMatch(value as String);
bool _columns(Object? value) =>
    _safeText(value, 512) &&
    (value as String).split(',').every((column) => _column(column.trim()));
bool _table(Object? value) => const {
  'customers',
  'orders',
  'archived_customers',
  'table_name',
  '',
}.contains(value);
bool _bool(Object? value) => value is bool;
bool _literal(Object? value) => _safeText(value, 512);
bool _integer(Object? value) =>
    value is String && RegExp(r'^\d{0,4}$').hasMatch(value);
bool _comparison(Object? value) => const {
  '=',
  '!=',
  '<>',
  '<',
  '<=',
  '>',
  '>=',
  'LIKE',
  'NOT LIKE',
  'IS NULL',
  'IS NOT NULL',
}.contains(value);
bool _direction(Object? value) => const {'ASC', 'DESC'}.contains(value);
bool _selectMode(Object? value) => const {'ALL', 'DISTINCT'}.contains(value);
bool _alias(Object? value) =>
    _safeText(value, 64) &&
    RegExp(r'^(?:[A-Za-z_][A-Za-z0-9_]*)?$').hasMatch(value as String);
bool _joinMode(Object? value) => const {
  'INNER',
  'LEFT',
  'RIGHT',
  'FULL',
  'CROSS',
  'NATURAL',
  'SELF',
}.contains(value);
bool _joinCondition(Object? value) {
  if (value == '1 = 1') return true;
  if (!_safeText(value, 220)) return false;
  final parts = (value as String).trim().split(RegExp(r' +'));
  return parts.length == 3 &&
      _column(parts[0]) &&
      _comparison(parts[1]) &&
      _column(parts[2]);
}

bool _sortExpression(Object? value) =>
    _safeText(value, 108) &&
    RegExp(
      r'^(?:[A-Za-z_][A-Za-z0-9_]*\.)?[A-Za-z_][A-Za-z0-9_]*(?: (?:ASC|DESC))?$',
    ).hasMatch(value as String);
bool _literalType(Object? value) =>
    const {'text', 'integer', 'real', 'null', 'blob'}.contains(value);
bool _filterValue(Object? value) =>
    _safeText(value, 512) &&
    RegExp(
      r"^(?:-?\d{1,12}(?:\.\d{1,12})?|'(?:[^']|'')*'|NULL)?$",
    ).hasMatch(value as String);

const _filterInputs = <String, _InputCheck>{
  'column': _column,
  'operator': _comparison,
  'value': _filterValue,
};
const _aggregateInputs = <String, _InputCheck>{
  'column': _column,
  'expr': _column,
};
const _tableInputs = <String, _InputCheck>{
  'table': _table,
  'table_alias': _alias,
};
const _joinInputs = <String, _InputCheck>{
  ..._tableInputs,
  'join_type': _joinMode,
  'left_column': _column,
  'right_column': _column,
  'operator': _comparison,
  'on': _joinCondition,
};

final _nodeInputs = <String, Map<String, _InputCheck>>{
  BlockType.eventGreenFlag.name: const {},
  BlockType.sqlSelect.name: const {
    ..._tableInputs,
    'columns': _columns,
    'separate_from': _bool,
    'distinct': _bool,
    'omit_from': _bool,
    'select_mode': _selectMode,
  },
  BlockType.sqlFrom.name: _tableInputs,
  BlockType.sqlColumn.name: const {'column': _column},
  BlockType.sqlText.name: const {
    'text': _literal,
    'literal_type': _literalType,
  },
  BlockType.sqlWhere.name: _filterInputs,
  BlockType.sqlAnd.name: _filterInputs,
  BlockType.sqlOr.name: _filterInputs,
  BlockType.sqlJoin.name: _joinInputs,
  BlockType.sqlInnerJoin.name: _joinInputs,
  BlockType.sqlLeftJoin.name: _joinInputs,
  BlockType.sqlRightJoin.name: _joinInputs,
  BlockType.sqlFullJoin.name: _joinInputs,
  BlockType.sqlCrossJoin.name: _joinInputs,
  BlockType.sqlSelfJoin.name: _joinInputs,
  BlockType.sqlNaturalJoin.name: _joinInputs,
  BlockType.sqlGroupBy.name: _aggregateInputs,
  BlockType.sqlCount.name: _aggregateInputs,
  BlockType.sqlSum.name: _aggregateInputs,
  BlockType.sqlAvg.name: _aggregateInputs,
  BlockType.sqlMin.name: _aggregateInputs,
  BlockType.sqlMax.name: _aggregateInputs,
  BlockType.sqlOrderBy.name: const {
    'column': _column,
    'order': _direction,
    'expr': _sortExpression,
  },
  BlockType.sqlLimit.name: const {'count': _integer, 'offset': _integer},
};
