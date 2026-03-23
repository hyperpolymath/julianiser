// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Integration tests for julianiser.
//
// These tests exercise the full pipeline from manifest parsing through
// source analysis to Julia code generation, verifying that the pieces
// work together correctly.

use julianiser::abi::{BenchmarkResult, JuliaType, SourceLanguage, TranslationUnit};
use julianiser::codegen::julia_gen;
use julianiser::manifest;
use tempfile::TempDir;

/// Create a complete test manifest as a TOML string.
fn sample_manifest_toml() -> &'static str {
    r#"
[project]
name = "integration-test"
version = "1.0.0"
description = "Integration test pipeline"

[[sources]]
path = "pipeline.py"
language = "python"

[[sources]]
path = "analysis.R"
language = "r"

[[mappings]]
from-lib = "pandas"
to-lib = "DataFrames.jl"

[[mappings]]
from-lib = "numpy"
to-lib = "Base"

[[mappings]]
from-lib = "dplyr"
to-lib = "DataFrames.jl"

[julia]
version = "1.10"
packages = ["DataFrames", "CSV", "Statistics"]
"#
}

/// Sample Python source code with common data-science patterns.
fn sample_python_code() -> &'static str {
    r#"
import pandas as pd
import numpy as np

df = pd.read_csv("data.csv")
filtered = df.dropna()
arr = np.array([1, 2, 3, 4, 5])
avg = np.mean(arr)
std = np.std(arr)
result = pd.DataFrame({"col": arr})
result.to_csv("output.csv")
"#
}

/// Sample R source code with common tidyverse patterns.
fn sample_r_code() -> &'static str {
    r#"
library(dplyr)
library(ggplot2)

data <- read_csv("data.csv")
filtered <- filter(data, value > 0)
grouped <- group_by(filtered, category)
summary <- summarise(grouped, mean_val = mean(value))
result <- arrange(summary, desc(mean_val))
p <- ggplot(filtered, aes(x = category, y = value))
"#
}

// =========================================================================
// Test 1: Full manifest round-trip (parse → validate → inspect)
// =========================================================================

#[test]
fn test_manifest_round_trip() {
    let manifest = manifest::parse_manifest(sample_manifest_toml())
        .expect("Manifest should parse successfully");

    // Validate passes.
    manifest::validate(&manifest).expect("Manifest should validate");

    // Project fields are correct.
    assert_eq!(manifest.project.name, "integration-test");
    assert_eq!(manifest.project.version, "1.0.0");

    // Sources are parsed.
    assert_eq!(manifest.sources.len(), 2);
    assert_eq!(manifest.sources[0].language, "python");
    assert_eq!(manifest.sources[1].language, "r");

    // Mappings are parsed.
    assert_eq!(manifest.mappings.len(), 3);
    assert_eq!(manifest.mappings[0].from_lib, "pandas");
    assert_eq!(manifest.mappings[0].to_lib, "DataFrames.jl");

    // Julia config is parsed.
    assert_eq!(manifest.julia.version, "1.10");
    assert_eq!(manifest.julia.packages.len(), 3);
    assert!(manifest.julia.packages.contains(&"DataFrames".to_string()));
}

// =========================================================================
// Test 2: Python source parsing detects all expected library calls
// =========================================================================

#[test]
fn test_python_source_parsing_detects_calls() {
    let unit = julianiser::parse_source_string(
        "pipeline.py",
        sample_python_code(),
        SourceLanguage::Python,
    )
    .expect("Python parsing should succeed");

    // Should detect multiple pandas and numpy calls.
    assert!(
        unit.detected_calls.len() >= 5,
        "Expected at least 5 detected calls, got {}",
        unit.detected_calls.len()
    );

    // Verify specific calls are detected.
    let libraries: Vec<&str> = unit
        .detected_calls
        .iter()
        .map(|c| c.library.as_str())
        .collect();
    assert!(libraries.contains(&"pandas"), "Should detect pandas calls");
    assert!(libraries.contains(&"numpy"), "Should detect numpy calls");

    // Verify function names.
    let functions: Vec<&str> = unit
        .detected_calls
        .iter()
        .map(|c| c.function.as_str())
        .collect();
    assert!(functions.contains(&"read_csv"), "Should detect read_csv");
    assert!(functions.contains(&"array"), "Should detect array");
    assert!(functions.contains(&"mean"), "Should detect mean");

    // Module name is derived from filename.
    assert_eq!(unit.module_name, "Pipeline");
    assert_eq!(unit.output_path, "pipeline.jl");
}

// =========================================================================
// Test 3: R source parsing detects all expected library calls
// =========================================================================

