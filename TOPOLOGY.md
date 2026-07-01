# SPDX-License-Identifier: CC-BY-SA-4.0
# Julianiser — Repository Topology

## Purpose

Julianiser analyses Python and R data science code, identifies known
pandas/numpy/scipy/dplyr/ggplot2-style calls, and generates equivalent Julia
modules via the Rust codegen pipeline (`src/codegen/`). Julia's LLVM JIT is
well-documented to deliver large speedups on this class of workload; julianiser
generates benchmark scaffolding so users can measure that for their own
pipeline, but does not itself measure or claim a speedup number today.

**Honesty note (see README.md for full detail):** the Idris2 ABI
(`src/interface/abi/`) and Zig FFI (`src/interface/ffi/`) below are
scaffolding — source files exist, but the Zig implementation is
TODO-stubbed and the Rust CLI never links or calls into it. The
operational translation pipeline today is the Rust codegen
(`src/codegen/parser.rs` + `src/codegen/julia_gen.rs`), invoked directly
by `src/main.rs`.

## Module Map

```
julianiser/
├── src/                            # Rust CLI + orchestration
│   ├── main.rs                     # CLI entry point (init, validate, generate, build, run, info)
│   ├── lib.rs                      # Library API
│   ├── manifest/mod.rs             # julianiser.toml parser and validator
│   ├── codegen/mod.rs              # Julia code generation engine
│   ├── abi/mod.rs                  # Rust-side domain types (not linked to Idris2 below)
│   └── interface/                  # Interface Seam SCAFFOLDING (planned, not wired — see Data Flow)
│       ├── abi/                    # Idris2 ABI (The Spec) — source only, not built by cargo
│       │   ├── Types.idr           # SourceLanguage, DataFrameOp, ArrayPattern, JuliaType, EquivalenceWitness
│       │   ├── Layout.idr          # AST node memory layout with alignment proofs
│       │   └── Foreign.idr         # FFI declarations for Python/R parsing and Julia codegen
│       ├── ffi/                    # Zig FFI (The Bridge) — TODO-stubbed, never called by the Rust CLI
│       │   ├── build.zig           # Zig build config (shared + static lib)
│       │   ├── src/main.zig        # FFI stub (parse/codegen/benchmark are placeholders)
│       │   └── test/               # Zig-side unit tests of the stub behaviour
│       └── generated/abi/          # Auto-generated C headers from Idris2 (placeholder dir)
├── verification/                   # Proofs, benchmarks, fuzzing, safety cases
│   ├── benchmarks/                 # Python/R vs Julia performance comparisons
│   ├── proofs/                     # Formal verification artifacts
│   └── tests/                      # Property-based and integration tests
├── examples/                       # Example julianiser.toml manifests and source files
├── container/                      # Stapeln container ecosystem (Chainguard base)
├── features/                       # BoJ-server cartridge, panic-attacker, SSG
├── docs/                           # Architecture, theory, governance, legal
│   ├── architecture/               # Threat model, topology diagrams
│   ├── developer/                  # ABI-FFI guide
│   ├── governance/                 # TSDM, maintenance, planning
│   └── theory/                     # Domain theory (Julia compilation model, AST translation)
└── .machine_readable/              # All machine-readable metadata (6a2, policies, contractiles)
    ├── 6a2/                        # STATE, META, ECOSYSTEM, AGENTIC, NEUROSYM, PLAYBOOK
    ├── anchors/                    # Semantic authority anchor
    ├── policies/                   # Maintenance axes and checklists
    ├── contractiles/               # k9, must, trust, dust, lust
    └── integrations/               # proven, verisimdb, vexometer, feedback-o-tron
```

## Data Flow (operational today)

```
julianiser.toml ──→ Manifest Parser ──→ Source Parser (line-based Python/R scan)
                     (src/manifest/)      (src/codegen/parser.rs)
                                              │
                                              ▼
                                     Detected library calls
                                     (import aliases resolved;
                                      local-variable calls skipped)
                                              │
                                              ▼
                                     Julia Codegen (template lookup per call)
                                     (src/codegen/julia_gen.rs)
                                              │
                                              ▼
                                     Benchmark scaffold generator
                                     (src/codegen/benchmark.rs — emits scripts
                                      for the user to run and record timings)
```

## Data Flow (planned, not yet wired)

The Idris2 ABI (`src/interface/abi/`) and Zig FFI (`src/interface/ffi/`)
are intended to eventually sit between source parsing and Julia codegen
as a formally-verified, compiled bridge. Today they are source-only
scaffolding: the Idris2 proofs are not built or checked by `cargo
build`/`cargo test`, and the Zig implementation's exported functions
are TODO stubs that the Rust CLI never calls.

## Key Dependencies

| Dependency | Purpose |
|------------|---------|
| `clap` | CLI argument parsing |
| `serde` + `toml` | Manifest deserialization |
| `anyhow` + `thiserror` | Error handling |
| `handlebars` | Template-based Julia code generation |
| `walkdir` | Source file discovery |

## Integration Points

| System | Role |
|--------|------|
| **iseriser** | Meta-framework that can scaffold new -iser projects |
| **proven** | Shared Idris2 verified library for formal proofs |
| **typell** | Type theory engine used by ABI layer |
| **PanLL** | Panel integration for interactive workflows |
| **BoJ-server** | Cartridge for remote julianiser execution |
| **VeriSimDB** | Storage for benchmark results and regression tracking |
