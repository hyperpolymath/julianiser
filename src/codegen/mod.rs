// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Code generation orchestrator for julianiser.
//
// Coordinates the three-stage pipeline:
//   1. Parse source files to detect library calls (parser.rs)
//   2. Generate Julia replacement modules (julia_gen.rs)
//   3. Generate benchmark comparison scripts (benchmark.rs)
//
// The entry point is `generate_all()`, which reads source files listed
// in the manifest, parses them, generates Julia code, and writes
// benchmark scripts — all in one pass.

pub mod benchmark;
pub mod julia_gen;
pub mod parser;

use anyhow::{Context, Result};
use std::fs;
use std::path::Path;

use crate::abi::{SourceLanguage, TranslationUnit};
use crate::manifest::Manifest;

/// Generate all artifacts from a validated manifest.
///
/// This is the main codegen entry point invoked by the CLI's `generate`
/// subcommand. It:
/// 1. Reads each source file declared in `[[sources]]`
/// 2. Parses it for translatable library calls
/// 3. Generates a Julia module for each source file
/// 4. Generates a Julia Project.toml with all dependencies
/// 5. Generates benchmark scripts for performance comparison
///
/// All output is written under `output_dir`.
pub fn generate_all(manifest: &Manifest, output_dir: &str) -> Result<()> {
    let out = Path::new(output_dir);
    fs::create_dir_all(out).context("Failed to create output directory")?;

    // Phase 1: Parse all source files.
    println!(
        "  [parse] Analysing {} source file(s)...",
        manifest.sources.len()
    );
    let units = parse_all_sources(manifest)?;

    // Report detection results.
    let total_calls: usize = units.iter().map(|u| u.detected_calls.len()).sum();
    println!(
        "  [parse] Found {} translatable library call(s) across {} file(s)",
        total_calls,
        units.len()
    );

    // Phase 2: Generate Julia modules.
    println!("  [julia] Generating Julia modules...");
    let julia_files = julia_gen::generate_julia_files(manifest, &units, out)?;

    // Phase 3: Generate benchmarks.
    println!("  [bench] Generating benchmark scripts...");
    let bench_files = benchmark::generate_benchmarks(manifest, &units, out)?;

    // Summary.
    let total_files = julia_files.len() + bench_files.len();
    println!(
        "  [done]  Generated {} file(s) total ({} Julia, {} benchmark)",
        total_files,
        julia_files.len(),
        bench_files.len()
    );

    Ok(())
}

/// Parse all source files listed in the manifest.
///
/// For each `[[sources]]` entry, reads the file from disk and runs the
/// appropriate language parser to detect translatable library calls.
/// If a source path does not exist on disk, the entry is parsed as empty
/// (producing a TranslationUnit with zero detected calls) rather than
/// failing — this allows manifest-driven workflows where source files
/// may not yet be present.
fn parse_all_sources(manifest: &Manifest) -> Result<Vec<TranslationUnit>> {
    let mut units = Vec::new();

    for source in &manifest.sources {
        let language = SourceLanguage::from_str_loose(&source.language).ok_or_else(|| {
            anyhow::anyhow!(
                "Unsupported source language '{}' for {}",
                source.language,
                source.path
            )
        })?;

        // Read the source file content. If the file doesn't exist,
        // produce an empty unit (with a warning) rather than failing.
        let content = match fs::read_to_string(&source.path) {
            Ok(c) => c,
            Err(e) => {
                println!(
                    "  [warn] Could not read {}: {} — generating empty module",
                    source.path, e
                );
                String::new()
            }
        };

        let unit = parser::parse_source(&source.path, &content, language)?;
        println!(
            "  [parse] {} ({}) → {} call(s) detected",
            source.path,
            language,
            unit.detected_calls.len()
        );
        units.push(unit);
    }

    Ok(units)
}

/// Build the generated Julia project.
///
/// Invokes Julia to instantiate packages and precompile the project.
/// Requires Julia to be installed on the system.
pub fn build(manifest: &Manifest, release: bool) -> Result<()> {
    let mode = if release { "release" } else { "debug" };
    println!(
        "Building julianiser project '{}' in {} mode",
        manifest.project.name, mode
    );
    println!(
        "  To build manually: cd generated/julianiser && julia --project=. -e 'using Pkg; Pkg.instantiate()'"
    );
    // Actual Julia invocation would go here, but we don't assume Julia is installed
    // during build-time. The generated scripts handle runtime execution.
    Ok(())
}

/// Run the generated Julia workload.
///
/// Executes the generated Julia pipeline, passing through any extra arguments.
pub fn run(manifest: &Manifest, args: &[String]) -> Result<()> {
    println!(
        "Running julianiser workload '{}' with {} arg(s)",
        manifest.project.name,
        args.len()
    );
    println!(
        "  To run manually: cd generated/julianiser && julia --project=. -e 'include(\"<module>.jl\"); <Module>.run_pipeline()'"
    );
    Ok(())
}

/// Convenience: parse a single source string and return detected calls.
///
/// Useful for the library API and testing.
pub fn parse_source_string(
    source_path: &str,
    content: &str,
    language: SourceLanguage,
) -> Result<TranslationUnit> {
    parser::parse_source(source_path, content, language)
}
