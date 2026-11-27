import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nodeql/localization/translation_controller.dart';

import 'license_repository.dart';

class NodeQlLicensePage extends ConsumerStatefulWidget {
  const NodeQlLicensePage({
    required this.applicationVersion,
    required this.applicationIcon,
    super.key,
  });

  final String applicationVersion;
  final Widget applicationIcon;

  @override
  ConsumerState<NodeQlLicensePage> createState() => _NodeQlLicensePageState();
}

class _NodeQlLicensePageState extends ConsumerState<NodeQlLicensePage> {
  late Future<Map<String, List<String>>> _licenses;

  @override
  void initState() {
    super.initState();
    _licenses = ref.read(licenseRepositoryProvider).load();
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(translationControllerProvider).catalog;
    return Scaffold(
      appBar: AppBar(title: Text(catalog.text('licenses.title'))),
      body: FutureBuilder<Map<String, List<String>>>(
        future: _licenses,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done &&
              snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(catalog.text('licenses.loadFailed')),
                    const SizedBox(height: 16),
                    FilledButton(
                      key: const ValueKey('licenses-retry'),
                      onPressed: () => setState(() {
                        _licenses = ref.read(licenseRepositoryProvider).load();
                      }),
                      child: Text(catalog.text('licenses.retry')),
                    ),
                  ],
                ),
              ),
            );
          }
          final packages = snapshot.data?.entries.toList(growable: false);
          return ListView.builder(
            itemCount: (packages?.length ?? 0) + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      widget.applicationIcon,
                      const SizedBox(height: 12),
                      Text(
                        'NodeQL',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(
                        widget.applicationVersion,
                        textDirection: TextDirection.ltr,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Copyright © 2026 NodeQL contributors\nMIT License',
                        textAlign: TextAlign.center,
                      ),
                      if (packages == null) ...[
                        const SizedBox(height: 24),
                        const CircularProgressIndicator(),
                      ],
                    ],
                  ),
                );
              }
              final package = packages![index - 1];
              return ListTile(
                title: Text(package.key, textDirection: TextDirection.ltr),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (context) => Scaffold(
                      appBar: AppBar(
                        title: Text(
                          package.key,
                          textDirection: TextDirection.ltr,
                        ),
                      ),
                      body: Directionality(
                        textDirection: TextDirection.ltr,
                        child: ListView.separated(
                          padding: const EdgeInsets.all(24),
                          itemCount: package.value.length,
                          separatorBuilder: (_, _) => const Divider(height: 40),
                          itemBuilder: (_, index) =>
                              SelectableText(package.value[index]),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
