import 'dart:async';

// Browser previews use the initialized SQLite instance and session file system.
// Dart isolates are unavailable on the web.
Future<T> runSqlTask<T>(FutureOr<T> Function() task) => Future<T>.sync(task);
