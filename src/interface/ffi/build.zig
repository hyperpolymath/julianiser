// Julianiser FFI Build Configuration
// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Shared library (.so, .dylib, .dll)
    //
    // NOTE (Zig 0.13 compat): `.version` must be passed inline here, not
    // assigned to `lib.version` after construction. When assigned after
    // the fact, `Compile.zig` never populates `major_only_filename` /
    // `name_only_filename`, and `InstallArtifact.create` unconditionally
    // dereferences them once `artifact.version != null` — crashing
    // `zig build` with "attempt to use null value".
    const lib = b.addSharedLibrary(.{
        .name = "julianiser",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .version = .{ .major = 0, .minor = 1, .patch = 0 },
    });
    // main.zig uses std.heap.c_allocator, which requires libc.
    lib.linkLibC();

    // Static library (.a)
    const lib_static = b.addStaticLibrary(.{
        .name = "julianiser",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib_static.linkLibC();

    // Install artifacts
    b.installArtifact(lib);
    b.installArtifact(lib_static);

    // Generate header file for C compatibility
    const header = b.addInstallHeaderFile(
        b.path("include/julianiser.h"),
        "julianiser.h",
    );
    b.getInstallStep().dependOn(&header.step);

    // Unit tests
    const lib_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib_tests.linkLibC();

    const run_lib_tests = b.addRunArtifact(lib_tests);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_lib_tests.step);

    // Integration tests
    const integration_tests = b.addTest(.{
        .root_source_file = b.path("test/integration_test.zig"),
        .target = target,
        .optimize = optimize,
    });

    integration_tests.linkLibrary(lib);

    const run_integration_tests = b.addRunArtifact(integration_tests);

    const integration_test_step = b.step("test-integration", "Run integration tests");
    integration_test_step.dependOn(&run_integration_tests.step);

    // Documentation
    const docs = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = .Debug,
    });
    docs.linkLibC();

    const docs_step = b.step("docs", "Generate documentation");
    docs_step.dependOn(&b.addInstallDirectory(.{
        .source_dir = docs.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    }).step);

    // Benchmark
    const bench = b.addExecutable(.{
        .name = "julianiser-bench",
        .root_source_file = b.path("bench/bench.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });

    bench.linkLibrary(lib);

    const run_bench = b.addRunArtifact(bench);

    const bench_step = b.step("bench", "Run benchmarks");
    bench_step.dependOn(&run_bench.step);
}
