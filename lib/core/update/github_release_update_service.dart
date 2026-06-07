import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

const githubReleaseOwner = 'Kartoffelspalt';
const githubReleaseRepository = 'NodeQL';

enum ReleasePlatform { android, ios, linux, macos, windows, web }

class AppUpdate {
  const AppUpdate({
    required this.currentVersion,
    required this.latestVersion,
    required this.releaseName,
    required this.releaseUrl,
    required this.downloadUrl,
    required this.assetName,
  });

  final String currentVersion;
  final String latestVersion;
  final String releaseName;
  final Uri releaseUrl;
  final Uri downloadUrl;
  final String assetName;
}

class GitHubReleaseUpdateService {
  GitHubReleaseUpdateService({
    http.Client? client,
    Future<PackageInfo> Function()? packageInfoLoader,
    ReleasePlatform? platform,
    this.owner = githubReleaseOwner,
    this.repository = githubReleaseRepository,
  }) : _client = client ?? http.Client(),
       _packageInfoLoader = packageInfoLoader ?? PackageInfo.fromPlatform,
       _platform = platform;

  final http.Client _client;
  final Future<PackageInfo> Function() _packageInfoLoader;
  final ReleasePlatform? _platform;
  final String owner;
  final String repository;

  Future<AppUpdate?> findUpdate() async {
    final platform = _platform ?? currentReleasePlatform();
    if (platform == null || platform == ReleasePlatform.web) {
      return null;
    }

    final packageInfo = await _packageInfoLoader();
    final currentVersion = VersionNumber.parse(packageInfo.version);
    if (currentVersion == null) {
      return null;
    }

    final endpoint = Uri.https(
      'api.github.com',
      '/repos/$owner/$repository/releases/latest',
    );
    final response = await _client.get(
      endpoint,
      headers: const {
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'NodeQL-Update-Checker',
      },
    );
    if (response.statusCode != 200) {
      return null;
    }

    final payload = jsonDecode(response.body);
    if (payload is! Map<String, Object?>) {
      return null;
    }

    final tagName = payload['tag_name'] as String?;
    final latestVersion = VersionNumber.parse(tagName ?? '');
    if (latestVersion == null || latestVersion.compareTo(currentVersion) <= 0) {
      return null;
    }

    final assets = payload['assets'];
    if (assets is! List) {
      return null;
    }

    final asset = bestAssetForPlatform(assets, platform);
    if (asset == null) {
      return null;
    }

    final releaseUrl = Uri.tryParse(payload['html_url'] as String? ?? '');
    final downloadUrl = Uri.tryParse(
      asset['browser_download_url'] as String? ?? '',
    );
    final assetName = asset['name'] as String?;
    if (releaseUrl == null || downloadUrl == null || assetName == null) {
      return null;
    }

    final releaseName = payload['name'] as String?;
    return AppUpdate(
      currentVersion: packageInfo.version,
      latestVersion: latestVersion.label,
      releaseName: (releaseName == null || releaseName.trim().isEmpty)
          ? tagName ?? latestVersion.label
          : releaseName,
      releaseUrl: releaseUrl,
      downloadUrl: downloadUrl,
      assetName: assetName,
    );
  }
}

ReleasePlatform? currentReleasePlatform() {
  if (kIsWeb) {
    return ReleasePlatform.web;
  }

  return switch (defaultTargetPlatform) {
    TargetPlatform.android => ReleasePlatform.android,
    TargetPlatform.iOS => ReleasePlatform.ios,
    TargetPlatform.linux => ReleasePlatform.linux,
    TargetPlatform.macOS => ReleasePlatform.macos,
    TargetPlatform.windows => ReleasePlatform.windows,
    TargetPlatform.fuchsia => null,
  };
}

Map<String, Object?>? bestAssetForPlatform(
  List<Object?> assets,
  ReleasePlatform platform,
) {
  Map<String, Object?>? bestAsset;
  var bestScore = 0;

  for (final rawAsset in assets) {
    if (rawAsset is! Map<String, Object?>) {
      continue;
    }

    final name = rawAsset['name'] as String?;
    final downloadUrl = rawAsset['browser_download_url'] as String?;
    if (name == null || downloadUrl == null) {
      continue;
    }

    final score = platformAssetScore(name, platform);
    if (score > bestScore) {
      bestScore = score;
      bestAsset = rawAsset;
    }
  }

  return bestAsset;
}

@visibleForTesting
int platformAssetScore(String name, ReleasePlatform platform) {
  final normalized = name.toLowerCase();
  final hasPlatformName = switch (platform) {
    ReleasePlatform.android => normalized.contains('android'),
    ReleasePlatform.ios => normalized.contains('ios'),
    ReleasePlatform.linux => normalized.contains('linux'),
    ReleasePlatform.macos =>
      normalized.contains('macos') ||
          normalized.contains('mac-os') ||
          normalized.contains('darwin'),
    ReleasePlatform.windows =>
      normalized.contains('windows') || normalized.contains('win64'),
    ReleasePlatform.web => normalized.contains('web'),
  };

  final installerScore = switch (platform) {
    ReleasePlatform.android => _matchesAny(normalized, const ['.apk']) ? 8 : 0,
    ReleasePlatform.ios => _matchesAny(normalized, const ['.ipa']) ? 8 : 0,
    ReleasePlatform.linux =>
      _matchesAny(normalized, const ['.appimage', '.deb', '.rpm']) ? 8 : 0,
    ReleasePlatform.macos =>
      _matchesAny(normalized, const ['.dmg', '.pkg']) ? 8 : 0,
    ReleasePlatform.windows =>
      _matchesAny(normalized, const ['.exe', '.msi', '.msix']) ? 8 : 0,
    ReleasePlatform.web => _matchesAny(normalized, const ['.zip']) ? 8 : 0,
  };

  final archiveScore =
      _matchesAny(normalized, const ['.zip', '.tar.gz', '.tgz']) ? 3 : 0;
  if (installerScore == 0 && archiveScore == 0) {
    return 0;
  }

  return installerScore + archiveScore + (hasPlatformName ? 4 : 0);
}

bool _matchesAny(String value, List<String> suffixes) {
  return suffixes.any(value.endsWith);
}

@visibleForTesting
class VersionNumber implements Comparable<VersionNumber> {
  const VersionNumber(this.parts, this.label, {this.preRelease});

  final List<int> parts;
  final String label;
  final String? preRelease;

  static VersionNumber? parse(String raw) {
    final match = RegExp(
      r'v?(\d+(?:\.\d+)*)(?:[-_]([0-9A-Za-z.-]+))?(?:\+\S+)?$',
      caseSensitive: false,
    ).firstMatch(raw.trim());
    if (match == null) {
      return null;
    }

    final parts = match
        .group(1)!
        .split('.')
        .map(int.parse)
        .toList(growable: false);
    return VersionNumber(parts, match.group(1)!, preRelease: match.group(2));
  }

  @override
  int compareTo(VersionNumber other) {
    final maxLength = parts.length > other.parts.length
        ? parts.length
        : other.parts.length;
    for (var index = 0; index < maxLength; index += 1) {
      final left = index < parts.length ? parts[index] : 0;
      final right = index < other.parts.length ? other.parts[index] : 0;
      if (left != right) {
        return left.compareTo(right);
      }
    }

    if (preRelease == null && other.preRelease != null) {
      return 1;
    }
    if (preRelease != null && other.preRelease == null) {
      return -1;
    }
    return 0;
  }
}
