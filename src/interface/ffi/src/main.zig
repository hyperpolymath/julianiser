// Julianiser FFI Implementation
//
// Implements the C-compatible FFI declared in src/interface/abi/Foreign.idr.
// Handles Python/R source parsing dispatch and Julia code generation across
// the ABI boundary. All types and layouts must match the Idris2 ABI definitions.
//
// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

const std = @import("std");

// Version information
const VERSION = "0.1.0";
const BUILD_INFO = "julianiser built with Zig " ++ @import("builtin").zig_version_string;

/// Thread-local error storage
threadlocal var last_error: ?[]const u8 = null;

/// Set the last error message
fn setError(msg: []const u8) void {
    last_error = msg;
}

/// Clear the last error
fn clearError() void {
    last_error = null;
}

//==============================================================================
// Core Types (must match Julianiser.ABI.Types)
//==============================================================================

/// Result codes (must match Idris2 Result type in Types.idr)
pub const Result = enum(c_int) {
    ok = 0,
    @"error" = 1,
    invalid_param = 2,
    out_of_memory = 3,
    null_pointer = 4,
    parse_error = 5,
    codegen_error = 6,
};

/// Source language tag (must match SourceLanguage in Types.idr)
pub const SourceLanguage = enum(u32) {
    python = 0,
    r_lang = 1,
};

/// AST node (must match astNodeLayout in Layout.idr — 32 bytes, 8-byte aligned)
pub const AstNode = extern struct {
    op_kind: u32,     // Operation type tag
    pad0: u32,        // Padding for alignment
    source_off: u64,  // Byte offset in source file
    source_len: u32,  // Length of source region
    arg_count: u32,   // Number of child nodes
    args_ptr: u64,    // Pointer to child node array
};

/// Translation record (must match translationRecordLayout in Layout.idr — 24 bytes)
pub const TranslationRecord = extern struct {
    source_node_ptr: u64,  // Pointer to source AST node
    julia_code_ptr: u64,   // Pointer to generated Julia code
    julia_code_len: u32,   // Length of Julia code
    witness_tag: u32,      // Equivalence witness type
};

/// Benchmark result (must match benchmarkResultLayout in Layout.idr — 40 bytes)
pub const BenchmarkResult = extern struct {
    original_ns: u64,    // Original execution time (nanoseconds)
    julian_ns: u64,      // Julia execution time (nanoseconds)
    speedup: f64,        // Speedup factor
    mem_orig_kb: u32,    // Original peak memory (KB)
    mem_julia_kb: u32,   // Julia peak memory (KB)
    correct: u32,        // 1 if outputs match, 0 otherwise
    pad: u32,            // Padding for alignment
};

/// Internal session state (opaque to callers)
const SessionState = struct {
    allocator: std.mem.Allocator,
    initialized: bool,
    source_lang: ?SourceLanguage,
    nodes: std.ArrayList(AstNode),
    julia_code: ?[]u8,
    last_speedup: f64,
};

//==============================================================================
// Library Lifecycle
//==============================================================================

/// Initialize a julianiser session.
/// Returns a pointer to internal state, or null on failure.
export fn julianiser_init() ?*anyopaque {
    const allocator = std.heap.c_allocator;

    const state = allocator.create(SessionState) catch {
        setError("Failed to allocate session state");
        return null;
    };

    state.* = .{
        .allocator = allocator,
        .initialized = true,
        .source_lang = null,
        .nodes = std.ArrayList(AstNode).init(allocator),
        .julia_code = null,
        .last_speedup = 0.0,
    };

    clearError();
    return @ptrCast(state);
}

/// Free a julianiser session and all associated resources
export fn julianiser_free(handle: ?*anyopaque) void {
    const ptr = handle orelse return;
    const state: *SessionState = @ptrCast(@alignCast(ptr));
    const allocator = state.allocator;

    // Free generated Julia code if present
    if (state.julia_code) |code| {
        allocator.free(code);
    }

    // Free AST nodes
    state.nodes.deinit();

    state.initialized = false;
    allocator.destroy(state);
    clearError();
}

//==============================================================================
// Source Parsing
//==============================================================================

