# NTT functional driver wiring — layers 0/1/2 (Task A3, 2026-06-04)

Continuation of `ntt-functional-layers012-2026-06-03.md` (within-chunk bridges,
per-SIMD-unit FE posts, A3a zeta-table bridge all done). This session = **A3**:
wire the 32-chunk drivers `ntt_at_layer_{0,1,2}` ensures to the canonical
`Hacspec_ml_dsa.Ntt` poly composition lemmas. **DONE — all 3 drivers verify
admit-free.**

## Result

`src/simd/portable/ntt.rs` `ntt_at_layer_{0,1,2}` now each carry, in addition to
the `is_i32b_polynomial` bounds post, a **functional** ensures:

```
forall i<256. (v (simd_units_to_array (chunks_of_re re_future))[i]) % q ==
              (v (Hacspec_ml_dsa.Ntt.ntt_layer (simd_units_to_array (chunks_of_re re)) k)[i]) % q
```

Commits (branch ml-dsa-proofs):
- `2346c5745` — layer 2.
- `8fcb8e702` — layers 0 + 1 (+ the two mechanical fixes below).

## Architecture (the key idea: keep the 32-round composition light)

The first attempt (raw 12-conjunct FE relations on the inner `round` post +
`forall32x4_elim` in the driver body) **saturated** — the driver VC carried 32×
raw butterfly arithmetic + two-direction frame congruence and a single z3 ran
>10 min / 3.3 GB. Fix = the **opaque-atom** pattern (mirrors how the bounds post
composes):

1. `unit_fe_post_l{0,1,2}` — an `[@@ "opaque_to_smt"]` ground 12-conjunction
   capturing one chunk's butterfly relations (refined zeta args: `{is_i32b
   4190208 _}` for the `montgomery_multiply_fe_by_fer` precondition). Matches the
   `simd_unit_ntt_at_layer_k` post **exactly**, so the inner `round` discharges
   it with a plain `reveal_opaque` after the simd-unit call.
2. The driver composes `forall32 (fun b -> unit_fe_post_lk (orig[b]) (fut[b])
   …zeta_r…)` by **congruence + frame** over the 32 opaque atoms — no raw
   arithmetic in the WP, exactly like the `is_i32b_polynomial` bounds post.
   `N` `assert_norm (zeta_r idx == <impl literal>)` connect each hardcoded round
   zeta to the symbolic `zeta_r` witness (32 / 64 / 128 for layers 2 / 1 / 0).
3. `lemma_l{0,1,2}_driver_compose` (clean context) does the heavy lifting:
   `forall32_elim_1d` (ground→symbolic, 32-arm match) → `lemma_atom_to_bf_lk`
   (reveal the atom + per-pair `introduce forall … with match`) → the zeta
   congruence (`zeta_r` ensures + `lemma_v_zetas_eq_zeta`, via `Classical.
   forall_intro`) → `lemma_ntt_layer_k_step_to_hacspec_poly`.

Result: driver max sub-query rlimit **<< 400** (module-wide max ~107), compose
lemmas ~10–120 ms.

## Two mechanical fixes (in `8fcb8e702`)

- **Extraction ordering**: hax hoists the nested `round` fn (`ntt_at_layer_0___round`)
  ABOVE its outer fn's `before`-blocks, so `unit_fe_post_l0` (a before-block on
  `ntt_at_layer_0`) landed AFTER the layer-0 round that uses it → `Error 72
  Identifier not found`. (Layers 1/2 escaped: their rounds are hoisted after
  layer-0's before-blocks.) FIX: moved the whole helper cluster (atoms +
  `lemma_atom_to_bf_*` + `lemma_l*_driver_compose` + `forall32_elim_1d` +
  `chunks_of_re`) to the FIRST fn (`simd_unit_ntt_step`) so it precedes every
  `ntt_at_layer_*___round`.
- **Proc-macro recursion**: the dense `before`-block stack overflows the default
  `recursion_limit` during `#[_hax::json]` expansion (`recursion limit reached`).
  FIX: `#![recursion_limit = "1024"]` in `lib.rs` (compile-time only; does NOT
  affect extracted F* or runtime).

## Gates

- Per-driver: `rm` the `.checked`, full `fstar_build check/…Portable.Ntt.fst`,
  NO `--admit_except`. Layer 2 alone: exit 0, 3717 query-stats. All 3: exit 0,
  ~22.75 min, `failed_modules=[]`, fresh `.checked`, **0 admits in ntt.rs**.
  (`failed {…} (with hint)` lines on `chunks_of_re` / `lemma_l2_driver_compose`
  sub-queries / `get_n_least_significant_bits` are the benign split-retry
  pattern — build exit 0.)
- Full-crate `JOBS=2 ./hax.sh prove`: **GREEN** — 79 modules invoked (74 CHECK +
  5 ADMIT pre-existing), 79 verified, **0 F* errors, 0 make failures**. No
  downstream regression from the strengthened driver posts.
- `ml_dsa_verification_status.md` regenerated: **tier improvement** — 3 Portable
  `ntt` functions moved Bounds→Hacspec (now cite `Hacspec_ml_dsa.Ntt`). Portable
  Hacspec 61→64, Bounds 67→64. lax count unchanged (0 admits added).

## Recipe reuse (cross-chunk layers 3-7 / final theorem)

The opaque-atom + `forall32_elim_1d` + `lemma_atom_to_bf` + clean
`*_driver_compose` recipe generalizes: for any per-chunk butterfly driver whose
inner round surfaces a fixed-shape FE post, bundle the post into an opaque atom,
compose `forall32` of atoms by frame in the driver, and do the symbolic lift +
poly-lemma call in a clean top-level lemma. The `recursion_limit` bump + the
"move helper cluster ahead of the first nested round" ordering rule are
prerequisites once the before-block stack gets dense.

## NEXT
- Cross-chunk layers 3-7 (`outer_3_plus` drivers; Commute.Bridges port) — these
  use `outer_3_plus` (a loop, not 32 explicit rounds), so the composition shape
  differs (loop invariant carries the atom forall).
- 8-layer compose → `== Hacspec_ml_dsa.Ntt.ntt` top driver.
- Inverse track.
