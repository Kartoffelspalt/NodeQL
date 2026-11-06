//! Convert Flutter project envelopes into native blocks without changing the source file.
use crate::{
    database::quote_identifier,
    model::{
        Block, BlockKind as K, CanvasPoint, CanvasView, DetachedBlock, MAX_BLOCKS, MAX_TABS,
        Project, QueryChain, QueryLayout, QueryTab, Workspace,
    },
    project::ProjectError,
    reporter::{LiteralKind, Reporter},
};
use serde_json::Value;
use std::{collections::HashSet, path::Path};

const REPORTERS: &str = "$nodeqlReporters";

fn invalid(message: impl std::fmt::Display) -> ProjectError {
    ProjectError::Invalid(format!("Flutter-Projekt: {message}"))
}

pub fn convert(source: &Value, path: &Path) -> Result<Project, ProjectError> {
    let legacy = source.get("format").is_none();
    if !legacy && source["version"].as_u64() != Some(2) {
        return Err(invalid("Diese Version wird nicht unterstützt."));
    }
    let mut tabs = Vec::new();
    let mut active = 0;
    if let Some(items) = source["tabs"]["items"]
        .as_array()
        .filter(|items| !items.is_empty())
    {
        if items.len() > MAX_TABS {
            return Err(invalid("Zu viele Query-Tabs."));
        }
        let mut ids = HashSet::new();
        for (index, item) in items.iter().enumerate() {
            let id = item["id"]
                .as_str()
                .filter(|id| !id.is_empty() && ids.insert(*id))
                .ok_or_else(|| invalid("Ungültige Query-Tab-ID."))?;
            if source["tabs"]["activeTabId"].as_str() == Some(id) {
                active = index;
            }
            let mut tab = workspace(&item["workspace"])?;
            tab.layout.name = item["name"]
                .as_str()
                .filter(|name| !name.trim().is_empty())
                .map_or_else(|| format!("Query {}", index + 1), str::to_owned);
            tabs.push(tab);
        }
    } else {
        tabs.push(workspace(if legacy {
            source
        } else {
            &source["workspace"]
        })?);
    }
    let first = tabs.remove(0);
    let runtime = &source["runtime"];
    let database = runtime["dbRelativePath"]
        .as_str()
        .filter(|name| !name.is_empty())
        .map(|name| name.replace('\\', "/").into())
        .or_else(|| {
            runtime["dbPath"]
                .as_str()
                .filter(|name| !name.trim().is_empty())
                .map(Into::into)
        });
    let name = path
        .file_stem()
        .and_then(|stem| stem.to_str())
        .unwrap_or("NodeQL")
        .to_owned();
    let no_database = database.is_none();
    let mut project = Project {
        name,
        database,
        blocks: first.blocks,
        workspace: Workspace {
            first: first.layout,
            tabs,
            active,
            sample: false,
            no_database,
        },
        ..Project::default()
    };
    project.settings.autosave = source["settings"]["autosaveEnabled"]
        .as_bool()
        .unwrap_or(true);
    Ok(project)
}

fn workspace(source: &Value) -> Result<QueryTab, ProjectError> {
    let roots = source["roots"]
        .as_array()
        .ok_or_else(|| invalid("Arbeitsbereich ohne Blockliste."))?;
    if roots.len() > MAX_BLOCKS {
        return Err(invalid("Zu viele Blöcke im Arbeitsbereich."));
    }
    let mut blocks = Vec::new();
    let coordinate = |key: &str| {
        source["pan"][key]
            .as_f64()
            .unwrap_or_default()
            .round()
            .clamp(-100_000.0, 100_000.0) as i32
    };
    let view = CanvasView {
        pan_x: coordinate("dx"),
        pan_y: coordinate("dy"),
        zoom_milli: (source["scale"].as_f64().unwrap_or(1.0).clamp(0.25, 3.0) * 1000.0).round()
            as u16,
    };
    let mut layout = QueryLayout {
        view,
        ..QueryLayout::default()
    };
    let mut trigger_seen = false;
    for root in roots {
        if root["type"] == "eventGreenFlag" {
            let mut connected = chain(&root["next"])?;
            // Flutter puts SELECT pagination after the entire connected chain.
            if root["next"]["type"] == "sqlSelect" {
                let inputs = &root["next"]["inputs"];
                if let Some(limit) = limit(inputs, "limit") {
                    connected.push(block(K::Limit, limit));
                }
            }
            let origin = position(root);
            if trigger_seen {
                layout.chains.push(QueryChain {
                    origin,
                    blocks: connected,
                });
            } else {
                trigger_seen = true;
                layout.origin = origin;
                blocks = connected;
            }
        } else {
            let at = position(root);
            for (index, block) in chain(root)?.into_iter().enumerate() {
                layout.detached.push(DetachedBlock {
                    block,
                    position: CanvasPoint {
                        y: at.y.saturating_add(index as i32 * 52),
                        ..at
                    },
                });
            }
        }
    }
    Ok(QueryTab { blocks, layout })
}

