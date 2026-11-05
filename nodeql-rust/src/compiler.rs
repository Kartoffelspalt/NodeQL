use crate::model::{Block, BlockKind, MAX_BLOCKS};
use uuid::Uuid;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Diagnostic {
    pub block_id: Option<Uuid>,
    pub message: String,
}

/// Compile one connected SELECT chain. SQLite validates expressions at execution.
/// Preserve the visible order: never silently sort or skip invalid blocks.
pub fn compile(blocks: &[Block]) -> Result<String, Vec<Diagnostic>> {
    let mut errors = Vec::new();
    if blocks.is_empty() {
        errors.push(Diagnostic { block_id: None, message: "Füge einen SELECT-Block hinzu.".into() });
    }
    if blocks.len() > MAX_BLOCKS {
        errors.push(Diagnostic { block_id: None, message: "Zu viele Blöcke.".into() });
    }
    let mut previous_rank = 0;
    let mut seen = [false; 8];
    for (index, block) in blocks.iter().enumerate() {
        let rank = block.kind.rank();
        let mut report = |message: String| errors.push(Diagnostic { block_id: Some(block.id), message });
        if index == 0 && block.kind != BlockKind::Select {
            report("Die Abfrage muss mit SELECT beginnen.".into());
        }
        if rank < previous_rank {
            report(format!("{} steht an der falschen Position.", block.kind.keyword()));
        }
        if seen[rank as usize] && block.kind != BlockKind::Join {
            report(format!("{} darf nur einmal vorkommen.", block.kind.keyword()));
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
        seen[rank as usize] = true;
        previous_rank = rank;
    }
    if !errors.is_empty() { return Err(errors); }
    Ok(format!("{};", blocks.iter().map(|block| {
        format!("{} {}", block.kind.keyword(), block.input.trim())
    }).collect::<Vec<_>>().join("\n")))
}
