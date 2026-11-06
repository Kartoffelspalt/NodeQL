use super::{
    NodeQlApp,
    blocks::{self, Puzzle},
    catalog::{Action, Category, ITEMS},
    dialogs::{BrowserView, Dialog},
    style::{
        self, Colors, Control, Dock, Language, font, glyph, hit, icon, rect, rule, show_logo,
        text_width, words,
    },
};
use crate::{
    database::QueryResult,
    export::Format,
    model::{MAX_TABS, QueryTab},
};
use eframe::egui::{
    self, Align2, Color32, CursorIcon, Id, Pos2, Rect, Response, Sense, Stroke, StrokeKind, Ui,
    pos2, vec2,
};
use std::sync::atomic::Ordering;

const RAIL: f32 = 72.0;
const TOOLBAR: f32 = 68.0;
const TAB_BAR: f32 = 52.0;
const HEADER: f32 = 38.0;
const GAP: f32 = 8.0;

#[derive(Clone, Copy)]
struct TabDrag(usize);

impl NodeQlApp {
    pub(super) fn render(&mut self, ui: &mut Ui) {
        self.poll();
        let ctx = ui.ctx().clone();
        if ctx.input(|i| i.viewport().close_requested()) && !self.allow_close {
            if self.practice.is_some() {
                if self.busy {
                    self.cancel.store(true, Ordering::Relaxed);
                    ctx.send_viewport_cmd(egui::ViewportCommand::CancelClose);
                    return;
                }
                self.leave_practice();
            }
            if self.can_discard() {
                self.flush_session();
                self.cancel.store(true, Ordering::Relaxed);
                self.allow_close = true;
                ctx.send_viewport_cmd(egui::ViewportCommand::Close);
            } else {
                ctx.send_viewport_cmd(egui::ViewportCommand::CancelClose);
            }
        }
        if self.dialog.is_none() && self.field_editor.is_none() {
            if self.pending.is_none() && !ctx.egui_wants_keyboard_input() {
                if shortcut(
                    &ctx,
                    egui::Modifiers::COMMAND | egui::Modifiers::SHIFT,
                    egui::Key::Z,
                ) || shortcut(&ctx, egui::Modifiers::COMMAND, egui::Key::Y)
                {
                    self.restore_edit(true);
                } else if shortcut(&ctx, egui::Modifiers::COMMAND, egui::Key::Z) {
                    self.restore_edit(false);
                }
            }
            if self.practice.is_none()
                && self.pending.is_none()
                && shortcut(&ctx, egui::Modifiers::COMMAND, egui::Key::S)
            {
                self.save(false);
            }
            if shortcut(&ctx, egui::Modifiers::COMMAND, egui::Key::Enter) {
                self.run();
            }
            if self.practice.is_none()
                && !self.busy
                && shortcut(&ctx, egui::Modifiers::COMMAND, egui::Key::O)
            {
                self.open_project();
            }
            if self.practice.is_none()
                && !self.busy
                && shortcut(&ctx, egui::Modifiers::COMMAND, egui::Key::N)
            {
                self.new_project();
            }
        }
        self.refresh_preview(&ctx);
        self.refresh_session(&ctx);
        let window = ui.max_rect();
        let colors = self.theme.colors();
        ui.painter().rect_filled(window, 0, colors.top);
        self.draw_toolbar(
            ui,
            rect(window.left(), window.top(), window.width(), TOOLBAR),
            colors,
        );

        let extra = if self.practice.is_some() {
            self.draw_lesson(
                ui,
                rect(window.left(), window.top() + TOOLBAR, window.width(), 104.0),
                colors,
            );
            104.0
        } else {
            0.0
        };
        let body = Rect::from_min_max(window.min + vec2(0.0, TOOLBAR + extra), window.max);
        let width = self
            .runtime_width
            .clamp(260.0, (body.width() - RAIL - 420.0).max(260.0));
        let palette_width = self
            .palette_width
            .clamp(200.0, (body.width() - RAIL - width - 190.0).max(200.0));
        let bottom_height =
            (body.height() * (1.0 - self.split)).clamp(150.0, (body.height() - 160.0).max(150.0));
        let upper = if self.dock == Dock::RightSplit {
            body
        } else {
            Rect::from_min_max(body.min, pos2(body.right(), body.bottom() - bottom_height))
        };
        let right = rect(upper.right() - width, upper.top(), width, upper.height());
        let rail = rect(upper.left(), upper.top(), RAIL, upper.height());
        let palette = rect(rail.right(), upper.top(), palette_width, upper.height());
        let workspace = Rect::from_min_max(
            pos2(palette.right(), upper.top()),
            pos2(right.left(), upper.bottom()),
        );
        let tabs = rect(
            workspace.left(),
            workspace.top(),
            workspace.width(),
            TAB_BAR,
        );
        let canvas = Rect::from_min_max(pos2(workspace.left(), tabs.bottom()), workspace.max);

        self.draw_categories(ui, rail, colors);
        self.draw_palette(ui, palette, colors);
        self.draw_tabs(ui, tabs, colors);
        self.draw_canvas(ui, canvas, rail.union(palette), colors);
        self.save_canvas_view();

        let (sql, output, resize_y) = match self.dock {
            Dock::RightSplit => {
                let height = ((right.height() - GAP) * self.split)
                    .clamp(100.0, (right.height() - 108.0).max(100.0));
                let sql = rect(right.left(), right.top(), right.width(), height);
                let output = Rect::from_min_max(pos2(right.left(), sql.bottom() + GAP), right.max);
                (sql, output, output.top())
            }
            Dock::PreviewBottom => (
                right,
                Rect::from_min_max(pos2(body.left(), upper.bottom()), body.max),
                upper.bottom(),
            ),
            Dock::CommandBottom => (
                Rect::from_min_max(pos2(body.left(), upper.bottom()), body.max),
                right,
                upper.bottom(),
            ),
        };
        self.draw_sql(ui, sql, colors);
        self.draw_output(ui, output, colors);

        let resize_palette = vertical_handle(
            ui,
            "palette-width",
            palette.right(),
            palette.center().y,
            colors,
        );
        if resize_palette.dragged() {
            self.palette_width =
                (palette_width + resize_palette.drag_delta().x).clamp(200.0, 520.0);
        }
        for (name, pane) in [("command-width", sql), ("result-width", output)] {
            if pane.left() == right.left() {
                let resize = vertical_handle(ui, name, right.left(), pane.center().y, colors);
                if resize.dragged() {
                    self.runtime_width = (width - resize.drag_delta().x).clamp(260.0, 720.0);
                }
            }
        }
        let handle_center = if self.dock == Dock::RightSplit {
            right.center().x
        } else {
            body.center().x
        };
        let resize_split = horizontal_handle(ui, handle_center, resize_y, colors);
        if resize_split.dragged() {
            self.split = (self.split + resize_split.drag_delta().y / body.height().max(1.0))
                .clamp(0.20, 0.78);
        }
        self.draw_dialogs(ui);
    }

