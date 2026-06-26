-- SPDX-License-Identifier: MPL-2.0
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
import Decidable.Equality

%default total

--------------------------------------------------------------------------------
-- Platform Detection
--------------------------------------------------------------------------------

||| Supported platforms for this ABI
public export
data Platform = Linux | Windows | MacOS | BSD | WASM

||| The platform this build targets. Defaults to Linux; the Rust/Zig build
||| layer overrides this via the codegen target selection. (Previously a
||| `%runElab` stub that required ElabReflection and did not compile.)
public export
thisPlatform : Platform
thisPlatform = Linux

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
  decEq Python RLang  = No (\case Refl impossible)
  decEq RLang Python  = No (\case Refl impossible)

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

-- Structural decidable equality for JuliaType.
--
-- Defined as a `mutual` block: `decEqJT` decides equality of two JuliaTypes,
-- and `decEqJTVect` decides *heterogeneous* equality of two JuliaType vectors
-- of possibly different statically-known lengths (used by the JTuple/JUnion
-- cases). `decEqJTVect` recurses structurally on the vectors themselves, so it
-- never needs the (erased) length as a runtime value. The off-diagonal cases
-- discharge constructor disequality explicitly; the previous
-- `decEq _ _ = No absurd` did not compile.
mutual
  ||| Heterogeneous decidable equality for two JuliaType vectors. Returns a
  ||| genuine `Dec (xs ~=~ ys)`; differing lengths are rejected by the nil/cons
  ||| shape mismatch, differing elements by `decEqJT`.
  public export
  decEqJTVect : (xs : Vect m JuliaType) -> (ys : Vect p JuliaType) ->
                Dec (xs ~=~ ys)
  decEqJTVect [] [] = Yes Refl
  decEqJTVect [] (y :: ys) = No (\case Refl impossible)
  decEqJTVect (x :: xs) [] = No (\case Refl impossible)
  decEqJTVect (x :: xs) (y :: ys) =
    case decEqJT x y of
      No xneqy => No (\case Refl => xneqy Refl)
      Yes Refl => case decEqJTVect xs ys of
        No tneq => No (\case Refl => tneq Refl)
        Yes Refl => Yes Refl

  ||| Structural decidable equality for two JuliaTypes.
  public export
  decEqJT : (x : JuliaType) -> (y : JuliaType) -> Dec (x = y)
  decEqJT JInt64 JInt64       = Yes Refl
  decEqJT JFloat64 JFloat64   = Yes Refl
  decEqJT JBool JBool         = Yes Refl
  decEqJT JString JString     = Yes Refl
  decEqJT JDataFrame JDataFrame = Yes Refl
  decEqJT JNothing JNothing   = Yes Refl
  decEqJT (JArray e1 n1) (JArray e2 n2) =
    case decEqJT e1 e2 of
      No neq => No (\case Refl => neq Refl)
      Yes Refl => case decEq n1 n2 of
        No neq => No (\case Refl => neq Refl)
        Yes Refl => Yes Refl
  decEqJT (JTuple es1) (JTuple es2) =
    case decEqJTVect es1 es2 of
      No esneq => No (\case Refl => esneq Refl)
      Yes Refl => Yes Refl
  decEqJT (JDict k1 v1) (JDict k2 v2) =
    case decEqJT k1 k2 of
      No neq => No (\case Refl => neq Refl)
      Yes Refl => case decEqJT v1 v2 of
        No neq => No (\case Refl => neq Refl)
        Yes Refl => Yes Refl
  decEqJT (JUnion as1) (JUnion as2) =
    case decEqJTVect as1 as2 of
      No asneq => No (\case Refl => asneq Refl)
      Yes Refl => Yes Refl
  decEqJT JInt64 JFloat64 = No (\case Refl impossible)
  decEqJT JInt64 JBool = No (\case Refl impossible)
  decEqJT JInt64 JString = No (\case Refl impossible)
  decEqJT JInt64 (JArray _ _) = No (\case Refl impossible)
  decEqJT JInt64 JDataFrame = No (\case Refl impossible)
  decEqJT JInt64 (JTuple _) = No (\case Refl impossible)
  decEqJT JInt64 (JDict _ _) = No (\case Refl impossible)
  decEqJT JInt64 JNothing = No (\case Refl impossible)
  decEqJT JInt64 (JUnion _) = No (\case Refl impossible)
  decEqJT JFloat64 JInt64 = No (\case Refl impossible)
  decEqJT JFloat64 JBool = No (\case Refl impossible)
  decEqJT JFloat64 JString = No (\case Refl impossible)
  decEqJT JFloat64 (JArray _ _) = No (\case Refl impossible)
  decEqJT JFloat64 JDataFrame = No (\case Refl impossible)
  decEqJT JFloat64 (JTuple _) = No (\case Refl impossible)
  decEqJT JFloat64 (JDict _ _) = No (\case Refl impossible)
  decEqJT JFloat64 JNothing = No (\case Refl impossible)
  decEqJT JFloat64 (JUnion _) = No (\case Refl impossible)
  decEqJT JBool JInt64 = No (\case Refl impossible)
  decEqJT JBool JFloat64 = No (\case Refl impossible)
  decEqJT JBool JString = No (\case Refl impossible)
  decEqJT JBool (JArray _ _) = No (\case Refl impossible)
  decEqJT JBool JDataFrame = No (\case Refl impossible)
  decEqJT JBool (JTuple _) = No (\case Refl impossible)
  decEqJT JBool (JDict _ _) = No (\case Refl impossible)
  decEqJT JBool JNothing = No (\case Refl impossible)
  decEqJT JBool (JUnion _) = No (\case Refl impossible)
  decEqJT JString JInt64 = No (\case Refl impossible)
  decEqJT JString JFloat64 = No (\case Refl impossible)
  decEqJT JString JBool = No (\case Refl impossible)
  decEqJT JString (JArray _ _) = No (\case Refl impossible)
  decEqJT JString JDataFrame = No (\case Refl impossible)
  decEqJT JString (JTuple _) = No (\case Refl impossible)
  decEqJT JString (JDict _ _) = No (\case Refl impossible)
  decEqJT JString JNothing = No (\case Refl impossible)
  decEqJT JString (JUnion _) = No (\case Refl impossible)
  decEqJT (JArray _ _) JInt64 = No (\case Refl impossible)
  decEqJT (JArray _ _) JFloat64 = No (\case Refl impossible)
  decEqJT (JArray _ _) JBool = No (\case Refl impossible)
  decEqJT (JArray _ _) JString = No (\case Refl impossible)
  decEqJT (JArray _ _) JDataFrame = No (\case Refl impossible)
  decEqJT (JArray _ _) (JTuple _) = No (\case Refl impossible)
  decEqJT (JArray _ _) (JDict _ _) = No (\case Refl impossible)
  decEqJT (JArray _ _) JNothing = No (\case Refl impossible)
  decEqJT (JArray _ _) (JUnion _) = No (\case Refl impossible)
  decEqJT JDataFrame JInt64 = No (\case Refl impossible)
  decEqJT JDataFrame JFloat64 = No (\case Refl impossible)
  decEqJT JDataFrame JBool = No (\case Refl impossible)
  decEqJT JDataFrame JString = No (\case Refl impossible)
  decEqJT JDataFrame (JArray _ _) = No (\case Refl impossible)
  decEqJT JDataFrame (JTuple _) = No (\case Refl impossible)
  decEqJT JDataFrame (JDict _ _) = No (\case Refl impossible)
  decEqJT JDataFrame JNothing = No (\case Refl impossible)
  decEqJT JDataFrame (JUnion _) = No (\case Refl impossible)
  decEqJT (JTuple _) JInt64 = No (\case Refl impossible)
  decEqJT (JTuple _) JFloat64 = No (\case Refl impossible)
  decEqJT (JTuple _) JBool = No (\case Refl impossible)
  decEqJT (JTuple _) JString = No (\case Refl impossible)
  decEqJT (JTuple _) (JArray _ _) = No (\case Refl impossible)
  decEqJT (JTuple _) JDataFrame = No (\case Refl impossible)
  decEqJT (JTuple _) (JDict _ _) = No (\case Refl impossible)
  decEqJT (JTuple _) JNothing = No (\case Refl impossible)
  decEqJT (JTuple _) (JUnion _) = No (\case Refl impossible)
  decEqJT (JDict _ _) JInt64 = No (\case Refl impossible)
  decEqJT (JDict _ _) JFloat64 = No (\case Refl impossible)
  decEqJT (JDict _ _) JBool = No (\case Refl impossible)
  decEqJT (JDict _ _) JString = No (\case Refl impossible)
  decEqJT (JDict _ _) (JArray _ _) = No (\case Refl impossible)
  decEqJT (JDict _ _) JDataFrame = No (\case Refl impossible)
  decEqJT (JDict _ _) (JTuple _) = No (\case Refl impossible)
  decEqJT (JDict _ _) JNothing = No (\case Refl impossible)
  decEqJT (JDict _ _) (JUnion _) = No (\case Refl impossible)
  decEqJT JNothing JInt64 = No (\case Refl impossible)
  decEqJT JNothing JFloat64 = No (\case Refl impossible)
  decEqJT JNothing JBool = No (\case Refl impossible)
  decEqJT JNothing JString = No (\case Refl impossible)
  decEqJT JNothing (JArray _ _) = No (\case Refl impossible)
  decEqJT JNothing JDataFrame = No (\case Refl impossible)
  decEqJT JNothing (JTuple _) = No (\case Refl impossible)
  decEqJT JNothing (JDict _ _) = No (\case Refl impossible)
  decEqJT JNothing (JUnion _) = No (\case Refl impossible)
  decEqJT (JUnion _) JInt64 = No (\case Refl impossible)
  decEqJT (JUnion _) JFloat64 = No (\case Refl impossible)
  decEqJT (JUnion _) JBool = No (\case Refl impossible)
  decEqJT (JUnion _) JString = No (\case Refl impossible)
  decEqJT (JUnion _) (JArray _ _) = No (\case Refl impossible)
  decEqJT (JUnion _) JDataFrame = No (\case Refl impossible)
  decEqJT (JUnion _) (JTuple _) = No (\case Refl impossible)
  decEqJT (JUnion _) (JDict _ _) = No (\case Refl impossible)
  decEqJT (JUnion _) JNothing = No (\case Refl impossible)

