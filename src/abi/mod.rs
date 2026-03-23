// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// ABI module for julianiser.
//
// Defines the core domain types used throughout the translation pipeline.
// These Rust types mirror what would be formally verified in an Idris2 ABI
// layer (see the hyperpolymath ABI-FFI standard). The Idris2 proofs
// guarantee correctness of layout and invariants; this module provides
// the runtime representations.
//
// Key types:
//   SourceLanguage   — Python or R (the input languages we support)
//   LibraryMapping   — Maps a source library to its Julia equivalent
//   JuliaType        — Represents Julia type annotations for generated code
//   TranslationUnit  — A single file's worth of translation work
//   BenchmarkResult  — Captures timing data from original vs. Julia runs
//   DetectedCall     — A library call found during source analysis

use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fmt;

/// Source languages that julianiser can analyse.
///
/// julianiser targets data-science ecosystems: Python (pandas, numpy, scipy)
/// and R (dplyr, ggplot2, tidyr). Each language has its own parser strategy
/// for detecting library calls.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum SourceLanguage {
    /// Python source files (.py). Parser detects import statements and
    /// qualified calls like `pd.read_csv()`, `np.array()`, etc.
    Python,
    /// R source files (.R, .r). Parser detects library() calls and
    /// function invocations like `read.csv()`, `ggplot()`, etc.
    R,
}

impl fmt::Display for SourceLanguage {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            SourceLanguage::Python => write!(f, "python"),
            SourceLanguage::R => write!(f, "r"),
        }
    }
}

impl SourceLanguage {
    /// Parse a string into a SourceLanguage.
    ///
    /// Accepts "python", "Python", "PYTHON", "r", "R" etc.
    /// Returns None for unsupported languages.
    pub fn from_str_loose(s: &str) -> Option<Self> {
        match s.to_lowercase().as_str() {
            "python" | "py" => Some(SourceLanguage::Python),
            "r" => Some(SourceLanguage::R),
            _ => None,
        }
    }

    /// File extensions associated with this language.
    pub fn extensions(&self) -> &[&str] {
        match self {
            SourceLanguage::Python => &[".py"],
            SourceLanguage::R => &[".R", ".r"],
        }
    }
}

/// Maps a source-language library to its Julia equivalent.
///
/// This is the core translation unit that drives code generation.
/// Each mapping knows how to translate function calls from the
/// source library into idiomatic Julia equivalents.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LibraryMapping {
    /// Source library name as it appears in import/library statements.
    /// e.g. "pandas", "numpy", "scipy.stats", "dplyr", "ggplot2"
    pub from_lib: String,

    /// Target Julia package name.
    /// e.g. "DataFrames", "Statistics", "Plots", "CSV"
    pub to_lib: String,

    /// Source language this mapping applies to.
    pub language: SourceLanguage,

    /// Function-level translation table.
    /// Keys are source function names (e.g. "read_csv"),
    /// values are Julia equivalents (e.g. "CSV.read").
    pub function_map: HashMap<String, String>,
}

impl LibraryMapping {
    /// Create a new library mapping with an empty function map.
    pub fn new(from_lib: &str, to_lib: &str, language: SourceLanguage) -> Self {
        Self {
            from_lib: from_lib.to_string(),
            to_lib: to_lib.to_string(),
            language,
            function_map: HashMap::new(),
        }
    }

    /// Look up the Julia equivalent of a source function name.
    ///
    /// Returns the mapped Julia function call if one is registered,
    /// or None if the function has no explicit mapping (in which case
    /// the codegen will emit a TODO comment).
    pub fn translate_function(&self, source_fn: &str) -> Option<&String> {
        self.function_map.get(source_fn)
    }
}

/// Julia type annotations used in generated code.
///
/// When julianiser generates Julia modules, it adds type annotations
/// to function signatures for performance (Julia's JIT compiles
/// specialised methods per type). These represent the common types
/// encountered in data pipelines.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum JuliaType {
    /// Julia's `Int64` — default integer type.
    Int64,
    /// Julia's `Float64` — default floating-point type.
    Float64,
    /// Julia's `String` type.
    JuliaString,
    /// Julia's `Bool` type.
    Bool,
    /// `Vector{T}` — one-dimensional typed array.
    Vector(Box<JuliaType>),
    /// `Matrix{T}` — two-dimensional typed array.
    Matrix(Box<JuliaType>),
    /// `DataFrame` from DataFrames.jl — the pandas equivalent.
    DataFrame,
    /// `Dict{K, V}` — Julia's dictionary type.
    Dict(Box<JuliaType>, Box<JuliaType>),
    /// `Tuple{T...}` — heterogeneous fixed-length container.
    Tuple(Vec<JuliaType>),
    /// `Nothing` — Julia's unit/void type.
    Nothing,
    /// `Any` — used when type cannot be inferred.
    Any,
    /// A named custom type, e.g. from a user-defined struct.
    Named(String),
}

