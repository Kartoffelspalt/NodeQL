use super::{
    NodeQlApp, QueryTarget,
    blocks::{self, Drag, FieldEditor},
    catalog::{Action, FUNCTIONS, Preset},
    screen::{table, table_with_rows},
    style::{self, Colors, Control, Dock, Language, Theme, font, glyph, icon, rect, rule, words},
};
use crate::{
    database::quote_identifier,
    model::{Block, BlockKind},
    reporter::{LiteralKind, Reporter},
};
use eframe::egui::{self, Align2, Frame, Id, Rect, RichText, Stroke, Ui, pos2, vec2};

pub enum Dialog {
    Settings(usize),
    Tables(BrowserView),
    Results,
    NewProject {
        name: String,
        autosave: bool,
        database: bool,
    },
    Rename {
        index: usize,
        name: String,
    },
    DeleteTab(usize),
    Introduction(usize),
    Workshop,
    Message {
        title: String,
        text: String,
    },
}

#[derive(Default)]
pub struct BrowserView {
    search: String,
    details: bool,
    page: usize,
    pub advanced: bool,
    editor: Option<TableDraft>,
}

const COLUMN_TYPES: [&str; 5] = ["INTEGER", "REAL", "TEXT", "BLOB", "NUMERIC"];

struct ColumnDraft {
    name: String,
    kind: usize,
    primary: bool,
    required: bool,
    unique: bool,
}

impl Default for ColumnDraft {
    fn default() -> Self {
        Self {
            name: String::new(),
            kind: 2,
            primary: false,
            required: false,
            unique: false,
        }
    }
}

struct TableDraft {
    name: String,
    columns: Vec<ColumnDraft>,
    sql: String,
    message: Option<String>,
}

impl Default for TableDraft {
    fn default() -> Self {
        Self {
            name: String::new(),
            columns: vec![ColumnDraft {
                name: "id".into(),
                kind: 0,
                primary: true,
                ..ColumnDraft::default()
            }],
            sql: "CREATE TABLE table_name (\n  id INTEGER PRIMARY KEY\n);".into(),
            message: None,
        }
    }
}

impl TableDraft {
    fn build(&self, lang: Language) -> Result<String, String> {
        let name = self.name.trim();
        if name.is_empty() {
            return Err(lang
                .pick("Gib einen Tabellennamen ein.", "Enter a table name.")
                .into());
        }
        let mut names = std::collections::HashSet::new();
        let mut definitions = Vec::new();
        for column in &self.columns {
            let name = column.name.trim();
            if name.is_empty() {
                return Err(lang
                    .pick(
                        "Jede Spalte benötigt einen Namen.",
                        "Every column needs a name.",
                    )
                    .into());
            }
            if !names.insert(name.to_ascii_lowercase()) {
                return Err(format!(
                    "{} {name}",
                    lang.pick("Doppelter Spaltenname", "Duplicate column name")
                ));
            }
            definitions.push(format!(
                "  {} {}{}{}{}",
                quote_identifier(name),
                COLUMN_TYPES[column.kind],
                if column.primary { " PRIMARY KEY" } else { "" },
                if column.required { " NOT NULL" } else { "" },
                if column.unique && !column.primary {
                    " UNIQUE"
                } else {
                    ""
                }
            ));
        }
        Ok(format!(
            "CREATE TABLE {} (\n{}\n);",
            quote_identifier(name),
            definitions.join(",\n")
        ))
    }
}

