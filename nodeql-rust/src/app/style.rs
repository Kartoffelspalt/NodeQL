use eframe::egui::{
    self, Align2, Color32, FontFamily, FontId, Pos2, Rect, Response, Sense, Stroke, StrokeKind, Ui,
    Vec2, pos2, vec2,
};
use std::sync::Arc;

pub const fn rgb(value: u32) -> Color32 {
    Color32::from_rgb((value >> 16) as u8, (value >> 8) as u8, value as u8)
}

#[derive(Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub enum Theme {
    Light,
    Dark,
    Midnight,
    Matrix,
}

#[derive(Clone, Copy)]
pub struct Colors {
    pub top: Color32,
    pub text: Color32,
    pub panel: Color32,
    pub raised: Color32,
    pub canvas: Color32,
    pub border: Color32,
    pub muted: Color32,
    pub sql: Color32,
    pub primary: Color32,
    pub on_primary: Color32,
    pub selected: Color32,
}

impl Theme {
    pub fn colors(self) -> Colors {
        let (top, text, panel, raised, canvas, border, muted, sql, primary, on_primary, selected) =
            match self {
                Self::Light => (
                    0xffffff, 0x0f172a, 0xf8fafc, 0xffffff, 0xe2e8f0, 0xcbd5e1, 0x64748b, 0x075985,
                    0x32633c, 0xffffff, 0xb4efb7,
                ),
                Self::Dark => (
                    0x0b1220, 0xf8fafc, 0x0f172a, 0x111c30, 0x111827, 0x1e293b, 0x94a3b8, 0xbde0fe,
                    0x9cd49f, 0x083915, 0x1b5026,
                ),
                Self::Midnight => (
                    0x070f17, 0xf0f9ff, 0x0c1420, 0x0e1b2b, 0x09131d, 0x1a4356, 0x7bc7ed, 0xbae6fd,
                    0x95ca92, 0x083915, 0x1b411c,
                ),
                Self::Matrix => (
                    0x040b05, 0xd1fae5, 0x07130a, 0x0a1f0e, 0x061009, 0x14532d, 0x86efac, 0xbbf7d0,
                    0x86efac, 0x052e16, 0x14532d,
                ),
            };
        Colors {
            top: rgb(top),
            text: rgb(text),
            panel: rgb(panel),
            raised: rgb(raised),
            canvas: rgb(canvas),
            border: rgb(border),
            muted: rgb(muted),
            sql: rgb(sql),
            primary: rgb(primary),
            on_primary: rgb(on_primary),
            selected: rgb(selected),
        }
    }

    pub fn name(self) -> &'static str {
        match self {
            Self::Light => "Light",
            Self::Dark => "Dark",
            Self::Midnight => "Midnight",
            Self::Matrix => "Matrix",
        }
    }

    pub fn apply(self, ctx: &egui::Context) {
        let colors = self.colors();
        let mut visuals = if self == Self::Light {
            egui::Visuals::light()
        } else {
            egui::Visuals::dark()
        };
        visuals.override_text_color = Some(colors.text);
        visuals.panel_fill = colors.panel;
        visuals.window_fill = colors.panel;
        visuals.extreme_bg_color = colors.raised;
        visuals.faint_bg_color = colors.raised;
        visuals.window_stroke = Stroke::new(1.0, colors.border);
        visuals.selection.bg_fill = colors.selected;
        for widget in [
            &mut visuals.widgets.inactive,
            &mut visuals.widgets.hovered,
            &mut visuals.widgets.active,
        ] {
            widget.bg_fill = colors.raised;
            widget.weak_bg_fill = colors.raised;
            widget.bg_stroke = Stroke::new(1.0, colors.border);
            widget.corner_radius = egui::CornerRadius::same(10);
        }
        visuals.widgets.hovered.weak_bg_fill = colors.selected;
        ctx.set_visuals(visuals);
        ctx.global_style_mut(|style| {
            style.spacing.item_spacing = vec2(8.0, 8.0);
            style.spacing.button_padding = vec2(12.0, 7.0);
            style.spacing.interact_size.y = 30.0;
            style.spacing.scroll.bar_width = 6.0;
        });
    }
}

#[derive(Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub enum Language {
    German,
    English,
}

impl Language {
    pub fn pick<'a>(self, de: &'a str, en: &'a str) -> &'a str {
        match self {
            Self::German => de,
            Self::English => en,
        }
    }

    pub fn native(self) -> &'static str {
        self.pick("Deutsch", "English")
    }
}

#[derive(Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub enum Dock {
    RightSplit,
    PreviewBottom,
    CommandBottom,
}

