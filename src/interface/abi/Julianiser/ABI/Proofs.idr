-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Machine-checked proofs over the julianiser ABI.
|||
||| These are not runtime tests — they are propositional statements the Idris2
||| type checker must discharge at compile time. If any concrete ABI layout
||| were misaligned, the result-code encoding wrong, or an index-remapping
||| relation mis-defined, this module would fail to typecheck and the proof
||| build would go red.
|||
||| The C-ABI compliance witnesses are built directly from per-field
||| divisibility proofs (`DivideBy k Refl`, where `offset = k * alignment`).
||| Multiplication reduces during type checking, so these are fully verified
||| by the compiler; we deliberately avoid routing them through `Nat`
||| division, which is a primitive that does not reduce at the type level.

module Julianiser.ABI.Proofs

import Julianiser.ABI.Types
import Julianiser.ABI.Layout
import Data.So
import Data.Vect

%default total

--------------------------------------------------------------------------------
-- The concrete FFI struct layouts are provably C-ABI compliant.
--------------------------------------------------------------------------------

||| Every field offset in the AST-node layout divides its alignment:
||| 0|4, 4|4, 8|8, 16|4, 20|4, 24|8.
export
astNodeCompliant : CABICompliant Layout.astNodeLayout
astNodeCompliant =
  CABIOk astNodeLayout
    (ConsField _ _ (DivideBy 0 Refl)   -- offset 0  = 0 * 4
    (ConsField _ _ (DivideBy 1 Refl)   -- offset 4  = 1 * 4
    (ConsField _ _ (DivideBy 1 Refl)   -- offset 8  = 1 * 8
    (ConsField _ _ (DivideBy 4 Refl)   -- offset 16 = 4 * 4
    (ConsField _ _ (DivideBy 5 Refl)   -- offset 20 = 5 * 4
    (ConsField _ _ (DivideBy 3 Refl)   -- offset 24 = 3 * 8
     NoFields))))))

||| Every field offset in the translation-record layout divides its alignment:
||| 0|8, 8|8, 16|4, 20|4.
export
translationRecordCompliant : CABICompliant Layout.translationRecordLayout
translationRecordCompliant =
  CABIOk translationRecordLayout
    (ConsField _ _ (DivideBy 0 Refl)   -- offset 0  = 0 * 8
    (ConsField _ _ (DivideBy 1 Refl)   -- offset 8  = 1 * 8
    (ConsField _ _ (DivideBy 4 Refl)   -- offset 16 = 4 * 4
    (ConsField _ _ (DivideBy 5 Refl)   -- offset 20 = 5 * 4
     NoFields))))

||| Every field offset in the benchmark-result layout divides its alignment:
||| 0|8, 8|8, 16|8, 24|4, 28|4, 32|4, 36|4.
export
benchmarkResultCompliant : CABICompliant Layout.benchmarkResultLayout
benchmarkResultCompliant =
  CABIOk benchmarkResultLayout
    (ConsField _ _ (DivideBy 0 Refl)   -- offset 0  = 0 * 8
    (ConsField _ _ (DivideBy 1 Refl)   -- offset 8  = 1 * 8
    (ConsField _ _ (DivideBy 2 Refl)   -- offset 16 = 2 * 8
    (ConsField _ _ (DivideBy 6 Refl)   -- offset 24 = 6 * 4
    (ConsField _ _ (DivideBy 7 Refl)   -- offset 28 = 7 * 4
    (ConsField _ _ (DivideBy 8 Refl)   -- offset 32 = 8 * 4
    (ConsField _ _ (DivideBy 9 Refl)   -- offset 36 = 9 * 4
     NoFields)))))))

--------------------------------------------------------------------------------
-- Result-code round-trip: the encoding the Zig FFI depends on.
--------------------------------------------------------------------------------

||| `Ok` encodes to 0 — the success sentinel the FFI wrappers branch on.
export
okIsZero : resultToInt Ok = 0
okIsZero = Refl

||| `ParseError` encodes to 5 — matched explicitly in `parsePython`/`parseR`.
export
parseErrorIsFive : resultToInt ParseError = 5
parseErrorIsFive = Refl

||| `CodegenError` encodes to 6 — matched explicitly in `codegen`.
export
codegenErrorIsSix : resultToInt CodegenError = 6
codegenErrorIsSix = Refl

--------------------------------------------------------------------------------
-- Index remapping: Python 0-based -> Julia 1-based is the successor relation.
--------------------------------------------------------------------------------

||| The remap of any Python index `n` is `S n` (1-based), carrying a genuine
||| `IndexRemapCorrect` witness. This pins the slicing-correctness contract.
export
remapIsSucc : (n : Nat) -> fst (remapIndex n) = S n
remapIsSucc n = Refl

||| Concretely: Python index 0 maps to Julia index 1.
export
remapZeroIsOne : fst (remapIndex 0) = 1
remapZeroIsOne = Refl
