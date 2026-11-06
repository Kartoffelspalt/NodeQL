//! NodeQL's read-only SQLite catalog, table paging, and snapshot API.
use rusqlite::{
    Connection, OpenFlags, Statement,
    backup::NO_PROGRESS,
    hooks::{AuthAction, AuthContext, Authorization},
    types::ValueRef,
};
use serde::Serialize;
use std::{
    path::{Path, PathBuf},
    sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
    },
    time::{Duration, Instant},
};
use thiserror::Error;

pub const ROW_LIMIT: usize = 1000;
pub const TABLE_PAGE_SIZE: usize = 25;
const INSPECTION_TIMEOUT: Duration = Duration::from_secs(5);

#[derive(Debug, Error)]
pub enum Error {
    #[error("Dateifehler: {0}")]
    Io(#[from] std::io::Error),
    #[error("SQLite: {0}")]
    Sqlite(#[from] rusqlite::Error),
    #[error("SQLite-Datei: {0}")]
    Image(#[from] nodeql_sqlite_file::Error),
    #[error("Die Tabellenabfrage wurde abgebrochen.")]
    Cancelled,
    #[error("Ungültige Seitengröße. Erlaubt sind 1 bis 500 Zeilen.")]
    InvalidPageSize,
}

pub use nodeql_sqlite_file::{Encoding, Header, Image, ObjectKind, Record, SchemaEntry, Value};

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

#[derive(Debug)]
pub struct ColumnInfo {
    pub name: String,
    pub declared_type: String,
    pub required: bool,
    pub default_sql: Option<String>,
    pub primary_key: u32,
    pub hidden: u32,
}

#[derive(Debug)]
pub struct ForeignKey {
    pub column: String,
    pub target_table: String,
    pub target_column: Option<String>,
    pub on_update: String,
    pub on_delete: String,
}

#[derive(Debug)]
pub struct IndexInfo {
    pub name: String,
    pub unique: bool,
    pub partial: bool,
    pub columns: Vec<String>,
}

#[derive(Debug)]
pub struct TablePage {
    pub data: QueryResult,
    pub total: usize,
    pub page: usize,
    pub view: bool,
    pub definition: String,
    pub columns: Vec<ColumnInfo>,
    pub foreign_keys: Vec<ForeignKey>,
    pub indexes: Vec<IndexInfo>,
}

/// Owns a read-only connection and never creates or updates the source file.
pub struct Reader {
    connection: Connection,
    source: PathBuf,
}

impl Reader {
    pub fn open(path: &Path) -> Result<Self, Error> {
        Ok(Self {
            connection: open_read_only(path)?,
            source: path.to_owned(),
        })
    }

    pub fn tables(&self) -> Result<Vec<Table>, Error> {
        Ok(schema(&self.connection)?)
    }

    pub fn table(
        &mut self,
        name: &str,
        page: usize,
        page_size: usize,
        cancel: Arc<AtomicBool>,
    ) -> Result<TablePage, Error> {
        inspect(&mut self.connection, name, page, page_size, cancel)
    }

    /// Copy the complete committed SQLite snapshot, including changes in WAL.
    pub fn snapshot(&self, directory: &Path) -> Result<PathBuf, Error> {
        let stem = self
            .source
            .file_stem()
            .and_then(|name| name.to_str())
            .unwrap_or("nodeql")
            .chars()
            .take(32)
            .collect::<String>();
        std::fs::create_dir_all(directory)?;
        let temporary = tempfile::Builder::new()
            .prefix(&format!("{stem}-"))
            .suffix(".db")
            .tempfile_in(directory)?;
        self.connection
            .backup(rusqlite::MAIN_DB, temporary.path(), NO_PROGRESS)?;
        Header::read(temporary.path())?;
        let (_, path) = temporary.keep().map_err(|error| error.error)?;
        Ok(path)
    }
}

pub fn open_read_only(path: &Path) -> rusqlite::Result<Connection> {
    let connection = Connection::open_with_flags(path, OpenFlags::SQLITE_OPEN_READ_ONLY)?;
    connection.busy_timeout(Duration::from_millis(500))?;
    connection.execute_batch("PRAGMA query_only = ON; PRAGMA trusted_schema = OFF;")?;
    connection.query_row("PRAGMA main.schema_version", [], |_| Ok(()))?;
    Ok(connection)
}

pub fn schema(connection: &Connection) -> rusqlite::Result<Vec<Table>> {
    if !connection.is_autocommit() {
        return read_schema(connection);
    }
    let transaction = connection.unchecked_transaction()?;
    let tables = read_schema(&transaction)?;
    transaction.rollback()?;
    Ok(tables)
}

fn read_schema(connection: &Connection) -> rusqlite::Result<Vec<Table>> {
    let mut statement = connection.prepare(
        "SELECT name FROM main.sqlite_schema WHERE type IN ('table', 'view') AND substr(name, 1, 7) != 'sqlite_' ORDER BY name",
    )?;
    let names = statement
        .query_map([], |row| row.get::<_, String>(0))?
        .collect::<Result<Vec<_>, _>>()?;
    names
        .into_iter()
        .map(|name| {
            let mut statement = connection.prepare(&format!(
                "PRAGMA main.table_info({})",
                quote_identifier(&name)
            ))?;
            let columns = statement
                .query_map([], |row| row.get(1))?
                .collect::<Result<Vec<_>, _>>()?;
            Ok(Table { name, columns })
        })
        .collect()
}

/// Inspect one logical table or view in a single read transaction.
/// The authorizer and progress hook belong to this operation and are cleared before it returns.
pub fn inspect(
    connection: &mut Connection,
    name: &str,
    page: usize,
    page_size: usize,
    cancel: Arc<AtomicBool>,
) -> Result<TablePage, Error> {
    if !(1..=500).contains(&page_size) {
        return Err(Error::InvalidPageSize);
    }
    if cancel.load(Ordering::Relaxed) {
        return Err(Error::Cancelled);
    }
    connection.execute_batch("BEGIN DEFERRED;")?;
    let result = inspect_with_limits(connection, name, page, page_size, cancel);
    if !connection.is_autocommit() {
        connection.execute_batch("ROLLBACK;")?;
    }
    result
}

fn inspect_with_limits(
    connection: &mut Connection,
    name: &str,
    page: usize,
    page_size: usize,
    cancel: Arc<AtomicBool>,
) -> Result<TablePage, Error> {
    let started = Instant::now();
    let check_cancel = cancel.clone();
    connection.authorizer(Some(inspect_permission))?;
    let progress = connection.progress_handler(
        1000,
        Some(move || {
            check_cancel.load(Ordering::Relaxed) || started.elapsed() > INSPECTION_TIMEOUT
        }),
    );
    let result = progress.and_then(|()| inspect_table(connection, name, page, page_size, started));
    let progress = connection.progress_handler(0, None::<fn() -> bool>);
    let authorizer = connection.authorizer(None::<fn(AuthContext<'_>) -> Authorization>);
    progress?;
    authorizer?;
    if cancel.load(Ordering::Relaxed) {
        return Err(Error::Cancelled);
    }
    Ok(result?)
}

fn inspect_permission(ctx: AuthContext<'_>) -> Authorization {
    match ctx.action {
        AuthAction::Pragma {
            pragma_name: "data_version",
            pragma_value: None,
        } => Authorization::Allow,
        AuthAction::Read { .. } | AuthAction::Select | AuthAction::Recursive => {
            Authorization::Allow
        }
        AuthAction::Function { function_name }
            if !function_name.eq_ignore_ascii_case("load_extension") =>
        {
            Authorization::Allow
        }
        AuthAction::Pragma {
            pragma_name:
                "table_xinfo" | "table_list" | "foreign_key_list" | "index_list" | "index_info",
            ..
        } => Authorization::Allow,
        _ => Authorization::Deny,
    }
}

fn inspect_table(
    connection: &Connection,
    name: &str,
    page: usize,
    page_size: usize,
    started: Instant,
) -> rusqlite::Result<TablePage> {
    let (name, kind, definition): (String, String, Option<String>) = connection.query_row(
        "SELECT name, type, sql FROM main.sqlite_schema WHERE name = ?1 COLLATE NOCASE AND type IN ('table', 'view') AND substr(name, 1, 7) != 'sqlite_'",
        [name], |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
    )?;
    let identifier = quote_identifier(&name);
    let mut statement = connection.prepare(&format!("PRAGMA main.table_xinfo({identifier})"))?;
    let columns = statement
        .query_map([], |row| {
            Ok(ColumnInfo {
                name: row.get(1)?,
                declared_type: row.get::<_, Option<String>>(2)?.unwrap_or_default(),
                required: row.get(3)?,
                default_sql: row.get(4)?,
                primary_key: row.get(5)?,
                hidden: row.get(6)?,
            })
        })?
        .collect::<Result<Vec<_>, _>>()?;
    let mut statement =
        connection.prepare(&format!("PRAGMA main.foreign_key_list({identifier})"))?;
    let foreign_keys = statement
        .query_map([], |row| {
            Ok(ForeignKey {
                target_table: row.get(2)?,
                column: row.get(3)?,
                target_column: row.get(4)?,
                on_update: row.get(5)?,
                on_delete: row.get(6)?,
            })
        })?
        .collect::<Result<Vec<_>, _>>()?;
    let mut statement = connection.prepare(&format!("PRAGMA main.index_list({identifier})"))?;
    let indexes = statement
        .query_map([], |row| {
            Ok(IndexInfo {
                name: row.get(1)?,
                unique: row.get(2)?,
                partial: row.get(4)?,
                columns: Vec::new(),
            })
        })?
        .map(|result| {
            let mut index = result?;
            let mut statement = connection.prepare(&format!(
                "PRAGMA main.index_info({})",
                quote_identifier(&index.name)
            ))?;
            index.columns = statement
                .query_map([], |row| {
                    Ok(row.get::<_, Option<String>>(2)?.unwrap_or_default())
                })?
                .collect::<Result<Vec<_>, _>>()?;
            Ok::<_, rusqlite::Error>(index)
        })
        .collect::<Result<Vec<_>, _>>()?;
    let view = kind == "view";
    let (_, without_rowid): (String, bool) = connection.query_row(
        &format!("PRAGMA main.table_list({identifier})"),
        [],
        |row| Ok((row.get(2)?, row.get(4)?)),
    )?;
    let order = row_order(view || without_rowid, &columns);
    let total = connection.query_row(
        &format!("SELECT COUNT(*) FROM main.{identifier}"),
        [],
        |row| row.get::<_, i64>(0),
    )?;
    let total = usize::try_from(total).unwrap_or(usize::MAX);
    let page = page.min(total.div_ceil(page_size).saturating_sub(1));
    let mut statement = connection.prepare(&format!(
        "SELECT * FROM main.{identifier}{order} LIMIT {page_size} OFFSET {}",
        page * page_size
    ))?;
    let data = read_statement(&mut statement, started, false)?;
    Ok(TablePage {
        data,
        total,
        page,
        view,
        definition: definition.unwrap_or_default(),
        columns,
        foreign_keys,
        indexes,
    })
}

fn row_order(no_rowid: bool, columns: &[ColumnInfo]) -> String {
    if !no_rowid
        && let Some(alias) = ["_rowid_", "rowid", "oid"].into_iter().find(|alias| {
            columns
                .iter()
                .all(|column| !column.name.eq_ignore_ascii_case(alias))
        })
    {
        return format!(" ORDER BY {alias}");
    }
    let mut key = columns
        .iter()
        .filter(|column| column.primary_key > 0)
        .collect::<Vec<_>>();
    key.sort_by_key(|column| column.primary_key);
    if key.is_empty() {
        return String::new();
    }
    format!(
        " ORDER BY {}",
        key.into_iter()
            .map(|column| quote_identifier(&column.name))
            .collect::<Vec<_>>()
            .join(", ")
    )
}

pub fn read_statement(
    statement: &mut Statement<'_>,
    started: Instant,
    drain: bool,
) -> rusqlite::Result<QueryResult> {
    let columns = statement
        .column_names()
        .map(str::to_owned)
        .collect::<Vec<_>>();
    let mut cursor = statement.query([])?;
    let mut rows = Vec::new();
    let mut truncated = false;
    while let Some(row) = cursor.next()? {
        if rows.len() == ROW_LIMIT {
            truncated = true;
            if drain {
                continue;
            }
            break;
        }
        let values = (0..columns.len())
            .map(|index| {
                Ok(match row.get_ref(index)? {
                    ValueRef::Null => Cell::Null,
                    ValueRef::Integer(value) => Cell::Integer(value),
                    ValueRef::Real(value) => Cell::Real(value),
                    ValueRef::Text(value) => {
                        Cell::Text(String::from_utf8_lossy(value).into_owned())
                    }
                    ValueRef::Blob(bytes) => Cell::Blob {
                        hex: bytes.iter().map(|byte| format!("{byte:02X}")).collect(),
                    },
                })
            })
            .collect::<Result<Vec<_>, rusqlite::Error>>()?;
        rows.push(values);
    }
    Ok(QueryResult {
        columns,
        rows,
        truncated,
        elapsed: started.elapsed(),
    })
}

pub fn quote_identifier(name: &str) -> String {
    format!("\"{}\"", name.replace('"', "\"\""))
}
