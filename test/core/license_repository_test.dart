import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nodeql/core/licenses/license_repository.dart';

void main() {
  const notices =
      'beta\nalpha\n\nLicense one\n'
      '\n--------------------------------------------------------------------------------\n'
      'alpha\n\nLicense two';

  test(
    'groups notices and shares concurrent and successful cached loads',
    () async {
      var reads = 0;
      final pending = Completer<String>();
      final repository = BundledLicenseRepository(
        loadNotices: () {
          reads++;
          return pending.future;
        },
      );
      final first = repository.load();
      expect(identical(first, repository.load()), isTrue);
      pending.complete(notices);
      final packages = await first;
      expect(packages.keys, ['alpha', 'beta']);
      expect(packages['alpha'], ['License one', 'License two']);
      expect(identical(packages, await repository.load()), isTrue);
      expect(reads, 1);
      expect(() => packages['alpha']!.add('changed'), throwsUnsupportedError);
    },
  );

  test('failed and timed-out loads are not retained in the cache', () async {
    var reads = 0;
    final repository = BundledLicenseRepository(
      loadTimeout: const Duration(milliseconds: 10),
      loadNotices: () async {
        reads++;
        if (reads == 1) throw StateError('missing asset');
        if (reads == 2) return Completer<String>().future;
        return notices;
      },
    );
    await expectLater(repository.load(), throwsStateError);
    await expectLater(repository.load(), throwsA(isA<TimeoutException>()));
    expect((await repository.load())['beta'], ['License one']);
    expect(reads, 3);
  });

  test('a new build or repository starts with fresh notices', () async {
    final first = BundledLicenseRepository(loadNotices: () async => notices);
    final next = BundledLicenseRepository(
      loadNotices: () async => 'new\n\nNew license',
    );
    await first.load();
    expect((await next.load()).keys, ['new']);
  });
}
