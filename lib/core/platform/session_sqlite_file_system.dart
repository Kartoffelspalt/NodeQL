import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file/file.dart';
import 'package:sqlite3/common.dart';

/// Makes SQLite see the same files as browser imports, snapshots and projects.
/// All connections run serially on the browser's event loop.
final class SessionSqliteFileSystem extends BaseVirtualFileSystem {
  SessionSqliteFileSystem(this.fileSystem) : super(name: 'nodeql-session');

  final FileSystem fileSystem;
  int _temporaryId = 0;

  @override
  int xAccess(String path, int flags) =>
      fileSystem.file(path).existsSync() ? 1 : 0;

  @override
  void xDelete(String path, int syncDir) {
    final file = fileSystem.file(path);
    if (file.existsSync()) file.deleteSync();
  }

  @override
  String xFullPathName(String path) =>
      fileSystem.path.normalize(fileSystem.path.absolute(path));

  @override
  XOpenResult xOpen(Sqlite3Filename path, int flags) {
    final file = fileSystem.file(path.path ?? '/tmp/sqlite-${_temporaryId++}');
    if (!file.existsSync()) {
      if (flags & SqlFlag.SQLITE_OPEN_CREATE == 0) {
        throw const VfsException(SqlError.SQLITE_CANTOPEN);
      }
      file.createSync(recursive: true);
    }
    return (
      outFlags: flags,
      file: _SessionFile(
        file,
        deleteOnClose: flags & SqlFlag.SQLITE_OPEN_DELETEONCLOSE != 0,
        readOnly: flags & SqlFlag.SQLITE_OPEN_READONLY != 0,
      ),
    );
  }

  @override
  void xSleep(Duration duration) {}
}

class _SessionFile extends BaseVfsFile {
  _SessionFile(
    this.file, {
    required this.deleteOnClose,
    required this.readOnly,
  });

  final File file;
  final bool deleteOnClose;
  final bool readOnly;
  int _lock = SqlFileLockingLevels.SQLITE_LOCK_NONE;

  @override
  int readInto(Uint8List buffer, int offset) {
    final bytes = file.readAsBytesSync();
    final count = math.min(buffer.length, math.max(0, bytes.length - offset));
    if (count > 0) buffer.setRange(0, count, bytes, offset);
    return count;
  }

  @override
  void xWrite(Uint8List buffer, int fileOffset) {
    if (readOnly) throw const VfsException(SqlError.SQLITE_READONLY);
    final existing = file.readAsBytesSync();
    final bytes =
        Uint8List(math.max(existing.length, fileOffset + buffer.length))
          ..setAll(0, existing)
          ..setAll(fileOffset, buffer);
    file.writeAsBytesSync(bytes);
  }

  @override
  void xTruncate(int size) {
    if (readOnly) throw const VfsException(SqlError.SQLITE_READONLY);
    final existing = file.readAsBytesSync();
    final bytes = Uint8List(size)
      ..setRange(0, math.min(size, existing.length), existing);
    file.writeAsBytesSync(bytes);
  }

  @override
  int xFileSize() => file.lengthSync();
  @override
  void xClose() {
    if (deleteOnClose && file.existsSync()) file.deleteSync();
  }

  @override
  void xSync(int flags) {}
  @override
  void xLock(int mode) => _lock = mode;
  @override
  void xUnlock(int mode) => _lock = mode;
  @override
  int xCheckReservedLock() =>
      _lock >= SqlFileLockingLevels.SQLITE_LOCK_RESERVED ? 1 : 0;
}