#[test]
fn test_r_source_parsing_detects_calls() {
    let unit = julianiser::parse_source_string("analysis.R", sample_r_code(), SourceLanguage::R)
        .expect("R parsing should succeed");

    // Should detect dplyr and ggplot2 calls.
    assert!(
        unit.detected_calls.len() >= 4,
        "Expected at least 4 detected calls, got {}",
        unit.detected_calls.len()
    );

    let libraries: Vec<&str> = unit
        .detected_calls
        .iter()
        .map(|c| c.library.as_str())
        .collect();
    assert!(libraries.contains(&"dplyr"), "Should detect dplyr calls");
    assert!(
        libraries.contains(&"ggplot2"),
        "Should detect ggplot2 calls"
    );

    let functions: Vec<&str> = unit
        .detected_calls
        .iter()
        .map(|c| c.function.as_str())
        .collect();
    assert!(functions.contains(&"filter"), "Should detect filter");
    assert!(functions.contains(&"group_by"), "Should detect group_by");
    assert!(functions.contains(&"ggplot"), "Should detect ggplot");

    assert_eq!(unit.module_name, "Analysis");
}

// =========================================================================
// Test 4: Julia code generation produces valid module structure
// =========================================================================

#[test]
fn test_julia_codegen_produces_valid_module() {
    let unit = julianiser::parse_source_string(
        "pipeline.py",
        sample_python_code(),
        SourceLanguage::Python,
    )
    .expect("Parsing should succeed");

    let manifest = manifest::parse_manifest(sample_manifest_toml()).unwrap();
    let julia_code = julia_gen::generate_julia_module(&unit, &manifest.mappings);

    // Must contain module declaration.
    assert!(
        julia_code.contains("module Pipeline"),
        "Generated code must declare module Pipeline"
    );

    // Must contain `using` statements for detected libraries.
    assert!(
        julia_code.contains("using DataFrames"),
        "Must import DataFrames"
    );
    assert!(julia_code.contains("using CSV"), "Must import CSV");

    // Must contain run_pipeline function.
    assert!(
        julia_code.contains("function run_pipeline()"),
        "Must contain run_pipeline function"
    );

    // Must contain translated calls (CSV.read for pd.read_csv).
    assert!(
        julia_code.contains("CSV.read"),
        "Should translate pd.read_csv to CSV.read"
    );

    // Must end with module close.
    assert!(
        julia_code.contains("end  # module Pipeline"),
        "Must close module"
    );

    // Must have SPDX header.
    assert!(
        julia_code.contains("SPDX-License-Identifier: PMPL-1.0-or-later"),
        "Must have SPDX header"
    );
}

// =========================================================================
// Test 5: Full generation pipeline writes files to disk
// =========================================================================

#[test]
fn test_full_generation_writes_files() {
    let tmp = TempDir::new().expect("Should create temp dir");
    let manifest_dir = tmp.path();

    // Write manifest.
    let manifest_path = manifest_dir.join("julianiser.toml");
    std::fs::write(&manifest_path, sample_manifest_toml()).unwrap();

    // Write Python source.
    let py_path = manifest_dir.join("pipeline.py");
    std::fs::write(&py_path, sample_python_code()).unwrap();

    // Write R source.
    let r_path = manifest_dir.join("analysis.R");
    std::fs::write(&r_path, sample_r_code()).unwrap();

    // Run the full pipeline.
    let output_dir = manifest_dir.join("output");

    // Load and parse manifest.
    let manifest =
        manifest::load_manifest(manifest_path.to_str().unwrap()).expect("Should load manifest");
    manifest::validate(&manifest).expect("Should validate");

    // Parse sources (reading from the temp directory).
    let py_content = std::fs::read_to_string(&py_path).unwrap();
    let r_content = std::fs::read_to_string(&r_path).unwrap();

    let py_unit =
        julianiser::parse_source_string("pipeline.py", &py_content, SourceLanguage::Python)
            .unwrap();
    let r_unit =
        julianiser::parse_source_string("analysis.R", &r_content, SourceLanguage::R).unwrap();

    let units = vec![py_unit, r_unit];

    // Generate Julia files.
    let generated = julia_gen::generate_julia_files(&manifest, &units, &output_dir)
        .expect("Should generate Julia files");

    // Verify files were created.
    assert!(
        output_dir.join("pipeline.jl").exists(),
        "pipeline.jl must exist"
    );
    assert!(
        output_dir.join("analysis.jl").exists(),
        "analysis.jl must exist"
    );
    assert!(
        output_dir.join("Project.toml").exists(),
        "Project.toml must exist"
    );
    assert!(generated.len() >= 3, "At least 3 files generated");

    // Verify Project.toml content.
    let project_toml = std::fs::read_to_string(output_dir.join("Project.toml")).unwrap();
    assert!(project_toml.contains("name = \"integration-test\""));
    assert!(project_toml.contains("[deps]"));
    assert!(project_toml.contains("DataFrames"));
}

// =========================================================================
// Test 6: Benchmark generation produces runnable scripts
// =========================================================================

