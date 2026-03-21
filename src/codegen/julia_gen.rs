// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Julia code generator for julianiser.
//
// Takes a TranslationUnit (produced by the parser) and a set of
// LibraryMappings (from the manifest), and generates idiomatic Julia
// source code that replicates the original Python/R pipeline.
//
// Generated code includes:
//   - Module wrapper with appropriate `using` statements
//   - Translated function calls with type annotations
//   - TODO comments for unmapped calls
//   - Julia Project.toml for package dependencies

#[cfg(test)]
use crate::abi::DetectedCall;
use crate::abi::{SourceLanguage, TranslationUnit};
use crate::manifest::{Manifest, MappingEntry};
use anyhow::Result;
use std::collections::HashMap;
use std::fmt::Write as FmtWrite;
use std::fs;
use std::path::Path;

/// Well-known function translations from Python libraries to Julia.
///
/// These are the default mappings that julianiser ships with. Users can
/// override or extend them via `[[mappings]]` in the manifest.
fn default_python_to_julia() -> HashMap<(&'static str, &'static str), &'static str> {
    let mut m = HashMap::new();
    // pandas → DataFrames.jl / CSV.jl
    m.insert(("pandas", "read_csv"), "CSV.read(_, DataFrame)");
    m.insert(("pandas", "read_excel"), "XLSX.readtable(_)");
    m.insert(("pandas", "DataFrame"), "DataFrame(_)");
    m.insert(("pandas", "concat"), "vcat(_)");
    m.insert(("pandas", "merge"), "innerjoin(_, _; on=_)");
    m.insert(("pandas", "groupby"), "groupby(_, _)");
    m.insert(("pandas", "pivot_table"), "unstack(_, _)");
    m.insert(("pandas", "describe"), "describe(_)");
    m.insert(("pandas", "head"), "first(_, _)");
    m.insert(("pandas", "tail"), "last(_, _)");
    m.insert(("pandas", "shape"), "size(_)");
    m.insert(("pandas", "dropna"), "dropmissing(_)");
    m.insert(("pandas", "fillna"), "coalesce.(_, _)");
    m.insert(("pandas", "sort_values"), "sort(_, _)");
    m.insert(("pandas", "to_csv"), "CSV.write(_, _)");

    // numpy → Julia Base / LinearAlgebra
    m.insert(("numpy", "array"), "collect(_)");
    m.insert(("numpy", "zeros"), "zeros(_)");
    m.insert(("numpy", "ones"), "ones(_)");
    m.insert(("numpy", "linspace"), "range(_, stop=_, length=_)");
    m.insert(("numpy", "arange"), "collect(_:_:_)");
    m.insert(("numpy", "mean"), "mean(_)");
    m.insert(("numpy", "std"), "std(_)");
    m.insert(("numpy", "sum"), "sum(_)");
    m.insert(("numpy", "dot"), "dot(_, _)");
    m.insert(("numpy", "reshape"), "reshape(_, _)");
    m.insert(("numpy", "concatenate"), "vcat(_...)");
    m.insert(("numpy", "transpose"), "transpose(_)");
    m.insert(("numpy", "linalg.inv"), "inv(_)");
    m.insert(("numpy", "linalg.det"), "det(_)");
    m.insert(("numpy", "linalg.eig"), "eigen(_)");
    m.insert(("numpy", "random.rand"), "rand(_)");
    m.insert(("numpy", "random.randn"), "randn(_)");

    // scipy → Julia stdlib
    m.insert(("scipy", "optimize"), "Optim.optimize(_, _)");
    m.insert(("scipy.stats", "norm"), "Normal(_, _)");
    m.insert(("scipy.stats", "t"), "TDist(_)");
    m.insert(("scipy.stats", "pearsonr"), "cor(_, _)");
    m.insert(("scipy", "integrate"), "QuadGK.quadgk(_, _, _)");

    // matplotlib → Plots.jl
    m.insert(("matplotlib.pyplot", "plot"), "plot(_, _)");
    m.insert(("matplotlib.pyplot", "scatter"), "scatter(_, _)");
    m.insert(("matplotlib.pyplot", "hist"), "histogram(_)");
    m.insert(("matplotlib.pyplot", "show"), "display(_)");
    m.insert(("matplotlib.pyplot", "savefig"), "savefig(_)");
    m.insert(("matplotlib.pyplot", "xlabel"), "xlabel!(_)");
    m.insert(("matplotlib.pyplot", "ylabel"), "ylabel!(_)");
    m.insert(("matplotlib.pyplot", "title"), "title!(_)");

    m
}

