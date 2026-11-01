import 'dart:io';

export 'dart:io' show Directory, File;
export 'package:path_provider/path_provider.dart'
    show getApplicationSupportDirectory;

File fileAt(String path) => File(path);
Directory directoryAt(String path) => Directory(path);
Directory get temporaryDirectory => Directory.systemTemp;
bool get isMacOS => Platform.isMacOS;
String? get pluginDirectoryOverride =>
    Platform.environment['NODEQL_PLUGIN_DIR'];
