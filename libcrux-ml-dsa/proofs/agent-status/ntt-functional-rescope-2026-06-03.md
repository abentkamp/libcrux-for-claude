# ML-DSA NTT functional-correctness plan — RE-SCOPE (2026-06-03)

READ-ONLY investigation. Worktree `/Users/karthik/libcrux-ml-dsa-proofs`, branch
`ml-dsa-proofs`, HEAD 81bbb077f. Corrects the prior plan's "no functional NTT
proofs exist anywhere" premise (KNOWN-WRONG) and updates D1–D3.

---

## (A) Corrected state map — what functional NTT machinery EXISTS today

The prior plan's "no functional anywhere" was wrong in TWO directions: avx2
already has substantial functional proofs, and a detailed Portable→Hacspec plan
plus partial bridge infrastructure already exist.

| Backend | Bounds (== `is_i32b`) | Functional (== spec) | Spec targeted | How far it composes |
|---|---|---|---|---|
| **avx2** (`src/simd/avx2/ntt.rs`, `invntt.rs`) | NONE (zero `is_i32b` facts in the whole file) | **YES — per-step + per-layer**, fully proven | **`Spec.MLDSA.Ntt.ntt_step` / `inv_ntt_step`** (the OBSOLETE spec) | Stops at the 5 per-layer fns (`ntt_at_layer_{0,1,2}`, `ntt_at_layer_5_to_3`, `ntt_at_layer_7_and_6`). The top-level `ntt(re)` has only `[@@opaque_to_smt]` and NO functional ensures; layers are NOT chained. |
| **Portable** (`src/simd/portable/ntt.rs`, `invntt.rs`) | YES — full per-layer `is_i32b_polynomial` accumulation (`NTT_BASE_BOUND + k·FIELD_MAX`), settled by D0 | NONE — every ensures is bounds-only, including the misleadingly-named `simd_unit_ntt_step` | n/a | bounds chain to top; functional absent |
| **Trait wrappers** (`src/simd/avx2.rs:917, 940`) | `NTT_OUTPUT_BOUND` post is present but **`admit()`-ed for avx2** (avx2 carries no bound facts to discharge it); Portable side discharges it for real | n/a | bound post only | — |

avx2 functional shape (per layer): `ensures` is `Spec.Utils.forall16 … forall4 …
(to_i32x8 nre0 jX, to_i32x8 nre0 jY) == ntt_step (mk_int zeta) (to_i32x8 re0 jX,
to_i32x8 re0 jY)` — i.e. per-lane-pair `ntt_step` equality, with the inline-Mont
zetas already related to standard zetas via `Spec.MLDSA.Ntt.zeta_r`.

CRUCIAL: nowhere is there an `== Hacspec_ml_dsa.Ntt.ntt` or `== ...ntt_layer`.
The canonical functional theorem is UNMET on BOTH backends. avx2 proves against
the deletion-pending spec and stops below the top; Portable proves only bounds.

Partial Hacspec-bridge infrastructure ALREADY EXISTS in
`specs/ml-dsa/proofs/fstar/commute/Hacspec_ml_dsa.Commute.Chunk.fst`:
- `simd_units_to_array` (32×8 chunks → flat 256) — the view function the final
  theorem needs.
- `lemma_simd_units_to_array_reveal` + `..._other_chunk_unchanged` (frame lemma)
  — DONE, the chunk↔flat plumbing for per-layer bridges.
- `lemma_butterfly_step_fe` — DONE: the per-butterfly algebraic bridge from
  Mont-form (`v t ≡ hi·zeta_mont·8265825`) to standard `mod_q` form, exactly the
  zeta-canonicalization the Hacspec spec needs.
- A `TODO (next session)` marks the next pieces: `lemma_ntt_layer_0_chunk_to_hacspec`
  + `lemma_ntt_layer_0_step_to_hacspec_poly`.

There is also a full prior `libcrux-ml-dsa/proofs/ntt-port-plan.md` (Apr 27) that
already lays out the Portable→`Hacspec_ml_dsa.Ntt` layer-by-layer plan (its
steps 3–13). The "D1 author a predicate / no functional exists" framing was
written without reference to it.

---

## (B) Spec.MLDSA.Ntt vs Hacspec_ml_dsa.Ntt — the decision

