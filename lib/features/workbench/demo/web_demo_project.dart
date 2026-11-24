import 'package:nodeql/core/platform/sqlite.dart';
import 'package:nodeql/core/platform/storage.dart';
import 'package:path/path.dart' as p;

/// The same example shown in the website's browser preview.
const webDemoQuery = '''
SELECT students.name, students.city, scores.score
FROM students
INNER JOIN scores ON students.id = scores.student_id
WHERE scores.subject = 'Math'
ORDER BY scores.score DESC
LIMIT 3;
''';

/// Creates a session database without replacing an existing demo database.
String createWebDemoDatabase({required String directoryPath}) {
  final directory = directoryAt(directoryPath)..createSync(recursive: true);
  final databasePath = p.join(directory.path, 'nodeql_demo.db');
  if (fileAt(databasePath).existsSync()) return databasePath;

  final database = sqlite3.open(databasePath);
  try {
    database.execute('''
      PRAGMA foreign_keys = ON;
      BEGIN;
      CREATE TABLE students (
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        grade TEXT NOT NULL,
        city TEXT NOT NULL
      );
      CREATE TABLE scores (
        student_id INTEGER NOT NULL REFERENCES students(id),
        subject TEXT NOT NULL,
        score INTEGER NOT NULL CHECK (score BETWEEN 0 AND 100),
        PRIMARY KEY (student_id, subject)
      );
      INSERT INTO students VALUES
        (1, 'Alice', 'A', 'Berlin'),
        (2, 'Ben', 'A', 'Chemnitz'),
        (3, 'Clara', 'A', 'Leipzig'),
        (4, 'Dan', 'B', 'Dresden'),
        (5, 'Eva', 'B', 'Berlin'),
        (6, 'Finn', 'C', 'Chemnitz');
      INSERT INTO scores VALUES
        (1, 'Math', 97), (1, 'Physics', 92),
        (2, 'Math', 94), (2, 'Physics', 88),
        (3, 'Math', 91), (3, 'Physics', 95),
        (4, 'Math', 78), (4, 'Physics', 74),
        (5, 'Math', 83), (5, 'Physics', 80),
        (6, 'Math', 65), (6, 'Physics', 70);
      COMMIT;
    ''');
  } catch (_) {
    database.close();
    fileAt(databasePath).deleteSync();
    rethrow;
  }
  database.close();
  return databasePath;
}
