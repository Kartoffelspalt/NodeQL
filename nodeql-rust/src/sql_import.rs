//! Convert supported handwritten SQLite statements to editable blocks without executing them.
use crate::model::{Block, BlockKind as K, MAX_BLOCKS, MAX_TABS};
use std::ops::Range;

type Word = (String, Range<usize>);

pub(crate) fn standalone_operation(sql: &str) -> Option<K> {
    let (clean, separators, words) = scan(sql, b';').ok()?;
    let first = words.first()?;
    if !clean[..first.1.start].trim().is_empty() {
        return None;
    }
    if let Some(&end) = separators.first()
        && !clean[end + 1..]
            .trim_matches(|c: char| c.is_whitespace() || c == ';')
            .is_empty()
    {
        return None;
    }
    match first.0.as_str() {
        "VACUUM" if words.iter().all(|(word, _)| word != "INTO") => Some(K::Vacuum),
        "ATTACH" => Some(K::Attach),
        "DETACH" => Some(K::Detach),
        "PRAGMA" => Some(K::Pragma),
        _ => None,
    }
}

pub fn convert(source: &str) -> Result<Vec<Vec<Block>>, String> {
    if source.len() > 256 * 1024 {
        return Err("Der SQL-Text ist größer als 256 KiB.".into());
    }
    let (clean, separators, words) = scan(source, b';')?;
    let mut tabs = Vec::new();
    let mut from = 0;
    for to in separators.into_iter().chain(std::iter::once(clean.len())) {
        let first = words.partition_point(|(_, range)| range.start < from);
        let last = words.partition_point(|(_, range)| range.start < to);
        if !clean[from..to].trim().is_empty() {
            if first == last || !clean[from..words[first].1.start].trim().is_empty() {
                return Err(format!(
                    "SQL-Anweisung {} beginnt nicht mit einem SQL-Schlüsselwort.",
                    tabs.len() + 1
                ));
            }
            tabs.push(
                statement(&clean[..to], &words[first..last])
                    .map_err(|error| format!("SQL-Anweisung {}: {error}", tabs.len() + 1))?,
            );
            if tabs.len() > MAX_TABS {
                return Err("Zu viele Anweisungen für die verfügbaren Query-Tabs.".into());
            }
        }
        from = to + 1;
    }
    if tabs.is_empty() {
        Err("Der SQL-Text enthält keine Anweisung.".into())
    } else {
        Ok(tabs)
    }
}

fn statement(sql: &str, words: &[Word]) -> Result<Vec<Block>, String> {
    let word = |index| {
        words
            .get(index)
            .map(|(name, _): &Word| name.as_str())
            .unwrap_or("")
    };
    let (kind, keyword_count) = match (word(0), word(1), word(2), word(3)) {
        ("SELECT", _, _, _) => return select(sql, words),
        ("INSERT", "INTO", _, _) => (K::Insert, 2),
        ("INSERT", "OR", "REPLACE", "INTO") => (K::InsertOrReplace, 4),
        ("REPLACE", "INTO", _, _) => (K::InsertOrReplace, 2),
        ("UPDATE", _, _, _) if word(1) != "OR" => (K::Update, 1),
        ("DELETE", "FROM", _, _) => (K::Delete, 2),
        ("CREATE", "TABLE", _, _) => (K::CreateTable, 2),
        ("CREATE", "INDEX", _, _) => (K::CreateIndex, 2),
        ("CREATE", "VIEW", _, _) => (K::CreateView, 2),
        ("CREATE", "VIRTUAL", "TABLE", _) => (K::CreateVirtualTable, 3),
        ("DROP", "TABLE", _, _) => (K::DropTable, 2),
        ("DROP", "INDEX", _, _) => (K::DropIndex, 2),
        ("DROP", "VIEW", _, _) => (K::DropView, 2),
        ("DROP", "TRIGGER", _, _) => (K::DropTrigger, 2),
        ("ALTER", "TABLE", _, _) => (K::AlterTable, 2),
        ("BEGIN", _, _, _) => (K::Begin, 1),
        ("COMMIT", _, _, _) => (K::Commit, 1),
        ("END", "TRANSACTION", _, _) => (K::End, 2),
        ("END", "", _, _) => (K::End, 1),
        ("ROLLBACK", "TO", "SAVEPOINT", _) => (K::RollbackTo, 3),
        ("ROLLBACK", "TO", _, _) => (K::RollbackTo, 2),
        ("ROLLBACK", _, _, _) => (K::Rollback, 1),
        ("SAVEPOINT", _, _, _) => (K::Savepoint, 1),
        ("RELEASE", "SAVEPOINT", _, _) => (K::Release, 2),
        ("RELEASE", _, _, _) => (K::Release, 1),
        ("PRAGMA", _, _, _) => (K::Pragma, 1),
        ("ATTACH", "DATABASE", _, _) => (K::Attach, 2),
        ("ATTACH", _, _, _) => (K::Attach, 1),
        ("DETACH", "DATABASE", _, _) => (K::Detach, 2),
        ("DETACH", _, _, _) => (K::Detach, 1),
        ("VACUUM", _, _, _) => (K::Vacuum, 1),
        ("REINDEX", _, _, _) => (K::Reindex, 1),
        ("ANALYZE", _, _, _) => (K::Analyze, 1),
        ("EXPLAIN", _, _, _) => (K::Explain, 1),
        ("WITH", _, _, _) => (K::With, 1),
        ("VALUES", _, _, _) => (K::Values, 1),
        _ => {
            return Err(format!(
                "„{}“ kann noch nicht in Blöcke umgewandelt werden.",
                word(0)
            ));
        }
    };
    let kind = if kind == K::Insert
        && words
            .windows(2)
            .any(|pair| pair[0].0 == "ON" && pair[1].0 == "CONFLICT")
    {
        K::Upsert
    } else {
        kind
    };
    Ok(vec![block(kind, &sql[words[keyword_count - 1].1.end..])?])
}