impl NodeQlApp {
    pub(super) fn draw_dialogs(&mut self, root: &Ui) {
        let ctx = root.ctx();
        if let Some(mut editor) = self.field_editor.take() {
            let c = self.theme.colors();
            let lang = self.language;
            let mut save = false;
            let mut cancel = false;
            let modal = egui::Modal::new(Id::unique("block-field"))
                .frame(modal_frame(c, 20))
                .show(ctx, |ui| {
                    ui.set_width(380.0);
                    title(ui, &editor.title, c);
                    if let Some(reporter) = &mut editor.reporter {
                        reporter_tray(ui, lang);
                        egui::ScrollArea::vertical()
                            .max_height(400.0)
                            .show(ui, |ui| {
                                reporter_editor(ui, reporter, lang, 0, &|preset| {
                                    self.authored_reporter(preset)
                                });
                            });
                        ui.code(reporter.sql());
                        if ui
                            .button(
                                lang.pick("Als SQL-Ausdruck bearbeiten", "Edit as SQL expression"),
                            )
                            .clicked()
                        {
                            editor.value = reporter.sql();
                            editor.reporter = None;
                        }
                        buttons(ui, lang, &mut save, &mut cancel);
                        return;
                    }
                    let response = ui.add(
                        egui::TextEdit::singleline(&mut editor.value)
                            .desired_width(f32::INFINITY)
                            .hint_text(lang.pick("Ausdruck oder Spalte", "Expression or column"))
                            .char_limit(4096),
                    );
                    if response.lost_focus() && ui.input(|i| i.key_pressed(egui::Key::Enter)) {
                        save = true;
                    }
                    if !editor.choices.is_empty() {
                        ui.add_space(7.0);
                        egui::ScrollArea::vertical()
                            .max_height(235.0)
                            .show(ui, |ui| {
                                for choice in &editor.choices {
                                    if ui
                                        .selectable_label(
                                            choice.value == editor.value,
                                            &choice.label,
                                        )
                                        .clicked()
                                    {
                                        editor.value.clone_from(&choice.value);
                                        save = true;
                                    }
                                }
                            });
                    }
                    buttons(ui, lang, &mut save, &mut cancel);
                });
            if save {
                self.save_field(editor);
            } else if !cancel && !modal.should_close() {
                self.field_editor = Some(editor);
            }
            return;
        }

        let Some(mut dialog) = self.dialog.take() else {
            return;
        };
        let c = self.theme.colors();
        let lang = self.language;
        let screen = root.max_rect();
        let mut close = false;
        let mut next = None;
        let frame = modal_frame(
            c,
            if matches!(
                dialog,
                Dialog::Settings(_) | Dialog::Tables(_) | Dialog::Results
            ) {
                0
            } else {
                20
            },
        );
        let modal = egui::Modal::new(Id::unique("workbench-dialog")).frame(frame).show(ctx, |ui| {
            match &mut dialog {
                Dialog::Settings(section) => {
                    next = self.settings(ui, screen.size() - vec2(30.0, 30.0), *section, c, &mut close);
                }
                Dialog::Tables(state) => {
                    self.tables(ui, screen.size() - vec2(60.0, 70.0), state, c, &mut close);
                }
                Dialog::Results => {
                    ui.set_width(screen.width() - 70.0);
                    ui.set_height(screen.height() - 70.0);
                    close = modal_header(ui, lang.pick("Ausgabevorschau", "Output preview"), icon::ROWS, c);
                    ui.menu_button(lang.pick("Exportieren", "Export"), |ui| self.export_menu(ui));
                    ui.separator();
                    if let Some(result) = &self.result { table(ui, result, c); }
                    else { ui.label(lang.pick("Noch keine Ergebnisse.", "No results yet.")); }
                }
                Dialog::NewProject { name, autosave, database } => {
                    ui.set_width(380.0);
                    title(ui, lang.pick("Neues Projekt", "New project"), c);
                    ui.label(lang.pick("Projektname", "Project name"));
                    ui.add(egui::TextEdit::singleline(name).char_limit(64).desired_width(f32::INFINITY));
                    ui.checkbox(database, lang.pick("SQLite-Datenbank anlegen", "Create a SQLite database"));
                    ui.checkbox(autosave, lang.pick("Automatisch sichern", "Enable autosave"));
                    ui.horizontal(|ui| {
                        close = ui.button(lang.pick("Abbrechen", "Cancel")).clicked();
                        if ui.add_enabled(!self.busy && !name.trim().is_empty(), egui::Button::new(lang.pick("Projekt erstellen", "Create project"))).clicked() {
                            close = self.start_project(name.trim(), *autosave, *database);
                        }
                    });
                }
                Dialog::Rename { index, name } => {
                    ui.set_width(330.0);
                    title(ui, lang.pick("Query umbenennen", "Rename query tab"), c);
                    ui.label(lang.pick("Name des Tabs", "Tab name"));
                    let editor = ui.add(egui::TextEdit::singleline(name).desired_width(f32::INFINITY).char_limit(64));
                    let mut save = editor.lost_focus() && ui.input(|i| i.key_pressed(egui::Key::Enter));
                    buttons(ui, lang, &mut save, &mut close);
                    if save && !name.trim().is_empty() {
                        if *index == 0 { self.project.workspace.first.name = name.trim().into(); }
                        else { self.project.workspace.tabs[*index - 1].layout.name = name.trim().into(); }
                        self.changed();
                        close = true;
                    }
                }
                Dialog::DeleteTab(index) => {
                    ui.set_width(365.0);
                    title(ui, lang.pick("Arbeitsbereich löschen?", "Delete workspace?"), c);
                    ui.label(lang.pick("Der Query-Tab und seine Blöcke werden gelöscht.", "The query tab and its blocks will be deleted."));
                    ui.add_space(12.0);
                    ui.horizontal(|ui| {
                        if ui.button(lang.pick("Abbrechen", "Cancel")).clicked() { close = true; }
                        if ui.button(lang.pick("Löschen", "Delete")).clicked() {
                            self.delete_tab(*index);
                            close = true;
                        }
                    });
                }
                Dialog::Message { title: heading, text } => {
                    ui.set_width(420.0);
                    title(ui, heading, c);
                    ui.label(text.as_str());
                    ui.add_space(12.0);
                    close = ui.button(lang.pick("Schließen", "Close")).clicked();
                }
                Dialog::Introduction(step) => {
                    ui.set_width(460.0);
                    close = modal_header(ui, lang.pick("Kurze Einführung", "Quick introduction"), icon::HELP, c);
                    let steps = [
                        (lang.pick("Datenbank laden", "Mount a database"), lang.pick("Öffne eine SQLite-Datei oder verwende die Demo. Der Tabellenbrowser zeigt Tabellen, Spalten und Beispieldaten.", "Open a SQLite file or use the demo. The table browser shows tables, columns and sample data.")),
                        (lang.pick("Abfrage aus Blöcken bauen", "Build a query with blocks"), lang.pick("Ziehe Blöcke aus der Palette unter den gelben Startblock. Über die Eingabefelder wählst du Spalten, Tabellen und Bedingungen.", "Drag blocks from the palette under the yellow trigger. Use the fields to choose columns, tables and predicates.")),
                        (lang.pick("SQLite ausführen", "Run SQLite"), lang.pick("Die SQL-Vorschau zeigt den erzeugten Befehl. Führe ihn aus und exportiere die Ausgabe als CSV oder JSON.", "The SQL preview shows the generated command. Run it and export the output as CSV or JSON.")),
                    ];
                    let (heading, body) = steps[*step];
                    title(ui, heading, c);
                    ui.label(body);
                    ui.add_space(14.0);
                    ui.horizontal(|ui| {
                        if ui.add_enabled(*step > 0, egui::Button::new(lang.pick("Zurück", "Back"))).clicked() { *step -= 1; }
                        if ui.button(if *step + 1 == steps.len() { lang.pick("Fertig", "Done") } else { lang.pick("Weiter", "Next") }).clicked() {
                            if *step + 1 == steps.len() { close = true; } else { *step += 1; }
                        }
                    });
                }
                Dialog::Workshop => {
                    close = self.workshop(ui, screen.size(), c);
                }
            }
        });
        if let Some(next) = next {
            self.dialog = Some(next);
        } else if !close && !modal.should_close() {
            self.dialog = Some(dialog);
        }
    }

