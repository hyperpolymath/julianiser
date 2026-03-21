// Julianiser Integration Tests
// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// These tests verify that the Zig FFI correctly implements the Idris2 ABI
// for julianiser's Python/R parsing and Julia code generation pipeline.

const std = @import("std");
const testing = std.testing;

// Import julianiser FFI functions
extern fn julianiser_init() ?*anyopaque;
extern fn julianiser_free(?*anyopaque) void;
extern fn julianiser_parse_python(?*anyopaque, ?[*]const u8, u32) c_int;
extern fn julianiser_parse_r(?*anyopaque, ?[*]const u8, u32) c_int;
extern fn julianiser_node_count(?*anyopaque) u32;
extern fn julianiser_codegen(?*anyopaque) c_int;
extern fn julianiser_get_julia_code(?*anyopaque) ?[*:0]const u8;
extern fn julianiser_free_string(?[*:0]const u8) void;
extern fn julianiser_benchmark(?*anyopaque, u32) c_int;
extern fn julianiser_get_speedup(?*anyopaque) f64;
extern fn julianiser_last_error() ?[*:0]const u8;
extern fn julianiser_version() [*:0]const u8;
extern fn julianiser_build_info() [*:0]const u8;
extern fn julianiser_is_initialized(?*anyopaque) u32;

//==============================================================================
// Lifecycle Tests
//==============================================================================

test "create and destroy session" {
    const handle = julianiser_init() orelse return error.InitFailed;
    defer julianiser_free(handle);

    try testing.expect(handle != null);
}

test "session is initialized after creation" {
    const handle = julianiser_init() orelse return error.InitFailed;
    defer julianiser_free(handle);

    const initialized = julianiser_is_initialized(handle);
    try testing.expectEqual(@as(u32, 1), initialized);
}

test "null handle is not initialized" {
    const initialized = julianiser_is_initialized(null);
    try testing.expectEqual(@as(u32, 0), initialized);
}

//==============================================================================
// Python Parsing Tests
//==============================================================================

test "parse python with valid path" {
    const handle = julianiser_init() orelse return error.InitFailed;
    defer julianiser_free(handle);

    const path = "examples/pipeline.py";
    const result = julianiser_parse_python(handle, path.ptr, @intCast(path.len));
    try testing.expectEqual(@as(c_int, 0), result); // ok
}

test "parse python with null handle returns error" {
    const path = "test.py";
    const result = julianiser_parse_python(null, path.ptr, @intCast(path.len));
    try testing.expectEqual(@as(c_int, 4), result); // null_pointer
}

test "parse python with null path returns error" {
    const handle = julianiser_init() orelse return error.InitFailed;
    defer julianiser_free(handle);

    const result = julianiser_parse_python(handle, null, 0);
    try testing.expectEqual(@as(c_int, 2), result); // invalid_param
}

//==============================================================================
// R Parsing Tests
//==============================================================================

test "parse R with valid path" {
    const handle = julianiser_init() orelse return error.InitFailed;
    defer julianiser_free(handle);

    const path = "examples/analysis.R";
    const result = julianiser_parse_r(handle, path.ptr, @intCast(path.len));
    try testing.expectEqual(@as(c_int, 0), result); // ok
}

//==============================================================================
// Code Generation Tests
//==============================================================================

test "codegen without parsing fails" {
    const handle = julianiser_init() orelse return error.InitFailed;
    defer julianiser_free(handle);

    const result = julianiser_codegen(handle);
    try testing.expectEqual(@as(c_int, 6), result); // codegen_error
}

test "codegen after python parse succeeds" {
    const handle = julianiser_init() orelse return error.InitFailed;
    defer julianiser_free(handle);

    const path = "test.py";
    _ = julianiser_parse_python(handle, path.ptr, @intCast(path.len));

    const result = julianiser_codegen(handle);
    try testing.expectEqual(@as(c_int, 0), result); // ok
}

test "get julia code after codegen" {
    const handle = julianiser_init() orelse return error.InitFailed;
    defer julianiser_free(handle);

    const path = "test.py";
    _ = julianiser_parse_python(handle, path.ptr, @intCast(path.len));
    _ = julianiser_codegen(handle);

    const code = julianiser_get_julia_code(handle);
    defer if (code) |c| julianiser_free_string(c);

    try testing.expect(code != null);
    if (code) |c| {
        const code_str = std.mem.span(c);
        try testing.expect(code_str.len > 0);
    }
}

test "get julia code without codegen returns null" {
    const handle = julianiser_init() orelse return error.InitFailed;
    defer julianiser_free(handle);

    const code = julianiser_get_julia_code(handle);
    try testing.expect(code == null);
}

//==============================================================================
// Benchmark Tests
//==============================================================================

test "benchmark without codegen fails" {
    const handle = julianiser_init() orelse return error.InitFailed;
    defer julianiser_free(handle);

    const result = julianiser_benchmark(handle, 10);
    try testing.expectEqual(@as(c_int, 1), result); // error
}

test "benchmark after codegen succeeds" {
    const handle = julianiser_init() orelse return error.InitFailed;
    defer julianiser_free(handle);

    const path = "test.py";
    _ = julianiser_parse_python(handle, path.ptr, @intCast(path.len));
    _ = julianiser_codegen(handle);

    const result = julianiser_benchmark(handle, 10);
    try testing.expectEqual(@as(c_int, 0), result); // ok
}

test "speedup after benchmark is non-negative" {
    const handle = julianiser_init() orelse return error.InitFailed;
    defer julianiser_free(handle);

    const path = "test.py";
    _ = julianiser_parse_python(handle, path.ptr, @intCast(path.len));
    _ = julianiser_codegen(handle);
    _ = julianiser_benchmark(handle, 5);

    const speedup = julianiser_get_speedup(handle);
    try testing.expect(speedup >= 0.0);
}

//==============================================================================
// Error Handling Tests
//==============================================================================

test "last error after null handle operation" {
    _ = julianiser_codegen(null);

    const err = julianiser_last_error();
    try testing.expect(err != null);

    if (err) |e| {
        const err_str = std.mem.span(e);
        try testing.expect(err_str.len > 0);
    }
}

//==============================================================================
// Version Tests
//==============================================================================

test "version string is not empty" {
    const ver = julianiser_version();
    const ver_str = std.mem.span(ver);
    try testing.expect(ver_str.len > 0);
}

test "version string is semantic version format" {
    const ver = julianiser_version();
    const ver_str = std.mem.span(ver);
    try testing.expect(std.mem.count(u8, ver_str, ".") >= 1);
}

test "build info is not empty" {
    const info = julianiser_build_info();
    const info_str = std.mem.span(info);
    try testing.expect(info_str.len > 0);
}

//==============================================================================
// Memory Safety Tests
//==============================================================================

test "multiple sessions are independent" {
    const h1 = julianiser_init() orelse return error.InitFailed;
    defer julianiser_free(h1);

    const h2 = julianiser_init() orelse return error.InitFailed;
    defer julianiser_free(h2);

    try testing.expect(h1 != h2);

    // Parse different languages in each session
    const py_path = "test.py";
    const r_path = "test.R";
    _ = julianiser_parse_python(h1, py_path.ptr, @intCast(py_path.len));
    _ = julianiser_parse_r(h2, r_path.ptr, @intCast(r_path.len));
}

test "free null is safe" {
    julianiser_free(null); // Must not crash
}