impl fmt::Display for JuliaType {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            JuliaType::Int64 => write!(f, "Int64"),
            JuliaType::Float64 => write!(f, "Float64"),
            JuliaType::JuliaString => write!(f, "String"),
            JuliaType::Bool => write!(f, "Bool"),
            JuliaType::Vector(inner) => write!(f, "Vector{{{}}}", inner),
            JuliaType::Matrix(inner) => write!(f, "Matrix{{{}}}", inner),
            JuliaType::DataFrame => write!(f, "DataFrame"),
            JuliaType::Dict(k, v) => write!(f, "Dict{{{}, {}}}", k, v),
            JuliaType::Tuple(ts) => {
                let parts: Vec<String> = ts.iter().map(|t| t.to_string()).collect();
                write!(f, "Tuple{{{}}}", parts.join(", "))
            }
            JuliaType::Nothing => write!(f, "Nothing"),
            JuliaType::Any => write!(f, "Any"),
            JuliaType::Named(name) => write!(f, "{}", name),
        }
    }
}

/// A detected library call found during source analysis.
///
/// The parser produces these when scanning Python/R files. Each
/// DetectedCall records enough context for the code generator to
/// produce an equivalent Julia statement.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DetectedCall {
    /// The library that this call belongs to (e.g. "pandas", "numpy").
    pub library: String,

    /// The function name within the library (e.g. "read_csv", "array").
    pub function: String,

    /// Source language the call was detected in.
    pub language: SourceLanguage,

    /// Line number in the source file where the call was found.
    pub line_number: usize,

    /// The raw source line containing the call (for context in comments).
    pub source_line: String,

    /// Detected argument patterns (simplified — just the raw strings).
    pub arguments: Vec<String>,
}

/// A translation unit representing one source file's worth of work.
///
/// After parsing, the pipeline produces one TranslationUnit per source
/// file. The code generator then transforms each unit into a Julia module.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TranslationUnit {
    /// Original source file path (relative to project root).
    pub source_path: String,

    /// Source language of the original file.
    pub language: SourceLanguage,

    /// Output Julia file path (relative to output directory).
    pub output_path: String,

    /// Julia module name generated from the source filename.
    pub module_name: String,

    /// All detected library calls found in this source file.
    pub detected_calls: Vec<DetectedCall>,

    /// Libraries that need to be imported in the Julia output.
    /// Derived from the detected calls and the active mappings.
    pub required_packages: Vec<String>,

    /// Whether the translation is complete (all calls mapped) or
    /// partial (some calls have TODO stubs).
    pub is_complete: bool,
}

impl TranslationUnit {
    /// Create a new empty translation unit for a source file.
    pub fn new(source_path: &str, language: SourceLanguage) -> Self {
        // Derive output path: replace extension with .jl
        let stem = std::path::Path::new(source_path)
            .file_stem()
            .map(|s| s.to_string_lossy().to_string())
            .unwrap_or_else(|| "module".to_string());

        // Julia module names must be PascalCase identifiers.
        let module_name = to_pascal_case(&stem);

        let output_path = format!("{}.jl", stem);

        Self {
            source_path: source_path.to_string(),
            language,
            output_path,
            module_name,
            detected_calls: Vec::new(),
            required_packages: Vec::new(),
            is_complete: true,
        }
    }

    /// Count how many detected calls have known Julia equivalents.
    pub fn mapped_call_count(&self) -> usize {
        // This is set during codegen when mappings are applied.
        // For now, return total — the codegen pass updates is_complete.
        self.detected_calls.len()
    }
}

