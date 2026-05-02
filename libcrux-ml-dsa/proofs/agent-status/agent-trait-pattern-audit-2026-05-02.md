# Trait pattern audit — `Operations` methods vs 3-part pattern (2026-05-02)

Read-only audit of `libcrux-ml-dsa/src/simd/traits.rs::Operations`
against the architectural pattern:

1. **Bounds-and-lengths precondition** — non-opaque, uses
   `bounded_i32_array` / `is_i32b_array_opaque` / length predicates.
2. **Bounds postcondition** — uses `bounded_i32` /
   `is_i32b_array_opaque`, often via opaque predicate.
3. **Correctness postcondition** — links output to a Hacspec or
   `Spec.MLDSA.Math` correctness function.

All written in Rust at the call site.

## Per-method audit

| Method | Bounds pre? | Bounds post? | Correctness post? | Effort | Notes |
|---|---|---|---|---|---|
| `zero` | ✗ | ~ | ~ | drive-by | Trivial pre; equality post only.  Add `bounded(0,0)`. |
| `from_coefficient_array` | ✗ | ✗ | ✓ | drive-by | No pre/post bounds; state caller obligation. |
| `to_coefficient_array` | ✗ | ~ | ✓ | drive-by | Missing pre bound; post inherits implicitly. |
| `add` | ✓ | ~ | ✓ | drive-by | Pre solid (`add_pre`); bounds post embedded in F* lemma `bounded_add_post` — surface to Rust. |
| `subtract` | ✓ | ~ | ✓ | drive-by | Pre solid; bounds post via `bounded_sub_post` lemma — surface. |
| `infinity_norm_exceeds` | ✓ | ✗ | ✓ | drive-by | Input bounded; result is bool (no output struct). |
| `decompose` | ✓ | ✓ | ✓ | **done** | Per-lane Hacspec `decompose_lane_post`; complete. |
| `compute_hint` | ✓ | ✓ | ✓ | **done** | Per-lane `Spec.MLDSA.Math.compute_one_hint`; complete. |
| `use_hint` | ✓ | ✓ | ✓ | **done** | Per-lane Hacspec `use_hint_lane_post`; complete. |
| `montgomery_multiply` | ~ | ✓ | ✓ | drive-by | lhs bound missing from pre (only rhs); add for symmetry. |
| `shift_left_then_reduce` | ✓ | ~ | ✓ | drive-by | Pre explicit; bounds in `shift_left_then_reduce_lane_post` — surface. |
| `power2round` | ✓ | ✓ | ✓ | **done** | Per-lane Hacspec `power2round_lane_post`; complete. |
| `rejection_sample_less_than_field_modulus` | ~ | ✓ | ~ | follow-up | Size checks only; no per-lane 3byte Hacspec post. |
| `rejection_sample_less_than_eta_equals_2` | ~ | ✓ | ~ | follow-up | Size checks only; no per-lane halfbyte Hacspec post. |
| `rejection_sample_less_than_eta_equals_4` | ~ | ✓ | ~ | follow-up | Size checks only; no per-lane halfbyte Hacspec post. |
| `gamma1_serialize` | ✓ | ✓ | ✗ | follow-up | Bounds + length present; no `bit_pack_chunk_post` correctness. |
| `gamma1_deserialize` | ~ | ✓ | ✗ | follow-up | Length check only; no `bit_unpack_chunk_post`. |
| `commitment_serialize` | ✓ | ✓ | ✗ | follow-up | Bounds + length present; no `bit_pack_chunk_post`. |
| `error_serialize` | ✓ | ✓ | ✗ | follow-up | Bounds + length present; no `bit_pack_chunk_post`. |
| `error_deserialize` | ~ | ✓ | ✗ | follow-up | Length only; no `bit_unpack_chunk_post`. |
| `t0_serialize` | ✓ | ✓ | ✗ | follow-up | Strict-lower + length present; no `simple_bit_pack_chunk_post`. |
| `t0_deserialize` | ✗ | ✓ | ✗ | follow-up | No pre on serialized bytes; no `simple_bit_unpack_chunk_post`. |
| `t1_serialize` | ✓ | ✓ | ✗ | follow-up | `[0, 2^10)` + length present; no `simple_bit_pack_chunk_post`. |
| `t1_deserialize` | ✗ | ✓ | ✗ | follow-up | No pre on serialized bytes; no `simple_bit_unpack_chunk_post`. |
| `ntt` | ✓ | ✓ | ✗ | follow-up | Bounds present; no per-lane correctness post. |
| `invert_ntt_montgomery` | ✓ | ✓ | ✗ | follow-up | Bounds present; no per-lane correctness post.  **Mont sprint addresses this.** |
| `reduce` | ✓ | ✓ | ✓ | **done** | Per-lane `Spec.MLDSA.Math.reduce_lane_post`; complete. |

