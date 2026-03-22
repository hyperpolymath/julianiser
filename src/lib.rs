#![forbid(unsafe_code)]
// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// julianiser library API.
//
// Public interface for programmatic use of julianiser. The main entry
// points are:
//   - `generate()` — load manifest, parse sources, generate Julia code
//   - `load_manifest()` / `validate()` — manifest operations
//   - `parse_source_string()` — parse a single source for detected calls
//   - ABI types — `SourceLanguage`, `TranslationUnit`, `BenchmarkResult`, etc.

pub mod abi;
pub mod codegen;
pub mod manifest;

pub use abi::{
    BenchmarkResult, DetectedCall, JuliaType, LibraryMapping, SourceLanguage, TranslationUnit,
};
pub use codegen::parse_source_string;
pub use manifest::{load_manifest, parse_manifest, validate, Manifest};

/// Convenience: load, validate, and generate all artifacts from a manifest file.
///
/// This is the simplest way to use julianiser as a library:
/// ```no_run
/// julianiser::generate("julianiser.toml", "generated/julianiser").unwrap();
/// ```
pub fn generate(manifest_path: &str, output_dir: &str) -> anyhow::Result<()> {
    let m = load_manifest(manifest_path)?;
    validate(&m)?;
    codegen::generate_all(&m, output_dir)?;
    Ok(())
}
