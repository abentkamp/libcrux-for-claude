#![cfg_attr(hax_backend_lean, feature(register_tool))]
#![cfg_attr(hax_backend_lean, register_tool(charon))]
/// Keccak-f[1600] permutation — exposed for cross-spec testing.
pub mod keccak_f;
mod sha3;
/// Sponge construction — exposed for cross-spec testing.
pub mod sponge;

pub use keccak_f::State;
pub use sha3::{sha3_224, sha3_256, sha3_384, sha3_512, shake128, shake256};
