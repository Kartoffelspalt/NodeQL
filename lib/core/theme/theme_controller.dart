import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

enum NodeQlTheme { dark, midnight, matrix }

final nodeQlThemeProvider =
    StateNotifierProvider<NodeQlThemeController, NodeQlTheme>(
      (_) => NodeQlThemeController(),
    );

class NodeQlThemeController extends StateNotifier<NodeQlTheme> {
  NodeQlThemeController() : super(NodeQlTheme.dark) {
    _restore();
  }

  Future<void> setTheme(NodeQlTheme theme) async {
    if (state == theme) return;
    state = theme;
    await _persist(theme);
  }

  Future<void> _restore() async {
    try {
      final file = await _storageFile();
      if (!await file.exists()) return;
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final name = '${decoded['theme'] ?? ''}';
      final matched = NodeQlTheme.values.where((t) => t.name == name);
      if (matched.isNotEmpty) {
        state = matched.first;
      }
    } catch (_) {}
  }

  Future<void> _persist(NodeQlTheme theme) async {
    try {
      final file = await _storageFile();
      final payload = <String, dynamic>{
        'theme': theme.name,
        'savedAt': DateTime.now().toIso8601String(),
      };
      await file.writeAsString(jsonEncode(payload), flush: true);
    } catch (_) {}
  }

  Future<File> _storageFile() async {
    final support = await getApplicationSupportDirectory();
    return File('${support.path}/nodeql_theme.json');
  }
}

ThemeData themeFor(NodeQlTheme theme) {
  switch (theme) {
    case NodeQlTheme.dark:
      return ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0B1220),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF3B82F6),
          secondary: Color(0xFF22D3EE),
          surface: Color(0xFF0F172A),
          onSurface: Color(0xFFF8FAFC),
        ),
      ).copyWith(
        textTheme: ThemeData.dark().textTheme.apply(
          bodyColor: const Color(0xFFF8FAFC),
          displayColor: const Color(0xFFF8FAFC),
        ),
      );
    case NodeQlTheme.midnight:
      return ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF05121E),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF22D3EE),
          secondary: Color(0xFF38BDF8),
          surface: Color(0xFF0A1A2A),
          onSurface: Color(0xFFF0F9FF),
        ),
      );
    case NodeQlTheme.matrix:
      return ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF040B05),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF22C55E),
          secondary: Color(0xFF16A34A),
          surface: Color(0xFF07130A),
          onSurface: Color(0xFFD1FAE5),
        ),
      );
  }
}
