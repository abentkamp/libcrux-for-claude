# NTT layer-0 chunk->Hacspec bridge — status (2026-06-03)

Task: prove `lemma_ntt_layer_0_chunk_to_hacspec` in Commute.Chunk.fst, relating the
impl's within-chunk layer-0 transform to `Hacspec_ml_dsa.Ntt.ntt_layer p 0`.

## Key findings (00:00)
- spec ntt_layer layer 0: len=1, k=128. flat i: round=i/2=j, idx=i%2.
  even (idx=0): out[2j] = mod_q(p[2j] + mod_q(z*p[2j+1])), z=v_ZETAS[j+128].
  odd  (idx=1): out[2j+1] = mod_q(p[2j] - mod_q(z*p[2j+1])).  (uses p[i-1]=p[2j])
- impl simd_unit_ntt_at_layer_0: 4 butterflies on pairs (0,1)(2,3)(4,5)(6,7),
  step=1; lo=even=lo_old+t, hi=odd=lo_old-t, t=mont_mul(hi_old, zeta).
- mod_q is NOT opaque (plain let) -> v (mod_q a) == (v a) % q (Euclidean, [0,q)).
- IMPL VALUES ARE NOT IN [0,q): bounded by NTT_BASE_BOUND+8*FIELD_MAX, NOT reduced.
  => literal `==` to spec (which IS in [0,q)) is FALSE.
  => conclusion must be PER-LANE MOD-Q CONGRUENCE, mirroring lemma_butterfly_step_fe.
- zeta bridge: spec uses v_ZETAS[j+128]; zeta_r proven for Spec.MLDSA.Ntt.zeta.
  v_ZETAS matches Spec.MLDSA.Ntt.zeta for idx>=1 (idx0 differs 1 vs 0; unused at L0).

## Plan
1. layer_0_lane reducer + lemma reducing ntt_layer p 0 at i to layer_0_lane.
2. per-chunk lane bridge: hypotheses = 4x butterfly new/old/t + zeta congruence;
   conclude per-lane mod-q congruence for the 8 lanes of chunk b.
3. (if time) poly-level compose via Classical.forall_intro + Seq.lemma_eq_intro.

## ETA: 60 min budget

## Progress (~20 min)
- Wrote 3 foundation defs (lax-OK): layer_0_lane reducer, lemma_ntt_layer_0_lane
  (reduce ntt_layer p 0 at i -> layer_0_lane), lemma_mod_q_v (v(mod_q a)==(v a)%q).
- Wrote lemma_layer_0_pair_spec (per-pair butterfly -> 2 spec lanes via
  lemma_butterfly_step_fe + lemma_mod_q_v + mod_plus/sub_distr). SMT verify in flight.
- Drafted lemma_ntt_layer_0_chunk_to_hacspec (per-chunk, 8 lanes): reveals chunk-b
  lanes via lemma_simd_units_to_array_reveal, aux per pair calls pair_spec +
  lemma_ntt_layer_0_lane, assemble forall over 8 lanes. Conclusion = per-lane mod-q
  congruence on chunk b.
- DESIGN DECISION: conclusion is PER-LANE MOD-Q CONGRUENCE (impl is bounded Mont
  form, not in [0,q); literal == is false). zeta congruence kept as hypothesis
  stated against v_ZETAS[4b+p+128] (self-contained; consumer discharges via zeta_r).

## Progress (~40 min) — RESTRUCTURE
- Foundation 3 lemmas VERIFIED clean (verify-to-position 998 ok): layer_0_lane,
  lemma_ntt_layer_0_lane, lemma_mod_q_v, lemma_layer_0_pair_spec.
- First monolithic chunk lemma TIMED OUT (curl 500s) — the inline aux+assemble
  with 16 top-level reveals + createi unfold inside one split-VC saturated.
- FIX: factored per-pair work into top-level lemma_layer_0_chunk_pair (clean
  context, createi unfold in minimal scope). chunk lemma now = thin dispatcher
  (4 pair calls + 8 reveals + bounded-forall enumeration). Verifying pair lemma now.

## RESULT (~52 min) — PROVED (verify-to-position)
All new lemmas verify clean (only benign pre-existing line-47 split warning):
- layer_0_lane (reducer) + lemma_ntt_layer_0_lane (ntt_layer p 0 @i == layer_0_lane)
- lemma_mod_q_v (v(mod_q a) == (v a)%q)
- lemma_layer_0_pair_spec (per-pair butterfly -> 2 spec mod_q lanes)
- lemma_layer_0_chunk_pair (per-pair clean-context spec-lane bridge, createi unfold)
- lemma_ntt_layer_0_chunk_to_hacspec (THE DELIVERABLE: per-chunk 8-lane bridge,
  thin dispatcher over 4 pair lemmas + forall over 8 lanes)
NO admit/assume in any new code (line>=879). Pre-existing admit at 639
(lemma_decompose_spec_eq_decompose) unchanged = baseline.
Running full fstar_build check/Chunk.fst as Phase 8 gate.

## DONE — PROVED & full-build clean (~58 min)
fstar_build check/Hacspec_ml_dsa.Commute.Chunk.fst (no --admit_except):
  exit_code 0, failed_modules [], ipc_crash false, wall 88s, .checked regenerated.
  build_id db4cff5f-7103-487f-afd7-4bd1fc84988c.
No unretried/cold failures. Reduction lemma hardened with --split_queries always
+ rlimit 150 (heaviest sub-query 77.4/150, was canceling at 80 on stale-hint replay).
Max rlimit annotation in new code: 300 (with split_queries; <=400 cap). No admit/assume.

NOT done (out of scope / time): lemma_ntt_layer_0_step_to_hacspec_poly (all-32-chunk
composition). Trivial to add now: forall over 256 lanes dispatching to
lemma_ntt_layer_0_chunk_to_hacspec per i/8; per-chunk witnesses via witness fns.
Also out of scope: wiring this into Portable simd_unit_ntt_at_layer_0 ensures (needs
the FE-form post on simd_unit_ntt_step — Step 5, separate task).
