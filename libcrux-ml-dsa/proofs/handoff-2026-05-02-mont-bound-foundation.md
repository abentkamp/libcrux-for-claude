# Handoff — Montgomery-bound spec foundation + propagation (two-sprint plan)

You are picking up libcrux-ml-dsa after the Class B sprint
(`handoff-2026-05-01-class-b-bounds.md` postmortem section)
partially landed.  Tip: `2054c9f15`.

**Prior context to read in order:**

1. `handoff-2026-05-01-class-b-bounds.md` — postmortem section at
   the end documents what landed (Chain 1) and why Chain 3 blocked.
2. `agent-status/agent-arith-bound-status.md` — full diagnostic of
   the hax tactic limitation that blocked Chain 3.
3. `agent-status/agent-ntt-bound-status.md` — Chain 1's surface
   (now-merged `is_pos_array_opaque eta` ensures on
   `sample_s1_and_s2`, etc.).
4. The `Spec.MLDSA.Math.fst` and `Simd.Traits.Specs.fst` files —
   the two layers this sprint touches.

The strategic insight from the Chain 3 postmortem: **the body
proofs we couldn't land are blocked because the upstream trait
post on `invert_ntt_montgomery` is loose (`is_i32b FIELD_MAX`,
~2× looser than empirically observed).  Tightening it makes the
consumer body proofs easier and dodges the hax tactic edge cases
we hit.**

This handoff covers two sprints:

* **Sprint 1 — Montgomery spec foundation (collaborative).**
  Add `mont_red` to `Spec.MLDSA.Math`, prove tight bound lemmas,
  align portable + avx2 + trait on the canonical spec functions,
  expose tight bounds via opaque predicate + specialized lemmas.
  Driven stage-by-stage with the user; each stage stops for review.

* **Sprint 2 — Bound propagation (autonomous).**
  Lift the new tight `invert_ntt_montgomery` post into consumers
  (`compute_as1_plus_s2`, possibly `compute_w_approx` /
  `compute_matrix_x_mask`).  Mechanical once Sprint 1 lands.

The end-state of Sprint 2 is the input to a third sprint that
finally lands the `generate_key_pair` panic-free flip — that
needs both `compute_as1_plus_s2` (from Sprint 2) AND
`power2round_vector` (a separate refactor), so it's deferred.

## What changed structurally since `handoff-2026-05-01-class-b-bounds.md`

