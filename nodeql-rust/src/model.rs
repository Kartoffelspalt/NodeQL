use serde::{Deserialize, Serialize};
use uuid::Uuid;

pub const FORMAT: &str = "nodeql_rust_project";
pub const VERSION: u32 = 1;
pub const MAX_BLOCKS: usize = 256;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum BlockKind {
    Select,
    From,
    Join,
    Where,
    GroupBy,
    Having,
    OrderBy,
    Limit,
}

impl BlockKind {
    pub const ALL: [Self; 8] = [
        Self::Select, Self::From, Self::Join, Self::Where,
        Self::GroupBy, Self::Having, Self::OrderBy, Self::Limit,
    ];

    pub fn keyword(self) -> &'static str {
        match self {
            Self::Select => "SELECT",
            Self::From => "FROM",
            Self::Join => "JOIN",
            Self::Where => "WHERE",
            Self::GroupBy => "GROUP BY",
            Self::Having => "HAVING",
            Self::OrderBy => "ORDER BY",
            Self::Limit => "LIMIT",
        }
    }

    pub fn description(self) -> &'static str {
        match self {
            Self::Select => "Spalten auswählen",
            Self::From => "Tabelle auswählen",
            Self::Join => "Tabelle verbinden · ON",
            Self::Where => "Zeilen filtern",
            Self::GroupBy => "Zeilen gruppieren",
            Self::Having => "Gruppen filtern",
            Self::OrderBy => "Ergebnis sortieren",
            Self::Limit => "Zeilen begrenzen",
        }
    }

    pub fn default_input(self) -> &'static str {
        match self {
            Self::Select => "*",
            Self::From => "customers",
            Self::Join => "orders ON orders.customer_id = customers.id",
            Self::Where => "city = 'Berlin'",
            Self::GroupBy => "city",
            Self::Having => "COUNT(*) > 1",
            Self::OrderBy => "name ASC",
            Self::Limit => "100",
        }
    }

    pub(crate) fn rank(self) -> u8 {
        match self {
            Self::Select => 0,
            Self::From => 1,
            Self::Join => 2,
            Self::Where => 3,
            Self::GroupBy => 4,
            Self::Having => 5,
            Self::OrderBy => 6,
            Self::Limit => 7,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Block {
    pub id: Uuid,
    pub kind: BlockKind,
    /// An editable SQLite expression, not a quoted literal.
    pub input: String,
}

impl Block {
    pub fn new(kind: BlockKind) -> Self {
        Self { id: Uuid::new_v4(), kind, input: kind.default_input().into() }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Project {
    pub format: String,
    pub version: u32,
    pub name: String,
    /// Absolute path when opened in the app; relative paths resolve beside the project file.
    pub database: Option<std::path::PathBuf>,
    pub blocks: Vec<Block>,
}

impl Default for Project {
    fn default() -> Self {
        Self {
            format: FORMAT.into(),
            version: VERSION,
            name: "Meine erste Abfrage".into(),
            database: None,
            blocks: vec![
                Block { input: "name, city, balance".into(), ..Block::new(BlockKind::Select) },
                Block::new(BlockKind::From),
                Block::new(BlockKind::OrderBy),
                Block::new(BlockKind::Limit),
            ],
        }
    }
}

impl Project {
    /// Move a block to an insertion slot (0..=len), preserving its identity.
    pub fn move_block(&mut self, id: Uuid, slot: usize) -> bool {
        let Some(index) = self.blocks.iter().position(|block| block.id == id) else {
            return false;
        };
        let slot = slot.min(self.blocks.len());
        let target = if index < slot { slot.saturating_sub(1) } else { slot };
        if index == target { return false; }
        let block = self.blocks.remove(index);
        self.blocks.insert(target, block);
        true
    }
}
