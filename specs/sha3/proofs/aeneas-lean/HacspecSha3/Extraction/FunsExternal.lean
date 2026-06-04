import Aeneas
import HacspecSha3.Extraction.Types
open Aeneas Aeneas.Std Result ControlFlow Error

namespace core.array

private theorem foldlM_list_build_length {T F : Type}
    (step : List T × F → Nat → Result (List T × F))
    (hstep : ∀ l f i r, step (l, f) i = .ok r → r.1.length = l.length + 1) :
    ∀ (l : List Nat) (acc : List T) (f : F) (result : List T × F),
    l.foldlM step (acc, f) = .ok result → result.1.length = acc.length + l.length := by
  intro l
  induction l with
  | nil =>
    intro acc f result h
    simp only [List.foldlM_nil] at h
    have heq : result = (acc, f) := (Result.ok.inj h).symm
    simp [heq]
  | cons x xs ih =>
    intro acc f result h
    simp only [List.foldlM_cons] at h
    cases hstep_x : step (acc, f) x with
    | ok r =>
      obtain ⟨r1, r2⟩ := r
      simp only [hstep_x] at h
      have hlen_r : r1.length = acc.length + 1 := by
        have := hstep acc f x ⟨r1, r2⟩ hstep_x; simpa using this
      have ih' := ih r1 r2 result h
      simp only [List.length_cons]; omega
    | fail e => simp [hstep_x] at h
    | div => simp [hstep_x] at h

/-- [core::array::from_fn]:
    Source: '/rustc/library/core/src/array/mod.rs', lines 110:0-112:52
    Name pattern: [core::array::from_fn]
    Visibility: public -/
@[rust_fun "core::array::from_fn"]
def from_fn
  {T : Type} {F : Type} (N : Std.Usize) (opsfunctionFnMutFTupleUsizeTInst :
  core.ops.function.FnMut F Std.Usize T) :
  F → Result (Array T N) := fun f =>
  match h : (List.range N.val).foldlM
    (fun (s : List T × F) (i : Nat) => do
      let (v, f') ← opsfunctionFnMutFTupleUsizeTInst.call_mut s.2 ⟨BitVec.ofNat _ i⟩
      ok (s.1 ++ [v], f'))
    ([], f) with
  | fail e => fail e
  | div => div
  | ok result => ok ⟨result.1, by
      have hlen := foldlM_list_build_length
        (fun (s : List T × F) (i : Nat) => do
          let (v, f') ← opsfunctionFnMutFTupleUsizeTInst.call_mut s.2 ⟨BitVec.ofNat _ i⟩
          ok (s.1 ++ [v], f'))
        (fun l f i r hr => by
          simp only [] at hr
          cases hcall : opsfunctionFnMutFTupleUsizeTInst.call_mut f ⟨BitVec.ofNat _ i⟩ with
          | ok p =>
            obtain ⟨v, fv⟩ := p
            simp only [hcall, bind_tc_ok] at hr
            have heq : r = (l ++ [v], fv) := (Result.ok.inj hr).symm
            simp [heq, List.length_append]
          | fail e =>
            simp only [hcall, bind_tc_fail] at hr
            exact nomatch hr
          | div =>
            simp only [hcall, bind_tc_div] at hr
            exact nomatch hr)
        _ [] f result h
      simp [List.length_range] at hlen; exact hlen⟩

end core.array
