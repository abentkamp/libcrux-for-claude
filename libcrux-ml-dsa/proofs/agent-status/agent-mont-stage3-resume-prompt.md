Branch ml-dsa-proofs at tip a2e75df3d (Stage 3 closed via revert).
Per-function 30–60 min budget; ASK before any Montgomery-touching change.

STATUS UPDATE (2026-05-03):

Stage 3 closed by REVERTING Stage 2's bound/mod_q over-engineering on
the AVX2 free fns (commit a2e75df3d).  The "incomplete quantifiers"
verification gap was the result of Stage 2 enlarging the SMT context
in a way that broke Stage 0's SMTPat-driven equality proof; stale
`.checked` masked the regression at Stage 2 commit time.

Current state:
* `simd/avx2/arithmetic.rs::montgomery_multiply_by_constant`,
  `montgomery_multiply_aux`, `montgomery_multiply` — posts back to
  upstream-shape per-lane mont_mul equality only; bodies = single
  `reveal_opaque mont_red`.  No aux helpers, no Classical.forall_intro.
* AVX2 trait impl (`simd/avx2.rs::montgomery_multiply`) does the
  bridge: takes the equality, calls `lemma_mont_mul_bound_and_mod_q`
  per-lane via `Classical.forall_intro pf` to derive bound + mod_q +
  lane_post.  Verifies clean (112s).
* AVX2 invntt + ntt: deps satisfied, up-to-date.
* cargo test: 20/20.

ARCHITECTURAL LESSONS LEARNED (codified in memory):
* `feedback_smtpat_lane_propagation`: SIMD-internal posts = per-lane
  equality + ONE reveal.  Don't add bound/mod_q clauses + aux helpers
  at this layer — it breaks SMTPat propagation through the SIMD chain.
  Bound/mod_q derivations belong at the trait/caller boundary.
* `feedback_per_stage_clean_rebuild`: each stage of a multi-stage
  refactor must re-verify from a clean .checked of the touched modules
  before claiming "verified clean" in the commit message.  Otherwise
  silent regressions compound.
* `feedback_no_checked_tampering`: never touch .checked mtimes.

REMAINING WORK (in priority order):

1. PORTABLE Mont revert (DEFERRED).
   `src/simd/portable/arithmetic.rs` has the same Stage-2
   over-engineering: bound + mod_q clauses in posts of
   `montgomery_multiply_fe_by_fer`, `montgomery_multiply_by_constant`,
   `montgomery_multiply`, with `lemma_mont_mul_bound_and_mod_q` calls
   inside loop bodies and bound clauses in loop_invariants.

   Revert to "post = just per-lane equality" requires ALSO updating
   `src/simd/portable.rs::montgomery_multiply_with_proof` (the trait
   wrapper) to invoke `lemma_mont_mul_bound_and_mod_q` per-lane —
   same pattern as the AVX2 trait impl bridge.

   Current portable proofs work; the revert is architectural cleanup,
   not blocking.  Defer to a dedicated sprint.

2. STAGE 4: tighten `invert_ntt_montgomery` post.
   Goal: from `is_i32b_polynomial FIELD_MAX` to
   `is_i32b_polynomial 4_211_177` (= q/2 + ⌈256·FIELD_MAX·41978/2³²⌉).

   Files:
   * `src/simd/portable/invntt.rs::invert_ntt_montgomery` (lines ~500-519)
   * `src/simd/avx2/invntt.rs::invert_ntt_montgomery`
   * `src/simd/traits.rs::Operations::invert_ntt_montgomery`
   * `src/ntt.rs::invert_ntt_montgomery` (polynomial wrapper)

   ARCHITECTURAL DESIGN QUESTION (not yet decided):
   Per the new SMTPat principle, the avx2-invntt SIMD-internal layer
   should not use `Classical.forall_intro aux` to derive bounds.  But
   the existing `lemma_mont_red_bound_*` lemmas in `Spec.MLDSA.Math`
   are plain lemmas without SMTPats.  Two options:
   (a) Add SMTPats to the bound lemmas.  Bodies expose only `is_i32b`
       (no raw `%`), so this should be safe per
       `feedback_smtpat_percent_above_trait`.  SMTPat trigger:
       `mont_red value` (when precondition holds).  Risk: per-lane
       saturation if the SMTPat fires in too many contexts.
   (b) Keep lemmas plain; use `Classical.forall_intro` at the trait
       boundary (`simd/avx2.rs::invert_ntt_montgomery`) only.  The
       SIMD-internal `simd/avx2/invntt.rs::invert_ntt_montgomery` keeps
       its existing minimal post and lets the trait-impl bridge derive
       the tighter bound via lemma calls.

   Decide (a) or (b) before execution.  Recommend starting with (b) —
   matches the proven AVX2 montgomery_multiply pattern.

3. STAGE 5: update `Operations::invert_ntt_montgomery` trait post to
   `is_i32b_array_opaque 4_211_177`.  Both impls must satisfy.

4. STAGE 6: update polynomial wrapper `Ntt::invert_ntt_montgomery` to
   mirror the trait's tighter bound.

5. STAGE 7: global verify — `JOBS=4 ./hax.sh prove` 0 errors,
   `cargo test --release --lib` 20/20.

WORKFLOW RULES (carried forward):
* Use `./hax.sh extract` from `libcrux-ml-dsa/`, NOT `cargo hax`.
* `.fst`/`.fsti` files are gitignored — edits reach F* via re-extraction.
* `make check/<Module>.fst` (from `proofs/fstar/extraction/`) builds
  a single .checked file.
* After hax extract, delete `Libcrux_ml_dsa.Types.Non_hax_impls.fst`
  (workaround for hax filter bug).
* ASK before any Montgomery-touching change.
* Per-stage CLEAN REBUILD: delete `.checked` for touched modules and
  re-make before claiming verified.
* SIMD-internal posts: just per-lane equality + one reveal.

DO NOT:
* Push to origin.
* Bulk-delete or otherwise tamper with `.checked` files (touch mtimes).
* Set --z3rlimit > 800.
* Add `Classical.forall_intro aux` patterns inside SIMD-internal
  arithmetic functions (use them only at trait boundaries).
