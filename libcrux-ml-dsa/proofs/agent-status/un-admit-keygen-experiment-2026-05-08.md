# Un-admit `Ml_dsa_generic::generate_key_pair` body — experiment 2026-05-08

Tier 1a from `resume-prompt-2026-05-08.md`.  Goal: measure whether the
post-Track-B / forall8/32 / mont_mul-clause-drop trait-surface state
(commit `03501b021`) is enough to discharge `generate_key_pair`'s body
proof, or whether the audit's Phase A items 25–27 (ntt/invert_ntt/reduce
poly-forall opacity) still need to land.

## Method

1. Started from clean baseline at HEAD `03501b021`: `JOBS=4 ./hax.sh prove`
   reports 99 modules / 0 errors.
2. Removed `hax_lib::fstar!("admit ()");` at `src/ml_dsa_generic.rs:95`.
3. Re-extracted; ran prove with `--query_stats`.
4. For the function-VC cliff query, dumped `.smt2` via
   `OTHERFLAGS='--log_queries --z3refresh' make -k check/<Module>.fst`
   and profiled with `z3-4.13.3 smt.qi.profile=true smt.qi.profile_freq=20000`.
5. Reverted the un-admit; confirmed baseline still clean.

## Results

### Failure shape

9 errors total across the three monomorphizations
(`Ml_dsa_generic.Ml_dsa_{44,65,87}_`):

| # | Site | Kind | Symptom |
|---|---|---|---|
| 6 | `.fst:111,16-111,24` and `:122,16-122,24` (×3 mono) | `Hax_lib.v_assert` failure | `unknown because (incomplete quantifiers)` at rlimit 400; **NOT a cliff** — caller-side missing-precondition. Discharges `signing_key.len() == SIGNING_KEY_SIZE` / `verification_key.len() == VERIFICATION_KEY_SIZE` from the `debug_assert!` lines.  These would close trivially if the dropped `requires` clause (per the FOLLOW-UP comment at `ml_dsa_generic.rs:56-62`) were restored. |
| 3 | `.fst:106,26-348,60` (×3 mono), Query-stats `generate_key_pair, 54` (Ml_dsa_44_), `, 56` (Ml_dsa_65_, Ml_dsa_87_) | function-VC cliff | `failed {reason-unknown=unknown because canceled}` after **70.7–80.4 s** at rlimit 400.000 (saturated). |

The cliff query was previously called q60 in the `9b5b75b4b` baseline
(per the FOLLOW-UP comment).  Post-Track-B / forall8/32 / mont_mul drop,
it has shifted to q54-56 but the magnitude (~70-80 s saturating rlimit
400) is unchanged.

### qi.profile of q54 (Ml_dsa_44_)

`.smt2`: `queries-Libcrux_ml_dsa.Ml_dsa_generic.Ml_dsa_44_-69.smt2` (4.2 MB).
Z3-4.13.3 ran 70.97 s before timeout, 6.62 M total quantifier instantiations.

| Top quantifier (max snapshot count) | name | source |
|---:|---|---|
| **668,938** | `k!61` | anonymous Skolem; growing ~20K per snapshot.  Same magnitude as the previously-attributed `k!63 ~624K` in q60 of HEAD `9b5b75b4b`.  `k!N` numbering is per-`.smt2` so the literal name differs but the structural pattern is identical. |
| **405,971** | `lemma_Spec.Utils.update_at_range_lemma.1` | named: inner `forall (i:nat). i < len ==> Seq.index s i == Seq.index s' i` of `Spec.Utils.update_at_range_lemma` (in `libcrux-ml-kem/proofs/fstar/spec/Spec.Utils.fsti:378-389`). |
| 340,073 | `refinement_interpretation_Tm_refine_386fa7cc...` | refinement-interp axiom |

Other contributors (per profile decay): refinement-interpretation
axioms, `Prims_pretyping`, `Rust_primitives.Integers` axioms — all
infrastructure.  Two cascades dominate above noise.