* Chain 1's ensures-only surfacing on `sample.rs` / `samplex4.rs`
  is **merged** at tip `140702ee2`.  Coefficient bounds are now
  callable upstream (`is_pos_array_opaque eta` on
  `sample_s1_and_s2`'s output, `is_i32b_array_opaque FIELD_MAX`
  on `matrix_flat`'s output).
* New memory rule: per-function 30–60 min hard cap on
  proof-debug iteration; mark and move on.  Codified in
  `~/.claude/projects/.../feedback_proof_debug_budget.md`.
* Trait audit (read-only, 2026-05-02) classified all 27
  `Operations` methods against the 3-part pattern:
  bounds-and-lengths-pre + bounds-post + correctness-post.
  Result: 5 already compliant, 8 drive-by candidates, 10
  follow-up candidates.  Detail in §"Trait pattern audit
  results" below.

---

## Architectural pattern (codifying for this sprint and future ones)

Every trait method in `simd/traits.rs::Operations` should declare
three things in its `requires` / `ensures`, written in Rust at
the call site:

1. **Bounds-and-lengths precondition** — usually NOT opaque;
   uses `bounded_i32_array` / `is_i32b_array_opaque` / length
   predicates.  States caller obligations on the input.

2. **Bounds postcondition** — uses `bounded_i32` /
   `is_i32b_array_opaque`.  States the magnitude guarantee on
   the output.  Often expressed via an opaque predicate
   (`mont_red_bound`, `mont_mul_bound`, `reduce_lane_post`)
   so callers reason via lemmas, not formulas.

3. **Correctness postcondition** — links the output to a
   Hacspec or `Spec.MLDSA.Math` correctness function (e.g.,
   `mod_q (v result) == mod_q (v input * MONTGOMERY_R⁻¹)`,
   or per-lane lookup against
   `Spec.MLDSA.Math.power2round`).  States what
   mathematical operation the function performs.

The Sprint 1 work surfaces bounds-post for `montgomery_multiply`
and `invert_ntt_montgomery` via the new `mont_red_bound` /
`mont_mul_bound` opaque predicates, mirroring the pattern that
`reduce_lane_post` and `shift_left_then_reduce_lane_post`
already follow.

The other 6 drive-by trait methods (`add`, `subtract`,
`shift_left_then_reduce`, `zero`, `from_coefficient_array`,
`to_coefficient_array`) are **out-of-scope for Sprint 1**.  A
separate "trait pattern cleanup" sprint should batch them.

---

## Sprint 1 — Montgomery spec foundation (collaborative)

**Goal**: portable + avx2 + trait converge on canonical
`Spec.MLDSA.Math.mont_mul` + new `Spec.MLDSA.Math.mont_red` spec
functions, with opaque-predicate-based tight bounds and
specialized lemmas for common input shapes.

**Driving model**: stage-by-stage with the user.  Each stage
stops, reports, and waits for "go" / "redirect" before the next.
Hard 30-min budget per function on body-proof debugging.  All
work in a fresh worktree.

### Stage 0 — Define `mont_red` in `Spec.MLDSA.Math.fst`

Mirror `mont_mul`'s structure (`Spec.MLDSA.Math.fst:36-42`).
`mont_red` is the canonical Montgomery reduction taking `i64`
input and returning `i32`, computing `value · 8265825 mod q`
via the same hi/lo arithmetic the implementations use.

```fstar
[@@ "opaque_to_smt"]
let mont_red (value: i64) : i32 =
  let k : i32 = cast_mod_opaque (i32_mul (cast_mod_opaque value <: i32)
                                          (mk_i32 58728449)) in
  let c : i32 = cast_mod_opaque (shift_right_opaque
                                  (i32_mul k (mk_i32 8380417))
                                  (mk_i32 32)) in
  sub_mod_opaque (cast_mod_opaque (shift_right_opaque value (mk_i32 32)))
                 c
```

(Exact form to be refined during implementation; the constraint
is that this match the body of `simd/portable/arithmetic.rs::montgomery_reduce_element`.)

Pure spec addition.  Verify `Spec.MLDSA.Math.fst` F* checks.

### Stage 1 — Prove tight bound lemma for `mont_red`

The opaque predicate (in `Simd.Traits.Specs` or `Spec.MLDSA.Math`,
TBD during implementation):

```fstar
[@@ "opaque_to_smt"]
let mont_red_bound (value: i64) (result: i32) : prop =
  abs (v result) <= 4190209 + (abs (v value) + pow2 32 - 1) / pow2 32
```

Closed form, no `exists`, no parametric `n`.  States the bound
as a function of the actual input magnitude.

A single parametric lemma proves the formula once:

```fstar
val lemma_mont_red_bound_holds (value: i64) :
  Lemma (mont_red_bound value (mont_red value))
```

Plus a small set of **specialized lookup lemmas** for the input
shapes that actually appear in our chain.  Callers use these;
they hide the `(N + 2³² − 1) / 2³²` arithmetic:

```fstar
val lemma_mont_red_q_squared (value: i64) :
  Lemma (requires Spec.Utils.is_i64b (8380416 * 8380416) value)
        (ensures  Spec.Utils.is_i32b 8380416 (mont_red value))

val lemma_mont_red_FIELD_MAX_pow32 (value: i64) :
  Lemma (requires Spec.Utils.is_i64b (8380416 * pow2 32) value)
        (ensures  Spec.Utils.is_i32b 12570625 (mont_red value))

val lemma_mont_red_FIELD_MAX_times_41978 (value: i64) :
  Lemma (requires Spec.Utils.is_i64b (8380416 * 41978) value)
        (ensures  Spec.Utils.is_i32b 4190291 (mont_red value))

val lemma_mont_red_256_FIELD_MAX_times_41978 (value: i64) :
  Lemma (requires Spec.Utils.is_i64b (256 * 8380416 * 41978) value)
        (ensures  Spec.Utils.is_i32b 4211178 (mont_red value))
```

(Add others as the chain demands.  Each instance is a one-line
F* proof: invoke the parametric lemma + `assert_norm` for the
arithmetic.  The lemmas live next to `mont_red`, not inline at
call sites.)

### Stage 2 — Refactor portable's Montgomery posts to use `mont_red` / `mont_mul`

Currently portable's `montgomery_reduce_element` post is in
mod-q form with `8265825` baked in
(`simd/portable/arithmetic.rs:101`):

```fstar
Spec.MLDSA.Math.(mod_q (v result) == mod_q (v value * 8265825))
```

Refactor to express via `mont_red`:

```fstar
v result == v (Spec.MLDSA.Math.mont_red value)
```

Plus add the bound clause:

```fstar
Spec.MLDSA.Math.mont_red_bound value result
```

Same shape for `montgomery_multiply_by_constant`,
`montgomery_multiply`, and `montgomery_multiply_fe_by_fer`
(switching to `mont_mul`-based correctness + `mont_mul_bound`).

### Stage 3 — Verify avx2 alignment

avx2 already uses `mont_mul`
(`simd/avx2/arithmetic.rs:61, 100, 132`).  Verify it stays
consistent.  Add `mont_red` references where appropriate
(if avx2 has a direct `montgomery_reduce_element` analog).
Add `mont_mul_bound` clause to avx2's existing
`montgomery_multiply_by_constant` post.

### Stage 4 — Define `mont_mul_bound` and prove the chain

Sister opaque predicate at the same layer:

```fstar
[@@ "opaque_to_smt"]
let mont_mul_bound (lhs rhs result: i32) : prop =
  abs (v result) <= 4190209 +
                    (abs (v lhs * v rhs) + pow2 32 - 1) / pow2 32
```

Lemma chains it from `mont_red_bound` (since
`mont_mul x y ≡ mont_red (x · y)`).  Specialized lookup lemmas
for the common shapes (FIELD_MAX × FIELD_MAX,
FIELD_MAX × 41978, etc.).

### Stage 5 — Update `Simd.Traits.Specs.*` lane-post predicates

Add (parallel, not extending existing predicates):

```fstar
[@@ "opaque_to_smt"]
let montgomery_multiply_bound_post (lhs rhs future_lhs: i32) : prop =
  Spec.MLDSA.Math.mont_mul_bound lhs rhs future_lhs

(* lemma_*_lookup, lemma_*_intro pair, mirroring existing
   montgomery_multiply_lane_post / reduce_lane_post style *)
```

Existing `montgomery_multiply_lane_post` (the mod-q one) is
**unchanged**.  Callers reference both predicates where they
want both bound and mod-q.

### Stage 6 — Update `Operations::montgomery_multiply` trait post

(audit: drive-by candidate; missing lhs bound in pre)

* Add the missing lhs bound in `requires` (audit drive-by
  observation).
* Add `montgomery_multiply_bound_post` clause to `ensures`.
* Both portable + avx2 impls must satisfy.  Existing impls
  already prove the body's underlying bound; surfacing it
  through the new predicate is ~1 lemma invocation per impl.

### Stage 7 — Update `Operations::invert_ntt_montgomery` trait post

The headline payoff.  Current post:

```fstar
forall i. is_i32b_array_opaque (v FIELD_MAX) (output[i])
```

(loose by ~2× empirically per the saturation probe).

Add a new conditional clause exposing the tighter parametric
bound — preserving the existing always-clause for backward
compat:

```fstar
forall i. is_i32b_array_opaque (v FIELD_MAX) (output[i]) /\
forall i j. mont_red_bound
              (cast_to_i64 (input[i].lane[j] * 41978))
              (output[i].lane[j])
```

(Exact shape TBD during implementation; the goal is for callers
to invoke `lemma_mont_red_256_FIELD_MAX_times_41978` to derive
`is_i32b 4211178` per output coefficient.)

### Stage 8 — Update both impls + verify globally

* Portable's `simd/portable/invntt.rs::invert_ntt_montgomery`:
  surface the new conditional clause, discharge via the chain
  through the layer functions.
* avx2's analog: same shape.
* Full F* re-verify: `JOBS=4 ./hax.sh prove`.
* `cargo test --release --lib`: 20/20.
* spec sanity: 3/3.

**Per-stage hard cap: 30–60 min.  Stop and consult parent on
budget overrun.**

### Sprint 1 success criterion

After Stage 8:

1. `Spec.MLDSA.Math.mont_red` defined.
2. `mont_red_bound`, `mont_mul_bound` opaque predicates +
   parametric lemma + ~5 specialized lookup lemmas in place.
3. Portable + avx2 + trait converge on `mont_mul` /
   `mont_red`-based posts (no more divergent `mod_q (... * 8265825)`
   form on the portable side).
4. `Operations::invert_ntt_montgomery` exposes the tight
   parametric bound via `mont_red_bound`.
5. F* clean, cargo test 20/20.

---

## How Sprint 1 is driven (no single agent prompt)

Sprint 1 is **collaborative — driven stage-by-stage with the
user, not as a single autonomous agent run**.  The "prompt"
for Sprint 1 IS the Stage 0–8 outline above.  Each stage is a
small unit of work executed together, with this document as the
working spec.

**Workflow per stage:**

1. Re-read the stage description in §"Sprint 1 — …" above.
2. Execute the stage (edit, extract, F* check).
3. Stop.  Report what landed: file diffs, F* timings, any
   surprises or open questions for the user.
4. User reviews and either approves moving to next stage,
   redirects (e.g., "use a different predicate name", "add
   another specialized lemma"), or pauses.
5. On approval, commit the stage's work in the worktree,
   update the doc if the stage's outcome diverged from plan,
   then move to the next stage.

**Key decision points the user is in the loop on** (from §"Decision points to surface to user"):

* Stage 0: exact form of `mont_red`.
* Stage 1: which specialized lookup lemmas to write.
* Stage 5: where the `montgomery_multiply_bound_post` lives.
* Stage 7: shape of the new `invert_ntt_montgomery` post.

**Hard rule**: if any single stage exceeds 60 min wall-clock
on body-proof debugging, STOP and consult.  Per the new memory
rule (`feedback_proof_debug_budget`).

---

## Sprint 2 — Bound propagation (autonomous, prompt skeleton)

**Goal**: use the new tight `invert_ntt_montgomery` post in
the consumer body proofs that need it, finally closing
`compute_as1_plus_s2` (and possibly `compute_w_approx` /
`compute_matrix_x_mask`).

This is mostly mechanical once Sprint 1 lands.

### When to launch Sprint 2

After Sprint 1's Stage 8 success criterion is met:

1. `Spec.MLDSA.Math.mont_red` defined.
2. `mont_red_bound`, `mont_mul_bound` opaque predicates +
   parametric lemma + specialized lookup lemmas in place.
3. Portable + avx2 + trait converged on `mont_mul` /
   `mont_red`-based posts.
4. `Operations::invert_ntt_montgomery` exposes tight
   parametric bound.
5. F* clean, cargo test 20/20.

At that point, **return to this document** and fill in the
placeholders below with the concrete Sprint 1 artefacts
(predicate names that landed, specialized lemma names, exact
trait-post shape).  Then launch Sprint 2 as an isolated
worktree agent.

### Sprint 2 prompt skeleton (fill placeholders before launch)

```text
You are agent-bound-propagation (Sprint 2).  Picking up
libcrux-ml-dsa after Sprint 1 (Montgomery spec foundation)
landed.  Tip: <SPRINT-1-MERGE-COMMIT-SHA>.

WORK TREE

Branch: ml-dsa-proofs.  Use a fresh worktree.
Status log: `libcrux-ml-dsa/proofs/agent-status/agent-bound-propagation-status.md`.
Don't push.

CONTEXT (read in order)

1. `proofs/handoff-2026-05-02-mont-bound-foundation.md` (this
   document) — Sprint 1 outcomes are in §"Sprint 1 outcome
   summary" below.
2. `proofs/agent-status/agent-arith-bound-status.md` — Chain
   3 diagnostic from the original Class B sprint; explains
   why these body proofs were blocked previously.
3. `proofs/audit-pre-post-chain.md` — Class B audit
   (compute_as1_plus_s2 body chain detail).

PARENT-APPROVED ARTEFACTS FROM SPRINT 1 (concrete, fill these in)

* New opaque predicates:
  - `<MONT_RED_BOUND_PATH>` (e.g. `Spec.MLDSA.Math.mont_red_bound`)
  - `<MONT_MUL_BOUND_PATH>`
* Specialized lookup lemmas now available:
  - `<LEMMA_FIELD_MAX_TIMES_41978_PATH>`
    Pre: `is_i64b (FIELD_MAX * 41978) value`
    Ensures: `is_i32b 4190291 (mont_red value)`
  - `<LEMMA_256_FIELD_MAX_TIMES_41978_PATH>`
    Pre: `is_i64b (256 * FIELD_MAX * 41978) value`
    Ensures: `is_i32b 4211178 (mont_red value)`
  - <list any other specialized lemmas>
* Trait post on `Operations::invert_ntt_montgomery` now
  exposes <DESCRIBE EXACT NEW CLAUSE — parametric or
  specialized; via per-lane mont_red_bound or via direct
  is_i32b conditional>.

TASKS (in priority order; per-function 30-min budget)

TASK 1 — `compute_as1_plus_s2` body proof (the headline)
    File: `libcrux-ml-dsa/src/matrix.rs`.

    1.1 Remove the body `admit ()`.
    1.2 Tighten the function's declared post from
        `is_i32b 16760832` to `is_i32b (v FIELD_MAX)` (or to
        whatever conditional shape the chain naturally
        delivers — see step 1.4).
    1.3 Add loop_invariants for the nested loops following
        the `add_vectors` recipe (rlimit 800 + split_queries
        always, snapshot frame, add_bounded for per-iteration
        bound tracking).  The OUTER loop's body invariant for
        the unprocessed suffix and processed prefix follows
        the existing pattern in matrix.rs::add_vectors.
    1.4 The KEY DIFFERENCE from the prior Chain 3 attempt:
        instead of needing a final reduce + post tightening
        via runtime canonicalization, the chain now composes
        directly via Sprint 1's tighter trait post:
            invert_ntt_montgomery output
              → satisfies <MONT_RED_BOUND_PATH>
              → invoke <LEMMA_256_FIELD_MAX_TIMES_41978_PATH>
              → derive `is_i32b 4_211_178`
              → after add(eta-bounded s2)
              → `is_i32b 4_211_178 + 4 = 4_211_182`
              → trivially `is_i32b FIELD_MAX = 8_380_416`.
        NO in-function reduce needed.  NO add_bounded
        substitution needed (existing `add` works).

    1.5 If the hax slice-bounds tactic limitation from Class
        B re-fires (Tactic failed at slice access in nested
        loops), STOP and consult parent — possibly a clever
        invariant shape exists post-Sprint-1, or possibly
        it's still blocking and needs the same dual-mutable
        refactor.
    1.6 Re-extract, F* check `Libcrux_ml_dsa.Matrix.fst`,
        cargo test 20/20.
    1.7 Commit selectively (only matrix.rs + corresponding
        F* extraction).
        Title: `ml-dsa: panic-free body proof for compute_as1_plus_s2`

TASK 2 (OPTIONAL) — `compute_w_approx` / `compute_matrix_x_mask`
    Same shape as Task 1.  If Task 1 closes cleanly and
    time permits, attempt these too.  If they hit issues,
    leave them for a follow-up sprint and log diagnostic.
    Per-function 30-min cap.

OUT OF SCOPE
* `power2round_vector` body proof — different blocker (hax
  dual-mutable slice tactic).  Separate sprint, separate
  refactor of `power2round_one_ring_element` to take t1 by
  value.
* `generate_key_pair` panic_free flip — needs both
  Task 1 (compute_as1_plus_s2) AND `power2round_vector` to
  close.  Land that as a third sprint after both close.
* Any spec change.  Sprint 1 closed the spec design.

HARD RULES (carried forward)

* rlimit cap: NEVER `--z3rlimit > 800` (or > 400 with
  `--split_queries always`).
* Per-function 30-min hard cap on proof debug.  Mark and
  move on.
* NEVER bulk-delete `.checked` files.
* DO NOT touch sample.rs / samplex4.rs / arithmetic.rs::power2round_vector
  / ml_dsa_generic.rs / specs/ml-dsa/.
* DO NOT push.
* Status reports every 15 min.

DECISION POINTS — STOP AND CONSULT

* Hax tactic limitations re-fire.
* rlimit > 800 needed.
* New spec change needed (would mean Sprint 1 missed
  something).
* Cascade timeout in previously-verified function (similar
  to the add_vectors timeout that surfaced during Chain 3).

SUCCESS CRITERION

* `compute_as1_plus_s2` body verified, post tightened.
* (Optional) `compute_w_approx` / `compute_matrix_x_mask`
  body verified.
* All F* modules in `JOBS=4 ./hax.sh prove` clean.
* cargo test 20/20.
* Status log committed.

After success criterion met, end your turn.  Parent merges
your worktree branch back, then schedules a third sprint
combining `compute_as1_plus_s2` (this sprint) and
`power2round_vector` (separate refactor sprint) into the
final `generate_key_pair` panic_free flip.
```

### Sprint 1 outcome summary (to be filled at end of Sprint 1)

(Append concrete artefact paths, predicate names, lemma names,
trait-post shape here when Sprint 1's Stage 8 success criterion
is met.)

* Spec functions added: `Spec.MLDSA.Math.mont_red`
* Opaque bound predicates: `<TBD>`
* Specialized lookup lemmas: `<TBD>`
* `Operations::montgomery_multiply` post change: `<TBD>`
* `Operations::invert_ntt_montgomery` post change: `<TBD>`
* Commits: `<SHA1, SHA2, ...>`
* Worktree branch (pre-merge): `<branch-name>`

---

## Trait pattern audit results (2026-05-02)

A read-only audit classified all 27 `Operations` methods
against the 3-part pattern:

* **5 fully compliant** (already follow the pattern):
  `decompose`, `compute_hint`, `use_hint`, `power2round`,
  `reduce`.  All use lane-post predicates linking to
  `Spec.MLDSA.Math` / `Hacspec_ml_dsa`.

* **8 drive-by candidates** (≤30 min effort each, surface
  existing F* lemmas into Rust ensures):
  `zero`, `from_coefficient_array`, `to_coefficient_array`,
  `add`, `subtract`, `infinity_norm_exceeds`,
  `montgomery_multiply` (only this one in Sprint 1 scope),
  `shift_left_then_reduce`.

* **10 follow-up candidates** (≥30 min each, need new
  lane-post predicates or new Hacspec lemmas):
  `rejection_sample_*` (3 methods), `gamma1_serialize`,
  `gamma1_deserialize`, `commitment_serialize`,
  `error_serialize`, `error_deserialize`,
  `t0_serialize`, `t0_deserialize`,
  `t1_serialize`, `t1_deserialize`,
  `ntt`, `invert_ntt_montgomery` (only this one in Sprint 1
  scope; needs the per-lane correctness post the audit
  flagged as missing — this sprint adds it via
  `mont_red_bound`).

**Recommendation**: drive-by ONLY `montgomery_multiply` (audit
fix: add missing lhs bound to pre) and `invert_ntt_montgomery`
(this sprint's main work) during Sprint 1.  Save the other
7 drive-bys for a focused trait-pattern-cleanup sprint
(estimated ~1 day, no proof debugging, mostly type-system
work).  The 10 follow-up candidates are their own multi-day
sprint.

Full audit table in `agent-status/agent-trait-pattern-audit-2026-05-02.md`
(to be created from the audit agent's output before Sprint 1
starts).

---

## Hard rules (carried forward)

* **rlimit cap**: NEVER `--z3rlimit > 800` (or > 400 with
  `--split_queries always`).
* **NEVER bulk-delete `.checked` files**.
* **Use fstar-mcp** for tight iteration.
* **Develop locally, upstream specs once** — but for this
  sprint, the spec functions (`mont_red`, `mont_red_bound`)
  are deliberately upstream from the start since both impls
  must reference them.
* **30–60 min hard cap per function** on proof-debug
  iteration.  Mark and move on.
* **Worktree isolation** — every agent in its own worktree.
* **Selective staging** — never `git add -A`.

## Decision points to surface to user

* Stage 0: exact form of `mont_red` (matching the impl body
  exactly vs slightly abstracted).
* Stage 1: which specialized lookup lemmas to write —
  determined by surveying the actual call sites.
* Stage 5: where the `montgomery_multiply_bound_post` lives
  (`Simd.Traits.Specs.fst` parallel to existing predicates,
  vs in `Spec.MLDSA.Math` with the math layer).  Lean
  `Simd.Traits.Specs.fst`.
* Stage 7: whether the new `invert_ntt_montgomery` ensures
  exposes the parametric `mont_red_bound` via per-lane
  predicates, or via a closed conditional clause that
  references specific input shapes.  Lean parametric for
  flexibility.
