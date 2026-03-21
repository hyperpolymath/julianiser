// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Source code parser for julianiser.
//
// Scans Python and R source files to detect library calls that can be
// translated into Julia equivalents. The parser uses line-by-line regex
// matching rather than full AST parsing — this is sufficient for the
// common patterns in data-science code (import statements, qualified
// method calls, function invocations).
//
// Supported detection patterns:
//   Python: `import X`, `from X import Y`, `X.func()`, `pd.func()`, `np.func()`
//   R:      `library(X)`, `require(X)`, `X::func()`, `func()` from known libs

use crate::abi::{DetectedCall, SourceLanguage, TranslationUnit};
use anyhow::Result;
use std::collections::HashMap;

/// Well-known Python library aliases.
///
/// Data scientists use conventional aliases (pd, np, plt, etc.).
/// This table maps aliases back to canonical library names so we can
/// match calls regardless of which alias the user chose.
fn python_aliases() -> HashMap<&'static str, &'static str> {
    let mut m = HashMap::new();
    m.insert("pd", "pandas");
    m.insert("np", "numpy");
    m.insert("plt", "matplotlib.pyplot");
    m.insert("sns", "seaborn");
    m.insert("sp", "scipy");
    m.insert("stats", "scipy.stats");
    m.insert("sk", "sklearn");
    m.insert("tf", "tensorflow");
    m.insert("torch", "pytorch");
    m
}

/// Well-known Python data-science functions and which library they belong to.
///
/// Used to detect bare function calls that come from `from X import func`.
fn python_known_functions() -> HashMap<&'static str, &'static str> {
    let mut m = HashMap::new();
    // pandas
    m.insert("read_csv", "pandas");
    m.insert("read_excel", "pandas");
    m.insert("read_json", "pandas");
    m.insert("DataFrame", "pandas");
    m.insert("Series", "pandas");
    m.insert("concat", "pandas");
    m.insert("merge", "pandas");
    m.insert("pivot_table", "pandas");
    // numpy
    m.insert("array", "numpy");
    m.insert("zeros", "numpy");
    m.insert("ones", "numpy");
    m.insert("linspace", "numpy");
    m.insert("arange", "numpy");
    m.insert("mean", "numpy");
    m.insert("std", "numpy");
    m.insert("dot", "numpy");
    m.insert("reshape", "numpy");
    m.insert("concatenate", "numpy");
    // scipy
    m.insert("optimize", "scipy");
    m.insert("integrate", "scipy");
    m.insert("interpolate", "scipy");
    m.insert("fft", "scipy");
    m.insert("linalg", "scipy");
    m
}

/// Well-known R library functions and which package they belong to.
///
/// R doesn't use aliases as commonly as Python, but functions from loaded
/// packages are called without qualification. This table maps them back.
fn r_known_functions() -> HashMap<&'static str, &'static str> {
    let mut m = HashMap::new();
    // dplyr / tidyverse
    m.insert("filter", "dplyr");
    m.insert("select", "dplyr");
    m.insert("mutate", "dplyr");
    m.insert("arrange", "dplyr");
    m.insert("group_by", "dplyr");
    m.insert("summarise", "dplyr");
    m.insert("summarize", "dplyr");
    m.insert("left_join", "dplyr");
    m.insert("inner_join", "dplyr");
    m.insert("bind_rows", "dplyr");
    m.insert("bind_cols", "dplyr");
    // tidyr
    m.insert("pivot_longer", "tidyr");
    m.insert("pivot_wider", "tidyr");
    m.insert("gather", "tidyr");
    m.insert("spread", "tidyr");
    m.insert("separate", "tidyr");
    m.insert("unite", "tidyr");
    // ggplot2
    m.insert("ggplot", "ggplot2");
    m.insert("aes", "ggplot2");
    m.insert("geom_point", "ggplot2");
    m.insert("geom_line", "ggplot2");
    m.insert("geom_bar", "ggplot2");
    m.insert("geom_histogram", "ggplot2");
    m.insert("facet_wrap", "ggplot2");
    m.insert("theme", "ggplot2");
    // readr
    m.insert("read_csv", "readr");
    m.insert("write_csv", "readr");
    m.insert("read_tsv", "readr");
    // base R / stats
    m.insert("lm", "stats");
    m.insert("glm", "stats");
    m.insert("t.test", "stats");
    m.insert("cor", "stats");
    m.insert("var", "stats");
    m
}