#[test]
fn test_benchmark_generation() {
    let tmp = TempDir::new().expect("Should create temp dir");
    let output_dir = tmp.path().join("output");

    let manifest = manifest::parse_manifest(sample_manifest_toml()).unwrap();

    let py_unit = julianiser::parse_source_string(
        "pipeline.py",
        sample_python_code(),
        SourceLanguage::Python,
    )
    .unwrap();
    let r_unit =
        julianiser::parse_source_string("analysis.R", sample_r_code(), SourceLanguage::R).unwrap();
    let units = vec![py_unit, r_unit];

    let bench_files =
        julianiser::codegen::benchmark::generate_benchmarks(&manifest, &units, &output_dir)
            .expect("Benchmark generation should succeed");

    // Should produce 3 files: benchmark.jl, benchmark_runner.sh, results.toml.
    assert_eq!(bench_files.len(), 3, "Should generate 3 benchmark files");

    let bench_dir = output_dir.join("benchmarks");
    assert!(
        bench_dir.join("benchmark.jl").exists(),
        "benchmark.jl must exist"
    );
    assert!(
        bench_dir.join("benchmark_runner.sh").exists(),
        "benchmark_runner.sh must exist"
    );
    assert!(
        bench_dir.join("results.toml").exists(),
        "results.toml must exist"
    );

    // Verify benchmark.jl content.
    let bench_jl = std::fs::read_to_string(bench_dir.join("benchmark.jl")).unwrap();
    assert!(
        bench_jl.contains("using BenchmarkTools"),
        "Must use BenchmarkTools"
    );
    assert!(
        bench_jl.contains("@benchmark"),
        "Must contain @benchmark macro"
    );
    assert!(
        bench_jl.contains("Pipeline"),
        "Must reference Pipeline module"
    );
    assert!(
        bench_jl.contains("Analysis"),
        "Must reference Analysis module"
    );

    // Verify runner script has correct shebang and references both languages.
    let runner = std::fs::read_to_string(bench_dir.join("benchmark_runner.sh")).unwrap();
    assert!(
        runner.starts_with("#!/usr/bin/env bash"),
        "Must have bash shebang"
    );
    assert!(runner.contains("python3"), "Must reference Python runner");
    assert!(runner.contains("Rscript"), "Must reference R runner");
    assert!(runner.contains("julia"), "Must reference Julia runner");

    // Verify results template.
    let results = std::fs::read_to_string(bench_dir.join("results.toml")).unwrap();
    assert!(
        results.contains("[[benchmarks]]"),
        "Must have benchmark entries"
    );
    assert!(
        results.contains("original_time_seconds"),
        "Must have timing fields"
    );
}

// =========================================================================
// Test 7: ABI types round-trip through serde correctly
// =========================================================================

#[test]
fn test_abi_types_serde_round_trip() {
    // SourceLanguage serialises to lowercase strings.
    let py = SourceLanguage::Python;
    let serialised = serde_json::to_string(&py).unwrap();
    assert_eq!(serialised, "\"python\"");
    let deserialised: SourceLanguage = serde_json::from_str(&serialised).unwrap();
    assert_eq!(deserialised, SourceLanguage::Python);

    // JuliaType Display.
    let vec_type = JuliaType::Vector(Box::new(JuliaType::Float64));
    assert_eq!(vec_type.to_string(), "Vector{Float64}");

    let dict_type = JuliaType::Dict(
        Box::new(JuliaType::JuliaString),
        Box::new(JuliaType::Vector(Box::new(JuliaType::Int64))),
    );
    assert_eq!(dict_type.to_string(), "Dict{String, Vector{Int64}}");

    // BenchmarkResult compute_speedup.
    let mut bench = BenchmarkResult::new("test", SourceLanguage::Python);
    bench.original_time_seconds = Some(5.0);
    bench.julia_time_seconds = Some(0.05);
    let speedup = bench.compute_speedup().unwrap();
    assert!(
        (speedup - 100.0).abs() < 0.01,
        "Expected 100x speedup, got {}",
        speedup
    );

    // TranslationUnit derives module name correctly.
    let unit = TranslationUnit::new("my_data_pipeline.py", SourceLanguage::Python);
    assert_eq!(unit.module_name, "MyDataPipeline");
    assert_eq!(unit.output_path, "my_data_pipeline.jl");
}

// =========================================================================
// Test 8: Manifest validation catches invalid inputs
// =========================================================================

#[test]
fn test_manifest_validation_errors() {
    // Missing sources.
    let no_sources = r#"
[project]
name = "test"
"#;
    let m = manifest::parse_manifest(no_sources).unwrap();
    let err = manifest::validate(&m).unwrap_err();
    assert!(
        err.to_string().contains("sources"),
        "Should reject manifest with no sources: {}",
        err
    );

    // Invalid language.
    let bad_lang = r#"
[project]
name = "test"

[[sources]]
path = "main.go"
language = "go"
"#;
    let m = manifest::parse_manifest(bad_lang).unwrap();
    let err = manifest::validate(&m).unwrap_err();
    assert!(
        err.to_string().contains("'python' or 'r'"),
        "Should reject unsupported language: {}",
        err
    );

    // Empty project name.
    let empty_name = r#"
[project]
name = ""

[[sources]]
path = "x.py"
language = "python"
"#;
    let m = manifest::parse_manifest(empty_name).unwrap();
    let err = manifest::validate(&m).unwrap_err();
    assert!(
        err.to_string().contains("name"),
        "Should reject empty project name: {}",
        err
    );
}