    fn draw_toolbar(&mut self, ui: &mut Ui, bounds: Rect, c: Colors) {
        let mut ui = style::region(ui, "toolbar", bounds);
        let lang = self.language;
        ui.painter().rect_filled(bounds, 0, c.top);
        rule(&ui, bounds.left_bottom(), bounds.right_bottom(), c.border);
        if self.practice.is_some() {
            self.draw_practice_toolbar(&mut ui, bounds, c);
            return;
        }
        let mut right = bounds.right() - 16.0;
        let workshop = Control {
            icon: Some(icon::SCHOOL),
            bg: c.primary,
            size: 16.0,
            ..Control::new("Workshop", c.on_primary)
        };
        let workshop_width = workshop.width(&ui, 20.0).max(154.0);
        right -= workshop_width;
        if workshop
            .show(
                &mut ui,
                rect(right, bounds.top() + 7.0, workshop_width, 54.0),
            )
            .clicked()
        {
            self.dialog = Some(Dialog::Workshop);
        }
        right -= 52.0;
        if Control::icon(
            icon::SETTINGS,
            lang.pick("Einstellungen", "Settings"),
            c.text,
        )
        .show(&mut ui, rect(right, bounds.top() + 12.0, 44.0, 44.0))
        .clicked()
        {
            self.dialog = Some(Dialog::Settings(0));
        }
        right -= 44.0;
        if Control::icon(
            icon::HELP,
            lang.pick("Kurze Einführung", "Quick introduction"),
            c.text,
        )
        .show(&mut ui, rect(right, bounds.top() + 12.0, 44.0, 44.0))
        .clicked()
        {
            self.dialog = Some(Dialog::Introduction(0));
        }

        let left_bounds = rect(
            bounds.left(),
            bounds.top(),
            right - bounds.left() - 6.0,
            TOOLBAR,
        );
        let mut left_ui = style::region(&mut ui, "toolbar-tools", left_bounds);
        egui::ScrollArea::horizontal()
            .id_salt("toolbar-scroll")
            .scroll_bar_visibility(egui::scroll_area::ScrollBarVisibility::AlwaysHidden)
            .show(&mut left_ui, |ui| {
                let min = ui.cursor().min;
                let end = self.draw_toolbar_tools(ui, min, c);
                ui.allocate_space(vec2(end - min.x + 8.0, TOOLBAR - 1.0));
            });
    }

    fn draw_practice_toolbar(&mut self, ui: &mut Ui, bounds: Rect, c: Colors) {
        let lang = self.language;
        show_logo(ui, &self.logo, bounds.min + vec2(16.0, 16.0), 36.0);
        let mut row = style::region(ui, "workshop-toolbar", bounds.shrink2(vec2(64.0, 12.0)));
        row.horizontal_wrapped(|ui| {
            ui.heading(egui::RichText::new("NodeQL Workshop").color(c.text));
            if ui
                .add_enabled(
                    !self.busy,
                    egui::Button::new(lang.pick("Lernpfade", "Learning paths")),
                )
                .clicked()
            {
                self.dialog = Some(Dialog::Workshop);
            }
            if ui
                .add_enabled(
                    self.busy || self.visible_sql().is_ok(),
                    egui::Button::new(if self.busy {
                        lang.pick("Abbrechen", "Cancel")
                    } else {
                        lang.pick("SQLite ausführen", "Run SQLite")
                    }),
                )
                .clicked()
            {
                if self.busy {
                    self.cancel.store(true, Ordering::Relaxed);
                } else {
                    self.run();
                }
            }
            ui.selectable_value(&mut self.advanced, false, lang.pick("Einfach", "Simple"));
            ui.selectable_value(&mut self.advanced, true, lang.pick("Erweitert", "Advanced"));
            if ui
                .add_enabled(
                    !self.busy,
                    egui::Button::new(lang.pick("Workshop verlassen", "Leave workshop")),
                )
                .clicked()
            {
                self.leave_practice();
            }
        });
    }

    fn draw_lesson(&mut self, ui: &mut Ui, bounds: Rect, c: Colors) {
        let Some(practice) = &self.practice else {
            return;
        };
        let lang = self.language;
        let lesson = practice.lesson();
        let title = format!(
            "{} / {}  ·  {}",
            practice.step + 1,
            practice.course().steps.len(),
            lesson.title
        );
        let final_step = practice.step + 1 == practice.course().steps.len();
        let instruction = if practice.show_hint {
            &lesson.hint
        } else {
            &lesson.instruction
        };
        let ready = self.practice_target().is_none();
        ui.painter().rect_filled(bounds, 0, c.raised);
        rule(ui, bounds.left_bottom(), bounds.right_bottom(), c.border);
        let mut step_ui = style::region(ui, "lesson-step", bounds.shrink2(vec2(16.0, 6.0)));
        step_ui.horizontal_wrapped(|ui| {
            ui.heading(title);
            if ui.button(lang.pick("Hinweis", "Hint")).clicked()
                && let Some(practice) = &mut self.practice
            {
                practice.show_hint = !practice.show_hint;
            }
            if ui
                .add_enabled(
                    ready && !self.busy,
                    egui::Button::new(if final_step {
                        lang.pick("Abschließen", "Finish")
                    } else {
                        lang.pick("Weiter", "Next")
                    }),
                )
                .clicked()
            {
                self.finish_practice_step();
            }
        });
        step_ui.label(instruction);
        if ready {
            step_ui.label(lang.pick(
                "Alle benötigten Blöcke sind vorhanden.",
                "All required blocks are in place.",
            ));
        } else if let Some(node) = self.practice_target() {
            step_ui.label(format!(
                "{} {}",
                lang.pick("Nächster Block", "Next block"),
                node.label(self.advanced, lang)
            ));
        }
    }

