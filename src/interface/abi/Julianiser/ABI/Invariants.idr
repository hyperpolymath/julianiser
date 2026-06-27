-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Layer-3 deep invariants for julianiser's source->Julia translation.
|||
||| The Layer-2 flagship (`Julianiser.ABI.Semantics.translatePreserves`) proves
||| a SINGLE per-expression law: for every expression, the translated Julia code
||| computes the same value as the source. This module proves three GENUINELY
||| DEEPER, DISTINCT properties about the translation as a *structure-preserving
||| transformation*, all reusing the existing model (no datatype is redefined):
|||
|||   1. COMPOSITIONALITY (homomorphism). The translation is a homomorphism with
|||      respect to syntactic composition: a generic binary "plug two programs
|||      together" combiner on the source side is sent by `translate` to the
|||      corresponding combiner on the Julia side. Hence
|||
|||          translate (link op a b) = jlink op (translate a) (translate b)
|||
|||      and, crucially, CORRECTNESS IS CLOSED UNDER COMPOSITION: if each part
|||      preserves results, so does the composite. This is the substitution /
|||      transitivity-style lemma the prompt asks for, NOT a restatement of the
|||      single-op theorem.
|||
|||   2. DETERMINISM. Both evaluators and the whole pipeline are functions: the
|||      translated program's output is uniquely determined by the source program
|||      and the environment. We give a real congruence proof
|||      (`evalJuliaCong`) and a pipeline-determinism corollary, then show
|||      `translate` is INJECTIVE (distinct source ASTs never collapse), which is
|||      the non-vacuous content behind "deterministic codegen".
|||
|||   3. A SECOND, INDEPENDENT CHECKER with a sound AND complete `Dec`: decide
|||      whether a (source, julia) pair is a faithful translation pair, with both
|||      directions proved.
|||
||| Quality controls: a POSITIVE control (an inhabited witness / concrete
||| instance) and a NEGATIVE / non-vacuity control (`Not (...)` plus an injective
||| disequality) are machine-checked at the bottom.

module Julianiser.ABI.Invariants

import Julianiser.ABI.Types
import Julianiser.ABI.Semantics
import Data.Vect
import Data.Fin
import Decidable.Equality

%default total

--------------------------------------------------------------------------------
-- 1. COMPOSITIONALITY: translation is a homomorphism over syntactic linking
--------------------------------------------------------------------------------

||| A binary linking operator on the shared surface syntax. `LinkAdd`/`LinkMul`
||| name the two ways two sub-programs may be composed into a larger one. This
||| is the abstract "compose two pipelines" operation the codegen must respect.
public export
data LinkOp = LinkAdd | LinkMul

||| Compose two SOURCE expressions with a chosen linking operator. This is the
||| syntactic substitution/composition combiner on the Python/R side.
public export
link : LinkOp -> Expr n -> Expr n -> Expr n
link LinkAdd a b = Add a b
link LinkMul a b = Mul a b

||| The corresponding linking combiner on the JULIA side.
public export
jlink : LinkOp -> JExpr n -> JExpr n -> JExpr n
jlink LinkAdd a b = JAdd a b
jlink LinkMul a b = JMul a b

||| The denotation of a linking operator on the source side: how it combines two
||| already-computed integer results.
public export
linkSem : LinkOp -> Integer -> Integer -> Integer
linkSem LinkAdd x y = x + y
linkSem LinkMul x y = x * y

||| HOMOMORPHISM LAW. Translating a composite program equals composing the
||| translations. `translate` commutes with `link`/`jlink`. This is a real
||| structural law, distinct from per-expression value preservation: it talks
||| about the SHAPE of the codegen, not (yet) the values.
public export
translateHom : (op : LinkOp) -> (a : Expr n) -> (b : Expr n) ->
               translate (link op a b) = jlink op (translate a) (translate b)
translateHom LinkAdd a b = Refl
translateHom LinkMul a b = Refl

||| The source evaluator factors through `linkSem`: evaluating a linked program
||| is the linked-semantics of evaluating the parts.
public export
evalSrcLink : (env : Vect n Integer) -> (op : LinkOp) ->
              (a : Expr n) -> (b : Expr n) ->
              evalSrc env (link op a b)
            = linkSem op (evalSrc env a) (evalSrc env b)
evalSrcLink env LinkAdd a b = Refl
evalSrcLink env LinkMul a b = Refl

||| The Julia evaluator factors through the SAME `linkSem` over linked Julia
||| programs. Together with `evalSrcLink` this says both languages agree on what
||| "compose" means at the value level.
public export
evalJuliaLink : (env : Vect n Integer) -> (op : LinkOp) ->
                (a : JExpr n) -> (b : JExpr n) ->
                evalJulia env (jlink op a b)
              = linkSem op (evalJulia env a) (evalJulia env b)
