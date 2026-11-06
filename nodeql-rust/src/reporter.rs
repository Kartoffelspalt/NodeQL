use crate::database::quote_identifier;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum LiteralKind {
    Null,
    Integer,
    Real,
    Text,
    Blob,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case", tag = "type")]
pub enum Reporter {
    Expression {
        sql: String,
    },
    Literal {
        kind: LiteralKind,
        value: String,
    },
    Function {
        name: String,
        arguments: Vec<Reporter>,
    },
    Alias {
        expression: Box<Reporter>,
        name: String,
    },
    InQuery {
        column: Box<Reporter>,
        query: String,
    },
    List {
        items: Vec<Reporter>,
    },
}

impl Reporter {
    pub fn expression(sql: impl Into<String>) -> Self {
        Self::Expression { sql: sql.into() }
    }

    pub fn sql(&self) -> String {
        match self {
            Self::Expression { sql } => sql.clone(),
            Self::Literal { kind, value } => match kind {
                LiteralKind::Null => "NULL".into(),
                LiteralKind::Integer => value.trim().parse::<i64>().unwrap_or_default().to_string(),
                LiteralKind::Real => format!(
                    "{:?}",
                    value
                        .trim()
                        .parse::<f64>()
                        .ok()
                        .filter(|n| n.is_finite())
                        .unwrap_or_default()
                ),
                LiteralKind::Text => format!("'{}'", value.replace('\'', "''")),
                LiteralKind::Blob => {
                    let hex: String = value.chars().filter(|ch| !ch.is_whitespace()).collect();
                    if hex.len().is_multiple_of(2)
                        && hex.bytes().all(|byte| byte.is_ascii_hexdigit())
                    {
                        format!("X'{}'", hex.to_ascii_uppercase())
                    } else {
                        "X''".into()
                    }
                }
            },
            Self::Function { name, arguments } => format!(
                "{}({})",
                name.to_ascii_uppercase(),
                arguments
                    .iter()
                    .map(Self::sql)
                    .collect::<Vec<_>>()
                    .join(", ")
            ),
            Self::Alias { expression, name } => {
                let expression = expression.sql();
                if name.trim().is_empty() {
                    expression
                } else {
                    format!("{expression} AS {}", quote_identifier(name.trim()))
                }
            }
            Self::InQuery { column, query } => format!(
                "{} IN ({})",
                column.sql(),
                query.trim().trim_end_matches(';')
            ),
            Self::List { items } => items.iter().map(Self::sql).collect::<Vec<_>>().join(", "),
        }
    }

    pub(crate) fn validate(&self, depth: usize) -> bool {
        if depth > 12 {
            return false;
        }
        match self {
            Self::Expression { sql } | Self::Literal { value: sql, .. } => sql.len() <= 16 * 1024,
            Self::Function { name, arguments } => {
                !name.is_empty()
                    && name.len() <= 80
                    && name
                        .bytes()
                        .all(|byte| byte.is_ascii_alphanumeric() || byte == b'_')
                    && !name.eq_ignore_ascii_case("load_extension")
                    && arguments.len() <= 32
                    && arguments
                        .iter()
                        .all(|argument| argument.validate(depth + 1))
            }
            Self::Alias { expression, name } => name.len() <= 256 && expression.validate(depth + 1),
            Self::InQuery { column, query } => {
                query.len() <= 16 * 1024 && column.validate(depth + 1)
            }
            Self::List { items } => {
                !items.is_empty()
                    && items.len() <= 32
                    && items.iter().all(|item| item.validate(depth + 1))
            }
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ReporterSlot {
    pub range: std::ops::Range<usize>,
    pub reporter: Reporter,
}