    fn draw_toolbar_tools(&mut self, ui: &mut Ui, min: Pos2, c: Colors) -> f32 {
        let lang = self.language;
        let mut x = min.x + 16.0;
        let y = min.y;
        show_logo(ui, &self.logo, pos2(x, y + 16.0), 36.0);
        words(
            ui,
            pos2(x + 44.0, y + 34.0),
            Align2::LEFT_CENTER,
            "NodeQL",
            font(22.0, true),
            c.text,
        );
        let brand_width = 44.0 + text_width(ui, "NodeQL", font(22.0, true));
        let brand = hit(ui, rect(x, y + 12.0, brand_width, 44.0), Sense::click())
            .on_hover_text(lang.pick("Projekt", "Project"));
        egui::Popup::menu(&brand).show(|ui| self.project_menu(ui));
        x += brand_width + 16.0;
        let mount = Control {
            icon: Some(icon::STORAGE),
            border: c.border,
            ..Control::new(lang.pick("DB laden", "Mount .db"), c.text)
        };
        let mount_width = mount.width(ui, 15.0).max(116.0);
        ui.add_enabled_ui(!self.busy, |ui| {
            if mount
                .show(ui, rect(x, y + 12.0, mount_width, 44.0))
                .clicked()
            {
                self.open_database();
            }
            x += mount_width + 8.0;
            if (Control {
                border: c.border,
                ..Control::icon(
                    icon::TABLE,
                    lang.pick("Tabellenbrowser", "Table browser"),
                    c.text,
                )
            })
            .show(ui, rect(x, y + 12.0, 44.0, 44.0))
            .clicked()
            {
                let mut view = BrowserView::default();
                view.advanced = self.advanced;
                self.dialog = Some(Dialog::Tables(view));
                if self.browser_table.is_none()
                    && let Some(table) = self.schema.first()
                {
                    self.browse_table(table.name.clone());
                }
            }
        });
        x += 52.0;
        let running = self.busy && self.pending.is_none();
        let run = Control {
            icon: Some(if running { icon::STOP } else { icon::PLAY }),
            bg: c.primary,
            ..Control::new(
                if running {
                    lang.pick("Abbrechen", "Cancel")
                } else {
                    lang.pick("SQLite ausführen", "Run SQLite")
                },
                c.on_primary,
            )
        };
        let run_width = run.width(ui, 18.0).max(138.0);
        ui.add_enabled_ui(
            running || !self.busy && self.database_available && self.visible_sql().is_ok(),
            |ui| {
                if run.show(ui, rect(x, y + 12.0, run_width, 44.0)).clicked() {
                    if running {
                        self.cancel.store(true, Ordering::Relaxed);
                    } else {
                        self.run();
                    }
                }
            },
        );
        x += run_width + 8.0;
        let connect = Control {
            bg: if self.link_mode {
                c.selected
            } else {
                Color32::TRANSPARENT
            },
            ..Control::icon(
                if self.link_mode {
                    icon::LINK
                } else {
                    icon::PAINT
                },
                lang.pick("Spaltenquellen verbinden", "Connect column sources"),
                c.text,
            )
        };
        if connect.show(ui, rect(x, y + 12.0, 44.0, 44.0)).clicked() {
            self.link_mode = !self.link_mode;
        }
        x += 48.0;

        let names = [
            lang.pick("Einfach", "Simple"),
            lang.pick("Erweitert", "Advanced"),
        ];
        let size = 14.0;
        let segment_width = names
            .iter()
            .map(|name| text_width(ui, name, font(size, true)))
            .fold(0.0, f32::max)
            + 42.0;
        let segment = rect(x, y + 14.0, segment_width * 2.0, 40.0);
        for (i, name) in names.into_iter().enumerate() {
            let selected = self.advanced == (i == 1);
            let bounds = rect(
                x + i as f32 * segment_width,
                segment.top(),
                segment_width,
                segment.height(),
            );
            let response = hit(ui, bounds, Sense::click());
            response
                .widget_info(|| egui::WidgetInfo::selected(egui::Role::Tab, true, selected, name));
            let rounding = if i == 0 {
                egui::CornerRadius {
                    nw: 14,
                    sw: 14,
                    ne: 0,
                    se: 0,
                }
            } else {
                egui::CornerRadius {
                    nw: 0,
                    sw: 0,
                    ne: 14,
                    se: 14,
                }
            };
            let fg = if selected && self.theme != style::Theme::Light {
                c.primary
            } else {
                c.text
            };
            ui.painter().rect_filled(
                bounds,
                rounding,
                if selected {
                    c.selected
                } else if response.hovered() {
                    c.raised
                } else {
                    c.panel
                },
            );
            words(
                ui,
                bounds.center() + vec2(if selected { 10.0 } else { 0.0 }, 0.0),
                Align2::CENTER_CENTER,
                name,
                font(size, true),
                fg,
            );
            if selected {
                glyph(
                    ui,
                    bounds.left_center() + vec2(20.0, 0.0),
                    icon::CHECK,
                    18.0,
                    fg,
                );
            }
            if response.clicked() {
                self.advanced = i == 1;
            }
        }
        ui.painter()
            .rect_stroke(segment, 14, Stroke::new(1.0, c.primary), StrokeKind::Inside);
        rule(ui, segment.center_top(), segment.center_bottom(), c.primary);
        x = segment.right() + 8.0;
        let language_width = text_width(ui, lang.native(), font(14.0, false)) + 26.0;
        let language_rect = rect(x, y + 14.0, language_width, 40.0);
        let language_button = hit(ui, language_rect, Sense::click());
        words(
            ui,
            language_rect.left_center(),
            Align2::LEFT_CENTER,
            lang.native(),
            font(14.0, false),
            c.text,
        );
        glyph(
            ui,
            language_rect.right_center() - vec2(8.0, 0.0),
            icon::DOWN,
            20.0,
            c.text,
        );
        egui::Popup::menu(&language_button).show(|ui| {
            for language in [Language::German, Language::English] {
                if ui
                    .selectable_label(lang == language, language.native())
                    .clicked()
                {
                    self.language = language;
                    ui.close();
                }
            }
        });
        language_rect.right()
    }