    fn save_field(&mut self, editor: FieldEditor) {
        if let Some(reporter) = editor.reporter {
            self.apply_reporter(editor.block, editor.range, reporter);
            return;
        }
        let mut value = editor.value.trim().to_owned();
        if editor.append_space {
            if !["INNER", "LEFT", "RIGHT", "FULL", "CROSS", "NATURAL"]
                .iter()
                .any(|kind| value.eq_ignore_ascii_case(kind))
            {
                return;
            }
            value = value.to_ascii_uppercase();
            let (blocks, layout) = self.project.active_query_mut();
            let block = blocks
                .iter_mut()
                .chain(layout.chains.iter_mut().flat_map(|chain| &mut chain.blocks))
                .chain(layout.detached.iter_mut().map(|node| &mut node.block))
                .find(|block| block.id == editor.block);
            if let Some(block) = block {
                let (_, rest) = crate::compiler::join_parts(&block.input);
                let on = rest.to_ascii_uppercase().find(" ON ");
                let prefix = block.input.len() - rest.len();
                if matches!(value.as_str(), "NATURAL" | "CROSS") {
                    if let Some(on) = on {
                        block.edit_input(prefix + on..block.input.len(), "");
                    }
                } else if on.is_none() {
                    let end = block.input.len();
                    block.edit_input(end..end, " ON 1 = 1");
                }
                block.edit_input(0..prefix, &format!("{value} "));
                self.changed();
            }
        } else {
            self.apply_field(editor.block, editor.range, &value);
        }
    }

    fn settings(
        &mut self,
        ui: &mut Ui,
        size: egui::Vec2,
        section: usize,
        c: Colors,
        close: &mut bool,
    ) -> Option<Dialog> {
        let lang = self.language;
        let names = [
            (
                icon::PAINT,
                lang.pick("Personalisierung", "Personalization"),
            ),
            (icon::TABLE, "Display"),
            (icon::PLAY, "Motion"),
            (icon::CHECK, lang.pick("Bedienungshilfen", "Accessibility")),
            (
                icon::DATA,
                lang.pick("Sprache & Region", "Language & Region"),
            ),
            (icon::EXTENSION, lang.pick("Erweiterungen", "Extensions")),
            (icon::SCHOOL, lang.pick("Lernen", "Learning")),
            (icon::HELP, lang.pick("Über NodeQL", "About NodeQL")),
        ];
        let (area, _) = ui.allocate_exact_size(size, egui::Sense::hover());
        let sidebar = rect(area.left(), area.top(), 244.0, area.height());
        ui.painter().rect_filled(sidebar, 0, c.raised);
        words(
            ui,
            sidebar.min + vec2(22.0, 24.0),
            Align2::LEFT_TOP,
            lang.pick("Einstellungen", "Settings"),
            font(22.0, true),
            c.text,
        );
        let mut next = None;
        let mut sidebar_ui = style::region(ui, "settings-sidebar", sidebar);
        for (i, (glyph, name)) in names.iter().enumerate() {
            let bounds = rect(
                sidebar.left() + 8.0,
                sidebar.top() + 62.0 + i as f32 * 48.0,
                228.0,
                42.0,
            );
            let response = style::hit(&mut sidebar_ui, bounds, egui::Sense::click());
            sidebar_ui.painter().rect_filled(
                bounds,
                10,
                if i == section {
                    c.selected
                } else if response.hovered() {
                    c.panel
                } else {
                    c.raised
                },
            );
            style::glyph(
                &sidebar_ui,
                bounds.left_center() + vec2(20.0, 0.0),
                *glyph,
                20.0,
                c.text,
            );
            words(
                &sidebar_ui,
                bounds.left_center() + vec2(40.0, 0.0),
                Align2::LEFT_CENTER,
                name,
                font(14.0, i == section),
                c.text,
            );
            if response.clicked() {
                next = Some(Dialog::Settings(i));
            }
        }

        let body = Rect::from_min_max(
            pos2(sidebar.right() + 32.0, area.top() + 23.0),
            area.max - vec2(24.0, 24.0),
        );
        let mut body = style::region(ui, "settings-content", body);
        *close = modal_header(&mut body, names[section].1, names[section].0, c);
        body.add_space(18.0);
        match section {
            0 => {
                title(&mut body, lang.pick("Design", "Appearance"), c);
                body.horizontal_wrapped(|ui| {
                    for theme in [Theme::Light, Theme::Dark, Theme::Midnight, Theme::Matrix] {
                        if ui
                            .selectable_label(self.theme == theme, theme.name())
                            .clicked()
                        {
                            self.theme = theme;
                            theme.apply(ui.ctx());
                        }
                    }
                });
                body.add_space(18.0);
                title(&mut body, lang.pick("SQL-Modus", "SQL mode"), c);
                body.horizontal(|ui| {
                    ui.selectable_value(&mut self.advanced, false, lang.pick("Einfach", "Simple"));
                    ui.selectable_value(
                        &mut self.advanced,
                        true,
                        lang.pick("Erweitert", "Advanced"),
                    );
                });
            }
            1 => {
                title(&mut body, lang.pick("Fensteranordnung", "Panel layout"), c);
                for (dock, text) in [
                    (
                        Dock::RightSplit,
                        lang.pick("Rechts geteilt", "Split on the right"),
                    ),
                    (
                        Dock::PreviewBottom,
                        lang.pick("Ausgabe unten", "Output at the bottom"),
                    ),
                    (
                        Dock::CommandBottom,
                        lang.pick("SQL unten", "SQL at the bottom"),
                    ),
                ] {
                    body.selectable_value(&mut self.dock, dock, text);
                }
                if body
                    .button(lang.pick("Layout zurücksetzen", "Reset layout"))
                    .clicked()
                {
                    self.dock = Dock::RightSplit;
                    self.palette_width = 266.0;
                    self.runtime_width = 368.0;
                    self.split = 0.545;
                    self.canvas.reset();
                }
            }
            2 => {
                if body
                    .checkbox(
                        &mut self.project.settings.autosave,
                        lang.pick("Projekt automatisch sichern", "Autosave project"),
                    )
                    .changed()
                {
                    self.mark_dirty();
                }
                body.checkbox(
                    &mut self.live_preview,
                    lang.pick("Live-Vorschau ausführen", "Run live preview"),
                );
                body.label(lang.pick(
                    "Aktualisiert die Ausgabe bei Änderungen an der Abfrage.",
                    "Updates the output when the query changes.",
                ));
                if !self.live_preview {
                    self.preview_at = None;
                }
            }
            3 => {
                body.label(lang.pick(
                    "Cmd/Ctrl+Enter führt SQLite aus. Cmd/Ctrl+S speichert das Projekt.",
                    "Cmd/Ctrl+Enter runs SQLite. Cmd/Ctrl+S saves the project.",
                ));
                body.label(lang.pick(
                    "Leertaste und Enter aktivieren fokussierte Bedienelemente.",
                    "Space and Enter activate focused controls.",
                ));
            }
            4 => {
                for language in [Language::German, Language::English] {
                    body.selectable_value(&mut self.language, language, language.native());
                }
            }
            5 => {
                body.label(lang.pick("Keine Plugins installiert", "No plugins installed"));
            }
            6 => {
                if body.button("Workshop").clicked() {
                    next = Some(Dialog::Workshop);
                }
                if body
                    .button(lang.pick("Kurze Einführung", "Quick introduction"))
                    .clicked()
                {
                    next = Some(Dialog::Introduction(0));
                }
            }
            _ => {
                title(&mut body, "NodeQL", c);
                body.label(format!("Rust · {}", env!("CARGO_PKG_VERSION")));
                body.label(lang.pick("Visuelle SQLite-Arbeitsumgebung", "Visual SQLite workbench"));
            }
        }
        next
    }