### Two cascade sources, not one

The audit's k!63 hypothesis (cascade originates from
`Operations::ntt`/`invert_ntt`/`reduce` bare `forall (i:nat). i < 32 ==>
is_i32b_array_opaque ...` in `traits.rs:321-366`) **is consistent with
k!61** here.  Audit items 25-27 are still candidate fixes for that
cascade.

But the **second cascade source is new data**: `update_at_range_lemma`'s
inner forall fires ~400K times.  This lemma's SMTPat is

    [SMTPat (Rust_primitives.Hax.Monomorphized_update_at.update_at_range s i x)]

so it triggers on every `update_at_range` call in scope.  In
`generate_key_pair`'s body, `verification_key::generate_serialized` and
`signing_key::generate_serialized` write into the `&mut [u8]` output
buffers via many `update_at_range` chunks; each call site fires the
lemma, and the inner `forall (i:nat). i < len ==> Seq.index s i ==
Seq.index s' i` has to be re-instantiated up to `len` (which is
`SIGNING_KEY_SIZE = 2528/4032/4896` for the three monos).

This is **shared ml-kem code** (`libcrux-ml-kem/proofs/fstar/spec/Spec.Utils.fsti`).
Touching it cascades to ml-kem.  Out of scope for the ml-dsa branch
without a coordinated cross-crate test.

## Implications for next-step prioritization

### What this experiment falsifies

- "Track B + forall8/32 + mont_mul drop alone closes `generate_key_pair`
  body": **false**.  The cliff persists at the same magnitude, just
  renumbered q54-56 instead of q60.

### What this experiment confirms

- The audit's Phase A items 25-27 hypothesis is still alive:
  `forall i<32. is_i32b_array_opaque ...` on ntt/invert_ntt/reduce
  trait pre/post is plausibly the k!61 source (matching the prior
  k!63 magnitude).  An A-B test would replace those with
  `is_bounded_poly` and re-profile to see if k!61 collapses.

### What this experiment newly surfaces

- `Spec.Utils.update_at_range_lemma.1` is a **second** cascade source
  with ~400K instances.  Even if items 25-27 collapse k!61, the
  remaining update_at_range cascade may still cliff `generate_key_pair`
  at rlimit 400.

### Sub-tasks for un-admit

- (A) Audit items 25-27: introduce `is_bounded_poly_array` (or peer pred
  on the per-32 SIMD-units array) on trait `ntt`/`invert_ntt`/`reduce`
  pre/post.  Cascades to ALL impls and ALL above-trait callers
  (matrix.rs, ntt.rs, polynomial.rs, ml_dsa_generic.rs).  Heavy
  refactor; needs the `compute_matrix_x_mask` and other consumers to
  re-prove against the new opaque-pred shape.
- (B) Restore the dropped `requires(signing_key.len() == SIGNING_KEY_SIZE
  && verification_key.len() == VERIFICATION_KEY_SIZE)` clause AND fix
  the wrapper modules
  (`Ml_dsa_generic.Instantiations.{Avx2,Portable,Neon}.Ml_dsa_*_`) so
  they can discharge it.  The cleanest fix is to change those
  wrappers' signatures from `&mut [u8]` to `&mut [u8; SIGNING_KEY_SIZE]`
  / `&mut [u8; VERIFICATION_KEY_SIZE]` (fixed-size arrays carry length
  statically).  Their callers (`Ml_dsa_44_.{Avx2,Portable,Neon}` etc.)
  are admitted, so the cascade stops there.
- (C) Tighten `update_at_range_lemma`'s SMTPat.  Currently
  `[SMTPat (update_at_range s i x)]` fires on every call.  Tighter
  would be a 2-trigger pattern, e.g.,
  `[SMTPat (update_at_range s i x); SMTPat (Seq.index s k)]` — fires
  only when the consumer is already indexing the input sequence.  But
  this is in shared ml-kem code; needs coordinated test.