    fn project_menu(&mut self, ui: &mut Ui) {
        let lang = self.language;
        ui.add_enabled_ui(!self.busy, |ui| {
            if ui
                .button(lang.pick("Neues Projekt", "New project"))
                .clicked()
            {
                self.new_project();
                ui.close();
            }
            if ui
                .button(lang.pick("Projekt öffnen …", "Open project …"))
                .clicked()
            {
                self.open_project();
                ui.close();
            }
        });
        if ui
            .button(lang.pick("Projekt speichern", "Save project"))
            .clicked()
        {
            self.save(false);
            ui.close();
        }
        if ui
            .button(lang.pick("Projekt speichern unter …", "Save project as …"))
            .clicked()
        {
            self.save(true);
            ui.close();
        }
        ui.add_enabled_ui(!self.busy && !self.session.recent.is_empty(), |ui| {
            ui.menu_button(lang.pick("Zuletzt geöffnet", "Open recent"), |ui| {
                for entry in self.session.recent.clone() {
                    if ui
                        .button(entry.name)
                        .on_hover_text(entry.path.display().to_string())
                        .clicked()
                    {
                        self.open_project_path(entry.path);
                        ui.close();
                    }
                }
            });
        });
        ui.separator();
        if ui
            .add_enabled(
                !self.busy,
                egui::Button::new(lang.pick("Neue Datenbank …", "New database …")),
            )
            .clicked()
        {
            self.new_database();
            ui.close();
        }
        if ui
            .button(lang.pick("Demo-Datenbank öffnen", "Open demo database"))
            .clicked()
            && !self.busy
        {
            let mut project = self.project.clone();
            project.database = None;
            project.workspace.no_database = false;
            self.connect(project, self.path.clone(), true);
            ui.close();
        }
    }

    fn new_project(&mut self) {
        self.dialog = Some(Dialog::NewProject {
            name: "NodeQL Project".into(),
            autosave: true,
            database: false,
        });
    }

    fn draw_categories(&mut self, ui: &mut Ui, bounds: Rect, c: Colors) {
        let mut ui = style::region(ui, "categories", bounds);
        ui.spacing_mut().item_spacing.y = 0.0;
        egui::ScrollArea::vertical()
            .id_salt("category-scroll")
            .scroll_bar_visibility(egui::scroll_area::ScrollBarVisibility::AlwaysHidden)
            .show(&mut ui, |ui| {
                for category in Category::ALL {
                    let (slot, _) = ui.allocate_exact_size(vec2(RAIL, 56.0), Sense::hover());
                    let (glyph, color) = category.visual();
                    let active = self.category == category && self.search.is_empty();
                    let control = Control {
                        bg: if active {
                            color
                        } else {
                            color.gamma_multiply(0.16)
                        },
                        size: 25.0,
                        ..Control::icon(
                            glyph,
                            category.name(self.language),
                            if active { Color32::WHITE } else { color },
                        )
                    };
                    if control.show(ui, slot.shrink2(vec2(8.0, 4.0))).clicked() {
                        self.category = category;
                        self.search.clear();
                    }
                }
            });
        rule(&ui, bounds.right_top(), bounds.right_bottom(), c.top);
    }

    fn draw_palette(&mut self, ui: &mut Ui, bounds: Rect, c: Colors) {
        let mut ui = style::region(ui, "palette", bounds);
        let lang = self.language;
        let search = rect(
            bounds.left() + 12.0,
            bounds.top() + 12.0,
            bounds.width() - 30.0,
            48.0,
        );
        ui.painter().rect(
            search,
            10,
            c.raised,
            Stroke::new(1.0, c.border),
            StrokeKind::Inside,
        );
        glyph(
            &ui,
            search.left_center() + vec2(24.0, 0.0),
            icon::SEARCH,
            22.0,
            c.muted,
        );
        let input = rect(
            search.left() + 52.0,
            search.top() + 13.0,
            search.width() - 62.0,
            24.0,
        );
        let response = ui.put(
            input,
            egui::TextEdit::singleline(&mut self.search)
                .font(font(16.0, false))
                .frame(egui::Frame::NONE),
        );
        if self.search.is_empty() && !response.has_focus() {
            words(
                &ui,
                input.left_center(),
                Align2::LEFT_CENTER,
                lang.pick("Befehl suchen", "Search command"),
                font(16.0, false),
                c.muted,
            );
        }
        let query = self.search.trim().to_lowercase();
        let items = ITEMS
            .iter()
            .filter(|item| {
                if query.is_empty() {
                    item.category == self.category
                } else {
                    item.label(self.advanced, lang)
                        .to_lowercase()
                        .contains(&query)
                        || item.description(lang).to_lowercase().contains(&query)
                        || item.key.to_lowercase().contains(&query)
                }
            })
            .collect::<Vec<_>>();
        let title = if query.is_empty() {
            self.category.name(lang)
        } else {
            lang.pick("Suchergebnisse", "Search results")
        };
        words(
            &ui,
            pos2(search.left() + 2.0, bounds.top() + 79.0),
            Align2::LEFT_CENTER,
            title,
            font(12.0, true),
            c.text,
        );
        words(
            &ui,
            pos2(search.right() - 2.0, bounds.top() + 79.0),
            Align2::RIGHT_CENTER,
            &items.len().to_string(),
            font(11.0, false),
            c.muted,
        );
        let list = Rect::from_min_max(
            pos2(bounds.left() + 12.0, bounds.top() + 95.0),
            bounds.right_bottom() - vec2(12.0, 0.0),
        );
        let mut ui = style::region(&mut ui, "palette-cards", list);
        egui::ScrollArea::vertical()
            .id_salt(("palette", title))
            .auto_shrink([false, false])
            .show(&mut ui, |ui| {
                let width = (list.width() - 6.0).max(100.0);
                if items.is_empty() {
                    ui.label(if self.category == Category::Plugins && query.is_empty() {
                        lang.pick("Keine Plugins installiert", "No plugins installed")
                    } else {
                        lang.pick("Keine Befehle gefunden", "No commands found")
                    });
                }
                for item in items {
                    let label = item.label(self.advanced, lang);
                    let description = item.description(lang);
                    let action = item.action();
                    let is_join = action == Action::Clause(crate::model::BlockKind::Join);
                    let (shape_y, shape_h, description_y) = match item.key.as_str() {
                        "eventGreenFlag" => (10.0, 47.0, 67.0),
                        "sqlSelect" => (17.0, 39.0, 73.0),
                        "sqlFrom" => (12.0, 44.0, 67.0),
                        "sqlJoin" => (14.0, 54.0, 80.0),
                        _ => (12.0, 42.0, 67.0),
                    };
                    let description_galley = ui.painter().layout(
                        description.into(),
                        font(11.5, false),
                        c.text,
                        width - 18.0,
                    );
                    let lines = description_galley.rows.len().clamp(1, 3);
                    let lines = if lang == Language::German && item.category == Category::Query {
                        lines.max(2)
                    } else {
                        lines
                    };
                    let h = description_y + 14.5 * lines as f32 + 8.0;
                    let (card, _) = ui.allocate_exact_size(vec2(width, h), Sense::hover());
                    let response = ui.interact(
                        card,
                        Id::unique(("palette-item", &item.key)),
                        Sense::click_and_drag(),
                    );
                    let response = response.on_hover_cursor(CursorIcon::Grab);
                    ui.painter().rect(
                        card,
                        14,
                        if response.hovered() {
                            c.raised
                        } else {
                            c.panel
                        },
                        if self
                            .practice_target()
                            .is_some_and(|target| target.key() == item.key)
                        {
                            Stroke::new(2.0, c.primary)
                        } else {
                            Stroke::new(1.0, c.border)
                        },
                        StrokeKind::Inside,
                    );
                    let block = rect(
                        card.left() + 9.0,
                        card.top() + shape_y,
                        card.width() - 18.0,
                        shape_h,
                    );
                    let shape = match action {
                        Action::Trigger => Puzzle::Trigger,
                        Action::Expression(_) => Puzzle::Value,
                        Action::Clause(crate::model::BlockKind::Join) => Puzzle::Join,
                        _ if item.category == Category::Transactions => Puzzle::Terminal,
                        _ => Puzzle::Statement,
                    };
                    blocks::puzzle(
                        ui,
                        block,
                        shape,
                        item.color(),
                        if is_join { 0.7 } else { 0.94 },
                        None,
                    );
                    if action == Action::Trigger {
                        blocks::trigger_content(
                            ui,
                            block,
                            label,
                            if label.len() > 14 { 0.94 } else { 1.0 },
                        );
                    } else if is_join && !self.advanced {
                        palette_join(ui, block, lang);
                    } else {
                        let rows = if label.contains('\n') { 2 } else { 1 };
                        let size = if label.len() > 35 && rows == 1 {
                            10.8
                        } else {
                            13.0
                        };
                        let label_area = if rows == 1 {
                            block.shrink2(vec2(11.0, 2.0))
                        } else {
                            Rect::from_min_max(
                                block.min + vec2(11.0, 2.0),
                                block.max - vec2(10.0, 0.0),
                            )
                        };
                        blocks::clipped_text(
                            ui,
                            label_area,
                            label,
                            size,
                            true,
                            Color32::WHITE,
                            rows,
                        );
                    }
                    let help = rect(card.right() - 33.0, card.top() + 13.0, 18.0, 18.0);
                    ui.painter()
                        .circle_filled(help.center(), 8.0, Color32::from_white_alpha(56));
                    glyph(ui, help.center(), icon::HELP, 19.0, Color32::WHITE);
                    if hit(ui, help, Sense::click())
                        .on_hover_text(description)
                        .clicked()
                    {
                        self.dialog = Some(Dialog::Message {
                            title: label.into(),
                            text: description.into(),
                        });
                    } else if response.clicked()
                        && self.pending.is_none()
                        && !matches!(action, Action::Expression(_))
                    {
                        self.insert(action, None, None);
                    }
                    self.palette_drag(&response, action, card.min);
                    let desc_bounds = Rect::from_min_max(
                        pos2(card.left() + 9.0, card.top() + description_y),
                        card.max - vec2(8.0, 4.0),
                    );
                    blocks::clipped_text(ui, desc_bounds, description, 11.5, false, c.text, 3);
                    ui.add_space(2.0);
                }
            });
    }

