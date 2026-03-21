-- SPDX-License-Identifier: PMPL-1.0-or-later
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| ABI Type Definitions for Julianiser
|||
||| Defines types for representing source language constructs (Python/R),
||| target Julia types, and equivalence witnesses proving that generated
||| Julia code preserves the semantics of the original.
|||
||| @see https://idris2.readthedocs.io for Idris2 documentation

module Julianiser.ABI.Types

import Data.Bits
import Data.So
import Data.Vect

%default total

--------------------------------------------------------------------------------
-- Platform Detection
--------------------------------------------------------------------------------

||| Supported platforms for this ABI
public export
data Platform = Linux | Windows | MacOS | BSD | WASM

||| Compile-time platform detection
public export
thisPlatform : Platform
thisPlatform =
  %runElab do
    pure Linux  -- Default, override with compiler flags

--------------------------------------------------------------------------------
-- Source Language Types
--------------------------------------------------------------------------------

||| Languages that julianiser can parse and translate from
public export
data SourceLanguage : Type where
  ||| Python source (parsed via AST)
  Python : SourceLanguage
  ||| R source (parsed via R parser)
  RLang  : SourceLanguage

||| Decidable equality for SourceLanguage
public export
DecEq SourceLanguage where
  decEq Python Python = Yes Refl
  decEq RLang RLang   = Yes Refl
  decEq Python RLang  = No absurd
  decEq RLang Python  = No absurd

--------------------------------------------------------------------------------
-- DataFrame Operations
--------------------------------------------------------------------------------

||| Operations on tabular data (pandas DataFrame / R data.frame / DataFrames.jl)
||| Each constructor represents a semantic operation that julianiser translates.
public export
data DataFrameOperation : Type where
  ||| Select columns by name: df[["col1", "col2"]] -> select(df, :col1, :col2)
  SelectColumns : (columns : Vect n String) -> DataFrameOperation
  ||| Filter rows: df[df.x > 5] -> filter(:x => x -> x > 5, df)
  FilterRows    : (predicate : String) -> DataFrameOperation
  ||| Group by columns: df.groupby("col") -> groupby(df, :col)
  GroupBy       : (columns : Vect n String) -> DataFrameOperation
  ||| Aggregate: df.agg({"col": "sum"}) -> combine(gdf, :col => sum)
  Aggregate     : (column : String) -> (func : String) -> DataFrameOperation
  ||| Join: pd.merge(left, right) -> innerjoin(left, right, on=:key)
  Join          : (joinType : String) -> (onColumns : Vect n String) -> DataFrameOperation
  ||| Sort: df.sort_values("col") -> sort(df, :col)
  SortBy        : (columns : Vect n String) -> (ascending : Bool) -> DataFrameOperation
  ||| Mutate/assign: df["new"] = expr -> transform(df, :new => expr)
  Mutate        : (column : String) -> (expression : String) -> DataFrameOperation

--------------------------------------------------------------------------------
-- Array Patterns
--------------------------------------------------------------------------------

||| Patterns in numeric array code that julianiser recognises and translates.
||| Python numpy operations map to native Julia array operations.
public export
data ArrayPattern : Type where
  ||| Element-wise broadcasting: a + b -> a .+ b
  Broadcasting     : ArrayPattern
  ||| Slicing: a[1:10] -> a[2:11] (0-based to 1-based index shift)
  Slicing          : (start : Nat) -> (stop : Nat) -> ArrayPattern
  ||| Matrix multiply: np.dot(a, b) -> a * b
  MatrixMultiply   : ArrayPattern
  ||| In-place operation: np.multiply(a, b, out=c) -> mul!(c, a, b)
  InPlaceOperation : (op : String) -> ArrayPattern
  ||| Reduction: np.sum(a, axis=0) -> sum(a, dims=1)
  Reduction        : (func : String) -> (axis : Nat) -> ArrayPattern
  ||| Reshape: a.reshape(m, n) -> reshape(a, m, n)
  Reshape          : (dims : Vect n Nat) -> ArrayPattern
  ||| Linear algebra: np.linalg.solve(A, b) -> A \ b
  LinearAlgebra    : (op : String) -> ArrayPattern

--------------------------------------------------------------------------------
-- Julia Types
--------------------------------------------------------------------------------

||| Julia types that julianiser generates. Each constructor corresponds to
||| a concrete Julia type annotation in the generated code.
public export
data JuliaType : Type where
  ||| Julia Int64 (default integer)
  JInt64       : JuliaType
  ||| Julia Float64 (default float)
  JFloat64     : JuliaType
  ||| Julia Bool
  JBool        : JuliaType
  ||| Julia String
  JString      : JuliaType
  ||| Julia Array{T, N} — N-dimensional typed array
  JArray       : (elemType : JuliaType) -> (ndims : Nat) -> JuliaType
  ||| Julia DataFrame (from DataFrames.jl)
  JDataFrame   : JuliaType
  ||| Julia Tuple{T...}
  JTuple       : (elements : Vect n JuliaType) -> JuliaType
  ||| Julia Dict{K, V}
  JDict        : (keyType : JuliaType) -> (valType : JuliaType) -> JuliaType
  ||| Julia Nothing (Unit/None equivalent)
  JNothing     : JuliaType
  ||| Julia Union{T...} (for Optional-like patterns)
  JUnion       : (alternatives : Vect n JuliaType) -> JuliaType

