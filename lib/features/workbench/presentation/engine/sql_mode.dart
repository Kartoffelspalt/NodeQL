import 'package:flutter_riverpod/flutter_riverpod.dart';

enum SqlAbstractionMode { advanced, simple }

final sqlModeProvider = StateProvider<SqlAbstractionMode>(
  (ref) => SqlAbstractionMode.advanced,
);
