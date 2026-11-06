use nodeql_sqlite_file::{Encoding, Error as ImageError, Header, Image, ObjectKind, Value};
use nodeql_sqlite_tables::{Cell, Error as TableError, Reader};
use rusqlite::{Connection, params};
use std::{
    ops::ControlFlow,
    sync::{Arc, atomic::AtomicBool},
};

fn cancellation() -> Arc<AtomicBool> {
    Arc::new(AtomicBool::new(false))
}

#[test]
fn physical_rowid_tree_reads_overflow_blobs_negative_rowids_and_utf16() {
    for (encoding, expected) in [
        ("UTF-16le", Encoding::Utf16Le),
        ("UTF-16be", Encoding::Utf16Be),
    ] {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("data.sqlite");
        let mut db = Connection::open(&path).unwrap();
        db.execute_batch(&format!(
            "PRAGMA page_size = 512; PRAGMA encoding = '{encoding}';
            PRAGMA user_version = 42; PRAGMA application_id = 171;
            CREATE TABLE notes(id INTEGER PRIMARY KEY, label TEXT, attachment BLOB, rating REAL);
            CREATE VIEW labels AS SELECT label FROM notes;"
        ))
        .unwrap();
        let blob = (0..8000)
            .map(|index| (index % 251) as u8)
            .collect::<Vec<_>>();
        let label = "Grüße 東京 🦀";
        db.execute(
            "INSERT INTO notes VALUES (?1, ?2, ?3, 3.25)",
            params![-9, label, &blob],
        )
        .unwrap();
        let tx = db.transaction().unwrap();
        tx.execute_batch(
            "WITH RECURSIVE seq(id) AS (VALUES(1) UNION ALL SELECT id + 1 FROM seq WHERE id < 550)
            INSERT INTO notes SELECT id, 'abc', X'0123', 1.25 FROM seq;",
        )
        .unwrap();
        tx.commit().unwrap();
        drop(db);

        let mut image = Image::open(&path).unwrap();
        let header = image.header();
        assert_eq!(header.page_size, 512);
        assert_eq!(header.encoding, expected);
        assert_eq!(header.user_version, 42);
        assert_eq!(header.application_id, 171);
        assert!(header.page_count > 10);
        let schema = image.schema().unwrap();
        assert!(
            schema
                .iter()
                .any(|entry| entry.name == "notes" && entry.kind == ObjectKind::Table)
        );
        assert!(matches!(
            image.visit_table("labels", |_| ControlFlow::Continue(())),
            Err(ImageError::NoStoredRecords)
        ));
        let mut rows = Vec::new();
        image
            .visit_table("NOTES", |record| {
                rows.push(record);
                ControlFlow::Continue(())
            })
            .unwrap();
        assert_eq!(rows.len(), 551);
        assert_eq!(rows[0].rowid, Some(-9));
        assert_eq!(
            rows[0].fields,
            [
                Value::Null,
                Value::Text(label.into()),
                Value::Blob(blob),
                Value::Real(3.25)
            ]
        );
        assert_eq!(rows[550].rowid, Some(550));
        image.set_max_record_bytes(1024);
        assert!(matches!(
            image.visit_table("notes", |_| ControlFlow::Continue(())),
            Err(ImageError::RecordLimit)
        ));
    }
}

#[test]
fn physical_without_rowid_reads_interior_index_records_and_large_pages() {
    let directory = tempfile::tempdir().unwrap();
    let path = directory.path().join("indexed.db");
    let db = Connection::open(&path).unwrap();
    db.execute_batch(
        "PRAGMA page_size = 65536;
        CREATE TABLE messages (content TEXT, priority INTEGER, position INTEGER,
            PRIMARY KEY (priority DESC, position)) WITHOUT ROWID;
        WITH RECURSIVE seq(i) AS (VALUES(1) UNION ALL SELECT i + 1 FROM seq WHERE i < 3500)
        INSERT INTO messages SELECT printf('%060d', i), i % 13, i FROM seq;",
    )
    .unwrap();
    let expected = db
        .prepare(
            "SELECT priority, position, content FROM messages ORDER BY priority DESC, position",
        )
        .unwrap()
        .query_map([], |row| {
            Ok(vec![
                Value::Integer(row.get(0)?),
                Value::Integer(row.get(1)?),
                Value::Text(row.get(2)?),
            ])
        })
        .unwrap()
        .collect::<Result<Vec<_>, _>>()
        .unwrap();
    drop(db);
    let mut image = Image::open(&path).unwrap();
    assert_eq!(image.header().page_size, 65536);
    let mut fields = Vec::new();
    image
        .visit_table("messages", |row| {
            assert_eq!(row.rowid, None);
            fields.push(row.fields);
            ControlFlow::Continue(())
        })
        .unwrap();
    assert_eq!(fields, expected);
}

