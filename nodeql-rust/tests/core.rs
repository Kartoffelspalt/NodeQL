use nodeql_rust::{
    compiler,
    database::{Cell, Database, ROW_LIMIT, quote_identifier},
    export,
    model::{Block, BlockKind, Project},
    project, sql_import,
};
use std::{
    sync::{Arc, atomic::AtomicBool},
    time::Duration,
};

fn query(database: &mut Database, sql: &str) -> nodeql_rust::database::QueryResult {
    database
        .query(sql, Arc::new(AtomicBool::new(false)))
        .unwrap()
}

fn block(kind: BlockKind, input: &str) -> Block {
    Block {
        input: input.into(),
        ..Block::new(kind)
    }
}

#[test]
fn default_project_executes_against_demo() {
    let mut database = Database::demo().unwrap();
    let sql = compiler::compile(&Project::default().blocks).unwrap();
    let result = query(&mut database, &sql);
    assert_eq!(result.columns, ["name", "city", "balance"]);
    assert_eq!(result.rows.len(), 6);
    assert_eq!(
        result.rows[0],
        [
            Cell::Text("Anna Weber".into()),
            Cell::Text("Berlin".into()),
            Cell::Real(245.5)
        ]
    );
}

#[test]
fn join_filter_group_and_having_compile_and_execute() {
    let blocks = vec![
        block(BlockKind::Select, "customers.city, COUNT(*) AS order_count"),
        block(BlockKind::From, "customers"),
        Block::new(BlockKind::Join),
        block(BlockKind::Where, "total > 50"),
        Block::new(BlockKind::GroupBy),
        Block::new(BlockKind::Having),
        block(BlockKind::OrderBy, "order_count DESC"),
    ];
    let result = query(
        &mut Database::demo().unwrap(),
        &compiler::compile(&blocks).unwrap(),
    );
    assert_eq!(
        result.rows,
        [vec![Cell::Text("Berlin".into()), Cell::Integer(3)]]
    );
}

#[test]
fn sql_to_blocks_round_trips_statements_with_nested_queries_and_quoted_keywords() {
    let source = "-- SQL source\nSELECT customers.name, COUNT(orders.id) AS [FROM; group] FROM customers\n\
        LEFT OUTER JOIN orders ON orders.customer_id = customers.id\n\
        WHERE customers.id IN (SELECT id FROM customers WHERE name <> 'WHERE; FROM')\n\
        GROUP BY customers.id HAVING COUNT(orders.id) >= 1 ORDER BY customers.id LIMIT 2;\n\
        /* second */ SELECT 'a''b; c' AS word UNION ALL SELECT 'FROM' ORDER BY word;";
    let tabs = sql_import::convert(source).unwrap();
    assert_eq!(tabs.len(), 2);
    assert_eq!(tabs[0][2].kind, BlockKind::Join);
    assert!(tabs[0][2].input.starts_with("LEFT orders"));
    assert_eq!(tabs[1][1].kind, BlockKind::Union);
    let mut database = Database::demo().unwrap();
    let sql = tabs
        .iter()
        .map(|blocks| compiler::compile(blocks).unwrap())
        .collect::<Vec<_>>()
        .join("\n");
    let run = |database: &mut Database, sql| {
        database
            .preview(sql, Arc::new(AtomicBool::new(false)))
            .unwrap()
    };
    assert_eq!(
        run(&mut database, &sql).rows,
        run(&mut database, source).rows
    );
    let select = compiler::compile(&tabs[0]).unwrap();
    assert_eq!(query(&mut database, &select).rows.len(), 2);
    assert!(sql_import::convert("SELECT 1; CREATE TRIGGER unsupported;").is_err());
    assert!(sql_import::convert("SELECT 'open;").is_err());
}

#[test]
fn invalid_order_duplicates_and_missing_values_report_block_ids() {
    let blocks = vec![
        Block::new(BlockKind::From),
        block(BlockKind::Select, ""),
        Block::new(BlockKind::Select),
    ];
    let errors = compiler::compile(&blocks).unwrap_err();
    assert!(
        errors
            .iter()
            .any(|error| error.block_id == Some(blocks[0].id))
    );
    assert!(
        errors
            .iter()
            .any(|error| error.message.contains("Position"))
    );
    assert!(
        errors
            .iter()
            .any(|error| error.message.contains("Ausdruck"))
    );
    assert!(errors.iter().any(|error| error.message.contains("einmal")));
    assert!(compiler::compile(&[]).is_err());
}

