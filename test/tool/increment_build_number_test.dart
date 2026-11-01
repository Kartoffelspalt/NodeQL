import 'package:flutter_test/flutter_test.dart';

import '../../tool/increment_build_number.dart';

void main() {
  group('incrementBuildNumber', () {
    test('increments the numeric build suffix', () {
      expect(
        incrementBuildNumber('name: nodeql\nversion: 0.4.5+9\n'),
        'name: nodeql\nversion: 0.4.5+10\n',
      );
    });

    test('preserves prerelease version names', () {
      expect(
        incrementBuildNumber('version: 1.0.0-beta.1+42\n'),
        'version: 1.0.0-beta.1+43\n',
      );
    });

    test('rejects a version without a numeric build suffix', () {
      expect(
        () => incrementBuildNumber('version: 1.0.0\n'),
        throwsFormatException,
      );
    });
  });
}