/// Parse a Python source file and detect translatable library calls.
///
/// Scans line-by-line for:
/// 1. Import statements (`import X`, `import X as Y`, `from X import Y`)
/// 2. Qualified calls (`alias.function(...)` or `module.function(...)`)
/// 3. Bare calls to well-known functions from star imports
///
/// Returns a TranslationUnit populated with all detected calls.
pub fn parse_python_source(source_path: &str, content: &str) -> Result<TranslationUnit> {
    let mut unit = TranslationUnit::new(source_path, SourceLanguage::Python);
    let aliases = python_aliases();
    let known_fns = python_known_functions();

    // Track user-defined aliases from import statements.
    // e.g. `import pandas as pd` adds pd → pandas.
    let mut local_aliases: HashMap<String, String> = HashMap::new();

    // Track imports from `from X import Y` statements.
    let mut from_imports: HashMap<String, String> = HashMap::new();

    for (line_idx, line) in content.lines().enumerate() {
        let trimmed = line.trim();
        let line_number = line_idx + 1;

        // Skip empty lines and comments.
        if trimmed.is_empty() || trimmed.starts_with('#') {
            continue;
        }

        // Detect `import X as Y` or `import X`
        if trimmed.starts_with("import ") && !trimmed.starts_with("import(") {
            let rest = trimmed.strip_prefix("import ").unwrap().trim();
            if let Some((module, alias)) = rest.split_once(" as ") {
                let module = module.trim();
                let alias = alias.trim();
                local_aliases.insert(alias.to_string(), module.to_string());
            } else {
                // `import pandas` — the module name is also the alias.
                let module = rest.split(',').next().unwrap_or(rest).trim();
                local_aliases.insert(module.to_string(), module.to_string());
            }
            continue;
        }

        // Detect `from X import Y, Z`
        if trimmed.starts_with("from ") && trimmed.contains(" import ") {
            if let Some((from_part, import_part)) = trimmed.split_once(" import ") {
                let module = from_part.strip_prefix("from ").unwrap_or("").trim();
                for name in import_part.split(',') {
                    let name = name.trim().split(" as ").next().unwrap_or("").trim();
                    if !name.is_empty() && name != "*" {
                        from_imports.insert(name.to_string(), module.to_string());
                    }
                }
            }
            continue;
        }

        // Detect qualified calls: `alias.function(` or `module.function(`
        // Pattern: word.word( — captures the qualifier and function name.
        detect_python_qualified_calls(
            trimmed,
            line_number,
            line,
            &aliases,
            &local_aliases,
            &mut unit,
        );

        // Detect bare calls to known functions from `from X import func`.
        detect_python_bare_calls(
            trimmed,
            line_number,
            line,
            &known_fns,
            &from_imports,
            &mut unit,
        );
    }

    // Deduplicate required packages from detected calls.
    let packages: Vec<String> = unit
        .detected_calls
        .iter()
        .map(|c| c.library.clone())
        .collect::<std::collections::HashSet<_>>()
        .into_iter()
        .collect();
    unit.required_packages = packages;

    Ok(unit)
}

