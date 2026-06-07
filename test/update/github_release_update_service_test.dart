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
