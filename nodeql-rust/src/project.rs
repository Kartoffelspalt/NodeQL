use std::{collections::HashSet, fs::File, io::{Read, Write}, path::Path};
use crate::model::{FORMAT, MAX_BLOCKS, Project, VERSION};
use thiserror::Error;

const MAX_FILE_BYTES: u64 = 2 * 1024 * 1024;

#[derive(Debug, Error)]
pub enum ProjectError {
    #[error("Dateifehler: {0}")]
    Io(#[from] std::io::Error),
    #[error("Ungültiges Projekt-JSON: {0}")]
    Json(#[from] serde_json::Error),
    #[error("{0}")]
    Invalid(String),
}

pub fn validate(project: &Project) -> Result<(), ProjectError> {
    let invalid = |text: &str| ProjectError::Invalid(text.into());
    if project.format != FORMAT || project.version != VERSION {
        return Err(invalid("Dieses Projektformat wird noch nicht unterstützt. Flutter-Projekte benötigen einen Import."));
    }
    if project.name.trim().is_empty() || project.name.len() > 256 {
        return Err(invalid("Der Projektname muss 1 bis 256 Bytes lang sein."));
    }
    if project.blocks.len() > MAX_BLOCKS {
        return Err(invalid("Das Projekt enthält zu viele Blöcke (maximal 256)."));
    }
    let mut ids = HashSet::new();
    for block in &project.blocks {
        if !ids.insert(block.id) { return Err(invalid("Block-IDs müssen eindeutig sein.")); }
        if block.input.len() > 16 * 1024 { return Err(invalid("Ein Blockausdruck ist zu lang.")); }
    }
    Ok(())
}

pub fn load(path: &Path) -> Result<Project, ProjectError> {
    let mut bytes = Vec::new();
    File::open(path)?.take(MAX_FILE_BYTES + 1).read_to_end(&mut bytes)?;
    if bytes.len() as u64 > MAX_FILE_BYTES {
        return Err(ProjectError::Invalid("Die Projektdatei ist größer als 2 MiB.".into()));
    }
    // Inspect the envelope before decoding: never reinterpret a Flutter file.
    let envelope: serde_json::Value = serde_json::from_slice(&bytes)?;
    if envelope.get("format").and_then(|v| v.as_str()) != Some(FORMAT) {
        return Err(ProjectError::Invalid("Kein Rust-Projekt. Der Import von Flutter-Projekten ist noch nicht implementiert.".into()));
    }
    let mut project: Project = serde_json::from_value(envelope)?;
    validate(&project)?;
    if let Some(database) = &project.database
        && database.is_relative()
    {
        project.database = Some(std::fs::canonicalize(path)?.parent().unwrap().join(database));
    }
    Ok(project)
}

pub fn save(path: &Path, project: &Project) -> Result<(), ProjectError> {
    validate(project)?;
    let mut saved = project.clone();
    // Keep relative database references stable when saving to a new directory.
    if let Some(database) = &saved.database
        && database.is_relative()
    {
        saved.database = Some(std::env::current_dir()?.join(database));
    }
    let encoded = serde_json::to_vec_pretty(&saved)?;
    if encoded.len() as u64 > MAX_FILE_BYTES {
        return Err(ProjectError::Invalid("Das Projekt ist größer als 2 MiB.".into()));
    }
    let parent = path.parent().filter(|p| !p.as_os_str().is_empty()).unwrap_or(Path::new("."));
    let mut temporary = tempfile::NamedTempFile::new_in(parent)?;
    temporary.write_all(&encoded)?;
    temporary.write_all(b"\n")?;
    temporary.as_file().sync_all()?;
    temporary.persist(path).map_err(|error| error.error)?;
    Ok(())
}
