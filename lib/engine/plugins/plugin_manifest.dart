import 'package:nodeql/engine/block/block_node.dart';

const pluginBlockKeyInput = r'$nodeqlPluginBlock';
const pluginVersionInput = r'$nodeqlPluginVersion';

enum PluginBlockShape { statement, value, container }

enum PluginInputType { sql, identifier, number, string }

class PluginInputDefinition {
  const PluginInputDefinition({
    required this.name,
    required this.type,
    required this.defaultValue,
  });

  final String name;
  final PluginInputType type;
  final Object? defaultValue;

  factory PluginInputDefinition.fromJson(Map<String, dynamic> json) {
    _rejectUnknownFields(json, const <String>{
      'name',
      'type',
      'default',
    }, context: 'plugin input');
    final name = _requiredId(json, 'name');
    final typeName = json['type'] as String? ?? 'sql';
    final type = PluginInputType.values.where(
      (candidate) => candidate.name == typeName,
    );
    if (type.isEmpty) {
      throw FormatException('Input "$name" has unsupported type "$typeName".');
    }
    if (!json.containsKey('default')) {
      throw FormatException('Input "$name" must define a default value.');
    }
    final definition = PluginInputDefinition(
      name: name,
      type: type.first,
      defaultValue: json['default'],
    );
    definition.format(definition.defaultValue);
    return definition;
  }

  String format(Object? value) {
    switch (type) {
      case PluginInputType.sql:
        return '${value ?? ''}';
      case PluginInputType.identifier:
        final identifier = '${value ?? ''}'.trim();
        if (!RegExp(
          r'^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*$',
        ).hasMatch(identifier)) {
          throw FormatException(
            'Value "$identifier" is not a valid SQL identifier.',
          );
        }
        return identifier;
      case PluginInputType.number:
        final number = value is num ? value : num.tryParse('${value ?? ''}');
        if (number == null) {
          throw FormatException('Value "$value" is not a number.');
        }
        return '$number';
      case PluginInputType.string:
        return "'${'${value ?? ''}'.replaceAll("'", "''")}'";
    }
  }
}

class NodeQlPluginBlock {
  NodeQlPluginBlock({
    required this.pluginId,
    required this.pluginName,
    required this.pluginVersion,
    required this.id,
    required this.shape,
    required this.labels,
    required this.descriptions,
    required this.inputs,
    required this.sqlTemplate,
    required this.colorValue,
    this.nativeBlockType,
  }) : qualifiedId = '$pluginId/$id';

  final String pluginId;
  final String pluginName;
  final String pluginVersion;
  final String id;
  final String qualifiedId;
  final PluginBlockShape shape;
  final Map<String, String> labels;
  final Map<String, String> descriptions;
  final List<PluginInputDefinition> inputs;
  final String? sqlTemplate;
  final int colorValue;
  final BlockType? nativeBlockType;

  BlockType get hostBlockType {
    if (nativeBlockType != null) return nativeBlockType!;
    return switch (shape) {
      PluginBlockShape.statement => BlockType.sqlHaving,
      PluginBlockShape.value => BlockType.sqlColumn,
      PluginBlockShape.container => BlockType.sqlLoop,
    };
  }

  Map<String, dynamic> get workspaceDefaults => <String, dynamic>{
    for (final input in inputs) input.name: input.defaultValue,
    pluginBlockKeyInput: qualifiedId,
    pluginVersionInput: pluginVersion,
  };

  String labelFor(String languageCode) =>
      _localized(labels, languageCode, qualifiedId);

  String uiTemplateFor(String languageCode) {
    final label = labelFor(languageCode);
    final referencedInputs = RegExp(
      r'[\[{]([A-Za-z_][A-Za-z0-9_-]*)[\]}]',
    ).allMatches(label).map((match) => match.group(1)!).toSet();
    final missing = inputs
        .where((input) => !referencedInputs.contains(input.name))
        .map((input) => '[${input.name}]')
        .join(' ');
    return missing.isEmpty ? label : '$label $missing';
  }

