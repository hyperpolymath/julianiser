# SPDX-License-Identifier: PMPL-1.0-or-later
# julianiser — Python/R to Julia data pipeline conversion

# Default: build and test
default: build test

# Build release binary
build:
    cargo build --release

# Run all tests
test:
    cargo test

# Run clippy lints
lint:
    cargo clippy -- -D warnings

# Format code
fmt:
    cargo fmt

# Check formatting without modifying
fmt-check:
    cargo fmt -- --check

# Generate code from manifest (main codegen pipeline)
generate *ARGS:
    cargo run -- generate {{ARGS}}

# Validate manifest file
validate *ARGS:
    cargo run -- validate {{ARGS}}

# Build documentation
doc:
    cargo doc --no-deps --open

# Clean build artifacts
clean:
    cargo clean

# Run the CLI
run *ARGS:
    cargo run -- {{ARGS}}

# Full quality check (lint + test + fmt-check)
quality: fmt-check lint test
    @echo "All quality checks passed"

# Install locally
install:
    cargo install --path .

# Run panic-attacker pre-commit scan
assail:
    @command -v panic-attack >/dev/null 2>&1 && panic-attack assail . || echo "panic-attack not found — install from https://github.com/hyperpolymath/panic-attacker"

# Show project info
info:
    cargo run -- info

# Run contractile checks
contractile:
    @just --justfile contractile.just check-all
