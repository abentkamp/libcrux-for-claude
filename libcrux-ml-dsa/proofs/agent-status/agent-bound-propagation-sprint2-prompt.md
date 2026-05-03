# Sprint 2 launch prompt — agent-bound-propagation

Use this prompt when launching the Sprint 2 agent (after Mon's user
decisions land — see `sprint-plan-2026-05-03.md`).

---

```text
You are agent-bound-propagation (Sprint 2).  Picking up libcrux-ml-dsa
after Sprint 1 (Montgomery spec foundation + invntt-post tightening)
landed.  Branch: ml-dsa-proofs.  Tip: 08e731129 (or refresh from
`git log -1` if Mon's user decisions added commits).

WORK TREE

Use a fresh worktree off ml-dsa-proofs.  Don't push.
Status log at `libcrux-ml-dsa/proofs/agent-status/agent-bound-propagation-status.md`.
Status reports every 15 min.

CONTEXT (read in order, then begin)

1. `proofs/agent-status/sprint-plan-2026-05-03.md` — current sprint
   plan, Tue is Sprint 2's first agent-driven day.
2. `proofs/agent-status/power2round-refactor-decision.md` — Mon's
   user decision.  Determines whether `power2round_vector` is in
   scope or admitted.
3. `proofs/agent-status/trait-correctness-post-design-draft.md` — Mon's
   user draft (if present).  Sprint 2 doesn't change the trait, but
   the draft hints at how week-2 trait design will land.
4. `proofs/handoff-2026-05-02-mont-bound-foundation.md` — sprint design
   doc; §"Sprint 1 partial outcome" + §"Sprint 1 remaining work" +
   §"Sprint 2 prompt skeleton" describe what's now landed.
5. `proofs/agent-status/agent-proof-review-2026-05-03.md` — broader
   admit/lax inventory; section 2 ("Above-trait admits") is the
   target list for this sprint.
6. `~/.claude/projects/-Users-karthik-libcrux/memory/MEMORY.md` and
   especially `feedback_smtpat_lane_propagation`,
   `feedback_per_stage_clean_rebuild`, `feedback_no_checked_tampering`,
   `feedback_proof_debug_budget` — recent rules from the Mont sprint.

CONCRETE ARTEFACTS FROM SPRINT 1

Spec layer (in `proofs/fstar/spec/Spec.MLDSA.Math.fst`):

* `mont_red (value: i64) : i32` — opaque single-arg Montgomery reduce.
* `mont_mul (x y: i32) : i32` — non-opaque, body = `mont_red (i32_mul x y)`.
* `lemma_mont_red_bound_internal (n: nat) (value: i64)` — parametric
  bound: `is_i64b n value /\ n <= FIELD_MAX·2³² ⇒ is_i32b (4190209 + n/2³²) (mont_red value)`.
* Specialized lookup lemmas (each one-line `assert_norm` from the
  parametric one):
  - `lemma_mont_red_bound_field_max_times_pow2_32` → `is_i32b 12_570_625 (mont_red value)`
  - `lemma_mont_red_bound_q_squared`               → `is_i32b 4_206_561  (mont_red value)`
  - `lemma_mont_red_bound_field_max_times_pow2_31` → `is_i32b 8_380_417  (mont_red value)`
  - `lemma_mont_red_bound_field_max_times_41978`   → `is_i32b 4_190_290  (mont_red value)`
  - `lemma_mont_red_bound_256_field_max_times_41978` → `is_i32b 4_211_177 (mont_red value)`

Trait layer (in `src/simd/traits.rs`):

* `Operations::invert_ntt_montgomery` post NOW =
  `forall i. i < 32 ==> Spec.Utils.is_i32b_array_opaque 4211177 (f_repr (Seq.index simd_units_future i))`
  (was: `is_i32b_array_opaque (v FIELD_MAX)`).

Polynomial-wrapper layer (in `src/ntt.rs`):

* `Ntt::invert_ntt_montgomery` post NOW =
  `is_i32b_array_opaque 4211177` (matching the trait).

Per-lane / vector arithmetic layer (in `src/simd/{avx2,portable}/arithmetic.rs`):

* `montgomery_multiply{,_aux,_by_constant}` post = per-lane `mont_mul`
  equality only (Sprint 1 architecture: no bound/mod_q clauses on the
  free fn; the trait impl method bridges via
  `Hacspec_ml_dsa.Commute.Chunk.lemma_mont_mul_bound_and_mod_q` per lane).

GOAL FOR SPRINT 2

Lift the new tight `is_i32b_array_opaque 4211177` post into above-trait
consumer body proofs that need it.  Do NOT touch the trait layer or
spec — Sprint 1 closed those.

TASKS (in priority order; per-function 30-60 min hard cap)

TASK 1 — compute_as1_plus_s2 body proof (the headline)

    File: `src/matrix.rs` (around line 44, body marked `hax_lib::fstar!("admit ()")`).

    1.1 Remove the body `admit ()`.
    1.2 Tighten the function's declared post — currently
        `is_i32b 16760832` (== 2*FIELD_MAX) — to
        `is_i32b_array_opaque (v FIELD_MAX)` per simd_unit.  The
        chain naturally delivers something closer to 4_211_181 but
        FIELD_MAX is the right caller-facing bound (callers expect
        FIELD_MAX for `power2round_vector`'s precondition).
    1.3 Add loop_invariants for the nested loops following the
        `add_vectors` recipe (rlimit 800 + split_queries always,
        snapshot frame, per-iteration bound tracking).  Outer loop's
        body invariant tracks unprocessed-suffix == orig and
        processed-prefix satisfies the post bound.
    1.4 The KEY chain composition (different from the old Class B
        Chain 3 attempt that hit hax tactic limits):
            invert_ntt_montgomery output          ← NOW gives
              is_i32b_array_opaque 4211177        ← from Sprint 1
              ⇒ per-lane is_i32b 4_211_177
              ⇒ + s2 (eta-bounded, |eta| ≤ 4)     ← `add` post
              ⇒ |result| ≤ 4_211_181
              ⇒ trivially is_i32b FIELD_MAX (8_380_416)
        NO in-function reduce needed.  NO add_bounded substitution
        (existing per-lane `add` works).  Use
        `Spec.Utils.is_i32b_array_larger 4211177 (v FIELD_MAX) …` to
        widen if the loop_invariant bound shape differs from
        `add`'s post shape.
    1.5 If a hax slice-bounds tactic limitation re-fires (Tactic
        failed at slice access in nested loops — Chain B's old
        blocker), STOP and consult parent.  Possibly the new tighter
        post lets a clever invariant shape dodge it; possibly it's
        still blocking and needs the dual-mutable refactor.
    1.6 Re-extract.  Per-stage clean rebuild: delete
        `.fstar-cache/checked/Libcrux_ml_dsa.Matrix.fst.checked` then
        `make check/Libcrux_ml_dsa.Matrix.fst` to confirm fresh
        verification (don't trust cached `.checked`).
    1.7 cargo test --release --lib --manifest-path libcrux-ml-dsa/Cargo.toml — 20/20.
    1.8 Commit selectively: matrix.rs only.
        Title: `ml-dsa: panic-free body proof for compute_as1_plus_s2`.

TASK 2 — compute_w_approx body proof

    File: `src/matrix.rs` (around line 296).
    Same shape as Task 1.  Same 30-60 min cap.  Commit separately.

TASK 3 — compute_matrix_x_mask body proof

    File: `src/matrix.rs` (around line 105).
    Same shape.  May be skipped if Tasks 1-2 take too long.

TASK 4 (OPTIONAL) — re-prove vector_times_ring_element

    File: `src/matrix.rs` (around line 142).  Currently
    `hax_lib::fstar!("admit ()")` — added during Sprint 1 as a
    Z3-saturation casualty.  Body is small (one nested loop calling
    `ntt_multiply_montgomery` then `invert_ntt_montgomery`).  After
    Tasks 1-3 patterns are working, re-attempting this should be
    short.  The post can stay `is_i32b_array_opaque (v FIELD_MAX)`
    (callers expect FIELD_MAX; widen from 4211177 inside the loop).

OUT OF SCOPE — DO NOT TOUCH

* `arithmetic.rs::power2round_vector` body — different blocker
  (hax dual-mutable slice tactic).  Refactor decision is in Mon's
  user decision doc.  If decision was "refactor", a separate Wed
  agent will handle it; this agent does not.
* `ml_dsa_generic.rs::{generate_key_pair, sign, verify, *_internal}` —
  panic-free flip is Thu/Fri after this sprint AND
  power2round_vector close.
* `sample.rs::*` — Wed sprint targets.
* Spec layer (`proofs/fstar/spec/`) — closed.
* `simd/{avx2,portable}/arithmetic.rs` — closed (Sprint 1).
* `simd/traits.rs`, `simd/avx2.rs`, `simd/portable.rs` — closed.

HARD RULES

* rlimit cap: NEVER --z3rlimit > 800 (or > 400 with --split_queries always).
* Per-function 30-60 min hard cap.  Mark and move on.
* NEVER touch `.checked` files (mtime, delete, copy).  See
  `feedback_no_checked_tampering`.
* NEVER bulk-delete `.fstar-cache`.
* Per-stage clean rebuild before claiming "verified clean": delete
  the touched module's `.checked` then `make check/<Module>.fst`.
  See `feedback_per_stage_clean_rebuild`.
* DO NOT push to origin.
* Status reports every 15 min in
  `proofs/agent-status/agent-bound-propagation-status.md`.

DECISION POINTS — STOP AND CONSULT PARENT

* Hax tactic limitations re-fire (Tactic failed errors in nested loops).
* rlimit > 800 needed.
* New spec change needed (would mean Sprint 1 missed something).
* Cascade timeout in a previously-verified function (similar to
  `add_vectors` timeout that surfaced during Chain 3).
* Trait post needs changing (would mean Sprint 1 over-tightened).

SUCCESS CRITERION

* Task 1 (`compute_as1_plus_s2`) body verified, post tightened.
* (Strong stretch) Tasks 2-3 (`compute_w_approx`, `compute_matrix_x_mask`)
  body verified.
* (Optional) Task 4 (`vector_times_ring_element`) re-proved.
* `JOBS=4 ./hax.sh prove` 0 errors.
* `cargo test --release --lib` 20/20 pass.
* Status log committed.

After success criterion met, end your turn with a one-page summary of
what landed + what remains for Sprint 3 (power2round_vector + the
`generate_key_pair` panic-free flip).
```