Legend:
- ✓ present and clean
- ~ present but mixed (e.g., bounds embedded in correctness post via lane_post, or partial)
- ✗ absent
- "drive-by" = ≤ 30 min effort to surface
- "follow-up" = ≥ 30 min, needs new lemmas / lane-posts / refactoring

## Compliance scorecard

* **5/27 fully compliant** (18%): `decompose`, `compute_hint`,
  `use_hint`, `power2round`, `reduce`.
* **8 drive-by candidates** (~2–3 hrs total).
* **10 follow-up candidates** (estimated 1–2 weeks).
* **4 already complete** (subset of the 5 fully compliant).

## Verdict

The trait deviates significantly from the 3-part pattern.
Arithmetic operations (`add`, `subtract`, `montgomery_multiply`)
declare bounds pre but rely on F* lemmas to discharge bounds
post — preventing call-site reasoning in Rust.  Serialization
and sampling methods omit correctness posts entirely, leaving
callers unable to establish what their outputs mean.  Five
methods (`decompose`, `compute_hint`, `use_hint`,
`power2round`, `reduce`) exemplify full compliance via lane-post
predicates in `traits/specs.rs`.

A drive-by during the Montgomery sprint is **tractable for the
8 arithmetic and conversion methods** (~2–3 hours total).
This surfaces existing F* lemmas (`bounded_add_post`,
`bounded_sub_post`, `shift_left_then_reduce_lane_post`) into
Rust ensures clauses and fills missing `lhs` bound in
`montgomery_multiply`.  No new proof work needed; just type-
system refactoring.

A **separate follow-up sprint** is required for 10
serialization / sampling / transform methods (~1–2 weeks),
which need new lane-post predicates
(`bit_pack_chunk_post`, `bit_unpack_chunk_post`,
rejection_sample lane-posts) or foundational work
(per-lane NTT correctness spec in `Spec.MLDSA.Math`).

## Three representative examples

### Best case: `compute_hint` (`traits.rs:93–107`)

* **Pre**: `gamma2` valid + `is_i32b_array_opaque FIELD_MAX` on
  low/high → bounds-and-lengths ✓.
* **Post**: `result <= 8` + `is_binary_array_8_opaque hint_future`
  → bounds ✓.
* **Post**: `forall8 compute_hint_lane_post` citing
  `Spec.MLDSA.Math.compute_one_hint` → correctness ✓.
* Diagnosis: fully adheres to pattern.  Per-lane post
  (`traits/specs.rs:171–175`) links to canonical
  `Spec.MLDSA.Math`; all three clauses in Rust at call-site.

### Median case: `add` (`traits.rs:50–52`)

* **Pre**: `specs::add_pre(lhs.repr(), rhs.repr())` → checks i32
  overflow ✓.
* **Post**: `specs::add_post(lhs.repr(), rhs.repr(), future(lhs).repr())`
  → states `future == lhs + rhs` ✓ (correctness).
* **Post bounds**: missing from Rust; bounds derivable only
  via F* lemma `bounded_add_post` (`traits/specs.rs:391–406`).
* Diagnosis: pre and correctness complete; bounds post
  embedded in F* lemma, not surfaced to Rust ensures.
  **Drive-by fix**: declare
  `ensures: is_i32b_array_opaque(sum_of_input_bounds) future(lhs)`
  in Rust.

### Worst case: `gamma1_serialize` (`traits.rs:216–223`)

* **Pre**: `is_pos_array_opaque (pow2 gamma1_exponent - 1) simd_unit`
  → bounds ✓.
* **Post**: `Seq.length serialized_future == Seq.length serialized`
  → length preservation only, **no correctness**.
* **Missing**: correctness post linking serialized bytes to
  bit-packing (would need `bit_pack_chunk_post` from
  `traits/specs.rs`, currently defined but not cited in trait).
* Diagnosis: bounds pre/post present; correctness post absent
  entirely.  **Follow-up sprint**: requires authoring/surfacing
  `bit_pack_chunk_post` in trait ensures, then updating both
  portable.rs and avx2.rs impls to cite it.  Estimated ~45–60 min
  per implementation variant.

## Sources

* `libcrux-ml-dsa/src/simd/traits.rs:26–354` (trait `Operations`)
* `libcrux-ml-dsa/src/simd/traits/specs.rs:29–466` (lane-post
  predicates; `bounded_add_post` / `bounded_sub_post` lemmas at
  lines 391–406 & 441–456)
* `libcrux-ml-dsa/proofs/fstar/spec/Spec.MLDSA.Math.fst:1–150`
  (canonical math specs: `montgomery_multiply`, `decompose`,
  `power2round`, `reduce`, `compute_one_hint`)