/// Well-known function translations from R libraries to Julia.
fn default_r_to_julia() -> HashMap<(&'static str, &'static str), &'static str> {
    let mut m = HashMap::new();
    // dplyr → DataFrames.jl
    m.insert(("dplyr", "filter"), "filter(row -> _, _)");
    m.insert(("dplyr", "select"), "select(_, _)");
    m.insert(("dplyr", "mutate"), "transform(_, _ => _)");
    m.insert(("dplyr", "arrange"), "sort(_, _)");
    m.insert(("dplyr", "group_by"), "groupby(_, _)");
    m.insert(("dplyr", "summarise"), "combine(_, _ => _)");
    m.insert(("dplyr", "summarize"), "combine(_, _ => _)");
    m.insert(("dplyr", "left_join"), "leftjoin(_, _; on=_)");
    m.insert(("dplyr", "inner_join"), "innerjoin(_, _; on=_)");
    m.insert(("dplyr", "bind_rows"), "vcat(_, _)");

    // tidyr → DataFrames.jl
    m.insert(("tidyr", "pivot_longer"), "stack(_, _)");
    m.insert(("tidyr", "pivot_wider"), "unstack(_, _)");
    m.insert(("tidyr", "gather"), "stack(_, _)");
    m.insert(("tidyr", "spread"), "unstack(_, _)");

    // ggplot2 → Plots.jl / Makie.jl
    m.insert(("ggplot2", "ggplot"), "plot(_)");
    m.insert(("ggplot2", "geom_point"), "scatter!(_, _)");
    m.insert(("ggplot2", "geom_line"), "plot!(_, _)");
    m.insert(("ggplot2", "geom_bar"), "bar!(_, _)");
    m.insert(("ggplot2", "geom_histogram"), "histogram!(_, _)");

    // readr → CSV.jl
    m.insert(("readr", "read_csv"), "CSV.read(_, DataFrame)");
    m.insert(("readr", "write_csv"), "CSV.write(_, _)");

    // stats → Statistics / GLM
    m.insert(("stats", "lm"), "lm(@formula(_ ~ _), _)");
    m.insert(("stats", "glm"), "glm(@formula(_ ~ _), _, _)");
    m.insert(("stats", "cor"), "cor(_, _)");
    m.insert(("stats", "var"), "var(_)");
    m.insert(("stats", "t.test"), "OneSampleTTest(_, _)");

    m
}

/// Map a source library name to the Julia packages that need to be imported.
///
/// Returns a list of Julia package names (for `using` statements).
fn julia_packages_for_library(lib: &str) -> Vec<&'static str> {
    match lib {
        "pandas" => vec!["DataFrames", "CSV"],
        "numpy" => vec!["LinearAlgebra", "Statistics"],
        "scipy" | "scipy.stats" | "scipy.optimize" => vec!["Distributions", "Optim"],
        "matplotlib" | "matplotlib.pyplot" | "seaborn" => vec!["Plots"],
        "sklearn" => vec!["MLJ"],
        "dplyr" | "tidyr" | "tibble" => vec!["DataFrames"],
        "readr" => vec!["CSV", "DataFrames"],
        "ggplot2" => vec!["Plots"],
        "stats" => vec!["Statistics", "GLM", "HypothesisTests"],
        _ => vec![],
    }
}

