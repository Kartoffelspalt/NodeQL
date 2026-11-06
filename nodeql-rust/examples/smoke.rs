use nodeql_rust::{
    compiler,
    database::{Cell, Database},
    model::Project,
};
use std::sync::{Arc, atomic::AtomicBool};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let mut database = Database::demo()?;
    let project = Project::default();
    let sql = compiler::compile(&project.blocks).map_err(|errors| format!("{errors:?}"))?;
    let result = database.query(&sql, Arc::new(AtomicBool::new(false)))?;
    assert_eq!(result.rows.len(), 6);
    assert_eq!(result.rows[0][0], Cell::Text("Anna Weber".into()));
    println!(
        "{sql}\n\n{} rows · {} tables · Rust/SQLite OK",
        result.rows.len(),
        database.schema()?.len()
    );
    Ok(())
}
