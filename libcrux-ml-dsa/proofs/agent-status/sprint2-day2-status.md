# Sprint 2 Day 2 — Matrix body proofs

Started: 2026-05-06 12:50

## Plan
- Task 4: vector_times_ring_element (simplest, single flat loop) — start
- Task 1: compute_as1_plus_s2 (nested + sequential loop)
- Task 3: compute_matrix_x_mask (nested loop, mask copy)
- Task 2: compute_w_approx (nested, weak ensures)

## Notes
- invert_ntt_montgomery ensures `is_i32b_array_opaque 4211177` (Sprint 1 tight bound)
- Posts mostly want FIELD_MAX (8380416) — need weakening via `is_i32b_array_larger`
  (no SMTPat; manual call required).

## Active sub-task: Task 4 vector_times_ring_element
- 12:50 begin: write loop invariant + post-invert weakening lemma.
- 12:55 verified: snapshot+invariant + is_i32b_array_larger weaken lemma. ✓

## Task 1: compute_as1_plus_s2 — BLOCKED (admit kept)
- 12:55-13:30 attempted body proof (~35min).
- Outer i-loop has tuple state (a_as_ntt, result) since both are mutated.
  Hax extracts the loop_invariant lambda as
  `(fun temp_0_ i -> let (a_as_ntt: T1), (result: T2) = temp_0_ in <inv>)`.
  The per-component type annotations don't propagate to F* field resolution,
  so `Seq.index result k).f_simd_units` errors as unresolved field. Adding an
  inner `let result : T = result in` re-binding fixes that, but then SMT
  subtype coercion `t_Array i32 8 → t_Slice i32` fails inside Z3 in the
  resulting (heavier) invariant — many timeouts at 400 rlimit per query.
- Decision: leave admit + comment, follow up by either (a) hax extraction
  emitting single-state fold or (b) refactoring inner j-loop into a helper.

## Active sub-task: Task 3 compute_matrix_x_mask
- 13:30 begin: matrix is immutable, fold is single-state on result.
