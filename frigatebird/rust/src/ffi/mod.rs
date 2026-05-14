use safer_ffi::prelude::*;
use std::ptr;

/// Error codes for FFI operations.
///
/// The numeric values **are part of the wire contract**: they are encoded in every
/// `FfiError.code` byte that crosses the FFI boundary. The Dart counterpart (`FfiErrorCode`)
/// must list variants in the same order. `u8` is sufficient — only 9 discriminants (0–8).
#[derive_ReprC]
#[repr(u8)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FfiErrorCode {
    Success = 0,
    Panic = 1,
    InvalidArg = 2,
    Io = 3,
    Decode = 4,
    Encode = 5,
    Font = 6,
    Render = 7,
    Utf8 = 8,
    Unknown = 9,
}

/// A multi-buffer arena for passing variable-length data across FFI.
///
/// Layout: 3 raw pointers + 3 `usize` = 48 bytes on 64-bit targets.
/// Matches Dart `FfiArena` exactly. The `error` field is a `c_slice::Box<u8>`
/// (ptr + len) which maps to Dart's `ByteBuffer`.
#[derive_ReprC]
#[repr(C)]
#[derive(Default)]
pub struct FfiArena {
    pub text_buf: *const u8,
    pub text_len: usize,
    // Reserved for future in-place operations (e.g. merge with byte-stream background).
    // Currently always null/0 — no op reads these fields yet.
    pub image_buf: *const u8,
    pub image_len: usize,
    pub error: c_slice::Box<u8>,
}

/// Create a new `FfiArena` with a pre-allocated error buffer.
#[ffi_export]
pub fn ffi_arena_create(error_cap: usize) -> repr_c::Box<FfiArena> {
    let mut arena = FfiArena::default();
    if error_cap > 0 {
        arena.error = vec![0u8; error_cap].into_boxed_slice().into();
    }
    Box::new(arena).into()
}

/// Free an `FfiArena` and its associated buffers.
#[ffi_export]
pub fn ffi_arena_free(arena: repr_c::Box<FfiArena>) {
    drop(arena);
}

/// A structured error returned from FFI.
///
/// Field sizes are chosen to be minimal:
/// - `code`: `u8` — only 9 discriminants (0–8); fits in one byte.
/// - `_pad`: alignment filler so `message_len` lands on a 2-byte boundary.
/// - `message_len`: `u16` — error message lengths up to 65 535 bytes; current arena cap is 256.
///
/// Total size: 4 bytes, alignment: 2.
#[derive_ReprC]
#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct FfiError {
    pub code: u8,
    pub _pad: u8,
    pub message_len: u16,
}

const _: () = assert!(std::mem::size_of::<FfiError>() == 4);

impl FfiError {
    #[inline]
    #[must_use]
    pub fn new(code: FfiErrorCode) -> Self {
        Self {
            code: code as u8,
            _pad: 0,
            message_len: 0,
        }
    }
}

/// Writes a panic message into the arena's error buffer and returns an `FfiError`.
///
/// # Safety
///
/// If `arena` is non-null, it must be a valid pointer to an `FfiArena`.
pub fn write_panic_to_arena(arena: Option<&mut FfiArena>, msg: &str) -> FfiError {
    write_error_to_arena(arena, FfiErrorCode::Panic, msg)
}

