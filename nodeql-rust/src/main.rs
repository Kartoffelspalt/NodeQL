#![cfg_attr(target_os = "windows", windows_subsystem = "windows")]

use nodeql_rust::app::{NodeQlApp, window_icon};

fn main() -> eframe::Result {
    eframe::run_native(
        "NodeQL",
        eframe::NativeOptions {
            viewport: eframe::egui::ViewportBuilder::default()
                .with_inner_size([1710.0, 966.0])
                .with_icon(window_icon())
                .with_min_inner_size([1040.0, 700.0]),
            ..Default::default()
        },
        Box::new(|context| Ok(Box::new(NodeQlApp::new(context)))),
    )
}
