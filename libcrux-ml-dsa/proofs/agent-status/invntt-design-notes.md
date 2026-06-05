# Inverse-NTT proof — B/C/D/E design notes (orchestrator, from forward template)

Forward template = `src/simd/portable/ntt.rs`. Mirror with GS deltas. All atoms/lemmas go in
`#[hax_lib::fstar::before(r#"..."#)]` blocks attached to the corresponding invntt.rs fn.
GS butterfly (impl simd_unit_inv_ntt_step / outer_3_plus): lo_new=lo+hi (plain add, even);
hi_new=mont_mul(hi-lo, zeta) (odd). mont_mul post: (v r)%q == (v x * v zeta * 8265825)%q.
NO separate `t` witness (odd output IS co[hi], a mod-q relation). zeta = zeta_r(k-r) (positive Mont rep).

## PHASE B — within-chunk L0-2 (invntt.rs invert_ntt_at_layer_0/1/2 + simd_unit_inv_ntt_step)
Forward refs: simd_unit_ntt_step FE-post ntt.rs:701-734; simd_unit_ntt_at_layer_0/1/2 posts 736-849;
unit_fe_post_l0/1/2 atoms 213-233/127-147/34-58; lemma_atom_to_bf_l0/1/2 234-252/149-167/60-80;
lemma_l0/1/2_driver_compose 254-296/169-210/82-125; driver ntt_at_layer_0 851-1073 (round helper w/
atom post + reveal; snapshot orig_re; 32 rounds; assert_norm zeta_r block; lemma_l0_driver_compose call).
INVERSE deltas:
1. Add FE-post to `simd_unit_inv_ntt_step` (currently bounds-only, invntt.rs:8-40): expose
   v(co index)==v(ci index)+v(ci (index+step)) /\ (v(co (index+step)))%q == ((v(ci(index+step))-v(ci index))*v zeta*8265825)%q.
   (montgomery_multiply_fe_by_fer(a_minus_b,zeta), a_minus_b=ci[i+step]-ci[i].)
2. unit_fe_post_inv_l0 (ci co)(z0..z3): per pair p∈{0..3} lanes (2p,2p+1):
   v(co 2p)==v(ci 2p)+v(ci (2p+1)) /\ (v(co (2p+1)))%q==((v(ci(2p+1))-v(ci 2p))*v zp*8265825)%q.
   l1: pairs (4h+j,4h+j+2), 2 zetas/chunk. l2: pairs (p,p+4), 1 zeta/chunk.
3. lemma_atom_to_bf_inv_l0/1/2: reveal atom → per-pair forall (match dispatch).
4. lemma_inv_l0/1/2_driver_compose: forall32 of inv atoms → Commute.Chunk.lemma_intt_layer_L_step_to_hacspec_poly.
   zeta witness zm(b,p)=mk_i32(zeta_r(k - round)); k=255/127/63 for L0/1/2; aux_z via lemma_v_zetas_eq_zeta(k-round).
   NOTE inverse zeta INDEX = k-round (L0: 255-(4b+p); descends), vs forward round+128.
5. Driver invert_ntt_at_layer_0/1/2 (invntt.rs:103-312): add functional ensures (mirror ntt_at_layer_0
   ensures 861-868 but with intt_layer + the 2*FIELD_MAX bound it already has); round helper gets atom post;
   body: snapshot orig_re, 32 rounds, assert_norm(zeta_r (k-round)==hardcoded) block, lemma_inv_l*_driver_compose.
   Impl hardcoded inverse L0 zetas (invntt.rs:144-175) ARE zeta_r 128..255 reverse-mapped (round 0 → 255).

## PHASE C — cross-chunk L3-7 (invntt.rs invert_ntt_at_layer_3..7 + outer_3_plus)
Forward refs: unit_fe_post_cross ntt.rs:298-334; lemma_round_cross_intro 335-366; lemma_atom_to_bf_cross
368-386; lemma_l3..7_cross_driver_compose 388-689 (uses lemma_cross_idx + createi bridge + aux_bf/aux_z);
forward outer_3_plus 1341-1469 (loop_invariant + 16-flat-asserts to build forall32); ntt_at_layer_3..7 1481-1746.
INVERSE deltas:
1. unit_fe_post_inv_cross (ci_lo ci_hi co_lo co_hi)(zeta): per lane l∈{0..7}:
   v(co_lo l)==v(ci_lo l)+v(ci_hi l) /\ (v(co_hi l))%q==((v(ci_hi l)-v(ci_lo l))*v zeta*8265825)%q.
