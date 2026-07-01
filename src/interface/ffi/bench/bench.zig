// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// Julianiser FFI — minimal benchmark harness executable.
//
// STATUS: scaffolding. Exercises the current TODO-stubbed FFI lifecycle
// (init → parse → codegen → benchmark → free) purely to give `zig build
// bench` something real to run and time. The underlying `julianiser_codegen`
// / `julianiser_benchmark` calls are placeholders (see src/main.zig) — the
// numbers this prints measure the stub's overhead, not real Python/R-to-
// Julia translation performance. Do not cite this as a speedup measurement.

const std = @import("std");

extern fn julianiser_init() ?*anyopaque;
extern fn julianiser_free(handle: ?*anyopaque) void;
extern fn julianiser_parse_python(handle: ?*anyopaque, path_ptr: ?[*]const u8, path_len: u32) c_int;
extern fn julianiser_codegen(handle: ?*anyopaque) c_int;
extern fn julianiser_benchmark(handle: ?*anyopaque, iterations: u32) c_int;
extern fn julianiser_get_speedup(handle: ?*anyopaque) f64;
extern fn julianiser_version() [*:0]const u8;

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    try stdout.print("julianiser FFI bench (scaffolding stub) — version {s}\n", .{julianiser_version()});

    var timer = try std.time.Timer.start();

    const handle = julianiser_init() orelse {
        try stdout.print("init failed\n", .{});
        return error.InitFailed;
    };
    defer julianiser_free(handle);

    const path = "bench.py";
    _ = julianiser_parse_python(handle, path.ptr, path.len);
    _ = julianiser_codegen(handle);
    _ = julianiser_benchmark(handle, 1000);

    const elapsed_ns = timer.read();
    const speedup = julianiser_get_speedup(handle);

    try stdout.print("lifecycle elapsed: {d}ns\n", .{elapsed_ns});
    try stdout.print("reported speedup (stub placeholder, not measured): {d}\n", .{speedup});
}