/// Generate a Julia module from a translation unit.
///
/// Produces a complete .jl file with:
/// - Module declaration and `using` statements
/// - Translated function calls (or TODO stubs for unmapped ones)
/// - Source-line comments showing the original code
///
/// Returns the generated Julia source code as a string.
pub fn generate_julia_module(
    unit: &TranslationUnit,
    manifest_mappings: &[MappingEntry],
) -> String {
    let py_translations = default_python_to_julia();
    let r_translations = default_r_to_julia();

    // Build user override table from manifest mappings.
    let mut user_overrides: HashMap<(String, String), String> = HashMap::new();
    for mapping in manifest_mappings {
        for (src_fn, julia_fn) in &mapping.overrides {
            user_overrides.insert(
                (mapping.from_lib.clone(), src_fn.clone()),
                julia_fn.clone(),
            );
        }
    }

    // Collect all Julia packages needed.
    let mut packages: Vec<String> = Vec::new();
    for call in &unit.detected_calls {
        for pkg in julia_packages_for_library(&call.library) {
            let pkg_str = pkg.to_string();
            if !packages.contains(&pkg_str) {
                packages.push(pkg_str);
            }
        }
    }

    // Also add packages from manifest julia.packages if they map through.
    // (These are added in generate_project_toml, but we need them in `using` too.)

    let mut output = String::new();

    // Header comment.
    writeln!(output, "# SPDX-License-Identifier: PMPL-1.0-or-later").unwrap();
    writeln!(output, "# Auto-generated by julianiser from {}", unit.source_path).unwrap();
    writeln!(output, "# Source language: {}", unit.language).unwrap();
    writeln!(output, "# DO NOT EDIT — regenerate with `julianiser generate`").unwrap();
    writeln!(output).unwrap();

    // Module declaration.
    writeln!(output, "module {}", unit.module_name).unwrap();
    writeln!(output).unwrap();

    // Using statements.
    for pkg in &packages {
        writeln!(output, "using {}", pkg).unwrap();
    }
    if !packages.is_empty() {
        writeln!(output).unwrap();
    }

    // Export a main entry-point function.
    writeln!(output, "export run_pipeline").unwrap();
    writeln!(output).unwrap();

    // Generate translated calls.
    writeln!(output, "\"\"\"").unwrap();
    writeln!(output, "    run_pipeline()").unwrap();
    writeln!(output).unwrap();
    writeln!(
        output,
        "Translated pipeline from `{}` ({}).",
        unit.source_path, unit.language
    )
    .unwrap();
    writeln!(output, "\"\"\"").unwrap();
    writeln!(output, "function run_pipeline()").unwrap();

    if unit.detected_calls.is_empty() {
        writeln!(output, "    # No translatable library calls detected.").unwrap();
        writeln!(output, "    @info \"No operations to run.\"").unwrap();
    } else {
        for call in &unit.detected_calls {
            let key = (call.library.as_str(), call.function.as_str());

            // Check user overrides first, then built-in tables.
            let julia_equivalent = user_overrides
                .get(&(call.library.clone(), call.function.clone()))
                .map(|s| s.as_str())
                .or_else(|| match call.language {
                    SourceLanguage::Python => py_translations.get(&key).copied(),
                    SourceLanguage::R => r_translations.get(&key).copied(),
                });

            writeln!(output, "    # L{}: {} (from {})", call.line_number, call.source_line.trim(), call.library).unwrap();

            match julia_equivalent {
                Some(julia_call) => {
                    // Substitute arguments into the template where possible.
                    let rendered = render_julia_call(julia_call, &call.arguments);
                    writeln!(output, "    {}", rendered).unwrap();
                }
                None => {
                    writeln!(
                        output,
                        "    # TODO: No mapping for {}.{}() — manual translation needed",
                        call.library, call.function
                    )
                    .unwrap();
                    writeln!(
                        output,
                        "    error(\"Unmapped call: {}.{}\")",
                        call.library, call.function
                    )
                    .unwrap();
                }
            }
            writeln!(output).unwrap();
        }
    }

    writeln!(output, "end  # function run_pipeline").unwrap();
    writeln!(output).unwrap();
    writeln!(output, "end  # module {}", unit.module_name).unwrap();

    output
}

