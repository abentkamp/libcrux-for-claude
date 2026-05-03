# ML-DSA Proof Sprint Plan — 2026-05-03

Two horizons:
* **Week 1** — Sprint A core (panic-freedom for keygen/sign/verify cone).
* **Weeks 2-8** — Sprint B (full Hacspec correctness, milestone B).

The week-1 plan is the foundation; everything in weeks 2-8 builds on
the cleared admit chain it produces.

Tip after Sprint 1: `08e731129`.  Branch: `ml-dsa-proofs`.

Notation: 🤖 = agent task (mechanical, parallelizable), 👤 = user task
(design judgment, Z3-saturation rescue, bit-trick proofs).

---

## Week 1 — Sprint A core (panic-freedom)

**Goal at end of week**: zero body admits in the keygen/sign/verify
cone, all `verification_status(lax)` cleared in AVX2, only the 17
`ADMIT_MODULES` (wrappers + samplex4 dispatchers) left.

User time budget: **~9 hr over the week**, scheduled to unblock agent
work as it lands.

### Mon — User-decision day (Claude usage constrained until reset ~24 h)

**Frame**: Claude usage is paused until reset.  Use the day for the
high-leverage user decisions normally scheduled later in the sprint —
this lets Tue-Sun proceed at full agent throughput with no further
gating decisions.

🤖 0 agent runs (intentionally).  No automated work today.

👤 ~4-5 hr of focused user work, in priority order:

1. **`power2round_one_ring_element` refactor decision** (originally
   Wed; pulled forward because it gates the keygen-cone flips on
   Thu).  Decide one of:
   * Take t1 by value (cleanest; check whether any caller relies on
     the in-place semantics for perf).
   * Return tuple (slight allocation cost, no caller change).
   * Accept admit on `power2round_vector` for Sprint A and chase in
     Sprint B.

   Document the decision in
   `proofs/agent-status/power2round-refactor-decision.md`.  ~1 hr.

2. **Trait correctness-post shape — design preview** (originally
   week 2; pulled forward to start drafting now so week-2 agents
   can land on a complete design).  Skim
   `proofs/agent-status/agent-trait-pattern-audit-2026-05-02.md`
   (if exists; otherwise the audit table in the proof-review).
   For each of the 22 missing-correctness-post methods, draft:
   * Hacspec function pointer (e.g.,
     `Operations::ntt` post should cite `Hacspec_ml_dsa.Ntt.ntt`).
   * Per-lane vs whole-vector equality.
   * Lane-post predicate name (mirror existing
     `montgomery_multiply_lane_post`).

   Save draft as
   `proofs/agent-status/trait-correctness-post-design-draft.md`.
   ~2 hr.  Don't finalize yet — week 2 will refine.

3. **Read `proofs/agent-status/agent-proof-review-2026-05-03.md`**
   end-to-end.  Confirm or revise the sprint priorities.  Especially:
   * Are the 7 Hacspec `assume`s lift-to-precondition vs
     discharge-in-place?  (Affects week 5 user time.)
   * Is `lemma_decompose_spec_eq_decompose` Sat-budget realistic?
     If not, swap with a Wed user session.
   * Any Sprint A targets to drop or add?

   30 min.

4. **Pre-flight `compute_as1_plus_s2` body** (optional, ~1 hr).  Look
   at the function in `src/matrix.rs:44`, the loop_invariant pattern
   in `add_vectors`, and the new tight invntt post.  Does the chain
   compose mentally?  If yes, Tue's agent run will be smooth.  If a
   blocker is visible (hax tactic, Z3 shape), revise the Tue plan
   before agents start.

**Output of Mon**: 2 design docs (refactor decision + trait-post
draft) + a confirmed sprint priority list.  This lets Tue agents
launch on solid ground with no mid-flight Claude consultations
needed for design questions.

### Tue — Mont Sprint 2 kickoff (full agent throughput)

🤖 1 agent: `compute_as1_plus_s2` body proof (Sprint 2 Task 1).
   Use the new tight `is_i32b_array_opaque 4211177` post on
   `invert_ntt_montgomery`.  Per-function 30-60 min cap.

🤖 (after compute_as1_plus_s2 lands) 2 agents in parallel:
   * `compute_w_approx` body (Task 2)
   * `compute_matrix_x_mask` body (Task 3)
   Both copy-paste shape from compute_as1_plus_s2.

