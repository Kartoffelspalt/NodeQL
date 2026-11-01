import 'package:sqlite3/wasm.dart';
import 'package:flutter/services.dart';

import 'session_sqlite_file_system.dart';
import 'storage_web.dart';

late final WasmSqlite3 sqlite3;
Future<void>? _initialization;

Future<void> initializeSqlite() => _initialization ??= _initialize();

Future<void> _initialize() async {
  final module = await rootBundle.load('assets/sqlite/sqlite3.wasm');
  sqlite3 = await WasmSqlite3.load(
    module.buffer.asUint8List(module.offsetInBytes, module.lengthInBytes),
  );
  sqlite3.registerVirtualFileSystem(
    SessionSqliteFileSystem(sessionFileSystem),
    makeDefault: true,
  );
}