    fn draw_tabs(&mut self, ui: &mut Ui, bounds: Rect, c: Colors) {
        let mut ui = style::region(ui, "query-tabs", bounds);
        let lang = self.language;
        ui.painter().rect_filled(bounds, 0, c.panel);
        rule(&ui, bounds.left_bottom(), bounds.right_bottom(), c.border);
        let order = rect(bounds.left() + 6.0, bounds.top() + 6.0, 32.0, 39.0);
        Control::icon(
            icon::ORDER,
            lang.pick("Ausführungsreihenfolge", "Query execution order"),
            c.muted,
        )
        .show(&mut ui, order);
        let add = rect(bounds.right() - 49.0, bounds.top() + 6.0, 42.0, 39.0);
        ui.add_enabled_ui(
            self.project.tab_count() < MAX_TABS && self.pending.is_none(),
            |ui| {
                if Control::icon(
                    icon::ADD,
                    lang.pick("Query hinzufügen", "Create query tab"),
                    c.text,
                )
                .show(ui, add)
                .clicked()
                {
                    self.project.workspace.tabs.push(QueryTab::default());
                    self.select_tab(self.project.tab_count() - 1);
                    self.changed();
                }
            },
        );
        let area = rect(
            order.right() + 2.0,
            bounds.top() + 6.0,
            add.left() - order.right() - 4.0,
            40.0,
        );
        let mut tabs_ui = style::region(&mut ui, "query-strip", area);
        let count = self.project.tab_count();
        let mut action = None;
        egui::ScrollArea::horizontal()
            .id_salt("tabs-scroll")
            .scroll_bar_visibility(egui::scroll_area::ScrollBarVisibility::AlwaysHidden)
            .show(&mut tabs_ui, |ui| {
                ui.horizontal(|ui| {
                    for index in 0..count {
                        let selected = index == self.project.workspace.active;
                        let (_, layout) = self.project.query(index);
                        let name = if layout.name.is_empty() {
                            format!("Query {}", index + 1)
                        } else {
                            layout.name.clone()
                        };
                        let width =
                            (text_width(ui, &name, font(12.0, true)) + 144.0).clamp(199.0, 266.0);
                        let (tab, response) =
                            ui.allocate_exact_size(vec2(width, 39.0), Sense::click());
                        let fill = if selected { c.primary } else { c.raised };
                        let fg = if selected { Color32::WHITE } else { c.text };
                        ui.painter().rect_filled(tab, 10, fill);
                        let point = tab.left_center() + vec2(21.0, 0.0);
                        ui.painter()
                            .circle_filled(point, 10.0, Color32::from_white_alpha(45));
                        words(
                            ui,
                            point,
                            Align2::CENTER_CENTER,
                            &(index + 1).to_string(),
                            font(11.0, true),
                            fg,
                        );
                        blocks::clipped_text(
                            ui,
                            rect(
                                tab.left() + 38.0,
                                tab.top(),
                                tab.width() - 143.0,
                                tab.height(),
                            ),
                            &name,
                            12.5,
                            true,
                            fg,
                            1,
                        );
                        let handle = rect(tab.right() - 35.0, tab.top() + 5.0, 31.0, 29.0);
                        let drag = hit(ui, handle, Sense::drag()).on_hover_cursor(CursorIcon::Grab);
                        glyph(
                            ui,
                            handle.center(),
                            icon::HANDLE,
                            17.0,
                            fg.gamma_multiply(0.72),
                        );
                        drag.dnd_set_drag_payload(TabDrag(index));
                        if let Some(source) = response.dnd_release_payload::<TabDrag>() {
                            action = Some(TabAction::Move(source.0, index));
                        }
                        if selected {
                            let rename = rect(tab.right() - 108.0, tab.top() + 5.0, 32.0, 29.0);
                            if Control::icon(
                                icon::EDIT,
                                lang.pick("Query umbenennen", "Rename query"),
                                fg.gamma_multiply(0.76),
                            )
                            .show(ui, rename)
                            .clicked()
                            {
                                action = Some(TabAction::Rename(index, name));
                            }
                            let remove = rect(tab.right() - 70.0, tab.top() + 5.0, 32.0, 29.0);
                            ui.add_enabled_ui(count > 1, |ui| {
                                if Control::icon(
                                    icon::DELETE,
                                    lang.pick("Query löschen", "Delete query"),
                                    fg.gamma_multiply(0.74),
                                )
                                .show(ui, remove)
                                .clicked()
                                {
                                    action = Some(TabAction::Delete(index));
                                }
                            });
                        }
                        if response.clicked() && !selected && self.pending.is_none() {
                            action = Some(TabAction::Select(index));
                        }
                    }
                });
            });
        match action {
            Some(TabAction::Select(index)) => self.select_tab(index),
            Some(TabAction::Rename(index, name)) => {
                self.dialog = Some(Dialog::Rename { index, name })
            }
            Some(TabAction::Delete(index)) => self.dialog = Some(Dialog::DeleteTab(index)),
            Some(TabAction::Move(from, to)) if from != to => self.reorder_tab(from, to),
            _ => {}
        }
    }

