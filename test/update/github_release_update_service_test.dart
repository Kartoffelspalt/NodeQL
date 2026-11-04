import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nodeql/core/update/github_release_update_service.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  group('VersionNumber', () {
    test('compares release tags without build metadata', () {
      expect(
        VersionNumber.parse(
          'v0.1.32',
        )!.compareTo(VersionNumber.parse('0.1.31+31')!),
        isPositive,
      );
      expect(
        VersionNumber.parse('1.2')!.compareTo(VersionNumber.parse('1.2.0')!),
        0,
      );
    });

    test('treats stable versions as newer than matching prereleases', () {
      expect(
        VersionNumber.parse(
          '1.0.0',
        )!.compareTo(VersionNumber.parse('1.0.0-beta.1')!),
        isPositive,
      );
    });
  });

  group('bestAssetForPlatform', () {
    test('selects the current platform installer over archives', () {
      final asset = bestAssetForPlatform([
        {
          'name': 'nodeql-linux-x64.tar.gz',
          'browser_download_url': 'https://example.com/linux.tar.gz',
        },
        {
          'name': 'nodeql-windows-x64.exe',
          'browser_download_url': 'https://example.com/windows.exe',
        },
        {
          'name': 'nodeql-windows-x64.zip',
          'browser_download_url': 'https://example.com/windows.zip',
        },
      ], ReleasePlatform.windows);

      expect(asset?['name'], 'nodeql-windows-x64.exe');
    });

    test('prefers the macOS installer over a portable disk image', () {
      final asset = bestAssetForPlatform([
        {
          'name': 'nodeql-macos-1.2.0-portable.dmg',
          'browser_download_url': 'https://example.com/nodeql-portable.dmg',
        },
        {
          'name': 'nodeql-macos-1.2.0.dmg',
          'browser_download_url': 'https://example.com/nodeql.dmg',
        },
      ], ReleasePlatform.macos);

      expect(asset?['name'], 'nodeql-macos-1.2.0.dmg');
    });

    test('ignores assets that cannot be installed on the platform', () {
      final asset = bestAssetForPlatform([
        {
          'name': 'nodeql-linux-x64.deb',
          'browser_download_url': 'https://example.com/linux.deb',
        },
      ], ReleasePlatform.macos);

      expect(asset, isNull);
    });
  });

  group('GitHubReleaseUpdateService', () {
    test('only enables installation for verified repository assets', () async {
      const name = 'nodeql-windows-x64-1.2.0-setup.exe';
      const expectedUrl =
          'https://github.com/Kartoffelspalt/NodeQL/releases/download/v1.2.0/$name';
      final digest = 'sha256:${'a' * 64}';
      for (final (url, assetDigest, expectedDigest) in [
        (expectedUrl, digest, digest),
        (expectedUrl, 'sha256:invalid', null),
        ('https://example.com/$name', digest, null),
      ]) {
        final service = GitHubReleaseUpdateService(
          platform: ReleasePlatform.windows,
          packageInfoLoader: () async => PackageInfo(
            appName: 'NodeQL',
            packageName: 'nodeql',
            version: '1.1.0',
            buildNumber: '1',
          ),
          client: MockClient(
            (_) async => http.Response(
              jsonEncode({
                'tag_name': 'v1.2.0',
                'html_url':
                    'https://github.com/Kartoffelspalt/NodeQL/releases/tag/v1.2.0',
                'assets': [
                  {
                    'name': name,
                    'browser_download_url': url,
                    'digest': assetDigest,
                  },
                ],
              }),
              200,
            ),
          ),
        );
        final update = await service.findUpdate();
        expect(update?.downloadUrl.toString(), url);
        expect(update?.installDigest, expectedDigest);
      }
    });

    test('returns update when a newer release has a platform asset', () async {
      final service = GitHubReleaseUpdateService(
        platform: ReleasePlatform.macos,
        packageInfoLoader: () async => PackageInfo(
          appName: 'NodeQL',
          packageName: 'nodeql',
          version: '0.1.31',
          buildNumber: '31',
        ),
        client: MockClient(
          (_) async => http.Response('''
{
  "tag_name": "v0.1.32",
  "name": "NodeQL 0.1.32",
  "html_url": "https://github.com/Kartoffelspalt/NodeQL/releases/tag/v0.1.32",
  "assets": [
    {
      "name": "nodeql-windows-x64.exe",
      "browser_download_url": "https://example.com/nodeql-windows-x64.exe"
    },
    {
      "name": "nodeql-macos-universal.dmg",
      "browser_download_url": "https://example.com/nodeql-macos-universal.dmg"
    }
  ]
}
''', 200),
        ),
      );

      final update = await service.findUpdate();

      expect(update?.latestVersion, '0.1.32');
      expect(update?.assetName, 'nodeql-macos-universal.dmg');
      expect(
        update?.downloadUrl.toString(),
        'https://example.com/nodeql-macos-universal.dmg',
      );
    });

    test(
      'stays silent when the latest release has no platform asset',
      () async {
        final service = GitHubReleaseUpdateService(
          platform: ReleasePlatform.windows,
          packageInfoLoader: () async => PackageInfo(
            appName: 'NodeQL',
            packageName: 'nodeql',
            version: '0.1.31',
            buildNumber: '31',
          ),
          client: MockClient(
            (_) async => http.Response('''
{
  "tag_name": "v0.1.32",
  "html_url": "https://github.com/Kartoffelspalt/NodeQL/releases/tag/v0.1.32",
  "assets": [
    {
      "name": "nodeql-linux-x64.deb",
      "browser_download_url": "https://example.com/nodeql-linux-x64.deb"
    }
  ]
}
''', 200),
          ),
        );

        expect(await service.findUpdate(), isNull);
      },
    );
  });
}