/// Parse a Python source file into internal AST nodes.
/// Returns 0 (ok) on success, 5 (parse_error) on failure.
export fn julianiser_parse_python(
    handle: ?*anyopaque,
    path_ptr: ?[*]const u8,
    path_len: u32,
) c_int {
    const state = getState(handle) orelse return @intFromEnum(Result.null_pointer);
    const path = getSlice(path_ptr, path_len) orelse {
        setError("Null or empty path");
        return @intFromEnum(Result.invalid_param);
    };

    // TODO: Implement Python AST parsing
    // For now, record that we are in Python mode
    state.source_lang = .python;
    _ = path;

    clearError();
    return @intFromEnum(Result.ok);
}

/// Parse an R source file into internal AST nodes.
/// Returns 0 (ok) on success, 5 (parse_error) on failure.
export fn julianiser_parse_r(
    handle: ?*anyopaque,
    path_ptr: ?[*]const u8,
    path_len: u32,
) c_int {
    const state = getState(handle) orelse return @intFromEnum(Result.null_pointer);
    const path = getSlice(path_ptr, path_len) orelse {
        setError("Null or empty path");
        return @intFromEnum(Result.invalid_param);
    };

    // TODO: Implement R parser
    state.source_lang = .r_lang;
    _ = path;

    clearError();
    return @intFromEnum(Result.ok);
}

//==============================================================================
// AST Query
//==============================================================================

/// Get the number of parsed AST nodes
export fn julianiser_node_count(handle: ?*anyopaque) u32 {
    const state = getState(handle) orelse return 0;
    return @intCast(state.nodes.items.len);
}

/// Get a pointer to the AST node array.
/// Returns null if no nodes have been parsed.
export fn julianiser_get_nodes(handle: ?*anyopaque) ?[*]const AstNode {
    const state = getState(handle) orelse return null;
    if (state.nodes.items.len == 0) return null;
    return state.nodes.items.ptr;
}

//==============================================================================
// Julia Code Generation
//==============================================================================

/// Generate Julia code from parsed AST nodes.
/// Returns 0 (ok) on success, 6 (codegen_error) on failure.
export fn julianiser_codegen(handle: ?*anyopaque) c_int {
    const state = getState(handle) orelse return @intFromEnum(Result.null_pointer);

    if (state.source_lang == null) {
        setError("No source parsed yet — call julianiser_parse_python or julianiser_parse_r first");
        return @intFromEnum(Result.codegen_error);
    }

    // TODO: Implement Julia code generation from AST nodes
    // For now, generate a stub module
    const stub = state.allocator.dupe(u8, "# Generated by julianiser\nmodule Generated\nend\n") catch {
        setError("Failed to allocate Julia code buffer");
        return @intFromEnum(Result.out_of_memory);
    };

    // Free previous code if any
    if (state.julia_code) |prev| {
        state.allocator.free(prev);
    }
    state.julia_code = stub;

    clearError();
    return @intFromEnum(Result.ok);
}

/// Get the generated Julia code as a C string.
/// Caller must free via julianiser_free_string.
export fn julianiser_get_julia_code(handle: ?*anyopaque) ?[*:0]const u8 {
    const state = getState(handle) orelse {
        setError("Null handle");
        return null;
    };

    const code = state.julia_code orelse {
        setError("No Julia code generated yet — call julianiser_codegen first");
        return null;
    };

    const c_str = state.allocator.dupeZ(u8, code) catch {
        setError("Failed to allocate string copy");
        return null;
    };

    clearError();
    return c_str.ptr;
}

//==============================================================================
// Benchmark Operations
//==============================================================================

/// Run benchmark comparing original vs. generated Julia.
/// iterations controls how many times each version runs.
export fn julianiser_benchmark(handle: ?*anyopaque, iterations: u32) c_int {
    const state = getState(handle) orelse return @intFromEnum(Result.null_pointer);

    if (state.julia_code == null) {
        setError("No Julia code to benchmark — call julianiser_codegen first");
        return @intFromEnum(Result.@"error");
    }

    // TODO: Implement actual benchmark harness
    _ = iterations;
    state.last_speedup = 1.0; // Placeholder

    clearError();
    return @intFromEnum(Result.ok);
}