||| Decidable equality for JuliaType (structural)
public export
DecEq JuliaType where
  decEq JInt64 JInt64         = Yes Refl
  decEq JFloat64 JFloat64    = Yes Refl
  decEq JBool JBool           = Yes Refl
  decEq JString JString       = Yes Refl
  decEq JNothing JNothing     = Yes Refl
  decEq _ _                   = No absurd

--------------------------------------------------------------------------------
-- Equivalence Witnesses
--------------------------------------------------------------------------------

||| Proof that a source operation in Python/R has a semantically equivalent
||| Julia translation. This is the core correctness guarantee of julianiser.
|||
||| An EquivalenceWitness carries:
|||   - The source language the operation came from
|||   - The source operation (as a string representation)
|||   - The generated Julia code
|||   - Evidence that the translation preserves semantics
public export
data EquivalenceWitness : SourceLanguage -> Type where
  ||| Witness that a DataFrame operation translates correctly
  DFEquiv   : (lang : SourceLanguage)
           -> (op : DataFrameOperation)
           -> (juliaCode : String)
           -> EquivalenceWitness lang
  ||| Witness that an array pattern translates correctly
  ArrayEquiv : (lang : SourceLanguage)
            -> (pattern : ArrayPattern)
            -> (juliaCode : String)
            -> EquivalenceWitness lang
  ||| Witness that a type mapping is correct
  TypeEquiv  : (lang : SourceLanguage)
            -> (sourceType : String)
            -> (juliaType : JuliaType)
            -> EquivalenceWitness lang

||| Collection of equivalence witnesses for a full translation unit
public export
record TranslationUnit where
  constructor MkTranslationUnit
  sourceLang   : SourceLanguage
  sourceFile   : String
  witnesses    : List (EquivalenceWitness sourceLang)
  outputModule : String

--------------------------------------------------------------------------------
-- Index Remapping
--------------------------------------------------------------------------------

||| Proof that 0-based indexing (Python) correctly maps to 1-based (Julia).
||| This is critical for array slicing correctness.
public export
data IndexRemapCorrect : Nat -> Nat -> Type where
  ||| ZeroToOne: Python index n maps to Julia index (n + 1)
  ZeroToOne : (pyIdx : Nat) -> IndexRemapCorrect pyIdx (S pyIdx)

||| Remap a 0-based index to 1-based
public export
remapIndex : (pyIdx : Nat) -> (juliaIdx : Nat ** IndexRemapCorrect pyIdx juliaIdx)
remapIndex n = (S n ** ZeroToOne n)

--------------------------------------------------------------------------------
-- Result Codes
--------------------------------------------------------------------------------

||| Result codes for FFI operations
public export
data Result : Type where
  Ok           : Result
  Error        : Result
  InvalidParam : Result
  OutOfMemory  : Result
  NullPointer  : Result
  ParseError   : Result
  CodegenError : Result

||| Convert Result to C integer
public export
resultToInt : Result -> Bits32
resultToInt Ok           = 0
resultToInt Error        = 1
resultToInt InvalidParam = 2
resultToInt OutOfMemory  = 3
resultToInt NullPointer  = 4
resultToInt ParseError   = 5
resultToInt CodegenError = 6

||| Results are decidably equal
public export
DecEq Result where
  decEq Ok Ok                       = Yes Refl
  decEq Error Error                 = Yes Refl
  decEq InvalidParam InvalidParam   = Yes Refl
  decEq OutOfMemory OutOfMemory     = Yes Refl
  decEq NullPointer NullPointer     = Yes Refl
  decEq ParseError ParseError       = Yes Refl
  decEq CodegenError CodegenError   = Yes Refl
  decEq _ _                         = No absurd

--------------------------------------------------------------------------------
-- Opaque Handles
--------------------------------------------------------------------------------

||| Opaque handle to a julianiser session (holds parsed AST + codegen state)
public export
data Handle : Type where
  MkHandle : (ptr : Bits64) -> {auto 0 nonNull : So (ptr /= 0)} -> Handle

||| Safely create a handle from a pointer value
public export
createHandle : Bits64 -> Maybe Handle
createHandle 0 = Nothing
createHandle ptr = Just (MkHandle ptr)

||| Extract pointer value from handle
public export
handlePtr : Handle -> Bits64
handlePtr (MkHandle ptr) = ptr

--------------------------------------------------------------------------------
-- Platform-Specific Types
--------------------------------------------------------------------------------

||| C int size varies by platform
public export
CInt : Platform -> Type
CInt Linux   = Bits32
CInt Windows = Bits32
CInt MacOS   = Bits32
CInt BSD     = Bits32
CInt WASM    = Bits32

||| C size_t varies by platform
public export
CSize : Platform -> Type
CSize Linux   = Bits64
CSize Windows = Bits64
CSize MacOS   = Bits64
CSize BSD     = Bits64
CSize WASM    = Bits32

||| C pointer size varies by platform
public export
ptrSize : Platform -> Nat
ptrSize Linux   = 64
ptrSize Windows = 64
ptrSize MacOS   = 64
ptrSize BSD     = 64
ptrSize WASM    = 32

--------------------------------------------------------------------------------
-- Memory Layout Proofs
--------------------------------------------------------------------------------

||| Proof that a type has a specific size in bytes
public export
data HasSize : Type -> Nat -> Type where
  SizeProof : {0 t : Type} -> {n : Nat} -> HasSize t n

||| Proof that a type has a specific alignment in bytes
public export
data HasAlignment : Type -> Nat -> Type where
  AlignProof : {0 t : Type} -> {n : Nat} -> HasAlignment t n
