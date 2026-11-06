use super::{
    Command, EditorHistory, NodeQlApp,
    blocks::Canvas,
    catalog::{Action, Category, ITEMS, Preset},
    dialogs::Dialog,
    style::Language,
};
use crate::{
    database::{QueryResult, Table},
    model::{Block, BlockKind, Project},
    reporter::{LiteralKind, Reporter},
};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::{collections::BTreeSet, path::PathBuf, sync::LazyLock};

#[derive(Deserialize)]
pub struct Catalog {
    pub paths: Vec<Course>,
}

#[derive(Deserialize)]
pub struct Course {
    pub id: String,
    pub title: Bilingual,
    pub description: Bilingual,
    pub steps: Vec<Lesson>,
}

#[derive(Deserialize)]
pub struct Bilingual {
    de: String,
    en: String,
}
impl Bilingual {
    pub fn at(&self, language: Language) -> &str {
        language.pick(&self.de, &self.en)
    }
}

#[derive(Deserialize)]
pub struct Lesson {
    pub id: String,
    pub title: String,
    pub instruction: String,
    pub hint: String,
    pub mode: String,
    pub nodes: Vec<LessonNode>,
}

#[derive(Deserialize)]
pub struct LessonNode {
    #[serde(rename = "type")]
    kind: String,
    #[serde(default)]
    defaults: Value,
}

impl LessonNode {
    pub fn label(&self, advanced: bool, language: Language) -> &str {
        self.item()
            .map_or(self.kind.as_str(), |item| item.label(advanced, language))
    }
    pub fn key(&self) -> &str {
        match self.kind.as_str() {
            "sqlText" => self.defaults["literal_type"].as_str().unwrap_or("text"),
            "sqlLeftJoin" | "sqlRightJoin" | "sqlInnerJoin" | "sqlFullJoin" => "sqlJoin",
            kind => kind,
        }
    }

    fn literal(&self) -> Option<Reporter> {
        if self.kind != "sqlText" {
            return None;
        }
        let kind = match self.key() {
            "integer" => LiteralKind::Integer,
            "real" => LiteralKind::Real,
            "blob" => LiteralKind::Blob,
            "null" => LiteralKind::Null,
            _ => LiteralKind::Text,
        };
        Some(Reporter::Literal {
            kind,
            value: self.defaults["text"].as_str().unwrap_or_default().into(),
        })
    }

    fn item(&self) -> Option<&'static super::catalog::Item> {
        ITEMS.iter().find(|item| item.key == self.key())
    }

    fn statement(&self) -> Option<Vec<Block>> {
        let mut inputs = self.defaults.as_object().cloned().unwrap_or_default();
        for key in ["value", "where_value"] {
            if inputs.get(key).and_then(Value::as_str) == Some("") {
                inputs.insert(key.into(), Value::String("NULL".into()));
            }
        }
        if inputs.get("values").and_then(Value::as_str) == Some("") {
            let count = inputs
                .get("columns")
                .and_then(Value::as_str)
                .unwrap_or("id")
                .split(',')
                .count();
            inputs.insert(
                "values".into(),
                Value::String(vec!["NULL"; count].join(", ")),
            );
        }
        crate::flutter_project::statement(&serde_json::json!({ "type":self.kind, "inputs":inputs }))
            .ok()
    }

    fn present(&self, project: &Project) -> bool {
        let (blocks, layout) = project.active_query();
        match self.item().map(|item| item.action()) {
            Some(Action::Trigger) => true,
            Some(Action::Clause(kind)) => layout.blocks(blocks).any(|block| {
                block.kind == kind
                    && (self.kind != "sqlLeftJoin"
                        || block.input.to_ascii_uppercase().starts_with("LEFT "))
                    && (kind != BlockKind::From
                        || self.defaults["table"].as_str().is_none_or(|name| {
                            name.eq_ignore_ascii_case(block.input.trim_matches('"'))
                        }))
            }),
            Some(Action::Expression(preset)) => {
                let required = self.literal().unwrap_or_else(|| preset.create());
                layout
                    .blocks(blocks)
                    .flat_map(|block| &block.reporters)
                    .any(|slot| contains_reporter(&slot.reporter, &required))
            }
            _ => false,
        }
    }
}

