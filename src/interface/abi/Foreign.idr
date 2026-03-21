-- SPDX-License-Identifier: PMPL-1.0-or-later
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Foreign Function Interface Declarations for Julianiser
|||
||| Declares all C-compatible functions implemented in the Zig FFI layer.
||| These functions handle Python/R source parsing and Julia code generation
||| across the FFI boundary.
|||
||| All functions are declared here with type signatures and safety proofs.
||| Implementations live in src/interface/ffi/src/main.zig

module Julianiser.ABI.Foreign

import Julianiser.ABI.Types
import Julianiser.ABI.Layout

%default total

--------------------------------------------------------------------------------
-- Library Lifecycle
--------------------------------------------------------------------------------

||| Initialize the julianiser session.
||| Allocates internal state for AST storage, codegen buffers, and
||| equivalence witness tracking. Returns a handle or Nothing on failure.
export
%foreign "C:julianiser_init, libjulianiser"
prim__init : PrimIO Bits64

||| Safe wrapper for session initialization
export
init : IO (Maybe Handle)
init = do
  ptr <- primIO prim__init
  pure (createHandle ptr)

||| Tear down the julianiser session and free all resources
export
%foreign "C:julianiser_free, libjulianiser"
prim__free : Bits64 -> PrimIO ()

||| Safe wrapper for cleanup
export
free : Handle -> IO ()
free h = primIO (prim__free (handlePtr h))

--------------------------------------------------------------------------------
-- Source Parsing
--------------------------------------------------------------------------------

||| Parse a Python source file into AST nodes.
||| The file is read, tokenised, and parsed into the internal AST
||| representation. Returns 0 on success, error code on failure.
|||
||| Parameters:
|||   handle   — session handle
|||   pathPtr  — pointer to null-terminated file path string
|||   pathLen  — length of file path (excluding null terminator)
export
%foreign "C:julianiser_parse_python, libjulianiser"
prim__parsePython : Bits64 -> Bits64 -> Bits32 -> PrimIO Bits32

||| Safe wrapper for Python parsing
export
parsePython : Handle -> (pathPtr : Bits64) -> (pathLen : Bits32) -> IO (Either Result ())
parsePython h pathPtr pathLen = do
  result <- primIO (prim__parsePython (handlePtr h) pathPtr pathLen)
  pure $ case result of
    0 => Right ()
    5 => Left ParseError
    _ => Left Error

||| Parse an R source file into AST nodes.
||| Same semantics as parsePython but for R scripts.
export
%foreign "C:julianiser_parse_r, libjulianiser"
prim__parseR : Bits64 -> Bits64 -> Bits32 -> PrimIO Bits32

||| Safe wrapper for R parsing
export
parseR : Handle -> (pathPtr : Bits64) -> (pathLen : Bits32) -> IO (Either Result ())
parseR h pathPtr pathLen = do
  result <- primIO (prim__parseR (handlePtr h) pathPtr pathLen)
  pure $ case result of
    0 => Right ()
    5 => Left ParseError
    _ => Left Error

--------------------------------------------------------------------------------
-- AST Query
--------------------------------------------------------------------------------

||| Get the number of parsed AST nodes (identified operations)
export
%foreign "C:julianiser_node_count, libjulianiser"
prim__nodeCount : Bits64 -> PrimIO Bits32

||| Safe node count query
export
nodeCount : Handle -> IO Bits32
nodeCount h = primIO (prim__nodeCount (handlePtr h))

||| Get a pointer to the array of AST nodes.
||| The returned pointer is valid until the session is freed.
||| Layout of each node matches astNodeLayout in Layout.idr.
export
%foreign "C:julianiser_get_nodes, libjulianiser"
prim__getNodes : Bits64 -> PrimIO Bits64

||| Safe node access
export
getNodes : Handle -> IO (Maybe Bits64)
getNodes h = do
  ptr <- primIO (prim__getNodes (handlePtr h))
  pure $ if ptr == 0 then Nothing else Just ptr

--------------------------------------------------------------------------------
-- Julia Code Generation
--------------------------------------------------------------------------------

