// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Manifest parser for julianiser.toml.
//
// The manifest describes a Python/R-to-Julia translation project:
//   [project]       — project metadata (name, version, description)
//   [[sources]]     — source files to translate (path + language)
//   [[mappings]]    — library mappings (e.g. pandas → DataFrames.jl)
//   [julia]         — Julia-specific configuration (version, packages)

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use std::path::Path;

/// Top-level julianiser manifest, parsed from julianiser.toml.
///
/// Every julianiser project requires at minimum a `[project]` section and
/// at least one `[[sources]]` entry describing what code to translate.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Manifest {
    /// Project-level metadata: name, version, description.
    pub project: ProjectConfig,

    /// One or more source files/directories to analyse and translate.
    /// Each entry specifies a filesystem path and the source language
    /// (Python or R).
    #[serde(default)]
    pub sources: Vec<SourceEntry>,

    /// Library-level mappings that tell the codegen engine how to
    /// translate calls from one ecosystem to another.
    /// e.g. pandas → DataFrames.jl, numpy → Julia Base arrays.
    #[serde(default)]
    pub mappings: Vec<MappingEntry>,

    /// Julia runtime and package configuration.
    #[serde(default)]
    pub julia: JuliaConfig,

    // --- Legacy compatibility fields (kept for backward compat) ---
    /// Legacy workload config — will be migrated to `project` in v0.2.
    #[serde(default)]
    pub workload: Option<LegacyWorkloadConfig>,

    /// Legacy data config — will be migrated to `sources` in v0.2.
    #[serde(default)]
    pub data: Option<LegacyDataConfig>,
}

/// Project metadata section: `[project]`.
///
/// Describes the translation project itself — not the source code being
/// translated, but the julianiser project that wraps it.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProjectConfig {
    /// Human-readable project name, used in generated module headers.
    pub name: String,

    /// Semantic version of this julianiser project (not the source code).
    #[serde(default = "default_version")]
    pub version: String,

    /// Optional longer description for generated documentation.
    #[serde(default)]
    pub description: String,
}

/// A single source entry: `[[sources]]`.
///
/// Points to a Python or R file (or directory) that julianiser will
/// analyse for translatable library calls.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SourceEntry {
    /// Filesystem path to the source file or directory.
    /// Relative paths are resolved against the manifest location.
    pub path: String,

    /// Source language: "python" or "r".
    /// Determines which parser strategy is used for call detection.
    pub language: String,
}

/// A library mapping: `[[mappings]]`.
///
/// Tells the code generator how to translate calls from a source-language
/// library into the Julia equivalent. The codegen engine uses these to
/// produce idiomatic Julia code rather than naive transliterations.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MappingEntry {
    /// Source library name, e.g. "pandas", "numpy", "scipy", "dplyr", "ggplot2".
    #[serde(rename = "from-lib")]
    pub from_lib: String,

    /// Target Julia package, e.g. "DataFrames.jl", "Plots.jl", "Statistics".
    #[serde(rename = "to-lib")]
    pub to_lib: String,

    /// Optional specific function-level overrides.
    /// Keys are source function names, values are Julia equivalents.
    #[serde(default)]
    pub overrides: std::collections::HashMap<String, String>,
}

/// Julia runtime configuration: `[julia]`.
///
/// Specifies which Julia version to target and which packages the
/// generated code will depend on.
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct JuliaConfig {
    /// Minimum Julia version required, e.g. "1.10".
    #[serde(default = "default_julia_version")]
    pub version: String,

    /// Julia packages to include in the generated Project.toml.
    /// These are auto-derived from `[[mappings]]` but can be extended.
    #[serde(default)]
    pub packages: Vec<String>,

    /// Extra Julia flags passed to the runtime (e.g. "--threads=auto").
    #[serde(default)]
    pub flags: Vec<String>,
}

// --- Legacy types for backward compatibility ---

/// Legacy workload config from the original scaffold.
/// Kept so that old julianiser.toml files still parse.
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct LegacyWorkloadConfig {
    /// Workload name.
    pub name: String,
    /// Entry point.
    #[serde(default)]
    pub entry: String,
    /// Strategy.
    #[serde(default)]
    pub strategy: String,
}

/// Legacy data config from the original scaffold.
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct LegacyDataConfig {
    /// Input type descriptor.
    #[serde(rename = "input-type", default)]
    pub input_type: String,
    /// Output type descriptor.
    #[serde(rename = "output-type", default)]
    pub output_type: String,
}

// --- Default value helpers ---

/// Default project version when omitted.
fn default_version() -> String {
    "0.1.0".to_string()
}

/// Default Julia version when `[julia]` section is absent or version omitted.
fn default_julia_version() -> String {
    "1.10".to_string()
}

// --- Public API ---

/// Load and deserialise a julianiser manifest from the given path.
///
/// Returns an error if the file cannot be read or the TOML is malformed.
pub fn load_manifest(path: &str) -> Result<Manifest> {
    let content = std::fs::read_to_string(path)
        .with_context(|| format!("Failed to read manifest: {}", path))?;
    parse_manifest(&content)
        .with_context(|| format!("Failed to parse manifest: {}", path))
}