/// Detect qualified calls like `pd.read_csv(...)` or `numpy.array(...)`.
///
/// Checks the line for `qualifier.function(` patterns and resolves the
/// qualifier through the alias tables.
fn detect_python_qualified_calls(
    trimmed: &str,
    line_number: usize,
    raw_line: &str,
    builtin_aliases: &HashMap<&str, &str>,
    local_aliases: &HashMap<String, String>,
    unit: &mut TranslationUnit,
) {
    // Find all occurrences of `word.word(` in the line.
    let chars: Vec<char> = trimmed.chars().collect();
    let len = chars.len();
    let mut i = 0;

    while i < len {
        // Skip to start of an identifier.
        if !chars[i].is_alphanumeric() && chars[i] != '_' {
            i += 1;
            continue;
        }

        // Read the qualifier (word before the dot).
        let qualifier_start = i;
        while i < len && (chars[i].is_alphanumeric() || chars[i] == '_') {
            i += 1;
        }
        let qualifier = &trimmed[qualifier_start..i];

        // Expect a dot.
        if i >= len || chars[i] != '.' {
            continue;
        }
        i += 1; // skip dot

        // Read the function name.
        let func_start = i;
        while i < len && (chars[i].is_alphanumeric() || chars[i] == '_') {
            i += 1;
        }
        if i == func_start {
            continue;
        }
        let function = &trimmed[func_start..i];

        // Check if followed by `(` (it's a function call).
        if i >= len || chars[i] != '(' {
            continue;
        }

        // Resolve the qualifier to a library name.
        let library = if let Some(lib) = local_aliases.get(qualifier) {
            lib.clone()
        } else if let Some(lib) = builtin_aliases.get(qualifier) {
            lib.to_string()
        } else {
            qualifier.to_string()
        };

        // Extract arguments (simplified: everything between parens).
        let args = extract_parenthesised_args(trimmed, i);

        unit.detected_calls.push(DetectedCall {
            library,
            function: function.to_string(),
            language: SourceLanguage::Python,
            line_number,
            source_line: raw_line.to_string(),
            arguments: args,
        });

        i += 1; // move past the opening paren
    }
}

/// Detect bare function calls that match known library functions.
///
/// When a user writes `from pandas import read_csv` and then calls
/// `read_csv(...)`, we detect that as a pandas call.
fn detect_python_bare_calls(
    trimmed: &str,
    line_number: usize,
    raw_line: &str,
    known_fns: &HashMap<&str, &str>,
    from_imports: &HashMap<String, String>,
    unit: &mut TranslationUnit,
) {
    for (func_name, lib) in known_fns.iter() {
        let pattern = format!("{}(", func_name);
        if trimmed.contains(&pattern) {
            // Check it's not already detected as a qualified call.
            let already_detected = unit.detected_calls.iter().any(|c| {
                c.line_number == line_number && c.function == *func_name
            });
            if already_detected {
                continue;
            }

            // Use from_imports first, then known_fns table.
            let library = from_imports
                .get(*func_name)
                .map(|s| s.as_str())
                .unwrap_or(lib);

            let args = if let Some(pos) = trimmed.find(&pattern) {
                extract_parenthesised_args(trimmed, pos + func_name.len())
            } else {
                vec![]
            };

            unit.detected_calls.push(DetectedCall {
                library: library.to_string(),
                function: func_name.to_string(),
                language: SourceLanguage::Python,
                line_number,
                source_line: raw_line.to_string(),
                arguments: args,
            });
        }
    }
}

/// Parse an R source file and detect translatable library calls.
///
/// Scans line-by-line for:
/// 1. Library/require statements: `library(dplyr)`, `require(ggplot2)`
/// 2. Namespace-qualified calls: `dplyr::filter(...)`, `stats::cor(...)`
/// 3. Bare calls to known functions from loaded libraries
///
/// Returns a TranslationUnit populated with all detected calls.
pub fn parse_r_source(source_path: &str, content: &str) -> Result<TranslationUnit> {
    let mut unit = TranslationUnit::new(source_path, SourceLanguage::R);
    let known_fns = r_known_functions();

    // Track which libraries have been loaded via library() or require().
    let mut loaded_libraries: Vec<String> = Vec::new();

    for (line_idx, line) in content.lines().enumerate() {
        let trimmed = line.trim();
        let line_number = line_idx + 1;

        // Skip empty lines and comments.
        if trimmed.is_empty() || trimmed.starts_with('#') {
            continue;
        }

        // Detect `library(X)` or `require(X)`.
        for loader in &["library(", "require("] {
            if let Some(rest) = trimmed.strip_prefix(loader) {
                if let Some(end) = rest.find(')') {
                    let lib_name = rest[..end].trim().trim_matches('"').trim_matches('\'');
                    if !lib_name.is_empty() {
                        loaded_libraries.push(lib_name.to_string());
                    }
                }
            }
        }

        // Detect namespace-qualified calls: `pkg::func(`
        detect_r_qualified_calls(trimmed, line_number, line, &mut unit);

        // Detect bare calls to known functions.
        detect_r_bare_calls(
            trimmed,
            line_number,
            line,
            &known_fns,
            &loaded_libraries,
            &mut unit,
        );
    }

    // Deduplicate required packages from detected calls.
    let packages: Vec<String> = unit
        .detected_calls
        .iter()
        .map(|c| c.library.clone())
        .collect::<std::collections::HashSet<_>>()
        .into_iter()
        .collect();
    unit.required_packages = packages;

    Ok(unit)
}