    fn select_tab(&mut self, index: usize) {
        self.project.workspace.active = index;
        self.tab_revision = self.tab_revision.wrapping_add(1);
        self.canvas.load(self.project.active_query().1.view);
        self.sql_editor = None;
        self.error = None;
        self.result = None;
        self.result_sql.clear();
        self.reset_history();
        self.mark_dirty();
    }

    fn reorder_tab(&mut self, from: usize, to: usize) {
        let active = self.project.workspace.active;
        let first = QueryTab {
            blocks: std::mem::take(&mut self.project.blocks),
            layout: std::mem::take(&mut self.project.workspace.first),
        };
        let mut tabs = std::mem::take(&mut self.project.workspace.tabs);
        tabs.insert(0, first);
        let tab = tabs.remove(from);
        tabs.insert(to, tab);
        let first = tabs.remove(0);
        self.project.blocks = first.blocks;
        self.project.workspace.first = first.layout;
        self.project.workspace.tabs = tabs;
        self.project.workspace.active = if active == from {
            to
        } else if from < active && active <= to {
            active - 1
        } else if to <= active && active < from {
            active + 1
        } else {
            active
        };
        self.changed();
    }

    pub(super) fn delete_tab(&mut self, index: usize) {
        if self.project.tab_count() <= 1 {
            return;
        }
        if index == 0 {
            let replacement = self.project.workspace.tabs.remove(0);
            self.project.blocks = replacement.blocks;
            self.project.workspace.first = replacement.layout;
        } else {
            self.project.workspace.tabs.remove(index - 1);
        }
        let active = self.project.workspace.active;
        if active == index {
            self.select_tab(index.min(self.project.tab_count() - 1));
        } else {
            self.project.workspace.active = active - usize::from(index < active);
            self.mark_dirty();
        }
    }

    fn draw_sql(&mut self, ui: &mut Ui, bounds: Rect, c: Colors) {
        let lang = self.language;
        let mut ui = style::region(ui, "sql-panel", bounds);
        let label = lang.pick("SQLite-Command Output", "SQLite command preview");
        let (header, body) = runtime_header(&ui, bounds, label, icon::TERMINAL, c);
        let edit = header_button(
            &mut ui,
            header,
            2,
            if self.sql_editor.is_some() {
                icon::TREE
            } else {
                icon::EDIT_NOTE
            },
            lang.pick("SQL bearbeiten", "Edit SQL"),
            c,
        );
        if edit.clicked() {
            if self.sql_editor.is_some() {
                self.sql_editor = None;
            } else {
                self.sql_editor = Some(self.compiled().unwrap_or_default());
            }
        }
        let copy = header_button(
            &mut ui,
            header,
            1,
            icon::COPY,
            lang.pick("SQL kopieren", "Copy SQL"),
            c,
        );
        if copy.clicked()
            && let Ok(sql) = self.visible_sql()
        {
            ui.ctx().copy_text(sql);
        }
        self.panel_layout(&mut ui, header, c, Dock::CommandBottom);
        let mut body_ui = style::region(&mut ui, "command-content", body.shrink(15.0));
        if self.sql_editor.is_some()
            && body_ui
                .add_enabled(
                    !self.busy,
                    egui::Button::new(lang.pick("Als Blöcke öffnen", "Open as blocks")),
                )
                .clicked()
        {
            self.import_sql_as_blocks();
        }
        if let Some(sql) = &mut self.sql_editor {
            egui::ScrollArea::vertical()
                .id_salt("sql-edit-scroll")
                .show(&mut body_ui, |ui| {
                    ui.add(
                        egui::TextEdit::multiline(sql)
                            .code_editor()
                            .frame(egui::Frame::NONE)
                            .desired_width(f32::INFINITY)
                            .desired_rows(6)
                            .text_color(c.sql),
                    );
                });
        } else {
            egui::ScrollArea::vertical()
                .id_salt("sql-preview-scroll")
                .show(&mut body_ui, |ui| match self.compiled_details() {
                    Ok(program) => {
                        let text = egui::RichText::new(program.sql.replace('\n', " ")).color(c.sql);
                        ui.add(
                            egui::Label::new(
                                text.size(14.0)
                                    .extra_letter_spacing(0.18)
                                    .line_height(Some(19.0)),
                            )
                            .wrap()
                            .selectable(true),
                        )
                        .context_menu(|ui| {
                            ui.label(lang.pick("Zum Block wechseln", "Go to block"));
                            egui::ScrollArea::vertical()
                                .max_height(260.0)
                                .show(ui, |ui| {
                                    for span in &program.spans {
                                        let fragment = program.sql[span.range.clone()]
                                            .lines()
                                            .next()
                                            .unwrap_or_default();
                                        if ui
                                            .button(fragment.chars().take(96).collect::<String>())
                                            .clicked()
                                        {
                                            self.focus_block(span.block_id);
                                            ui.close();
                                        }
                                    }
                                });
                        });
                    }
                    Err(errors) => {
                        for error in errors {
                            if let Some(block) = error.block_id {
                                if ui.link(error.message).clicked() {
                                    self.focus_block(block);
                                }
                            } else {
                                ui.label(egui::RichText::new(error.message).color(c.muted));
                            }
                        }
                    }
                });
        }
    }