#[test]
fn select_expression_needs_no_table() {
    let sql = compiler::compile(&[block(
        BlockKind::Select,
        "'hello; world' AS message, 6 * 7 AS answer",
    )])
    .unwrap();
    assert_eq!(
        query(&mut Database::demo().unwrap(), &sql).rows[0],
        [Cell::Text("hello; world".into()), Cell::Integer(42)]
    );
}

#[test]
fn missing_join_source_and_group_are_diagnostics() {
    let blocks = vec![
        Block::new(BlockKind::Select),
        Block::new(BlockKind::Join),
        Block::new(BlockKind::Having),
    ];
    assert_eq!(compiler::compile(&blocks).unwrap_err().len(), 2);
}

#[test]
fn insertion_slot_moves_preserve_identity_and_handle_both_directions() {
    let mut project = Project::default();
    let first = project.blocks[0].id;
    let last = project.blocks[3].id;
    assert!(!project.move_block(first, 1));
    assert!(project.move_block(first, 4));
    assert_eq!(project.blocks[3].id, first);
    assert!(project.move_block(last, 0));
    assert_eq!(project.blocks[0].id, last);
    assert_eq!(project.blocks.len(), 4);
}

#[test]
fn schema_lists_tables_columns_and_quotes_identifiers() {
    let schema = Database::demo().unwrap().schema().unwrap();
    assert_eq!(
        schema
            .iter()
            .map(|table| table.name.as_str())
            .collect::<Vec<_>>(),
        ["customers", "orders"]
    );
    assert_eq!(schema[0].columns, ["id", "name", "city", "balance"]);
    assert_eq!(quote_identifier("odd\"table"), "\"odd\"\"table\"");
}

#[test]
fn runtime_refuses_writes_and_multiple_statements() {
    let mut database = Database::demo().unwrap();
    for sql in [
        "DELETE FROM customers",
        "SELECT 1; DELETE FROM customers;",
        "SELECT 1; SELECT 2;",
    ] {
        assert!(
            database
                .query(sql, Arc::new(AtomicBool::new(false)))
                .is_err(),
            "{sql}"
        );
    }
    assert_eq!(
        query(&mut database, "SELECT COUNT(*) FROM customers").rows[0],
        [Cell::Integer(6)]
    );
}

#[test]
fn writable_workspace_keeps_previews_read_only_and_rolls_back_failed_scripts() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("project.db");
    Database::create(&path).unwrap();
    assert!(Database::create(&path).is_err());
    let mut database = Database::open_workspace(&path).unwrap();
    let cancel = || Arc::new(AtomicBool::new(false));
    let blocks = [
        block(
            BlockKind::CreateTable,
            "notes (id INTEGER PRIMARY KEY, body TEXT NOT NULL)",
        ),
        block(
            BlockKind::Insert,
            "notes (id, body) VALUES (1, 'hello; world')",
        ),
        block(BlockKind::Select, "body"),
        block(BlockKind::From, "notes"),
    ];
    let script = compiler::compile(&blocks).unwrap();
    assert!(database.preview(&script, cancel()).is_err());
    assert!(database.schema().unwrap().is_empty());
    let result = database.execute(&script, cancel()).unwrap();
    assert_eq!(result.rows, [vec![Cell::Text("hello; world".into())]]);

    for invalid in [
        "UPDATE notes SET body = 'lost'; INSERT INTO notes VALUES (2, NULL);",
        "DROP TABLE notes; SELECT * FROM missing;",
        "UPDATE notes SET body = 'lost'; COMMIT;",
    ] {
        assert!(database.execute(invalid, cancel()).is_err(), "{invalid}");
        assert_eq!(
            query(&mut database, "SELECT body FROM notes").rows,
            result.rows
        );
    }
    for unsafe_preview in [
        "PRAGMA query_only = OFF; INSERT INTO notes VALUES (2, 'wrong');",
        "SELECT 1; WITH x AS (SELECT 2) DELETE FROM notes RETURNING id;",
        "ATTACH DATABASE ':memory:' AS other;",
    ] {
        assert!(
            database.preview(unsafe_preview, cancel()).is_err(),
            "{unsafe_preview}"
        );
    }
    assert_eq!(
        database
            .preview("SELECT 1; SELECT 2;", cancel())
            .unwrap()
            .rows,
        [vec![Cell::Integer(2)]]
    );
    drop(database);
    assert_eq!(
        query(
            &mut Database::open(&path).unwrap(),
            "SELECT body FROM notes"
        )
        .rows,
        result.rows
    );
}

