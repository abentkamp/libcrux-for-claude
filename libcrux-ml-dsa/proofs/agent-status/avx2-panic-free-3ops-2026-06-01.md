# AVX2 panic-free 3 ops + follow-on survey (2026-06-01)

## DONE & committed (`860769ea4`)
Flipped `verification_status(lax)` → `panic_free` on the user's first-objective trio:
- `src/simd/avx2/invntt.rs::invert_ntt_montgomery` (+ nested `inv_inner`)
- `src/simd/avx2/arithmetic.rs::compute_hint`
- `src/simd/avx2/arithmetic.rs::use_hint`

Result: **lax 51 → 47 (8.6% → 7.9%)**, panic-free 278 → 282. Full `JOBS=4`
prove: 0 F* errors, 0 failed modules (build 23c9c053, ~280 s). Both touched
modules re-checked from scratch (stale `.checked` removed) exit 0.

### Why it was easy (and why the portable analog is harder)
AVX2 arithmetic is all SIMD intrinsics → **wraps, never panics**, so no
bounds-carrying loop invariant is needed (unlike portable's scalar `+`/mont).
- `invert_ntt_montgomery`/`inv_inner`: the 8 `invert_ntt_at_layer_*` fns and
  `montgomery_multiply_by_constant` carry **no precondition**; `re.len()==32`
  is static → in-bounds indexing. **No contract added.**
- `compute_hint`: added `requires gamma2 ∈ {GAMMA2_V261_888, GAMMA2_V95_232}`.
  The ONLY non-intrinsic panic risk is the i32 negation `-gamma2` at
  `mm256_set1_epi32(-gamma2)` (overflow at i32::MIN); the disjunction kills it.
- `use_hint`: added `requires gamma2 ∈ {…} ∧ (∀ i. is_i32b (FIELD_MODULUS-1)
  (to_i32x8 r i))`. gamma2 disjunction discharges the `_ => unreachable!()`
  arm + `decompose`'s gamma2 pre; the lane bound discharges `decompose`'s
  `∀ i. is_i32b (FIELD_MODULUS-1) (to_i32x8 r i)` pre.

### Soundness of the added preconditions
Both inner fns are called ONLY by their `*_with_proof` wrappers
(`avx2.rs:397` / `:423`), which `admit ()` first (so F* checks vacuously — the
discharge is on us). Verified true: the wrappers' existing `requires` carry the
same gamma2 disjunction and `is_i32b_array_opaque FIELD_MAX (f_repr simd_unit)`,
and **FIELD_MAX = FIELD_MODULUS-1 = 8380416**, so the lane bound holds exactly.

## Follow-on survey — NONE of the suggested clusters is "mechanical"
Investigated the prompt's suggested follow-ons; all need real (often bitvector
or bound-propagation) work, not a bare admit removal:

1. **avx2/encoding serialize** (t0:68, error:58/109, gamma1:52/106): each
   `serialize` body calls a `*_aux` fn with a **bit-level precondition**
   (e.g. t0 `serialize_aux` requires `∀ i. v i % 32 ≥ 13 ⟹ simd_unit.(i) ==
   Bit_Zero`). Removing the admit forces discharging that from the input bound
   through `change_interval`'s `mm256_sub_epi32` — bitvector reasoning. The
   bv256 functional ensures stays auto-admitted under panic_free, so it's
   "only" the `_aux` pre, but that pre is still bit-level. The fns ALSO need
   `out.len() == N` added (sound: trait `t0_serialize` etc. require it).
   avx2/encoding deserialize (gamma1:185/213): check load-length panic-freedom;
   may be lighter — not yet scoped.

2. **simd-top `ntt` / `invert_ntt_montgomery` dispatchers** (avx2.rs:909/925,
   portable.rs ~690/702): admit()'d wrappers whose `ensures` is a **tighter
   bound** (`is_i32b_array_opaque 4211177`) than the inner fns prove
   (portable inner: `is_i32b_polynomial FIELD_MAX=8380416`; avx2 inner: now
   panic_free, ensures auto-admitted = no bounds at all). Closing them requires
   strengthening the inner ensures to 4211177 and propagating — real work.

3. **rejection_sample dispatchers** (avx2.rs:712/725/738, portable.rs ~532/544):
   ⚠️ SOUNDNESS TRAP. Dispatcher `requires Seq.length randomness / 3 <= …` but
   calls inner `sample` which `requires input.len() == 24` (avx2 field_modulus)
   / `== 4` (eta). The admit() masks a precondition GAP — the dispatcher's pre
   is too weak to discharge the inner's exact-length pre. Also the dispatcher's
   bounds ensures (`v out[i] ∈ [0,8380417)`) is NOT in the inner `sample`
   ensures (which is only `future(output).len()==output.len() && result<=8`).
   Before un-admitting, audit the generic caller (does it always pass 24/4-byte
   chunks?) and likely tighten the dispatcher `requires` to `== 24`/`== 4`.

## Recommended next mechanical-ish target
None obvious in avx2 simd-top/encoding. Candidates worth scoping fresh:
- avx2/encoding **deserialize** load-length panic-freedom (gamma1:185/213) — may
  avoid the `_aux` bit-level pre that the serialize side has.
- portable/simd (top) remaining admits (532/544/556/687/702) mirror avx2 —
  same bound/precondition issues, not mechanical.
The genuinely-additive work is bound-strengthening on the inner ntt/invntt
ensures (item 2) — a coherent but non-trivial cluster.
