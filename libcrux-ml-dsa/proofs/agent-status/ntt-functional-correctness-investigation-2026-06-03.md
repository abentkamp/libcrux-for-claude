# ML-DSA NTT Functional-Correctness Investigation (read-only study)

> NOTE ON FILE LOCATION: the task asked for this report at
> `/Users/karthik/libcrux-ml-dsa-proofs/libcrux-ml-dsa/proofs/agent-status/ntt-functional-correctness-investigation-2026-06-03.md`.
> Plan mode restricted writes to this plan file only, so the full report lives here.
> Copy verbatim to that path to land the intended deliverable (no other edits made; investigation was 100% read-only).

---

# A. ML-KEM NTT functional-correctness ARCHITECTURE (the template)

## A.0 End-to-end shape

The ML-KEM proof connects a backend-specific imperative NTT to the math spec
`Hacspec_ml_kem.Ntt.ntt` through THREE strata, each backend-generic above the
SIMD-intrinsic leaf:

```
 per-backend impl (Portable / Avx2 / Neon)            [backend-SPECIFIC, has admits in leaves]
   Vector.{Portable,Avx2,Neon}.Ntt.{ntt_layer_N_step}
     ensures: bounds  +  Spec.Utils.ntt_layer_N_butterfly_post   <-- BACKEND-GENERIC predicate
        |
   above-trait driver  Libcrux_ml_kem.Ntt.{ntt_at_layer_*, ntt_vector_u}
     each per-vector ensures: forall i<16. pv_post (per-vector spec-commute atom)
        |
   commute bridges  Hacspec_ml_kem.Commute.{Ntt_bridge,Invert_ntt_bridge,Bridges,Chunk}
     pv_post forall  ->  poly_step (to_spec_poly == N.ntt_layer)  ->  lemma_compose_7
        |
   FINAL: to_spec_poly_plain re_future == Hacspec_ml_kem.Ntt.ntt (to_spec_poly_plain re)
```

The top theorem is `Libcrux_ml_kem.Ntt.ntt_vector_u` (fst line 217 of fsti, body 1427):
```
(ensures ... is_bounded_poly 3328 re_future /\
  Hacspec_ml_kem.Commute.Chunk.to_spec_poly_plain re_future
    == Hacspec_ml_kem.Ntt.ntt (to_spec_poly_plain re))
```
`to_spec_poly_plain` (Chunk.fst:1474) maps the 16-vector `PolynomialRingElement`
impl repr to a `t_Array P.t_FieldElement 256` math poly; `_mont` is the Montgomery-form
variant used on the inverse track.

## A.1 The math spec

`Hacspec_ml_kem.Ntt.ntt` (extraction/Hacspec_ml_kem.Ntt.fst:341) is a fixed unfolding of
7 `ntt_layer p layer` calls, layers 7,6,...,1. `ntt_layer` (line 321) selects a zeta slice
`ZETAS[groups..2*groups]` (`groups = 128/len`, `len = 1<<layer`) and calls `ntt_layer_n`
(line 274). `ntt_layer_n` is a **`createi`** over 256 indices, each index doing a
`butterfly` lo/hi half-select (line 296-310). `butterfly zeta a b` (line 253) = `(a + zeta*b, a - zeta*b)`.
This `createi`-of-`if`-of-`butterfly` shape is the source of the `createi_lemma` SMTPat
cascade hazard.

## A.2 Role of each Commute.* file

- **Commute.Chunk.fst** (3012 lines): the algebraic leaf layer. Contains (a) per-lane
  field-element commute lemmas (`lemma_butterfly_fe_commute_plus/minus`,
  `lemma_butterfly_pair_commute`, Mont/plain reconciliation `lemma_mont_zeta_cancel`,
  `lemma_1441_eq_RR_div_128`), (b) the impl-repr -> spec-poly maps `to_spec_poly_plain`/`_mont`
  (line 1474/1488) and `poly_lane_*`, (c) `lemma_poly_barrett_reduce_id`/`_commute` used for
  the final reduce, (d) the opaque inverse-track atom `intt_mont_form_lane` (line 1788).
  This is the file ML-DSA already has a (much smaller) analog of.