/// Result of running a benchmark comparison between original and Julia code.
///
/// Produced by the benchmark generator and filled in when the user
/// actually runs the generated benchmark scripts.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BenchmarkResult {
    /// Name of the benchmark (typically the source filename or function).
    pub name: String,

    /// Source language of the original code.
    pub language: SourceLanguage,

    /// Execution time of the original Python/R code, in seconds.
    /// None if not yet measured.
    pub original_time_seconds: Option<f64>,

    /// Execution time of the generated Julia code, in seconds.
    /// None if not yet measured.
    pub julia_time_seconds: Option<f64>,

    /// Speedup factor (original / julia). None if either time is missing.
    pub speedup: Option<f64>,

    /// Number of data points / iterations used in the benchmark.
    pub iterations: u64,

    /// Human-readable notes about the benchmark conditions.
    pub notes: String,
}

impl BenchmarkResult {
    /// Create a new benchmark result placeholder.
    pub fn new(name: &str, language: SourceLanguage) -> Self {
        Self {
            name: name.to_string(),
            language,
            original_time_seconds: None,
            julia_time_seconds: None,
            speedup: None,
            iterations: 1000,
            notes: String::new(),
        }
    }

    /// Compute the speedup ratio from measured times.
    ///
    /// Returns the speedup factor, or None if either time is missing
    /// or the Julia time is zero (would be infinite speedup).
    pub fn compute_speedup(&mut self) -> Option<f64> {
        match (self.original_time_seconds, self.julia_time_seconds) {
            (Some(orig), Some(julia)) if julia > 0.0 => {
                let s = orig / julia;
                self.speedup = Some(s);
                Some(s)
            }
            _ => None,
        }
    }
}

/// Convert a snake_case or kebab-case string to PascalCase.
///
/// Used to derive Julia module names from filenames.
/// e.g. "data_pipeline" → "DataPipeline", "my-analysis" → "MyAnalysis"
fn to_pascal_case(s: &str) -> String {
    s.split(['_', '-', '.'])
        .filter(|part| !part.is_empty())
        .map(|part| {
            let mut chars = part.chars();
            match chars.next() {
                None => String::new(),
                Some(first) => {
                    let upper: String = first.to_uppercase().collect();
                    upper + &chars.collect::<String>()
                }
            }
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_source_language_display() {
        assert_eq!(SourceLanguage::Python.to_string(), "python");
        assert_eq!(SourceLanguage::R.to_string(), "r");
    }

    #[test]
    fn test_source_language_from_str() {
        assert_eq!(
            SourceLanguage::from_str_loose("python"),
            Some(SourceLanguage::Python)
        );
        assert_eq!(SourceLanguage::from_str_loose("R"), Some(SourceLanguage::R));
        assert_eq!(SourceLanguage::from_str_loose("go"), None);
    }

    #[test]
    fn test_julia_type_display() {
        assert_eq!(JuliaType::Float64.to_string(), "Float64");
        assert_eq!(
            JuliaType::Vector(Box::new(JuliaType::Int64)).to_string(),
            "Vector{Int64}"
        );
        assert_eq!(JuliaType::DataFrame.to_string(), "DataFrame");
        assert_eq!(
            JuliaType::Dict(Box::new(JuliaType::JuliaString), Box::new(JuliaType::Any)).to_string(),
            "Dict{String, Any}"
        );
    }

    #[test]
    fn test_pascal_case() {
        assert_eq!(to_pascal_case("data_pipeline"), "DataPipeline");
        assert_eq!(to_pascal_case("my-analysis"), "MyAnalysis");
        assert_eq!(to_pascal_case("simple"), "Simple");
    }

    #[test]
    fn test_library_mapping_translate() {
        let mut mapping = LibraryMapping::new("pandas", "DataFrames", SourceLanguage::Python);
        mapping
            .function_map
            .insert("read_csv".to_string(), "CSV.read".to_string());
        assert_eq!(
            mapping.translate_function("read_csv"),
            Some(&"CSV.read".to_string())
        );
        assert_eq!(mapping.translate_function("unknown_fn"), None);
    }

    #[test]
    fn test_benchmark_result_speedup() {
        let mut result = BenchmarkResult::new("test", SourceLanguage::Python);
        result.original_time_seconds = Some(10.0);
        result.julia_time_seconds = Some(0.1);
        let speedup = result.compute_speedup().unwrap();
        assert!((speedup - 100.0).abs() < 0.001);
    }

    #[test]
    fn test_translation_unit_new() {
        let unit = TranslationUnit::new("data_pipeline.py", SourceLanguage::Python);
        assert_eq!(unit.module_name, "DataPipeline");
        assert_eq!(unit.output_path, "data_pipeline.jl");
        assert_eq!(unit.language, SourceLanguage::Python);
    }
}
