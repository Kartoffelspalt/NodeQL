use super::{
    NodeQlApp,
    catalog::{Action, block_color},
    style::{self, Colors, Language, font, glyph, icon, rect, rgb, rule, text_width, words},
};
use crate::{
    compiler,
    database::quote_identifier,
    model::{Block, BlockKind, CanvasPoint, CanvasView, DetachedBlock, MAX_BLOCKS, QueryChain},
    reporter::Reporter,
};
use eframe::egui::{
    self, Align2, Color32, CursorIcon, Id, Pos2, Rect, Response, Sense, Shape, Stroke, StrokeKind,
    Ui, Vec2, pos2, vec2,
};
use std::ops::Range;
use uuid::Uuid;

const HAT_WIDTH: f32 = 236.0;
const HAT_HEIGHT: f32 = 44.0;

#[derive(Clone, Copy)]
pub enum Puzzle {
    Trigger,
    Statement,
    Join,
    Value,
    Terminal,
}

#[derive(Clone, Copy)]
pub enum Drag {
    Palette(Action),
    Node(Uuid),
    Stack(usize),
}

pub struct Canvas {
    pub pan: Vec2,
    pub zoom: f32,
    pub selected: Option<Uuid>,
    grab_offset: Vec2,
}

impl Default for Canvas {
    fn default() -> Self {
        Self {
            pan: Vec2::ZERO,
            zoom: 1.0,
            selected: None,
            grab_offset: Vec2::ZERO,
        }
    }
}

impl Canvas {
    pub fn reset(&mut self) {
        *self = Self::default();
    }

    pub fn load(&mut self, view: CanvasView) {
        self.reset();
        self.pan = vec2(view.pan_x as f32, view.pan_y as f32);
        self.zoom = (view.zoom_milli as f32 / 1000.0).clamp(0.25, 3.0);
    }

    pub fn view(&self) -> CanvasView {
        CanvasView {
            pan_x: self.pan.x.round() as i32,
            pan_y: self.pan.y.round() as i32,
            zoom_milli: (self.zoom * 1000.0).round() as u16,
        }
    }
}

#[derive(Clone)]
pub struct Choice {
    pub label: String,
    pub value: String,
}

pub struct FieldEditor {
    pub title: String,
    pub block: Uuid,
    pub range: Range<usize>,
    pub value: String,
    pub choices: Vec<Choice>,
    pub append_space: bool,
    pub reporter: Option<Reporter>,
}

#[derive(Clone, Copy)]
pub(super) struct DockSlot {
    chain: usize,
    index: usize,
}

struct Node<'a> {
    block: Option<&'a Block>,
    from: Option<&'a Block>,
    bounds: Rect,
    chain: usize,
}

impl Node<'_> {
    fn shape(&self) -> Puzzle {
        match self.block.map(|block| block.kind) {
            None => Puzzle::Trigger,
            Some(BlockKind::Join) => Puzzle::Join,
            _ => Puzzle::Statement,
        }
    }

    fn color(&self) -> Color32 {
        self.block
            .map_or(rgb(0xfbb100), |block| block_color(block.kind))
    }
}

fn to_screen(origin: Pos2, point: CanvasPoint, zoom: f32) -> Pos2 {
    origin + vec2(point.x as f32, point.y as f32) * zoom
}

fn to_canvas(origin: Pos2, point: Pos2, zoom: f32) -> CanvasPoint {
    let point = (point - origin) / zoom;
    CanvasPoint {
        x: point.x.round().clamp(-100_000.0, 100_000.0) as i32,
        y: point.y.round().clamp(-100_000.0, 100_000.0) as i32,
    }
}

fn size_for(kind: BlockKind, source: bool, advanced: bool) -> Vec2 {
    match kind {
        BlockKind::Insert
        | BlockKind::InsertOrReplace
        | BlockKind::Upsert
        | BlockKind::Update
        | BlockKind::Delete => vec2(350.0, 94.0),
        BlockKind::Select => vec2(if source { 334.0 } else { 246.0 }, 51.0),
        BlockKind::Join => vec2(328.0, 80.0),
        BlockKind::Where | BlockKind::And | BlockKind::Or => vec2(322.0, 62.0),
        BlockKind::OrderBy => vec2(if advanced { 313.0 } else { 270.0 }, 62.0),
        BlockKind::Having => vec2(296.0, 62.0),
        BlockKind::From | BlockKind::GroupBy | BlockKind::Limit => vec2(270.0, 48.0),
        _ => vec2(330.0, 62.0),
    }
}

pub fn puzzle(
    ui: &Ui,
    bounds: Rect,
    kind: Puzzle,
    color: Color32,
    scale: f32,
    outline: Option<Color32>,
) {
    let painter = ui.painter();
    if matches!(kind, Puzzle::Value) {
        painter.rect(
            bounds,
            bounds.height() / 2.0,
            color,
            Stroke::new(1.4, Color32::from_white_alpha(87)),
            StrokeKind::Inside,
        );
        return;
    }
    let points = puzzle_path(bounds, kind, scale);
    let indices = triangulate(&points);
    for (offset, fill) in [
        (vec2(0.0, 2.0 * scale), Color32::from_black_alpha(64)),
        (Vec2::ZERO, color),
    ] {
        let mut mesh = egui::Mesh::default();
        mesh.indices.clone_from(&indices);
        for &point in &points {
            mesh.colored_vertex(point + offset, fill);
        }
        painter.add(Shape::mesh(mesh));
    }
    painter.add(Shape::closed_line(
        points.clone(),
        Stroke::new(4.0 * scale, Color32::from_black_alpha(82)),
    ));
    painter.add(Shape::closed_line(
        points.clone(),
        Stroke::new(1.4 * scale, Color32::from_white_alpha(87)),
    ));
    if let Some(color) = outline {
        painter.add(Shape::closed_line(points, Stroke::new(2.5 * scale, color)));
    }
}