||| Generate Julia code from the parsed AST nodes.
||| The codegen engine translates each identified operation to its
||| Julia equivalent, producing a complete Julia module.
||| Returns 0 on success, error code on failure.
export
%foreign "C:julianiser_codegen, libjulianiser"
prim__codegen : Bits64 -> PrimIO Bits32

||| Safe wrapper for Julia code generation
export
codegen : Handle -> IO (Either Result ())
codegen h = do
  result <- primIO (prim__codegen (handlePtr h))
  pure $ case result of
    0 => Right ()
    6 => Left CodegenError
    _ => Left Error

||| Get the generated Julia code as a string.
||| Caller must free the returned string via julianiser_free_string.
export
%foreign "C:julianiser_get_julia_code, libjulianiser"
prim__getJuliaCode : Bits64 -> PrimIO Bits64

||| Safe wrapper to retrieve generated Julia source
export
getJuliaCode : Handle -> IO (Maybe String)
getJuliaCode h = do
  ptr <- primIO (prim__getJuliaCode (handlePtr h))
  if ptr == 0
    then pure Nothing
    else do
      let str = prim__getString ptr
      primIO (prim__freeString ptr)
      pure (Just str)

--------------------------------------------------------------------------------
-- Benchmark Operations
--------------------------------------------------------------------------------

||| Run benchmark comparing original source vs. generated Julia.
||| Results are written to the internal benchmark buffer.
||| Layout of each result matches benchmarkResultLayout in Layout.idr.
export
%foreign "C:julianiser_benchmark, libjulianiser"
prim__benchmark : Bits64 -> Bits32 -> PrimIO Bits32

||| Safe benchmark invocation
||| The iterations parameter controls how many times each version runs.
export
benchmark : Handle -> (iterations : Bits32) -> IO (Either Result ())
benchmark h iterations = do
  result <- primIO (prim__benchmark (handlePtr h) iterations)
  pure $ case result of
    0 => Right ()
    _ => Left Error

||| Get the speedup factor from the last benchmark run
export
%foreign "C:julianiser_get_speedup, libjulianiser"
prim__getSpeedup : Bits64 -> PrimIO Double

||| Safe speedup query
export
getSpeedup : Handle -> IO Double
getSpeedup h = primIO (prim__getSpeedup (handlePtr h))

--------------------------------------------------------------------------------
-- String Operations (shared infrastructure)
--------------------------------------------------------------------------------

||| Convert C string to Idris String
export
%foreign "support:idris2_getString, libidris2_support"
prim__getString : Bits64 -> String

||| Free C string allocated by julianiser
export
%foreign "C:julianiser_free_string, libjulianiser"
prim__freeString : Bits64 -> PrimIO ()

--------------------------------------------------------------------------------
-- Error Handling
--------------------------------------------------------------------------------

||| Get last error message
export
%foreign "C:julianiser_last_error, libjulianiser"
prim__lastError : PrimIO Bits64

||| Retrieve last error as string
export
lastError : IO (Maybe String)
lastError = do
  ptr <- primIO prim__lastError
  if ptr == 0
    then pure Nothing
    else pure (Just (prim__getString ptr))

||| Get error description for result code
export
errorDescription : Result -> String
errorDescription Ok           = "Success"
errorDescription Error        = "Generic error"
errorDescription InvalidParam = "Invalid parameter"
errorDescription OutOfMemory  = "Out of memory"
errorDescription NullPointer  = "Null pointer"
errorDescription ParseError   = "Source parsing failed"
errorDescription CodegenError = "Julia code generation failed"

--------------------------------------------------------------------------------
-- Version Information
--------------------------------------------------------------------------------

||| Get library version
export
%foreign "C:julianiser_version, libjulianiser"
prim__version : PrimIO Bits64

||| Get version as string
export
version : IO String
version = do
  ptr <- primIO prim__version
  pure (prim__getString ptr)

--------------------------------------------------------------------------------
-- Utility Functions
--------------------------------------------------------------------------------

||| Check if session is initialized and ready
export
%foreign "C:julianiser_is_initialized, libjulianiser"
prim__isInitialized : Bits64 -> PrimIO Bits32

||| Check initialization status
export
isInitialized : Handle -> IO Bool
isInitialized h = do
  result <- primIO (prim__isInitialized (handlePtr h))
  pure (result /= 0)
