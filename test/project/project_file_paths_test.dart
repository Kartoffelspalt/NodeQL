import 'package:flutter_test/flutter_test.dart';
import 'package:nodeql/data/project/project_file_paths.dart';
import 'package:path/path.dart' as p;

void main() {
  test('Windows project files store portable relative database paths', () {
    final windows = p.Context(style: p.Style.windows);
    final relative = ProjectFilePaths.relativeDatabasePath(
      r'C:\Projects\Demo\data\sample.db',
      r'C:\Projects\Demo\demo.nodeql',
      context: windows,
    );

    expect(relative, 'data/sample.db');
    expect(
      ProjectFilePaths.resolveDatabasePath(
        r'C:\Projects\Demo\data\sample.db',
        relative,
        r'C:\Projects\Demo\demo.nodeql',
        context: windows,
      ),
      r'C:\Projects\Demo\data\sample.db',
    );
  });

  test('Linux opens Windows relative paths after a project is moved', () {
    final posix = p.Context(style: p.Style.posix);
    expect(
      ProjectFilePaths.resolveDatabasePath(
        r'C:\Projects\Demo\data\sample.db',
        r'data\sample.db',
        '/home/user/Demo/demo.nodeql',
        context: posix,
      ),
      '/home/user/Demo/data/sample.db',
    );
    expect(
      ProjectFilePaths.relativeDatabasePath(
        '/home/user/elsewhere/sample.db',
        '/home/user/Demo/demo.nodeql',
        context: posix,
      ),
      isNull,
    );
  });
}
