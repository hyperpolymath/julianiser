-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Layer 4: ABI <-> FFI seam soundness proofs for Julianiser.
|||
||| The structural gate (scripts/abi-ffi-gate.py) checks that the Idris2 `Result`
||| enum and the Zig FFI enum agree by name+value. THIS module is the proof-side
||| guarantee that the wire encoding is itself SOUND:
|||
|||   (a) `resultToIntInjective` — distinct ABI `Result` outcomes never collide
|||       on the wire (the encoding is unambiguous).
|||   (b) `intToResult` + `resultRoundTrip` — the C integer faithfully and
|||       losslessly round-trips back to the originating ABI `Result`.
|||
||| Injectivity (a) is DERIVED from the round-trip (b) via `cong` + `justInj`,
||| which is the cleanest argument: if two results encode to the same int, then
||| decoding that int yields the same `Just`, hence the results are equal.
|||
||| Julianiser has exactly one FFI enum encoder (`Result`/`resultToInt`); there
||| is no `ProofStatus`/`statusToInt` or other encoder to mirror, so clause (c)
||| of the seam obligation is vacuous here.
|||
||| Genuine proof only: no `believe_me`, `idris_crash`, `assert_total`,
||| `postulate`, `sorry`. Decidable primitive Bits32 equality discharges the
||| negative (non-vacuity) control.

module Julianiser.ABI.FfiSeam

import Julianiser.ABI.Types

%default total

--------------------------------------------------------------------------------
-- Local lemma
--------------------------------------------------------------------------------

||| `Just` is injective. Proved by pattern matching on the single inhabitant
||| of the equality (the `Just x = Just y` shape forces `x = y`).
private
justInj : {0 x, y : a} -> Just x = Just y -> x = y
justInj Refl = Refl

--------------------------------------------------------------------------------
-- Decoder: the inverse of resultToInt
--------------------------------------------------------------------------------

||| Decode a C integer result code back to the ABI `Result`. Built with nested
||| boolean `if`/`==` on concrete Bits32 literals so the round-trip equalities
||| reduce definitionally to `Refl`. Unknown codes decode to `Nothing`.
public export
intToResult : Bits32 -> Maybe Result
intToResult x =
  if x == 0 then Just Ok
  else if x == 1 then Just Error
  else if x == 2 then Just InvalidParam
  else if x == 3 then Just OutOfMemory
  else if x == 4 then Just NullPointer
  else if x == 5 then Just ParseError
  else if x == 6 then Just CodegenError
  else Nothing

--------------------------------------------------------------------------------
-- (b) Faithful / lossless round-trip
--------------------------------------------------------------------------------

||| The wire encoding is lossless: decoding the encoding of any `Result`
||| recovers exactly that `Result`. Each clause reduces through the boolean
||| `==` comparisons on concrete literals.
export
resultRoundTrip : (r : Result) -> intToResult (resultToInt r) = Just r
resultRoundTrip Ok           = Refl
resultRoundTrip Error        = Refl
resultRoundTrip InvalidParam = Refl
resultRoundTrip OutOfMemory  = Refl
resultRoundTrip NullPointer  = Refl
resultRoundTrip ParseError   = Refl
resultRoundTrip CodegenError = Refl

--------------------------------------------------------------------------------
-- (a) Injectivity, DERIVED from the round-trip
--------------------------------------------------------------------------------

||| The encoding is unambiguous: distinct `Result` values never map to the same
||| C integer. Derived from the round-trip — if `resultToInt a = resultToInt b`,
||| then applying `intToResult` to both sides (via `cong`) gives
||| `Just a = Just b` (using both round-trips), and `justInj` yields
||| `a = b`. No case analysis on the 49-cell matrix is needed.
export
resultToIntInjective : (a, b : Result) ->
                       resultToInt a = resultToInt b -> a = b
resultToIntInjective a b prf =
  justInj $
    rewrite sym (resultRoundTrip a) in
    rewrite sym (resultRoundTrip b) in
    cong intToResult prf

--------------------------------------------------------------------------------
-- Positive controls (concrete decodes machine-checked = Refl)
--------------------------------------------------------------------------------

||| Positive control: code 0 decodes to Ok.
export
decodeZeroIsOk : intToResult 0 = Just Ok
decodeZeroIsOk = Refl

||| Positive control: code 6 decodes to CodegenError (the largest code).
export
decodeSixIsCodegenError : intToResult 6 = Just CodegenError
decodeSixIsCodegenError = Refl

||| Positive control: an out-of-range code decodes to Nothing.
export
decodeSevenIsNothing : intToResult 7 = Nothing
decodeSevenIsNothing = Refl

--------------------------------------------------------------------------------
-- Negative / non-vacuity control (machine-checked)
--------------------------------------------------------------------------------

||| Non-vacuity: two DISTINCT result codes have DISTINCT wire integers. If this
||| were not machine-checkable the injectivity theorem above would be vacuously
||| true. Discharged by Idris's coverage checker on distinct primitive Bits32
||| literals (0 vs 1).
export
okIntNotErrorInt : Not (resultToInt Ok = resultToInt Error)
okIntNotErrorInt = \case Refl impossible

||| A second distinct-pair witness across non-adjacent codes (0 vs 6).
export
okIntNotCodegenInt : Not (resultToInt Ok = resultToInt CodegenError)
okIntNotCodegenInt = \case Refl impossible