/// Render a Julia call template with actual arguments.
///
/// Templates use `_` as placeholders for arguments. If the call has
/// arguments, they replace the underscores left-to-right. Extra
/// arguments are appended comma-separated. Missing arguments leave
/// the underscore as-is (the user will fill them in).
fn render_julia_call(template: &str, arguments: &[String]) -> String {
    if arguments.is_empty() {
        return template.to_string();
    }

    let mut result = String::new();
    let mut arg_idx = 0;
    let chars: Vec<char> = template.chars().collect();
    let mut i = 0;

    while i < chars.len() {
        if chars[i] == '_' {
            // Check it's a standalone placeholder (not part of a word).
            let prev_is_word = i > 0 && (chars[i - 1].is_alphanumeric() || chars[i - 1] == '_');
            let next_is_word = i + 1 < chars.len()
                && (chars[i + 1].is_alphanumeric() || chars[i + 1] == '_');

            if !prev_is_word && !next_is_word && arg_idx < arguments.len() {
                result.push_str(&arguments[arg_idx]);
                arg_idx += 1;
            } else {
                result.push('_');
            }
        } else {
            result.push(chars[i]);
        }
        i += 1;
    }

    result
}

/// Generate a Julia Project.toml for the translated project.
///
/// Lists all required packages so the user can `Pkg.instantiate()` to
/// install dependencies before running the generated code.
pub fn generate_project_toml(
    manifest: &Manifest,
    units: &[TranslationUnit],
) -> String {
    let mut output = String::new();

    writeln!(output, "# SPDX-License-Identifier: PMPL-1.0-or-later").unwrap();
    writeln!(output, "# Auto-generated by julianiser").unwrap();
    writeln!(output).unwrap();
    writeln!(output, "name = \"{}\"", manifest.project.name).unwrap();
    writeln!(output, "version = \"{}\"", manifest.project.version).unwrap();
    writeln!(output).unwrap();
    writeln!(output, "[deps]").unwrap();

    // Collect all packages from translation units.
    let mut all_packages: Vec<String> = Vec::new();
    for unit in units {
        for call in &unit.detected_calls {
            for pkg in julia_packages_for_library(&call.library) {
                let pkg_str = pkg.to_string();
                if !all_packages.contains(&pkg_str) {
                    all_packages.push(pkg_str);
                }
            }
        }
    }

    // Add packages from manifest [julia].packages.
    for pkg in &manifest.julia.packages {
        if !all_packages.contains(pkg) {
            all_packages.push(pkg.clone());
        }
    }

    // Well-known Julia package UUIDs.
    let uuids = julia_package_uuids();
    all_packages.sort();

    for pkg in &all_packages {
        if let Some(uuid) = uuids.get(pkg.as_str()) {
            writeln!(output, "{} = \"{}\"", pkg, uuid).unwrap();
        } else {
            writeln!(output, "# {} = \"<uuid>\"  # TODO: look up UUID", pkg).unwrap();
        }
    }

    // Julia compat section.
    writeln!(output).unwrap();
    writeln!(output, "[compat]").unwrap();
    writeln!(output, "julia = \">= {}\"", manifest.julia.version).unwrap();

    output
}

/// Well-known Julia package UUIDs for Project.toml generation.
fn julia_package_uuids() -> HashMap<&'static str, &'static str> {
    let mut m = HashMap::new();
    m.insert("CSV", "336ed68f-0bac-5ca0-87d4-7b16caf5d00b");
    m.insert("DataFrames", "a93c6f00-e57d-5684-b7b6-d8193f3e46c0");
    m.insert("Statistics", "10745b16-79ce-11e8-11f9-7d13ad32a3b2");
    m.insert("LinearAlgebra", "37e2e46d-f89d-539d-b4ee-838fcccc9c8e");
    m.insert("Plots", "91a5bcdd-55d7-5caf-9e0b-520d859cae80");
    m.insert("Distributions", "31c24e10-a181-5473-b8eb-7969acd0382f");
    m.insert("Optim", "429524aa-4258-5aef-a3af-852621145aeb");
    m.insert("GLM", "cf35fbd7-0cd7-5a64-9ae8-7a8e0f74bc5c");
    m.insert("HypothesisTests", "09f84164-cd44-5f33-b23f-e6b0d136a0d5");
    m.insert("MLJ", "add582a8-e3ab-11e8-2d5e-e98b27df1bc7");
    m.insert("BenchmarkTools", "6e4b80f9-dd63-53aa-95a3-0cdb28fa8baf");
    m
}