#[test]
fn sqlite_transaction_blocks_honor_commit_rollback_and_savepoints_atomically() {
    let mut database = Database::demo().unwrap();
    let cancel = || Arc::new(AtomicBool::new(false));
    let source = "BEGIN IMMEDIATE; CREATE TABLE notes(id PRIMARY KEY); INSERT INTO notes VALUES (1); \
        SAVEPOINT edit; INSERT INTO notes VALUES (2); ROLLBACK TO edit; RELEASE edit; COMMIT; \
        BEGIN; INSERT INTO notes VALUES (3); ROLLBACK; SELECT id FROM notes;";
    let tabs = sql_import::convert(source).unwrap();
    let sql = tabs
        .iter()
        .map(|blocks| compiler::compile(blocks).unwrap())
        .collect::<Vec<_>>()
        .join("\n");
    assert!(database.preview(&sql, cancel()).is_err());
    assert_eq!(
        database.execute(&sql, cancel()).unwrap().rows,
        [vec![Cell::Integer(1)]]
    );
    assert!(
        database
            .execute(
                "BEGIN; INSERT INTO notes VALUES (7); COMMIT; INSERT INTO missing VALUES (1);",
                cancel()
            )
            .is_err()
    );
    assert!(
        database
            .execute(
                "SAVEPOINT nodeql_run; DROP TABLE notes; RELEASE nodeql_run;",
                cancel()
            )
            .is_err()
    );
    assert!(
        database
            .execute("BEGIN; INSERT INTO notes VALUES (9);", cancel())
            .is_err()
    );
    assert_eq!(
        query(&mut database, "SELECT id FROM notes").rows,
        [vec![Cell::Integer(1)]]
    );
}

#[test]
fn standalone_database_tools_work_and_practice_cannot_attach_a_file() {
    let directory = tempfile::tempdir().unwrap();
    let path = directory.path().join("main.db");
    let other = directory.path().join("other.db");
    Database::create(&path).unwrap();
    Database::create(&other).unwrap();
    let mut database = Database::open_workspace(&path).unwrap();
    let cancel = || Arc::new(AtomicBool::new(false));
    database.execute("VACUUM;", cancel()).unwrap();
    let attach = format!(
        "ATTACH DATABASE '{}' AS extra;",
        other.display().to_string().replace('\'', "''")
    );
    assert!(database.preview(&attach, cancel()).is_err());
    database.execute(&attach, cancel()).unwrap();
    database
        .execute("CREATE TABLE extra.notes(id);", cancel())
        .unwrap();
    database
        .execute("DETACH DATABASE extra;", cancel())
        .unwrap();
    assert!(
        Database::demo()
            .unwrap()
            .execute(&attach, cancel())
            .is_err()
    );
    assert!(
        database
            .execute("PRAGMA writable_schema = ON;", cancel())
            .is_err()
    );
}

#[test]
fn database_working_copy_includes_committed_wal_and_protects_the_original() {
    let dir = tempfile::tempdir().unwrap();
    let source = dir.path().join("live.db");
    let connection = rusqlite::Connection::open(&source).unwrap();
    connection.execute_batch("PRAGMA journal_mode = WAL; PRAGMA wal_autocheckpoint = 0; CREATE TABLE records (value); INSERT INTO records VALUES (42);").unwrap();
    let copied = Database::import_copy(&source, &dir.path().join("copies")).unwrap();
    let mut working = Database::open_workspace(&copied).unwrap();
    assert_eq!(
        query(&mut working, "SELECT value FROM records").rows[0],
        [Cell::Integer(42)]
    );
    working
        .execute(
            "UPDATE records SET value = 99;",
            Arc::new(AtomicBool::new(false)),
        )
        .unwrap();
    assert_eq!(
        connection
            .query_row("SELECT value FROM records", [], |row| row.get::<_, i64>(0))
            .unwrap(),
        42
    );
    assert_eq!(
        query(&mut working, "SELECT value FROM records").rows[0],
        [Cell::Integer(99)]
    );
}

#[test]
fn existing_database_is_opened_read_only_and_missing_files_are_not_created() {
    let directory = tempfile::tempdir().unwrap();
    let path = directory.path().join("existing.db");
    let connection = rusqlite::Connection::open(&path).unwrap();
    connection
        .execute_batch("CREATE TABLE data (value); INSERT INTO data VALUES (42);")
        .unwrap();
    drop(connection);
    let mut database = Database::open(&path).unwrap();
    assert_eq!(
        query(&mut database, "SELECT value FROM data").rows[0],
        [Cell::Integer(42)]
    );
    assert!(
        database
            .query(
                "INSERT INTO data VALUES (1) RETURNING value",
                Arc::new(AtomicBool::new(false))
            )
            .is_err()
    );
    let missing = directory.path().join("missing.db");
    assert!(Database::open(&missing).is_err());
    assert!(!missing.exists());
}