2. lemma_round_inv_cross_intro: leaf posts → atom. Impl outer_3_plus (invntt.rs:351-372):
   add(&mut re[j],&rejs) ⇒ add_post ci_lo ci_hi co_lo (co_lo=lo+hi);
   subtract(&mut re[j+STEP_BY],&rej) ⇒ sub_post: re[j+STEP_BY]=rejs-rej=hi-lo (tmp=hi-lo, NOTE order b-a);
   montgomery_multiply_by_constant(&mut re[j+STEP_BY],ZETA) ⇒ co_hi=mont_mul(tmp,ZETA), tmp=hi-lo.
   So requires: add_post ci_lo ci_hi co_lo /\ sub_post ci_hi ci_lo tmp /\ (forall l. tmp[l]==mont_mul(ci_hi[l]-... )).
   Mirror forward lemma_round_cross_intro (335-366) but add is on lo+hi (not lo+t), mont on the diff.
3. lemma_atom_to_bf_inv_cross: reveal → per-lane forall (8-way match).
4. lemma_inv_l3..7_cross_driver_compose: forall32 of inv cross atoms → Commute.Chunk.lemma_intt_layer_L_cross_to_hacspec_poly.
   zm(u)=mk_i32(zeta_r(k - u/(2*step_by)))... use the EXACT zeta index Commute.Chunk cross lemma expects (k-round).
   L3 k=31 idx=31-(u/2); L4 k=15 idx 15-(u/4); L5 k=7; L6 k=3; L7 k=1. lemma_cross_idx step_by u 0 + small_mod.
5. Driver outer_3_plus (invntt.rs:314-373) keeps its bounds loop_invariant + ADD the cross-atom forall32 to
   loop_invariant + ensures (mirror forward outer_3_plus 1341-1469); 16 flat per-lo-unit asserts in
   invert_ntt_at_layer_3 (step_by=1, 16 calls) before lemma_inv_l3_cross_driver_compose; analogous for L4-7.

## PHASE D — top compose (invntt.rs invert_ntt_montgomery, before-block)
Forward refs: lemma_modq_eq ntt.rs:1751; lemma_bf_even/odd_cong 1757/1775; lemma_layer_L_lane_cong 1793.. (8);
lemma_ntt_layer_L_cong (createi unfold via Commute.Chunk.lemma_ntt_layer_L_lane + forall_intro + eq_intro);
lemma_ntt_compose_8 2087; body 2142 (snapshots s0..s1 + compose call).
INVERSE deltas (GS cong helpers — plan harmonic-sauteeing-key.md:92-104):
- lemma_inv_bf_even_cong (x y x' y':i32): mod_q((cast x)+!(cast y))==mod_q((cast x')+!(cast y')) given x≡x',y≡y' mod q.
- lemma_inv_bf_odd_cong (z:i64)(x y x' y':i32): mod_q(z*!((cast x)-!(cast y)))==mod_q(z*!((cast x')-!(cast y'))).
- 8 STANDALONE createi-free lemma_inv_layer_L_lane_cong (dispatch parity via intt_layer_L_lane) +
  lemma_intt_layer_L_cong (createi unfold). KEEP createi reduction OUT of the standalone lane-cong (cascade avoidance).
- lemma_intt_compose_8: chains intt_layer 0→7 (ORDER 0→7, opposite forward) targeting the UNSCALED 8-fold chain
  (i.e. result of intt_layer 0..7 WITHOUT reduce_polynomial). Hypotheses: f_{L+1} ≡ intt_layer f_L L.
- 8 #[cfg(hax)] snapshots in invert_ntt_montgomery (s0 before L0 ... s7 after L6) + compose call.
  invert_ntt_montgomery body currently invntt.rs:490-520.

## PHASE E — scaling + top ensures (invntt.rs invert_ntt_montgomery loop)
*** HEADLINE OFF BY R (F*-confirmed): out ≡ R·intt(in) mod q, R=4193792. mont_mul(_,41978)≡·16382=R·256^{-1}. ***
- lemma_reduce_scale (x:i32): (v(mont_mul x (mk_i32 41978)))%q == (16382 * v x)%q   [via lemma_mont_mul_bound_and_mod_q + assert_norm(41978*8265825 % q==16382)]. (NOT 8347681!)
- lemma_reduce_scale_chunk_to_hacspec: lift over 32 chunks: out_flat[i] ≡ 16382*chain[i] ≡ R*reduce_polynomial(chain)[i] = R*intt(in)[i].
- Wire the 41978 loop's loop_invariant + functional post (mirror ntt body); compose with D's unscaled post.
- TOP ensures: out_flat[i]%q == (R * (intt in_flat)[i])%q   (or to_mont(intt in_flat)). SETTLE with user / honest form; do NOT prove false ==intt.
- Final gate: JOBS=2 ./hax.sh prove 0 errors; regen ml_dsa_verification_status.md.