/// Detect R namespace-qualified calls like `dplyr::filter(...)`.
fn detect_r_qualified_calls(
    trimmed: &str,
    line_number: usize,
    raw_line: &str,
    unit: &mut TranslationUnit,
) {
    // Look for `word::word(` pattern.
    let mut i = 0;
    let chars: Vec<char> = trimmed.chars().collect();
    let len = chars.len();

    while i < len {
        if !chars[i].is_alphanumeric() && chars[i] != '_' && chars[i] != '.' {
            i += 1;
            continue;
        }

        let pkg_start = i;
        while i < len && (chars[i].is_alphanumeric() || chars[i] == '_' || chars[i] == '.') {
            i += 1;
        }
        let pkg = &trimmed[pkg_start..i];

        // Check for `::`
        if i + 1 < len && chars[i] == ':' && chars[i + 1] == ':' {
            i += 2; // skip ::

            let func_start = i;
            while i < len && (chars[i].is_alphanumeric() || chars[i] == '_' || chars[i] == '.') {
                i += 1;
            }
            let function = &trimmed[func_start..i];

            if i < len && chars[i] == '(' && !function.is_empty() {
                let args = extract_parenthesised_args(trimmed, i);
                unit.detected_calls.push(DetectedCall {
                    library: pkg.to_string(),
                    function: function.to_string(),
                    language: SourceLanguage::R,
                    line_number,
                    source_line: raw_line.to_string(),
                    arguments: args,
                });
            }
        }
    }
}

/// Detect bare R function calls that match known library functions.
fn detect_r_bare_calls(
    trimmed: &str,
    line_number: usize,
    raw_line: &str,
    known_fns: &HashMap<&str, &str>,
    loaded_libraries: &[String],
    unit: &mut TranslationUnit,
) {
    for (func_name, default_lib) in known_fns.iter() {
        let pattern = format!("{}(", func_name);
        if trimmed.contains(&pattern) {
            let already_detected = unit.detected_calls.iter().any(|c| {
                c.line_number == line_number && c.function == *func_name
            });
            if already_detected {
                continue;
            }

            // Use the loaded library that most likely provides this function,
            // falling back to the known_fns default.
            let library = loaded_libraries
                .iter()
                .find(|lib| lib.as_str() == *default_lib)
                .map(|s| s.as_str())
                .unwrap_or(default_lib);

            let args = if let Some(pos) = trimmed.find(&pattern) {
                extract_parenthesised_args(trimmed, pos + func_name.len())
            } else {
                vec![]
            };

            unit.detected_calls.push(DetectedCall {
                library: library.to_string(),
                function: func_name.to_string(),
                language: SourceLanguage::R,
                line_number,
                source_line: raw_line.to_string(),
                arguments: args,
            });
        }
    }
}

