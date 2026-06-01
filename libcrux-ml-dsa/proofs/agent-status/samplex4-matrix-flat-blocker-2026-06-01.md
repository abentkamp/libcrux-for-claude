# samplex4 un-lax — matrix_flat panic-freedom blocker (2026-06-01)

Status: **samplex4 reverted to admitted (green)** after the API tier (ml_dsa_44/65/87)
was un-laxed and committed (`e7a1b7eff`). matrix_flat could not be closed; this note
records the precise diagnosis so a future session can resume without re-deriving it.

## Goal
Drop the 4 `Libcrux_ml_dsa.Samplex4*` modules from `ADMIT_MODULES`. They carry real
ensures (`is_bounded_poly_slice 8380416 matrix_future`, via the admitted
`sample_up_to_four_ring_elements_flat` post) — the bounds ensures DISCHARGES; the
blocker is **panic-freedom** of `matrix_flat`'s `(0..matrix.len()).step_by(4)` loop.

## Obligations found (in order), and status
1. **`step_by(4)` overflow** — `fold_range_step_by` needs `range (v(len matrix) + 4) USIZE`.
   FIX (SOUND, verified true at all call sites): add to free-fn `matrix_flat` AND the
   `X4Sampler::matrix_flat` trait method:
   `#[hax_lib::requires(matrix.len() <= 256)]`
   Confirmed: every call site passes `[_; ROW_X_COLUMN]` with
   `ROW_X_COLUMN = ROWS_IN_A * COLUMNS_IN_A ∈ {16,30,56}` (ml_dsa_generic.rs:33;
   constants 4×4 / 6×5 / 8×7). All 3 callers (generate_key_pair:142, sign_internal:268,
   verify_internal:512) are in the admitted keygen cone, so the precondition is
   genuinely true (not vacuous) and discharges trivially when the cone is un-laxed.
2. **`tmp_stack` length rebind** — `tmp_stack: &mut [[i32;263]]` (slice, length-erased)
   passed to `sample_up_to_four_ring_elements_flat`, then rebound to `[[i32;263];4]`.
   FIX (SOUND, vacuous via that fn's `admit()` body, and genuinely true — it writes
   elements, never resizes): add a conjunct to `sample_up_to_four_ring_elements_flat`'s
   ensures: `/\ Seq.length ${tmp_stack}_future == Seq.length $tmp_stack`.
3. **`matrix.len() - start_index` underflow** (else-branch of `elements_requested`),
   plus the `start_index + 4` overflow in the if-condition. Needs `start_index <= len`.
   **BLOCKED — see below.**

## The blocker (obligation 3)
The fold body has the bound `v start_index < v len - ((v len - 1) % 4)` (from
`fold_range_step_by`'s `f` param refinement). In ISOLATION F* proves
`range (v len - v start_index) USIZE` from this automatically (verified in a scratch
session, even with `--ext context_pruning`). BUT hax extracts the body as:
    (fun temp_0_ start_index -> ... let start_index:usize = start_index in ...)
The `let start_index:usize = start_index` **rebind erases the refinement** — after it,
F* has only `start_index: usize` with no `< len` bound, so the underflow can't discharge.

### Things tried (all FAILED for obligation 3)
- inline `assert (v start_index <= v len)`  → "incomplete quantifiers" (bound absent).
- `--ext context_pruning=false` (note: non-empty value does NOT disable the ext) → no change.
- `--ext context_pruning=` (empty value, the real disable) + `--z3rlimit 150` → still
  "incomplete quantifiers". So it is NOT pruning; the refinement is genuinely gone.
- `hax_lib::loop_invariant!(|start_index| v start_index <= v len)` → invariant MAINTENANCE
  fails: the fold checks the inv at `i + 4`, which overshoots `len` (e.g. last index +4 > len),
  so `<= len` is not an inductive invariant for step-4. (Works for matrix.rs only because
  those are step-1 `fold_range` loops where `i+1 <= len` follows from `i < len`.)
  No maintainable invariant yields the tight per-index `< len` the body needs.

## Why it is genuinely hard
The tight bound `start_index < len` is a PER-INDEX fact (from the fold contract), not an
inductive invariant (the step-4 stride overshoots `len` on the maintenance check). The
only carrier of the per-index fact is the `f`-param refinement, which hax's index-rebind
discards. Neither lever (invariant / refinement) is available after extraction.

## Recommended next steps (pick one)
- **hax-level fix** (best): stop emitting `let start_index:usize = start_index` for
  step_by loop indices, or have it preserve/re-assert the index refinement. Upstream.
- **custom step_by index lemma**: a lemma `(len i:usize) -> Lemma (requires <fold wf for i>)
  (ensures v i < v len)` plus a hax hook to inject it where the refinement is still live
  (no such hook today — loop_invariant! and fstar! both land AFTER the rebind).
- **defer** until one of the above lands.

## To resume
Re-apply fixes (1) and (2) above (both sound, ~3 small edits), drop the 4 Samplex4 lines
from `proofs/fstar/extraction/Makefile` ADMIT_MODULES, then tackle obligation 3 via one of
the recommended routes. sample_s1_and_s2 and the Avx2/Neon/Portable dispatchers already
verified once obligations 1–2 were in place; only matrix_flat's obligation 3 remains.
