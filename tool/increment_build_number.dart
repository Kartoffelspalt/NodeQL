import 'dart:io';

/// Increments the numeric build suffix of a pubspec version.
String incrementBuildNumber(String pubspecContents) {
  final match = RegExp(
    r'^version:\s*([^+\s]+)\+(\d+)[ \t]*$',
    multiLine: true,
  ).firstMatch(pubspecContents);
  if (match == null) {
    throw const FormatException(
      'Expected pubspec.yaml to contain a version in the form X.Y.Z+BUILD.',
    );
  }

  final versionName = match.group(1)!;
  final buildNumber = int.parse(match.group(2)!);
  return pubspecContents.replaceRange(
    match.start,
    match.end,
    'version: $versionName+${buildNumber + 1}',
  );
}

Future<void> main(List<String> arguments) async {
  final pubspecPath = switch (arguments) {
    [] => 'pubspec.yaml',
    ['--pubspec', final path] => path,
    _ => throw ArgumentError(
      'Usage: dart tool/increment_build_number.dart '
      '[--pubspec path/to/pubspec.yaml]',
    ),
  };
  final pubspecFile = File(pubspecPath);
  final updatedContents = incrementBuildNumber(
    await pubspecFile.readAsString(),
  );
  await pubspecFile.writeAsString(updatedContents);
  stdout.writeln('Incremented build number in ${pubspecFile.path}.');
}
