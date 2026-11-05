use crate::database::{Cell, QueryResult};

pub fn csv(result: &QueryResult) -> String {
    fn escape(value: &str) -> String {
        if value.contains([',', '"', '\r', '\n']) { format!("\"{}\"", value.replace('"', "\"\"")) }
        else { value.into() }
    }
    let mut output = result.columns.iter().map(|value| escape(value)).collect::<Vec<_>>().join(",");
    output.push_str("\r\n");
    for row in &result.rows {
        output.push_str(&row.iter().map(|cell| match cell {
            Cell::Null => String::new(),
            _ => escape(&cell.to_string()),
        }).collect::<Vec<_>>().join(","));
        output.push_str("\r\n");
    }
    output
}

/// Columns + row arrays preserve duplicate SQL column names and SQL value types.
pub fn json(result: &QueryResult) -> Result<String, serde_json::Error> {
    serde_json::to_string_pretty(&serde_json::json!({
        "columns": result.columns, "rows": result.rows, "truncated": result.truncated,
    }))
}