pub mod icon {
    pub const CODE: char = '\u{e176}';
    pub const DATA: char = '\u{f04e6}';
    pub const EDIT_NOTE: char = '\u{f04f6}';
    pub const SCHEMA: char = '\u{e558}';
    pub const TREE: char = '\u{e044}';
    pub const STORAGE: char = '\u{e609}';
    pub const EXTENSION: char = '\u{e250}';
    pub const TABLE: char = '\u{f41d}';
    pub const PLAY: char = '\u{f00a0}';
    pub const STOP: char = '\u{f01dc}';
    pub const PAINT: char = '\u{f0a8}';
    pub const LINK: char = '\u{f85a}';
    pub const HELP: char = '\u{f7e4}';
    pub const SETTINGS: char = '\u{e57f}';
    pub const SCHOOL: char = '\u{f012e}';
    pub const SEARCH: char = '\u{e567}';
    pub const ORDER: char = '\u{f895}';
    pub const EDIT: char = '\u{f6fb}';
    pub const DELETE: char = '\u{f696}';
    pub const HANDLE: char = '\u{f6e3}';
    pub const ADD: char = '\u{f537}';
    pub const TERMINAL: char = '\u{f039c}';
    pub const COPY: char = '\u{f66c}';
    pub const ROWS: char = '\u{f0210}';
    pub const FULLSCREEN: char = '\u{f7a6}';
    pub const EXPORT: char = '\u{f826}';
    pub const DOWN: char = '\u{e098}';
    pub const CHECK: char = '\u{f636}';
    pub const CLOSE: char = '\u{f647}';
    pub const REFRESH: char = '\u{e514}';
    pub const CHEVRON: char = '\u{e15f}';
    pub const CHEVRON_LEFT: char = '\u{e15e}';
}

pub fn install_fonts(ctx: &egui::Context) {
    let mut fonts = egui::FontDefinitions::default();
    for (key, bytes) in [
        (
            "NodeQL Roboto",
            include_bytes!("../../assets/ui/Roboto-Regular.ttf").as_slice(),
        ),
        (
            "NodeQL Bold",
            include_bytes!("../../assets/ui/Roboto-Bold.ttf").as_slice(),
        ),
        (
            "NodeQL Material",
            include_bytes!("../../assets/ui/MaterialIcons-Regular.otf").as_slice(),
        ),
    ] {
        fonts
            .font_data
            .insert(key.into(), Arc::new(egui::FontData::from_static(bytes)));
    }
    let fallback = fonts.families[&FontFamily::Proportional].clone();
    fonts
        .families
        .get_mut(&FontFamily::Proportional)
        .unwrap()
        .insert(0, "NodeQL Roboto".into());
    fonts.families.insert(
        FontFamily::Name("NodeQL Bold".into()),
        std::iter::once("NodeQL Bold".into())
            .chain(fallback)
            .collect(),
    );
    fonts.families.insert(
        FontFamily::Name("NodeQL Material".into()),
        vec!["NodeQL Material".into()],
    );
    // Flutter uses the system face on macOS. Read it from the OS and retain
    // the bundled Roboto faces as fallbacks on other platforms.
    #[cfg(target_os = "macos")]
    if let Ok(bytes) = std::fs::read("/System/Library/Fonts/SFNS.ttf") {
        let regular = egui::FontData::from_owned(bytes);
        let axes = regular.variation_axes();
        if axes
            .iter()
            .any(|axis| axis.tag == egui::epaint::text::Tag::new(b"wght"))
        {
            let bold = regular.clone().tweak(egui::FontTweak {
                coords: egui::epaint::text::VariationCoords::new([
                    (b"wght", 700.0),
                    (b"opsz", 14.0),
                ]),
                ..Default::default()
            });
            let regular = regular.tweak(egui::FontTweak {
                coords: egui::epaint::text::VariationCoords::new([
                    (b"wght", 400.0),
                    (b"opsz", 14.0),
                ]),
                ..Default::default()
            });
            fonts
                .font_data
                .insert("NodeQL System".into(), Arc::new(regular));
            fonts
                .font_data
                .insert("NodeQL System Bold".into(), Arc::new(bold));
            fonts
                .families
                .get_mut(&FontFamily::Proportional)
                .unwrap()
                .insert(0, "NodeQL System".into());
            fonts
                .families
                .get_mut(&FontFamily::Name("NodeQL Bold".into()))
                .unwrap()
                .insert(0, "NodeQL System Bold".into());
        }
    }
    ctx.set_fonts(fonts);
}

pub fn logo_image() -> egui::ColorImage {
    let image = image::load_from_memory(include_bytes!("../../assets/ui/logo.png"))
        .expect("NodeQL app icon")
        .to_rgba8();
    egui::ColorImage::from_rgba_unmultiplied(
        [image.width() as usize, image.height() as usize],
        image.as_raw(),
    )
}

