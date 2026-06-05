# ML-DSA Inverse NTT proof campaign — orchestrator status (2026-06-05)

Worktree: /Users/karthik/libcrux-ml-dsa-proofs  branch ml-dsa-proofs  base 58febee0a (fwd NTT complete)
Goal: invert_ntt_montgomery functional correctness vs Hacspec_ml_dsa.Ntt.intt, mirroring forward.

## CRITICAL FINDING (F*-confirmed, /tmp/scaling_check.fst) — headline is off by R
- mont_mul(x,41978) % q == 16382*x % q  (loop's actual factor = 16382, NOT 8347681)
- spec reduce_polynomial multiplies by 8347681 = 256^{-1}
- 16382 == R*8347681 mod q, R = 2^32 mod q = 4193792
- => invert_ntt_montgomery(in) ≡ R * intt(in)  (mod q).  The literal "== intt" is OFF BY R.
- Cause: impl leaves result in Montgomery domain (×R); 41978 = R^2/256, mont divides by R, net R/256 = R·256^{-1}.
- Plan's Phase E note ("lands on 8347681*V_spec") was optimistic; lands on R·8347681·V_spec.
- IMPACT: only Phase E headline. Phases A-D (V_impl ≡ unscaled intt_layer chain) are unaffected.
- RESOLUTION: prove A-D clean; at Phase E prove the honest `out ≡ R·intt(in)` (or ask user). DO NOT fudge a false ==intt.

## Confirmed design facts
- GS inverse butterfly (impl simd_unit_inv_ntt_step): lo_new=lo+hi; hi_new=mont_mul(hi-lo, zeta_mont).
- spec intt_layer: even(idx<len)=mod_q(p[i]+p[i+len]); odd=mod_q(z*(p[i-len]-p[i])), z=(Q-ZETAS[k-round])%Q.
- k = 256/len - 1; zeta table index = k - round (vs forward round+128/64/...).
- Impl hardcoded inverse zeta_mont = zeta_r(k-r) (POSITIVE Montgomery rep): (v zeta_mont)%q == (zeta(k-r)*pow2 32)%q.
  Confirmed: zeta_r(1)=25847=impl L7 r0 ZETA. Sign cancels: hi_new≡(hi-lo)*zeta(k-r)=(lo-hi)*(-zeta(k-r))=(lo-hi)*z.

## Phase status
- A (Commute.Chunk inverse bridges): LAUNCHED (background). Scope = 8 layer bridges (within L0-2, cross L3-7); scaling DEFERRED to E.
- B/C/D/E: pending.