fn puzzle_path(bounds: Rect, kind: Puzzle, scale: f32) -> Vec<Pos2> {
    let w = bounds.width();
    let h = bounds.height();
    let radius = (9.0 * scale).min(h * 0.45);
    let nx = 31.0 * scale;
    let nw = 20.0 * scale;
    let depth = 7.0 * scale;
    let bevel = 4.0 * scale;
    let join = matches!(kind, Puzzle::Join);
    let left = if join { 17.0 * scale } else { radius };
    let mut p = vec![pos2(left, 0.0)];
    if !matches!(kind, Puzzle::Trigger) {
        p.extend([
            pos2(nx, 0.0),
            pos2(nx + bevel, depth),
            pos2(nx + nw - bevel, depth),
            pos2(nx + nw, 0.0),
        ]);
    }
    p.push(pos2(w - radius, 0.0));
    quad(&mut p, pos2(w, 0.0), pos2(w, radius));
    p.push(pos2(w, h - radius));
    quad(&mut p, pos2(w, h), pos2(w - radius, h));
    if !matches!(kind, Puzzle::Terminal) {
        p.extend([
            pos2(nx + nw, h),
            pos2(nx + nw - bevel, h + depth),
            pos2(nx + bevel, h + depth),
            pos2(nx, h),
        ]);
    }
    p.push(pos2(left, h));
    if join {
        p.push(pos2(0.0, h / 2.0));
    } else {
        quad(&mut p, pos2(0.0, h), pos2(0.0, h - radius));
        p.push(pos2(0.0, radius));
        quad(&mut p, pos2(0.0, 0.0), pos2(radius, 0.0));
        p.pop();
    }
    p.into_iter().map(|p| bounds.min + p.to_vec2()).collect()
}

fn quad(points: &mut Vec<Pos2>, control: Pos2, end: Pos2) {
    let start = *points.last().unwrap();
    for step in 1..=4 {
        let t = step as f32 / 4.0;
        points.push(start.lerp(control, t).lerp(control.lerp(end, t), t));
    }
}

// The notches are concave. Split the outline into triangles so the tab of
// the preceding block remains visible through the open top of its neighbor.
fn triangulate(points: &[Pos2]) -> Vec<u32> {
    fn side(a: Pos2, b: Pos2, c: Pos2) -> f32 {
        (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
    }

    let mut ring: Vec<usize> = (0..points.len()).collect();
    let mut indices = Vec::with_capacity((points.len() - 2) * 3);
    while ring.len() >= 3 {
        let ear = (0..ring.len()).find(|&i| {
            let a = ring[(i + ring.len() - 1) % ring.len()];
            let b = ring[i];
            let c = ring[(i + 1) % ring.len()];
            side(points[a], points[b], points[c]) > 0.01
                && !ring.iter().any(|&x| {
                    x != a
                        && x != b
                        && x != c
                        && side(points[a], points[b], points[x]) >= -0.01
                        && side(points[b], points[c], points[x]) >= -0.01
                        && side(points[c], points[a], points[x]) >= -0.01
                })
        });
        let Some(i) = ear else {
            break;
        };
        indices.extend([
            ring[(i + ring.len() - 1) % ring.len()] as u32,
            ring[i] as u32,
            ring[(i + 1) % ring.len()] as u32,
        ]);
        ring.remove(i);
    }
    indices
}

pub fn trigger_content(ui: &Ui, bounds: Rect, label: &str, scale: f32) {
    let center = pos2(bounds.left() + 25.0 * scale, bounds.center().y);
    ui.painter()
        .circle_filled(center, 11.5 * scale, Color32::from_white_alpha(51));
    glyph(ui, center, icon::PLAY, 17.0 * scale, Color32::WHITE);
    words(
        ui,
        center + vec2(19.0 * scale, 0.0),
        Align2::LEFT_CENTER,
        label,
        font(15.0 * scale, true),
        Color32::WHITE,
    );
}

pub fn clipped_text(
    ui: &Ui,
    bounds: Rect,
    text: &str,
    size: f32,
    bold: bool,
    color: Color32,
    rows: usize,
) {
    let mut job = egui::text::LayoutJob::simple(
        text.to_owned(),
        font(size, bold),
        color,
        bounds.width().max(1.0),
    );
    for section in &mut job.sections {
        section.format.extra_letter_spacing = 0.14;
        if rows > 1 {
            section.format.line_height = Some(size * 1.25);
        }
    }
    job.wrap.max_rows = rows;
    job.wrap.break_anywhere = rows == 1;
    let galley = ui.painter().layout_job(job);
    let y = if rows == 1 {
        bounds.center().y - galley.size().y / 2.0
    } else {
        bounds.top()
    };
    ui.painter()
        .with_clip_rect(ui.clip_rect().intersect(bounds))
        .galley(pos2(bounds.left(), y), galley, color);
}

pub fn chip_background(ui: &Ui, bounds: Rect, radius: f32, hover: bool) {
    ui.painter().rect(
        bounds,
        radius,
        Color32::from_white_alpha(if hover { 78 } else { 56 }),
        Stroke::new(1.0, Color32::from_white_alpha(138)),
        StrokeKind::Inside,
    );
}

fn trigger_label(advanced: bool, lang: Language) -> &'static str {
    if advanced {
        "EXECUTE QUERY"
    } else {
        lang.pick("QUERY AUSFUEHREN", "RUN QUERY")
    }
}