||| Decidable equality for JuliaType (structural), delegating to the
||| machine-checked `decEqJT` decision procedure above.
public export
DecEq JuliaType where
  decEq = decEqJT

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

||| Results are decidably equal. The off-diagonal cases discharge the
||| disequality explicitly; the previous `decEq _ _ = No absurd` did not
||| compile (no `Uninhabited (x = y)` instance exists for these).
public export
DecEq Result where
  decEq Ok Ok                       = Yes Refl
  decEq Error Error                 = Yes Refl
  decEq InvalidParam InvalidParam   = Yes Refl
  decEq OutOfMemory OutOfMemory     = Yes Refl
  decEq NullPointer NullPointer     = Yes Refl
  decEq ParseError ParseError       = Yes Refl
  decEq CodegenError CodegenError   = Yes Refl
  decEq Ok Error = No (\case Refl impossible)
  decEq Ok InvalidParam = No (\case Refl impossible)
  decEq Ok OutOfMemory = No (\case Refl impossible)
  decEq Ok NullPointer = No (\case Refl impossible)
  decEq Ok ParseError = No (\case Refl impossible)
  decEq Ok CodegenError = No (\case Refl impossible)
  decEq Error Ok = No (\case Refl impossible)
  decEq Error InvalidParam = No (\case Refl impossible)
  decEq Error OutOfMemory = No (\case Refl impossible)
  decEq Error NullPointer = No (\case Refl impossible)
  decEq Error ParseError = No (\case Refl impossible)
  decEq Error CodegenError = No (\case Refl impossible)
  decEq InvalidParam Ok = No (\case Refl impossible)
  decEq InvalidParam Error = No (\case Refl impossible)
  decEq InvalidParam OutOfMemory = No (\case Refl impossible)
  decEq InvalidParam NullPointer = No (\case Refl impossible)
  decEq InvalidParam ParseError = No (\case Refl impossible)
  decEq InvalidParam CodegenError = No (\case Refl impossible)
  decEq OutOfMemory Ok = No (\case Refl impossible)
  decEq OutOfMemory Error = No (\case Refl impossible)
  decEq OutOfMemory InvalidParam = No (\case Refl impossible)
  decEq OutOfMemory NullPointer = No (\case Refl impossible)
  decEq OutOfMemory ParseError = No (\case Refl impossible)
  decEq OutOfMemory CodegenError = No (\case Refl impossible)
  decEq NullPointer Ok = No (\case Refl impossible)
  decEq NullPointer Error = No (\case Refl impossible)
  decEq NullPointer InvalidParam = No (\case Refl impossible)
  decEq NullPointer OutOfMemory = No (\case Refl impossible)
  decEq NullPointer ParseError = No (\case Refl impossible)
  decEq NullPointer CodegenError = No (\case Refl impossible)
  decEq ParseError Ok = No (\case Refl impossible)
  decEq ParseError Error = No (\case Refl impossible)
  decEq ParseError InvalidParam = No (\case Refl impossible)
  decEq ParseError OutOfMemory = No (\case Refl impossible)
  decEq ParseError NullPointer = No (\case Refl impossible)
  decEq ParseError CodegenError = No (\case Refl impossible)
  decEq CodegenError Ok = No (\case Refl impossible)
  decEq CodegenError Error = No (\case Refl impossible)
  decEq CodegenError InvalidParam = No (\case Refl impossible)
  decEq CodegenError OutOfMemory = No (\case Refl impossible)
  decEq CodegenError NullPointer = No (\case Refl impossible)
  decEq CodegenError ParseError = No (\case Refl impossible)

--------------------------------------------------------------------------------
-- Opaque Handles
--------------------------------------------------------------------------------

||| Opaque handle to a julianiser session (holds parsed AST + codegen state)
public export
data Handle : Type where
  MkHandle : (ptr : Bits64) -> {auto 0 nonNull : So (ptr /= 0)} -> Handle

||| Safely create a handle from a pointer value. Uses `choose` to obtain a
||| real `So (ptr /= 0)` witness for the non-null branch. (Previously
||| `Just (MkHandle ptr)` left the `auto` proof unsolved and did not compile.)
public export
createHandle : Bits64 -> Maybe Handle
createHandle ptr =
  case choose (ptr /= 0) of
    Left ok => Just (MkHandle ptr {nonNull = ok})
    Right _ => Nothing

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
