/* SPDX-License-Identifier: MPL-2.0 */
/* Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk> */
/*
 * Julianiser FFI — C header
 *
 * C-ABI declarations for the Zig FFI implementation in src/main.zig.
 * This header mirrors the `export fn` surface of that file exactly; keep
 * the two in sync when either changes.
 *
 * STATUS: scaffolding. The Zig implementation behind this header is
 * TODO-stubbed (see src/main.zig) and is not currently linked into the
 * julianiser Rust CLI. See 0-AI-MANIFEST.a2ml "HONESTY NOTE" for detail.
 */

#ifndef JULIANISER_H
#define JULIANISER_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Opaque session handle. */
typedef void julianiser_handle;

/* Result codes — must match the `Result` enum in src/main.zig. */
typedef enum {
    JULIANISER_OK = 0,
    JULIANISER_ERROR = 1,
    JULIANISER_INVALID_PARAM = 2,
    JULIANISER_OUT_OF_MEMORY = 3,
    JULIANISER_NULL_POINTER = 4,
    JULIANISER_PARSE_ERROR = 5,
    JULIANISER_CODEGEN_ERROR = 6,
} julianiser_result;

/* Lifecycle */
julianiser_handle *julianiser_init(void);
void julianiser_free(julianiser_handle *handle);

/* Source parsing */
int julianiser_parse_python(julianiser_handle *handle, const uint8_t *path_ptr, uint32_t path_len);
int julianiser_parse_r(julianiser_handle *handle, const uint8_t *path_ptr, uint32_t path_len);

/* AST query */
uint32_t julianiser_node_count(julianiser_handle *handle);

/* Julia code generation */
int julianiser_codegen(julianiser_handle *handle);
const char *julianiser_get_julia_code(julianiser_handle *handle);

/* Benchmark operations */
int julianiser_benchmark(julianiser_handle *handle, uint32_t iterations);
double julianiser_get_speedup(julianiser_handle *handle);

/* String operations */
void julianiser_free_string(const char *str);

/* Error handling */
const char *julianiser_last_error(void);

/* Version information */
const char *julianiser_version(void);
const char *julianiser_build_info(void);

/* Utility */
uint32_t julianiser_is_initialized(julianiser_handle *handle);

#ifdef __cplusplus
}
#endif

#endif /* JULIANISER_H */