/// Parse a manifest from a TOML string.
///
/// Useful for testing without touching the filesystem.
pub fn parse_manifest(content: &str) -> Result<Manifest> {
    let manifest: Manifest = toml::from_str(content)?;
    Ok(manifest)
}

/// Validate a parsed manifest for semantic correctness.
///
/// Checks that required fields are present and that source languages
/// are supported (python or r).
pub fn validate(manifest: &Manifest) -> Result<()> {
    // Project name is mandatory.
    if manifest.project.name.is_empty() {
        anyhow::bail!("project.name is required and must not be empty");
    }

    // At least one source entry is required for meaningful work.
    if manifest.sources.is_empty() {
        anyhow::bail!("At least one [[sources]] entry is required");
    }

    // Validate each source entry.
    for (index, source) in manifest.sources.iter().enumerate() {
        if source.path.is_empty() {
            anyhow::bail!("sources[{}].path must not be empty", index);
        }
        let lang_lower = source.language.to_lowercase();
        if lang_lower != "python" && lang_lower != "r" {
            anyhow::bail!(
                "sources[{}].language must be 'python' or 'r', got '{}'",
                index,
                source.language
            );
        }
    }

    // Validate mappings if present.
    for (index, mapping) in manifest.mappings.iter().enumerate() {
        if mapping.from_lib.is_empty() {
            anyhow::bail!("mappings[{}].from-lib must not be empty", index);
        }
        if mapping.to_lib.is_empty() {
            anyhow::bail!("mappings[{}].to-lib must not be empty", index);
        }
    }

    Ok(())
}

/// Initialise a new julianiser.toml manifest in the given directory.
///
/// Creates a template manifest with sensible defaults that the user
/// can customise for their specific Python/R-to-Julia translation project.
pub fn init_manifest(path: &str) -> Result<()> {
    let manifest_path = Path::new(path).join("julianiser.toml");
    if manifest_path.exists() {
        anyhow::bail!("julianiser.toml already exists at {}", manifest_path.display());
    }
    let template = r#"# julianiser manifest — Auto-wrap Python/R data pipelines into Julia
# SPDX-License-Identifier: PMPL-1.0-or-later

[project]
name = "my-pipeline"
version = "0.1.0"
description = "Translated data pipeline"

[[sources]]
path = "src/pipeline.py"
language = "python"

[[mappings]]
from-lib = "pandas"
to-lib = "DataFrames.jl"

[[mappings]]
from-lib = "numpy"
to-lib = "Base"

[julia]
version = "1.10"
packages = ["DataFrames", "CSV", "Statistics"]
"#;
    std::fs::write(&manifest_path, template)?;
    println!("Created {}", manifest_path.display());
    Ok(())
}

/// Print summary information about a loaded manifest.
///
/// Displays project metadata, source count, mapping count, and Julia config
/// in a human-readable format suitable for the `info` CLI subcommand.
pub fn print_info(manifest: &Manifest) {
    println!("=== {} v{} ===", manifest.project.name, manifest.project.version);
    if !manifest.project.description.is_empty() {
        println!("  {}", manifest.project.description);
    }
    println!("\nSources ({}):", manifest.sources.len());
    for source in &manifest.sources {
        println!("  {} [{}]", source.path, source.language);
    }
    println!("\nMappings ({}):", manifest.mappings.len());
    for mapping in &manifest.mappings {
        println!("  {} → {}", mapping.from_lib, mapping.to_lib);
    }
    println!("\nJulia:");
    println!("  Version: {}", manifest.julia.version);
    if !manifest.julia.packages.is_empty() {
        println!("  Packages: {}", manifest.julia.packages.join(", "));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Verify that a well-formed manifest parses without error.
    #[test]
    fn test_parse_valid_manifest() {
        let toml = r#"
[project]
name = "test-pipeline"
version = "1.0.0"
description = "A test pipeline"

[[sources]]
path = "analysis.py"
language = "python"

[[mappings]]
from-lib = "pandas"
to-lib = "DataFrames.jl"

[julia]
version = "1.10"
packages = ["DataFrames"]
"#;
        let manifest = parse_manifest(toml).expect("valid manifest should parse");
        assert_eq!(manifest.project.name, "test-pipeline");
        assert_eq!(manifest.sources.len(), 1);
        assert_eq!(manifest.sources[0].language, "python");
        assert_eq!(manifest.mappings.len(), 1);
        assert_eq!(manifest.mappings[0].from_lib, "pandas");
        assert_eq!(manifest.julia.version, "1.10");
    }

    /// Verify that validation rejects empty project name.
    #[test]
    fn test_validate_empty_name_rejected() {
        let toml = r#"
[project]
name = ""

[[sources]]
path = "x.py"
language = "python"
"#;
        let m = parse_manifest(toml).unwrap();
        assert!(validate(&m).is_err());
    }

    /// Verify that validation rejects unsupported languages.
    #[test]
    fn test_validate_bad_language_rejected() {
        let toml = r#"
[project]
name = "test"

[[sources]]
path = "x.go"
language = "go"
"#;
        let m = parse_manifest(toml).unwrap();
        let err = validate(&m).unwrap_err();
        assert!(err.to_string().contains("'python' or 'r'"));
    }
}
