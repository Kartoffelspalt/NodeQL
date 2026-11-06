use crate::{
    compiler,
    database::{Database, QueryResult, Table, TablePage},
    export,
    model::{self, Project},
    project,
};
use eframe::egui;
use std::{
    collections::VecDeque,
    path::PathBuf,
    sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
        mpsc::{self, Receiver, Sender},
    },
    thread,
    time::{Instant, SystemTime},
};
mod blocks;
mod catalog;
mod dialogs;
mod screen;
mod session;
mod style;
mod workshop;

use blocks::{Canvas, FieldEditor};
use catalog::Category;
use dialogs::Dialog;
use style::{Dock, Language, Theme};

#[derive(Clone, Copy)]
enum QueryTarget {
    Workspace(u64),
    TableEditor,
}

enum DatabaseSource {
    Project(Option<PathBuf>, bool),
    Empty,
    Import(PathBuf),
    Create(PathBuf),
}

enum Command {
    Connect(DatabaseSource),
    Query(String, QueryTarget, bool),
    Inspect(String, usize),
    Practice(bool),
}

struct ConnectionInfo {
    schema: Vec<Table>,
    path: Option<PathBuf>,
    issue: Option<String>,
}

enum Event {
    Connected(Result<ConnectionInfo, String>),
    Practice(Result<Vec<Table>, String>),
    Inspected(Result<TablePage, String>),
    Queried {
        sql: String,
        target: QueryTarget,
        result: Result<QueryResult, String>,
        schema: Option<Vec<Table>>,
    },
}

struct PendingConnection {
    project: Project,
    path: Option<PathBuf>,
    dirty: bool,
}

#[derive(Default)]
struct EditorHistory {
    current: model::QueryTab,
    undo: VecDeque<model::QueryTab>,
    redo: Vec<model::QueryTab>,
}

impl EditorHistory {
    fn record(&mut self, snapshot: model::QueryTab) {
        if self.current != snapshot {
            if self.undo.len() == 40 {
                self.undo.pop_front();
            }
            self.undo
                .push_back(std::mem::replace(&mut self.current, snapshot));
            self.redo.clear();
        }
    }

    fn undo(&mut self) -> Option<model::QueryTab> {
        let previous = self.undo.pop_back()?;
        self.redo
            .push(std::mem::replace(&mut self.current, previous.clone()));
        Some(previous)
    }

    fn redo(&mut self) -> Option<model::QueryTab> {
        let next = self.redo.pop()?;
        self.undo
            .push_back(std::mem::replace(&mut self.current, next.clone()));
        Some(next)
    }
}

pub struct NodeQlApp {
    project: Project,
    path: Option<PathBuf>,
    dirty: bool,
    schema: Vec<Table>,
    session: session::Session,
    saved_modified: Option<SystemTime>,
    database_available: bool,
    result: Option<QueryResult>,
    result_sql: String,
    tab_revision: u64,
    error: Option<String>,
    status: String,
    busy: bool,
    pending: Option<PendingConnection>,
    cancel: Arc<AtomicBool>,
    commands: Sender<Command>,
    events: Receiver<Event>,
    allow_close: bool,
    theme: Theme,
    language: Language,
    advanced: bool,
    category: Category,
    search: String,
    dock: Dock,
    palette_width: f32,
    runtime_width: f32,
    split: f32,
    link_mode: bool,
    logo: egui::TextureHandle,
    canvas: Canvas,
    history: EditorHistory,
    dialog: Option<Dialog>,
    field_editor: Option<FieldEditor>,
    sql_editor: Option<String>,
    live_preview: bool,
    preview_at: Option<Instant>,
    browser_table: Option<String>,
    browser_result: Option<TablePage>,
    table_edit_result: Option<Result<(), String>>,
    practice: Option<workshop::Practice>,
}

impl NodeQlApp {
    pub fn new(context: &eframe::CreationContext<'_>) -> Self {
        Self::create_with_session(
            context.egui_ctx.clone(),
            session::Session::open(application_data_directory()),
        )
    }

    #[cfg(test)]
    fn create(ctx: egui::Context) -> Self {
        Self::create_with_session(ctx, session::Session::default())
    }