impl NodeQlApp {
    pub(super) fn insert(
        &mut self,
        action: Action,
        position: Option<CanvasPoint>,
        slot: Option<DockSlot>,
    ) {
        let lang = self.language;
        let mut authored = self.authored_blocks(action).unwrap_or_default().into_iter();
        let default_table = self.schema.first().map(|table| table.name.clone());
        let source = self
            .project
            .active_query()
            .0
            .iter()
            .find(|node| node.kind == BlockKind::From)
            .map(|node| node.input.trim_matches('"'));
        let from_column = self
            .schema
            .iter()
            .find(|table| Some(table.name.as_str()) == source)
            .or_else(|| self.schema.first())
            .and_then(|table| {
                table
                    .columns
                    .first()
                    .map(|column| format!("{}.{}", sql_name(&table.name), sql_name(column)))
            });
        let demo_filter = self.project.workspace.sample
            && self.project.database.is_none()
            && source.is_some_and(|name| name.eq_ignore_ascii_case("Customers"));
        let (primary, layout) = self.project.active_query_mut();
        if action == Action::Trigger {
            if layout.chains.len() + 1 < MAX_BLOCKS {
                let at = position.unwrap_or(CanvasPoint {
                    x: layout.origin.x + 385,
                    y: layout.origin.y + 55 * (1 + layout.chains.len() as i32),
                });
                layout.chains.push(QueryChain {
                    origin: at,
                    blocks: Vec::new(),
                });
                self.changed();
            }
            return;
        }
        let count = layout.block_count(primary);
        let chain = slot.map_or(0, |slot| slot.chain);
        let blocks = if chain == 0 {
            primary
        } else {
            &mut layout.chains[chain - 1].blocks
        };
        if matches!(action, Action::Expression(_)) {
            return;
        }
        let Action::Clause(kind) = action else {
            if action == Action::Unavailable {
                self.error = Some(
                    lang.pick(
                        "Dieser Block ist im Rust-Editor noch nicht ausführbar.",
                        "This block is not executable in the Rust editor yet.",
                    )
                    .into(),
                );
            }
            return;
        };
        if count >= MAX_BLOCKS {
            return;
        }
        let mut block = if let Some(authored) = authored.next() {
            authored
        } else {
            Block::new(kind)
        };
        if self.practice.is_some()
            && kind == BlockKind::From
            && let Some(existing) = blocks
                .iter_mut()
                .find(|block| block.kind == BlockKind::From)
        {
            *existing = block;
            self.changed();
            return;
        }
        if self.practice.is_none() && kind == BlockKind::From {
            if let Some(table) = default_table.as_deref() {
                block.input = sql_name(table);
            }
        } else if self.practice.is_none()
            && kind == BlockKind::OrderBy
            && let Some(column) = from_column
        {
            block.input = format!("{column} ASC");
        } else if self.practice.is_none()
            && matches!(kind, BlockKind::Where | BlockKind::And | BlockKind::Or)
        {
            if demo_filter {
                block.input = "Customers.country = 'UK'".into();
            } else if let Some(column) = from_column {
                block.input = format!("{column} IS NOT NULL");
            }
        }
        let duplicate = !kind.repeatable() && blocks.iter().any(|node| node.kind == kind);
        if let Some(point) = position.filter(|_| slot.is_none() || duplicate) {
            layout.detached.push(DetachedBlock {
                block,
                position: point,
            });
        } else if duplicate {
            let point = CanvasPoint {
                x: layout.origin.x.saturating_add(380),
                y: layout.origin.y.saturating_add(55),
            };
            layout.detached.push(DetachedBlock {
                block,
                position: point,
            });
        } else {
            let index = slot.map(|slot| slot.index).unwrap_or_else(|| {
                blocks
                    .iter()
                    .position(|node| node.kind.rank() > kind.rank())
                    .unwrap_or(blocks.len())
            });
            blocks.insert(index.min(blocks.len()), block);
            if kind == BlockKind::Select
                && !blocks.iter().any(|node| node.kind == BlockKind::From)
                && count + 1 < MAX_BLOCKS
                && let Some(from) = authored.next().or_else(|| {
                    default_table.map(|table| Block {
                        input: sql_name(&table),
                        ..Block::new(BlockKind::From)
                    })
                })
            {
                let index = blocks
                    .iter()
                    .position(|node| node.kind == BlockKind::Select)
                    .unwrap()
                    + 1;
                blocks.insert(index, from);
            }
        }
        self.changed();
    }