  String descriptionFor(String languageCode) =>
      _localized(descriptions, languageCode, pluginName);

  String renderSql(Map<String, dynamic> values, {required String childrenSql}) {
    final template = sqlTemplate;
    if (template == null) {
      throw StateError('Legacy plugin blocks use their native compiler.');
    }
    final inputByName = <String, PluginInputDefinition>{
      for (final input in inputs) input.name: input,
    };
    return template.replaceAllMapped(
      RegExp(r'\{\{([A-Za-z_][A-Za-z0-9_-]*)\}\}'),
      (match) {
        final name = match.group(1)!;
        if (name == 'children') return childrenSql;
        final input = inputByName[name];
        if (input == null) {
          throw FormatException(
            'SQL template references unknown input "$name".',
          );
        }
        return input.format(values[name] ?? input.defaultValue);
      },
    );
  }

  static NodeQlPluginBlock fromJson({
    required String pluginId,
    required String pluginName,
    required String pluginVersion,
    required Map<String, dynamic> json,
  }) {
    _rejectUnknownFields(json, const <String>{
      'id',
      'shape',
      'label',
      'description',
      'color',
      'inputs',
      'sql',
    }, context: 'plugin block');
    final id = _requiredId(json, 'id');
    final shapeName = json['shape'] as String? ?? 'statement';
    final shape = PluginBlockShape.values.where(
      (candidate) => candidate.name == shapeName,
    );
    if (shape.isEmpty) {
      throw FormatException('Block "$id" has unsupported shape "$shapeName".');
    }
    final labels = _localizedMap(json['label'], field: 'label');
    final descriptions = _localizedMap(
      json['description'] ?? labels,
      field: 'description',
    );
    final rawInputs = json['inputs'] as List<dynamic>? ?? const <dynamic>[];
    final inputs = rawInputs
        .map(
          (value) => PluginInputDefinition.fromJson(
            Map<String, dynamic>.from(value as Map),
          ),
        )
        .toList(growable: false);
    final names = <String>{};
    for (final input in inputs) {
      if (!names.add(input.name)) {
        throw FormatException(
          'Block "$id" defines input "${input.name}" more than once.',
        );
      }
      if (input.name == 'children' ||
          input.name == pluginBlockKeyInput ||
          input.name == pluginVersionInput) {
        throw FormatException(
          'Block "$id" uses reserved input name "${input.name}".',
        );
      }
    }
    for (final label in labels.values) {
      final labelInputs = RegExp(
        r'[\[{]([A-Za-z_][A-Za-z0-9_-]*)[\]}]',
      ).allMatches(label).map((match) => match.group(1)!).toSet();
      final unknownLabelInputs = labelInputs.difference(names);
      if (unknownLabelInputs.isNotEmpty) {
        throw FormatException(
          'Block "$id" label references unknown input(s): '
          '${unknownLabelInputs.join(', ')}.',
        );
      }
    }

    final sqlTemplate = json['sql'] as String?;
    if (sqlTemplate == null || sqlTemplate.trim().isEmpty) {
      throw FormatException(
        'Block "$id" must define a non-empty SQL template.',
      );
    }
    final placeholders = RegExp(
      r'\{\{([A-Za-z_][A-Za-z0-9_-]*)\}\}',
    ).allMatches(sqlTemplate).map((match) => match.group(1)!).toSet();
    final allowed = <String>{...names};
    if (shape.first == PluginBlockShape.container) allowed.add('children');
    final unknown = placeholders.difference(allowed);
    if (unknown.isNotEmpty) {
      throw FormatException(
        'Block "$id" references unknown SQL input(s): ${unknown.join(', ')}.',
      );
    }
    if (shape.first != PluginBlockShape.container &&
        placeholders.contains('children')) {
      throw FormatException(
        'Only container blocks may reference "{{children}}".',
      );
    }

    return NodeQlPluginBlock(
      pluginId: pluginId,
      pluginName: pluginName,
      pluginVersion: pluginVersion,
      id: id,
      shape: shape.first,
      labels: labels,
      descriptions: descriptions,
      inputs: inputs,
      sqlTemplate: sqlTemplate,
      colorValue: _parseColor(json['color'] as String?),
    );
  }

