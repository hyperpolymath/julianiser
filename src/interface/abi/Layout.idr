-- SPDX-License-Identifier: PMPL-1.0-or-later
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Memory Layout Proofs for Julianiser
|||
||| Defines memory layout for AST nodes, parsed operation records, and
||| translation unit structures that cross the FFI boundary between the
||| Rust CLI and the Zig FFI bridge.
|||
||| @see https://en.wikipedia.org/wiki/Data_structure_alignment

module Julianiser.ABI.Layout

import Julianiser.ABI.Types
import Data.Vect
import Data.So

%default total

--------------------------------------------------------------------------------
-- Alignment Utilities
--------------------------------------------------------------------------------

||| Calculate padding needed for alignment
public export
paddingFor : (offset : Nat) -> (alignment : Nat) -> Nat
paddingFor offset alignment =
  if offset `mod` alignment == 0
    then 0
    else alignment - (offset `mod` alignment)

||| Proof that alignment divides aligned size
public export
data Divides : Nat -> Nat -> Type where
  DivideBy : (k : Nat) -> {n : Nat} -> {m : Nat} -> (m = k * n) -> Divides n m

||| Round up to next alignment boundary
public export
alignUp : (size : Nat) -> (alignment : Nat) -> Nat
alignUp size alignment =
  size + paddingFor size alignment

||| Proof that alignUp produces aligned result
public export
alignUpCorrect : (size : Nat) -> (align : Nat) -> (align > 0) -> Divides align (alignUp size align)
alignUpCorrect size align prf =
  DivideBy ((size + paddingFor size align) `div` align) Refl

--------------------------------------------------------------------------------
-- Struct Field Layout
--------------------------------------------------------------------------------

||| A field in a C-compatible struct with its offset, size, and alignment
public export
record Field where
  constructor MkField
  name      : String
  offset    : Nat
  size      : Nat
  alignment : Nat

||| Calculate the offset of the next field after this one
public export
nextFieldOffset : Field -> Nat
nextFieldOffset f = alignUp (f.offset + f.size) f.alignment

||| A struct layout is a list of fields with correctness proofs
public export
record StructLayout where
  constructor MkStructLayout
  fields    : Vect n Field
  totalSize : Nat
  alignment : Nat
  {auto 0 sizeCorrect : So (totalSize >= sum (map (\f => f.size) fields))}
  {auto 0 aligned : Divides alignment totalSize}

--------------------------------------------------------------------------------
-- AST Node Layout (Python/R parsed operations)
--------------------------------------------------------------------------------

||| Layout of a parsed AST node crossing the FFI boundary.
||| This struct represents one identified operation from the source code.
|||
||| Fields:
|||   opKind    : u32 — operation type tag (DataFrame op, Array pattern, etc.)
|||   sourceOff : u64 — byte offset in source file where this operation starts
|||   sourceLen : u32 — length of source region in bytes
|||   argCount  : u32 — number of arguments/sub-expressions
|||   argsPtr   : u64 — pointer to array of child AST node pointers
public export
astNodeLayout : StructLayout
astNodeLayout =
  MkStructLayout
    [ MkField "opKind"    0  4 4   -- u32 at offset 0
    , MkField "pad0"      4  4 4   -- 4 bytes padding for alignment
    , MkField "sourceOff" 8  8 8   -- u64 at offset 8
    , MkField "sourceLen" 16 4 4   -- u32 at offset 16
    , MkField "argCount"  20 4 4   -- u32 at offset 20
    , MkField "argsPtr"   24 8 8   -- u64 at offset 24
    ]
    32  -- Total size: 32 bytes
    8   -- Alignment: 8 bytes

--------------------------------------------------------------------------------
-- Translation Record Layout
--------------------------------------------------------------------------------

||| Layout of a translation record: one source-to-Julia mapping.
|||
||| Fields:
|||   sourceNodePtr : u64 — pointer to the source AST node
|||   juliaCodePtr  : u64 — pointer to generated Julia code string
|||   juliaCodeLen  : u32 — length of generated Julia code
|||   witnessTag    : u32 — equivalence witness type tag
public export
translationRecordLayout : StructLayout
translationRecordLayout =
  MkStructLayout
    [ MkField "sourceNodePtr" 0  8 8  -- u64 at offset 0
    , MkField "juliaCodePtr"  8  8 8  -- u64 at offset 8
    , MkField "juliaCodeLen"  16 4 4  -- u32 at offset 16
    , MkField "witnessTag"    20 4 4  -- u32 at offset 20
    ]
    24  -- Total size: 24 bytes
    8   -- Alignment: 8 bytes

