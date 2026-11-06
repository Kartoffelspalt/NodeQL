use crate::model::{Block, BlockKind, MAX_BLOCKS};
use uuid::Uuid;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Diagnostic {
    pub block_id: Option<Uuid>,
    pub message: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SourceSpan {
    pub block_id: Uuid,
    pub range: std::ops::Range<usize>,
}

#[derive(Debug, Default, Clone, PartialEq, Eq)]
pub struct Compiled {
    pub sql: String,
    pub spans: Vec<SourceSpan>,
}

impl Compiled {
    pub fn extend(&mut self, other: Self) {
        if !self.sql.is_empty() {
            self.sql.push('\n');
        }
        let offset = self.sql.len();
        self.sql.push_str(&other.sql);
        self.spans
            .extend(other.spans.into_iter().map(|span| SourceSpan {
                block_id: span.block_id,
                range: span.range.start + offset..span.range.end + offset,
            }));
    }

    fn push(&mut self, id: Uuid, fragment: &str) {
        if !self.sql.is_empty() {
            self.sql.push('\n');
        }
        let start = self.sql.len();
        self.sql.push_str(fragment);
        self.spans.push(SourceSpan {
            block_id: id,
            range: start..self.sql.len(),
        });
    }
}

pub fn compile(blocks: &[Block]) -> Result<String, Vec<Diagnostic>> {
    compile_with_spans(blocks).map(|compiled| compiled.sql)
}

pub fn compile_with_spans(blocks: &[Block]) -> Result<Compiled, Vec<Diagnostic>> {
    if blocks.len() > MAX_BLOCKS {
        return Err(vec![Diagnostic {
            block_id: None,
            message: "Zu viele Blöcke.".into(),
        }]);
    }
    if blocks.is_empty() {
        return Err(vec![Diagnostic {
            block_id: None,
            message: "Füge einen SQL-Block hinzu.".into(),
        }]);
    }
    let mut output = Compiled::default();
    let mut start = 0;
    for (index, block) in blocks
        .iter()
        .enumerate()
        .filter(|(_, block)| block.kind.standalone())
    {
        if start < index {
            output.extend(compile_select(&blocks[start..index])?);
        }
        let input = block.input.trim();
        if input.is_empty() && !block.kind.optional_input() {
            return Err(vec![Diagnostic {
                block_id: Some(block.id),
                message: format!("{} benötigt einen Ausdruck.", block.kind.keyword()),
            }]);
        }
        let input = input.trim_end_matches(';').trim_end();
        let fragment = if input.is_empty() {
            block.kind.keyword().into()
        } else {
            format!("{} {input}", block.kind.keyword())
        };
        output.push(block.id, &fragment);
        output.sql.push(';');
        start = index + 1;
    }
    if start < blocks.len() {
        output.extend(compile_select(&blocks[start..])?);
    }
    Ok(output)
}

/// Compile one connected SELECT chain, preserving the visible order.
fn compile_select(blocks: &[Block]) -> Result<Compiled, Vec<Diagnostic>> {
    let mut errors = Vec::new();
    let mut previous_rank = 0;
    let mut seen = [false; 10];
    for (index, block) in blocks.iter().enumerate() {
        let rank = block.kind.rank();
        let mut report = |message: String| {
            errors.push(Diagnostic {
                block_id: Some(block.id),
                message,
            })
        };
        if index == 0 && block.kind != BlockKind::Select {
            report("Die Abfrage muss mit SELECT beginnen.".into());
        }
        if rank < previous_rank {
            report(format!(
                "{} steht an der falschen Position.",
                block.kind.keyword()
            ));
        }
        if seen[rank as usize] && !block.kind.repeatable() {
            report(format!(
                "{} darf nur einmal vorkommen.",
                block.kind.keyword()
            ));
        }
        if block.input.trim().is_empty() {
            report(format!("{} benötigt einen Ausdruck.", block.kind.keyword()));
        }
        if block.kind == BlockKind::Join && !seen[BlockKind::From.rank() as usize] {
            report("JOIN benötigt einen FROM-Block.".into());
        }
        if block.kind == BlockKind::Having && !seen[BlockKind::GroupBy.rank() as usize] {
            report("HAVING benötigt einen GROUP BY-Block.".into());
        }
        if matches!(block.kind, BlockKind::And | BlockKind::Or)
            && !seen[BlockKind::Where.rank() as usize]
        {
            report(format!(
                "{} benötigt einen WHERE-Block.",
                block.kind.keyword()
            ));
        }
        seen[rank as usize] = true;
        previous_rank = rank;
    }
    if !errors.is_empty() {
        return Err(errors);
    }
    let mut output = Compiled::default();
    let source = blocks
        .iter()
        .any(|block| block.kind == BlockKind::Join)
        .then(|| blocks.iter().find(|block| block.kind == BlockKind::From))
        .flatten()
        .and_then(|block| projection_source(&block.input));
    for block in blocks {
        let input = block.input.trim();
        let fragment = match block.kind {
            BlockKind::Join => {
                let (kind, source) = join_parts(input);
                if kind.is_empty() {
                    format!("JOIN {source}")
                } else {
                    format!("{kind} JOIN {source}")
                }
            }
            BlockKind::Select if block.qualify_projection && source.is_some() => {
                format!("SELECT {}", qualify_projection(input, source.unwrap()))
            }
            kind => format!("{} {input}", kind.keyword()),
        };
        output.push(block.id, &fragment);
    }
    output.sql.push(';');
    Ok(output)
}

pub fn join_parts(input: &str) -> (&str, &str) {
    if let Some((first, rest)) = input.split_once(' ')
        && ["INNER", "LEFT", "RIGHT", "FULL", "CROSS", "NATURAL"]
            .iter()
            .any(|kind| first.eq_ignore_ascii_case(kind))
    {
        (first, rest)
    } else {
        ("", input)
    }
}

fn projection_source(source: &str) -> Option<&str> {
    let tokens = source.split_whitespace().collect::<Vec<_>>();
    let name = match tokens.as_slice() {
        [name] => *name,
        [_, alias] => *alias,
        [_, as_, alias] if as_.eq_ignore_ascii_case("AS") => *alias,
        _ => return None,
    };
    name.split('.').all(identifier).then_some(name)
}

fn identifier(text: &str) -> bool {
    let mut bytes = text.bytes();
    bytes
        .next()
        .is_some_and(|byte| byte.is_ascii_alphabetic() || byte == b'_')
        && bytes.all(|byte| byte.is_ascii_alphanumeric() || byte == b'_')
}

fn qualify_projection(input: &str, source: &str) -> String {
    let (modifier, projection) = input
        .split_once(char::is_whitespace)
        .filter(|(word, _)| {
            word.eq_ignore_ascii_case("DISTINCT") || word.eq_ignore_ascii_case("ALL")
        })
        .map_or(("", input), |(word, rest)| (word, rest.trim_start()));
    let arguments = crate::sql_import::arguments(projection);
    if arguments.is_empty() {
        return input.into();
    }
    let selected = arguments
        .into_iter()
        .map(|range| {
            let term = &projection[range];
            let mut words = term.split_whitespace();
            let first = words.next().unwrap_or_default();
            let alias = words
                .next()
                .is_none_or(|word| word.eq_ignore_ascii_case("AS"));
            if alias
                && identifier(first)
                && ![
                    "NULL",
                    "TRUE",
                    "FALSE",
                    "CURRENT_DATE",
                    "CURRENT_TIME",
                    "CURRENT_TIMESTAMP",
                ]
                .iter()
                .any(|keyword| first.eq_ignore_ascii_case(keyword))
            {
                format!("{source}.{term}")
            } else {
                term.into()
            }
        })
        .collect::<Vec<_>>()
        .join(", ");
    if modifier.is_empty() {
        selected
    } else {
        format!("{modifier} {selected}")
    }
}