  static NodeQlPluginBlock legacy({
    required String pluginId,
    required String pluginName,
    required String pluginVersion,
    required int index,
    required BlockType nativeBlockType,
    required String? label,
    required Map<String, dynamic> defaults,
  }) {
    return NodeQlPluginBlock(
      pluginId: pluginId,
      pluginName: pluginName,
      pluginVersion: pluginVersion,
      id: 'legacy-$index-${nativeBlockType.name}',
      shape: PluginBlockShape.statement,
      labels: <String, String>{
        'en': label?.trim().isNotEmpty == true
            ? label!.trim()
            : nativeBlockType.name,
      },
      descriptions: <String, String>{'en': 'Legacy NodeQL palette extension'},
      inputs: defaults.entries
          .map(
            (entry) => PluginInputDefinition(
              name: entry.key,
              type: PluginInputType.sql,
              defaultValue: entry.value,
            ),
          )
          .toList(growable: false),
      sqlTemplate: null,
      colorValue: 0xFF8B5CF6,
      nativeBlockType: nativeBlockType,
    );
  }
}

class NodeQlPluginManifest {
  const NodeQlPluginManifest({
    required this.schemaVersion,
    required this.id,
    required this.name,
    required this.version,
    required this.minNodeQlVersion,
    required this.author,
    required this.description,
    required this.homepage,
    required this.license,
    required this.capabilities,
    required this.blocks,
  });

  final int schemaVersion;
  final String id;
  final String name;
  final String version;
  final String? minNodeQlVersion;
  final String? author;
  final Map<String, String> description;
  final String? homepage;
  final String? license;
  final Set<String> capabilities;
  final List<NodeQlPluginBlock> blocks;

  factory NodeQlPluginManifest.fromJson(Map<String, dynamic> json) {
    _rejectUnknownFields(json, const <String>{
      r'$schema',
      'schemaVersion',
      'id',
      'name',
      'version',
      'minNodeQlVersion',
      'author',
      'description',
      'homepage',
      'license',
      'capabilities',
      'blocks',
    }, context: 'plugin manifest');
    final schemaVersion = json['schemaVersion'];
    if (schemaVersion != 1) {
      throw FormatException(
        'Unsupported schemaVersion "$schemaVersion"; expected 1.',
      );
    }
    final id = _requiredPluginId(json, 'id');
    final name = _requiredString(json, 'name');
    final version = _requiredVersion(json, 'version');
    final minNodeQlVersion = json['minNodeQlVersion'] as String?;
    if (minNodeQlVersion != null) {
      _validateVersion(minNodeQlVersion, 'minNodeQlVersion');
    }
    final capabilities =
        (json['capabilities'] as List<dynamic>? ??
                const <dynamic>['sql.compile'])
            .map((value) => '$value')
            .toSet();
    final unsupported = capabilities.difference(const <String>{'sql.compile'});
    if (unsupported.isNotEmpty) {
      throw FormatException(
        'Unsupported capabilities: ${unsupported.join(', ')}.',
      );
    }
    final author = _optionalString(json, 'author');
    final description = json['description'] == null
        ? const <String, String>{}
        : _localizedMap(json['description'], field: 'description');
    final homepage = _optionalUri(json, 'homepage');
    final license = _optionalString(json, 'license');
    final rawBlocks = json['blocks'] as List<dynamic>?;
    if (rawBlocks == null || rawBlocks.isEmpty) {
      throw const FormatException('A plugin must define at least one block.');
    }
    final blocks = rawBlocks
        .map(
          (value) => NodeQlPluginBlock.fromJson(
            pluginId: id,
            pluginName: name,
            pluginVersion: version,
            json: Map<String, dynamic>.from(value as Map),
          ),
        )
        .toList(growable: false);
    final blockIds = <String>{};
    for (final block in blocks) {
      if (!blockIds.add(block.id)) {
        throw FormatException(
          'Plugin "$id" defines block "${block.id}" more than once.',
        );
      }
    }
    return NodeQlPluginManifest(
      schemaVersion: schemaVersion as int,
      id: id,
      name: name,
      version: version,
      minNodeQlVersion: minNodeQlVersion,
      author: author,
      description: description,
      homepage: homepage,
      license: license,
      capabilities: capabilities,
      blocks: blocks,
    );
  }