    pub(super) fn draw_canvas(&mut self, ui: &mut Ui, area: Rect, palette: Rect, colors: Colors) {
        let mut ui = style::region(ui, "canvas", area);
        let ui = &mut ui;
        ui.painter().rect_filled(area, 0, colors.canvas);
        if self.pending.is_some() {
            ui.disable();
        }
        let background = ui.interact(area, Id::unique("workspace-pan"), Sense::click_and_drag());
        if background.dragged() {
            self.canvas.pan += background.drag_delta();
        }
        if background.clicked() {
            self.canvas.selected = None;
        }
        if background.hovered() {
            let (delta, zoom, pointer) =
                ui.input(|i| (i.smooth_scroll_delta, i.zoom_delta(), i.pointer.hover_pos()));
            if zoom != 1.0 {
                let old = self.canvas.zoom;
                self.canvas.zoom = (old * zoom).clamp(0.35, 2.6);
                if let Some(pointer) = pointer {
                    let at = pointer - area.min;
                    self.canvas.pan = at - (at - self.canvas.pan) * (self.canvas.zoom / old);
                }
            } else {
                self.canvas.pan += delta;
            }
        }
        let zoom = self.canvas.zoom;
        let screen_origin = area.min + self.canvas.pan;
        let (blocks, layout) = self.project.active_query();
        let blocks = blocks.to_vec();
        let layout = layout.clone();
        let mut nodes = Vec::new();
        let mut sockets = Vec::new();
        for (chain, (point, blocks)) in layout.chains(&blocks).enumerate() {
            let origin = to_screen(screen_origin, point, zoom);
            let first = nodes.len();
            nodes.push(Node {
                block: None,
                from: None,
                bounds: Rect::from_min_size(origin, vec2(HAT_WIDTH, HAT_HEIGHT) * zoom),
                chain,
            });
            let mut y = origin.y + HAT_HEIGHT * zoom;
            let mut index = 0;
            while index < blocks.len() {
                let block = &blocks[index];
                let from = blocks
                    .get(index + 1)
                    .filter(|next| block.kind == BlockKind::Select && next.kind == BlockKind::From);
                let at = pos2(origin.x, y);
                sockets.push((DockSlot { chain, index }, at));
                let bounds = Rect::from_min_size(
                    at,
                    size_for(block.kind, from.is_some(), self.advanced) * zoom,
                );
                nodes.push(Node {
                    block: Some(block),
                    from,
                    bounds,
                    chain,
                });
                y = bounds.bottom();
                index += 1 + usize::from(from.is_some());
            }
            sockets.push((
                DockSlot {
                    chain,
                    index: blocks.len(),
                },
                pos2(origin.x, y),
            ));
            self.draw_ropes(ui, &nodes[first..], zoom, colors);
        }
        for detached in &layout.detached {
            nodes.push(Node {
                block: Some(&detached.block),
                from: None,
                chain: 0,
                bounds: Rect::from_min_size(
                    to_screen(screen_origin, detached.position, zoom),
                    size_for(detached.block.kind, false, self.advanced) * zoom,
                ),
            });
        }

        let mut remove = None;
        let mut remove_chain = None;
        for node in &nodes {
            let Some(visible) = node
                .bounds
                .expand(8.0)
                .intersects(area)
                .then_some(node.bounds)
            else {
                continue;
            };
            let id = node.block.map(|block| block.id);
            let drag_id = if let Some(id) = id {
                Id::unique(("workspace-node", id))
            } else {
                Id::unique(("workspace-trigger", node.chain))
            };
            let response = ui
                .interact(visible, drag_id, Sense::click_and_drag())
                .on_hover_cursor(CursorIcon::Grab);
            if response.drag_started() {
                self.canvas.grab_offset =
                    response.interact_pointer_pos().unwrap_or(visible.min) - visible.min;
            }
            response.dnd_set_drag_payload(id.map_or(Drag::Stack(node.chain), Drag::Node));
            if response.clicked() {
                self.canvas.selected = id;
            }
            if id.is_some() {
                response.context_menu(|ui| {
                    if ui
                        .button(self.language.pick("Block löschen", "Delete block"))
                        .clicked()
                    {
                        remove = id;
                        ui.close();
                    }
                });
            }
            if id.is_none() && node.chain > 0 {
                response.context_menu(|ui| {
                    if ui
                        .button(
                            self.language
                                .pick("Startkette löschen", "Delete query chain"),
                        )
                        .clicked()
                    {
                        remove_chain = Some(node.chain);
                        ui.close();
                    }
                });
            }
            let selected = id.is_some_and(|id| self.canvas.selected == Some(id))
                || node
                    .from
                    .is_some_and(|from| self.canvas.selected == Some(from.id));
            puzzle(
                ui,
                visible,
                node.shape(),
                node.color(),
                zoom,
                selected.then_some(colors.primary),
            );
            if let Some(block) = node.block {
                self.block_content(ui, visible, block, node.from, zoom);
            } else {
                trigger_content(
                    ui,
                    visible,
                    trigger_label(self.advanced, self.language),
                    zoom,
                );
                if response.double_clicked() {
                    self.run();
                }
            }
        }

        if let Some(id) = remove.or_else(|| {
            (ui.input(|i| i.key_pressed(egui::Key::Delete) || i.key_pressed(egui::Key::Backspace))
                && !ui.ctx().egui_wants_keyboard_input()
                && self.dialog.is_none()
                && self.field_editor.is_none())
            .then_some(self.canvas.selected)
            .flatten()
        }) {
            self.remove_block(id);
        }

        if let Some(chain) = remove_chain {
            self.project.active_query_mut().1.chains.remove(chain - 1);
            self.changed();
        }
        let pointer = ui.input(|i| i.pointer.interact_pos());
        let drag = egui::DragAndDrop::payload::<Drag>(ui.ctx());
        if let (Some(pointer), Some(drag)) = (pointer, drag)
            && !matches!(*drag, Drag::Palette(Action::Expression(_)))
        {
            let snap = sockets
                .into_iter()
                .filter(|(_, at)| {
                    !matches!(*drag, Drag::Stack(_) | Drag::Palette(Action::Trigger))
                        && pointer.x >= at.x - 50.0 * zoom
                        && pointer.x <= at.x + 366.0 * zoom
                        && (pointer.y - at.y).abs() <= 22.0 * zoom
                })
                .min_by(|(_, a), (_, b)| {
                    let distance = |at: &Pos2| {
                        (at.y - pointer.y).abs() + ((at.x + 80.0 * zoom) - pointer.x).abs() * 0.08
                    };
                    distance(a).total_cmp(&distance(b))
                });
            if let Some((_, at)) = snap {
                rule(ui, at, at + vec2(180.0 * zoom, 0.0), colors.primary);
                ui.painter()
                    .circle_filled(at + vec2(31.0 * zoom, 0.0), 3.0, colors.primary);
            }
            if ui.input(|i| i.pointer.any_released())
                && (area.contains(pointer) || palette.contains(pointer))
            {
                let drag = egui::DragAndDrop::take_payload::<Drag>(ui.ctx()).unwrap();
                let slot = snap.map(|(slot, _)| slot);
                let destination = to_canvas(screen_origin, pointer - self.canvas.grab_offset, zoom);
                if area.contains(pointer) {
                    match *drag {
                        Drag::Stack(chain) => {
                            let layout = self.project.active_query_mut().1;
                            if chain == 0 {
                                layout.origin = destination;
                            } else {
                                layout.chains[chain - 1].origin = destination;
                            }
                            self.changed();
                        }
                        Drag::Node(id) => self.drop_block(id, destination, slot),
                        Drag::Palette(action) => self.insert(action, Some(destination), slot),
                    }
                } else if let Drag::Node(id) = *drag {
                    self.remove_block(id);
                }
            } else if area.contains(pointer) {
                match *drag {
                    Drag::Node(id) => {
                        if let Some(node) = nodes
                            .iter()
                            .find(|node| node.block.is_some_and(|block| block.id == id))
                        {
                            let ghost = Rect::from_min_size(
                                pointer - self.canvas.grab_offset,
                                node.bounds.size(),
                            );
                            puzzle(
                                ui,
                                ghost,
                                node.shape(),
                                node.color().gamma_multiply(0.55),
                                zoom,
                                Some(colors.primary),
                            );
                        }
                    }
                    Drag::Stack(_) => {
                        let ghost = Rect::from_min_size(
                            pointer - self.canvas.grab_offset,
                            nodes[0].bounds.size(),
                        );
                        puzzle(
                            ui,
                            ghost,
                            Puzzle::Trigger,
                            nodes[0].color().gamma_multiply(0.55),
                            zoom,
                            Some(colors.primary),
                        );
                    }
                    Drag::Palette(Action::Clause(kind)) => {
                        let ghost = Rect::from_min_size(
                            pointer - self.canvas.grab_offset,
                            size_for(kind, false, self.advanced) * zoom,
                        );
                        puzzle(
                            ui,
                            ghost,
                            if kind == BlockKind::Join {
                                Puzzle::Join
                            } else {
                                Puzzle::Statement
                            },
                            block_color(kind).gamma_multiply(0.65),
                            zoom,
                            Some(colors.primary),
                        );
                    }
                    _ => {}
                }
            }
        }

        background.context_menu(|ui| {
            if ui
                .button(self.language.pick("Ansicht zurücksetzen", "Reset view"))
                .clicked()
            {
                self.canvas.reset();
                ui.close();
            }
            if ui
                .button(self.language.pick("Vergrößern", "Zoom in"))
                .clicked()
            {
                self.canvas.zoom = (self.canvas.zoom * 1.2).min(2.6);
                ui.close();
            }
            if ui
                .button(self.language.pick("Verkleinern", "Zoom out"))
                .clicked()
            {
                self.canvas.zoom = (self.canvas.zoom / 1.2).max(0.35);
                ui.close();
            }
        });
    }

