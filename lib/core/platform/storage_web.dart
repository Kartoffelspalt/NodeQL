import 'package:file/file.dart';
import 'package:file/memory.dart';

export 'package:file/file.dart' show Directory, File;

/// Preview data belongs to this tab and is discarded when it is reloaded.
/// SQLite and project/settings storage share this same file system.
final FileSystem sessionFileSystem = MemoryFileSystem();

File fileAt(String path) => sessionFileSystem.file(path);
Directory directoryAt(String path) => sessionFileSystem.directory(path);
Directory get temporaryDirectory =>
    directoryAt('/tmp')..createSync(recursive: true);
bool get isMacOS => false;
String? get pluginDirectoryOverride => null;

Future<Directory> getApplicationSupportDirectory() async =>
    directoryAt('/support')..createSync(recursive: true);