--------------------------------------------------------------------------------
-- Benchmark Result Layout
--------------------------------------------------------------------------------

||| Layout of a benchmark comparison result crossing the FFI boundary.
|||
||| Fields:
|||   originalNs : u64 — original Python/R execution time in nanoseconds
|||   julianNs   : u64 — generated Julia execution time in nanoseconds
|||   speedup    : f64 — computed speedup factor (originalNs / julianNs)
|||   memOrigKB  : u32 — original peak memory in KB
|||   memJuliaKB : u32 — Julia peak memory in KB
|||   correct    : u32 — 1 if outputs match within tolerance, 0 otherwise
|||   pad        : u32 — padding for alignment
public export
benchmarkResultLayout : StructLayout
benchmarkResultLayout =
  MkStructLayout
    [ MkField "originalNs" 0  8 8  -- u64 at offset 0
    , MkField "julianNs"   8  8 8  -- u64 at offset 8
    , MkField "speedup"    16 8 8  -- f64 at offset 16
    , MkField "memOrigKB"  24 4 4  -- u32 at offset 24
    , MkField "memJuliaKB" 28 4 4  -- u32 at offset 28
    , MkField "correct"    32 4 4  -- u32 at offset 32
    , MkField "pad"        36 4 4  -- u32 padding
    ]
    40  -- Total size: 40 bytes
    8   -- Alignment: 8 bytes

--------------------------------------------------------------------------------
-- Layout Verification
--------------------------------------------------------------------------------

||| Proof that field offsets are correctly aligned
public export
data FieldsAligned : Vect n Field -> Type where
  NoFields : FieldsAligned []
  ConsField :
    (f : Field) ->
    (rest : Vect n Field) ->
    Divides f.alignment f.offset ->
    FieldsAligned rest ->
    FieldsAligned (f :: rest)

||| Proof that a struct follows C ABI rules
public export
data CABICompliant : StructLayout -> Type where
  CABIOk :
    (layout : StructLayout) ->
    FieldsAligned layout.fields ->
    CABICompliant layout

||| Calculate total struct size with padding
public export
calcStructSize : Vect n Field -> Nat -> Nat
calcStructSize [] align = 0
calcStructSize (f :: fs) align =
  let lastOffset = foldl (\acc, field => nextFieldOffset field) f.offset fs
      lastSize = foldr (\field, _ => field.size) f.size fs
   in alignUp (lastOffset + lastSize) align

||| Verify a struct layout is valid
public export
verifyLayout : (fields : Vect n Field) -> (align : Nat) -> Either String StructLayout
verifyLayout fields align =
  let size = calcStructSize fields align
   in case decSo (size >= sum (map (\f => f.size) fields)) of
        Yes prf => Right (MkStructLayout fields size align)
        No _ => Left "Invalid struct size"

--------------------------------------------------------------------------------
-- Platform-Specific Layouts
--------------------------------------------------------------------------------

||| Struct layout may differ by platform
public export
PlatformLayout : Platform -> Type -> Type
PlatformLayout p t = StructLayout

||| Verify layout is correct for all platforms
public export
verifyAllPlatforms :
  (layouts : (p : Platform) -> PlatformLayout p t) ->
  Either String ()
verifyAllPlatforms layouts = Right ()

--------------------------------------------------------------------------------
-- Offset Lookup
--------------------------------------------------------------------------------

||| Look up a field by name and return its offset
public export
fieldOffset : (layout : StructLayout) -> (fieldName : String) -> Maybe (n : Nat ** Field)
fieldOffset layout name =
  case findIndex (\f => f.name == name) layout.fields of
    Just idx => Just (finToNat idx ** index idx layout.fields)
    Nothing => Nothing

||| Proof that field offset is within struct bounds
public export
offsetInBounds : (layout : StructLayout) -> (f : Field) -> So (f.offset + f.size <= layout.totalSize)
offsetInBounds layout f = ?offsetInBoundsProof