/// Extract arguments from a parenthesised expression.
///
/// Given a string and the position of the opening `(`, extracts the
/// comma-separated arguments as raw strings. Handles nested parentheses
/// at one level of depth.
fn extract_parenthesised_args(s: &str, open_paren_pos: usize) -> Vec<String> {
    let chars: Vec<char> = s.chars().collect();
    if open_paren_pos >= chars.len() || chars[open_paren_pos] != '(' {
        return vec![];
    }

    let mut depth = 0;
    let mut args = Vec::new();
    let mut current_arg = String::new();
    let mut i = open_paren_pos;

    while i < chars.len() {
        let ch = chars[i];
        match ch {
            '(' => {
                depth += 1;
                if depth > 1 {
                    current_arg.push(ch);
                }
            }
            ')' => {
                depth -= 1;
                if depth == 0 {
                    let trimmed = current_arg.trim().to_string();
                    if !trimmed.is_empty() {
                        args.push(trimmed);
                    }
                    break;
                }
                current_arg.push(ch);
            }
            ',' if depth == 1 => {
                let trimmed = current_arg.trim().to_string();
                if !trimmed.is_empty() {
                    args.push(trimmed);
                }
                current_arg.clear();
            }
            _ => {
                if depth >= 1 {
                    current_arg.push(ch);
                }
            }
        }
        i += 1;
    }

    args
}

/// Parse a source file based on its declared language.
///
/// Dispatches to the language-specific parser. This is the main entry
/// point used by the codegen pipeline.
pub fn parse_source(source_path: &str, content: &str, language: SourceLanguage) -> Result<TranslationUnit> {
    match language {
        SourceLanguage::Python => parse_python_source(source_path, content),
        SourceLanguage::R => parse_r_source(source_path, content),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_python_import_and_call() {
        let code = r#"
import pandas as pd
import numpy as np

df = pd.read_csv("data.csv")
arr = np.array([1, 2, 3])
"#;
        let unit = parse_python_source("test.py", code).unwrap();
        assert!(unit.detected_calls.len() >= 2);

        let csv_call = unit.detected_calls.iter().find(|c| c.function == "read_csv");
        assert!(csv_call.is_some());
        assert_eq!(csv_call.unwrap().library, "pandas");

        let array_call = unit.detected_calls.iter().find(|c| c.function == "array");
        assert!(array_call.is_some());
        assert_eq!(array_call.unwrap().library, "numpy");
    }

    #[test]
    fn test_parse_python_from_import() {
        let code = r#"
from pandas import read_csv, DataFrame
df = read_csv("data.csv")
"#;
        let unit = parse_python_source("test.py", code).unwrap();
        let csv_call = unit.detected_calls.iter().find(|c| c.function == "read_csv");
        assert!(csv_call.is_some());
        assert_eq!(csv_call.unwrap().library, "pandas");
    }

    #[test]
    fn test_parse_r_library_and_call() {
        let code = r#"
library(dplyr)
library(ggplot2)

df <- filter(data, x > 0)
p <- ggplot(df, aes(x, y))
"#;
        let unit = parse_r_source("test.R", code).unwrap();
        let filter_call = unit.detected_calls.iter().find(|c| c.function == "filter");
        assert!(filter_call.is_some());
        assert_eq!(filter_call.unwrap().library, "dplyr");

        let ggplot_call = unit.detected_calls.iter().find(|c| c.function == "ggplot");
        assert!(ggplot_call.is_some());
        assert_eq!(ggplot_call.unwrap().library, "ggplot2");
    }

    #[test]
    fn test_parse_r_namespace_qualified() {
        let code = r#"
result <- dplyr::filter(df, x > 0)
"#;
        let unit = parse_r_source("test.R", code).unwrap();
        let call = unit.detected_calls.iter().find(|c| c.function == "filter");
        assert!(call.is_some());
        assert_eq!(call.unwrap().library, "dplyr");
    }

    #[test]
    fn test_extract_args() {
        let args = extract_parenthesised_args("func(a, b, c)", 4);
        assert_eq!(args, vec!["a", "b", "c"]);
    }

    #[test]
    fn test_extract_nested_args() {
        let args = extract_parenthesised_args("func(a, inner(b, c), d)", 4);
        assert_eq!(args, vec!["a", "inner(b, c)", "d"]);
    }
}