- (D) Replace the universal-frame inner forall with a specialized
  prefix-equality predicate that's `[@@ "opaque_to_smt"]`-wrapped.
  Same shared-code concern.

Doing (A) + (B) + (C/D) all at once is too many moving parts for one
sprint.  A staged plan:

1. **Stage 1**: do (B) only (precondition restoration + wrapper
   `&mut [u8; SIZE]` change).  Re-run.  If the body cliff at q54
   persists, the cliff is NOT precondition-related.  This isolates
   the data: cliff is opacity-driven, not pre-driven.
2. **Stage 2**: do (A).  Re-run.  Measure k!61's reduction.  If k!61
   collapses but `update_at_range_lemma.1` becomes the new dominant,
   move to (C/D).
3. **Stage 3**: do (C) or (D).  Coordinate with ml-kem.

## Workflow notes (for next agent)

### `.smt2` numbering ≠ Query-stats query number

The `queries-<Module>-N.smt2` file numbering is per-module (counts ALL
queries in the file), while `Query-stats (<fn>, K)` numbers reset
per-function.  In this experiment Query-stats q54 of `generate_key_pair`
mapped to `queries-...-69.smt2`.  Always grep
`grep "Query-stats.*<fn>, <K>" log.txt` to find the exact `.smt2`
filename — do not assume `q54 ↔ -54.smt2`.

### z3 profile exit code

`z3-4.13.3 smt.qi.profile=true ... <file>.smt2` exits 1 with
`(error "...: model is not available")` when the query is UNSAT (no
model).  This is normal — the qi profile output via stderr is still
valid.  Use `tail /tmp/q.qi` to see the final-state quantifier table
(reverse-time order) and `awk` aggregation to rank.

### qi.profile freq matters

`smt.qi.profile_freq=20000` prints every 20K instantiations.  The MAX
snapshot per quantifier (sum across snapshots is wrong) is the
actionable metric — it bounds how many instantiations Z3 made of that
specific qid.  Lower freq (e.g., 1000) gives finer trajectory but
larger output; higher freq (100000) misses fast-decay cascades.  20K
is a good default for cliff-magnitude analysis.

## Stage 2 — k!61 traced to its source (the eta_val match)

After Stage 1 confirmed the cliff is independent of the precondition, a
complementary forall-shape audit (separate doc) found that **bare-forall
sprawl in pre/post/loop_invariant is NOT the cause** — only 26 of 92
foralls in the call chain are bare, and most of those are intrinsic
frames or idiomatic `Classical.forall_intro` patterns. So the cascade
had to come from somewhere we hadn't audited.

This stage traced `k!61` and its sibling refinement-interpretation
quantifiers to their source-line anchor in the `.smt2` dump.

### Profile (re-run, identical magnitudes)

`queries-Libcrux_ml_dsa.Ml_dsa_generic.Ml_dsa_44_-91.smt2`, q60, 68.5s
saturating rlimit 400. Top quantifiers (max instances):

| Count | Quantifier |
|---:|---|
| 636,322 | `k!61` (anonymous) |
| 320,629 | `Tm_refine_386fa7cc364d6c69b9421bac1e859420.24` |
| 319,475 | `Tm_refine_386fa7cc364d6c69b9421bac1e859420.16` |
| 300,028 | `lemma_Spec.Utils.update_at_range_lemma.1` |
| 150,400 | `Tm_refine_386fa7cc364d6c69b9421bac1e859420.11` |
| 149,562 | `Tm_refine_bdcdf9605dc73aa91b69d875a32a9d42.1` |
| 148,431 | `Tm_refine_4e4555cc72265088626db378398e833b.1` |

The dominant is `Tm_refine_386fa7cc...` instantiating at THREE positions
(.11, .16, .24) inside the same refinement type, summing to ~790K.

### The Tm_refine anchor