fn contains_reporter(reporter: &Reporter, required: &Reporter) -> bool {
    if reporter == required {
        return true;
    }
    match reporter {
        Reporter::Function { name, arguments } => {
            matches!(required, Reporter::Function { name: required, .. } if name.eq_ignore_ascii_case(required))
                || arguments
                    .iter()
                    .any(|argument| contains_reporter(argument, required))
        }
        Reporter::Alias { expression, .. } => contains_reporter(expression, required),
        Reporter::InQuery { column, .. } => contains_reporter(column, required),
        Reporter::List { items } => items.iter().any(|item| contains_reporter(item, required)),
        _ => false,
    }
}

pub static WORKSHOP: LazyLock<Catalog> = LazyLock::new(|| {
    serde_json::from_str(include_str!("../../assets/ui/workshops.json"))
        .expect("Bundled NodeQL learning paths")
});

#[derive(Clone, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct Progress {
    pub step: String,
    pub completed: BTreeSet<String>,
    pub workspace: Option<Project>,
}

pub struct MainWorkbench {
    pub project: Project,
    pub path: Option<PathBuf>,
    pub dirty: bool,
    pub advanced: bool,
    schema: Vec<Table>,
    database_available: bool,
    result: Option<QueryResult>,
    result_sql: String,
    error: Option<String>,
    status: String,
    canvas: Canvas,
    history: EditorHistory,
    sql_editor: Option<String>,
    category: Category,
    search: String,
}

pub struct Practice {
    pub main: MainWorkbench,
    pub course: usize,
    pub step: usize,
    pub completed: BTreeSet<String>,
    pub show_hint: bool,
}

impl Practice {
    pub fn course(&self) -> &'static Course {
        &WORKSHOP.paths[self.course]
    }
    pub fn lesson(&self) -> &'static Lesson {
        &self.course().steps[self.step]
    }
}

impl NodeQlApp {
    pub(super) fn begin_practice(&mut self, course: usize, repeat: bool) {
        if self.busy {
            return;
        }
        let definition = &WORKSHOP.paths[course];
        self.store_practice();
        let progress = (!repeat)
            .then(|| self.session.lessons.get(&definition.id).cloned())
            .flatten()
            .unwrap_or_default();
        let step = definition
            .steps
            .iter()
            .position(|lesson| lesson.id == progress.step)
            .unwrap_or_default();
        let mut workspace = progress
            .workspace
            .filter(|workspace| crate::project::validate(workspace).is_ok())
            .unwrap_or_else(|| Project {
                name: definition.id.clone(),
                blocks: Vec::new(),
                ..Project::default()
            });
        workspace.database = None;
        if let Some(practice) = &mut self.practice {
            practice.course = course;
            practice.step = step;
            practice.completed = progress.completed;
            practice.show_hint = false;
            self.project = workspace;
            self.result = None;
            self.result_sql.clear();
            self.error = None;
            self.sql_editor = None;
        } else {
            self.flush_session();
            let main = MainWorkbench {
                project: std::mem::replace(&mut self.project, workspace),
                path: self.path.take(),
                dirty: self.dirty,
                advanced: self.advanced,
                schema: std::mem::take(&mut self.schema),
                database_available: self.database_available,
                result: self.result.take(),
                result_sql: std::mem::take(&mut self.result_sql),
                error: self.error.take(),
                status: std::mem::take(&mut self.status),
                canvas: std::mem::take(&mut self.canvas),
                history: std::mem::take(&mut self.history),
                sql_editor: self.sql_editor.take(),
                category: self.category,
                search: std::mem::take(&mut self.search),
            };
            self.practice = Some(Practice {
                main,
                course,
                step,
                completed: progress.completed,
                show_hint: false,
            });
        }
        self.dirty = false;
        self.database_available = false;
        self.browser_table = None;
        self.browser_result = None;
        self.preview_at = None;
        self.prepare_practice_step();
        self.send(Command::Practice(true));
    }