| | `Spec.MLDSA.Ntt` (impl-tree, `proofs/fstar/spec/`) | `Hacspec_ml_dsa.Ntt` (specs/, extracted) |
|---|---|---|
| Status | **DELETION-PENDING** (header says Phase 4A migrate citations → 4B delete) | **CANONICAL** |
| Shape | `ntt_step zeta (a,b)` = `let t=mont_mul b zeta in (add_mod a t, sub_mod a t)` — a single Mont-form **butterfly on a plain i32 pair**; plus `inv_ntt_step`, `zeta` (std table), `zeta_r` (Mont table, proven `≡ zeta·2^32 mod q` for all 256). NO whole-`ntt`. | `ntt`/`intt` (8-layer chain), `ntt_layer`/`intt_layer` (`createi`-of-`if` over flat 256), `v_ZETAS` (std table), `bit_rev_8_`, `reduce_polynomial`. Operates on `t_Array i32 256`. |
| Cited by | ONLY avx2 `ntt.rs` + `invntt.rs` (`open Spec.MLDSA.Ntt`, uses `ntt_step`/`inv_ntt_step`/`zeta_r`). Nothing else. | Commute.Chunk.fst design note references it as the target; not yet proven `==` anywhere. |

`ntt_step` and `ntt_layer` are NOT the same object and there is **no existing
bridge lemma** between them. `ntt_step` is one Mont butterfly on a pair;
`ntt_layer` is the standard-form `createi` over all 256 lanes. `lemma_butterfly_step_fe`
is exactly the (not-yet-applied) glue: it converts the Mont-form butterfly
equality that `ntt_step` gives into the `mod_q (lo±hi·zeta_std)` form that one
lane of `ntt_layer` requires.

**Decision: target `Hacspec_ml_dsa.Ntt` for the final theorem (it is canonical
and FIPS-faithful).** `ntt_step` should be KEPT as a useful intermediate (it is
the per-butterfly leaf), but it must be RE-HOMED out of the deletion-pending
`Spec.MLDSA.Ntt`. Cost of canonicalization is modest because the hard part
(`lemma_butterfly_step_fe`, `zeta_r`) is already done — but see blocker (D).

---

## (C) UPDATED D1–D3 plan