  String descriptionFor(String languageCode) =>
      _localized(description, languageCode, name);
}

String _localized(
  Map<String, String> values,
  String languageCode,
  String fallback,
) {
  return values[languageCode] ??
      values['en'] ??
      (values.isEmpty ? fallback : values.values.first);
}

Map<String, String> _localizedMap(Object? value, {required String field}) {
  if (value is String && value.trim().isNotEmpty) {
    return <String, String>{'en': value.trim()};
  }
  if (value is Map) {
    final result = <String, String>{};
    for (final entry in value.entries) {
      final text = '${entry.value}'.trim();
      if (text.isNotEmpty) result['${entry.key}'] = text;
    }
    if (result.isNotEmpty) return result;
  }
  throw FormatException('Field "$field" must contain localized text.');
}

String _requiredString(Map<String, dynamic> json, String field) {
  final value = json[field];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Field "$field" must be a non-empty string.');
  }
  return value.trim();
}

String? _optionalString(Map<String, dynamic> json, String field) {
  final value = json[field];
  if (value == null) return null;
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Field "$field" must be a non-empty string.');
  }
  return value.trim();
}

String? _optionalUri(Map<String, dynamic> json, String field) {
  final value = _optionalString(json, field);
  if (value == null) return null;
  final uri = Uri.tryParse(value);
  if (uri == null ||
      !uri.hasScheme ||
      (uri.scheme != 'https' && uri.scheme != 'http')) {
    throw FormatException('Field "$field" must be an HTTP(S) URL.');
  }
  return value;
}

String _requiredId(Map<String, dynamic> json, String field) {
  final value = _requiredString(json, field);
  if (!RegExp(r'^[a-z][a-z0-9-]*$').hasMatch(value)) {
    throw FormatException('Field "$field" must match [a-z][a-z0-9-]*.');
  }
  return value;
}

String _requiredPluginId(Map<String, dynamic> json, String field) {
  final value = _requiredString(json, field);
  if (!RegExp(r'^[a-z][a-z0-9]*(\.[a-z][a-z0-9-]*)+$').hasMatch(value)) {
    throw FormatException('Field "$field" must be a reverse-domain plugin ID.');
  }
  return value;
}

String _requiredVersion(Map<String, dynamic> json, String field) {
  final value = _requiredString(json, field);
  _validateVersion(value, field);
  return value;
}

void _validateVersion(String value, String field) {
  if (!RegExp(r'^\d+\.\d+\.\d+([+-][0-9A-Za-z.-]+)?$').hasMatch(value)) {
    throw FormatException('Field "$field" must be a semantic version.');
  }
}

int _parseColor(String? source) {
  if (source == null) return 0xFF8B5CF6;
  final normalized = source.replaceFirst('#', '');
  if (!RegExp(r'^[0-9A-Fa-f]{6}$').hasMatch(normalized)) {
    throw FormatException('Color "$source" must use #RRGGBB.');
  }
  return 0xFF000000 | int.parse(normalized, radix: 16);
}

void _rejectUnknownFields(
  Map<String, dynamic> json,
  Set<String> allowed, {
  required String context,
}) {
  final unknown = json.keys.toSet().difference(allowed);
  if (unknown.isNotEmpty) {
    throw FormatException(
      'Unknown field(s) in $context: ${unknown.join(', ')}.',
    );
  }
}
