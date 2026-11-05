//! UI-independent domain, compiler, persistence, and SQLite runtime.
pub mod compiler;
pub mod database;
pub mod export;
pub mod model;
pub mod project;

#[cfg(feature = "desktop")]
pub mod app;
