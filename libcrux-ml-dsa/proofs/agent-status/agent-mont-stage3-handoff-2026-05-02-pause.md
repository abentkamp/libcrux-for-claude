# Stage 3 mid-flight pause — 2026-05-02 ~19:30

Pausing for session limit; resume in ~2 hours.  No push.

## What landed (verified clean, ready to commit)

**File:** `libcrux-ml-dsa/src/simd/portable/arithmetic.rs`

* `montgomery_multiply_by_constant` post: added `forall (i:nat). i < 8 ==>
  lane_future[i] == mont_mul lane_orig[i] c` clause + matching loop_invariant
  conjunct + body proof (added `reveal_opaque i32_mul` to the existing reveal
  block).  This is **Stage 3's actual goal**.

* `montgomery_multiply` (per-lane) post: added the symmetric `mont_mul`
  equality clause.  This is a **latent Stage 2 bug fix**: trait
  `Operations::montgomery_multiply` post had `lhs_future[i] == mont_mul lhs[i]
  rhs[i]` (added in Stage 2) but the underlying `arithmetic::montgomery_multiply`
  post did NOT expose it — the trait impl `montgomery_multiply_with_proof` was
  passing only via stale `.hints` cache.  Once hints invalidated by my
  re-extraction, the latent break surfaced.  Fix: add the equality clause to
  the impl-side post.

**Both verify clean** via `make check/Libcrux_ml_dsa.Simd.Portable.Arithmetic.fst`
(245s) and `make check/Libcrux_ml_dsa.Simd.Portable.fst` (101s).

## What's in flight (not verified, work-in-progress, also worth committing)

**File:** `libcrux-ml-dsa/src/simd/avx2/arithmetic.rs`

These are all latent Stage-2 issues uncovered when hint cache invalidated.
The fixes below got the file to typecheck/extract but the post for
`montgomery_multiply_by_constant` doesn't yet prove (Z3 incomplete
quantifiers on the new `mont_mul` equality clause that Stage 2 added):

1. **Build fix**: `montgomery_multiply_aux` requires used
   `.and(hax_lib::fstar!(...))`.  `hax_lib::fstar!` returns `()` not `Prop`
   in current hax-lib.  Replaced with `hax_lib::fstar::prop!(...)` — the
   `Prop`-returning variant.

2. **Body F* binder fix**: `montgomery_multiply_aux` body referenced
   `${lhs}_future` which is the `ensures` binder — not in scope inside the
   body.  Added `#[cfg(hax)] let _lhs0 = *lhs;` snapshot at function entry,
   replaced `${lhs}_future` → `${lhs}` (post-state inside body) and pre-state
   refs to `${_lhs0}`.  Mirrors portable convention (`#[cfg(hax)] let _lhs0 = lhs.clone();`).

3. **Type fix**: aux lemmas in both `montgomery_multiply_by_constant` and
   `montgomery_multiply_aux` declared `aux (i:nat{i < 8})` but `to_i32x8`
   requires `i: u64 { v i < 8 }`.  Replaced `nat{i < 8}` → `u64{v i < 8}`.

4. **Rlimit bump**: `--z3rlimit 200` → `--z3rlimit 800` to give room for the
   added equality clauses (8380416 bound + mod_q + mont_mul equality, all in
   the post).  Within the per-fn cap (memory rule SD: rlimit cap 800).

## Known unresolved (post-break)

**`Libcrux_ml_dsa.Simd.Avx2.Arithmetic.fst::montgomery_multiply_by_constant`
post still fails to verify.** Z3: "incomplete quantifiers" on the
function-level postcondition.

The `aux` lemma proves `is_i32b 8380416 (to_i32x8 result i)` and the
`mod_q` clause via `lemma_mont_mul_bound_and_mod_q`.  But the post's
FIRST conjunct `forall i. to_i32x8 result i == mont_mul (to_i32x8 lhs i) constant`
is NOT explicitly proven by `aux` and is not derivable from the
intrinsics axioms + `mont_red` reveal alone (Z3 gives up under quantifier
saturation).  Stage 2 was passing this via hints; re-derivation needs
explicit guidance.

**Investigation paths for resume:**

* Add the equality `to_i32x8 result i == mont_mul (to_i32x8 lhs i) constant`
  as a third conjunct in the `aux` lemma's ensures, derived inside the body
  using `lemma_mont_mul_bound_and_mod_q` widening + reveals (similar to
  how portable's body proof bridges the equality).
* Or: split the post into three separate `Classical.forall_intro` aux
  lemmas (one per conjunct).
* Or: re-enable `--split_queries always`.  When I tried this, two
  smaller errors appeared (assertion failures) — hints that the
  widening from `is_i32b 4190208 constant` to `is_i32b 8380416` may not
  be auto-firing with split_queries.  Worth diagnosing separately.

`montgomery_multiply_aux` likely has the symmetric issue — wasn't reached
by make because make stops after `montgomery_multiply_by_constant`'s error.

## Other latent issue(s) found (out of Stage 3 scope)

* `Libcrux_ml_dsa.Types.Non_hax_impls.fst` was being auto-extracted by hax
  for unsupported `&mut` patterns; references `Rust_primitives.Hax.t_Failure`
  which has been renamed/removed in current hax-lib.  Workaround applied:
  delete the extracted .fst file from disk after extraction.  The hax filter
  `-i "-**::types::non_hax_impls::**"` only excludes the inner items; the
  outer module still gets extracted.  Long-term: fix the extraction filter
  upstream OR add a dummy Non_hax_impls.fst that's safely admittable.
  **Not critical for Stage 3.**

* The Stage 2 commit message claim ("F* verified clean: ...
  Libcrux_ml_dsa.Simd.Avx2.Arithmetic, ... Libcrux_ml_dsa.Simd.Avx2") was
  evidently based on stale `.checked` cache.  Rebuilding from scratch
  surfaces the issues above.

## Stages 4–7 (still pending)

Sprint 1 stages 4–7 (the actual `invert_ntt_montgomery` tightening) have
NOT been touched.  The Stage 3 work was supposed to be a quick prologue;
got stuck cleaning up Stage 2 fallout instead.

When resuming:

1. Land Stage 3 portable (already verified) as one commit.
2. Either close out the avx2 verification gap (recommended) or
   ADMIT_MODULES the avx2 arithmetic file temporarily and proceed to
   Stages 4–7 on portable + admitted avx2.
3. After the avx2 verification gap closes, audit Stage 2's other
   "verified clean" claims — likely several other modules also passed
   only via cache.
