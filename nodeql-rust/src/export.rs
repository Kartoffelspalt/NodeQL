use crate::database::{Cell, QueryResult};

#[derive(Clone, Copy)]
pub enum Format {
    Csv,
    Json,
    Tsv,
}

impl Format {
    pub const ALL: [Self; 3] = [Self::Csv, Self::Json, Self::Tsv];

    pub fn extension(self) -> &'static str {
        match self {
            Self::Csv => "csv",
            Self::Json => "json",
            Self::Tsv => "tsv",
        }
    }

    pub fn encode(self, result: &QueryResult) -> Result<String, serde_json::Error> {
        match self {
            Self::Csv => Ok(csv(result)),
            Self::Json => json(result),
            Self::Tsv => Ok(tsv(result)),
        }
    }
}

pub fn tsv(result: &QueryResult) -> String {
    let headers = result
        .columns
        .iter()
        .map(|column| tsv_escape(column))
        .collect::<Vec<_>>()
        .join("\t");
    std::iter::once(headers)
        .chain(result.rows.iter().map(|row| {
            row.iter()
                .map(|cell| match cell {
                    Cell::Null => String::new(),
                    value => tsv_escape(&value.to_string()),
                })
                .collect::<Vec<_>>()
                .join("\t")
        }))
        .collect::<Vec<_>>()
        .join("\n")
}

fn tsv_escape(text: &str) -> String {
    text.replace(['\r', '\n', '\t'], " ")
}

fn csv_escape(value: &str) -> String {
    if value.contains([',', '"', '\r', '\n']) {
        format!("\"{}\"", value.replace('"', "\"\""))
    } else {
        value.into()
    }
}

pub fn csv(result: &QueryResult) -> String {
    let mut output = result
        .columns
        .iter()
        .map(|value| csv_escape(value))
        .collect::<Vec<_>>()
        .join(",");
    output.push_str("\r\n");
    for row in &result.rows {
        output.push_str(
            &row.iter()
                .map(|cell| match cell {
                    Cell::Null => String::new(),
                    _ => csv_escape(&cell.to_string()),
                })
                .collect::<Vec<_>>()
                .join(","),
        );
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