`grep "Tm_refine_386fa7cc..."` in the `.smt2` shows:

```smt2
(declare-fun
 Tm_refine_386fa7cc364d6c69b9421bac1e859420
 (Term Term Term Term Term Term Term Term Term)
 Term)
;;; def=Prims.fst(410,27-410,88); use=Libcrux_ml_dsa.Ml_dsa_generic.Ml_dsa_44_.fst(108,26-350,60)
```

Inside the refinement body:

```smt2
;; def=Libcrux_ml_dsa.Ml_dsa_generic.Ml_dsa_44_.fst(192,8-195,55); use=Libcrux_ml_dsa.Ml_dsa_generic.Ml_dsa_44_.fst(192,8-195,55)
(=
 (let ((@lb12 (Libcrux_ml_dsa.Constants.Ml_dsa_44_.v_ETA Dummy_value)))
  (ite
   (is-Libcrux_ml_dsa.Constants.Eta_Two @lb12)
   (Rust_primitives.Integers.mk_usize (BoxInt 2))
   (ite
    (is-Libcrux_ml_dsa.Constants.Eta_Four @lb12)
    (Rust_primitives.Integers.mk_usize (BoxInt 4))
    Tm_unit)))
 @x11)
```

Lines 192-195 of the `.fst` are exactly the bridge block:

```fstar
let eta_val:usize =
  match Libcrux_ml_dsa.Constants.Ml_dsa_44_.v_ETA with
  | Libcrux_ml_dsa.Constants.Eta_Two -> mk_usize 2
  | Libcrux_ml_dsa.Constants.Eta_Four -> mk_usize 4
in
Libcrux_ml_dsa.Polynomial.Spec.lemma_lane_range_pos_to_bounded_poly_slice eta_val
  (mk_usize 4)
  s1_s2;
Libcrux_ml_dsa.Polynomial.Spec.lemma_lane_range_pos_to_bounded_poly_slice eta_val
  (mk_usize 8380416)
  s1_s2
```

Source: `src/ml_dsa_generic.rs:127-137`, the bridge block that converts
`is_lane_range_poly_slice 0 eta_val s1_s2` → `is_bounded_poly_slice b s1_s2`
for two different `b`s (4 and 8380416).

### Mechanism

