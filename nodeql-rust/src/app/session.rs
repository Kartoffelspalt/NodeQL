use super::{
    NodeQlApp,
    style::{Dock, Language, Theme},
};
use crate::{model::Project, project};
use eframe::egui;
use serde::{Deserialize, Serialize};
use std::{
    collections::BTreeMap,
    path::{Path, PathBuf},
    time::{Duration, Instant, SystemTime},
};

const LIMIT: u64 = 4 * 1024 * 1024;

#[derive(Clone, Serialize, Deserialize)]
pub struct Recent {
    pub name: String,
    pub path: PathBuf,
}

#[derive(Clone, Serialize, Deserialize)]
struct Recovery {
    project: Project,
    path: Option<PathBuf>,
    saved_at: Option<SystemTime>,
}

#[derive(Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct Preferences {
    pub theme: Theme,
    pub language: Language,
    pub advanced: bool,
    pub dock: Dock,
    pub palette_width: f32,
    pub runtime_width: f32,
    pub split: f32,
    pub live_preview: bool,
}

impl Default for Preferences {
    fn default() -> Self {
        Self {
            theme: Theme::Midnight,
            language: Language::German,
            advanced: false,
            dock: Dock::RightSplit,
            palette_width: 266.0,
            runtime_width: 368.0,
            split: 0.545,
            live_preview: true,
        }
    }
}

#[derive(Default, Serialize, Deserialize)]
#[serde(default)]
pub struct Session {
    pub recent: Vec<Recent>,
    pub preferences: Preferences,
    pub lessons: BTreeMap<String, super::workshop::Progress>,
    last: Option<PathBuf>,
    recovery: Option<Recovery>,
    #[serde(skip)]
    pub file: Option<PathBuf>,
    #[serde(skip)]
    write_at: Option<Instant>,
}

impl Session {
    pub fn open(directory: Option<PathBuf>) -> Self {
        let file = directory.map(|path| path.join("session.json"));
        let mut session: Self = file
            .as_deref()
            .and_then(|path| project::read_json(path, LIMIT).ok())
            .unwrap_or_default();
        session.recent.truncate(12);
        session.file = file;
        session
    }

    pub fn resume(&self) -> Option<(Project, Option<PathBuf>, bool)> {
        if let Some(draft) = &self.recovery
            && project::validate(&draft.project).is_ok()
        {
            let path = draft
                .path
                .clone()
                .filter(|path| modified(path).is_some_and(|time| Some(time) == draft.saved_at));
            return Some((draft.project.clone(), path, true));
        }
        let path = self.last.as_ref()?;
        let (project, imported) = project::load_with_origin(path).ok()?;
        Some((project, (!imported).then(|| path.clone()), imported))
    }

    pub fn remember(&mut self, path: PathBuf, name: String) {
        let path = path.canonicalize().unwrap_or(path);
        self.recent.retain(|entry| entry.path != path);
        self.recent.insert(0, Recent { name, path });
        self.recent.truncate(12);
    }

    pub fn schedule(&mut self) {
        if self.file.is_some() {
            self.write_at = Some(Instant::now() + Duration::from_millis(550));
        }
    }

    fn save(&self) -> Result<(), project::ProjectError> {
        if let Some(path) = &self.file {
            if let Some(parent) = path.parent() {
                std::fs::create_dir_all(parent)?;
            }
            project::write_json(path, self, LIMIT)?;
        }
        Ok(())
    }
}

fn modified(path: &Path) -> Option<SystemTime> {
    path.metadata().ok()?.modified().ok()
}

impl NodeQlApp {
    pub(super) fn set_session_project(&mut self) {
        if let Some(path) = &self.path {
            self.session
                .remember(path.clone(), self.project.name.clone());
        }
        self.session.last.clone_from(&self.path);
        self.session.schedule();
    }

    pub(super) fn refresh_session(&mut self, ctx: &egui::Context) {
        let preferences = Preferences {
            theme: self.theme,
            language: self.language,
            advanced: self
                .practice
                .as_ref()
                .map_or(self.advanced, |practice| practice.main.advanced),
            dock: self.dock,
            palette_width: self.palette_width,
            runtime_width: self.runtime_width,
            split: self.split,
            live_preview: self.live_preview,
        };
        if preferences != self.session.preferences {
            self.session.preferences = preferences;
            self.session.schedule();
        }
        if let Some(at) = self.session.write_at {
            let delay = at.saturating_duration_since(Instant::now());
            if delay.is_zero() {
                if self.pending.is_none() {
                    self.flush_session();
                }
            } else {
                ctx.request_repaint_after(delay);
            }
        }
    }

    pub(super) fn flush_session(&mut self) {
        self.session.write_at = None;
        self.store_practice();
        if self.session.file.is_none() {
            return;
        }
        let (project, path, dirty) = if let Some(practice) = &self.practice {
            (
                &practice.main.project,
                &practice.main.path,
                practice.main.dirty,
            )
        } else {
            (&self.project, &self.path, self.dirty)
        };
        self.session.recovery = (dirty && project.settings.autosave).then(|| Recovery {
            project: project.clone(),
            path: path.clone(),
            saved_at: self.saved_modified,
        });
        if let Err(error) = self.session.save() {
            self.status = format!("Autosave: {error}");
        }
    }

    pub(super) fn capture_saved_version(&mut self) {
        self.saved_modified = self.path.as_deref().and_then(modified);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn recovery_preserves_the_original_and_detaches_if_it_was_changed() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("work.json");
        let original = Project::default();
        project::save(&path, &original).unwrap();
        let mut session = Session::open(Some(directory.path().into()));
        let draft = Project {
            name: "Recovered draft".into(),
            ..original.clone()
        };
        session.recovery = Some(Recovery {
            project: draft.clone(),
            path: Some(path.clone()),
            saved_at: modified(&path),
        });
        session.save().unwrap();
        assert_eq!(project::load(&path).unwrap(), original);
        let resumed = Session::open(Some(directory.path().into()));
        assert_eq!(
            resumed.resume(),
            Some((draft.clone(), Some(path.clone()), true))
        );
        std::fs::remove_file(path).unwrap();
        assert_eq!(resumed.resume(), Some((draft, None, true)));
    }
}