    fn focus_block(&mut self, id: uuid::Uuid) {
        let index = (0..self.project.tab_count()).find(|&index| {
            let (blocks, layout) = self.project.query(index);
            layout.blocks(blocks).any(|block| block.id == id)
        });
        if let Some(index) = index {
            if self.project.workspace.active != index {
                self.select_tab(index);
            }
            self.reveal_block(id);
        }
    }

    fn import_sql_as_blocks(&mut self) {
        let Some(sql) = &self.sql_editor else {
            return;
        };
        let queries = match crate::sql_import::convert(sql) {
            Ok(queries) if self.project.tab_count() + queries.len() <= MAX_TABS => queries,
            Ok(_) => {
                self.error = Some(
                    self.language
                        .pick("Zu viele Query-Tabs.", "Too many query tabs.")
                        .into(),
                );
                return;
            }
            Err(error) => {
                self.error = Some(error);
                return;
            }
        };
        let first = self.project.tab_count();
        self.project
            .workspace
            .tabs
            .extend(
                queries
                    .into_iter()
                    .enumerate()
                    .map(|(index, blocks)| QueryTab {
                        blocks,
                        layout: crate::model::QueryLayout {
                            name: format!("SQL {}", first + index + 1),
                            ..Default::default()
                        },
                    }),
            );
        self.select_tab(first);
    }

    fn draw_output(&mut self, ui: &mut Ui, bounds: Rect, c: Colors) {
        let lang = self.language;
        let mut ui = style::region(ui, "output-panel", bounds);
        let (header, body) = runtime_header(
            &ui,
            bounds,
            lang.pick("Ausgabevorschau", "Output preview"),
            icon::ROWS,
            c,
        );
        if header_button(
            &mut ui,
            header,
            2,
            icon::FULLSCREEN,
            lang.pick("Vollbild", "Fullscreen"),
            c,
        )
        .clicked()
        {
            self.dialog = Some(Dialog::Results);
        }
        let export = header_button(
            &mut ui,
            header,
            1,
            icon::EXPORT,
            lang.pick("Ergebnis exportieren", "Export results"),
            c,
        );
        egui::Popup::menu(&export).show(|ui| self.export_menu(ui));
        self.panel_layout(&mut ui, header, c, Dock::PreviewBottom);
        let mut ui = style::region(&mut ui, "results-body", body);
        if let Some(error) = &self.error {
            ui.painter().rect_filled(body, 0, c.panel);
            blocks::clipped_text(
                &ui,
                body.shrink(12.0),
                error,
                14.0,
                false,
                Color32::LIGHT_RED,
                5,
            );
        } else if let Some(result) = &self.result
            && !result.columns.is_empty()
        {
            table(&mut ui, result, c);
        } else {
            words(
                &ui,
                body.left_top() + vec2(12.0, 14.0),
                Align2::LEFT_TOP,
                if self.busy || self.result.is_some() {
                    &self.status
                } else if self.requires_manual_run() {
                    lang.pick(
                        "Schreibende Befehle mit „SQLite ausführen“ starten.",
                        "Use Run SQLite to apply changes.",
                    )
                } else {
                    lang.pick("Noch keine Ergebnisse.", "No results yet.")
                },
                font(14.0, false),
                c.text,
            );
        }
    }

    fn panel_layout(&mut self, ui: &mut Ui, header: Rect, c: Colors, bottom: Dock) {
        let lang = self.language;
        let handle = rect(header.right() - 25.0, header.top(), 24.0, header.height());
        let response = ui
            .interact(
                handle,
                ui.scope_id().with("dock-handle"),
                Sense::click_and_drag(),
            )
            .on_hover_text(lang.pick("Fensteranordnung", "Panel layout"))
            .on_hover_cursor(CursorIcon::Grab);
        glyph(ui, handle.center(), icon::HANDLE, 18.0, c.text);
        egui::Popup::menu(&response).show(|ui| {
            for (mode, name) in [
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
                if ui.selectable_label(self.dock == mode, name).clicked() {
                    self.dock = mode;
                    ui.close();
                }
            }
        });
        if response.drag_stopped()
            && let Some(pointer) = response.interact_pointer_pos()
        {
            let screen = ui.ctx().input(|i| i.content_rect());
            self.dock = if pointer.y > screen.bottom() - 120.0 {
                bottom
            } else {
                Dock::RightSplit
            };
        }
    }

    pub(super) fn browse_table(&mut self, name: String) {
        self.inspect_table(name, 0);
    }

    pub(super) fn inspect_table(&mut self, name: String, page: usize) {
        if self.busy {
            return;
        }
        self.error = None;
        self.browser_result = None;
        self.browser_table = Some(name.clone());
        self.cancel.store(false, Ordering::Relaxed);
        self.send(super::Command::Inspect(name, page));
    }

    pub(super) fn export_menu(&mut self, ui: &mut Ui) {
        for format in Format::ALL {
            if ui
                .add_enabled(
                    self.result
                        .as_ref()
                        .is_some_and(|result| !result.columns.is_empty()),
                    egui::Button::new(format.extension().to_ascii_uppercase()),
                )
                .clicked()
            {
                self.export(format);
                ui.close();
            }
        }
    }
}

enum TabAction {
    Select(usize),
    Rename(usize, String),
    Delete(usize),
    Move(usize, usize),
}

fn shortcut(ctx: &egui::Context, modifiers: egui::Modifiers, key: egui::Key) -> bool {
    ctx.input_mut(|i| i.consume_key(modifiers, key))
}

fn palette_join(ui: &Ui, bounds: Rect, lang: Language) {
    let x = bounds.left() + 16.0;
    let y = bounds.top() + 9.0;
    words(
        ui,
        pos2(x, y + 7.0),
        Align2::LEFT_CENTER,
        "JOIN",
        font(8.5, true),
        Color32::WHITE,
    );
    for (bounds, text) in [
        (
            rect(x + 22.0, y, 60.0, 16.0),
            lang.pick("Tabelle wählen", "Choose table"),
        ),
        (
            rect(x + 86.0, y, (bounds.right() - x - 94.0).max(35.0), 16.0),
            lang.pick("Nur passende Zeilen", "Matching rows only"),
        ),
        (
            rect(x, y + 22.0, 83.0, 18.0),
            lang.pick("Spalte wählen", "Choose column"),
        ),
        (rect(x + 87.0, y + 22.0, 20.0, 18.0), "="),
        (
            rect(
                x + 111.0,
                y + 22.0,
                (bounds.right() - x - 118.0).max(28.0),
                18.0,
            ),
            lang.pick("Spalte wählen", "Choose column"),
        ),
    ] {
        blocks::chip_background(ui, bounds, 6.0, false);
        blocks::clipped_text(
            ui,
            bounds.shrink2(vec2(4.0, 0.0)),
            text,
            8.3,
            true,
            Color32::WHITE,
            1,
        );
    }
}

