use crate::reporter::{Reporter, ReporterSlot};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

pub const FORMAT: &str = "nodeql_rust_project";
pub const VERSION: u32 = 1;
pub const MAX_BLOCKS: usize = 256;
pub const MAX_TABS: usize = 32;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum BlockKind {
    Select,
    From,
    Join,
    Where,
    And,
    Or,
    GroupBy,
    Having,
    Union,
    Intersect,
    Except,
    OrderBy,
    Limit,
    Insert,
    InsertOrReplace,
    Upsert,
    Update,
    Delete,
    CreateTable,
    CreateIndex,
    DropIndex,
    CreateView,
    DropView,
    CreateTrigger,
    DropTrigger,
    CreateVirtualTable,
    AlterTable,
    Truncate,
    DropTable,
    Begin,
    Commit,
    End,
    Rollback,
    Savepoint,
    RollbackTo,
    Release,
    Pragma,
    Attach,
    Detach,
    Vacuum,
    Reindex,
    Analyze,
    Explain,
    With,
    Values,
}

impl BlockKind {
    pub const ALL: [Self; 10] = [
        Self::Select,
        Self::From,
        Self::Join,
        Self::Where,
        Self::And,
        Self::Or,
        Self::GroupBy,
        Self::Having,
        Self::OrderBy,
        Self::Limit,
    ];

