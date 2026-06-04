import Aeneas
import CoreModels
import HacspecSha3.Extraction.Types
open Aeneas Aeneas.Std Result ControlFlow Error

/-- Adapter from Aeneas's native `core.ops.function.FnMut` to the structurally
identical `core_models.ops.function.FnMut`, so we can reuse the `from_fn`
implementation defined in `rust-core-models`. -/
private def toCoreModelsFnMut
    {F Args Out : Type} (inst : core.ops.function.FnMut F Args Out) :
    core_models.ops.function.FnMut F Args Out :=
  { FnOnceInst := { call_once := inst.FnOnceInst.call_once }
    call_mut := inst.call_mut }

/-- [core::array::from_fn]:
    Source: '/rustc/library/core/src/array/mod.rs', lines 110:0-112:52
    Name pattern: [core::array::from_fn]
    Visibility: public -/
@[rust_fun "core::array::from_fn"]
def core.array.from_fn
  {T : Type} {F : Type} (N : Std.Usize) (opsfunctionFnMutFTupleUsizeTInst :
  core.ops.function.FnMut F Std.Usize T) :
  F → Result (Array T N) :=
  rust_primitives.slice.array_from_fn N
    (toCoreModelsFnMut opsfunctionFnMutFTupleUsizeTInst)