    pub(super) fn restore_main_workbench(&mut self) {
        self.store_practice();
        if let Some(practice) = self.practice.take() {
            let main = practice.main;
            self.project = main.project;
            self.path = main.path;
            self.dirty = main.dirty;
            self.advanced = main.advanced;
            self.schema = main.schema;
            self.database_available = main.database_available;
            self.result = main.result;
            self.result_sql = main.result_sql;
            self.error = main.error;
            self.status = main.status;
            self.canvas = main.canvas;
            self.history = main.history;
            self.sql_editor = main.sql_editor;
            self.category = main.category;
            self.search = main.search;
            self.preview_at = None;
            self.browser_table = None;
            self.browser_result = None;
            self.field_editor = None;
            self.dialog = None;
        }
    }

    pub(super) fn leave_practice(&mut self) {
        if !self.busy {
            self.restore_main_workbench();
            self.send(Command::Practice(false));
            self.flush_session();
        }
    }

    pub(super) fn practice_target(&self) -> Option<&'static LessonNode> {
        self.practice
            .as_ref()?
            .lesson()
            .nodes
            .iter()
            .find(|node| !node.present(&self.project))
    }

    pub(super) fn authored_blocks(&self, action: Action) -> Option<Vec<Block>> {
        let target = self.practice_target()?;
        if target.item()?.action() != action {
            return None;
        }
        target.statement()
    }

    pub(super) fn authored_reporter(&self, preset: Preset) -> Reporter {
        self.practice_target()
            .filter(|node| {
                node.item()
                    .is_some_and(|item| item.action() == Action::Expression(preset))
            })
            .and_then(LessonNode::literal)
            .unwrap_or_else(|| preset.create())
    }

    fn prepare_practice_step(&mut self) {
        let Some(practice) = &self.practice else {
            return;
        };
        let lesson = practice.lesson();
        self.advanced = lesson.mode == "advanced";
        if self.project.blocks.is_empty()
            && lesson.nodes.iter().any(|node| {
                matches!(
                    node.item().map(|item| item.action()),
                    Some(
                        Action::Expression(_)
                            | Action::Clause(
                                BlockKind::Where | BlockKind::OrderBy | BlockKind::Join
                            )
                    )
                )
            })
            && !lesson.nodes.iter().any(|node| node.kind == "sqlSelect")
        {
            self.project.blocks = vec![Block::new(BlockKind::Select), Block::new(BlockKind::From)];
        }
        self.canvas.load(self.project.active_query().1.view);
        self.reset_history();
        self.follow_practice_target();
    }

    pub(super) fn follow_practice_target(&mut self) {
        if let Some(item) = self.practice_target().and_then(LessonNode::item) {
            self.category = item.category;
            self.search.clear();
        }
    }

    pub(super) fn finish_practice_step(&mut self) {
        if self.practice_target().is_some() {
            return;
        }
        let Some(practice) = &mut self.practice else {
            return;
        };
        practice.completed.insert(practice.lesson().id.clone());
        if practice.step + 1 == practice.course().steps.len() {
            self.dialog = Some(Dialog::Workshop);
        } else {
            practice.step += 1;
            practice.show_hint = false;
            self.prepare_practice_step();
        }
        self.flush_session();
    }

    pub(super) fn store_practice(&mut self) {
        if let Some(practice) = &self.practice {
            self.session.lessons.insert(
                practice.course().id.clone(),
                Progress {
                    step: practice.lesson().id.clone(),
                    completed: practice.completed.clone(),
                    workspace: Some(self.project.clone()),
                },
            );
        }
    }
}