#[test]
fn result_cap_reports_truncation_only_when_an_extra_row_exists() {
    let mut database = Database::demo().unwrap();
    let recursive = "WITH RECURSIVE n(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM n WHERE x < 1001) SELECT x FROM n";
    let result = query(&mut database, recursive);
    assert_eq!(result.rows.len(), ROW_LIMIT);
    assert!(result.truncated);
    let result = query(&mut database, &format!("{recursive} LIMIT 1000"));
    assert_eq!(result.rows.len(), ROW_LIMIT);
    assert!(!result.truncated);
}

#[test]
fn cancellation_interrupts_expensive_sql_and_connection_remains_usable() {
    let mut database = Database::demo().unwrap();
    let start = std::time::Instant::now();
    let result = database.query(
        "WITH RECURSIVE n(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM n WHERE x < 1000000000) SELECT sum(x) FROM n",
        Arc::new(AtomicBool::new(true)),
    );
    assert!(result.is_err());
    assert!(start.elapsed() < Duration::from_secs(2));
    assert_eq!(
        query(&mut database, "SELECT 42").rows[0],
        [Cell::Integer(42)]
    );
}

#[test]
fn csv_escapes_quotes_commas_newlines_and_json_preserves_duplicate_columns_and_types() {
    let mut database = Database::demo().unwrap();
    let result = query(
        &mut database,
        "SELECT 'a,b' AS same, 'he said \"hi\"' AS same, char(10) AS newline, NULL AS missing, X'01FF' AS bytes, 42 AS number",
    );
    assert_eq!(
        export::csv(&result),
        "same,same,newline,missing,bytes,number\r\n\"a,b\",\"he said \"\"hi\"\"\",\"\n\",,X'01FF',42\r\n"
    );
    let value: serde_json::Value = serde_json::from_str(&export::json(&result).unwrap()).unwrap();
    assert_eq!(value["columns"][0], value["columns"][1]);
    assert!(value["rows"][0][3].is_null());
    assert_eq!(value["rows"][0][4]["hex"], "01FF");
    assert_eq!(value["rows"][0][5], 42);
}

#[test]
fn tsv_export_preserves_column_order_and_flattens_cell_separators() {
    let mut database = Database::demo().unwrap();
    let result = query(
        &mut database,
        "SELECT 'a' || char(9) || 'b' AS first, 'c' || char(10) || 'd' AS second, NULL AS third",
    );
    assert_eq!(export::tsv(&result), "first\tsecond\tthird\na b\tc d\t");
}

#[test]
fn project_round_trip_replaces_existing_file_and_invalid_save_preserves_it() {
    let directory = tempfile::tempdir().unwrap();
    let path = directory.path().join("project.json");
    let mut project = Project::default();
    project::save(&path, &project).unwrap();
    project.name = "Gespeichert 🦀".into();
    project::save(&path, &project).unwrap();
    assert_eq!(project::load(&path).unwrap(), project);
    let original = std::fs::read(&path).unwrap();
    project.blocks[1].id = project.blocks[0].id;
    assert!(project::save(&path, &project).is_err());
    assert_eq!(std::fs::read(&path).unwrap(), original);
}

#[test]
fn project_load_rejects_incomplete_flutter_future_and_oversized_files() {
    let directory = tempfile::tempdir().unwrap();
    let path = directory.path().join("project.json");
    std::fs::write(
        &path,
        r#"{"format":"nodeql_project_v2","version":2,"workspace":{}}"#,
    )
    .unwrap();
    assert!(
        project::load(&path)
            .unwrap_err()
            .to_string()
            .contains("Flutter")
    );
    let future = Project {
        version: 999,
        ..Project::default()
    };
    std::fs::write(&path, serde_json::to_vec(&future).unwrap()).unwrap();
    assert!(project::load(&path).is_err());
    std::fs::write(&path, vec![b' '; 2 * 1024 * 1024 + 1]).unwrap();
    assert!(
        project::load(&path)
            .unwrap_err()
            .to_string()
            .contains("2 MiB")
    );
}