    fn create_with_session(ctx: egui::Context, session: session::Session) -> Self {
        style::install_fonts(&ctx);
        let settings = session.preferences;
        settings.theme.apply(&ctx);
        let logo = style::texture(&ctx);
        let (commands, incoming) = mpsc::channel();
        let (outgoing, events) = mpsc::channel();
        let cancel = Arc::new(AtomicBool::new(false));
        let cancellation = cancel.clone();
        thread::spawn(move || {
            let mut database: Option<Database> = None;
            let mut practice: Option<Database> = None;
            while let Ok(command) = incoming.recv() {
                let event = match command {
                    Command::Inspect(name, page) => Event::Inspected(
                        practice
                            .as_mut()
                            .or(database.as_mut())
                            .ok_or_else(|| "Keine Datenbank geöffnet.".to_owned())
                            .and_then(|database| {
                                database
                                    .inspect(&name, page, cancellation.clone())
                                    .map_err(|error| error.to_string())
                            }),
                    ),
                    Command::Practice(start) => {
                        practice = None;
                        let result = if start {
                            Database::workshop().and_then(|opened| {
                                let schema = opened.schema()?;
                                practice = Some(opened);
                                Ok(schema)
                            })
                        } else {
                            Ok(Vec::new())
                        };
                        Event::Practice(result.map_err(|error| error.to_string()))
                    }
                    Command::Connect(source) => Event::Connected(
                        open_source(source)
                            .map(|(opened, info)| {
                                database = opened;
                                info
                            })
                            .map_err(|error| error.to_string()),
                    ),
                    Command::Query(sql, target, explicit) => {
                        let mut schema = None;
                        let result = practice
                            .as_mut()
                            .or(database.as_mut())
                            .ok_or_else(|| "Keine Datenbank geöffnet.".to_owned())
                            .and_then(|database| {
                                if explicit {
                                    let result = database.execute(&sql, cancellation.clone());
                                    if result.is_ok() {
                                        schema = database.schema().ok();
                                    }
                                    result
                                } else {
                                    database.preview(&sql, cancellation.clone())
                                }
                                .map_err(|error| error.to_string())
                            });
                        Event::Queried {
                            sql,
                            target,
                            result,
                            schema,
                        }
                    }
                };
                if outgoing.send(event).is_err() {
                    break;
                }
                ctx.request_repaint();
            }
        });
        let resume = session.resume();
        let mut app = Self {
            project: Project::showcase(),
            path: None,
            dirty: false,
            schema: Vec::new(),
            session,
            saved_modified: None,
            database_available: false,
            result: None,
            result_sql: String::new(),
            tab_revision: 0,
            error: None,
            status: "Demo wird geöffnet …".into(),
            busy: false,
            pending: None,
            cancel,
            commands,
            events,
            allow_close: false,
            theme: settings.theme,
            language: settings.language,
            advanced: settings.advanced,
            category: Category::Query,
            search: String::new(),
            dock: settings.dock,
            palette_width: settings.palette_width.clamp(200.0, 520.0),
            runtime_width: settings.runtime_width.clamp(260.0, 720.0),
            split: settings.split.clamp(0.15, 0.85),
            link_mode: false,
            logo,
            canvas: Canvas::default(),
            history: EditorHistory::default(),
            dialog: None,
            field_editor: None,
            sql_editor: None,
            live_preview: settings.live_preview,
            preview_at: None,
            browser_table: None,
            browser_result: None,
            table_edit_result: None,
            practice: None,
        };
        let (project, path, dirty) = resume.unwrap_or_else(|| (Project::showcase(), None, false));
        app.connect(project, path, dirty);
        app
    }

    fn send(&mut self, command: Command) {
        if self.commands.send(command).is_err() {
            self.busy = false;
            self.pending = None;
            self.error =
                Some("Der Datenbank-Thread wurde beendet. Bitte die Anwendung neu starten.".into());
        } else {
            self.busy = true;
        }
    }

    fn connect(&mut self, project: Project, path: Option<PathBuf>, dirty: bool) {
        let source = if project.workspace.no_database && project.database.is_none() {
            DatabaseSource::Empty
        } else {
            DatabaseSource::Project(project.database.clone(), project.workspace.sample)
        };
        self.connect_source(project, path, dirty, source);
    }

    fn connect_source(
        &mut self,
        project: Project,
        path: Option<PathBuf>,
        dirty: bool,
        source: DatabaseSource,
    ) {
        self.pending = Some(PendingConnection {
            project,
            path,
            dirty,
        });
        self.error = None;
        self.status = "Datenbank wird geöffnet …".into();
        self.send(Command::Connect(source));
    }