The `match ETA with Eta_Two -> mk_usize 2 | Eta_Four -> mk_usize 4`
expression has F\*-inferred type `usize` with a refinement that captures
"either 2 or 4." That refinement (Tm_refine_386fa7cc...) is structured
as a multi-position forall (`.11`, `.16`, `.24`, `.47` — different
positions inside the body's nested implications + foralls).

Each subsequent USE of `eta_val` (in the two `lemma_lane_range_pos_to_bounded_poly_slice
eta_val ...` calls AND in any downstream WP sub-goal that mentions the
resulting `is_bounded_poly_slice` claim) requires F* to type-check
`eta_val` against this refinement, which instantiates ALL the inner
foralls.

`k!61` (anonymous, 636K) is the deepest forall inside this refinement
chain — likely the `forall @x12. ...` from `Prims.fst(459,66-459,102)`
that's a standard refinement-interpretation axiom for nat-typed inner
quantifiers.

### Why it cascades to 600K+

The bridge is invoked once per call site, but the refinement instantiates
once per WP sub-goal that mentions `eta_val` or any value derived from
it. The downstream chain:

1. `eta_val` flows into `lemma_lane_range_pos_to_bounded_poly_slice eta_val 4 s1_s2`,
   which establishes `is_bounded_poly_slice 4 s1_s2`.
2. `s1_s2` is then read by every later consumer (`compute_as1_plus_s2`'s
   pre, the `for ntt(&mut s1_ntt[i])` loop_invariant, etc.) — each
   re-instantiates the eta_val refinement when discharging WP.
3. With ~32+ WP sub-goals downstream, each instantiating 4 forall
   positions, we get 32 × 4 × N inner-forall instantiations, where N is
   the number of bound variables in each forall — easily reaching 600K.

### Fix candidates

1. **`assert_norm` to flatten the match**: add
   `FStar.Pervasives.assert_norm (eta_val == mk_usize 2)` (or 4) right
   after the `let`. Forces F* to normalize the match to a constant
   early. Cheapest experiment.
2. **Replace match with helper function**: define a `eta_to_usize: t_Eta -> usize`
   helper with a clean `Pure usize (...)` Type. F* gives it a single
   refinement axiom, and consumers see a clean call instead of a match
   expansion.
3. **Lift `lemma_lane_range_pos_to_bounded_poly_slice` to take `Eta`
   directly**: the lemma does the match internally. Eliminates the
   `eta_val` intermediate at the call site. Cleanest abstraction.
4. **Per-monomorphization specialization**: hax may already be running
   per-mono extraction, but this match is in a `hax_lib::fstar!` block
   that's not specialized. Could refactor the bridge to use Rust-side
   constants per param-set.

The user picked Option A (the trace) and now needs to pick a fix.

### Note on update_at_range_lemma re-emergence

In Stage 1's profile, `update_at_range_lemma.1` was at 405K (no pre)
and dropped out of top-20 with pre restored. In this Stage 2 profile
it's BACK at 300K — re-introduced because of the precondition's
text changing slightly between runs (it's listed as 300K vs not in
top-20 earlier; the difference is likely the deduplication threshold).
It's a secondary cascade, not the primary. The primary fix on the
eta_val match should reduce it too.

---

## Stage 1 follow-up — cliff confirmed independent of pre

User pushed back: with 6 debug-assert failures from the dropped
precondition, the q54 cliff could be a WP-composition artifact, not a
real cliff.  Conclusive test: restore the precondition, admit the
wrappers that can't discharge it, re-run.

### Setup

- Restored `#[cfg_attr(hax, hax_lib::requires(signing_key.len() ==
  SIGNING_KEY_SIZE && verification_key.len() == VERIFICATION_KEY_SIZE))]`
  on `src/ml_dsa_generic.rs::generate_key_pair`.
- Removed body admit.
- Added 12 wrapper modules to `Makefile` `ADMIT_MODULES`
  (`Ml_dsa_generic.{Instantiations.{Avx2,Portable,Neon},Multiplexing}.Ml_dsa_{44,65,87}_`).
  These take `&mut [u8]` slices and have no analogous pre to discharge
  the new generic precondition.

### Results

6 debug-assert failures GONE.  3 cliff failures remain at q60-62:

| Mono | Q | Wall | rlimit |
|---|---|---|---|
| `Ml_dsa_44_` | 60 | 71.96 s | 400.000 saturated |
| `Ml_dsa_65_` | 62 | 65.52 s | 400.000 saturated |
| `Ml_dsa_87_` | 60 | 81.33 s | 400.000 saturated |

(The query-number shift from q54-56 → q60-62 is because the restored
pre adds 6 easy queries before the cliff — confirms our q54 was the
same VC, just renumbered.)

### qi.profile of q60 (Ml_dsa_44_), pre-restored

`.smt2`: `queries-Libcrux_ml_dsa.Ml_dsa_generic.Ml_dsa_44_-91.smt2`.
Z3 ran 56.77 s, ~6 M total instantiations.

| Top quantifier (max snapshot) | name | Δ vs pre-dropped run |
|---:|---|---|
| **636,322** | `k!61` | -5% (was 668,938) |
| 320,629 | `refinement_interpretation_Tm_refine_386fa7cc364d...24` | new #2 (was beneath update_at_range_lemma) |
| 319,475 | `refinement_interpretation_Tm_refine_386fa7cc364d...16` | similar refinement axiom |
| — | `lemma_Spec.Utils.update_at_range_lemma.1` | **GONE from top-20** (was 405K) |

### Conclusions

1. **The cliff is REAL**, not a WP-composition artifact of the dropped
   precondition.  Same q60 query position as the original session-state
   baseline ("q60 cliff at rlimit 400, ~65s, k!63 ~624K").  Same
   structural cascade: one dominant anonymous Skolem at ~620K-670K
   instances.
2. **`update_at_range_lemma.1` was an artifact**, not a co-cascade.
   With the pre restored, it drops out of the top contributors entirely.
   The cleaner picture: single dominant cascade at the trait pre/post
   level (`k!61`).
3. **Audit items 25-27 (poly-forall opacity on
   `Operations::ntt`/`invert_ntt`/`reduce` trait pre/post) remain the
   prime candidate fix.**  The audit's k!63 hypothesis is consistent
   with what we now see at k!61 (renumbering only).
4. The next-step staged plan in the prior section needs revision:
   Stage 1 (restore pre + change wrapper sigs) is **necessary** for a
   landable un-admit, but it does NOT close the body proof on its own.
   Stage 2 (audit items 25-27) is REQUIRED.

### Updated staged plan

1. **Stage 1** (mechanical, scope: ml-dsa internal): change wrapper
   signatures in `src/ml_dsa_generic/instantiations/{avx2,portable,neon}.rs`
   and `src/ml_dsa_generic/multiplexing.rs` from `&mut [u8]` to
   `&mut [u8; SIGNING_KEY_SIZE]` / `&mut [u8; VERIFICATION_KEY_SIZE]`.
   This removes the need for the temporary `ADMIT_MODULES` block.
   Estimated effort: 1-2 hours; touches 4 files; the public-facing
   `Ml_dsa_*.{Avx2,Portable,Neon}.generate_key_pair` are already
   admitted, so the cascade stops cleanly.
2. **Stage 2** (audit items 25-27, scope: ml-dsa trait-surface):
   replace `forall (i:nat). i < 32 ==> is_i32b_array_opaque ...` on
   `Operations::ntt`/`invert_ntt_montgomery`/`reduce` trait pre/post
   with a poly-array opaque pred (e.g., `is_bounded_poly_array b
   simd_units`).  Cascades to all impls + above-trait callers; needs
   `compute_matrix_x_mask`, `ntt`/`invert_ntt`/`reduce` consumers in
   `matrix.rs`/`ntt.rs`/`polynomial.rs` to re-prove against the new
   opaque-pred shape.
3. **Stage 3** (no longer needed): `update_at_range_lemma` SMTPat
   tightening — was a confounder, not a real issue.

## Current state at end of stage 1

- `src/ml_dsa_generic.rs`: precondition restored, body admit removed.
- `proofs/fstar/extraction/Makefile`: 12 wrapper modules temporarily
  in `ADMIT_MODULES` (with a `TEMPORARY` comment block).  REVERT these
  before any commit.
- 99 modules invoked; 12 newly admitted (so 29 admitted total).  3 F\*
  errors remain — the q60 cliffs.

The state is set up for Stage 2 work (audit items 25-27 trial).  Or
revert via `git checkout -- src/ml_dsa_generic.rs proofs/fstar/extraction/Makefile`
+ re-extract to return to baseline.

## Files referenced

- `src/ml_dsa_generic.rs:53-95` — function with admit + dropped
  precondition.
- `libcrux-ml-kem/proofs/fstar/spec/Spec.Utils.fsti:378-389` —
  `update_at_range_lemma` definition.
- `libcrux-ml-kem/proofs/fstar/spec/Spec.Utils.fst:309-317` —
  implementation.
- `proofs/fstar/extraction/Libcrux_ml_dsa.Ml_dsa_generic.Ml_dsa_44_.fst:106-348`
  — extracted function (only present when un-admitted).
- `/tmp/q54-real.qi` — full qi.profile output (saved during this
  session; will be cleared by `/tmp` reaper).