- **Commute.Bridges.fst** (1697 lines): the per-layer "lane bridge" + "to_hacspec" layer.
  Two families:
  * `lemma_ntt_layer_N_step_lane_bridge` / `lemma_ntt_layer_N_step_to_hacspec` (N=1,2,3):
    take a single SIMD-vector `_butterfly_post` and prove the per-lane butterfly relations,
    then lift to the within-16 `ntt_layer_n` spec.
  * The layer-4-plus (cross-vector) machinery: `cross_vec_hyp` (opaque, line 1380),
    `lemma_layer_4_plus_per_coeff` (line 1408), `lemma_layer_4_plus_cross_vector` (line 1478),
    `lemma_ntt_inverse_layer_unfold` (line 1522), plus index lemmas
    (`lemma_cross_idx`, `lemma_partner_idx_add/sub`, `lemma_vec_partner_hi`).
  * `lemma_zeta_eq_vzetas` (val, line 1511): the zeta-table indexing bridge
    (impl Mont-zeta vs `N.v_ZETAS` standard zeta).

- **Commute.Ntt_bridge.fst** (1039 lines): the FORWARD composition spine. Key pieces:
  * `pv_post` (opaque, line 427): the per-vector spec-commute atom — for vector `m<16`,
    `mont_i16_to_spec_array cout[m] == N.ntt_layer_n 16 (mont_i16_to_spec_array cin[m]) len pvm`.
    This is the "producer-side opaque atom" — the above-trait driver's per-layer ensures is a
    `forall i<16. pv_post ...`, and the bridge consumes that forall. `pv_post_intro`/`_elim`
    (line 439/452) are the reveal wrappers.
  * `lemma_intra_vec_per_coeff` (line 472) + `lemma_intra_vec_layer_to_poly` (line 559,
    `--split_queries always`): chain the 16 `pv_post` atoms (+ a zeta-slice reconstruction)
    into the per-coefficient butterfly relation over all 256 coeffs, then into
    `to_spec_poly_plain cout == N.ntt_layer (to_spec_poly_plain cin) layer`.
  * `poly_step` (opaque, line 597): `to_spec_poly_plain re_out == N.ntt_layer (to_spec_poly_plain re_in) layer`.
  * `lemma_layerN_to_poly_step` (N=1,2,3 lines 643/693/748; layer_4_plus 952) and
    `lemma_compose_7` (line 616): the 7-fold INDUCTION. `lemma_compose_7` takes seven
    `poly_step` atoms in layer order 7..1, reveals each, and calls `lemma_ntt_unfold` (line 409)
    which unfolds the fixed 7-call definition of `N.ntt`. **This is the heart of the composition.**

- **Commute.Invert_ntt_bridge.fst** (680 lines): mirror of Ntt_bridge for the inverse track,
  with `lemma_ntt_inverse_layer_unfold_lo` / `lemma_ntt_inverse_butterflies_unfold`, its own
  `pv_post`/`poly_step`/`lemma_compose_7`, and `lemma_layerN_to_poly_step` (N=1,2,3).

- **Commute.ProofUtils.fst** (23 lines): just `map_array` helper.

## A.3 The driver composition (Libcrux_ml_kem.Ntt.fst:1427 ntt_vector_u)

Pattern (the recipe to copy): name every intermediate poly `re0..re7`; run the 7 layer
functions sequentially; after layers 3/2/1 call
`lemma_layer3/2/1_to_poly_step re_prev re_cur` (each turns that layer's `forall pv_post`
ensures into a `poly_step` atom); then ONE `lemma_compose_7 re0..re7` collapses the chain to
`to_spec_poly_plain re7 == N.ntt (to_spec_poly_plain re0)`; then bound-widen
(`is_bounded_poly_higher`) and `poly_barrett_reduce` + `lemma_poly_barrett_reduce_id` to land
the final `3328` bound while preserving the spec equality. The layer-4-plus group is folded by
its own `lemma_layer_4_plus_to_poly_step` / `lemma_cross_vec_from_step_fwd`.

## A.4 Per-backend split & the trait/SIMD-model boundary