    fn poll(&mut self) {
        let events = self.events.try_iter().collect::<Vec<_>>();
        for event in events {
            self.busy = false;
            match event {
                Event::Inspected(result) => match result {
                    Ok(page) => self.browser_result = Some(page),
                    Err(error) => self.error = Some(error),
                },
                Event::Practice(result) => match result {
                    Ok(schema) if self.practice.is_some() => {
                        self.schema = schema;
                        self.database_available = true;
                        self.preview();
                    }
                    Ok(_) => {}
                    Err(error) => {
                        self.restore_main_workbench();
                        self.error = Some(error);
                    }
                },
                Event::Connected(result) => {
                    let pending = self.pending.take();
                    match result {
                        Ok(info) => {
                            if let Some(pending) = pending {
                                self.project = pending.project;
                                self.project.database = info.path;
                                if self.project.database.is_some() {
                                    self.project.workspace.no_database = false;
                                }
                                self.path = pending.path;
                                self.dirty = pending.dirty;
                                self.canvas.load(self.project.active_query().1.view);
                                self.reset_history();
                                self.capture_saved_version();
                                self.set_session_project();
                                self.sql_editor = None;
                                self.browser_table = None;
                                self.browser_result = None;
                                self.preview_at = None;
                            }
                            self.schema = info.schema;
                            self.database_available = info.issue.is_none();
                            self.error = info.issue;
                            self.result = None;
                            self.result_sql.clear();
                            self.status = "Datenbank geöffnet".into();
                            self.preview();
                        }
                        Err(error) => {
                            self.error = Some(error);
                            self.status = "Öffnen fehlgeschlagen".into();
                        }
                    }
                }
                Event::Queried {
                    sql,
                    target,
                    result,
                    schema,
                } => {
                    if let Some(schema) = schema {
                        self.schema = schema;
                        self.browser_table = None;
                        self.browser_result = None;
                    }
                    match target {
                        QueryTarget::TableEditor => {
                            self.table_edit_result = Some(result.map(|_| ()));
                        }
                        QueryTarget::Workspace(revision) if revision == self.tab_revision => {
                            match result {
                                Ok(result) => {
                                    self.status = if result.columns.is_empty() {
                                        "SQLite-Befehl ausgeführt".into()
                                    } else {
                                        format!(
                                            "{} Zeilen · {:.1} ms",
                                            result.rows.len(),
                                            result.elapsed.as_secs_f64() * 1000.0
                                        )
                                    };
                                    self.result_sql = sql;
                                    self.result = Some(result);
                                }
                                Err(error) => {
                                    self.error = Some(error);
                                    self.status = "Abfrage beendet".into();
                                }
                            }
                        }
                        QueryTarget::Workspace(_) => {}
                    }
                }
            }
        }
    }

    fn compiled(&self) -> Result<String, Vec<compiler::Diagnostic>> {
        self.compiled_details().map(|compiled| compiled.sql)
    }

    fn compiled_details(&self) -> Result<compiler::Compiled, Vec<compiler::Diagnostic>> {
        let mut chains = (0..self.project.tab_count())
            .flat_map(|index| {
                let (blocks, layout) = self.project.query(index);
                layout.chains(blocks).map(|(_, chain)| chain)
            })
            .filter(|blocks| !blocks.is_empty());
        let mut program = compiler::compile_with_spans(chains.next().unwrap_or_default())?;
        for chain in chains {
            program.extend(compiler::compile_with_spans(chain)?);
        }
        Ok(program)
    }

    fn visible_sql(&self) -> Result<String, Vec<compiler::Diagnostic>> {
        if let Some(sql) = &self.sql_editor {
            Ok(sql.clone())
        } else {
            self.compiled()
        }
    }

    fn run(&mut self) {
        if let Ok(sql) = self.visible_sql() {
            self.run_sql(sql, QueryTarget::Workspace(self.tab_revision), true);
        }
    }

    fn preview(&mut self) {
        if self.database_available
            && self.live_preview
            && self.sql_editor.is_none()
            && !self.requires_manual_run()
            && let Ok(sql) = self.compiled()
        {
            self.run_sql(sql, QueryTarget::Workspace(self.tab_revision), false);
        }
    }