    fn table_editor(
        &mut self,
        ui: &mut Ui,
        draft: &mut TableDraft,
        advanced: bool,
        c: Colors,
    ) -> bool {
        let lang = self.language;
        let back = ui
            .button(lang.pick("Zurück zur Tabelle", "Back to table"))
            .clicked();
        ui.add_space(12.0);
        title(ui, lang.pick("Tabelle erstellen", "Create table"), c);
        egui::ScrollArea::vertical().show(ui, |ui| {
            ui.add_enabled_ui(!self.busy, |ui| {
                if advanced {
                    ui.add(
                        egui::TextEdit::multiline(&mut draft.sql)
                            .code_editor()
                            .desired_width(f32::INFINITY)
                            .desired_rows(10),
                    );
                } else {
                    ui.label(lang.pick("Tabellenname", "Table name"));
                    ui.text_edit_singleline(&mut draft.name);
                    ui.add_space(8.0);
                    let mut remove = None;
                    let can_remove = draft.columns.len() > 1;
                    for (index, column) in draft.columns.iter_mut().enumerate() {
                        ui.horizontal_wrapped(|ui| {
                            ui.add(
                                egui::TextEdit::singleline(&mut column.name)
                                    .hint_text(lang.pick("Spaltenname", "Column name"))
                                    .desired_width(150.0),
                            );
                            egui::ComboBox::from_id_salt(("column-type", index))
                                .selected_text(COLUMN_TYPES[column.kind])
                                .show_ui(ui, |ui| {
                                    for (value, name) in COLUMN_TYPES.into_iter().enumerate() {
                                        ui.selectable_value(&mut column.kind, value, name);
                                    }
                                });
                            ui.checkbox(
                                &mut column.primary,
                                lang.pick("Primärschlüssel", "Primary key"),
                            );
                            ui.checkbox(&mut column.required, lang.pick("Pflichtfeld", "Required"));
                            ui.checkbox(&mut column.unique, lang.pick("Eindeutig", "Unique"));
                            if ui.add_enabled(can_remove, egui::Button::new("×")).clicked() {
                                remove = Some(index);
                            }
                        });
                    }
                    if let Some(index) = remove {
                        draft.columns.remove(index);
                    }
                    if ui
                        .button(lang.pick("Spalte hinzufügen", "Add column"))
                        .clicked()
                    {
                        draft.columns.push(ColumnDraft::default());
                    }
                    if let Ok(sql) = draft.build(lang) {
                        ui.code(sql);
                    }
                }
                if ui
                    .button(lang.pick("SQLite ausführen", "Run SQLite"))
                    .clicked()
                {
                    match if advanced {
                        Ok(draft.sql.clone())
                    } else {
                        draft.build(lang)
                    } {
                        Ok(sql) if !sql.trim().is_empty() => {
                            draft.message = None;
                            self.run_sql(sql, QueryTarget::TableEditor, true);
                        }
                        Ok(_) => {
                            draft.message = Some(
                                lang.pick("Gib einen SQL-Befehl ein.", "Enter a SQL command.")
                                    .into(),
                            )
                        }
                        Err(error) => draft.message = Some(error),
                    }
                }
            });
            if self.busy && ui.button(lang.pick("Abbrechen", "Cancel")).clicked() {
                self.cancel
                    .store(true, std::sync::atomic::Ordering::Relaxed);
            }
            if let Some(message) = &draft.message {
                ui.label(message);
            }
        });
        back
    }

