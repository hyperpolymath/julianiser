-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Layer 5 CAPSTONE: a single end-to-end ABI soundness certificate.
|||
||| This module proves NO new domain theorem. Its sole job is to ASSEMBLE the
||| already-proven facts from every prior proof layer into ONE inhabited value,
||| `abiContractDischarged : ABISound`. Because that value is constructed only
||| from genuine exported witnesses/theorems, it typechecks IF AND ONLY IF every
||| layer it depends on is itself sound — collapsing the whole ABI contract into
||| a single yes/no compile event.
|||
||| The certificate ties the manifest's correctness promise through the ABI
||| proofs into the FFI seam:
|||
|||   * Layer 2 (flagship) — `Julianiser.ABI.Semantics.sampleAgreesGeneric`:
|||     on the canonical positive-control pipeline (`sampleExpr` over `sampleEnv`)
|||     the generated Julia code computes exactly the same value as the source.
|||     This is the headline manifest promise: translation preserves semantics.
|||
|||   * Layer 3 (deeper invariant) — two distinct facts reused verbatim:
|||       - `Julianiser.ABI.Invariants.compositeAgrees`: correctness is CLOSED
|||         UNDER COMPOSITION (the modular/compositional theorem, witnessed on a
|||         concrete linked program), and
|||       - `Julianiser.ABI.Invariants.translateInjective`: the codegen is
|||         INJECTIVE (distinct source ASTs never collapse) — the structural
|||         backbone of deterministic, information-preserving translation.
|||
|||   * Layer 4 (FFI seam) — `Julianiser.ABI.FfiSeam.resultToIntInjective`:
|||     the C-ABI wire encoding of `Result` is unambiguous, so the boundary back
|||     out to Zig/C is sound.
|||
||| Together these say: manifest promise -> ABI proofs (flagship + invariant +
||| injective codegen) -> FFI seam, all discharged in one place. If ANY prior
||| layer were unsound, the field supplying its witness would fail to resolve and
||| this module would not build. The adversarial control (in /tmp during CI)
||| confirms the certificate is non-vacuous: a FALSE field value is rejected.

module Julianiser.ABI.Capstone

import Julianiser.ABI.Types
import Julianiser.ABI.Semantics
import Julianiser.ABI.Invariants
import Julianiser.ABI.FfiSeam
import Data.Vect
import Data.Fin

%default total

--------------------------------------------------------------------------------
-- The end-to-end ABI soundness certificate
--------------------------------------------------------------------------------

||| `ABISound` is a conjunction of the KEY proven facts of this ABI, one field
||| per layer. Each field's TYPE is the exact proposition proved in the layer it
||| names; an inhabitant therefore certifies all layers simultaneously.
public export
record ABISound where
  constructor MkABISound

  ||| Layer 2 flagship, on the canonical positive control: source and generated
  ||| Julia agree on the sample pipeline. (= `Semantics.sampleAgreesGeneric`.)
  flagshipControl :
    evalSrc Semantics.sampleEnv Semantics.sampleExpr
      = evalJulia Semantics.sampleEnv (translate Semantics.sampleExpr)

  ||| Layer 3 invariant (compositionality): correctness is closed under
  ||| composition, witnessed on the concrete composite program.
  ||| (= `Invariants.compositeAgrees`.)
  invariantCompose :
    evalSrc Semantics.sampleEnv Invariants.compositeExpr
      = evalJulia Semantics.sampleEnv (translate Invariants.compositeExpr)

  ||| Layer 3 invariant (deterministic, information-preserving codegen):
  ||| `translate` is injective for every array length. (=
  ||| `Invariants.translateInjective`, held as a function field so the full
  ||| universally-quantified theorem is carried; `n` is bound explicitly here so
  ||| the field type is closed.)
  invariantInjective :
    (n : Nat) -> (e1, e2 : Expr n) -> translate e1 = translate e2 -> e1 = e2

  ||| Layer 4 FFI seam: the `Result` wire encoding is injective / unambiguous.
  ||| (= `FfiSeam.resultToIntInjective`.)
  ffiSeamInjective :
    (a, b : Result) -> resultToInt a = resultToInt b -> a = b

--------------------------------------------------------------------------------
-- THE CAPSTONE: one inhabited value assembled from the real witnesses
--------------------------------------------------------------------------------

||| The capstone certificate. Every field is an existing exported theorem/witness
||| — nothing is re-proved here, only composed. If any layer were unsound, the
||| corresponding witness would not resolve and this definition would not build.
public export
abiContractDischarged : ABISound
abiContractDischarged = MkABISound
  Semantics.sampleAgreesGeneric
  Invariants.compositeAgrees
  (\n, e1, e2, prf => Invariants.translateInjective e1 e2 prf)
  FfiSeam.resultToIntInjective

--------------------------------------------------------------------------------
-- Positive control: the certificate's facts are usable end-to-end
--------------------------------------------------------------------------------

||| Positive control: project the flagship field back out of the assembled
||| certificate and confirm it is the genuine sample-agreement equality.
||| Demonstrates the capstone is not an opaque token but carries real proofs.
public export
capstoneFlagship :
  evalSrc Semantics.sampleEnv Semantics.sampleExpr
    = evalJulia Semantics.sampleEnv (translate Semantics.sampleExpr)
capstoneFlagship = flagshipControl abiContractDischarged

||| Positive control: the carried FFI-seam injectivity, applied to a concrete
||| pair (`Ok`, `Ok`) with `Refl`, yields the expected `Ok = Ok`. Exercises the
||| function-valued field of the assembled certificate.
public export
capstoneSeamOnOk : Ok = Ok
capstoneSeamOnOk = ffiSeamInjective abiContractDischarged Ok Ok Refl
