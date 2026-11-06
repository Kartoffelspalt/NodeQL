use super::style::{Language, icon, rgb};
use crate::{
    model::BlockKind,
    reporter::{LiteralKind, Reporter},
};
use eframe::egui::Color32;
use serde::Deserialize;
use std::sync::LazyLock;

#[derive(Clone, Copy, Deserialize, PartialEq, Eq)]
pub enum Category {
    #[serde(rename = "queryLanguage")]
    Query,
    #[serde(rename = "dataTypes")]
    Types,
    #[serde(rename = "dml")]
    Changes,
    #[serde(rename = "ddl")]
    Schema,
    #[serde(rename = "txn")]
    Transactions,
    #[serde(rename = "database")]
    Database,
    #[serde(rename = "plugins")]
    Plugins,
}

impl Category {
    pub const ALL: [Self; 7] = [
        Self::Query,
        Self::Types,
        Self::Changes,
        Self::Schema,
        Self::Transactions,
        Self::Database,
        Self::Plugins,
    ];

    pub fn name(self, lang: Language) -> &'static str {
        match self {
            Self::Query => "Query Language",
            Self::Types => lang.pick("Datentypen", "Data types"),
            Self::Changes => lang.pick("Daten ändern", "Data manipulation"),
            Self::Schema => lang.pick("Schema", "Schema"),
            Self::Transactions => lang.pick("Transaktionen", "Transactions"),
            Self::Database => lang.pick("Datenbank", "Database"),
            Self::Plugins => "Plugins",
        }
    }

    pub fn visual(self) -> (char, Color32) {
        match self {
            Self::Query => (icon::CODE, rgb(0x3f83fe)),
            Self::Types => (icon::DATA, rgb(0x5cb1d6)),
            Self::Changes => (icon::EDIT_NOTE, rgb(0xffab19)),
            Self::Schema => (icon::SCHEMA, rgb(0x59c059)),
            Self::Transactions => (icon::TREE, rgb(0xff8c1a)),
            Self::Database => (icon::STORAGE, rgb(0x1b645b)),
            Self::Plugins => (icon::EXTENSION, rgb(0xff6680)),
        }
    }
}

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum Action {
    Trigger,
    Clause(BlockKind),
    Expression(Preset),
    Unavailable,
}

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum Preset {
    Literal(LiteralKind, &'static str),
    Function(&'static str, &'static str),
    Column,
    Alias,
    InQuery,
    Raw(&'static str),
}

impl Preset {
    pub fn create(self) -> Reporter {
        match self {
            Self::Literal(kind, value) => Reporter::Literal {
                kind,
                value: value.into(),
            },
            Self::Function(name, argument) => Reporter::Function {
                name: name.into(),
                arguments: vec![Reporter::expression(argument)],
            },
            Self::Column => Reporter::expression("id"),
            Self::Alias => Reporter::Alias {
                expression: Box::new(Reporter::expression("id")),
                name: "alias".into(),
            },
            Self::InQuery => Reporter::InQuery {
                column: Box::new(Reporter::expression("id")),
                query: "SELECT id FROM table_name".into(),
            },
            Self::Raw(value) => Reporter::expression(value),
        }
    }
}

#[derive(Deserialize)]
pub struct Function {
    pub name: String,
    pub category: String,
    pub min: usize,
    pub max: Option<usize>,
    pub arguments: Vec<String>,
    pub version_dependent: bool,
}

pub static FUNCTIONS: LazyLock<Vec<Function>> = LazyLock::new(|| {
    serde_json::from_str(include_str!("../../assets/ui/sqlite-functions.json"))
        .expect("Bundled SQLite function catalog")
});

#[derive(Deserialize)]
pub struct Item {
    pub key: String,
    pub category: Category,
    advanced: String,
    german: String,
    english: String,
    description_de: String,
    description_en: String,
}

impl Item {
    pub fn label(&self, advanced: bool, lang: Language) -> &str {
        if advanced {
            &self.advanced
        } else {
            lang.pick(&self.german, &self.english)
        }
    }

    pub fn description(&self, lang: Language) -> &str {
        lang.pick(&self.description_de, &self.description_en)
    }

    pub fn action(&self) -> Action {
        use Action::{Clause, Expression, Trigger, Unavailable};
        match self.key.as_str() {
            "eventGreenFlag" => Trigger,
            "sqlSelect" => Clause(BlockKind::Select),
            "sqlFrom" => Clause(BlockKind::From),
            "sqlJoin" => Clause(BlockKind::Join),
            "sqlWhere" => Clause(BlockKind::Where),
            "sqlAnd" => Clause(BlockKind::And),
            "sqlOr" => Clause(BlockKind::Or),
            "sqlGroupBy" => Clause(BlockKind::GroupBy),
            "sqlHaving" => Clause(BlockKind::Having),
            "sqlOrderBy" => Clause(BlockKind::OrderBy),
            "sqlLimit" => Clause(BlockKind::Limit),
            "sqlUnion" => Clause(BlockKind::Union),
            "sqlIntersect" => Clause(BlockKind::Intersect),
            "sqlExcept" => Clause(BlockKind::Except),
            "sqlInsert" => Clause(BlockKind::Insert),
            "sqlInsertOrReplace" => Clause(BlockKind::InsertOrReplace),
            "sqlUpsert" => Clause(BlockKind::Upsert),
            "sqlUpdate" => Clause(BlockKind::Update),
            "sqlDelete" => Clause(BlockKind::Delete),
            "sqlCreateTable" => Clause(BlockKind::CreateTable),
            "sqlCreateIndex" => Clause(BlockKind::CreateIndex),
            "sqlDropIndex" => Clause(BlockKind::DropIndex),
            "sqlCreateView" => Clause(BlockKind::CreateView),
            "sqlDropView" => Clause(BlockKind::DropView),
            "sqlCreateTrigger" => Clause(BlockKind::CreateTrigger),
            "sqlDropTrigger" => Clause(BlockKind::DropTrigger),
            "sqlCreateVirtualTable" => Clause(BlockKind::CreateVirtualTable),
            "sqlAlterTable" => Clause(BlockKind::AlterTable),
            "sqlTruncate" => Clause(BlockKind::Truncate),
            "sqlDropTable" => Clause(BlockKind::DropTable),
            "sqlBeginTransaction" => Clause(BlockKind::Begin),
            "sqlCommit" => Clause(BlockKind::Commit),
            "sqlEndTransaction" => Clause(BlockKind::End),
            "sqlRollback" => Clause(BlockKind::Rollback),
            "sqlSavepoint" => Clause(BlockKind::Savepoint),
            "sqlRollbackToSavepoint" => Clause(BlockKind::RollbackTo),
            "sqlReleaseSavepoint" => Clause(BlockKind::Release),
            "sqlPragma" => Clause(BlockKind::Pragma),
            "sqlAttachDatabase" => Clause(BlockKind::Attach),
            "sqlDetachDatabase" => Clause(BlockKind::Detach),
            "sqlVacuum" => Clause(BlockKind::Vacuum),
            "sqlReindex" => Clause(BlockKind::Reindex),
            "sqlAnalyze" => Clause(BlockKind::Analyze),
            "sqlExplain" => Clause(BlockKind::Explain),
            "sqlWith" => Clause(BlockKind::With),
            "sqlValues" => Clause(BlockKind::Values),
            "sqlCount" => Expression(Preset::Function("count", "*")),
            "sqlSum" => Expression(Preset::Function("sum", "0")),
            "sqlAvg" => Expression(Preset::Function("avg", "0")),
            "sqlMin" => Expression(Preset::Function("min", "0")),
            "sqlMax" => Expression(Preset::Function("max", "0")),
            "sqlFunction" => Expression(Preset::Function("abs", "0")),
            "sqlUpper" => Expression(Preset::Function("upper", "'text'")),
            "sqlColumn" => Expression(Preset::Column),
            "sqlAlias" => Expression(Preset::Alias),
            "sqlSubqueryIn" => Expression(Preset::InQuery),
            "sqlCase" => Expression(Preset::Raw("CASE WHEN 1 = 1 THEN 1 ELSE 0 END")),
            "null" => Expression(Preset::Literal(LiteralKind::Null, "")),
            "integer" => Expression(Preset::Literal(LiteralKind::Integer, "1")),
            "real" => Expression(Preset::Literal(LiteralKind::Real, "1.0")),
            "text" => Expression(Preset::Literal(LiteralKind::Text, "Text")),
            "blob" => Expression(Preset::Literal(LiteralKind::Blob, "00")),
            _ => Unavailable,
        }
    }

    pub fn color(&self) -> Color32 {
        match self.action() {
            Action::Trigger => rgb(0xfbb100),
            Action::Clause(kind) => block_color(kind),
            Action::Expression(_) => rgb(0x6d28d9),
            Action::Unavailable => rgb(match self.category {
                Category::Changes => 0xb45309,
                Category::Schema => 0xbe185d,
                Category::Database | Category::Transactions => 0xb91c1c,
                _ => 0x4338ca,
            }),
        }
    }
}

pub fn block_color(kind: BlockKind) -> Color32 {
    rgb(match kind {
        BlockKind::Select => 0x1c4dea,
        BlockKind::From => 0x1b645b,
        BlockKind::Join => 0x6423e8,
        BlockKind::GroupBy | BlockKind::Having => 0x15803d,
        BlockKind::Insert
        | BlockKind::InsertOrReplace
        | BlockKind::Upsert
        | BlockKind::Update
        | BlockKind::Delete => 0xb45309,
        BlockKind::Begin
        | BlockKind::Commit
        | BlockKind::End
        | BlockKind::Rollback
        | BlockKind::Savepoint
        | BlockKind::RollbackTo
        | BlockKind::Release => 0xb91c1c,
        BlockKind::Pragma
        | BlockKind::Attach
        | BlockKind::Detach
        | BlockKind::Vacuum
        | BlockKind::Reindex
        | BlockKind::Analyze => 0x1b645b,
        kind if kind.writes() => 0xbe185d,
        kind if kind.set_operation() => 0x4338ca,
        _ => 0x1571bd,
    })
}

pub static ITEMS: LazyLock<Vec<Item>> = LazyLock::new(|| {
    serde_json::from_str(include_str!("../../assets/ui/catalog.json"))
        .expect("Bundled NodeQL command catalog")
});
