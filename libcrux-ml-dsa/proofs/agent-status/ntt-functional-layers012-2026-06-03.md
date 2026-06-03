# NTT functional layers 0-2 session (2026-06-03, evening)

Continuation of the layer-0 chunk bridge (ntt-layer0-chunk-bridge-2026-06-03.md).
Scope: (1) all-32-chunk layer-0 composition, (2) Portable simd_unit_ntt_step /
at_layer_0 functional FE posts, (3) layers 1-2 within-chunk bridges.
ALL THREE STEPS PROVEN + COMMITTED. Full-crate prove in flight (final gate).

## Step 1 — DONE (commit 215f3c8c6)
`lemma_ntt_layer_0_step_to_hacspec_poly` in Commute.Chunk.fst: forall i<256
mod-q congruence to `ntt_layer input 0`, witness fns (b,p)->t/zm, dispatching
to the chunk lemma per i/8. Clean module build 77s, 395 query-stats, max
sub-query 65ms. No new admits (baseline 1 admit at line 639 unchanged).

## Step 2 — DONE (commit a12bde20a)
- FE-form ensures on `simd_unit_ntt_step`: exact butterfly relations
  (new_lo == old_lo + t, new_hi == old_lo - t) with t NAMED as the
  `montgomery_multiply_fe_by_fer` application on the OLD hi lane + mod-q
  congruence (v t) % q == (v hi_old * v zeta * 8265825) % q.
  `reveal_opaque mod_q` at body end converts mmfbf's opaque-mod_q post.
- GOTCHA FOUND: requires had only `v step <= 4` — step=0 was admitted, under
  which the FE conjuncts are FALSE (both updates collapse onto one lane;
  bounds posts didn't care). Failure signature: ONE sub-query (q55)
  "incomplete quantifiers" at 4.9/300 rlimit. Fix: `1 <= v step`.
  All callers pass step in {1,2,4}.
- `simd_unit_ntt_at_layer_0` lifted post: 4 pairs x 3 conjuncts in exactly
  the chunk-lemma-requires shape (t_p named via mmfbf on ORIGINAL lanes;
  frame-chaining through the 4 sequential step calls is automatic from
  modifies2_8 ground equalities). Bounds posts kept.
- Re-extraction byte-identical to the verified .fst (md5 4d76002f...).

## Step 3 — DONE (commit e072c02dc)
Layer-1 (pairs (4h+j, 4h+j+2), zeta v_ZETAS[2b+h+64] one per half) and
layer-2 (pairs (p, p+4), zeta v_ZETAS[b+32] one per chunk) in
Commute.Chunk.fst: reducer + lane-reduction + clean-context per-pair +
per-chunk dispatcher + all-32-chunk poly composition each.
`lemma_layer_0_pair_spec` reused as the layer-agnostic butterfly algebra.

- TRIGGER-COVERAGE GOTCHA (new, generalizable): in a requires
  `forall (b,h,j). butterfly(t b h j) /\ zeta-congruence(zm b h)`, the ONLY
  single-term trigger covering all three binders is `t b h j`. Under
  --split_queries the zeta sub-goals (which never mention t) cannot fire the
  instantiation -> "incomplete quantifiers" on exactly the zeta conjuncts
  (q73/q74). Layer-0 passed because its zm is indexed (b,p) = same arity as
  t. FIX: split the requires into two foralls — butterfly per (b,h,j), zeta
  per (b,h) [resp. per b for layer 2] — so each forall's natural trigger
  matches its goals' terms.
- Benign: layer_1_lane/layer_2_lane monolithic WF VC cancels at the file
  default rlimit 80, then F*'s automatic retry-with-split passes all 33
  sub-queries at <=29/80. Not a failure (build exit 0).

## Gate — GREEN (session complete)
- Combined chain build (Chunk -> Portable.Arithmetic -> Portable.Ntt, all
  stale after the Chunk edit): exit 0, 19.5 min wall, 4412 query-stats,
  no ipc crash, zero unretried failures. Build d26c685e.
- Full-crate `JOBS=2 ./hax.sh prove`: **99 modules (94 CHECK + 5 ADMIT
  pre-existing), 99 verified, 0 F* errors, 0 make failures** (~75 min;
  Portable.Invntt alone took ~45 min cold — hint invalidation from the
  Chunk->Arithmetic dep cascade, passed clean).
- verification_status.md regenerated: IDENTICAL to committed (no tier
  flips; this session strengthened existing ensures + added proof-lib
  lemmas, lax count stays 42).

## Next (layer 3+ / future sessions)
- Cross-chunk layers 3-7 (Commute.Bridges port) + 8-layer compose to
  `== Hacspec_ml_dsa.Ntt.ntt` driver.
- Wiring the poly composition into `ntt_at_layer_0`'s ensures needs the
  zeta_r-discharge at the round level + a v_ZETAS<->Spec.MLDSA.Ntt.zeta
  bridge (v_ZETAS matches zeta for idx>=1; idx 0 differs, unused at L0-2).
- at_layer_1/at_layer_2 impl-post lifts (mirror of a12bde20a's at_layer_0).