    fn requires_manual_run(&self) -> bool {
        (0..self.project.tab_count()).any(|index| {
            let (blocks, layout) = self.project.query(index);
            layout
                .chains(blocks)
                .flat_map(|(_, chain)| chain)
                .any(|block| block.kind.writes())
        })
    }

    fn run_sql(&mut self, sql: String, target: QueryTarget, explicit: bool) {
        if self.busy || sql.trim().is_empty() {
            return;
        }
        self.error = None;
        match target {
            QueryTarget::Workspace(_) => {
                self.result = None;
                self.preview_at = None;
            }
            QueryTarget::TableEditor => self.table_edit_result = None,
        }
        self.cancel.store(false, Ordering::Relaxed);
        self.status = "Abfrage läuft …".into();
        self.send(Command::Query(sql, target, explicit));
    }

    fn changed(&mut self) {
        self.history.record(self.editor_snapshot());
        self.mark_dirty();
        self.follow_practice_target();
    }

    fn mark_dirty(&mut self) {
        self.dirty = true;
        self.session.schedule();
        if self.live_preview && self.sql_editor.is_none() {
            self.preview_at = Some(Instant::now() + std::time::Duration::from_millis(250));
        }
    }

    fn editor_snapshot(&self) -> model::QueryTab {
        let (blocks, layout) = self.project.active_query();
        let mut layout = layout.clone();
        layout.name.clear();
        model::QueryTab {
            blocks: blocks.to_vec(),
            layout,
        }
    }

    fn reset_history(&mut self) {
        self.history = EditorHistory {
            current: self.editor_snapshot(),
            ..Default::default()
        };
    }

    fn restore_edit(&mut self, redo: bool) {
        let snapshot = if redo {
            self.history.redo()
        } else {
            self.history.undo()
        };
        if let Some(mut snapshot) = snapshot {
            let (blocks, layout) = self.project.active_query_mut();
            snapshot.layout.name.clone_from(&layout.name);
            *blocks = snapshot.blocks;
            *layout = snapshot.layout;
            self.canvas.load(layout.view);
            self.mark_dirty();
        }
    }

    fn save_canvas_view(&mut self) {
        if self.pending.is_some() {
            return;
        }
        let view = self.canvas.view();
        let layout = self.project.active_query_mut().1;
        if layout.view != view {
            layout.view = view;
            self.history.current.layout.view = view;
            self.dirty = true;
            self.session.schedule();
        }
    }

    fn refresh_preview(&mut self, ctx: &egui::Context) {
        if self.busy {
            return;
        }
        if let Some(at) = self.preview_at {
            let delay = at.saturating_duration_since(Instant::now());
            if delay.is_zero() {
                self.preview_at = None;
                if self.compiled().is_ok_and(|sql| sql != self.result_sql) {
                    self.preview();
                }
            } else {
                ctx.request_repaint_after(delay);
            }
        }
    }

    fn save(&mut self, save_as: bool) -> bool {
        let path = if save_as || self.path.is_none() {
            rfd::FileDialog::new()
                .set_title("Rust-Projekt speichern")
                .add_filter("NodeQL Rust", &["json"])
                .set_file_name("projekt.nodeql-rust.json")
                .save_file()
        } else {
            self.path.clone()
        };
        let Some(path) = path else {
            return false;
        };
        match project::save(&path, &self.project) {
            Ok(()) => {
                self.path = Some(path);
                self.dirty = false;
                self.capture_saved_version();
                self.set_session_project();
                self.flush_session();
                self.status = "Projekt gespeichert".into();
                true
            }
            Err(error) => {
                self.error = Some(error.to_string());
                false
            }
        }
    }

    fn can_discard(&mut self) -> bool {
        if !self.dirty {
            return true;
        }
        match rfd::MessageDialog::new().set_title("Änderungen speichern?")
            .set_description("Dieses Rust-Projekt enthält ungespeicherte Änderungen. Vor dem Fortfahren speichern?\nJa: speichern · Nein: verwerfen · Abbrechen: zurück")
            .set_buttons(rfd::MessageButtons::YesNoCancel).show()
        {
            rfd::MessageDialogResult::Yes => self.save(false),
            rfd::MessageDialogResult::No => {
                self.dirty = false;
                self.flush_session();
                true
            }
            _ => false,
        }
    }