    fn tables(
        &mut self,
        ui: &mut Ui,
        size: egui::Vec2,
        state: &mut BrowserView,
        c: Colors,
        close: &mut bool,
    ) {
        let lang = self.language;
        let (area, _) = ui.allocate_exact_size(
            vec2(size.x.min(1240.0), size.y.min(900.0)),
            egui::Sense::hover(),
        );
        let header = rect(area.left(), area.top(), area.width(), 74.0);
        ui.painter().rect_filled(header, 16, c.top);
        let mut bar = style::region(ui, "browser-header", header);
        let filename = self
            .project
            .database
            .as_ref()
            .and_then(|path| path.file_name())
            .map(|name| name.to_string_lossy())
            .unwrap_or("NodeQL Demo".into());
        let symbol = rect(header.left() + 20.0, header.top() + 15.0, 44.0, 44.0);
        bar.painter().rect_filled(symbol, 14, c.selected);
        glyph(&bar, symbol.center(), icon::STORAGE, 24.0, c.primary);
        words(
            &bar,
            header.min + vec2(78.0, 15.0),
            Align2::LEFT_TOP,
            lang.pick("Entdecke deine Daten", "Explore your data"),
            font(22.0, true),
            c.text,
        );
        words(
            &bar,
            header.min + vec2(78.0, 44.0),
            Align2::LEFT_TOP,
            &filename,
            font(12.0, false),
            c.text,
        );
        *close = Control {
            bg: c.selected,
            ..Control::icon(icon::CLOSE, lang.pick("Schließen", "Close"), c.primary)
        }
        .show(
            &mut bar,
            rect(header.right() - 56.0, header.top() + 15.0, 44.0, 44.0),
        )
        .clicked();
        if (Control {
            bg: c.selected,
            ..Control::icon(
                icon::REFRESH,
                lang.pick("Aktualisieren", "Refresh"),
                c.primary,
            )
        })
        .show(
            &mut bar,
            rect(header.right() - 106.0, header.top() + 15.0, 44.0, 44.0),
        )
        .clicked()
            && !self.busy
            && let Some(table) = self.browser_table.clone()
        {
            self.inspect_table(table, state.page);
        }
        for (index, label) in [
            lang.pick("Einfach", "Simple"),
            lang.pick("Erweitert", "Advanced"),
        ]
        .into_iter()
        .enumerate()
        {
            let selected = state.advanced == (index == 1);
            let bounds = rect(
                header.right() - 330.0 + 102.0 * index as f32,
                header.top() + 17.0,
                102.0,
                40.0,
            );
            if (Control {
                bg: if selected { c.selected } else { c.panel },
                border: c.primary,
                radius: 10,
                icon: selected.then_some(icon::CHECK),
                ..Control::new(label, c.text)
            })
            .show(&mut bar, bounds)
            .clicked()
            {
                state.advanced = index == 1;
            }
        }
        rule(ui, header.left_bottom(), header.right_bottom(), c.border);

        let sidebar = Rect::from_min_max(
            pos2(area.left(), header.bottom()),
            pos2(
                area.left() + (area.width() * 0.23).clamp(220.0, 285.0),
                area.bottom(),
            ),
        );
        let mut list = style::region(ui, "browser-sidebar", sidebar.shrink(8.0));
        let search_area = rect(
            sidebar.left() + 14.0,
            sidebar.top() + 14.0,
            sidebar.width() - 28.0,
            47.0,
        );
        list.painter().rect(
            search_area,
            12,
            c.raised,
            Stroke::new(1.0, c.border),
            egui::StrokeKind::Inside,
        );
        glyph(
            &list,
            search_area.left_center() + vec2(24.0, 0.0),
            icon::SEARCH,
            20.0,
            c.text,
        );
        list.put(
            rect(
                search_area.left() + 48.0,
                search_area.top() + 14.0,
                search_area.width() - 56.0,
                23.0,
            ),
            egui::TextEdit::singleline(&mut state.search)
                .font(font(15.0, false))
                .frame(Frame::NONE)
                .hint_text(lang.pick("Tabelle suchen", "Search tables")),
        );
        let label_at = sidebar.top() + 93.0;
        words(
            &list,
            pos2(search_area.left(), label_at),
            Align2::LEFT_CENTER,
            lang.pick("TABELLEN", "TABLES"),
            font(11.0, true),
            c.text,
        );
        words(
            &list,
            pos2(search_area.right() - 4.0, label_at),
            Align2::RIGHT_CENTER,
            &self.schema.len().to_string(),
            font(11.0, true),
            c.text,
        );
        let list_area = Rect::from_min_max(
            pos2(sidebar.left() + 8.0, sidebar.top() + 112.0),
            sidebar.right_bottom() - vec2(8.0, 62.0),
        );
        let mut names = style::region(&mut list, "browser-table-names", list_area);
        let filter = state.search.to_lowercase();
        let mut selected = None;
        egui::ScrollArea::vertical()
            .id_salt("browser-names-scroll")
            .show(&mut names, |ui| {
                for table in &self.schema {
                    if !table.name.to_lowercase().contains(&filter) {
                        continue;
                    }
                    let (row, response) = ui.allocate_exact_size(
                        vec2(list_area.width() - 2.0, 48.0),
                        egui::Sense::click(),
                    );
                    let active = self.browser_table.as_deref() == Some(&table.name);
                    if active || response.hovered() {
                        ui.painter().rect_filled(
                            row,
                            14,
                            if active { c.selected } else { c.raised },
                        );
                    }
                    let badge = rect(row.left() + 10.0, row.top() + 7.0, 34.0, 34.0);
                    ui.painter().rect_filled(badge, 5, c.raised);
                    glyph(ui, badge.center(), icon::TABLE, 19.0, c.text);
                    blocks::clipped_text(
                        ui,
                        rect(
                            row.left() + 54.0,
                            row.top(),
                            row.width() - 84.0,
                            row.height(),
                        ),
                        &table.name,
                        15.0,
                        true,
                        c.text,
                        1,
                    );
                    if active {
                        glyph(
                            ui,
                            row.right_center() - vec2(18.0, 0.0),
                            icon::CHEVRON,
                            17.0,
                            c.primary,
                        );
                    }
                    if response.clicked() && !self.busy {
                        selected = Some(table.name.clone());
                    }
                }
            });
        if let Some(selected) = selected {
            state.page = 0;
            self.browse_table(selected);
        }
        let new_table = rect(
            sidebar.left() + 14.0,
            sidebar.bottom() - 56.0,
            sidebar.width() - 28.0,
            42.0,
        );
        list.add_enabled_ui(!self.busy && self.database_available, |ui| {
            if (Control {
                border: c.border,
                icon: Some(icon::ADD),
                ..Control::new(lang.pick("Neue Tabelle", "New table"), c.primary)
            })
            .show(ui, new_table)
            .clicked()
            {
                self.table_edit_result = None;
                state.editor = Some(TableDraft::default());
            }
        });
        rule(ui, sidebar.right_top(), sidebar.right_bottom(), c.border);

        let content =
            Rect::from_min_max(pos2(sidebar.right() + 1.0, header.bottom() + 1.0), area.max);
        ui.painter().rect_filled(content, 0, c.raised);
        let mut body = style::region(ui, "table-details", content.shrink2(vec2(20.0, 19.0)));
        if let Some(draft) = &mut state.editor {
            if let Some(result) = self.table_edit_result.take() {
                draft.message = Some(match result {
                    Ok(()) => lang
                        .pick("SQLite-Befehl ausgeführt.", "SQLite command executed.")
                        .into(),
                    Err(error) => error,
                });
            }
            if self.table_editor(&mut body, draft, state.advanced, c) {
                if !self.busy
                    && self.browser_table.is_none()
                    && let Some(table) = self
                        .schema
                        .iter()
                        .find(|table| table.name == draft.name.trim())
                        .or_else(|| self.schema.first())
                {
                    state.page = 0;
                    self.browse_table(table.name.clone());
                }
                state.editor = None;
            }
            return;
        }
        let Some(name) = self.browser_table.clone() else {
            body.label(lang.pick("Wähle eine Tabelle aus.", "Choose a table."));
            return;
        };
        let body_rect = body.max_rect();
        let head = rect(body_rect.left(), body_rect.top(), body_rect.width(), 49.0);
        let symbol = rect(head.left(), head.top(), 45.0, 45.0);
        body.painter().rect_filled(symbol, 13, c.selected);
        glyph(&body, symbol.center(), icon::TABLE, 22.0, c.primary);
        words(
            &body,
            head.left_top() + vec2(59.0, 0.0),
            Align2::LEFT_TOP,
            &name,
            font(23.0, true),
            c.text,
        );
        words(
            &body,
            head.left_top() + vec2(59.0, 32.0),
            Align2::LEFT_TOP,
            if self
                .browser_result
                .as_ref()
                .is_some_and(|result| result.view)
            {
                lang.pick("Ansicht", "View")
            } else {
                lang.pick("Tabelle", "Table")
            },
            font(12.0, true),
            c.text,
        );
        let columns = self
            .schema
            .iter()
            .find(|table| table.name == name)
            .map_or(0, |table| table.columns.len());
        let count = self
            .browser_result
            .as_ref()
            .map_or(0, |result| result.total);
        let count_label = count.to_string();
        for (index, caption) in [
            format!("{}  {columns}", lang.pick("Spalten", "Columns")),
            format!("{}  {count_label}", lang.pick("Einträge", "Entries")),
        ]
        .iter()
        .enumerate()
        {
            let badge = rect(
                head.right() - 103.0 * (2 - index) as f32,
                head.top() + 8.0,
                97.0,
                28.0,
            );
            body.painter().rect_filled(badge, 8, c.selected);
            words(
                &body,
                badge.center(),
                Align2::CENTER_CENTER,
                caption,
                font(11.0, true),
                c.text,
            );
        }
        let tabs = rect(head.left(), head.bottom() + 13.0, head.width(), 56.0);
        body.painter().rect(
            tabs,
            14,
            c.panel,
            Stroke::new(1.0, c.border),
            egui::StrokeKind::Inside,
        );
        for (index, (marker, caption)) in [
            (icon::ROWS, lang.pick("Daten", "Data")),
            (
                icon::TREE,
                lang.pick("Spalten & Details", "Columns & details"),
            ),
        ]
        .into_iter()
        .enumerate()
        {
            let selected = state.details == (index == 1);
            let bounds = rect(
                tabs.left() + 5.0 + index as f32 * (tabs.width() / 2.0 - 4.0),
                tabs.top() + 5.0,
                tabs.width() / 2.0 - 6.0,
                46.0,
            );
            if (Control {
                bg: if selected { c.raised } else { c.panel },
                border: if selected {
                    c.border
                } else {
                    egui::Color32::TRANSPARENT
                },
                radius: 10,
                icon: Some(marker),
                ..Control::new(caption, if selected { c.primary } else { c.text })
            })
            .show(&mut body, bounds)
            .clicked()
            {
                state.details = index == 1;
            }
        }
        let toolbar = rect(tabs.left(), tabs.bottom() + 13.0, tabs.width(), 61.0);
        body.painter().rect(
            toolbar,
            14,
            c.panel,
            Stroke::new(1.0, c.border),
            egui::StrokeKind::Inside,
        );
        let data_rect =
            Rect::from_min_max(pos2(toolbar.left(), toolbar.bottom() + 12.0), body_rect.max);
        if state.details {
            let key = lang.pick("Im Query öffnen", "Open in query");
            let open = Control {
                icon: Some(icon::CODE),
                border: c.border,
                ..Control::new(key, c.text)
            };
            if open
                .show(
                    &mut body,
                    rect(toolbar.left() + 12.0, toolbar.top() + 9.0, 162.0, 42.0),
                )
                .clicked()
            {
                let (blocks, _) = self.project.active_query_mut();
                *blocks = vec![
                    Block::new(BlockKind::Select),
                    Block {
                        input: blocks::sql_name(&name),
                        ..Block::new(BlockKind::From)
                    },
                ];
                self.changed();
                self.preview();
                *close = true;
            }
            let mut details = style::region(&mut body, "schema-columns", data_rect);
            if let Some(page) = &self.browser_result {
                egui::ScrollArea::vertical().show(&mut details, |ui| {
                    ui.heading(lang.pick("Spalten", "Columns"));
                    egui::Grid::new("column-metadata")
                        .striped(true)
                        .show(ui, |ui| {
                            for heading in [
                                lang.pick("Name", "Name"),
                                lang.pick("Typ", "Type"),
                                lang.pick("Standardwert", "Default"),
                                lang.pick("Eigenschaften", "Properties"),
                            ] {
                                ui.strong(heading);
                            }
                            ui.end_row();
                            for column in &page.columns {
                                ui.label(&column.name);
                                ui.code(&column.declared_type);
                                ui.code(column.default_sql.as_deref().unwrap_or("—"));
                                ui.horizontal(|ui| {
                                    if column.primary_key > 0 {
                                        ui.code(format!("PK {}", column.primary_key));
                                    }
                                    if column.required {
                                        ui.code("NOT NULL");
                                    }
                                    if column.hidden > 0 {
                                        ui.label(lang.pick(
                                            "Generiert / ausgeblendet",
                                            "Generated / hidden",
                                        ));
                                    }
                                });
                                ui.end_row();
                            }
                        });
                    if !page.foreign_keys.is_empty() {
                        ui.separator();
                        ui.heading(lang.pick("Fremdschlüssel", "Foreign keys"));
                        for key in &page.foreign_keys {
                            ui.code(format!(
                                "{} → {}.{}   ·   ON UPDATE {}   ·   ON DELETE {}",
                                key.column,
                                key.target_table,
                                key.target_column.as_deref().unwrap_or("PK"),
                                key.on_update,
                                key.on_delete
                            ));
                        }
                    }
                    if !page.indexes.is_empty() {
                        ui.separator();
                        ui.heading(lang.pick("Indizes", "Indexes"));
                        for index in &page.indexes {
                            ui.code(format!(
                                "{}{} ({}){}",
                                if index.unique { "UNIQUE " } else { "" },
                                index.name,
                                index.columns.join(", "),
                                if index.partial { " · PARTIAL" } else { "" }
                            ));
                        }
                    }
                    if state.advanced && !page.definition.is_empty() {
                        ui.separator();
                        ui.heading(lang.pick("SQL-Definition", "SQL definition"));
                        ui.code(&page.definition);
                    }
                });
            } else {
                details.label(lang.pick(
                    "Tabellendetails werden geladen …",
                    "Loading table details …",
                ));
            }
            return;
        }

        let page_size = crate::database::TABLE_PAGE_SIZE;
        let pages = count.div_ceil(page_size).max(1);
        if let Some(result) = &self.browser_result {
            state.page = result.page;
        }
        let start = state.page * page_size;
        let end = (start + page_size).min(count);
        let entries = format!(
            "{} {}–{} {} {count_label}",
            lang.pick("Einträge", "Entries"),
            (start + 1).min(end),
            end,
            lang.pick("von", "of")
        );
        words(
            &body,
            toolbar.left_center() + vec2(16.0, 0.0),
            Align2::LEFT_CENTER,
            &entries,
            font(14.0, true),
            c.text,
        );
        let pages_rect = rect(toolbar.right() - 170.0, toolbar.top() + 8.0, 160.0, 45.0);
        body.painter().rect(
            pages_rect,
            8,
            c.raised,
            Stroke::new(1.0, c.border),
            egui::StrokeKind::Inside,
        );
        let page_label = format!(
            "{} {} {} {pages}",
            lang.pick("Seite", "Page"),
            state.page + 1,
            lang.pick("von", "of")
        );
        words(
            &body,
            pages_rect.center(),
            Align2::CENTER_CENTER,
            &page_label,
            font(12.0, true),
            c.text,
        );
        for (right, tip) in [
            (false, lang.pick("Vorige Seite", "Previous page")),
            (true, lang.pick("Nächste Seite", "Next page")),
        ] {
            let x = if right {
                pages_rect.right() - 36.0
            } else {
                pages_rect.left()
            };
            let enabled = if right {
                state.page + 1 < pages
            } else {
                state.page > 0
            };
            body.add_enabled_ui(enabled && !self.busy, |ui| {
                let marker = if right {
                    icon::CHEVRON
                } else {
                    icon::CHEVRON_LEFT
                };
                if Control::icon(marker, tip, c.text)
                    .show(ui, rect(x, pages_rect.top(), 36.0, 45.0))
                    .clicked()
                {
                    state.page = if right {
                        state.page + 1
                    } else {
                        state.page - 1
                    };
                    self.inspect_table(name.clone(), state.page);
                }
            });
        }
        let mut data = style::region(&mut body, ("browser-data", state.page, &name), data_rect);
        if let Some(page) = &self.browser_result {
            use crate::database::{Cell, QueryResult};
            let result = &page.data;
            let page = QueryResult {
                columns: std::iter::once("#".into())
                    .chain(result.columns.iter().cloned())
                    .collect(),
                rows: result
                    .rows
                    .iter()
                    .enumerate()
                    .map(|(i, row)| {
                        std::iter::once(Cell::Integer((start + i + 1) as i64))
                            .chain(row.iter().cloned())
                            .collect()
                    })
                    .collect(),
                truncated: result.truncated,
                elapsed: result.elapsed,
            };
            table_with_rows(&mut data, &page, c, 76.0, true);
        } else if self.busy {
            data.spinner();
        } else if let Some(error) = &self.error {
            data.label(error);
        }
    }