- The backend-SPECIFIC content lives ONLY in `Vector.{Portable,Avx2,Neon}.Ntt.fst`. Each
  `ntt_layer_N_step` proves: bounds (`is_i16b_array (k*3328)`) **and**
  `Spec.Utils.ntt_layer_N_butterfly_post vec_in vec_out z..` — a **backend-GENERIC** predicate
  defined in `Spec.Utils.fsti:617-642` as a bundle of 8 `ntt_spec vec_in zeta i j vec_out`
  per-butterfly congruences (`ntt_spec`, fsti:597, is `out[i]%q == (in[i]+in[j]*zeta*169)%q /\
  out[j]%q == (in[i]-in[j]*zeta*169)%q`). Because the post is stated on the abstract i16 array
  view (`vec256_as_i16x16` for Avx2, `.f_elements` for Portable), the SAME commute bridge
  proves all three backends — the bridge never sees vec256 intrinsics.
- The SIMD-model boundary is crossed exactly at `pv_post`: the driver's per-layer ensures
  carries `forall i<16. pv_post cin cout len pvm i`; `pv_post` internally uses
  `mont_i16_to_spec_array (T.f_repr ...)`, i.e. the trait `f_repr` projection, so it is
  backend-generic. The `_butterfly_post` -> `pv_post` step is done inside
  `lemma_layerN_to_poly_step` (Bridges' `_to_hacspec` lemmas feed it).
- **createi_lemma cascade mitigation**: `ntt_layer_n` is `createi`-based, and
  `to_spec_poly_*` is `createi`-based, so a `[SMTPat (Seq.index (createi f) i)]` re-matches
  recursively inside the composition. The mitigation visible in the bridges: every spec-commute
  fact is wrapped in an `opaque_to_smt` atom (`pv_post`, `poly_step`, `cross_vec_hyp`) and
  revealed only at the precise consumer (`reveal_opaque (\`%poly_step) ...`), so the createi
  SMTPat never fires across the whole forall. `--split_queries always` on the heavy
  `lemma_layerN_to_poly_step` / `lemma_intra_vec_layer_to_poly` isolates each lane query.

## A.5 Forward vs inverse — what made each closeable

- Same skeleton. Inverse differs in: Montgomery domain throughout (`to_spec_poly_mont`,
  `intt_mont_form_lane`), butterfly is Gentleman-Sande (`(a+b, (b-a)*zeta)`), and the FINAL
  per-element `·R²/128` step (`1441 = R²/128 mod q`) is **fused into the next caller op** rather
  than applied in `invert_ntt_montgomery` itself (`invert_ntt_montgomery` post stops at
  `ntt_inverse_butterflies`, the FIPS-203 `ntt_inverse` fusion is the caller's `mont_mul(_,1441)`).
- Inverse was "USER-15 job B": closeable once the `createi` cascade was tamed via the
  producer-side opaque `pv_post` atom + reordering aux-defs before `forall_intro` +
  `--split_queries always` + clean-context division grounding (per MEMORY note
  project_user15_jobB_inline_lift). Forward (e6fde3497) was the mirror.

---

# B. ML-DSA NTT current state + the precise functional HOLES

## B.0 What EXISTS

- **Math spec is PRESENT and structurally KEM-shaped**: `Hacspec_ml_dsa.Ntt`
  (specs/.../extraction/Hacspec_ml_dsa.Ntt.fst) has `ntt` (line 124, fixed 8-layer unfold 7..0),
  `ntt_layer` (line 86, `createi`-of-`if`-of-butterfly, zeta index `round + k`, `k=128/len`),
  `intt` (line 188, 8-layer unfold 0..7 + final `reduce_polynomial`), `intt_layer` (line 140,
  zeta index `k - round`, `k = 256/len - 1`), `bit_rev_8_` (line 60), `v_ZETAS: t_Array i32 256`
  (line 7), `reduce_polynomial` (line 177, `×8347681 = 256^-1 mod q`).
  NOTE: `Spec.MLDSA.Ntt.fst` (proofs/fstar/spec) is the OBSOLETE hand-written tier — marked
  DELETION-PENDING (Phase 4B); only AVX2 proofs still cite it. The canonical spec is `Hacspec_ml_dsa.Ntt`.
- **Commute.Chunk.fst** (the ONLY commute file): has the algebraic primitives needed to START
  the bridge, but the NTT-specific content is minimal:
  * `simd_units_to_array` (line 776): the `[Coefficients;32]` -> `t_Array i32 256` map
    (= ML-KEM's `to_spec_poly_*`, but PLAIN i32, `createi`-based).
  * `lemma_simd_units_to_array_reveal` (786) + `lemma_simd_units_to_array_other_chunk_unchanged`
    (803): index-reveal + frame property. Real proofs.
  * `lemma_butterfly_step_fe` (847): the per-butterfly Mont->std-zeta congruence bridge
    (`v t %q == hi*zeta_mont*8265825 %q` & `zeta_mont %q == zeta_std*2^32 %q` ==>
    `lo_new %q == (lo_old + hi_old*zeta_std)%q` etc). Real proof. This is the ML-DSA analog of
    ML-KEM's `lemma_butterfly_fe_commute_*` + `lemma_mont_zeta_cancel`.
  * `lemma_mont_mul_bound_and_mod_q` (656): full Montgomery-reduction bound+congruence. Real proof.
- **Per-backend BOUNDS proofs are essentially done**: `Portable.Ntt.fst` and `Portable.Invntt.fst`
  have **0 admits**; `Avx2.Ntt.fst` has **0 admits**; `Avx2.Invntt.fst` has **4 `admit() (* Panic freedom *)`**
  (layers 3, 4, 7 region). `Portable.Ntt.ntt` (line 1239) is fully proven with post
  `is_i32b_polynomial (NTT_BASE_BOUND + 8*FIELD_MAX)`.

## B.1 The precise HOLES (relative to A)

1. **Trait posts are bounds-only — no functional conjunct.**
   `Libcrux_ml_dsa.Simd.Traits.fst:523 f_ntt_post` = `forall32. is_i32b_array_opaque FIELD_MAX`,
   and `:541 f_invert_ntt_montgomery_post` = `forall32. is_i32b_array_opaque 4211177`.
   NO `== Hacspec_ml_dsa.Ntt.ntt` / `intt` conjunct exists. (ML-KEM's trait/driver carries the
   `pv_post` forall and the final driver carries `to_spec_poly == N.ntt`.)

2. **Per-backend layer posts are bounds-only — no `ntt_spec` analog.** Confirmed by grep:
   NO `% 8380417 ==` functional congruence anywhere in `Portable.Ntt.fst`, `Avx2.Ntt.fst`,
   `Portable.Invntt.fst`. The layer-step posts (e.g. `simd_unit_ntt_step` post at
   Portable.Ntt.fst:30-46) carry only the accumulating bound
   `is_i32b (NTT_BASE_BOUND + (factor+1)*FIELD_MAX)` + `modifies2_8` framing.
   **There is no `Spec.Utils.ntt_spec` / `ntt_layer_N_butterfly_post` analog for ML-DSA.**

3. **No `Hacspec_ml_dsa.Commute.Ntt_bridge`, `.Invert_ntt_bridge`, or `.Bridges` files at all.**
   The entire middle stratum (pv_post/poly_step/lemma_compose, lane bridges, to_hacspec,
   layer-4-plus cross-vector, zeta-table bridge) is ABSENT.

4. **`lemma_ntt_full_commute` does NOT yet exist.** Despite the catalog entry
   (outstanding-admits.md:54), grep finds NO `lemma_ntt_full_commute` definition in
   `Commute.Chunk.fst`. The only `admit ()` in that file is `lemma_decompose_spec_eq_decompose`
   (line 639) — a DECOMPOSE bit-trick admit, unrelated to NTT. So the catalog's "admitted
   full_commute" is really "not-yet-written full_commute" — the NTT composition spine is
   entirely TODO (see the comment block lines 824-887 which scopes the next-session lane bridge).

5. **Two Portable trait-wrapper `admit()`s — a BOUNDS mismatch, not functional.**
   `Libcrux_ml_dsa.Simd.Portable.fst:1259` (`f_ntt`) and `:1288` (`f_invert_ntt_montgomery`)
   each have `let _ = admit () in` before calling `Portable.Ntt.ntt` / `Portable.Invntt....`.
   The cause is concrete: `Portable.Ntt.ntt`'s proven post is
   `is_i32b_polynomial (NTT_BASE_BOUND + 8*FIELD_MAX)` ≈ 75M, but `f_ntt_post` PROMISES
   `is_i32b_array_opaque FIELD_MAX` ≈ 8.38M. The impl as written does NOT do a final reduction,
   so the trait post is **unsatisfiable as stated** without either (a) a final Barrett reduce in
   the impl path, or (b) loosening the trait post bound. The admit papers over exactly this gap.
   Inverse: `Portable.Invntt` proven bound vs trait's `4211177` — same shape.

6. **Avx2.Invntt 4 panic-freedom admits** (layers 3/4/7) — pure bounds/overflow, backend-specific.

---

# C. TRANSFERABILITY analysis

| ML-KEM pattern | ML-DSA | Notes |
|---|---|---|
| Math spec `N.ntt` = fixed N-layer createi unfold; `butterfly` lo/hi | **TRANSFERS DIRECTLY** | `Hacspec_ml_dsa.Ntt.ntt`/`ntt_layer` is the SAME shape, already present. 8 layers (7..0) vs 7. `lemma_ntt_unfold`/`lemma_compose_7` become `lemma_compose_8`. |
| `to_spec_poly_plain`/`_mont` repr map | **MOSTLY DONE** | ML-DSA already has `simd_units_to_array` (PLAIN i32) + reveal/frame lemmas. But there is NO `_mont`/`_plain` distinction yet — forward is Mont-domain throughout in ML-DSA (i32 stays in standard-rep per `mod_q`?), need to confirm which domain each track wants. |
| `Spec.Utils.ntt_spec` + `ntt_layer_N_butterfly_post` (backend-generic per-vector post) | **NEW WORK** | Must be authored for ML-DSA (i32, q=8380417, Mont factor 8265825, lane geometry 8-lane chunks not 16). This is the keystone that lets one bridge serve Portable+Avx2. |
| `pv_post` opaque per-vector atom + `lemma_intra_vec_layer_to_poly` | **ADAPT** | ML-DSA uses `[Coefficients;32]` of 8 lanes = 256 coeffs (vs ML-KEM 16 vectors of 16 lanes). The "intra-vector" geometry (8 lanes) and "cross-vector" boundary (chunk size 8) differ; `simd_units_to_array` flat index `8b+l` replaces ML-KEM's 16-lane indexing. Layers 0/1/2 are within-chunk (len 1/2/4 < 8); layers 3..7 are cross-chunk. So the within/cross split point moves (KEM: within at len 2/4/8 i.e. layers 1/2/3; DSA: within at len 1/2/4 i.e. layers 0/1/2). |
| `lemma_layerN_to_poly_step` + `lemma_compose_7` induction | **ADAPT (one more layer)** | 8 layers. Forward 7..0, inverse 0..7. Indexing: zeta `round + 128/len` fwd, `256/len-1 - round` inv — different from KEM's `groups..2*groups` slice but same createi structure. |
| `lemma_zeta_eq_vzetas` (Mont-zeta vs std-zeta table) | **ADAPT** | ML-DSA already has the per-butterfly half via `lemma_butterfly_step_fe` (carries `zeta_mont %q == zeta_std*2^32 %q` as a hypothesis). Need the table-wide `zeta_mont[i] == ZETAS[i]` discharge for all 256/255 indices. |
| createi_lemma cascade hazard | **APPLIES — same hazard** | Both `Hacspec_ml_dsa.Ntt.ntt_layer` and `simd_units_to_array` are createi-based; the comment block (Chunk.fst:881-887) already flags it as "Z3-risky" and prescribes the opaque-atom + per-lane factor + `Classical.forall_intro` + `Seq.lemma_eq_intro` recipe — i.e. the ML-KEM mitigation transfers. |
| Final reduce (`poly_barrett_reduce` fwd / `mont_mul 1441` inv fused) | **DIFFERS** | ML-DSA inverse ends with `reduce_polynomial` (×`8347681 = 256^-1 mod q`) INSIDE `intt` (not fused into caller like KEM's 1441). ML-DSA forward does NOT reduce at the end (hence the 75M bound). |
| Montgomery bound growth | **DIFFERS — this is the BOUNDS hole** | KEM forward driver reduces to land `3328`. ML-DSA forward accumulates `NTT_BASE_BOUND + k*FIELD_MAX` and the impl never reduces, so `Portable.Ntt.ntt` exits at `+8*FIELD_MAX`. The trait post `FIELD_MAX` is therefore unmet -> the wrapper admit. Inverse exits at `4211177` (= FIELD_MID-ish), trait post matches that bound, so the inverse wrapper admit is a tightness/propagation gap not an unsatisfiable-claim gap. |

### Top transferability risks / differences
1. **The trait `f_ntt_post` FIELD_MAX bound is unsatisfiable for the impl as written.** This is
   the single biggest non-mechanical issue: closing the Portable wrapper admit requires either a
   spec/trait-post change (loosen to `+8*FIELD_MAX`, matching the impl — preferred per MEMORY
   "no code changes for proofs") or accepting that the bound needs a reduce the impl doesn't do.
   Must be resolved before any functional post can compose through the trait.
2. **No `ntt_spec`/`_butterfly_post` predicate exists** — the backend-generic functional post
   layer is entirely missing and must be authored (genuinely new). Everything above it depends on it.
3. **8-lane chunk geometry + 8 layers** shifts the within/cross-vector boundary and adds a layer
   to the induction; mechanical but error-prone in indexing.
4. **i32/q=8380417 is slower for Z3 than i16/3329** (flagged in Chunk.fst:882) — expect higher
   rlimits / more `--split_queries always` than ML-KEM needed; respect the rlimit≤800 / ≤400-with-split cap.
5. **SIMD-model unification is referenced as an alternative** for the Avx2 leaf admits
   (`simd-model-unification-plan.md`) but is NOT a blocker for the functional commute, which is
   backend-generic and proves over the `f_repr` i32-array view regardless of vec256 leaf admits.

---

# D. RECOMMENDED SEQUENCE to fill the holes

Ordered; each tagged [MECH]=mechanical port of ML-KEM, [NEW]=genuinely new ML-DSA work,
[DECISION]=needs a spec/trait-shape decision (surface to user per MEMORY no-code-changes rule).

**Prereqs / decisions first**
- **D0 [DECISION] Resolve the forward trait-post bound.** Decide whether `f_ntt_post` should be
  `is_i32b_array_opaque (NTT_BASE_BOUND + 8*FIELD_MAX)` (match impl, drop the wrapper admit
  immediately — a spec/post change, allowed) vs inserting a reduce. This unblocks D5 and is a
  pure-bounds question independent of functional work. ~LOW effort once decided. Risk: touches a
  shared trait `.fst` — re-extraction cascade.
- **D0b [MECH]** Confirm `Hacspec_ml_dsa.Ntt` is the canonical spec everywhere; do NOT depend on
  `Spec.MLDSA.Ntt` (deletion-pending). Migrate the 4 Avx2.Invntt citations off it if they block.

**Functional spec scaffolding (the keystone)**
- **D1 [NEW] Author the backend-generic per-butterfly functional predicate.** Add
  `ntt_spec`/`inv_ntt_spec` (i32, q=8380417, Mont factor 8265825) and the bundled
  `ntt_layer_N_butterfly_post` for ML-DSA's lane geometry, in a local consumer module
  (per MEMORY develop-locally; e.g. inside the new Ntt_bridge or an ml-dsa Spec.Utils analog).
  The per-butterfly algebra is already proven (`lemma_butterfly_step_fe`), so this is mostly
  packaging. ~MED. Risk: getting the 8-lane index map right.

**Per-backend functional posts**
- **D2 [NEW/ADAPT] Wire `ntt_layer_N_butterfly_post` into the per-backend layer-step posts.**
  Add the functional conjunct to `Portable.Ntt.{simd_unit_ntt_step, ntt_at_layer_N}` and the Avx2
  equivalents (proved from the existing bounds proof + `lemma_butterfly_step_fe`). Forward layers
  0/1/2 within-chunk, 3..7 cross-chunk. ~MED-HIGH (8 layers x 2 backends; but Avx2 reuses the same
  predicate on `vec256_as_i32x8`). Risk: Z3 cost at i32/q.

**Commute bridges (the spine)**
- **D3 [ADAPT] Create `Hacspec_ml_dsa.Commute.Ntt_bridge`**: port `pv_post` (opaque),
  `pv_post_intro/_elim`, `lemma_intra_vec_per_coeff`, `lemma_intra_vec_layer_to_poly`,
  `poly_step` (opaque), `lemma_layerN_to_poly_step` (within-chunk layers), and `lemma_compose_8`
  (8-fold, layer order 7..0) + `lemma_ntt_unfold` for `Hacspec_ml_dsa.Ntt.ntt`. ~HIGH.
  Mitigate createi cascade with opaque atoms + `--split_queries always` from the start.
- **D4 [ADAPT] Create `Hacspec_ml_dsa.Commute.Bridges`** for the cross-chunk (layer-3..7)
  machinery: `cross_vec_hyp`, `lemma_layer_*_plus_per_coeff/_cross_vector`, the index lemmas,
  `lemma_zeta_eq_vzetas` table bridge, and the unfold lemmas. ~HIGH. This is the hardest port
  (the layer-4-plus group in ML-KEM was the USER-14/15 work).

**Above-trait driver + final theorem**
- **D5 [MECH] Strengthen the above-trait `Libcrux_ml_dsa.Ntt.ntt` driver** to carry
  `simd_units_to_array re_future == Hacspec_ml_dsa.Ntt.ntt (simd_units_to_array re)` by the
  `re0..re7,re8` + per-layer `lemma_layerN_to_poly_step` + `lemma_compose_8` pattern, then add the
  matching functional conjunct to the trait `f_ntt_post`. ~MED, mostly copying ntt_vector_u's body.
- **D6 [ADAPT] Repeat D1-D5 for the inverse** (`Invert_ntt_bridge`, `lemma_intt_full_commute`,
  trait `f_invert_ntt_montgomery_post`, final `reduce_polynomial`/`8347681` step). ML-KEM says
  inverse is "direct adaptation once forward lands". ~HIGH but lower-risk than forward (template exists).

**Residual bounds admits**
- **D7 [bounds, SEPARATE from functional] Close the Avx2.Invntt 4 panic-freedom admits**
  (layers 3/4/7). Pure overflow/bound, independent of functional commute; can be done anytime, or
  via SIMD-model unification. ~MED.

### BOUNDS vs FUNCTIONAL — do them together or separately?
- **Do the two Portable wrapper admits (D0) SEPARATELY and FIRST** — they are a pure bounds/trait-post
  tightening question (the impl bound 75M vs the post bound 8.38M), decidable without any commute work,
  and currently the trait post is *unsatisfiable as written*. Resolving D0 also removes a confounder:
  once the wrapper compiles without admit, the functional conjunct (D5) can be added cleanly.
- **The FUNCTIONAL closure (D1-D6) is the large, genuinely-new body of work** and should be sequenced
  spec-scaffolding (D1) -> per-backend posts (D2) -> bridges (D3-D4) -> driver (D5) -> inverse (D6).
- The Avx2.Invntt panic admits (D7) are orthogonal bounds work; bundle with whatever SIMD-model effort
  is convenient, not with the functional sprint.

### First 2-3 concrete steps to take
1. **D0**: decide+apply the forward trait-post bound fix and drop the two `Portable.fst` wrapper
   admits (bounds-only; surface the trait-post-change decision to the user first per no-code-changes rule).
2. **D1**: author the ML-DSA `ntt_spec` / `ntt_layer_N_butterfly_post` predicate (i32/q=8380417/8265825,
   8-lane geometry), proving it from the existing `lemma_butterfly_step_fe`.
3. **D3 scaffold**: create `Hacspec_ml_dsa.Commute.Ntt_bridge` with the opaque `pv_post`/`poly_step`
   atoms + `lemma_compose_8` skeleton (admit the lane bridges initially), then fill within-chunk layers
   first to validate the spine end-to-end before tackling the cross-chunk D4 group.