    pub(super) fn palette_drag(&mut self, response: &Response, action: Action, min: Pos2) {
        if self.pending.is_some() {
            return;
        }
        if response.drag_started() {
            let pointer = response.interact_pointer_pos().unwrap_or(min);
            self.canvas.grab_offset = (pointer - min).min(vec2(36.0, 22.0));
        }
        response.dnd_set_drag_payload(Drag::Palette(action));
    }

    fn draw_ropes(&self, ui: &Ui, nodes: &[Node<'_>], zoom: f32, colors: Colors) {
        let find = |kind| {
            nodes
                .iter()
                .find(|node| node.block.is_some_and(|block| block.kind == kind))
        };
        if let Some(select) = nodes.iter().find(|node| node.from.is_some())
            && let Some(join) = find(BlockKind::Join)
        {
            let rope = colors
                .primary
                .gamma_multiply(if self.link_mode { 1.0 } else { 0.68 });
            curve(
                ui,
                select.bounds.right_center(),
                pos2(
                    join.bounds.right() - 13.0 * zoom,
                    join.bounds.top() + 3.0 * zoom,
                ),
                30.0 * zoom,
                rope,
            );
            if let Some(order) = find(BlockKind::OrderBy) {
                curve(
                    ui,
                    pos2(
                        join.bounds.left() + 10.0 * zoom,
                        join.bounds.bottom() + 10.0 * zoom,
                    ),
                    order.bounds.left_center(),
                    -35.0 * zoom,
                    rope,
                );
            }
        }
    }

    fn remove_block(&mut self, id: Uuid) {
        let (blocks, layout) = self.project.active_query_mut();
        for chain in
            std::iter::once(blocks).chain(layout.chains.iter_mut().map(|chain| &mut chain.blocks))
        {
            chain.retain(|block| block.id != id);
        }
        layout.detached.retain(|block| block.block.id != id);
        self.canvas.selected = None;
        self.changed();
    }

    pub(super) fn reveal_block(&mut self, id: Uuid) {
        let (blocks, layout) = self.project.active_query();
        let at = layout
            .detached
            .iter()
            .find(|node| node.block.id == id)
            .map(|node| vec2(node.position.x as f32, node.position.y as f32))
            .or_else(|| {
                layout.chains(blocks).find_map(|(origin, chain)| {
                    let mut y = origin.y as f32 + HAT_HEIGHT;
                    let mut blocks = chain.iter().peekable();
                    while let Some(block) = blocks.next() {
                        let folded = block.kind == BlockKind::Select
                            && blocks
                                .peek()
                                .is_some_and(|next| next.kind == BlockKind::From);
                        let source = folded.then(|| blocks.next().unwrap());
                        if block.id == id || source.is_some_and(|source| source.id == id) {
                            return Some(vec2(origin.x as f32, y));
                        }
                        y += size_for(block.kind, folded, self.advanced).y;
                    }
                    None
                })
            });
        if let Some(at) = at {
            self.canvas.selected = Some(id);
            self.canvas.pan = vec2(44.0, 60.0) - at * self.canvas.zoom;
        }
    }

    fn drop_block(&mut self, id: Uuid, destination: CanvasPoint, slot: Option<DockSlot>) {
        let (blocks, layout) = self.project.active_query_mut();
        let source = std::iter::once(&mut *blocks)
            .chain(layout.chains.iter_mut().map(|chain| &mut chain.blocks))
            .enumerate()
            .find_map(|(chain, blocks)| {
                let index = blocks.iter().position(|block| block.id == id)?;
                Some((chain, index, blocks.remove(index)))
            });
        let (source_chain, source_index, block) = if let Some((chain, index, block)) = source {
            (Some(chain), index, block)
        } else if let Some(index) = layout.detached.iter().position(|node| node.block.id == id) {
            (None, index, layout.detached.remove(index).block)
        } else {
            return;
        };
        if let Some(slot) = slot {
            let target = if slot.chain == 0 {
                blocks
            } else {
                &mut layout.chains[slot.chain - 1].blocks
            };
            let index = slot.index
                - usize::from(source_chain == Some(slot.chain) && source_index < slot.index);
            target.insert(index.min(target.len()), block);
        } else {
            layout.detached.push(DetachedBlock {
                block,
                position: destination,
            });
        }
        self.changed();
    }

    fn block_content(
        &mut self,
        ui: &mut Ui,
        bounds: Rect,
        block: &Block,
        source: Option<&Block>,
        zoom: f32,
    ) {
        let lang = self.language;
        let left = bounds.left() + 13.0 * zoom;
        let mid = bounds.center().y;
        let white = Color32::WHITE;
        let label = |ui: &Ui, x, y, text| {
            words(
                ui,
                pos2(x, y),
                Align2::LEFT_CENTER,
                text,
                font(15.0 * zoom, true),
                white,
            )
        };
        let part = |range| FieldPart::new(block, range);
        match block.kind {
            BlockKind::Select => {
                let caption = if self.advanced {
                    "SELECT"
                } else {
                    lang.pick("Zeige", "Show")
                };
                let from_label = if self.advanced {
                    "FROM"
                } else {
                    lang.pick("aus Tabelle", "from table")
                };
                label(ui, left, mid, caption);
                let x = left + text_width(ui, caption, font(15.0 * zoom, true)) + 4.0 * zoom;
                let display = (block.input == "*" && !self.advanced)
                    .then_some(lang.pick("Alles", "Everything"));
                let width = if source.is_some() { 49.0 } else { 147.0 };
                self.pill(
                    ui,
                    pill_rect(x, mid, width, zoom),
                    part(0..block.input.len())
                        .display(display)
                        .kind(FieldKind::Select),
                    zoom,
                );
                if let Some(from) = source {
                    let x = bounds.left() + 133.0 * zoom;
                    label(ui, x, mid, from_label);
                    let x = bounds.left()
                        + if self.advanced {
                            192.0 * zoom
                        } else {
                            225.0 * zoom
                        };
                    self.pill(
                        ui,
                        pill_rect(x, mid, 76.0, zoom),
                        FieldPart::new(from, 0..from.input.len()).kind(FieldKind::Table),
                        zoom,
                    );
                }
            }
            BlockKind::Join => self.join_content(ui, bounds, block, zoom),
            BlockKind::OrderBy => {
                let caption = if self.advanced {
                    "ORDER BY"
                } else {
                    lang.pick("sortiere nach", "sort by")
                };
                let (x, y, order_x) = if self.advanced {
                    label(ui, left, mid, caption);
                    (left + 90.0 * zoom, mid, left + 208.0 * zoom)
                } else {
                    label(ui, left, bounds.top() + 17.0 * zoom, caption);
                    (left, bounds.top() + 44.0 * zoom, left + 119.0 * zoom)
                };
                if let Some((value, order)) = block.input.rsplit_once(' ')
                    && (order.eq_ignore_ascii_case("ASC") || order.eq_ignore_ascii_case("DESC"))
                {
                    self.pill(
                        ui,
                        pill_rect(x, y, 90.0, zoom),
                        part(0..value.len()).kind(FieldKind::Column),
                        zoom,
                    );
                    let display = if self.advanced {
                        order
                    } else if order.eq_ignore_ascii_case("ASC") {
                        lang.pick("Aufsteigend", "Ascending")
                    } else {
                        lang.pick("Absteigend", "Descending")
                    };
                    self.pill(
                        ui,
                        pill_rect(order_x, y, 84.0, zoom),
                        part(value.len() + 1..block.input.len())
                            .display(Some(display))
                            .kind(FieldKind::Order),
                        zoom,
                    );
                } else {
                    self.pill(
                        ui,
                        pill_rect(x, y, 188.0, zoom),
                        part(0..block.input.len()).kind(FieldKind::Column),
                        zoom,
                    );
                }
            }
            BlockKind::Where | BlockKind::And | BlockKind::Or | BlockKind::Having => {
                let caption = if self.advanced {
                    block.kind.keyword()
                } else {
                    match block.kind {
                        BlockKind::Where => lang.pick("filtere Zeilen", "filter rows"),
                        BlockKind::And => lang.pick("und zusätzlich", "and also"),
                        BlockKind::Or => lang.pick("oder alternativ", "or alternatively"),
                        _ => lang.pick("filtere Gruppen", "filter groups"),
                    }
                };
                label(ui, left, bounds.top() + 17.0 * zoom, caption);
                self.condition(
                    ui,
                    rect(
                        left,
                        bounds.top() + 31.0 * zoom,
                        bounds.width() - 26.0 * zoom,
                        22.0 * zoom,
                    ),
                    block,
                    0,
                    zoom,
                );
            }
            kind if kind.standalone() || kind.set_operation() => {
                let caption = if self.advanced {
                    if kind == BlockKind::Truncate {
                        "TRUNCATE TABLE"
                    } else {
                        kind.keyword()
                    }
                } else {
                    super::catalog::ITEMS
                        .iter()
                        .find(|item| item.action() == Action::Clause(kind))
                        .map_or(kind.keyword(), |item| {
                            item.label(false, lang)
                                .split(" [")
                                .next()
                                .unwrap_or(kind.keyword())
                        })
                };
                clipped_text(
                    ui,
                    rect(
                        left,
                        bounds.top() + 4.0 * zoom,
                        bounds.width() - 26.0 * zoom,
                        24.0 * zoom,
                    ),
                    caption,
                    15.0 * zoom,
                    true,
                    white,
                    1,
                );
                if self.data_fields(ui, bounds, block, zoom) {
                    return;
                }
                self.pill(
                    ui,
                    rect(
                        left,
                        bounds.top() + 31.0 * zoom,
                        bounds.width() - 26.0 * zoom,
                        22.0 * zoom,
                    ),
                    part(0..block.input.len()),
                    zoom,
                );
            }
            kind => {
                let caption = if self.advanced {
                    kind.keyword()
                } else {
                    match kind {
                        BlockKind::From => lang.pick("aus Tabelle", "from table"),
                        BlockKind::GroupBy => lang.pick("bilde Gruppen nach", "group by"),
                        _ => lang.pick("zeige höchstens", "show at most"),
                    }
                };
                label(ui, left, mid, caption);
                let x = left + text_width(ui, caption, font(15.0 * zoom, true)) + 9.0 * zoom;
                let field_kind = match kind {
                    BlockKind::From => FieldKind::Table,
                    BlockKind::GroupBy => FieldKind::Column,
                    _ => FieldKind::Raw,
                };
                self.pill(
                    ui,
                    pill_rect(x, mid, (bounds.right() - x) / zoom - 13.0, zoom),
                    part(0..block.input.len()).kind(field_kind),
                    zoom,
                );
            }
        }
    }

    fn data_fields(&mut self, ui: &mut Ui, bounds: Rect, block: &Block, zoom: f32) -> bool {
        let input = &block.input;
        let body = rect(
            bounds.left() + 13.0 * zoom,
            bounds.top() + 31.0 * zoom,
            bounds.width() - 26.0 * zoom,
            22.0 * zoom,
        );
        let values = rect(
            body.left(),
            body.top() + 30.0 * zoom,
            body.width(),
            body.height(),
        );
        if matches!(
            block.kind,
            BlockKind::Insert | BlockKind::InsertOrReplace | BlockKind::Upsert
        ) && let Some(mark) = crate::sql_import::keyword(input, "VALUES")
        {
            let tail = input[mark.end..].trim_start();
            if let Some(row) = tail
                .strip_prefix('(')
                .and_then(|tail| tail.strip_suffix(')'))
            {
                let offset = input.len() - tail.len() + 1;
                let fields = crate::sql_import::arguments(row);
                if !fields.is_empty() && fields.len() <= 5 {
                    self.pill(ui, body, FieldPart::new(block, 0..mark.end), zoom);
                    let width = (values.width() - (fields.len() - 1) as f32 * 6.0 * zoom)
                        / fields.len() as f32;
                    for (index, field) in fields.into_iter().enumerate() {
                        self.pill(
                            ui,
                            rect(
                                values.left() + index as f32 * (width + 6.0 * zoom),
                                values.top(),
                                width,
                                values.height(),
                            ),
                            FieldPart::new(block, offset + field.start..offset + field.end)
                                .kind(FieldKind::Value),
                            zoom,
                        );
                    }
                    return true;
                }
            }
        }
        if matches!(block.kind, BlockKind::Update | BlockKind::Delete)
            && let Some(where_) = crate::sql_import::keyword(input, "WHERE")
        {
            let start = input[..where_.start].trim_end().len();
            if block.kind == BlockKind::Update
                && let Some(set) = crate::sql_import::keyword(input, "SET")
                && set.end < start
                && let Some(equal) = input[set.end..start].find('=')
            {
                let equal = set.end + equal + 1;
                let value = start - input[equal..start].trim_start().len();
                let first_width = body.width() * 0.62;
                self.pill(
                    ui,
                    rect(body.left(), body.top(), first_width, body.height()),
                    FieldPart::new(block, 0..equal),
                    zoom,
                );
                self.pill(
                    ui,
                    rect(
                        body.left() + first_width + 6.0 * zoom,
                        body.top(),
                        body.width() - first_width - 6.0 * zoom,
                        body.height(),
                    ),
                    FieldPart::new(block, value..start).kind(FieldKind::Value),
                    zoom,
                );
            } else {
                self.pill(ui, body, FieldPart::new(block, 0..start), zoom);
            }
            let condition = input.len() - input[where_.end..].trim_start().len();
            self.condition(ui, values, block, condition, zoom);
            return true;
        }
        false
    }

    fn join_content(&mut self, ui: &mut Ui, bounds: Rect, block: &Block, zoom: f32) {
        let (join, rest) = compiler::join_parts(&block.input);
        let start = block.input.len() - rest.len();
        let on = rest.to_ascii_uppercase().find(" ON ");
        let table_end = start + on.unwrap_or(rest.len());
        let x = bounds.left() + 24.0 * zoom;
        let y = bounds.top() + 24.0 * zoom;
        let join_type = if join.is_empty() { "INNER" } else { join };
        let (join_x, type_x, type_width, table_x, table_width) = if self.advanced {
            (x + 82.0 * zoom, x, 64.0, x + 130.0 * zoom, 120.0)
        } else {
            (x, x + 132.0 * zoom, 161.0, x + 33.0 * zoom, 91.0)
        };
        words(
            ui,
            pos2(join_x, y),
            Align2::LEFT_CENTER,
            "JOIN",
            font(13.0 * zoom, true),
            Color32::WHITE,
        );
        self.pill(
            ui,
            rect(table_x, y - 12.0 * zoom, table_width * zoom, 24.0 * zoom),
            FieldPart::new(block, start..table_end).kind(FieldKind::Table),
            zoom,
        );
        let join_type = if self.advanced {
            join_type
        } else {
            join_label(self.language, join_type)
        };
        self.pill(
            ui,
            rect(type_x, y - 11.0 * zoom, type_width * zoom, 22.0 * zoom),
            FieldPart::new(block, 0..start)
                .display(Some(join_type))
                .kind(FieldKind::JoinType),
            zoom,
        );
        let condition = if self.advanced {
            words(
                ui,
                pos2(x, bounds.top() + 57.0 * zoom),
                Align2::LEFT_CENTER,
                "ON",
                font(13.0 * zoom, true),
                Color32::WHITE,
            );
            rect(
                x + 28.0 * zoom,
                bounds.top() + 44.0 * zoom,
                265.0 * zoom,
                27.0 * zoom,
            )
        } else {
            rect(x, bounds.top() + 44.0 * zoom, 293.0 * zoom, 27.0 * zoom)
        };
        if let Some(on) = on {
            self.condition(ui, condition, block, start + on + 4, zoom);
        } else {
            self.pill(
                ui,
                condition,
                FieldPart::new(block, 0..block.input.len()).display(Some("ON …")),
                zoom,
            );
        }
    }

    fn condition(&mut self, ui: &mut Ui, bounds: Rect, block: &Block, start: usize, zoom: f32) {
        let condition = &block.input[start..];
        if let Some((left, operator, right)) = split_condition(condition) {
            let op_start = start + left.len() + 1;
            let right_start = op_start + operator.len() + 1;
            let middle = 31.0 * zoom;
            let side = (bounds.width() - middle - 12.0 * zoom) / 2.0;
            let y = bounds.top();
            for (area, part) in [
                (
                    rect(bounds.left(), y, side, bounds.height()),
                    FieldPart::new(block, start..start + left.len()).kind(FieldKind::Column),
                ),
                (
                    rect(
                        bounds.left() + side + 6.0 * zoom,
                        y,
                        middle,
                        bounds.height(),
                    ),
                    FieldPart::new(block, op_start..op_start + operator.len())
                        .kind(FieldKind::Operator),
                ),
                (
                    rect(bounds.right() - side, y, side, bounds.height()),
                    FieldPart::new(block, right_start..right_start + right.len()).kind(
                        if block.kind == BlockKind::Join {
                            FieldKind::Column
                        } else {
                            FieldKind::Value
                        },
                    ),
                ),
            ] {
                self.pill(ui, area, part, zoom);
            }
        } else {
            self.pill(
                ui,
                bounds,
                FieldPart::new(block, start..block.input.len()),
                zoom,
            );
        }
    }

    fn pill(&mut self, ui: &mut Ui, bounds: Rect, field: FieldPart<'_>, zoom: f32) {
        let actual = field
            .block
            .input
            .get(field.range.clone())
            .unwrap_or_default();
        let text = field.display.unwrap_or(actual).trim();
        let shown = if field.kind == FieldKind::Table {
            text.strip_prefix('"')
                .and_then(|text| text.strip_suffix('"'))
                .unwrap_or(text)
        } else {
            text
        };
        let response = ui.interact(
            bounds,
            Id::unique((
                "block-field",
                field.block.id,
                field.range.start,
                field.range.end,
            )),
            Sense::click(),
        );
        let embedded = field
            .block
            .reporters
            .iter()
            .find(|slot| slot.range == field.range);
        let accepts_reporter = matches!(
            field.kind,
            FieldKind::Select | FieldKind::Column | FieldKind::Value
        );
        let border_radius = (bounds.height() / 2.0).min(10.0 * zoom);
        let is_join_type = field.kind == FieldKind::JoinType;
        if is_join_type {
            ui.painter().rect_filled(
                bounds,
                8.0 * zoom,
                Color32::from_white_alpha(if response.hovered() { 70 } else { 36 }),
            );
        } else if embedded.is_some() {
            ui.painter()
                .rect_filled(bounds, border_radius, rgb(0x6d28d9));
        } else {
            chip_background(ui, bounds, border_radius, response.hovered());
        }
        let mut label_rect = bounds.shrink2(vec2(6.0 * zoom, 0.0));
        if is_join_type {
            glyph(
                ui,
                bounds.right_center() - vec2(10.0 * zoom, 0.0),
                icon::DOWN,
                13.0 * zoom,
                Color32::WHITE,
            );
            label_rect.max.x -= 12.0 * zoom;
        }
        clipped_text(
            ui,
            label_rect,
            shown,
            11.2 * zoom,
            !is_join_type,
            Color32::WHITE,
            1,
        );
        if response.clicked() {
            let title = field.kind.title(self.language);
            self.field_editor = Some(FieldEditor {
                title: title.to_owned(),
                block: field.block.id,
                range: field.range.clone(),
                value: if is_join_type && actual.trim().is_empty() {
                    "INNER".into()
                } else {
                    actual.trim().into()
                },
                choices: self.field_choices(field.kind),
                append_space: is_join_type,
                reporter: embedded.map(|slot| slot.reporter.clone()),
            });
        }
        if accepts_reporter
            && let Some(payload) = response.dnd_hover_payload::<Drag>()
            && let Drag::Palette(Action::Expression(preset)) = *payload
            && response.dnd_release_payload::<Drag>().is_some()
        {
            self.apply_reporter(field.block.id, field.range, self.authored_reporter(preset));
        }
    }

    fn field_choices(&self, kind: FieldKind) -> Vec<Choice> {
        let pair = |label: &str, value: &str| Choice {
            label: label.into(),
            value: value.into(),
        };
        match kind {
            FieldKind::Table => self
                .schema
                .iter()
                .map(|table| pair(&table.name, &sql_name(&table.name)))
                .collect(),
            FieldKind::Column | FieldKind::Select => {
                let mut choices = Vec::new();
                if kind == FieldKind::Select {
                    choices.push(pair(self.language.pick("Alles (*)", "Everything (*)"), "*"));
                }
                for table in &self.schema {
                    for column in &table.columns {
                        choices.push(pair(
                            &format!("{}.{column}", table.name),
                            &format!("{}.{}", sql_name(&table.name), sql_name(column)),
                        ));
                    }
                }
                choices
            }
            FieldKind::Order => ["ASC", "DESC"]
                .into_iter()
                .map(|value| pair(value, value))
                .collect(),
            FieldKind::JoinType => ["INNER", "LEFT", "RIGHT", "FULL", "CROSS", "NATURAL"]
                .into_iter()
                .map(|value| {
                    pair(
                        if self.advanced {
                            value
                        } else {
                            join_label(self.language, value)
                        },
                        value,
                    )
                })
                .collect(),
            FieldKind::Operator => ["=", "!=", ">", ">=", "<", "<=", "LIKE", "IS", "IS NOT"]
                .into_iter()
                .map(|value| pair(value, value))
                .collect(),
            FieldKind::Raw | FieldKind::Value => Vec::new(),
        }
    }

    pub(super) fn apply_field(&mut self, id: Uuid, range: Range<usize>, value: &str) {
        let (blocks, layout) = self.project.active_query_mut();
        let block = blocks
            .iter_mut()
            .chain(layout.chains.iter_mut().flat_map(|chain| &mut chain.blocks))
            .chain(layout.detached.iter_mut().map(|node| &mut node.block))
            .find(|block| block.id == id);
        if block.is_some_and(|block| block.edit_input(range, value)) {
            self.changed();
        }
    }

    pub(super) fn apply_reporter(&mut self, id: Uuid, range: Range<usize>, reporter: Reporter) {
        let (blocks, layout) = self.project.active_query_mut();
        let block = blocks
            .iter_mut()
            .chain(layout.chains.iter_mut().flat_map(|chain| &mut chain.blocks))
            .chain(layout.detached.iter_mut().map(|node| &mut node.block))
            .find(|block| block.id == id);
        if block.is_some_and(|block| block.set_reporter(range, reporter)) {
            self.changed();
        }
    }
}

fn pill_rect(x: f32, y: f32, width: f32, scale: f32) -> Rect {
    rect(x, y - 9.5 * scale, width.max(30.0) * scale, 19.0 * scale)
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum FieldKind {
    Raw,
    Value,
    Table,
    Select,
    Column,
    Order,
    JoinType,
    Operator,
}

impl FieldKind {
    fn title(self, lang: Language) -> &'static str {
        match self {
            Self::Raw | Self::Value => lang.pick("SQL-Ausdruck", "SQL expression"),
            Self::Table => lang.pick("Tabelle wählen", "Choose table"),
            Self::Select => lang.pick("Spalten wählen", "Choose columns"),
            Self::Column => lang.pick("Spalte wählen", "Choose column"),
            Self::Order => lang.pick("Sortierreihenfolge", "Sort direction"),
            Self::JoinType => lang.pick("Verbindungsart", "Join type"),
            Self::Operator => "Operator",
        }
    }
}

struct FieldPart<'a> {
    block: &'a Block,
    range: Range<usize>,
    display: Option<&'a str>,
    kind: FieldKind,
}

