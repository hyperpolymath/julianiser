#![forbid(unsafe_code)]
// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// julianiser CLI — Auto-wrap Python/R data pipelines into Julia
//
// Analyses Python and R source files, identifies library calls (pandas,
// numpy, scipy, dplyr, ggplot2, etc.), and generates equivalent Julia
// modules with type annotations, plus benchmark comparison scripts.
//
// Part of the hyperpolymath -iser family. See README.adoc for architecture.

use anyhow::Result;
use clap::{Parser, Subcommand};

mod abi;
mod codegen;
mod manifest;

/// julianiser — Auto-wrap Python/R data pipelines into Julia for 100x speedups.
///
/// Analyses source files declared in julianiser.toml, detects library calls,
/// generates idiomatic Julia replacements, and produces benchmark scripts
/// to measure the speedup.
#[derive(Parser)]
#[command(name = "julianiser", version, about, long_about = None)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

/// Available CLI subcommands.
///
/// Each subcommand corresponds to a stage in the julianiser workflow:
/// init → validate → generate → build → run.
#[derive(Subcommand)]
enum Commands {
    /// Initialise a new julianiser.toml manifest in the current directory.
    Init {
        /// Directory to create the manifest in. Defaults to current directory.
        #[arg(short, long, default_value = ".")]
        path: String,
    },
    /// Validate a julianiser.toml manifest for correctness.
    Validate {
        /// Path to the julianiser.toml manifest file.
        #[arg(short, long, default_value = "julianiser.toml")]
        manifest: String,
    },
    /// Analyse source files and generate Julia replacements + benchmarks.
    Generate {
        /// Path to the julianiser.toml manifest file.
        #[arg(short, long, default_value = "julianiser.toml")]
        manifest: String,
        /// Output directory for generated Julia files.
        #[arg(short, long, default_value = "generated/julianiser")]
        output: String,
    },
    /// Build the generated Julia artifacts.
    Build {
        /// Path to the julianiser.toml manifest file.
        #[arg(short, long, default_value = "julianiser.toml")]
        manifest: String,
        /// Enable release-mode optimisations.
        #[arg(long)]
        release: bool,
    },
    /// Run the generated Julia workload.
    Run {
        /// Path to the julianiser.toml manifest file.
        #[arg(short, long, default_value = "julianiser.toml")]
        manifest: String,
        /// Additional arguments passed to the Julia runtime.
        #[arg(trailing_var_arg = true)]
        args: Vec<String>,
    },
    /// Display summary information about a manifest.
    Info {
        /// Path to the julianiser.toml manifest file.
        #[arg(short, long, default_value = "julianiser.toml")]
        manifest: String,
    },
}

fn main() -> Result<()> {
    let cli = Cli::parse();
    match cli.command {
        Commands::Init { path } => {
            println!("Initialising julianiser manifest in: {}", path);
            manifest::init_manifest(&path)?;
        }
        Commands::Validate { manifest } => {
            let m = manifest::load_manifest(&manifest)?;
            manifest::validate(&m)?;
            println!("Manifest valid: {}", m.project.name);
        }
        Commands::Generate { manifest, output } => {
            let m = manifest::load_manifest(&manifest)?;
            manifest::validate(&m)?;
            codegen::generate_all(&m, &output)?;
            println!("Generated Julia artifacts in: {}", output);
        }
        Commands::Build { manifest, release } => {
            let m = manifest::load_manifest(&manifest)?;
            codegen::build(&m, release)?;
        }
        Commands::Run { manifest, args } => {
            let m = manifest::load_manifest(&manifest)?;
            codegen::run(&m, &args)?;
        }
        Commands::Info { manifest } => {
            let m = manifest::load_manifest(&manifest)?;
            manifest::print_info(&m);
        }
    }
    Ok(())
}
