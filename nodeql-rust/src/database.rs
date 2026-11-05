use std::{path::Path, sync::{Arc, atomic::{AtomicBool, Ordering}}, time::{Duration, Instant}};
use rusqlite::{Connection, OpenFlags, types::ValueRef};
use serde::Serialize;
use thiserror::Error;

pub const ROW_LIMIT: usize = 1000;
pub const QUERY_TIMEOUT: Duration = Duration::from_secs(5);

#[derive(Debug, Error)]
pub enum DatabaseError {
    #[error("SQLite: {0}")]
    Sqlite(#[from] rusqlite::Error),
    #[error("{0}")]
    Invalid(String),
}

#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(untagged)]
pub enum Cell {
    Null,
    Integer(i64),
    Real(f64),
    Text(String),
    Blob { hex: String },
}

impl std::fmt::Display for Cell {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Null => write!(f, "NULL"),
            Self::Integer(value) => write!(f, "{value}"),
            Self::Real(value) => write!(f, "{value}"),
            Self::Text(value) => write!(f, "{value}"),
            Self::Blob { hex } => write!(f, "X'{hex}'"),
        }
    }
}

#[derive(Debug, Clone)]
pub struct QueryResult {
    pub columns: Vec<String>,
    pub rows: Vec<Vec<Cell>>,
    pub truncated: bool,
    pub elapsed: Duration,
}

#[derive(Debug, Clone)]
pub struct Table {
    pub name: String,
    pub columns: Vec<String>,
}

pub struct Database { connection: Connection }

impl Database {
    pub fn open(path: &Path) -> Result<Self, DatabaseError> {
        // Existing user databases are deliberately read-only in this first slice.
        let connection = Connection::open_with_flags(path, OpenFlags::SQLITE_OPEN_READ_ONLY)?;
        connection.busy_timeout(Duration::from_millis(500))?;
        connection.execute_batch("PRAGMA query_only = ON;")?;
        Ok(Self { connection })
    }

    pub fn demo() -> Result<Self, DatabaseError> {
        let connection = Connection::open_in_memory()?;
        connection.execute_batch(include_str!("../assets/demo.sql"))?;
        connection.execute_batch("PRAGMA query_only = ON;")?;
        Ok(Self { connection })
    }

    pub fn schema(&self) -> Result<Vec<Table>, DatabaseError> {
        let mut statement = self.connection.prepare(
            "SELECT name FROM sqlite_schema WHERE type IN ('table', 'view') AND name NOT LIKE 'sqlite_%' ORDER BY name"
        )?;
        let names = statement.query_map([], |row| row.get::<_, String>(0))?.collect::<Result<Vec<_>, _>>()?;
        names.into_iter().map(|name| {
            let mut statement = self.connection.prepare("SELECT name FROM pragma_table_info(?1)")?;
            let columns = statement.query_map([&name], |row| row.get(0))?.collect::<Result<Vec<_>, _>>()?;
            Ok(Table { name, columns })
        }).collect()
    }

    pub fn query(&self, sql: &str, cancel: Arc<AtomicBool>) -> Result<QueryResult, DatabaseError> {
        let started = Instant::now();
        self.connection.progress_handler(1000, Some(move || {
            cancel.load(Ordering::Relaxed) || started.elapsed() > QUERY_TIMEOUT
        }));
        let result = self.query_inner(sql, started);
        self.connection.progress_handler(0, None::<fn() -> bool>);
        result
    }

    fn query_inner(&self, sql: &str, started: Instant) -> Result<QueryResult, DatabaseError> {
        let mut batch = rusqlite::Batch::new(&self.connection, sql);
        let mut statement = batch.next()?.ok_or_else(|| DatabaseError::Invalid("Die Abfrage ist leer.".into()))?;
        if batch.next()?.is_some() {
            return Err(DatabaseError::Invalid("Bitte genau eine SELECT-Abfrage ausführen.".into()));
        }
        if !statement.readonly() || statement.column_count() == 0 {
            return Err(DatabaseError::Invalid("Dieser erste Rust-Stand unterstützt nur lesende Abfragen.".into()));
        }
        let columns = statement.column_names().iter().map(|name| (*name).to_owned()).collect::<Vec<_>>();
        let mut cursor = statement.query([])?;
        let mut rows = Vec::new();
        let mut truncated = false;
        while let Some(row) = cursor.next()? {
            if rows.len() == ROW_LIMIT { truncated = true; break; }
            let values = (0..columns.len()).map(|index| Ok(match row.get_ref(index)? {
                ValueRef::Null => Cell::Null,
                ValueRef::Integer(value) => Cell::Integer(value),
                ValueRef::Real(value) => Cell::Real(value),
                ValueRef::Text(value) => Cell::Text(String::from_utf8_lossy(value).into_owned()),
                ValueRef::Blob(bytes) => Cell::Blob { hex: bytes.iter().map(|byte| format!("{byte:02X}")).collect() },
            })).collect::<Result<Vec<_>, rusqlite::Error>>()?;
            rows.push(values);
        }
        Ok(QueryResult { columns, rows, truncated, elapsed: started.elapsed() })
    }
}

pub fn quote_identifier(name: &str) -> String {
    format!("\"{}\"", name.replace('"', "\"\""))
}