pub fn font(size: f32, bold: bool) -> FontId {
    if bold {
        FontId::new(size, FontFamily::Name("NodeQL Bold".into()))
    } else {
        FontId::proportional(size)
    }
}

pub fn glyph(ui: &Ui, pos: Pos2, value: char, size: f32, color: Color32) {
    ui.painter().text(
        pos,
        Align2::CENTER_CENTER,
        value,
        FontId::new(size, FontFamily::Name("NodeQL Material".into())),
        color,
    );
}

pub fn words(ui: &Ui, pos: Pos2, anchor: Align2, text: &str, font: FontId, color: Color32) {
    ui.painter().text(pos, anchor, text, font, color);
}

pub fn text_width(ui: &Ui, text: &str, font: FontId) -> f32 {
    ui.painter()
        .layout_no_wrap(text.into(), font, Color32::WHITE)
        .size()
        .x
}

pub fn region(ui: &mut Ui, id: impl egui::AsIdSalt, rect: Rect) -> Ui {
    let mut child = ui.new_child(egui::UiBuilder::new().id_salt(id).max_rect(rect));
    child.set_clip_rect(ui.clip_rect().intersect(rect));
    child
}

pub fn rect(x: f32, y: f32, width: f32, height: f32) -> Rect {
    Rect::from_min_size(pos2(x, y), vec2(width, height))
}

pub fn hit(ui: &mut Ui, bounds: Rect, sense: Sense) -> Response {
    let id = ui.next_auto_id();
    ui.skip_ahead_auto_ids(1);
    ui.interact(bounds, id, sense)
}

pub fn rule(ui: &Ui, a: Pos2, b: Pos2, color: Color32) {
    ui.painter().line_segment([a, b], Stroke::new(1.0, color));
}

pub struct Control<'a> {
    pub text: &'a str,
    pub icon: Option<char>,
    pub tip: &'a str,
    pub fg: Color32,
    pub bg: Color32,
    pub border: Color32,
    pub radius: u8,
    pub size: f32,
}

impl<'a> Control<'a> {
    pub fn new(text: &'a str, fg: Color32) -> Self {
        Self {
            text,
            icon: None,
            tip: text,
            fg,
            bg: Color32::TRANSPARENT,
            border: Color32::TRANSPARENT,
            radius: 14,
            size: 14.0,
        }
    }

    pub fn icon(icon: char, tip: &'a str, fg: Color32) -> Self {
        Self {
            icon: Some(icon),
            tip,
            size: 21.0,
            ..Self::new("", fg)
        }
    }

    pub fn width(&self, ui: &Ui, padding: f32) -> f32 {
        text_width(ui, self.text, font(self.size, true))
            + if self.icon.is_some() { 26.0 } else { 0.0 }
            + padding * 2.0
    }

    pub fn show(&self, ui: &mut Ui, bounds: Rect) -> Response {
        let response = hit(ui, bounds, Sense::click());
        response.widget_info(|| {
            egui::WidgetInfo::labeled(egui::Role::Button, ui.is_enabled(), self.tip)
        });
        let fill = if response.hovered() {
            self.bg.blend(self.fg.gamma_multiply(0.10))
        } else {
            self.bg
        };
        let fg = if ui.is_enabled() {
            self.fg
        } else {
            self.fg.gamma_multiply(0.38)
        };
        ui.painter().rect(
            bounds,
            self.radius,
            fill,
            Stroke::new(1.0, self.border),
            StrokeKind::Inside,
        );
        let center = bounds.center();
        let label_width = text_width(ui, self.text, font(self.size, true));
        match (self.icon, self.text.is_empty()) {
            (Some(icon), true) => glyph(ui, center, icon, self.size, fg),
            (Some(icon), false) => {
                glyph(
                    ui,
                    center - vec2((label_width + 8.0) / 2.0, 0.0),
                    icon,
                    self.size + 4.0,
                    fg,
                );
                words(
                    ui,
                    center + vec2(13.0, 0.0),
                    Align2::CENTER_CENTER,
                    self.text,
                    font(self.size, true),
                    fg,
                );
            }
            _ => words(
                ui,
                center,
                Align2::CENTER_CENTER,
                self.text,
                font(self.size, true),
                fg,
            ),
        }
        response.on_hover_text(self.tip)
    }
}

pub fn texture(ctx: &egui::Context) -> egui::TextureHandle {
    ctx.load_texture("nodeql-brand", logo_image(), egui::TextureOptions::LINEAR)
}

pub fn show_logo(ui: &Ui, logo: &egui::TextureHandle, point: Pos2, size: f32) {
    egui::Image::new(egui::load::SizedTexture::new(logo.id(), Vec2::splat(size)))
        .corner_radius(10)
        .paint_at(ui, Rect::from_min_size(point, Vec2::splat(size)));
}