/// Get the speedup factor from the last benchmark
export fn julianiser_get_speedup(handle: ?*anyopaque) f64 {
    const state = getState(handle) orelse return 0.0;
    return state.last_speedup;
}

//==============================================================================
// String Operations
//==============================================================================

/// Free a string allocated by julianiser
export fn julianiser_free_string(str: ?[*:0]const u8) void {
    const s = str orelse return;
    const allocator = std.heap.c_allocator;
    const slice = std.mem.span(s);
    allocator.free(slice);
}

//==============================================================================
// Error Handling
//==============================================================================

/// Get the last error message.
/// Returns null if no error. Caller should NOT free this string.
export fn julianiser_last_error() ?[*:0]const u8 {
    const err = last_error orelse return null;
    const allocator = std.heap.c_allocator;
    const c_str = allocator.dupeZ(u8, err) catch return null;
    return c_str.ptr;
}

//==============================================================================
// Version Information
//==============================================================================

/// Get the library version string
export fn julianiser_version() [*:0]const u8 {
    return VERSION.ptr;
}

/// Get build information string
export fn julianiser_build_info() [*:0]const u8 {
    return BUILD_INFO.ptr;
}

//==============================================================================
// Utility Functions
//==============================================================================

/// Check if session handle is initialized and ready
export fn julianiser_is_initialized(handle: ?*anyopaque) u32 {
    const state = getState(handle) orelse return 0;
    return if (state.initialized) 1 else 0;
}

//==============================================================================
// Internal Helpers
//==============================================================================

/// Safely extract SessionState from opaque handle
fn getState(handle: ?*anyopaque) ?*SessionState {
    const ptr = handle orelse {
        setError("Null handle");
        return null;
    };
    const state: *SessionState = @ptrCast(@alignCast(ptr));
    if (!state.initialized) {
        setError("Session not initialized");
        return null;
    }
    return state;
}

/// Safely create a slice from a pointer and length
fn getSlice(ptr: ?[*]const u8, len: u32) ?[]const u8 {
    const p = ptr orelse return null;
    if (len == 0) return null;
    return p[0..len];
}

//==============================================================================
// Tests
//==============================================================================

test "lifecycle" {
    const handle = julianiser_init() orelse return error.InitFailed;
    defer julianiser_free(handle);

    try std.testing.expect(julianiser_is_initialized(handle) == 1);
}

test "parse python sets source language" {
    const handle = julianiser_init() orelse return error.InitFailed;
    defer julianiser_free(handle);

    const path = "test.py";
    const result = julianiser_parse_python(handle, path.ptr, path.len);
    try std.testing.expectEqual(@as(c_int, 0), result);
}

test "codegen without parse fails" {
    const handle = julianiser_init() orelse return error.InitFailed;
    defer julianiser_free(handle);

    const result = julianiser_codegen(handle);
    try std.testing.expectEqual(@as(c_int, 6), result); // codegen_error
}

test "codegen after parse succeeds" {
    const handle = julianiser_init() orelse return error.InitFailed;
    defer julianiser_free(handle);

    const path = "test.py";
    _ = julianiser_parse_python(handle, path.ptr, path.len);

    const result = julianiser_codegen(handle);
    try std.testing.expectEqual(@as(c_int, 0), result);
}

test "error handling with null handle" {
    const result = julianiser_codegen(null);
    try std.testing.expectEqual(@as(c_int, 4), result); // null_pointer

    const err = julianiser_last_error();
    try std.testing.expect(err != null);
}

test "version string" {
    const ver = julianiser_version();
    const ver_str = std.mem.span(ver);
    try std.testing.expectEqualStrings(VERSION, ver_str);
}

test "struct sizes match ABI" {
    // Verify struct sizes match Layout.idr definitions
    try std.testing.expectEqual(@as(usize, 32), @sizeOf(AstNode));
    try std.testing.expectEqual(@as(usize, 24), @sizeOf(TranslationRecord));
    try std.testing.expectEqual(@as(usize, 40), @sizeOf(BenchmarkResult));
}