🤖 1 agent: re-prove `vector_times_ring_element` body (currently
   admitted post-Sprint-1 as a Z3-saturation casualty).

👤 ~1 hr: mid-day status check; intervene if the hax slice-bounds
   tactic limitation re-fires (Class B Chain 3's old blocker).
   Decision tree:
   * Tactic failure → propose loop-invariant refactor; if that fails,
     escalate to take-by-value Rust signature change.
   * Z3 saturation → introduce explicit `Classical.forall_intro` with
     focused trigger.

   If `vector_times_ring_element` keeps saturating, accept admit and
   move on.

### Wed — sample.rs admits + power2round refactor execution

🤖 2 agents in parallel:
   * `sample_mask_ring_element` + `sample_mask_vector` body proofs
     (Class B Chain 1 surfaced ensures already in place)
   * `sample_challenge_ring_element` body

🤖 1 agent: drive the `power2round_one_ring_element` refactor per
   Mon's decision doc (`power2round-refactor-decision.md`), if not
   the "accept admit" branch.  Update callers; re-extract; verify.

👤 30 min: spot-check the refactor.  If Mon's decision was "accept
   admit", skip this; agents focus only on sample.rs.

### Thu — Public API panic-free flips

🤖 1 agent: `generate_key_pair` panic-free flip.  Depends on
   `compute_as1_plus_s2` (Mon) + `power2round_vector` (Wed
   decision).  If Wed accepted admit, this flip uses the
   admit-trusted post.

🤖 1 agent: `sign_internal` panic-free flip.  Depends on
   `compute_w_approx` + `compute_matrix_x_mask` (Tue) +
   `sample_mask_*` (Wed).

👤 30 min: spot-check the flips; ensure no `verification_status(lax)`
   slipped in.

### Fri — verify + AVX2 encoding mop-up

🤖 1 agent: `verify_internal` flip + 6 wrapper variants.

🤖 2 agents in parallel: AVX2 encoding admits.  Files:
   `simd/avx2/encoding/{gamma1,t0,error}.rs`.  7 fns total.
   ~1 hr each.

👤 0 (rest day for human; agents run autonomously).

### Sat — Mechanical cleanup

🤖 1 agent: discharge `lemma_mont_red_mod_q` from preserved calc-chain
   (`Spec.MLDSA.Math.fst:258`, calc preserved as 50-line comment
   lines 195-252).

🤖 1 agent: 8 trait-pattern drive-by surfacings from the audit
   table (zero, from_coefficient_array, to_coefficient_array, add,
   subtract, infinity_norm_exceeds, montgomery_multiply lhs-bound,
   shift_left_then_reduce).

👤 **3-4 hr (highest-value user session)**: `lemma_decompose_spec_eq_decompose`
   (`Hacspec_ml_dsa.Commute.Chunk.fst:639`).  150-200 line
   bit-trick interval analysis over centered-modulo (FIPS 204
   Algorithm 36).  Agents have repeatedly bounced; needs human
   case-split over r ∈ ((q-1)/2 - g, ...] partitions.  Closing it
   unblocks AVX2 `compute_hint`/`use_hint` body proofs (currently 4
   lax markers).

### Sun — Stabilization + handoff

🤖 0 — stop submitting new agent work.

👤 ~1 hr:
   * Run global verify from CLEAN cache.  Confirm 0 errors, expected
     ADMIT count.
   * Refresh `proofs/agent-status/fstar-perf-top20.md` with new
     timings.
   * Write Sprint A completion report.
   * Compose Sprint B kickoff handoff prompt.

### Week-1 success criterion

* 0 F* errors, `JOBS=4 ./hax.sh prove` from clean cache.
* `cargo test --release --lib` 20/20 pass.
* `verification_status(lax)` cleared from `simd/avx2/{arithmetic,
  invntt}.rs` (the 4 markers from today's review).
* Body admits in `arithmetic.rs`, `matrix.rs`, `sample.rs`,
  `ml_dsa_generic.rs`, `encoding/signature.rs` reduced to ≤2
  (allowed: `power2round_vector` if Wed decided to defer).
* `lemma_mont_red_mod_q` discharged.
* 8 trait drive-bys landed.
* `lemma_decompose_spec_eq_decompose` discharged → AVX2
  `compute_hint`/`use_hint` lax cleared.

### Week-1 risk register

1. **Hax tactic limit re-fires** in `compute_as1_plus_s2` → +1-2 days,
   may force `power2round_one_ring_element`-style refactor on
   `compute_as1_plus_s2`'s neighbours too.
2. **Z3 saturation in nested-loop proofs** (multiple targets) →
   case-by-case, +0.5-1 hr each, user-rescued via explicit
   `Classical.forall_intro` patterns.
3. **`lemma_decompose_spec_eq_decompose` over budget** → if Sat
   session doesn't close it, slip to weekday by 0.5 day; AVX2
   `compute_hint`/`use_hint` stay lax until next sprint.

---

## Weeks 2-8 — Sprint B (full Hacspec correctness, milestone B)

**Goal**: every public API function in `ml_dsa_44`/`ml_dsa_65`/`ml_dsa_87`
proven equal to its Hacspec counterpart.  No body admits, no lax
markers, no `assume`s left in `Hacspec_ml_dsa.Ml_dsa.fst`.

This sprint is gated by trait-correctness-post design (👤 task #5)
which is itself gated by Sprint A clearing the trait impl bodies.

### Week 2 — Trait correctness posts (design + first wave)

👤 4-6 hr (highest-leverage user week): **trait correctness-post
   shape decisions** for the 22 methods missing them.  Audit table
   in `agent-trait-pattern-audit-2026-05-02.md`.  Decide:
   * Per-lane equality vs whole-vector equality
   * Hacspec function pointer in the post
   * Lane-post predicate naming convention (mirror existing
     `montgomery_multiply_lane_post`, `power2round_lane_post`)
   * Whether to add SMTPats (caution per `feedback_smtpat_percent_above_trait`)

🤖 First wave (parallel after design lands): 8 drive-by methods
   (zero, from_coefficient_array, to_coefficient_array, add, subtract,
   infinity_norm_exceeds, shift_left_then_reduce, montgomery_multiply
   lhs-bound).  ~30 min each.

### Week 3 — Trait correctness posts (heavy methods)

👤 2 hr: review week-2 first wave outcomes; refine the design for
   the remaining 14 methods if patterns emerged.

🤖 2-3 agents in parallel on the 14 follow-up methods:
   * `ntt`, `invert_ntt_montgomery` (correctness post = per-lane
     equality with `Hacspec_ml_dsa.Ntt.{ntt, invert_ntt}`)
   * 7 serialize/deserialize methods (gamma1/commitment/error/t0/t1)
   * 3 rejection_sample methods

### Week 4 — Above-trait body proofs (round 1)

🤖 Parallel: `Encoding.T0`, `Encoding.T1`, `Polynomial.add/subtract`
   correctness posts + bodies.  These are the "clean Hacspec mapping"
   targets identified in the proof-review.

🤖 `compute_a_times_mask`, `compute_t1_minus_ct0` body proofs (above
   trait, currently admit).  Now feasible with trait correctness
   posts in place.

### Week 5 — Hacspec_ml_dsa.Ml_dsa.fst spec hardening

👤 6-8 hr (heavy week): **discharge the 7 inline `assume (forall i. ...)`
   clauses** in `Hacspec_ml_dsa.Ml_dsa.fst` (lines 115, 224, 326, 354,
   403, 598, 800).  Each is a loop-invariant axiom that needs to be
   either:
   * Proven from algorithm semantics, OR
   * Lifted to a caller precondition / function-level requires.

   This requires understanding the spec's algorithm at each location
   (which loop, which invariant, what's the post-condition).  Agents
   can't do this without spec-design context.

👤 1-2 hr: discharge `lemma_decompose_spec_eq_decompose` if it slipped
   from week 1.

### Week 6 — Above-trait body proofs (round 2)

🤖 Parallel agents on the 12 `ml_dsa_generic.rs` admits, plus the 6
   wrapper variants in `ml_dsa_44`/`ml_dsa_65`/`ml_dsa_87`.  Now that
   trait posts cite Hacspec functions and the in-spec `assume`s are
   discharged, body proofs can compose.

🤖 1 agent: `encoding/signature.rs::serialize` (count-ones lemma gap).

👤 2 hr: spot-check; intervene if the wrapper-equality flip surfaces
   in-spec `assume`s that were missed in week 5.

### Week 7 — ADMIT_MODULES lift

🤖 Parallel agents: lift the 17 ADMIT_MODULES one by one.
   * 12 `Ml_dsa_{44,65,87}_*.fst` wrappers: now have callers proven, so
     they can be moved out of ADMIT_MODULES into CHECK.
   * 4 `Samplex4*.fst` dispatchers: depend on sample.rs bodies (week 3-4).
   * 1 `Shuffle_table.fst`: needs constant-table extraction.

👤 1 hr: review which ADMIT_MODULES can lift; ones that can't stay
   admitted with documented reason.

### Week 8 — Stabilization

🤖 0 new sprints.

👤 4 hr:
   * Final global verify from clean cache.
   * Refresh top-20 perf table.
   * Write the Hacspec-correctness completion report.
   * Tag the milestone-B commit.

### Sprint B success criterion

* All 27 trait methods have correctness posts.
* `Hacspec_ml_dsa.Ml_dsa.fst` has no `assume` clauses.
* `Spec.MLDSA.Math.fst` has no `admit ()`.
* `Hacspec_ml_dsa.Commute.Chunk.fst` has no `admit ()`.
* `src/ml_dsa_*.rs` and `src/ml_dsa_generic.rs` have no body admits.
* All AVX2 trait impls verified (no `admit ()` bodies; no lax).
* ADMIT_MODULES count ≤ 5 (only the truly-can't-lift cases).
* `JOBS=4 ./hax.sh prove` from clean cache: 0 errors.
* `cargo test --release --lib` 20/20.

---

## User-task summary across both sprints

| # | Task | When | Hours | Why human-only |
|---|---|---|---|---|
| 1 | power2round refactor decision | **Wk 1 Mon** (pulled forward) | 1 | Sig-change refactor decision; agents tried 3+ times to work within current API |
| 2 | Trait correctness-post draft | **Wk 1 Mon** (pulled forward) | 2 | API design preview; week 2 will refine |
| 3 | Sprint priority confirmation | Wk 1 Mon | 0.5 | Read proof-review; revise if needed |
| 4 | Pre-flight `compute_as1_plus_s2` | Wk 1 Mon (optional) | 1 | Mental compose-check before Tue agent run |
| 5 | `compute_as1_plus_s2` Z3-saturation rescue | Wk 1 Tue | 1 | Hax tactic / Z3 saturation in nested-loop body proofs |
| 6 | Refactor + sample-admit spot-check | Wk 1 Wed | 0.5 | Validate Mon decision execution |
| 7 | Public API flip spot-checks | Wk 1 Thu | 0.5 | Ensure no `verification_status(lax)` slips in |
| 8 | `lemma_decompose_spec_eq_decompose` | Wk 1 Sat | 3-4 | 150-200 line bit-trick interval analysis; agents bounce off |
| 9 | Sprint A wrap-up + handoff | Wk 1 Sun | 1 | Completion report + Sprint B kickoff prompt |
| 10 | Trait correctness-post finalize | Wk 2 | 4-6 | Refine Mon's draft; finalize design across 22 trait methods |
| 11 | 7 in-spec Hacspec `assume` discharge | Wk 5 | 6-8 | Spec-internal loop invariants need algorithm-level reasoning |
| 12 | Spot-checks throughout | Wk 4-7 | 3-4 | Course-correct stalled agents, validate flip safety |
| **Total** | | | **~24 hr** | |

The week-1 budget is **~10 hr concentrated on Mon (4-5 hr) and Sat
(3-4 hr)**, with light daily check-ins (~30-60 min Tue-Thu).  Mon is
intentionally heavy on user decisions to front-load all gating
choices BEFORE agent throughput resumes Tue with the usage reset.
Weeks 2-8 add ~13 hr concentrated in week 2 (trait design finalize)
and week 5 (spec discharge).  Other weeks are mostly agent-driven
with light review.

---

## What this plan does NOT cover

* **`Spec.Intrinsics.fsti:20` admit** on a low-level intrinsic — out
  of scope, not ml-dsa-specific.
* **Performance tuning** — top-20 perf is tracked but not optimized
  during these sprints.
* **Constant-time / side-channel proofs** — separate workstream.
* **C extraction via KaRaMeL** — out of scope.

---

## References

* Sprint 1 outcome: tip `08e731129` (today).
* Original handoff: `proofs/handoff-2026-05-02-mont-bound-foundation.md`.
* Proof-review: `proofs/agent-status/agent-proof-review-2026-05-03.md`.
* Sprint 2 launch prompt: see Sprint 2 prompt in this conversation
  history (or refresh from `handoff-2026-05-02-mont-bound-foundation.md` §"Sprint 2 prompt skeleton").
* Memory rules: `~/.claude/projects/-Users-karthik-libcrux/memory/MEMORY.md`.