impl<'a> FieldPart<'a> {
    fn new(block: &'a Block, range: Range<usize>) -> Self {
        Self {
            block,
            range,
            display: None,
            kind: FieldKind::Raw,
        }
    }

    fn display(mut self, display: Option<&'a str>) -> Self {
        self.display = display;
        self
    }
    fn kind(mut self, kind: FieldKind) -> Self {
        self.kind = kind;
        self
    }
}

fn split_condition(input: &str) -> Option<(&str, &str, &str)> {
    for operator in [
        " IS NOT ", " LIKE ", " >= ", " <= ", " != ", " = ", " > ", " < ", " IS ",
    ] {
        if let Some((left, right)) = input.split_once(operator)
            && !left.contains(['\'', '"'])
        {
            return Some((left, operator.trim(), right));
        }
    }
    None
}

fn join_label(lang: Language, kind: &str) -> &'static str {
    match kind.to_ascii_uppercase().as_str() {
        "LEFT" => lang.pick("Alle linken Zeilen", "All left rows"),
        "RIGHT" => lang.pick("Alle rechten Zeilen", "All right rows"),
        "FULL" => lang.pick("Alle Zeilen", "All rows"),
        "CROSS" => lang.pick("Alle Kombinationen", "All combinations"),
        "NATURAL" => lang.pick("Gleiche Spaltennamen", "Matching column names"),
        _ => lang.pick("Nur passende Zeilen", "Matching rows only"),
    }
}

pub fn sql_name(name: &str) -> String {
    quote_identifier(name)
}

fn curve(ui: &Ui, a: Pos2, b: Pos2, delta: f32, color: Color32) {
    ui.painter()
        .add(egui::epaint::CubicBezierShape::from_points_stroke(
            [a, a + vec2(delta, 0.0), b + vec2(delta, 0.0), b],
            false,
            Color32::TRANSPARENT,
            Stroke::new(2.2, color),
        ));
    for point in [a, b] {
        ui.painter().circle_filled(point, 3.1, color);
    }
}