    pub fn keyword(self) -> &'static str {
        match self {
            Self::Select => "SELECT",
            Self::From => "FROM",
            Self::Join => "JOIN",
            Self::Where => "WHERE",
            Self::And => "AND",
            Self::Or => "OR",
            Self::GroupBy => "GROUP BY",
            Self::Having => "HAVING",
            Self::Union => "UNION",
            Self::Intersect => "INTERSECT",
            Self::Except => "EXCEPT",
            Self::OrderBy => "ORDER BY",
            Self::Limit => "LIMIT",
            Self::Insert | Self::Upsert => "INSERT INTO",
            Self::InsertOrReplace => "INSERT OR REPLACE INTO",
            Self::Update => "UPDATE",
            Self::Delete | Self::Truncate => "DELETE FROM",
            Self::CreateTable => "CREATE TABLE",
            Self::CreateIndex => "CREATE INDEX",
            Self::DropIndex => "DROP INDEX",
            Self::CreateView => "CREATE VIEW",
            Self::DropView => "DROP VIEW",
            Self::CreateTrigger => "CREATE TRIGGER",
            Self::DropTrigger => "DROP TRIGGER",
            Self::CreateVirtualTable => "CREATE VIRTUAL TABLE",
            Self::AlterTable => "ALTER TABLE",
            Self::DropTable => "DROP TABLE",
            Self::Begin => "BEGIN",
            Self::Commit => "COMMIT",
            Self::End => "END TRANSACTION",
            Self::Rollback => "ROLLBACK",
            Self::Savepoint => "SAVEPOINT",
            Self::RollbackTo => "ROLLBACK TO SAVEPOINT",
            Self::Release => "RELEASE SAVEPOINT",
            Self::Pragma => "PRAGMA",
            Self::Attach => "ATTACH DATABASE",
            Self::Detach => "DETACH DATABASE",
            Self::Vacuum => "VACUUM",
            Self::Reindex => "REINDEX",
            Self::Analyze => "ANALYZE",
            Self::Explain => "EXPLAIN",
            Self::With => "WITH",
            Self::Values => "VALUES",
        }
    }

    pub fn description(self) -> &'static str {
        match self {
            Self::Select => "Spalten auswählen",
            Self::From => "Tabelle auswählen",
            Self::Join => "Tabelle verbinden · ON",
            Self::Where => "Zeilen filtern",
            Self::And | Self::Or => "Filter verknüpfen",
            Self::GroupBy => "Zeilen gruppieren",
            Self::Having => "Gruppen filtern",
            Self::Union | Self::Intersect | Self::Except => "Abfrageergebnisse verknüpfen",
            Self::OrderBy => "Ergebnis sortieren",
            Self::Limit => "Zeilen begrenzen",
            _ => "SQL-Befehl bearbeiten",
        }
    }

    pub fn default_input(self) -> &'static str {
        match self {
            Self::Select => "*",
            Self::From => "customers",
            Self::Join => "orders ON orders.customer_id = customers.id",
            Self::Where | Self::And | Self::Or => "city = 'Berlin'",
            Self::GroupBy => "city",
            Self::Having => "COUNT(*) > 1",
            Self::Union | Self::Intersect | Self::Except => "SELECT 1",
            Self::OrderBy => "name ASC",
            Self::Limit => "100",
            Self::Insert | Self::InsertOrReplace => "table_name (id) VALUES (1)",
            Self::Upsert => {
                "table_name (id, name) VALUES (1, 'Text') ON CONFLICT (id) DO UPDATE SET name = excluded.name"
            }
            Self::Update => "table_name SET name = 'Text' WHERE id = 1",
            Self::Delete => "table_name WHERE id = 1",
            Self::CreateTable => "table_name (id INTEGER PRIMARY KEY)",
            Self::CreateIndex => "index_name ON table_name (id)",
            Self::DropIndex => "IF EXISTS index_name",
            Self::CreateView => "view_name AS SELECT * FROM table_name",
            Self::DropView => "IF EXISTS view_name",
            Self::CreateTrigger => "trigger_name AFTER INSERT ON table_name BEGIN SELECT 1; END",
            Self::DropTrigger => "IF EXISTS trigger_name",
            Self::CreateVirtualTable => "table_name USING fts5(content)",
            Self::AlterTable => "table_name ADD COLUMN new_column TEXT",
            Self::Truncate => "table_name",
            Self::DropTable => "IF EXISTS table_name",
            Self::Begin => "DEFERRED TRANSACTION",
            Self::Commit
            | Self::End
            | Self::Rollback
            | Self::Vacuum
            | Self::Reindex
            | Self::Analyze => "",
            Self::Savepoint | Self::RollbackTo | Self::Release => "before_change",
            Self::Pragma => "table_info('table_name')",
            Self::Attach => "':memory:' AS attached",
            Self::Detach => "attached",
            Self::Explain => "QUERY PLAN SELECT 1",
            Self::With => "example AS (SELECT 1 AS value) SELECT value FROM example",
            Self::Values => "(1), (2)",
        }
    }

    pub(crate) fn rank(self) -> u8 {
        match self {
            Self::Select => 0,
            Self::From => 1,
            Self::Join => 2,
            Self::Where => 3,
            Self::And | Self::Or => 4,
            Self::GroupBy => 5,
            Self::Having => 6,
            Self::Union | Self::Intersect | Self::Except => 7,
            Self::OrderBy => 8,
            Self::Limit => 9,
            _ => 10,
        }
    }

    pub fn writes(self) -> bool {
        self.standalone() && !matches!(self, Self::Explain | Self::With | Self::Values)
    }

    pub(crate) fn standalone(self) -> bool {
        self.rank() == 10
    }

    pub(crate) fn optional_input(self) -> bool {
        matches!(
            self,
            Self::Begin
                | Self::Commit
                | Self::End
                | Self::Rollback
                | Self::Vacuum
                | Self::Reindex
                | Self::Analyze
        )
    }

    pub fn set_operation(self) -> bool {
        matches!(self, Self::Union | Self::Intersect | Self::Except)
    }

    pub(crate) fn repeatable(self) -> bool {
        self.standalone()
            || self.set_operation()
            || matches!(self, Self::Join | Self::And | Self::Or)
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Block {
    pub id: Uuid,
    pub kind: BlockKind,
    /// An editable SQLite expression, not a quoted literal.
    pub input: String,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub reporters: Vec<ReporterSlot>,
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub qualify_projection: bool,
}

impl Block {
    pub fn new(kind: BlockKind) -> Self {
        Self {
            id: Uuid::new_v4(),
            kind,
            input: kind.default_input().into(),
            reporters: Vec::new(),
            qualify_projection: kind == BlockKind::Select,
        }
    }

    pub fn edit_input(&mut self, range: std::ops::Range<usize>, value: &str) -> bool {
        if self.input.get(range.clone()).is_none()
            || self.input.len() - range.len() + value.len() > 16 * 1024
        {
            return false;
        }
        self.reporters.retain_mut(|slot| {
            if slot.range.end <= range.start {
                return true;
            }
            if slot.range.start < range.end {
                return false;
            }
            let start = range.start + value.len() + (slot.range.start - range.end);
            slot.range = start..start + slot.range.len();
            true
        });
        self.input.replace_range(range, value);
        true
    }

    pub fn set_reporter(&mut self, range: std::ops::Range<usize>, reporter: Reporter) -> bool {
        if !reporter.validate(0) {
            return false;
        }
        let sql = reporter.sql();
        let start = range.start;
        if sql.is_empty() || !self.edit_input(range, &sql) {
            return false;
        }
        self.reporters.push(ReporterSlot {
            range: start..start + sql.len(),
            reporter,
        });
        self.reporters.sort_by_key(|slot| slot.range.start);
        true
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
    #[serde(default, skip_serializing_if = "Workspace::is_default")]
    pub workspace: Workspace,
    #[serde(default, skip_serializing_if = "ProjectSettings::is_default")]
    pub settings: ProjectSettings,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default)]
pub struct ProjectSettings {
    pub autosave: bool,
}

impl Default for ProjectSettings {
    fn default() -> Self {
        Self { autosave: true }
    }
}

impl ProjectSettings {
    fn is_default(&self) -> bool {
        *self == Self::default()
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct CanvasPoint {
    pub x: i32,
    pub y: i32,
}

impl Default for CanvasPoint {
    fn default() -> Self {
        Self { x: 44, y: 30 }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DetachedBlock {
    pub block: Block,
    pub position: CanvasPoint,
}

#[derive(Debug, Default, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default)]
pub struct QueryLayout {
    pub name: String,
    pub origin: CanvasPoint,
    pub detached: Vec<DetachedBlock>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub chains: Vec<QueryChain>,
    #[serde(skip_serializing_if = "CanvasView::is_default")]
    pub view: CanvasView,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct QueryChain {
    pub origin: CanvasPoint,
    pub blocks: Vec<Block>,
}

impl QueryLayout {
    pub fn chains<'a>(
        &'a self,
        first: &'a [Block],
    ) -> impl Iterator<Item = (CanvasPoint, &'a [Block])> {
        std::iter::once((self.origin, first)).chain(
            self.chains
                .iter()
                .map(|chain| (chain.origin, chain.blocks.as_slice())),
        )
    }

    pub fn block_count(&self, first: &[Block]) -> usize {
        self.detached.len()
            + self
                .chains(first)
                .map(|(_, blocks)| blocks.len())
                .sum::<usize>()
    }

    pub fn blocks<'a>(&'a self, first: &'a [Block]) -> impl Iterator<Item = &'a Block> {
        self.chains(first)
            .flat_map(|(_, blocks)| blocks)
            .chain(self.detached.iter().map(|node| &node.block))
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default)]
pub struct CanvasView {
    pub pan_x: i32,
    pub pan_y: i32,
    pub zoom_milli: u16,
}

impl Default for CanvasView {
    fn default() -> Self {
        Self {
            pan_x: 0,
            pan_y: 0,
            zoom_milli: 1000,
        }
    }
}

impl CanvasView {
    fn is_default(&self) -> bool {
        *self == Self::default()
    }
}

#[derive(Debug, Default, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default)]
pub struct QueryTab {
    pub blocks: Vec<Block>,
    pub layout: QueryLayout,
}

#[derive(Debug, Default, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default)]
pub struct Workspace {
    pub first: QueryLayout,
    pub tabs: Vec<QueryTab>,
    pub active: usize,
    pub sample: bool,
    pub no_database: bool,
}

impl Workspace {
    fn is_default(&self) -> bool {
        *self == Self::default()
    }
}

impl Default for Project {
    fn default() -> Self {
        Self {
            format: FORMAT.into(),
            version: VERSION,
            name: "Meine erste Abfrage".into(),
            database: None,
            workspace: Workspace::default(),
            settings: ProjectSettings::default(),
            blocks: vec![
                Block {
                    input: "name, city, balance".into(),
                    ..Block::new(BlockKind::Select)
                },
                Block::new(BlockKind::From),
                Block::new(BlockKind::OrderBy),
                Block::new(BlockKind::Limit),
            ],
        }
    }
}

impl Project {
    pub fn showcase() -> Self {
        let block = |kind, input: &str| Block {
            input: input.into(),
            ..Block::new(kind)
        };
        Self {
            name: "NodeQL".into(),
            workspace: Workspace {
                sample: true,
                ..Workspace::default()
            },
            blocks: vec![
                block(BlockKind::Select, "*"),
                block(BlockKind::From, "Customers"),
                block(
                    BlockKind::Join,
                    "INNER Orders ON Customers.id = Orders.customer_id",
                ),
                block(BlockKind::OrderBy, "Customers.id ASC"),
            ],
            ..Self::default()
        }
    }

    pub fn query(&self, index: usize) -> (&[Block], &QueryLayout) {
        if index == 0 {
            (&self.blocks, &self.workspace.first)
        } else {
            let tab = &self.workspace.tabs[index - 1];
            (&tab.blocks, &tab.layout)
        }
    }

    pub fn active_query(&self) -> (&[Block], &QueryLayout) {
        self.query(self.workspace.active)
    }

    pub fn active_query_mut(&mut self) -> (&mut Vec<Block>, &mut QueryLayout) {
        if self.workspace.active == 0 {
            (&mut self.blocks, &mut self.workspace.first)
        } else {
            let tab = &mut self.workspace.tabs[self.workspace.active - 1];
            (&mut tab.blocks, &mut tab.layout)
        }
    }

    pub fn tab_count(&self) -> usize {
        self.workspace.tabs.len() + 1
    }

    /// Move a block to an insertion slot (0..=len), preserving its identity.
    pub fn move_block(&mut self, id: Uuid, slot: usize) -> bool {
        let (blocks, _) = self.active_query_mut();
        let Some(index) = blocks.iter().position(|block| block.id == id) else {
            return false;
        };
        let slot = slot.min(blocks.len());
        let target = if index < slot {
            slot.saturating_sub(1)
        } else {
            slot
        };
        if index == target {
            return false;
        }
        let block = blocks.remove(index);
        blocks.insert(target, block);
        true
    }
}