/// Writes a custom error message into the arena's error buffer.
///
/// If `arena` is null, or the arena has no error buffer, returns a bare `FfiError` with no
/// message.
///
/// # Safety
///
/// If `arena` is provided, its `error` buffer must be valid.
pub fn write_error_to_arena(
    arena: Option<&mut FfiArena>,
    code: FfiErrorCode,
    msg: &str,
) -> FfiError {
    let Some(arena_ref) = arena else {
        return FfiError::new(code);
    };

    if arena_ref.error.is_empty() {
        return FfiError::new(code);
    }

    let bytes = msg.as_bytes();
    // Leave space for null terminator.
    let limit = bytes.len().min(arena_ref.error.len() - 1);
    // Guard: error cap is stored as usize but message_len is u16. If cap ever exceeds
    // u16::MAX the cast below would silently truncate the length. Catch this in debug builds.
    debug_assert!(
        u16::try_from(arena_ref.error.len()).is_ok(),
        "error cap {} exceeds u16::MAX",
        arena_ref.error.len()
    );
    // Clamp to the last valid UTF-8 boundary: a plain byte-count truncation can cut a
    // multi-byte codepoint in half, causing `utf8.decode` on the Dart side to throw a
    // FormatException. `valid_up_to()` gives us the byte index of the first invalid byte
    // after the longest valid prefix — always ≤ `limit`.
    let len = match std::str::from_utf8(&bytes[..limit]) {
        Ok(_) => limit,
        Err(e) => e.valid_up_to(),
    };

    // SAFETY: We verified `error` is non-empty and `len` is within bounds.
    #[expect(unsafe_code, reason = "FFI arena write")]
    unsafe {
        let error_ptr = arena_ref.error.as_mut_ptr();
        ptr::copy_nonoverlapping(bytes.as_ptr(), error_ptr, len);
        ptr::write(error_ptr.add(len), 0);
    }

    FfiError {
        code: code as u8,
        _pad: 0,
        message_len: u16::try_from(len.min(u16::MAX as usize)).unwrap_or(0),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // ── write_error_to_arena ──────────────────────────────────────────────────────────────────────

    #[test]
    fn write_error_null_arena_returns_bare_error() {
        let err = write_error_to_arena(None, FfiErrorCode::Decode, "msg");
        assert_eq!(err.code, FfiErrorCode::Decode as u8);
        assert_eq!(
            err.message_len, 0,
            "null arena must produce zero-length message"
        );
    }

    #[test]
    fn write_error_cap_one_only_writes_null_terminator() {
        let mut arena = ffi_arena_create(1);
        let err = write_error_to_arena(Some(&mut arena), FfiErrorCode::Render, "hello");
        assert_eq!(err.message_len, 0);
        assert_eq!(arena.error.as_slice()[0], 0);
        ffi_arena_free(arena);
    }

    #[test]
    fn write_error_ascii_fits_exactly() {
        let mut arena = ffi_arena_create(6);
        let err = write_error_to_arena(Some(&mut arena), FfiErrorCode::Io, "hello");
        assert_eq!(err.message_len, 5);
        assert_eq!(
            std::str::from_utf8(&arena.error.as_slice()[..5]).unwrap(),
            "hello"
        );
        ffi_arena_free(arena);
    }

    #[test]
    fn write_error_truncates_at_utf8_boundary_not_mid_codepoint() {
        let mut arena = ffi_arena_create(2);
        let err = write_error_to_arena(Some(&mut arena), FfiErrorCode::Decode, "aé");
        assert_eq!(
            err.message_len, 1,
            "must stop before the 2-byte 'é', not mid-codepoint"
        );
        assert_eq!(
            std::str::from_utf8(&arena.error.as_slice()[..1]).unwrap(),
            "a"
        );
        ffi_arena_free(arena);
    }

    #[test]
    fn write_error_multibyte_fits_completely() {
        let mut arena = ffi_arena_create(7);
        let err = write_error_to_arena(Some(&mut arena), FfiErrorCode::Font, "éàü");
        assert_eq!(err.message_len, 6);
        assert_eq!(
            std::str::from_utf8(&arena.error.as_slice()[..6]).unwrap(),
            "éàü"
        );
        ffi_arena_free(arena);
    }

    #[test]
    fn write_error_four_byte_codepoint_truncated_cleanly() {
        let mut arena = ffi_arena_create(3);
        let err = write_error_to_arena(Some(&mut arena), FfiErrorCode::Render, "𝄞");
        assert_eq!(
            err.message_len, 0,
            "4-byte codepoint must not be written into a 3-byte buffer"
        );
        assert_eq!(arena.error.as_slice()[0], 0);
        ffi_arena_free(arena);
    }
}
