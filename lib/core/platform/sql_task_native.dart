import 'dart:async';
import 'dart:isolate';

Future<T> runSqlTask<T>(FutureOr<T> Function() task) => Isolate.run(task);