#[test]
fn live_reader_uses_committed_wal_and_pages_with_real_schema_metadata() {
    let directory = tempfile::tempdir().unwrap();
    let path = directory.path().join("live.db");
    let mut writer = Connection::open(&path).unwrap();
    writer.execute_batch("PRAGMA journal_mode = WAL; PRAGMA wal_autocheckpoint = 0; PRAGMA foreign_keys = ON;
        CREATE TABLE parents (id INTEGER PRIMARY KEY); INSERT INTO parents VALUES (1);
        CREATE TABLE \"table\"\"name\" (id INTEGER PRIMARY KEY, parent INTEGER NOT NULL REFERENCES parents(id), label TEXT DEFAULT 'empty');
        CREATE INDEX label_index ON \"table\"\"name\"(label) WHERE label IS NOT NULL;
        CREATE VIEW visible AS SELECT id, label FROM \"table\"\"name\" WHERE id <= 3;
        WITH RECURSIVE seq(i) AS (VALUES(1) UNION ALL SELECT i + 1 FROM seq WHERE i < 1275)
        INSERT INTO \"table\"\"name\"(id, parent) SELECT i, 1 FROM seq;").unwrap();
    let pending = writer.transaction().unwrap();
    pending
        .execute(
            "INSERT INTO \"table\"\"name\"(id, parent) VALUES (2000, 1)",
            [],
        )
        .unwrap();
    assert!(matches!(Image::open(&path), Err(ImageError::Unstable)));

    let mut reader = Reader::open(&path).unwrap();
    assert!(
        reader
            .tables()
            .unwrap()
            .iter()
            .any(|table| table.name == "table\"name")
    );
    let page = reader.table("TABLE\"NAME", 50, 25, cancellation()).unwrap();
    assert_eq!(page.total, 1275);
    assert_eq!(page.page, 50);
    assert_eq!(page.data.rows[0][0], Cell::Integer(1251));
    assert_eq!(page.columns[0].primary_key, 1);
    assert!(page.columns[1].required);
    assert_eq!(page.columns[2].default_sql.as_deref(), Some("'empty'"));
    assert_eq!(page.foreign_keys[0].target_table, "parents");
    assert!(page.indexes[0].partial);
    assert_eq!(page.indexes[0].columns, ["label"]);
    let view = reader.table("visible", 1000, 2, cancellation()).unwrap();
    assert!(view.view);
    assert_eq!(view.total, 3);
    assert_eq!(view.page, 1);
    assert_eq!(view.data.rows.len(), 1);
    assert!(matches!(
        reader.table("visible", 0, 0, cancellation()),
        Err(TableError::InvalidPageSize)
    ));
    assert!(matches!(
        reader.table("visible", 0, 5, Arc::new(AtomicBool::new(true))),
        Err(TableError::Cancelled)
    ));

    let copy = reader
        .snapshot(&directory.path().join("snapshots"))
        .unwrap();
    let mut image = Image::open(&copy).unwrap();
    let mut last_row = None;
    image
        .visit_table("table\"name", |record| {
            last_row = record.rowid;
            ControlFlow::Continue(())
        })
        .unwrap();
    assert_eq!(last_row, Some(1275));
    drop(pending);
}

#[test]
fn image_validation_rejects_invalid_headers_and_cell_offsets() {
    let directory = tempfile::tempdir().unwrap();
    let path = directory.path().join("damaged.db");
    let db = Connection::open(&path).unwrap();
    db.execute_batch("CREATE TABLE t(id); INSERT INTO t VALUES (1);")
        .unwrap();
    drop(db);
    let mut bytes = std::fs::read(&path).unwrap();
    bytes[108..110].copy_from_slice(&0_u16.to_be_bytes());
    std::fs::write(&path, &bytes).unwrap();
    let mut image = Image::open(&path).unwrap();
    assert!(matches!(
        image.schema(),
        Err(ImageError::Invalid("invalid cell pointer"))
    ));
    std::fs::write(&path, b"not a sqlite database").unwrap();
    assert!(Header::read(&path).is_err());
    assert!(Reader::open(&path).is_err());
    assert!(image.schema().is_err());
    assert!(Reader::open(&directory.path().join("missing.db")).is_err());
    assert!(!directory.path().join("missing.db").exists());
}

#[test]
fn virtual_table_is_resolved_by_the_logical_reader() {
    let directory = tempfile::tempdir().unwrap();
    let path = directory.path().join("virtual.db");
    let db = Connection::open(&path).unwrap();
    db.execute_batch(
        "CREATE VIRTUAL TABLE entries USING fts5(body); INSERT INTO entries VALUES ('NodeQL');",
    )
    .unwrap();
    drop(db);
    let mut image = Image::open(&path).unwrap();
    assert!(matches!(
        image.visit_table("entries", |_| ControlFlow::Continue(())),
        Err(ImageError::NoStoredRecords)
    ));
    let mut reader = Reader::open(&path).unwrap();
    let page = reader.table("entries", 0, 25, cancellation()).unwrap();
    assert_eq!(page.total, 1);
    assert_eq!(page.data.rows, [vec![Cell::Text("NodeQL".into())]]);
    assert!(page.columns.iter().any(|column| column.hidden > 0));
}