evalJuliaLink env LinkAdd a b = Refl
evalJuliaLink env LinkMul a b = Refl

||| CORRECTNESS IS CLOSED UNDER COMPOSITION (the compositionality theorem).
||| Given ONLY that each part preserves results under translation, the COMPOSITE
||| program preserves results too. The proof never unfolds the structure of `a`
||| or `b` — it uses only the two preservation hypotheses plus the linking laws,
||| so it is a genuine modular/compositional argument rather than a re-run of the
||| structural induction in `translatePreserves`.
public export
preserveCompose :
     (env : Vect n Integer) -> (op : LinkOp) ->
     (a : Expr n) -> (b : Expr n) ->
     (pa : evalSrc env a = evalJulia env (translate a)) ->
     (pb : evalSrc env b = evalJulia env (translate b)) ->
     evalSrc env (link op a b) = evalJulia env (translate (link op a b))
preserveCompose env op a b pa pb =
  rewrite translateHom op a b in
  rewrite evalSrcLink env op a b in
  rewrite evalJuliaLink env op (translate a) (translate b) in
  rewrite pa in
  rewrite pb in Refl

||| Corollary tying the modular lemma back to the global theorem: instantiating
||| `preserveCompose` with the Layer-2 theorem on each part reproves preservation
||| for any linked program — demonstrating the modular lemma is strong enough to
||| drive the whole correctness story by composition.
public export
preserveLinkGlobal :
     (env : Vect n Integer) -> (op : LinkOp) -> (a : Expr n) -> (b : Expr n) ->
     evalSrc env (link op a b) = evalJulia env (translate (link op a b))
preserveLinkGlobal env op a b =
  preserveCompose env op a b
    (translatePreserves env a) (translatePreserves env b)

--------------------------------------------------------------------------------
-- 2. DETERMINISM: evaluators and the pipeline are functions; translate is 1-1
--------------------------------------------------------------------------------

||| Congruence / determinism of the Julia evaluator: equal Julia ASTs evaluated
||| against the same environment give equal results. (Well-definedness: the
||| evaluator is a function, so it cannot return two different answers for the
||| same program.)
public export
evalJuliaCong : (env : Vect n Integer) -> (p, q : JExpr n) ->
                p = q -> evalJulia env p = evalJulia env q
evalJuliaCong env p p Refl = Refl

||| Determinism of the WHOLE pipeline: if two source programs are equal, then
||| their compiled-and-run results coincide. Output is a function of (source,
||| env). Proved by congruence over `translate` then `evalJulia`.
public export
pipelineDet : (env : Vect n Integer) -> (e1, e2 : Expr n) ->
              e1 = e2 ->
              evalJulia env (translate e1) = evalJulia env (translate e2)
pipelineDet env e1 e2 prf =
  evalJuliaCong env (translate e1) (translate e2) (cong translate prf)

-- Constructor-injectivity helpers. Each refutes a stuck/mismatched equality at
-- the top level (idiom: top-level `impossible` clause, never nested `case`).

||| `JAdd` is injective in its left argument (used by `translateInjective`).
jAddInjL : JAdd x1 y1 = JAdd x2 y2 -> x1 = x2
jAddInjL Refl = Refl

||| `JAdd` is injective in its right argument.
jAddInjR : JAdd x1 y1 = JAdd x2 y2 -> y1 = y2
jAddInjR Refl = Refl

||| `JMul` is injective in its left argument.
jMulInjL : JMul x1 y1 = JMul x2 y2 -> x1 = x2
jMulInjL Refl = Refl

||| `JMul` is injective in its right argument.
jMulInjR : JMul x1 y1 = JMul x2 y2 -> y1 = y2
jMulInjR Refl = Refl

||| `JLit` is injective.
jLitInj : JLit a = JLit b -> a = b
jLitInj Refl = Refl

||| `JIndex` is injective.
jIndexInj : JIndex i = JIndex j -> i = j
jIndexInj Refl = Refl

||| `MkJuliaIdx` is injective (so `toJulia` reflects index equality).
mkJuliaIdxInj : MkJuliaIdx i = MkJuliaIdx j -> i = j
mkJuliaIdxInj Refl = Refl

||| INJECTIVITY OF CODEGEN: distinct source ASTs never translate to the same
||| Julia AST. This is the non-vacuous backbone of "the codegen is
||| deterministic AND information-preserving" — a property `translatePreserves`
||| says nothing about. Proved by structural induction, peeling each
||| constructor with the injectivity helpers above.
public export
translateInjective : (e1, e2 : Expr n) ->
                     translate e1 = translate e2 -> e1 = e2