#[test]
fn flutter_project_import_preserves_tabs_paths_filters_and_nested_reporter_results() {
    use serde_json::json;
    let dir = tempfile::tempdir().unwrap();
    let original = dir.path().join("Demo Projekt.nodeql");
    let db_path = dir.path().join("data").join("working.db");
    std::fs::create_dir(db_path.parent().unwrap()).unwrap();
    Database::create(&db_path).unwrap();
    let mut database = Database::open_workspace(&db_path).unwrap();
    database.execute("CREATE TABLE notes (id INTEGER PRIMARY KEY, body TEXT); INSERT INTO notes VALUES (1, 'eins'), (2, 'zwei');", Arc::new(AtomicBool::new(false))).unwrap();
    let roots = json!([
        {"type":"eventGreenFlag","id":"root", "position":{"dx":120,"dy":104}, "next":{
            "type":"sqlSelect","id":"read","inputs":{
                "table":"notes","table_alias":"n", "$nodeqlReporters":{"columns":{
                    "type":"sqlAlias", "inputs":{"alias":"Titel der Notiz","$nodeqlReporters":{"value":{
                        "type":"sqlFunction", "inputs":{"function":"upper","args":["n.body"]}
                    }}}
                }}
            },"next":{"type":"sqlWhere","inputs":{
                "conditions":[{"column":"n.id","operator":">=","value":2},{"column":"n.body","operator":"LIKE","value":"'z%'"}]
            }}
        }},
        {"type":"sqlOrderBy","id":"floating","position":{"dx":420,"dy":200},"inputs":{"column":"n.id","order":"DESC"}}
    ]);
    let fixture = json!({
        "format":"nodeql_project_v2", "version":2, "workspace":{"roots":[]},
        "runtime":{"dbRelativePath":"data\\working.db","dbPath":"/older/machine.db"},
        "tabs":{"activeTabId":"second","items":[
            {"id":"first","name":"Lesen","workspace":{"roots":roots}},
            {"id":"second","name":"Schreiben","workspace":{"roots":[{"type":"eventGreenFlag","next":{"type":"sqlInsert","inputs":{"table":"notes","columns":"id, body","values":"3, 'drei'"}}}]}}
        ]}
    });
    let bytes = serde_json::to_vec(&fixture).unwrap();
    std::fs::write(&original, &bytes).unwrap();
    let (imported, converted) = project::load_with_origin(&original).unwrap();
    assert!(converted);
    assert_eq!(imported.name, "Demo Projekt");
    assert_eq!(
        imported.database.as_ref().unwrap().canonicalize().unwrap(),
        db_path.canonicalize().unwrap()
    );
    assert_eq!(imported.workspace.active, 1);
    let (reading, layout) = imported.query(0);
    assert_eq!(
        (layout.name.as_str(), layout.origin.x, layout.origin.y),
        ("Lesen", 120, 104)
    );
    assert_eq!(layout.detached[0].position.x, 420);
    let result = query(&mut database, &compiler::compile(reading).unwrap());
    assert_eq!(result.columns, ["Titel der Notiz"]);
    assert_eq!(result.rows, [vec![Cell::Text("ZWEI".into())]]);
    let sql = compiler::compile(imported.active_query().0).unwrap();
    assert!(
        database
            .preview(&sql, Arc::new(AtomicBool::new(false)))
            .is_err()
    );
    assert_eq!(
        query(&mut database, "SELECT count(*) FROM notes").rows[0],
        [Cell::Integer(2)]
    );
    let output = dir.path().join("native.nodeql-rust.json");
    project::save(&output, &imported).unwrap();
    assert_eq!(project::load(&output).unwrap(), imported);
    assert_eq!(std::fs::read(&original).unwrap(), bytes);
    let mut unsupported = fixture;
    unsupported["tabs"]["items"][1]["workspace"]["roots"][0]["next"]["type"] = json!("sqlLoop");
    std::fs::write(&original, serde_json::to_vec(&unsupported).unwrap()).unwrap();
    assert!(
        project::load(&original)
            .unwrap_err()
            .to_string()
            .contains("sqlLoop")
    );
}

#[test]
fn relative_database_paths_resolve_from_project_directory() {
    let directory = tempfile::tempdir().unwrap();
    let path = directory.path().join("project.json");
    let project = Project {
        database: Some("data.sqlite".into()),
        ..Project::default()
    };
    std::fs::write(&path, serde_json::to_vec(&project).unwrap()).unwrap();
    let loaded = project::load(&path).unwrap();
    assert_eq!(
        loaded.database.unwrap(),
        std::fs::canonicalize(directory.path())
            .unwrap()
            .join("data.sqlite")
    );
}