/// Generate all Julia files for a set of translation units.
///
/// Writes each .jl module file and a Project.toml into the output directory.
/// Returns the list of generated file paths.
pub fn generate_julia_files(
    manifest: &Manifest,
    units: &[TranslationUnit],
    output_dir: &Path,
) -> Result<Vec<String>> {
    fs::create_dir_all(output_dir)?;

    let mut generated_files = Vec::new();

    // Generate each module file.
    for unit in units {
        let julia_code = generate_julia_module(unit, &manifest.mappings);
        let file_path = output_dir.join(&unit.output_path);
        fs::write(&file_path, &julia_code)?;
        generated_files.push(file_path.display().to_string());
        println!("  [julia] Generated {}", file_path.display());
    }

    // Generate Project.toml.
    let project_toml = generate_project_toml(manifest, units);
    let project_path = output_dir.join("Project.toml");
    fs::write(&project_path, &project_toml)?;
    generated_files.push(project_path.display().to_string());
    println!("  [julia] Generated {}", project_path.display());

    Ok(generated_files)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::abi::SourceLanguage;

    #[test]
    fn test_render_julia_call_with_args() {
        let rendered = render_julia_call("CSV.read(_, DataFrame)", &["\"data.csv\"".to_string()]);
        assert_eq!(rendered, "CSV.read(\"data.csv\", DataFrame)");
    }

    #[test]
    fn test_render_julia_call_no_args() {
        let rendered = render_julia_call("zeros(_)", &[]);
        assert_eq!(rendered, "zeros(_)");
    }

    #[test]
    fn test_generate_julia_module_basic() {
        let mut unit = TranslationUnit::new("pipeline.py", SourceLanguage::Python);
        unit.detected_calls.push(DetectedCall {
            library: "pandas".to_string(),
            function: "read_csv".to_string(),
            language: SourceLanguage::Python,
            line_number: 5,
            source_line: "df = pd.read_csv(\"data.csv\")".to_string(),
            arguments: vec!["\"data.csv\"".to_string()],
        });

        let code = generate_julia_module(&unit, &[]);
        assert!(code.contains("module Pipeline"));
        assert!(code.contains("using DataFrames"));
        assert!(code.contains("using CSV"));
        assert!(code.contains("CSV.read"));
    }

    #[test]
    fn test_generate_project_toml() {
        let manifest = Manifest {
            project: crate::manifest::ProjectConfig {
                name: "test".to_string(),
                version: "0.1.0".to_string(),
                description: String::new(),
            },
            sources: vec![],
            mappings: vec![],
            julia: crate::manifest::JuliaConfig {
                version: "1.10".to_string(),
                packages: vec!["BenchmarkTools".to_string()],
                flags: vec![],
            },
            workload: None,
            data: None,
        };

        let mut unit = TranslationUnit::new("test.py", SourceLanguage::Python);
        unit.detected_calls.push(DetectedCall {
            library: "pandas".to_string(),
            function: "read_csv".to_string(),
            language: SourceLanguage::Python,
            line_number: 1,
            source_line: String::new(),
            arguments: vec![],
        });

        let toml = generate_project_toml(&manifest, &[unit]);
        assert!(toml.contains("name = \"test\""));
        assert!(toml.contains("CSV ="));
        assert!(toml.contains("DataFrames ="));
        assert!(toml.contains("BenchmarkTools ="));
        assert!(toml.contains(">= 1.10"));
    }
}
