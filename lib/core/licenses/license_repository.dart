import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'license_decoder.dart';

final licenseRepositoryProvider = Provider((_) => BundledLicenseRepository());

/// The notices belong to this app build. Cache only in memory so an app update
/// cannot reuse licenses from an older executable or asset bundle.
class BundledLicenseRepository {
  BundledLicenseRepository({
    Future<String> Function()? loadNotices,
    this.loadTimeout = const Duration(seconds: 15),
  }) : _loadNotices = loadNotices ?? _readNotices;

  final Future<String> Function() _loadNotices;
  final Duration loadTimeout;
  Future<Map<String, List<String>>>? _cached;

  Future<Map<String, List<String>>> load() =>
      _cached ??= _load().catchError((Object error, StackTrace stack) {
        // Both concurrent callers and reopened views reuse successful loads.
        // Failures and timeouts must remain retryable.
        _cached = null;
        Error.throwWithStackTrace(error, stack);
      });

  Future<Map<String, List<String>>> _load() async {
    final notices = await _loadNotices().timeout(loadTimeout);
    final packages = <String, List<String>>{};
    for (final entry in notices.split('\n${'-' * 80}\n')) {
      final split = entry.indexOf('\n\n');
      if (split < 0) throw const FormatException('Invalid license notices.');
      final names = entry.substring(0, split).split('\n');
      final text = entry.substring(split + 2).trim();
      if (text.isEmpty) throw const FormatException('Empty license notice.');
      for (final name in names) {
        if (name.trim().isEmpty) continue;
        (packages[name.trim()] ??= []).add(text);
      }
    }
    if (packages.isEmpty) throw const FormatException('No license notices.');
    final names = packages.keys.toList()..sort();
    return Map.unmodifiable({
      for (final name in names)
        name: List<String>.unmodifiable(packages[name]!),
    });
  }

  static Future<String> _readNotices() async {
    // Read the generated bundle directly. Flutter's LicenseRegistry collector
    // can leave its stream open if its asynchronous asset loader throws.
    final bytes = await rootBundle.load(kIsWeb ? 'NOTICES' : 'NOTICES.Z');
    return compute(
      decodeBundledLicenses,
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      debugLabel: 'nodeqlLicenses',
    );
  }
}