The old D1/D2/D3 ("author ntt_spec predicate; Portable within-chunk == ntt_layer
posts; Commute.Ntt_bridge spine → Hacspec") is structurally right but mis-scoped:
D1 is mostly a RE-HOME, not authoring, and there is more reusable machinery
(avx2 ntt_step proofs, Commute.Chunk lemmas, ntt-port-plan) than assumed.

**D1 — Predicate: RE-HOME + bridge, NOT author-from-scratch.**
- The per-step functional predicate already exists: `Spec.MLDSA.Ntt.ntt_step`
  (plain-i32 butterfly, backend-agnostic — operands are `i32` lanes projected
  via `to_i32x8` on avx2, would be Coefficients lanes on Portable). It is NOT
  vec256-specific.
- Action: move `ntt_step`/`inv_ntt_step`/`zeta_r` into a non-deletion module
  (either `Spec.MLDSA.Math`, which both backends already open, or a small new
  `…Ntt_step` module). Re-point avx2's `open Spec.MLDSA.Ntt`. This unblocks
  deleting `Spec.MLDSA.Ntt` later. Effort ~2–3 h (mechanical, but touches avx2
  ensures + re-extract; risk = avx2 re-verify cost).
- Do NOT author a fresh ML-KEM-style `ntt_spec`; `ntt_step` + `Hacspec_ml_dsa.Ntt.ntt_layer`
  already cover the two tiers (per-butterfly leaf + flat-256 layer).

**D2 — Within-chunk == ntt_layer: leverage Commute.Chunk; first slice on Portable.**
- The bridge target lemmas (`lemma_ntt_layer_0_chunk_to_hacspec`,
  `…_step_to_hacspec_poly`) are already specified as TODOs in Commute.Chunk.fst,
  with `simd_units_to_array`, the frame lemma, and `lemma_butterfly_step_fe`
  already proven. This is the bulk of D2's plumbing — DONE.
- Per-layer FUNCTIONAL posts must still be ADDED to Portable (`simd_unit_ntt_at_layer_{0,1,2}`
  + `ntt_at_layer_*`): today they are bounds-only. Strengthen them to
  `simd_units_to_array re_future == ntt_layer (simd_units_to_array re) k`.
- Effort: ntt-port-plan estimates ~3–4 h per (layer, direction) for layers 0/1/2
  + similar for cross-chunk layers 3–7.

**D3 — Compose spine → Hacspec: still NEW, but smaller.**
- `lemma_ntt_full_commute` (chain the 8 per-layer `== ntt_layer` posts into
  `== Hacspec_ml_dsa.Ntt.ntt`) has no complete analog (ML-KEM's USER-15 is the
  closest, but the inverse-NTT driver there IS now done — see MEMORY
  `project_user15_jobB_inline_lift`, `project_fwd_ntt_driver_post` — so a working
  recipe exists). Effort ~3–5 h once layers exist.
- The Spec.MLDSA.Ntt↔Hacspec "bridge" reduces to the zeta-canonicalization
  already captured by `lemma_butterfly_step_fe` + `zeta_r`; no separate
  whole-spec equivalence lemma is needed if D2 posts are stated directly against
  `Hacspec_ml_dsa.Ntt.ntt_layer`.

**Recommended order & single highest-value first step:**
1. **FIRST (highest value): Portable forward layer 0 within-chunk slice** —
   add the functional post to `simd_unit_ntt_at_layer_0` / `ntt_at_layer_0` and
   discharge via the already-proven Commute.Chunk lemmas
   (`lemma_butterfly_step_fe` + `simd_units_to_array` + frame). This is the
   smallest end-to-end vertical that proves `== ntt_layer …0` and validates the
   whole Mont→std→flat pipeline before scaling. Build on Portable (not avx2)
   because Portable's per-step fn is a clean 2-lane mutation and the chunk→flat
   plumbing already targets the portable Coefficients view.
2. Portable layers 1, 2 (within-chunk), then cross-chunk 3–7.
3. `lemma_ntt_full_commute` spine → `== Hacspec_ml_dsa.Ntt.ntt`; wire trait/`src/ntt.rs` posts.
4. Inverse NTT mirror (~70% of forward).
5. Re-home `ntt_step` out of `Spec.MLDSA.Ntt`, re-point avx2, delete `Spec.MLDSA.Ntt`.
6. (Optional, larger) port the functional posts onto avx2 too, reusing the same
   `ntt_step`→`ntt_layer` bridge but driven from avx2's existing per-layer posts.

---

## (D) Blockers / risks

1. **avx2 functional proofs are coupled to the deletion-pending spec.** avx2
   `ntt.rs`/`invntt.rs` `open Spec.MLDSA.Ntt` and cite `ntt_step`/`inv_ntt_step`/`zeta_r`.
   Deleting `Spec.MLDSA.Ntt` (Phase 4B) WOULD ORPHAN every avx2 functional
   proof unless those three are re-homed first (D1). Order matters: re-home
   before delete.
2. **avx2 has zero bound facts** → the trait `ntt`/`invert_ntt_montgomery`
   bound posts are currently `admit()`-ed for avx2 (`src/simd/avx2.rs:917,940`).
   Any avx2 functional work does NOT help the bound side; the avx2 bound admit
   is an independent debt (would need a full per-layer bound-accumulation proof
   on avx2, which only Portable has).
3. **`ntt_step` IS reusable across backends** (it is plain-i32, lane-level), so
   NO blocker there — the avx2 ntt_step proofs are not vec256-locked at the
   predicate level; only their *application* projects vec256 lanes. But the
   avx2 per-layer posts are stated in `to_i32x8`/`forall16`/`forall4` shape and
   would each need a separate chunk→flat reconciliation to reach `ntt_layer`
   (different from Portable's lane layout), so avx2 functional→Hacspec is extra
   work, not free reuse of Portable's bridge.
4. **Z3 cost on i32 mod q = 8380417** (vs ML-KEM i16/3329) is the standing
   performance risk flagged in both ntt-port-plan §5#3 and the Commute.Chunk
   TODO — the `ntt_layer` `createi`-of-`if` over 256 lanes is the expensive
   object; mitigate by factoring a top-level `layer_k_lane (i)` reducer.