    fn workshop(&mut self, ui: &mut Ui, screen: egui::Vec2, c: Colors) -> bool {
        let lang = self.language;
        ui.set_width((screen.x * 0.72).clamp(400.0, 960.0));
        let close = modal_header(ui, "NodeQL Workshop", icon::SCHOOL, c);
        ui.add_space(12.0);
        let mut choice = None;
        egui::ScrollArea::vertical()
            .max_height(screen.y * 0.72)
            .show(ui, |ui| {
                for (row, paths) in super::workshop::WORKSHOP.paths.chunks(2).enumerate() {
                    ui.columns(2, |columns| {
                        for (column, path) in paths.iter().enumerate() {
                            let index = row * 2 + column;
                            let progress = self.session.lessons.get(&path.id);
                            let done = progress.map_or(0, |progress| {
                                path.steps
                                    .iter()
                                    .filter(|step| progress.completed.contains(&step.id))
                                    .count()
                            });
                            Frame::new()
                                .fill(c.raised)
                                .stroke(Stroke::new(1.0, c.border))
                                .corner_radius(14)
                                .inner_margin(16)
                                .show(&mut columns[column], |ui| {
                                    ui.label(
                                        RichText::new(path.title.at(lang)).size(18.0).strong(),
                                    );
                                    ui.label(
                                        RichText::new(path.description.at(lang)).color(c.muted),
                                    );
                                    ui.add_space(5.0);
                                    ui.label(format!(
                                        "{} / {} {}",
                                        done,
                                        path.steps.len(),
                                        lang.pick("Schritte", "steps")
                                    ));
                                    let label = if done == path.steps.len() {
                                        lang.pick("Wiederholen", "Repeat")
                                    } else if progress.is_some() {
                                        lang.pick("Fortsetzen", "Resume")
                                    } else {
                                        lang.pick("Lernpfad starten", "Start learning path")
                                    };
                                    if ui
                                        .add_enabled(!self.busy, egui::Button::new(label))
                                        .clicked()
                                    {
                                        choice = Some((index, done == path.steps.len()));
                                    }
                                });
                        }
                    });
                    ui.add_space(7.0);
                }
            });
        if let Some((course, repeat)) = choice {
            self.begin_practice(course, repeat);
        }
        close || choice.is_some()
    }
}