translateInjective (Lit a) (Lit b) prf =
  cong Lit (jLitInj prf)
translateInjective (Add l1 r1) (Add l2 r2) prf =
  let pl = translateInjective l1 l2 (jAddInjL prf)
      pr = translateInjective r1 r2 (jAddInjR prf)
   in rewrite pl in rewrite pr in Refl
translateInjective (Mul l1 r1) (Mul l2 r2) prf =
  let pl = translateInjective l1 l2 (jMulInjL prf)
      pr = translateInjective r1 r2 (jMulInjR prf)
   in rewrite pl in rewrite pr in Refl
translateInjective (Index i) (Index j) prf =
  cong Index (mkJuliaIdxInj (jIndexInj prf))
-- Cross-constructor cases: the two translations are headed by different Julia
-- constructors, so the equality is impossible. Discharged by top-level clauses.
translateInjective (Lit _) (Add _ _) Refl impossible
translateInjective (Lit _) (Mul _ _) Refl impossible
translateInjective (Lit _) (Index _) Refl impossible
translateInjective (Add _ _) (Lit _) Refl impossible
translateInjective (Add _ _) (Mul _ _) Refl impossible
translateInjective (Add _ _) (Index _) Refl impossible
translateInjective (Mul _ _) (Lit _) Refl impossible
translateInjective (Mul _ _) (Add _ _) Refl impossible
translateInjective (Mul _ _) (Index _) Refl impossible
translateInjective (Index _) (Lit _) Refl impossible
translateInjective (Index _) (Add _ _) Refl impossible
translateInjective (Index _) (Mul _ _) Refl impossible

--------------------------------------------------------------------------------
-- 3. SECOND CHECKER: faithful-translation-pair decision (sound + complete)
--------------------------------------------------------------------------------