fn chain(mut node: &Value) -> Result<Vec<Block>, ProjectError> {
    let mut blocks = Vec::new();
    while !node.is_null() {
        blocks.extend(statement(node)?);
        if blocks.len() > MAX_BLOCKS {
            return Err(invalid("Zu viele Blöcke im Arbeitsbereich."));
        }
        if matches!(node["type"].as_str(), Some("sqlExplain" | "sqlWith")) {
            break;
        }
        node = &node["next"];
    }
    Ok(blocks)
}

fn position(node: &Value) -> CanvasPoint {
    let pos = &node["position"];
    let coordinate = |key: &str, fallback| {
        pos[key].as_f64().map_or(fallback, |number| {
            number.round().clamp(-100_000.0, 100_000.0) as i32
        })
    };
    let default = CanvasPoint::default();
    CanvasPoint {
        x: coordinate("dx", default.x),
        y: coordinate("dy", default.y),
    }
}

fn block(kind: K, input: String) -> Block {
    Block {
        input,
        ..Block::new(kind)
    }
}

pub(crate) fn statement(node: &Value) -> Result<Vec<Block>, ProjectError> {
    let kind = node["type"]
        .as_str()
        .ok_or_else(|| invalid("Block ohne Typ."))?;
    let inputs = &node["inputs"];
    if inputs.get("$nodeqlPluginBlock").is_some()
        || kind != "sqlSelect" && has_items(&node["children"])
    {
        return Err(invalid(format_args!(
            "Block {kind} enthält eine noch nicht unterstützte Erweiterung oder Unterkette."
        )));
    }
    let get = |key: &str, fallback: &str| input(inputs, key, fallback);
    let expr = |key: &str, fallback: &str| expression(inputs, key, fallback);
    let table = || with_alias(&get("table", "table_name"), &get("table_alias", ""));
    let option = |key, keyword: &str| {
        if enabled(&inputs[key]) || get(key, "").eq_ignore_ascii_case(keyword) {
            format!("{keyword} ")
        } else {
            String::new()
        }
    };
    let (kind, value) = match kind {
        "sqlSelect" => {
            let projection = if let Some(reporter) = inputs[REPORTERS].get("columns") {
                Some(decode_reporter(reporter)?)
            } else if let Some(children) = node["children"]
                .as_array()
                .filter(|children| !children.is_empty())
            {
                Some(Reporter::List {
                    items: children
                        .iter()
                        .map(decode_reporter)
                        .collect::<Result<Vec<_>, _>>()?,
                })
            } else {
                None
            };
            let columns = projection
                .as_ref()
                .map_or_else(|| get("columns", "*"), Reporter::sql);
            let columns = if columns.trim().is_empty() {
                "*".into()
            } else {
                columns
            };
            let prefix = if enabled(&inputs["distinct"])
                || get("select_mode", "").eq_ignore_ascii_case("DISTINCT")
            {
                "DISTINCT "
            } else {
                ""
            };
            let mut select = block(K::Select, format!("{prefix}{columns}"));
            if let Some(projection) = projection {
                let end = select.input.len();
                if !select.set_reporter(prefix.len()..end, projection) {
                    return Err(invalid("Die SELECT-Reporter sind zu groß."));
                }
            }
            let mut blocks = vec![select];
            if node["next"]["type"] != "sqlFrom"
                && !enabled(&inputs["omit_from"])
                && !get("table", "table_name").trim().is_empty()
            {
                blocks.push(block(K::From, table()));
            }
            return Ok(blocks);
        }
        "sqlFrom" => (K::From, table()),
        "sqlWhere" | "sqlAnd" | "sqlOr" => (
            match kind {
                "sqlWhere" => K::Where,
                "sqlAnd" => K::And,
                _ => K::Or,
            },
            predicate(inputs, "column", "value", "1 = 0")?,
        ),
        "sqlJoin" | "sqlInnerJoin" | "sqlLeftJoin" | "sqlRightJoin" | "sqlFullJoin"
        | "sqlCrossJoin" | "sqlNaturalJoin" | "sqlSelfJoin" => {
            let join = get(
                "join_type",
                kind.trim_start_matches("sql").trim_end_matches("Join"),
            )
            .to_ascii_uppercase();
            let mut source = if join == "SELF" && get("table_alias", "").trim().is_empty() {
                with_alias(&get("table", "table_name"), "t2")
            } else {
                table()
            };
            if !matches!(join.as_str(), "CROSS" | "NATURAL") {
                let left = expr("left_column", "")?;
                let right = expr("right_column", "")?;
                let condition = if left.is_empty() || right.is_empty() {
                    get(
                        "on",
                        if join == "SELF" {
                            "t1.id = t2.id"
                        } else {
                            "1 = 1"
                        },
                    )
                } else {
                    format!("{left} {} {right}", comparison(inputs))
                };
                source.push_str(&format!(" ON {condition}"));
            }
            if matches!(
                join.as_str(),
                "INNER" | "LEFT" | "RIGHT" | "FULL" | "CROSS" | "NATURAL"
            ) {
                source.insert_str(0, &format!("{join} "));
            }
            (K::Join, source)
        }
        "sqlUnion" | "sqlIntersect" | "sqlExcept" => {
            let mut select = get("sql", "SELECT 1")
                .trim()
                .trim_end_matches(';')
                .trim_end()
                .to_owned();
            if kind == "sqlUnion"
                && (enabled(&inputs["all"]) || get("set_mode", "").eq_ignore_ascii_case("ALL"))
            {
                select.insert_str(0, "ALL ");
            }
            (
                match kind {
                    "sqlUnion" => K::Union,
                    "sqlIntersect" => K::Intersect,
                    _ => K::Except,
                },
                select,
            )
        }
        "sqlGroupBy" => (
            K::GroupBy,
            first_expression(inputs, &["column", "expr"], "id")?,
        ),
        "sqlOrderBy" => {
            let column = first_expression(inputs, &["column", "expr"], "id")?;
            let order = if get("order", "").eq_ignore_ascii_case("DESC") {
                "DESC"
            } else {
                "ASC"
            };
            let upper = column.to_ascii_uppercase();
            (
                K::OrderBy,
                if upper.ends_with(" ASC") || upper.ends_with(" DESC") {
                    column
                } else {
                    format!("{column} {order}")
                },
            )
        }
        "sqlHaving" => {
            let value = expr("value", "")?;
            if value.is_empty() {
                (K::Having, get("predicate", "COUNT(*) > 0"))
            } else {
                let aggregate = match inputs[REPORTERS]["aggregate"]["type"].as_str() {
                    Some("sqlCount") => "COUNT".into(),
                    Some("sqlSum") => "SUM".into(),
                    Some("sqlAvg") => "AVG".into(),
                    Some("sqlMin") => "MIN".into(),
                    Some("sqlMax") => "MAX".into(),
                    Some(kind) => {
                        return Err(invalid(format_args!(
                            "HAVING-Reporter {kind} wird noch nicht unterstützt."
                        )));
                    }
                    None => get("aggregate", "COUNT").to_ascii_uppercase(),
                };
                let expression = if inputs.get("aggregate").is_none()
                    && inputs[REPORTERS].get("aggregate").is_none()
                {
                    expr("expr", "")?
                } else {
                    String::new()
                };
                let expression = if expression.is_empty() {
                    format!("{aggregate}({})", expr("column", "*")?)
                } else {
                    expression
                };
                (
                    K::Having,
                    format!("{expression} {} {value}", comparison(inputs)),
                )
            }
        }
        "sqlLimit" => (
            K::Limit,
            limit(inputs, "count")
                .or_else(|| limit(inputs, "limit"))
                .ok_or_else(|| invalid("LIMIT ohne gültige Zeilenanzahl."))?,
        ),
        "sqlInsert" | "sqlInsertOrReplace" | "sqlUpsert" => {
            let columns = get("columns", "");
            let values = get("values", "");
            let mut text = format!(
                "{}{columns} VALUES {values}",
                get("table", "table_name"),
                columns = parentheses(&columns),
                values = row_values(&values)
            );
            if kind == "sqlUpsert" {
                text.push_str(&format!(
                    " ON CONFLICT{}",
                    parentheses(&get("conflict_columns", ""))
                ));
                if get("action", "").eq_ignore_ascii_case("DO NOTHING") {
                    text.push_str(" DO NOTHING");
                } else {
                    let column = columns
                        .split(',')
                        .next()
                        .map(str::trim)
                        .filter(|value| !value.is_empty())
                        .unwrap_or("id");
                    text.push_str(&format!(
                        " DO UPDATE SET {}",
                        get("assignments", &format!("{column} = excluded.{column}"))
                    ));
                    let condition = get("update_where", "");
                    if !condition.trim().is_empty() {
                        text.push_str(&format!(" WHERE {condition}"));
                    }
                }
            }
            (
                match kind {
                    "sqlInsert" => K::Insert,
                    "sqlInsertOrReplace" => K::InsertOrReplace,
                    _ => K::Upsert,
                },
                text,
            )
        }
        "sqlUpdate" => (
            K::Update,
            format!(
                "{} SET {} = {} WHERE {}",
                get("table", "table_name"),
                expr("column", "column_name")?,
                expr("value", "")?,
                predicate(inputs, "where_column", "where_value", "1 = 0")?
            ),
        ),
        "sqlDelete" => (
            K::Delete,
            format!(
                "{} WHERE {}",
                get("table", "table_name"),
                predicate(inputs, "where_column", "where_value", "1 = 0")?
            ),
        ),
        "sqlCreateTable" => (
            K::CreateTable,
            format!(
                "{}{} {}",
                option("if_not_exists", "IF NOT EXISTS"),
                get("table", "new_table"),
                row_values(&get("definition", "id INTEGER PRIMARY KEY"))
            ),
        ),
        "sqlCreateIndex" if option("unique", "UNIQUE").is_empty() => (
            K::CreateIndex,
            format!(
                "{}{} ON {} ({})",
                option("if_not_exists", "IF NOT EXISTS"),
                get("name", "index_name"),
                get("table", "table_name"),
                get("columns", "column_name")
            ),
        ),
        "sqlDropIndex" => (
            K::DropIndex,
            format!(
                "{}{}",
                option("if_exists", "IF EXISTS"),
                get("name", "index_name")
            ),
        ),
        "sqlCreateView" if option("temporary", "TEMP").is_empty() => (
            K::CreateView,
            format!(
                "{}{}{} AS {}",
                option("if_not_exists", "IF NOT EXISTS"),
                get("name", "view_name"),
                parentheses(&get("columns", "")),
                get("sql", "SELECT * FROM table_name")
                    .trim()
                    .trim_end_matches(';')
            ),
        ),
        "sqlDropView" => (
            K::DropView,
            format!(
                "{}{}",
                option("if_exists", "IF EXISTS"),
                get("name", "view_name")
            ),
        ),
        "sqlCreateTrigger" if option("temporary", "TEMP").is_empty() => {
            let when = get("when", "");
            let when = if when.is_empty() {
                when
            } else {
                format!(" WHEN {when}")
            };
            (
                K::CreateTrigger,
                format!(
                    "{}{} {} {} ON {} FOR EACH ROW{when} BEGIN {}; END",
                    option("if_not_exists", "IF NOT EXISTS"),
                    get("name", "trigger_name"),
                    get("timing", "AFTER"),
                    get("event", "INSERT"),
                    get("table", "table_name"),
                    get("body", "SELECT 1").trim().trim_end_matches(';')
                ),
            )
        }
        "sqlDropTrigger" => (
            K::DropTrigger,
            format!(
                "{}{}",
                option("if_exists", "IF EXISTS"),
                get("name", "trigger_name")
            ),
        ),
        "sqlCreateVirtualTable" => (
            K::CreateVirtualTable,
            format!(
                "{}{} USING {}({})",
                option("if_not_exists", "IF NOT EXISTS"),
                get("table", "virtual_table"),
                get("module", "fts5"),
                get("arguments", "content")
            ),
        ),
        "sqlAlterTable" => (
            K::AlterTable,
            format!(
                "{} {}",
                get("table", "table_name"),
                get(
                    "alter",
                    &format!(
                        "{} {}",
                        get("alter_action", "ADD COLUMN"),
                        get("alter_value", "new_column TEXT")
                    )
                )
            ),
        ),
        "sqlTruncate" => (K::Truncate, get("table", "table_name")),
        "sqlBeginTransaction" => (
            K::Begin,
            format!("{} TRANSACTION", get("behavior", "DEFERRED")),
        ),
        "sqlCommit" => (K::Commit, String::new()),
        "sqlEndTransaction" => (K::End, String::new()),
        "sqlRollback" => (K::Rollback, String::new()),
        "sqlSavepoint" => (K::Savepoint, quote_identifier(&get("name", "sp1"))),
        "sqlRollbackToSavepoint" => (K::RollbackTo, quote_identifier(&get("name", "sp1"))),
        "sqlReleaseSavepoint" => (K::Release, quote_identifier(&get("name", "sp1"))),
        "sqlValues" => (K::Values, row_values(&get("values", "1"))),
        "sqlVacuum" | "sqlReindex" | "sqlAnalyze" => (
            match kind {
                "sqlVacuum" => K::Vacuum,
                "sqlReindex" => K::Reindex,
                _ => K::Analyze,
            },
            get(
                if kind == "sqlVacuum" {
                    "schema"
                } else {
                    "target"
                },
                "",
            ),
        ),
        "sqlAttachDatabase" => (
            K::Attach,
            format!(
                "'{}' AS {}",
                get("path", "database.db")
                    .trim_matches('\'')
                    .replace('\'', "''"),
                quote_identifier(&get("schema", "attached"))
            ),
        ),
        "sqlDetachDatabase" => (K::Detach, quote_identifier(&get("schema", "attached"))),
        "sqlPragma" => {
            let name = get("pragma", "foreign_keys").to_ascii_lowercase();
            let value = get("value", "");
            let command = match name.as_str() {
                "table_info" => format!(
                    "table_info('{}')",
                    if value.trim().is_empty() {
                        "table_name".into()
                    } else {
                        value.trim_matches('\'').replace('\'', "''")
                    }
                ),
                "database_list" => name,
                "journal_mode" => format!(
                    "journal_mode = {}",
                    if matches!(
                        value.to_ascii_uppercase().as_str(),
                        "DELETE" | "TRUNCATE" | "PERSIST" | "MEMORY" | "WAL" | "OFF"
                    ) {
                        value
                    } else {
                        "WAL".into()
                    }
                ),
                _ => format!(
                    "foreign_keys = {}",
                    if value.eq_ignore_ascii_case("OFF") {
                        "OFF"
                    } else {
                        "ON"
                    }
                ),
            };
            (K::Pragma, command)
        }
        "sqlExplain" | "sqlWith" => {
            let body = if node["next"].is_null() {
                None
            } else {
                Some(chain(&node["next"])?)
            };
            let body = body
                .as_ref()
                .map(|blocks| crate::compiler::compile(blocks))
                .transpose()
                .map_err(|_| invalid("Der untergeordnete SQL-Ausdruck ist ungültig."))?;
            if kind == "sqlExplain" {
                let mode = if get("mode", "").eq_ignore_ascii_case("EXPLAIN") {
                    ""
                } else {
                    "QUERY PLAN "
                };
                (
                    K::Explain,
                    format!(
                        "{mode}{}",
                        body.unwrap_or_else(|| get("sql", "SELECT 1"))
                            .trim()
                            .trim_end_matches(';')
                    ),
                )
            } else {
                let name = get("name", "cte");
                let recursive = option("recursive", "RECURSIVE");
                let columns = parentheses(&get("columns", ""));
                let cte = get("sql", "SELECT 1");
                let body =
                    body.unwrap_or_else(|| get("statement", &format!("SELECT * FROM {name}")));
                (
                    K::With,
                    format!(
                        "{recursive}{name}{columns} AS ({}) {}",
                        cte.trim().trim_end_matches(';'),
                        body.trim().trim_end_matches(';')
                    ),
                )
            }
        }
        "sqlDropTable" => (
            K::DropTable,
            format!(
                "{}{}",
                option("if_exists", "IF EXISTS"),
                get("table", "table_name")
            ),
        ),
        _ => {
            return Err(invalid(format_args!(
                "Block {kind} wird noch nicht unterstützt."
            )));
        }
    };
    let mut block = block(kind, value);
    if let Some(reporters) = inputs[REPORTERS].as_object() {
        for node in reporters.values() {
            let reporter = decode_reporter(node)?;
            let text = reporter.sql();
            let mut locations = block.input.match_indices(&text);
            if let Some((start, _)) = locations.next()
                && locations.next().is_none()
                && !text.is_empty()
                && !block
                    .reporters
                    .iter()
                    .any(|slot| start < slot.range.end && start + text.len() > slot.range.start)
            {
                block.set_reporter(start..start + text.len(), reporter);
            }
        }
    }
    Ok(vec![block])
}