    fn open_project(&mut self) {
        let Some(path) = rfd::FileDialog::new()
            .set_title("NodeQL-Projekt öffnen")
            .add_filter("NodeQL", &["json", "nodeql", "scratchql", "sqlq", "sqp"])
            .pick_file()
        else {
            return;
        };
        self.open_project_path(path);
    }

    fn open_project_path(&mut self, path: PathBuf) {
        match project::load_with_origin(&path) {
            Ok((project, imported)) => {
                if self.can_discard() {
                    if imported {
                        self.session.remember(path.clone(), project.name.clone());
                    }
                    self.connect(project, (!imported).then_some(path), imported);
                }
            }
            Err(error) => self.error = Some(error.to_string()),
        }
    }

    fn open_database(&mut self) {
        let Some(path) = rfd::FileDialog::new()
            .set_title("SQLite-Datenbank öffnen")
            .add_filter("SQLite", &["db", "sqlite", "sqlite3", "db3"])
            .pick_file()
        else {
            return;
        };
        self.connect_source(
            self.project.clone(),
            self.path.clone(),
            true,
            DatabaseSource::Import(path),
        );
    }

    fn new_database(&mut self) {
        let Some(path) = rfd::FileDialog::new()
            .set_title("SQLite-Datenbank anlegen")
            .add_filter("SQLite", &["db", "sqlite", "sqlite3"])
            .set_file_name("nodeql.db")
            .save_file()
        else {
            return;
        };
        self.connect_source(
            self.project.clone(),
            self.path.clone(),
            true,
            DatabaseSource::Create(path),
        );
    }

    fn start_project(&mut self, name: &str, autosave: bool, database: bool) -> bool {
        let mut project = Project {
            name: name.into(),
            blocks: Vec::new(),
            ..Project::default()
        };
        project.settings.autosave = autosave;
        project.workspace.no_database = !database;
        let create = if database {
            let Some(path) = rfd::FileDialog::new()
                .set_title("SQLite-Datenbank anlegen")
                .add_filter("SQLite", &["db", "sqlite", "sqlite3"])
                .set_file_name("nodeql.db")
                .save_file()
            else {
                return false;
            };
            Some(DatabaseSource::Create(path))
        } else {
            None
        };
        if !self.can_discard() {
            return false;
        }
        if let Some(source) = create {
            self.connect_source(project, None, true, source);
        } else {
            self.connect(project, None, true);
        }
        true
    }

    fn export(&mut self, format: export::Format) {
        let Some(result) = &self.result else {
            return;
        };
        let extension = format.extension();
        let Some(path) = rfd::FileDialog::new()
            .set_title("Ergebnis exportieren")
            .add_filter(extension, &[extension])
            .set_file_name(format!("ergebnis.{extension}"))
            .save_file()
        else {
            return;
        };
        let content = format.encode(result).map_err(|error| error.to_string());
        match content
            .and_then(|content| std::fs::write(path, content).map_err(|error| error.to_string()))
        {
            Ok(()) => self.status = "Ergebnis exportiert".into(),
            Err(error) => self.error = Some(error),
        }
    }
}

fn open_source(
    source: DatabaseSource,
) -> Result<(Option<Database>, ConnectionInfo), crate::database::DatabaseError> {
    let project_connection = matches!(source, DatabaseSource::Project(..));
    let (path, sample) = match source {
        DatabaseSource::Empty => {
            return Ok((
                None,
                ConnectionInfo {
                    schema: Vec::new(),
                    path: None,
                    issue: Some("Keine Datenbank verbunden.".into()),
                },
            ));
        }
        DatabaseSource::Project(path, sample) => (path, sample),
        DatabaseSource::Import(path) => {
            let directory = application_data_directory()
                .ok_or_else(|| std::io::Error::other("Kein Ordner für NodeQL-Daten verfügbar."))?
                .join("databases");
            (Some(Database::import_copy(&path, &directory)?), false)
        }
        DatabaseSource::Create(path) => {
            Database::create(&path)?;
            (Some(path), false)
        }
    };
    let opened = match &path {
        Some(path) => Database::open_workspace(path).or_else(|_| Database::open(path)),
        None if sample => Database::workbench_demo(),
        None => Database::demo(),
    }
    .and_then(|database| Ok((database.schema()?, database)));
    match opened {
        Ok((schema, database)) => Ok((
            Some(database),
            ConnectionInfo {
                schema,
                path,
                issue: None,
            },
        )),
        Err(error) if project_connection => {
            let location = path
                .as_ref()
                .map_or_else(String::new, |path| format!(" {}", path.display()));
            Ok((
                None,
                ConnectionInfo {
                    schema: Vec::new(),
                    path,
                    issue: Some(format!(
                        "Datenbank{location} konnte nicht geöffnet werden. {error}"
                    )),
                },
            ))
        }
        Err(error) => Err(error),
    }
}

