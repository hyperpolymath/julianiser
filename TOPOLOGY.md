# SPDX-License-Identifier: PMPL-1.0-or-later
# Julianiser — Repository Topology

## Purpose

Julianiser analyses Python and R data science code, identifies performance-critical
array/dataframe operations, and generates equivalent Julia modules that deliver
10-100x speedups via LLVM JIT compilation.

## Module Map

```
julianiser/
├── src/                            # Rust CLI + orchestration
│   ├── main.rs                     # CLI entry point (init, validate, generate, build, run, info)
│   ├── lib.rs                      # Library API
│   ├── manifest/mod.rs             # julianiser.toml parser and validator
│   ├── codegen/mod.rs              # Julia code generation engine
│   ├── abi/mod.rs                  # Rust-side ABI types mirroring Idris2 proofs
│   └── interface/                  # Verified Interface Seams
│       ├── abi/                    # Idris2 ABI (The Spec)
│       │   ├── Types.idr           # SourceLanguage, DataFrameOp, ArrayPattern, JuliaType, EquivalenceWitness
│       │   ├── Layout.idr          # AST node memory layout with alignment proofs
│       │   └── Foreign.idr         # FFI declarations for Python/R parsing and Julia codegen
│       ├── ffi/                    # Zig FFI (The Bridge)
│       │   ├── build.zig           # Zig build config (shared + static lib)
│       │   ├── src/main.zig        # FFI implementation (parse, translate, codegen)
│       │   └── test/               # Integration tests verifying ABI compliance
│       └── generated/abi/          # Auto-generated C headers from Idris2
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

## Data Flow

```
julianiser.toml ──→ Manifest Parser ──→ Source Parser (Python AST / R parser)
                                              │
                                              ▼
                                     Typed IR (operations, types, data flow)
                                              │
                                              ▼
                                     Idris2 ABI (equivalence proofs)
                                              │
                                              ▼
                                     Julia Codegen (type-annotated, broadcasting)
                                              │
                                              ▼
                                     Zig FFI Bridge (C-ABI interop)
                                              │
                                              ▼
                                     Benchmark Harness (original vs generated)
```

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