fn input(inputs: &Value, key: &str, fallback: &str) -> String {
    match &inputs[key] {
        Value::String(value) => value.clone(),
        value @ (Value::Number(_) | Value::Bool(_)) => value.to_string(),
        _ => fallback.into(),
    }
}

fn expression(inputs: &Value, key: &str, fallback: &str) -> Result<String, ProjectError> {
    if let Some(node) = inputs[REPORTERS].get(key) {
        reporter(node)
    } else {
        Ok(input(inputs, key, fallback))
    }
}

fn first_expression(inputs: &Value, keys: &[&str], fallback: &str) -> Result<String, ProjectError> {
    if let Some(key) = keys
        .iter()
        .find(|key| inputs[REPORTERS].get(**key).is_some())
    {
        return expression(inputs, key, fallback);
    }
    Ok(keys
        .iter()
        .find_map(|key| {
            inputs
                .get(*key)
                .filter(|value| !value.is_null())
                .map(|_| input(inputs, key, fallback))
        })
        .unwrap_or_else(|| fallback.into()))
}

fn reporter(node: &Value) -> Result<String, ProjectError> {
    decode_reporter(node).map(|reporter| reporter.sql())
}

fn decode_reporter(node: &Value) -> Result<Reporter, ProjectError> {
    let inputs = &node["inputs"];
    let kind = node["type"].as_str().unwrap_or("?");
    if inputs.get("$nodeqlPluginBlock").is_some()
        || !node["next"].is_null()
        || has_items(&node["children"])
    {
        return Err(invalid(format_args!(
            "Reporter {kind} enthält eine Erweiterung oder Kette."
        )));
    }
    let get = |key: &str, fallback: &str| input(inputs, key, fallback);
    let child = |key: &str, fallback: &str| {
        inputs[REPORTERS].get(key).map_or_else(
            || Ok(Reporter::expression(get(key, fallback))),
            decode_reporter,
        )
    };
    let first_child = |keys: &[&str], fallback: &str| {
        let key = keys
            .iter()
            .copied()
            .find(|key| inputs[REPORTERS].get(*key).is_some())
            .or_else(|| {
                keys.iter()
                    .copied()
                    .find(|key| inputs.get(*key).is_some_and(|value| !value.is_null()))
            })
            .unwrap_or(keys[0]);
        child(key, fallback)
    };
    let alias = |expression| {
        let name = get("alias", "");
        if name.trim().is_empty() {
            expression
        } else {
            Reporter::Alias {
                expression: Box::new(expression),
                name,
            }
        }
    };
    let function = |name: &str, arguments| Reporter::Function {
        name: name.to_ascii_lowercase(),
        arguments,
    };
    let result = match kind {
        "sqlColumn" => alias(child("column", "*")?),
        "sqlAlias" => alias(first_child(&["value", "expr"], "id")?),
        "sqlText" if inputs[REPORTERS].get("text").is_some() => child("text", "")?,
        "sqlText" => {
            let kind = match get("literal_type", "text")
                .trim()
                .to_ascii_lowercase()
                .as_str()
            {
                "null" => LiteralKind::Null,
                "integer" => LiteralKind::Integer,
                "real" => LiteralKind::Real,
                "blob" => LiteralKind::Blob,
                _ => LiteralKind::Text,
            };
            Reporter::Literal {
                kind,
                value: get("text", ""),
            }
        }
        "sqlCount" | "sqlSum" | "sqlAvg" | "sqlMin" | "sqlMax" => {
            let mut argument = first_child(
                &["column", "expr"],
                if kind == "sqlCount" { "*" } else { "amount" },
            )?;
            if kind == "sqlCount" && enabled(&inputs["distinct"]) {
                argument = Reporter::expression(format!("DISTINCT {}", argument.sql()));
            }
            alias(function(&kind[3..], vec![argument]))
        }
        "sqlFunction" => {
            let name = get("function", "");
            let mut arguments = Vec::new();
            if let Some(args) = inputs["args"].as_array() {
                for (index, value) in args.iter().enumerate() {
                    let fallback = value
                        .as_str()
                        .map_or_else(|| value.to_string(), str::to_owned);
                    arguments.push(child(&format!("arg{index}"), &fallback)?);
                }
            }
            function(&name, arguments)
        }
        "sqlLength" | "sqlUpper" | "sqlLower" | "sqlTrim" => {
            function(&kind[3..], vec![child("expr", "''")?])
        }
        "sqlConcat" => Reporter::expression(format!(
            "({} || {})",
            child("a", "''")?.sql(),
            child("b", "''")?.sql()
        )),
        "sqlSubstring" => function(
            "substr",
            vec![
                child("expr", "''")?,
                child("start", "1")?,
                child("len", "1")?,
            ],
        ),
        "sqlLeft" => function(
            "substr",
            vec![
                child("expr", "''")?,
                Reporter::expression("1"),
                child("n", "1")?,
            ],
        ),
        "sqlRight" => function(
            "substr",
            vec![
                child("expr", "''")?,
                Reporter::expression(format!("-{}", get("n", "1"))),
            ],
        ),
        "sqlReplace" => function(
            "replace",
            vec![
                child("expr", "''")?,
                child("from", "''")?,
                child("to", "''")?,
            ],
        ),
        "sqlCoalesce" => function("coalesce", vec![child("a", "NULL")?, child("b", "NULL")?]),
        "sqlNullIf" => function("nullif", vec![child("a", "1")?, child("b", "1")?]),
        "sqlCurrentDate" => Reporter::expression("CURRENT_DATE"),
        "sqlCurrentTime" => Reporter::expression("CURRENT_TIME"),
        "sqlCurrentTimestamp" => Reporter::expression("CURRENT_TIMESTAMP"),
        "sqlCase" | "sqlIf" => {
            let (condition, a, b) = if kind == "sqlCase" {
                ("when", ["then", "result"], ["else", "default"])
            } else {
                ("cond", ["a", "value"], ["b", "default"])
            };
            let predicate = predicate(
                inputs,
                "condition_column",
                "condition_value",
                &get(condition, "1 = 0"),
            )?;
            Reporter::expression(format!(
                "CASE WHEN {predicate} THEN {} ELSE {} END",
                first_child(&a, "'x'")?.sql(),
                first_child(&b, "'y'")?.sql()
            ))
        }
        "sqlSubqueryIn" => Reporter::InQuery {
            column: Box::new(first_child(&["lhs", "column"], "id")?),
            query: get("sql", "SELECT id FROM t"),
        },
        _ => {
            return Err(invalid(format_args!(
                "Reporter {kind} wird noch nicht unterstützt."
            )));
        }
    };
    if !result.validate(0) {
        return Err(invalid(format_args!("Ungültiger Reporter {kind}.")));
    }
    Ok(result)
}