fn reporter_tray(ui: &mut Ui, lang: Language) {
    ui.horizontal_wrapped(|ui| {
        ui.label(lang.pick("In ein Feld ziehen", "Drag into a field"));
        for (name, preset) in [
            (
                lang.pick("Text", "Text"),
                Preset::Literal(LiteralKind::Text, "Text"),
            ),
            (
                lang.pick("Zahl", "Number"),
                Preset::Literal(LiteralKind::Integer, "1"),
            ),
            (lang.pick("Spalte", "Column"), Preset::Column),
            (
                lang.pick("Funktion", "Function"),
                Preset::Function("abs", "0"),
            ),
            (lang.pick("Alias", "Alias"), Preset::Alias),
        ] {
            let response = ui.add(egui::Button::new(name).sense(egui::Sense::drag()));
            response.dnd_set_drag_payload(Drag::Palette(Action::Expression(preset)));
        }
    });
}

fn reporter_editor(
    ui: &mut Ui,
    reporter: &mut Reporter,
    lang: Language,
    depth: usize,
    template: &impl Fn(Preset) -> Reporter,
) {
    let zone = ui.group(|ui| match reporter {
        Reporter::Expression { sql } => {
            ui.text_edit_singleline(sql);
        }
        Reporter::Literal { kind, value } => {
            ui.horizontal(|ui| {
                egui::ComboBox::from_id_salt("literal")
                    .selected_text(format!("{kind:?}"))
                    .show_ui(ui, |ui| {
                        for option in [
                            LiteralKind::Null,
                            LiteralKind::Integer,
                            LiteralKind::Real,
                            LiteralKind::Text,
                            LiteralKind::Blob,
                        ] {
                            ui.selectable_value(kind, option, format!("{option:?}"));
                        }
                    });
                if *kind != LiteralKind::Null {
                    ui.text_edit_singleline(value);
                }
            });
        }
        Reporter::Function { name, arguments } => {
            egui::ComboBox::from_id_salt("function")
                .selected_text(name.to_ascii_uppercase())
                .height(320.0)
                .show_ui(ui, |ui| {
                    for function in &*FUNCTIONS {
                        let label = format!(
                            "{}  ·  {}",
                            function.name.to_ascii_uppercase(),
                            function.category
                        );
                        let row =
                            ui.selectable_label(name.eq_ignore_ascii_case(&function.name), label);
                        let row =
                            if function.version_dependent {
                                row.on_hover_text(lang.pick(
                                    "Abhängig vom SQLite-Build",
                                    "Depends on the SQLite build",
                                ))
                            } else {
                                row
                            };
                        if row.clicked() {
                            name.clone_from(&function.name);
                            *arguments = function
                                .arguments
                                .iter()
                                .map(Reporter::expression)
                                .collect();
                        }
                    }
                });
            edit_reporter_list(ui, arguments, lang, depth, template);
            if let Some(function) = FUNCTIONS
                .iter()
                .find(|function| function.name.eq_ignore_ascii_case(name))
                && (arguments.len() < function.min
                    || function.max.is_some_and(|max| arguments.len() > max))
            {
                ui.label(lang.pick(
                    "Prüfe die Anzahl der Argumente.",
                    "Check the number of arguments.",
                ));
            }
        }
        Reporter::Alias { expression, name } => {
            ui.horizontal(|ui| {
                ui.label("AS");
                ui.text_edit_singleline(name);
            });
            ui.push_id("alias-expression", |ui| {
                reporter_editor(ui, expression, lang, depth + 1, template)
            });
        }
        Reporter::InQuery { column, query } => {
            ui.push_id("in-column", |ui| {
                reporter_editor(ui, column, lang, depth + 1, template)
            });
            ui.label("IN");
            ui.text_edit_multiline(query);
        }
        Reporter::List { items } => edit_reporter_list(ui, items, lang, depth, template),
    });
    if depth < 10
        && let Some(payload) = zone.response.dnd_hover_payload::<Drag>()
        && let Drag::Palette(Action::Expression(preset)) = *payload
        && zone.response.dnd_release_payload::<Drag>().is_some()
    {
        *reporter = template(preset);
    }
    if depth == 0
        && !matches!(reporter, Reporter::List { .. })
        && ui
            .button(lang.pick("Weitere Spalte hinzufügen", "Add another column"))
            .clicked()
    {
        *reporter = Reporter::List {
            items: vec![reporter.clone(), Reporter::expression("id")],
        };
    }
}