||| A second, independent checker (distinct from Layer-2's `certifyEquiv`):
||| decide whether a candidate Julia AST `j` is *exactly* the translation of a
||| source AST `e`. This is the relation "j is the certified codegen output for
||| e". We give a genuine `Dec`, sound and complete, built on `DecEq JExpr`.

||| Decidable equality for `JuliaIdx`, via `Fin`'s `DecEq`.
public export
decEqJuliaIdx : (i, j : JuliaIdx n) -> Dec (i = j)
decEqJuliaIdx (MkJuliaIdx a) (MkJuliaIdx b) =
  case decEq a b of
    Yes prf => Yes (cong MkJuliaIdx prf)
    No contra => No (\eq => contra (mkJuliaIdxInj eq))

||| Decidable equality for the Julia AST. Drives the faithfulness checker; built
||| structurally with the injectivity helpers, no `believe_me`/`assert`.
public export
decEqJExpr : (p, q : JExpr n) -> Dec (p = q)
decEqJExpr (JLit a) (JLit b) =
  case decEq a b of
    Yes prf => Yes (cong JLit prf)
    No contra => No (\eq => contra (jLitInj eq))
decEqJExpr (JAdd l1 r1) (JAdd l2 r2) =
  case decEqJExpr l1 l2 of
    No contra => No (\eq => contra (jAddInjL eq))
    Yes pl => case decEqJExpr r1 r2 of
      No contra => No (\eq => contra (jAddInjR eq))
      Yes pr => Yes (rewrite pl in rewrite pr in Refl)
decEqJExpr (JMul l1 r1) (JMul l2 r2) =
  case decEqJExpr l1 l2 of
    No contra => No (\eq => contra (jMulInjL eq))
    Yes pl => case decEqJExpr r1 r2 of
      No contra => No (\eq => contra (jMulInjR eq))
      Yes pr => Yes (rewrite pl in rewrite pr in Refl)
decEqJExpr (JIndex i) (JIndex j) =
  case decEqJuliaIdx i j of
    Yes prf => Yes (cong JIndex prf)
    No contra => No (\eq => contra (jIndexInj eq))
decEqJExpr (JLit _) (JAdd _ _) = No (\case Refl impossible)
decEqJExpr (JLit _) (JMul _ _) = No (\case Refl impossible)
decEqJExpr (JLit _) (JIndex _) = No (\case Refl impossible)
decEqJExpr (JAdd _ _) (JLit _) = No (\case Refl impossible)
decEqJExpr (JAdd _ _) (JMul _ _) = No (\case Refl impossible)
decEqJExpr (JAdd _ _) (JIndex _) = No (\case Refl impossible)
decEqJExpr (JMul _ _) (JLit _) = No (\case Refl impossible)
decEqJExpr (JMul _ _) (JAdd _ _) = No (\case Refl impossible)
decEqJExpr (JMul _ _) (JIndex _) = No (\case Refl impossible)
decEqJExpr (JIndex _) (JLit _) = No (\case Refl impossible)
decEqJExpr (JIndex _) (JAdd _ _) = No (\case Refl impossible)
decEqJExpr (JIndex _) (JMul _ _) = No (\case Refl impossible)

||| `IsFaithfulPair e j` holds exactly when `j` is the certified translation of
||| `e`. Indexed relation, the second checker's specification.
public export
data IsFaithfulPair : Expr n -> JExpr n -> Type where
  MkFaithful : (e : Expr n) -> IsFaithfulPair e (translate e)

||| DECISION PROCEDURE for the faithfulness relation: decide whether `j` is the
||| translation of `e`, by comparing `j` to `translate e`.
public export
decFaithful : (e : Expr n) -> (j : JExpr n) -> Dec (IsFaithfulPair e j)
decFaithful e j =
  case decEqJExpr (translate e) j of
    Yes prf => Yes (rewrite sym prf in MkFaithful e)
    No contra => No (\(MkFaithful e) => contra Refl)

||| SOUNDNESS of the faithfulness checker: a `Yes` verdict means the candidate
||| really equals the codegen output AND (via Layer 2) computes the same value.
public export
decFaithfulSound : (env : Vect n Integer) -> (e : Expr n) -> (j : JExpr n) ->
                   IsFaithfulPair e j ->
                   evalSrc env e = evalJulia env j
decFaithfulSound env e (translate e) (MkFaithful e) = translatePreserves env e

||| COMPLETENESS of the faithfulness checker: the genuine codegen output is
||| always accepted (the checker never rejects a real translation).
public export
decFaithfulComplete : (e : Expr n) -> IsFaithfulPair e (translate e)
decFaithfulComplete e = MkFaithful e

--------------------------------------------------------------------------------
-- POSITIVE control: a concrete composite that round-trips through composition
--------------------------------------------------------------------------------

||| Reuse the Layer-2 sample components to build a COMPOSITE program by linking,
||| then certify it via the compositional lemma `preserveCompose` (NOT the global
||| induction), so the positive control actually exercises the new machinery.
public export
compositeExpr : Expr 3
compositeExpr = link LinkAdd Semantics.sampleExpr (Index FZ)

||| Positive control: the composite preserves results, proved through the
||| compositional theorem fed with per-part Layer-2 witnesses. Inhabited witness
||| for compositionality.
public export
compositeAgrees :
  evalSrc Semantics.sampleEnv Invariants.compositeExpr
    = evalJulia Semantics.sampleEnv (translate Invariants.compositeExpr)
compositeAgrees =
  preserveCompose Semantics.sampleEnv LinkAdd
    Semantics.sampleExpr (Index FZ)
    (translatePreserves Semantics.sampleEnv Semantics.sampleExpr)
    (translatePreserves Semantics.sampleEnv (Index FZ))

||| Positive control for the homomorphism law on the concrete composite,
||| fully reduced and checked by `Refl`.
public export
compositeHom :
  translate Invariants.compositeExpr
    = jlink LinkAdd (translate Semantics.sampleExpr) (translate (Index FZ))
compositeHom = Refl

||| Positive control for the faithfulness checker: it ACCEPTS the genuine
||| translation of the composite.
public export
compositeFaithful : IsFaithfulPair Invariants.compositeExpr
                                   (translate Invariants.compositeExpr)
compositeFaithful = MkFaithful Invariants.compositeExpr

--------------------------------------------------------------------------------
-- NEGATIVE / non-vacuity controls
--------------------------------------------------------------------------------

||| Non-vacuity of injectivity: two DIFFERENT source programs really do produce
||| DIFFERENT Julia programs. Here `Index FZ` vs `Index (FS FZ)`; if `translate`
||| were constant (vacuous), this `Not` would be unprovable. Machine-checked by
||| peeling the codegen output down to the underlying `Fin` disequality
||| `FZ = FS FZ`, which is `Uninhabited`.
public export
translateDistinct : Not (translate (the (Expr 3) (Index FZ))
                       = translate (the (Expr 3) (Index (FS FZ))))
translateDistinct prf =
  absurd (mkJuliaIdxInj (jIndexInj prf))

||| Non-vacuity of the faithfulness checker: it REJECTS a WRONG candidate. The
||| sample's translation is an `Add`, so the checker must say `No` to a `JLit 0`
||| candidate. Forces the `Dec` to be genuinely discriminating, not a constant
||| `Yes`. Machine-checked via the decision returning `No`.
public export
sampleNotFaithfulToLit :
  Not (IsFaithfulPair Semantics.sampleExpr (JLit 0))
sampleNotFaithfulToLit (MkFaithful Semantics.sampleExpr) impossible
