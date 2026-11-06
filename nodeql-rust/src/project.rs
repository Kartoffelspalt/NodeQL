use crate::model::{FORMAT, MAX_BLOCKS, MAX_TABS, Project, VERSION};
use std::{
    collections::HashSet,
    fs::File,
    io::{Read, Write},
    path::Path,
};
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
        return Err(invalid(
            "Dieses Projektformat wird noch nicht unterstützt. Flutter-Projekte benötigen einen Import.",
        ));
    }
    if project.name.trim().is_empty() || project.name.len() > 256 {
        return Err(invalid("Der Projektname muss 1 bis 256 Bytes lang sein."));
    }
    if project.tab_count() > MAX_TABS || project.workspace.active >= project.tab_count() {
        return Err(invalid("Ungültige Arbeitsbereiche."));
    }
    let mut ids = HashSet::new();
    for index in 0..project.tab_count() {
        let (blocks, layout) = project.query(index);
        if layout.block_count(blocks) > MAX_BLOCKS
            || layout.name.len() > 256
            || layout.chains.len() >= MAX_BLOCKS
        {
            return Err(invalid("Ein Arbeitsbereich ist zu groß."));
        }
        for block in layout.blocks(blocks) {
            if !ids.insert(block.id) {
                return Err(invalid("Block-IDs müssen eindeutig sein."));
            }
            if block.input.len() > 16 * 1024 {
                return Err(invalid("Ein Blockausdruck ist zu lang."));
            }
            let mut previous = 0;
            for slot in &block.reporters {
                if slot.range.start < previous
                    || slot.range.is_empty()
                    || !slot.reporter.validate(0)
                    || block.input.get(slot.range.clone()) != Some(slot.reporter.sql().as_str())
                {
                    return Err(invalid("Ein eingebetteter Reporter ist ungültig."));
                }
                previous = slot.range.end;
            }
        }
    }
    Ok(())
}

pub fn load(path: &Path) -> Result<Project, ProjectError> {
    load_with_origin(path).map(|(project, _)| project)
}

pub fn load_with_origin(path: &Path) -> Result<(Project, bool), ProjectError> {
    let envelope: serde_json::Value = read_json(path, MAX_FILE_BYTES)?;
    let (mut project, imported) = match envelope.get("format").and_then(|v| v.as_str()) {
        Some(FORMAT) => (serde_json::from_value(envelope)?, false),
        Some("nodeql_project_v2" | "scratchql_project_v2") => {
            (crate::flutter_project::convert(&envelope, path)?, true)
        }
        None if envelope.get("roots").is_some() => {
            (crate::flutter_project::convert(&envelope, path)?, true)
        }
        _ => {
            return Err(ProjectError::Invalid(
                "Unbekanntes NodeQL-Projektformat.".into(),
            ));
        }
    };
    validate(&project)?;
    if let Some(database) = &project.database
        && database.is_relative()
    {
        project.database = Some(
            std::fs::canonicalize(path)?
                .parent()
                .unwrap()
                .join(database),
        );
    }
    Ok((project, imported))
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
    write_json(path, &saved, MAX_FILE_BYTES)
}

pub(crate) fn read_json<T: serde::de::DeserializeOwned>(
    path: &Path,
    limit: u64,
) -> Result<T, ProjectError> {
    let mut bytes = Vec::new();
    File::open(path)?.take(limit + 1).read_to_end(&mut bytes)?;
    if bytes.len() as u64 > limit {
        return Err(ProjectError::Invalid(format!(
            "Die Datei ist größer als {} MiB.",
            limit / (1024 * 1024)
        )));
    }
    Ok(serde_json::from_slice(&bytes)?)
}

pub(crate) fn write_json(
    path: &Path,
    value: &impl serde::Serialize,
    limit: u64,
) -> Result<(), ProjectError> {
    let encoded = serde_json::to_vec_pretty(value)?;
    if encoded.len() as u64 + 1 > limit {
        return Err(ProjectError::Invalid(format!(
            "Die Datei ist größer als {} MiB.",
            limit / (1024 * 1024)
        )));
    }
    let parent = path
        .parent()
        .filter(|p| !p.as_os_str().is_empty())
        .unwrap_or(Path::new("."));
    let mut temporary = tempfile::NamedTempFile::new_in(parent)?;
    temporary.write_all(&encoded)?;
    temporary.write_all(b"\n")?;
    temporary.as_file().sync_all()?;
    temporary.persist(path).map_err(|error| error.error)?;
    Ok(())
}