fn application_data_directory() -> Option<PathBuf> {
    if cfg!(target_os = "macos") {
        std::env::home_dir().map(|home| home.join("Library/Application Support"))
    } else if cfg!(target_os = "windows") {
        std::env::var_os("LOCALAPPDATA").map(PathBuf::from)
    } else {
        std::env::var_os("XDG_DATA_HOME")
            .map(PathBuf::from)
            .filter(|path| path.is_absolute())
            .or_else(|| std::env::home_dir().map(|home| home.join(".local/share")))
    }
    .map(|path| path.join("NodeQL Rust"))
}

impl eframe::App for NodeQlApp {
    fn ui(&mut self, ui: &mut egui::Ui, _frame: &mut eframe::Frame) {
        self.render(ui);
    }
}

impl Drop for NodeQlApp {
    fn drop(&mut self) {
        self.cancel.store(true, Ordering::Relaxed);
    }
}

pub fn window_icon() -> egui::IconData {
    let logo = style::logo_image();
    egui::IconData {
        rgba: logo
            .pixels
            .into_iter()
            .flat_map(|color| color.to_srgba_unmultiplied())
            .collect(),
        width: logo.size[0] as u32,
        height: logo.size[1] as u32,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::BlockKind;
    use egui::{Event as Input, Id, Modifiers, PointerButton, Pos2, RawInput, Rect, vec2};

    fn frame(ctx: &egui::Context, app: &mut NodeQlApp, events: Vec<Input>) {
        let mut output = ctx.run_ui(
            RawInput {
                screen_rect: Some(Rect::from_min_size(Pos2::ZERO, vec2(1710.0, 966.0))),
                events,
                ..Default::default()
            },
            |ui| app.render(ui),
        );
        assert!(!output.shapes.is_empty());
        output.textures_delta.clear();
    }

    fn await_query(app: &mut NodeQlApp) {
        let deadline = Instant::now() + std::time::Duration::from_secs(5);
        while app.busy && Instant::now() < deadline {
            app.poll();
            thread::sleep(std::time::Duration::from_millis(5));
        }
        assert!(!app.busy, "SQLite worker timed out");
        assert!(app.error.is_none(), "{:?}", app.error);
    }

    fn drag(ctx: &egui::Context, app: &mut NodeQlApp, from: Pos2, to: Pos2) {
        let button = |pos, pressed| Input::PointerButton {
            pos,
            button: PointerButton::Primary,
            pressed,
            modifiers: Modifiers::NONE,
        };
        frame(ctx, app, vec![Input::PointerMoved(from)]);
        frame(ctx, app, vec![button(from, true)]);
        frame(ctx, app, vec![Input::PointerMoved(from.lerp(to, 0.5))]);
        frame(ctx, app, vec![Input::PointerMoved(to)]);
        frame(ctx, app, vec![button(to, false)]);
        frame(ctx, app, vec![]);
    }

    #[test]
    fn flutter_layout_canvas_docks_detaches_and_executes_filter() {
        let ctx = egui::Context::default();
        let mut app = NodeQlApp::create(ctx.clone());
        await_query(&mut app);
        assert_eq!(app.result.as_ref().unwrap().rows.len(), 11);
        frame(&ctx, &mut app, vec![]);
        let palette = ctx
            .read_response(Id::unique(("palette-item", "sqlWhere")))
            .unwrap()
            .rect;
        let order = app
            .project
            .blocks
            .iter()
            .find(|block| block.kind == BlockKind::OrderBy)
            .unwrap()
            .id;
        let destination = ctx
            .read_response(Id::unique(("workspace-node", order)))
            .unwrap()
            .rect;
        drag(
            &ctx,
            &mut app,
            palette.center(),
            destination.center_top() + vec2(0.0, 2.0),
        );
        let filter = &app.project.blocks[3];
        assert_eq!(filter.kind, BlockKind::Where);
        let filter_id = filter.id;
        assert!(
            app.compiled()
                .unwrap()
                .contains("WHERE Customers.country = 'UK'")
        );
        app.run();
        await_query(&mut app);
        assert_eq!(app.result.as_ref().unwrap().rows.len(), 4);
        let filter = ctx
            .read_response(Id::unique(("workspace-node", filter_id)))
            .unwrap()
            .rect;
        drag(
            &ctx,
            &mut app,
            filter.center_top() + vec2(0.0, 16.0),
            Pos2::new(1120.0, 575.0),
        );
        assert!(!app.compiled().unwrap().contains("WHERE"));
        assert_eq!(app.project.workspace.first.detached[0].block.id, filter_id);
        app.restore_edit(false);
        assert_eq!(app.project.blocks[3].id, filter_id);
        assert!(app.project.workspace.first.detached.is_empty());
        app.restore_edit(true);
        assert_eq!(app.project.workspace.first.detached[0].block.id, filter_id);

        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("canvas.nodeql-rust.json");
        project::save(&path, &app.project).unwrap();
        assert_eq!(project::load(&path).unwrap(), app.project);
    }

    #[test]
    fn workbench_requires_an_explicit_run_for_visual_changes_in_other_tabs() {
        use crate::model::{Block, QueryTab};
        let ctx = egui::Context::default();
        let mut app = NodeQlApp::create(ctx);
        await_query(&mut app);
        let mut create = Block::new(BlockKind::CreateTable);
        create.input = "notes (id INTEGER PRIMARY KEY)".into();
        app.project.workspace.tabs.push(QueryTab {
            blocks: vec![create],
            ..Default::default()
        });
        assert!(app.compiled().unwrap().contains("CREATE TABLE notes"));
        app.preview();
        assert!(!app.busy);
        assert!(!app.schema.iter().any(|table| table.name == "notes"));

        app.run();
        await_query(&mut app);
        assert!(app.schema.iter().any(|table| table.name == "notes"));
        app.browse_table("notes".into());
        await_query(&mut app);
        assert_eq!(app.browser_result.as_ref().unwrap().data.columns, ["id"]);
    }

    #[test]
    fn workshop_reporter_requires_a_real_slot_drop_and_resumes_in_isolation() {
        use crate::reporter::{LiteralKind, Reporter};
        use catalog::Action;
        let ctx = egui::Context::default();
        let mut app = NodeQlApp::create(ctx.clone());
        await_query(&mut app);
        let original = app.project.clone();
        app.begin_practice(3, false);
        await_query(&mut app);
        assert_eq!(app.practice_target().unwrap().key(), "sqlSelect");
        app.insert(Action::Clause(BlockKind::Select), None, None);
        assert!(app.practice_target().is_none());
        app.finish_practice_step();
        app.insert(Action::Clause(BlockKind::Where), None, None);
        assert_eq!(app.practice_target().unwrap().key(), "text");
        frame(&ctx, &mut app, vec![]);
        let card = ctx
            .read_response(Id::unique(("palette-item", "text")))
            .unwrap()
            .rect
            .center();
        let click = |pressed| Input::PointerButton {
            pos: card,
            button: PointerButton::Primary,
            pressed,
            modifiers: Modifiers::NONE,
        };
        frame(&ctx, &mut app, vec![Input::PointerMoved(card), click(true)]);
        frame(&ctx, &mut app, vec![click(false)]);
        assert_eq!(app.practice_target().unwrap().key(), "text");
        let filter = &app.project.blocks[2];
        assert_eq!(filter.input, "city = NULL");
        let slot = ctx
            .read_response(Id::unique(("block-field", filter.id, 7_usize, 11_usize)))
            .unwrap()
            .rect
            .center();
        drag(&ctx, &mut app, card, slot);
        assert!(app.practice_target().is_none());
        assert_eq!(
            app.project.blocks[2].reporters[0].reporter,
            Reporter::Literal {
                kind: LiteralKind::Text,
                value: "Berlin".into()
            }
        );
        app.run();
        await_query(&mut app);
        assert_eq!(app.result.as_ref().unwrap().rows.len(), 3);
        let practice = app.project.clone();
        app.leave_practice();
        await_query(&mut app);
        assert_eq!(app.project, original);
        assert_eq!(app.result.as_ref().unwrap().rows.len(), 11);
        app.begin_practice(3, false);
        await_query(&mut app);
        assert_eq!(app.project, practice);
        assert!(app.practice_target().is_none());
    }
}