fn select(sql: &str, words: &[Word]) -> Result<Vec<Block>, String> {
    let mut blocks = Vec::new();
    let mut kind = K::Select;
    let mut input_start = words[0].1.end;
    let mut join_type = "";
    for (index, (word, range)) in words.iter().enumerate().skip(1) {
        let next = words.get(index + 1).map(|word| word.0.as_str());
        let next_kind = match word.as_str() {
            "FROM"
                if kind == K::Select
                    && !(words[index - 1].0 == "DISTINCT"
                        && index >= 2
                        && matches!(words[index - 2].0.as_str(), "IS" | "NOT")
                        && sql[words[index - 1].1.end..range.start].trim().is_empty()) =>
            {
                K::From
            }
            "JOIN" => K::Join,
            "WHERE" => K::Where,
            "GROUP" if next == Some("BY") => K::GroupBy,
            "HAVING" => K::Having,
            "ORDER" if next == Some("BY") => K::OrderBy,
            "LIMIT" => K::Limit,
            "UNION" => K::Union,
            "INTERSECT" => K::Intersect,
            "EXCEPT" => K::Except,
            "WINDOW" => {
                return Err(
                    "Ein WINDOW-Abschnitt kann noch nicht in Blöcke umgewandelt werden.".into(),
                );
            }
            _ => continue,
        };
        let mut cut = range.start;
        let mut prefix = "";
        if next_kind == K::Join {
            let preceding = &words[index - 1];
            if matches!(
                preceding.0.as_str(),
                "INNER" | "LEFT" | "RIGHT" | "FULL" | "NATURAL" | "CROSS"
            ) && sql[preceding.1.end..range.start].trim().is_empty()
            {
                cut = preceding.1.start;
                prefix = &preceding.0;
            } else if preceding.0 == "OUTER" && index >= 2 {
                let modifier = &words[index - 2];
                if matches!(modifier.0.as_str(), "LEFT" | "RIGHT" | "FULL")
                    && sql[modifier.1.end..preceding.1.start].trim().is_empty()
                    && sql[preceding.1.end..range.start].trim().is_empty()
                {
                    cut = modifier.1.start;
                    prefix = &modifier.0;
                }
            }
            let modifier_index = words.partition_point(|(_, range)| range.start < cut);
            if modifier_index >= 1
                && words[modifier_index - 1].0 == "NATURAL"
                && prefix != "NATURAL"
            {
                return Err(
                    "Dieser zusammengesetzte NATURAL JOIN wird noch nicht unterstützt.".into(),
                );
            }
        }
        push_clause(&mut blocks, kind, join_type, &sql[input_start..cut])?;
        kind = next_kind;
        join_type = prefix;
        input_start = if matches!(kind, K::GroupBy | K::OrderBy) {
            words[index + 1].1.end
        } else {
            range.end
        };
        if kind.set_operation() {
            break;
        }
    }
    push_clause(&mut blocks, kind, join_type, &sql[input_start..])?;
    if blocks.len() > MAX_BLOCKS {
        return Err("Die Abfrage enthält zu viele Blöcke.".into());
    }
    crate::compiler::compile(&blocks).map_err(|errors| {
        errors
            .into_iter()
            .map(|error| error.message)
            .collect::<Vec<_>>()
            .join("\n")
    })?;
    Ok(blocks)
}