fn runtime_header(ui: &Ui, bounds: Rect, title: &str, marker: char, c: Colors) -> (Rect, Rect) {
    ui.painter().rect(
        bounds,
        0,
        c.panel,
        Stroke::new(1.0, c.border),
        StrokeKind::Inside,
    );
    let header = rect(
        bounds.left() + 1.0,
        bounds.top() + 1.0,
        bounds.width() - 2.0,
        HEADER - 1.0,
    );
    ui.painter().rect_filled(header, 0, c.raised);
    rule(ui, header.left_bottom(), header.right_bottom(), c.border);
    glyph(
        ui,
        header.left_center() + vec2(20.0, 0.0),
        marker,
        18.0,
        c.primary,
    );
    blocks::clipped_text(
        ui,
        rect(
            header.left() + 38.0,
            header.top(),
            header.width() - 129.0,
            header.height(),
        ),
        title,
        14.0,
        true,
        c.text,
        1,
    );
    (
        header,
        Rect::from_min_max(
            pos2(bounds.left() + 1.0, header.bottom()),
            bounds.max - vec2(1.0, 1.0),
        ),
    )
}

fn header_button(
    ui: &mut Ui,
    header: Rect,
    index: usize,
    glyph: char,
    tip: &str,
    c: Colors,
) -> Response {
    let x = header.right() - 24.0 - index as f32 * 38.0;
    Control::icon(glyph, tip, c.text)
        .show(ui, rect(x, header.top() + 3.0, 37.0, header.height() - 6.0))
}

fn vertical_handle(ui: &mut Ui, name: &str, x: f32, y: f32, c: Colors) -> Response {
    let handle = rect(x - 3.0, y - 17.0, 8.0, 34.0);
    let r = ui
        .interact(handle, Id::unique(name), Sense::drag())
        .on_hover_cursor(CursorIcon::ResizeHorizontal);
    ui.painter().rect_filled(
        rect(x + 1.0, y - 17.0, if r.hovered() { 4.0 } else { 2.0 }, 34.0),
        0,
        c.border,
    );
    r
}

fn horizontal_handle(ui: &mut Ui, x: f32, y: f32, c: Colors) -> Response {
    let handle = rect(x - 18.0, y - 3.0, 36.0, 8.0);
    let r = ui
        .interact(handle, Id::unique("runtime-height"), Sense::drag())
        .on_hover_cursor(CursorIcon::ResizeVertical);
    ui.painter().rect_filled(
        rect(x - 17.0, y + 1.0, 34.0, if r.hovered() { 4.0 } else { 2.0 }),
        0,
        c.border,
    );
    r
}

pub(super) fn table(ui: &mut Ui, result: &QueryResult, c: Colors) {
    table_with_rows(ui, result, c, 48.0, false);
}

pub(super) fn table_with_rows(
    ui: &mut Ui,
    result: &QueryResult,
    c: Colors,
    row_height: f32,
    striped: bool,
) {
    let mut headers = Vec::with_capacity(result.columns.len());
    let mut widths = Vec::with_capacity(result.columns.len());
    for (index, column) in result.columns.iter().enumerate() {
        let prior = result.columns[..index]
            .iter()
            .filter(|name| *name == column)
            .count();
        let name = if prior > 0 {
            format!("{column} ({})", prior + 1)
        } else {
            column.clone()
        };
        let header_width = text_width(ui, &name, font(14.0, true));
        let max_data = result
            .rows
            .iter()
            .take(80)
            .filter_map(|row| row.get(index))
            .map(|cell| text_width(ui, &cell.to_string(), font(14.0, false)))
            .fold(0.0, f32::max);
        widths.push((header_width.max(max_data) + 60.0).clamp(73.0, 295.0));
        headers.push(name);
    }
    let data_width = widths.iter().sum::<f32>();
    let width = data_width.max(ui.available_width());
    if striped && !widths.is_empty() {
        let extra = (width - data_width) / widths.len() as f32;
        widths.iter_mut().for_each(|column| *column += extra);
    }
    egui::ScrollArea::both()
        .id_salt("result-table")
        .scroll_bar_visibility(egui::scroll_area::ScrollBarVisibility::AlwaysVisible)
        .auto_shrink([false, false])
        .show(ui, |ui| {
            let height = 56.0 + result.rows.len() as f32 * row_height;
            let (area, _) = ui.allocate_exact_size(vec2(width, height), Sense::hover());
            let heading = rect(area.left(), area.top(), width, 56.0);
            ui.painter().rect_filled(
                heading,
                if striped { 12 } else { 0 },
                if striped { c.panel } else { c.raised },
            );
            rule(
                ui,
                heading.left_bottom(),
                heading.right_bottom(),
                c.text.gamma_multiply(0.8),
            );
            let mut x = area.left();
            for (column, width) in headers.iter().zip(&widths) {
                blocks::clipped_text(
                    ui,
                    rect(x + 24.0, heading.top(), width - 32.0, heading.height()),
                    column,
                    14.0,
                    true,
                    c.text,
                    1,
                );
                x += width;
            }
            for (i, row) in result.rows.iter().enumerate() {
                let y = heading.bottom() + i as f32 * row_height;
                if y > ui.clip_rect().bottom() || y + row_height < ui.clip_rect().top() {
                    continue;
                }
                if striped {
                    ui.painter().rect_filled(
                        rect(area.left(), y, width, row_height),
                        0,
                        if i % 2 == 0 { c.raised } else { c.panel },
                    );
                }
                rule(
                    ui,
                    pos2(area.left(), y + row_height),
                    pos2(area.right(), y + row_height),
                    c.text.gamma_multiply(0.76),
                );
                let mut x = area.left();
                for (cell, width) in row.iter().zip(&widths) {
                    blocks::clipped_text(
                        ui,
                        rect(x + 24.0, y, width - 32.0, row_height),
                        &cell.to_string(),
                        14.0,
                        false,
                        c.text,
                        1,
                    );
                    x += width;
                }
            }
            if result.truncated {
                ui.label("1.000 / …");
            }
        });
}
