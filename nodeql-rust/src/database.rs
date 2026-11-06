use rusqlite::{
    Connection, OpenFlags,
    fallible_iterator::FallibleIterator,
    hooks::{AuthAction, AuthContext, Authorization, TransactionOperation as Tx},
};
use std::{
    path::{Path, PathBuf},
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, Ordering},
    },
    time::{Duration, Instant},
};
use thiserror::Error;

use nodeql_sqlite_tables::{self as tables, read_statement};
pub use nodeql_sqlite_tables::{
    Cell, ColumnInfo, ForeignKey, IndexInfo, QueryResult, ROW_LIMIT, TABLE_PAGE_SIZE, Table,
    TablePage, quote_identifier,
};
pub const QUERY_TIMEOUT: Duration = Duration::from_secs(5);

#[derive(Debug, Error)]
pub enum DatabaseError {
    #[error("Dateifehler: {0}")]
    Io(#[from] std::io::Error),
    #[error("SQLite: {0}")]
    Sqlite(#[from] rusqlite::Error),
    #[error("{0}")]
    Reader(#[from] tables::Error),
    #[error("{0}")]
    Invalid(String),
}

pub struct Database {
    connection: Connection,
    isolated: bool,
}

impl Database {
    pub fn open(path: &Path) -> Result<Self, DatabaseError> {
        let connection = tables::open_read_only(path)?;
        Ok(Self {
            connection,
            isolated: true,
        })
    }

    pub fn open_workspace(path: &Path) -> Result<Self, DatabaseError> {
        let connection = Connection::open_with_flags(path, OpenFlags::SQLITE_OPEN_READ_WRITE)?;
        connection.busy_timeout(Duration::from_millis(500))?;
        connection.execute_batch("PRAGMA foreign_keys = ON; PRAGMA trusted_schema = OFF;")?;
        Ok(Self {
            connection,
            isolated: false,
        })
    }

    pub fn create(path: &Path) -> Result<(), DatabaseError> {
        let parent = path
            .parent()
            .filter(|p| !p.as_os_str().is_empty())
            .unwrap_or(Path::new("."));
        let temporary = tempfile::NamedTempFile::new_in(parent)?;
        let connection = Connection::open(temporary.path())?;
        connection.execute_batch("PRAGMA user_version = 1;")?;
        drop(connection);
        temporary
            .persist_noclobber(path)
            .map_err(|error| error.error)?;
        Ok(())
    }

    pub fn import_copy(path: &Path, directory: &Path) -> Result<PathBuf, DatabaseError> {
        let reader = tables::Reader::open(path)?;
        Ok(reader.snapshot(directory)?)
    }

    pub fn demo() -> Result<Self, DatabaseError> {
        Self::seeded(include_str!("../assets/demo.sql"))
    }

    pub fn workbench_demo() -> Result<Self, DatabaseError> {
        Self::seeded(include_str!("../assets/workbench_demo.sql"))
    }

    pub fn workshop() -> Result<Self, DatabaseError> {
        Self::seeded(include_str!("../assets/workshop.sql"))
    }

    fn seeded(sql: &str) -> Result<Self, DatabaseError> {
        let connection = Connection::open_in_memory()?;
        connection.execute_batch(sql)?;
        connection.execute_batch("PRAGMA foreign_keys = ON; PRAGMA trusted_schema = OFF;")?;
        Ok(Self {
            connection,
            isolated: true,
        })
    }

    pub fn schema(&self) -> Result<Vec<Table>, DatabaseError> {
        Ok(tables::schema(&self.connection)?)
    }

    pub fn inspect(
        &mut self,
        name: &str,
        page: usize,
        cancel: Arc<AtomicBool>,
    ) -> Result<TablePage, DatabaseError> {
        Ok(tables::inspect(
            &mut self.connection,
            name,
            page,
            TABLE_PAGE_SIZE,
            cancel,
        )?)
    }

    pub fn query(
        &mut self,
        sql: &str,
        cancel: Arc<AtomicBool>,
    ) -> Result<QueryResult, DatabaseError> {
        self.read_only(sql, cancel, true)
    }

    pub fn preview(
        &mut self,
        sql: &str,
        cancel: Arc<AtomicBool>,
    ) -> Result<QueryResult, DatabaseError> {
        self.read_only(sql, cancel, false)
    }

    fn read_only(
        &mut self,
        sql: &str,
        cancel: Arc<AtomicBool>,
        single: bool,
    ) -> Result<QueryResult, DatabaseError> {
        self.with_execution_limits(cancel, preview_permission, |connection, started| {
            let mut batch = rusqlite::Batch::new(connection, sql);
            let mut result = None;
            while let Some(mut statement) = batch.next()? {
                if single && result.is_some() {
                    return Err(DatabaseError::Invalid(
                        "Bitte genau eine SELECT-Abfrage ausführen.".into(),
                    ));
                }
                if !statement.readonly() || statement.column_count() == 0 {
                    return Err(DatabaseError::Invalid(
                        "Die Live-Vorschau erlaubt nur lesende Abfragen.".into(),
                    ));
                }
                result = Some(read_statement(&mut statement, started, false)?);
            }
            result.ok_or_else(empty_query)
        })
    }

    pub fn execute(
        &mut self,
        sql: &str,
        cancel: Arc<AtomicBool>,
    ) -> Result<QueryResult, DatabaseError> {
        if let Some(operation) = crate::sql_import::standalone_operation(sql) {
            let isolated = self.isolated;
            return self.with_execution_limits(
                cancel,
                move |context: AuthContext<'_>| {
                    maintenance_permission(context, operation, isolated)
                },
                |connection, started| {
                    let mut batch = rusqlite::Batch::new(connection, sql);
                    let mut statement = batch.next()?.ok_or_else(empty_query)?;
                    if batch.next()?.is_some() {
                        return Err(DatabaseError::Invalid(
                            "Bitte den Datenbankbefehl einzeln ausführen.".into(),
                        ));
                    }
                    Ok(read_statement(&mut statement, started, true)?)
                },
            );
        }
        self.connection.execute_batch("SAVEPOINT nodeql_run;")?;
        let result = self.execute_group(sql, cancel);
        let result = result.and_then(|result| {
            self.connection.execute_batch("RELEASE nodeql_run;")?;
            Ok(result)
        });
        if result.is_err() && !self.connection.is_autocommit() {
            self.connection
                .execute_batch("ROLLBACK TO nodeql_run; RELEASE nodeql_run;")?;
        }
        result
    }

    fn execute_group(
        &mut self,
        sql: &str,
        cancel: Arc<AtomicBool>,
    ) -> Result<QueryResult, DatabaseError> {
        let observed = Arc::new(Mutex::new(None));
        let control = observed.clone();
        let internal = Arc::new(AtomicBool::new(false));
        let allow_internal = internal.clone();
        self.with_execution_limits(cancel, move |ctx: AuthContext<'_>| {
            if allow_internal.load(Ordering::Relaxed) { return Authorization::Allow; }
            match ctx.action {
                AuthAction::Transaction { operation } => *control.lock().unwrap() = Some(Control::Transaction(operation)),
                AuthAction::Savepoint { operation, savepoint_name } => {
                    if savepoint_name.eq_ignore_ascii_case("nodeql_run") || savepoint_name.eq_ignore_ascii_case("nodeql_explicit") { return Authorization::Deny; }
                    *control.lock().unwrap() = Some(Control::Named(operation, savepoint_name.into()));
                }
                _ => return execution_permission(ctx),
            }
            Authorization::Allow
        }, |connection, started| {
            let mut batch = rusqlite::Batch::new(connection, sql);
            let mut result = None;
            let mut scopes: Vec<String> = Vec::new();
            loop {
                *observed.lock().unwrap() = None;
                let Some(mut statement) = batch.next()? else { break; };
                let action = observed.lock().unwrap().take();
                let next = match action {
                    Some(Control::Transaction(operation)) => {
                        let sql = match operation {
                            Tx::Begin if scopes.is_empty() => {
                                scopes.push("nodeql_explicit".into());
                                "SAVEPOINT nodeql_explicit;".into()
                            }
                            // The binding calls COMMIT an unknown operation. SQLite
                            // recognizes the complete command before we get here.
                            Tx::Unknown | Tx::Release | Tx::Rollback if !scopes.is_empty() => {
                                let outer = quote_identifier(&scopes[0]);
                                scopes.clear();
                                if operation == Tx::Rollback { format!("ROLLBACK TO {outer}; RELEASE {outer};") }
                                else { format!("RELEASE {outer};") }
                            }
                            _ => return Err(DatabaseError::Invalid("Die Transaktionsanweisung passt nicht zur laufenden Transaktion.".into())),
                        };
                        internal.store(true, Ordering::Relaxed);
                        let applied = connection.execute_batch(&sql);
                        internal.store(false, Ordering::Relaxed);
                        applied?;
                        QueryResult { columns: Vec::new(), rows: Vec::new(), truncated: false, elapsed: started.elapsed() }
                    }
                    action => {
                        let drain = !statement.readonly();
                        let next = read_statement(&mut statement, started, drain)?;
                        if let Some(Control::Named(operation, name)) = action {
                            match operation {
                                Tx::Begin => scopes.push(name),
                                Tx::Release | Tx::Rollback => {
                                    if let Some(index) = scopes.iter().rposition(|scope| scope.eq_ignore_ascii_case(&name)) {
                                        scopes.truncate(index + usize::from(operation == Tx::Rollback));
                                    }
                                }
                                _ => {}
                            }
                        }
                        next
                    }
                };
                if !next.columns.is_empty() || result.is_none() { result = Some(next); }
            }
            if !scopes.is_empty() {
                return Err(DatabaseError::Invalid("Schließe die Transaktion oder den Savepoint vor dem Ende der Ausführung.".into()));
            }
            result.ok_or_else(empty_query)
        })
    }

    fn with_execution_limits<T>(
        &mut self,
        cancel: Arc<AtomicBool>,
        permission: impl for<'a> FnMut(AuthContext<'a>) -> Authorization + Send + 'static,
        run: impl FnOnce(&Connection, Instant) -> Result<T, DatabaseError>,
    ) -> Result<T, DatabaseError> {
        let started = Instant::now();
        self.connection.authorizer(Some(permission))?;
        self.connection.progress_handler(
            1000,
            Some({
                let cancel = cancel.clone();
                move || cancel.load(Ordering::Relaxed) || started.elapsed() > QUERY_TIMEOUT
            }),
        )?;
        let result = if cancel.load(Ordering::Relaxed) {
            Err(cancelled_query())
        } else {
            run(&self.connection, started)
        };
        let progress = self.connection.progress_handler(0, None::<fn() -> bool>);
        let authorizer = self
            .connection
            .authorizer(None::<fn(AuthContext<'_>) -> Authorization>);
        progress?;
        authorizer?;
        if cancel.load(Ordering::Relaxed) {
            return Err(cancelled_query());
        }
        result
    }
}

fn empty_query() -> DatabaseError {
    DatabaseError::Invalid("Die Abfrage ist leer.".into())
}

fn cancelled_query() -> DatabaseError {
    DatabaseError::Invalid("Die Abfrage wurde abgebrochen.".into())
}

enum Control {
    Transaction(Tx),
    Named(Tx, String),
}

fn maintenance_permission(
    ctx: AuthContext<'_>,
    operation: crate::model::BlockKind,
    isolated: bool,
) -> Authorization {
    use crate::model::BlockKind as K;
    match (operation, ctx.action) {
        (K::Vacuum, AuthAction::Attach { filename: "" } | AuthAction::Transaction { .. }) => {
            Authorization::Allow
        }
        (K::Attach, AuthAction::Attach { filename })
            if !isolated && (filename == ":memory:" || Path::new(filename).is_file()) =>
        {
            Authorization::Allow
        }
        (K::Detach, AuthAction::Detach { .. }) if !isolated => Authorization::Allow,
        (K::Pragma, AuthAction::Pragma { pragma_name, .. })
            if !isolated
                && (pragma_name.eq_ignore_ascii_case("foreign_keys")
                    || pragma_name.eq_ignore_ascii_case("journal_mode")) =>
        {
            Authorization::Allow
        }
        _ => execution_permission(ctx),
    }
}

fn preview_permission(ctx: AuthContext<'_>) -> Authorization {
    match ctx.action {
        AuthAction::Select | AuthAction::Read { .. } | AuthAction::Recursive => {
            Authorization::Allow
        }
        AuthAction::Function { .. } => execution_permission(ctx),
        _ => Authorization::Deny,
    }
}

fn execution_permission(ctx: AuthContext<'_>) -> Authorization {
    match ctx.action {
        AuthAction::Transaction { .. }
        | AuthAction::Savepoint { .. }
        | AuthAction::Attach { .. }
        | AuthAction::Detach { .. } => Authorization::Deny,
        AuthAction::Function { function_name }
            if function_name.eq_ignore_ascii_case("load_extension") =>
        {
            Authorization::Deny
        }
        AuthAction::Pragma {
            pragma_name,
            pragma_value,
        } if !matches!(
            pragma_name.to_ascii_lowercase().as_str(),
            "table_info"
                | "table_xinfo"
                | "index_list"
                | "index_info"
                | "index_xinfo"
                | "foreign_key_list"
        ) && (pragma_value.is_some()
            || matches!(
                pragma_name.to_ascii_lowercase().as_str(),
                "optimize" | "incremental_vacuum" | "wal_checkpoint" | "shrink_memory"
            )) =>
        {
            Authorization::Deny
        }
        _ => Authorization::Allow,
    }
}