fn push_clause(blocks: &mut Vec<Block>, kind: K, join: &str, input: &str) -> Result<(), String> {
    let mut block = block(kind, input)?;
    if !join.is_empty() {
        block.input.insert_str(0, &format!("{join} "));
    }
    blocks.push(block);
    Ok(())
}

fn block(kind: K, input: &str) -> Result<Block, String> {
    let input = input.trim();
    if input.is_empty() && !kind.optional_input() || input.len() > 16 * 1024 {
        return Err(format!(
            "{} benötigt einen Ausdruck bis 16 KiB.",
            kind.keyword()
        ));
    }
    Ok(Block {
        input: input.into(),
        qualify_projection: false,
        ..Block::new(kind)
    })
}

pub(crate) fn arguments(source: &str) -> Vec<Range<usize>> {
    let Ok((_, commas, _)) = scan(source, b',') else {
        return Vec::new();
    };
    let mut from = 0;
    commas
        .into_iter()
        .chain(std::iter::once(source.len()))
        .filter_map(|to| {
            let field = &source[from..to];
            let start = from + (field.len() - field.trim_start().len());
            let end = from + field.trim_end().len();
            from = to + 1;
            (start < end).then_some(start..end)
        })
        .collect()
}

#[cfg(feature = "desktop")]
pub(crate) fn keyword(source: &str, key: &str) -> Option<Range<usize>> {
    scan(source, b';')
        .ok()?
        .2
        .into_iter()
        .find_map(|(word, span)| (word == key).then_some(span))
}

fn scan(source: &str, separator: u8) -> Result<(String, Vec<usize>, Vec<Word>), String> {
    let bytes = source.as_bytes();
    let mut clean = bytes.to_vec();
    let mut separators = Vec::new();
    let mut words = Vec::new();
    let mut index = 0;
    let mut depth: usize = 0;
    while let Some(&byte) = bytes.get(index) {
        let start = index;
        index += 1;
        match byte {
            b'-' if bytes.get(index) == Some(&b'-') => {
                index += 1;
                while bytes.get(index).is_some_and(|byte| *byte != b'\n') {
                    index += 1;
                }
                clean[start..index].fill(b' ');
            }
            b'/' if bytes.get(index) == Some(&b'*') => {
                index += 1;
                while bytes
                    .get(index..index + 2)
                    .is_some_and(|pair| pair != b"*/")
                {
                    index += 1;
                }
                if bytes.get(index..index + 2) != Some(b"*/") {
                    return Err("Ein SQL-Kommentar ist offen.".into());
                }
                index += 2;
                clean[start..index].fill(b' ');
            }
            b'\'' | b'"' | b'`' | b'[' => {
                let end = if byte == b'[' { b']' } else { byte };
                loop {
                    let Some(&next) = bytes.get(index) else {
                        return Err("Ein SQL-String oder Bezeichner ist offen.".into());
                    };
                    index += 1;
                    if next == end {
                        if end == b']' || bytes.get(index) != Some(&end) {
                            break;
                        }
                        index += 1;
                    }
                }
            }
            b'(' => depth += 1,
            b')' => {
                depth = depth
                    .checked_sub(1)
                    .ok_or("Unerwartete schließende Klammer.")?
            }
            value if value == separator && depth == 0 => separators.push(start),
            _ if identifier(byte) => {
                while bytes.get(index).is_some_and(|byte| identifier(*byte)) {
                    index += 1;
                }
                if depth == 0 {
                    words.push((source[start..index].to_ascii_uppercase(), start..index));
                }
            }
            _ => {}
        }
    }
    if depth != 0 {
        return Err("Eine SQL-Klammer ist offen.".into());
    }
    Ok((
        String::from_utf8(clean).expect("Only complete comments were replaced"),
        separators,
        words,
    ))
}

fn identifier(byte: u8) -> bool {
    byte.is_ascii_alphanumeric() || matches!(byte, b'_' | b'$') || !byte.is_ascii()
}