fn edit_reporter_list(
    ui: &mut Ui,
    items: &mut Vec<Reporter>,
    lang: Language,
    depth: usize,
    template: &impl Fn(Preset) -> Reporter,
) {
    let mut remove = None;
    for (index, item) in items.iter_mut().enumerate() {
        ui.push_id(index, |ui| {
            ui.horizontal(|ui| {
                if ui.small_button("×").clicked() {
                    remove = Some(index);
                }
                reporter_editor(ui, item, lang, depth + 1, template);
            });
        });
    }
    if let Some(index) = remove {
        items.remove(index);
    }
    if items.len() < 32
        && ui
            .small_button(lang.pick("Feld hinzufügen", "Add field"))
            .clicked()
    {
        items.push(Reporter::expression("NULL"));
    }
}

fn buttons(ui: &mut Ui, lang: Language, save: &mut bool, cancel: &mut bool) {
    ui.add_space(9.0);
    ui.horizontal(|ui| {
        if ui.button(lang.pick("Abbrechen", "Cancel")).clicked() {
            *cancel = true;
        }
        if ui.button(lang.pick("Übernehmen", "Apply")).clicked() {
            *save = true;
        }
    });
}

fn modal_frame(c: Colors, margin: i8) -> Frame {
    Frame::new()
        .fill(c.panel)
        .stroke(Stroke::new(1.0, c.border))
        .corner_radius(16)
        .inner_margin(margin)
}

fn title(ui: &mut Ui, text: &str, c: Colors) {
    ui.label(RichText::new(text).font(font(22.0, true)).color(c.text));
}

fn modal_header(ui: &mut Ui, text: &str, marker: char, c: Colors) -> bool {
    let (bounds, _) =
        ui.allocate_exact_size(vec2(ui.available_width(), 44.0), egui::Sense::hover());
    glyph(
        ui,
        bounds.left_center() + vec2(15.0, 0.0),
        marker,
        23.0,
        c.primary,
    );
    words(
        ui,
        bounds.left_center() + vec2(35.0, 0.0),
        Align2::LEFT_CENTER,
        text,
        font(22.0, true),
        c.text,
    );
    Control::icon(icon::CLOSE, "Close", c.text)
        .show(ui, rect(bounds.right() - 42.0, bounds.top(), 42.0, 42.0))
        .clicked()
}