fn predicate(
    inputs: &Value,
    column_key: &str,
    value_key: &str,
    fallback: &str,
) -> Result<String, ProjectError> {
    let sql = if let Some(conditions) = inputs["conditions"]
        .as_array()
        .filter(|items| !items.is_empty())
    {
        let connector = if input(inputs, "match", "").eq_ignore_ascii_case("ANY") {
            "OR"
        } else {
            "AND"
        };
        let mut sql = String::new();
        for condition in conditions {
            let part = predicate(condition, "column", "value", "")?;
            if part.is_empty() {
                continue;
            }
            if !sql.is_empty() {
                let op = if input(condition, "connector", connector).eq_ignore_ascii_case("OR") {
                    "OR"
                } else {
                    "AND"
                };
                sql.push_str(&format!(" {op} "));
            }
            if has_items(&condition["conditions"]) && !part.starts_with("NOT (") {
                sql.push_str(&format!("({part})"));
            } else {
                sql.push_str(&part);
            }
        }
        if sql.is_empty() {
            input(inputs, "predicate", fallback)
        } else {
            sql
        }
    } else if inputs[REPORTERS][value_key]["type"] == "sqlSubqueryIn" {
        reporter(&inputs[REPORTERS][value_key])?
    } else {
        let column = expression(inputs, column_key, "")?;
        let mut value = expression(inputs, value_key, "")?;
        let operator = comparison(inputs);
        if let Some(values) = inputs[value_key].as_array() {
            let values = values
                .iter()
                .map(|item| {
                    item.as_str()
                        .map_or_else(|| item.to_string(), str::to_owned)
                })
                .collect::<Vec<_>>();
            value = if matches!(operator, "BETWEEN" | "NOT BETWEEN") {
                values.join(" AND ")
            } else {
                values.join(", ")
            };
        }
        if matches!(operator, "BETWEEN" | "NOT BETWEEN")
            && inputs.get("lower").is_some()
            && inputs.get("upper").is_some()
        {
            value = format!(
                "{} AND {}",
                input(inputs, "lower", ""),
                input(inputs, "upper", "")
            );
        }
        if column.trim().is_empty() {
            input(inputs, "predicate", fallback)
        } else if matches!(operator, "IS NULL" | "IS NOT NULL") {
            format!("{column} {operator}")
        } else if value.trim().is_empty() {
            input(inputs, "predicate", fallback)
        } else if matches!(operator, "IN" | "NOT IN") {
            format!("{column} {operator} {}", row_values(&value))
        } else {
            format!("{column} {operator} {value}")
        }
    };
    let negated = inputs.get("negated").unwrap_or(&inputs["negation"]);
    Ok(
        if !sql.is_empty()
            && (enabled(negated)
                || negated
                    .as_str()
                    .is_some_and(|value| value.eq_ignore_ascii_case("NOT")))
        {
            format!("NOT ({sql})")
        } else {
            sql
        },
    )
}

fn comparison(inputs: &Value) -> &'static str {
    const OPS: &[&str] = &[
        "=",
        "==",
        "!=",
        "<>",
        "<",
        ">",
        "<=",
        ">=",
        "IS",
        "IS NOT",
        "LIKE",
        "NOT LIKE",
        "GLOB",
        "NOT GLOB",
        "IN",
        "NOT IN",
        "BETWEEN",
        "NOT BETWEEN",
        "IS NULL",
        "IS NOT NULL",
    ];
    let requested = inputs["operator"].as_str().unwrap_or("=").trim();
    OPS.iter()
        .copied()
        .find(|operator| requested.eq_ignore_ascii_case(operator))
        .unwrap_or("=")
}

fn limit(inputs: &Value, key: &str) -> Option<String> {
    let count = input(inputs, key, "").trim().parse::<u64>().ok()?;
    let offset = input(inputs, "offset", "").trim().parse::<u64>().ok();
    Some(offset.map_or_else(
        || count.to_string(),
        |offset| format!("{count} OFFSET {offset}"),
    ))
}

fn enabled(value: &Value) -> bool {
    value == &Value::Bool(true)
        || value.as_f64().is_some_and(|number| number != 0.0)
        || value.as_str().is_some_and(|text| {
            matches!(
                text.trim().to_ascii_uppercase().as_str(),
                "TRUE" | "YES" | "ON" | "1"
            )
        })
}

fn has_items(value: &Value) -> bool {
    value.as_array().is_some_and(|items| !items.is_empty())
}

fn with_alias(value: &str, alias: &str) -> String {
    let alias = alias.trim();
    if alias.is_empty() {
        value.into()
    } else {
        format!("{value} AS {}", quote_identifier(alias))
    }
}

fn parentheses(value: &str) -> String {
    if value.trim().is_empty() {
        String::new()
    } else {
        format!(" ({value})")
    }
}

fn row_values(value: &str) -> String {
    let trimmed = value.trim().trim_end_matches(';').trim_end();
    let trimmed = if trimmed
        .get(..7)
        .is_some_and(|prefix| prefix.eq_ignore_ascii_case("VALUES "))
    {
        trimmed[7..].trim_start()
    } else {
        trimmed
    };
    if trimmed.starts_with('(') {
        trimmed.into()
    } else {
        format!("({trimmed})")
    }
}
