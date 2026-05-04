pub mod macros;

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
}

/// A multi-buffer arena for passing variable-length data across FFI.
///
/// Layout: 3 raw pointers + 3 `usize` = 48 bytes on 64-bit targets.
/// Matches Dart `FfiArena` (3 × `Pointer` + 3 × `Size`). No `error_len` here — message length
/// is returned in `FfiError.message_len` so the Dart layout stays in sync.
#[derive_ReprC]
#[repr(C)]
pub struct FfiArena {
    pub text_buf: *const u8,
    pub text_len: usize,
    pub image_buf: *const u8,
    pub image_len: usize,
    pub error_buf: *mut u8,
    pub error_cap: usize,
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

// Result type for FFI operations returning no payload on success.
// repr(C, u8) layout: discriminant(u8) + implicit_pad(1) + payload_union(FfiError=4) = 6 bytes.
// Not #[derive_ReprC] — safer_ffi 0.2.0-rc1 doesn't support derive_ReprC for payload enums.
// The ffi_result! macro generates the repr(C, u8) layout and helper constructors directly.
crate::ffi_result!(FfiResultUnit, u8);

const _: () = assert!(std::mem::size_of::<FfiResultUnit>() == 6);
const _: () = assert!(std::mem::align_of::<FfiResultUnit>() == 2);

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
/// If `arena` is provided, its `error_buf` must be valid for `error_cap` bytes.
pub fn write_error_to_arena(
    arena: Option<&mut FfiArena>,
    code: FfiErrorCode,
    msg: &str,
) -> FfiError {
    let Some(arena_ref) = arena else {
        return FfiError::new(code);
    };

    if arena_ref.error_buf.is_null() || arena_ref.error_cap == 0 {
        return FfiError::new(code);
    }

    let bytes = msg.as_bytes();
    let limit = bytes.len().min(arena_ref.error_cap);
    // Guard: error_cap is stored as usize but message_len is u16. If cap ever exceeds
    // u16::MAX the cast below would silently truncate the length. Catch this in debug builds.
    debug_assert!(
        u16::try_from(arena_ref.error_cap).is_ok(),
        "error_cap {} exceeds u16::MAX",
        arena_ref.error_cap
    );
    // Clamp to the last valid UTF-8 boundary: a plain byte-count truncation can cut a
    // multi-byte codepoint in half, causing `utf8.decode` on the Dart side to throw a
    // FormatException. `valid_up_to()` gives us the byte index of the first invalid byte
    // after the longest valid prefix — always ≤ `limit`.
    let len = match std::str::from_utf8(&bytes[..limit]) {
        Ok(_) => limit,
        Err(e) => e.valid_up_to(),
    };

    // SAFETY: We verified `error_buf` is non-null and `len` is within `error_cap`.
    #[expect(unsafe_code, reason = "FFI arena write")]
    unsafe {
        ptr::copy_nonoverlapping(bytes.as_ptr(), arena_ref.error_buf, len);
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

    fn make_arena(buf: &mut Vec<u8>) -> FfiArena {
        FfiArena {
            text_buf: ptr::null(),
            text_len: 0,
            image_buf: ptr::null(),
            image_len: 0,
            error_buf: buf.as_mut_ptr(),
            error_cap: buf.capacity(),
        }
    }

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
    fn write_error_ascii_fits_exactly() {
        let mut buf = Vec::with_capacity(5);
        let mut arena = make_arena(&mut buf);
        let err = write_error_to_arena(Some(&mut arena), FfiErrorCode::Io, "hello");
        assert_eq!(err.message_len, 5);
        #[expect(unsafe_code, reason = "Test cleanup")]
        // SAFETY: Test cleanup.
        unsafe {
            buf.set_len(5)
        };
        assert_eq!(std::str::from_utf8(&buf).unwrap(), "hello");
    }

    #[test]
    fn write_error_truncates_at_utf8_boundary_not_mid_codepoint() {
        // "aé" is 3 bytes: [0x61, 0xC3, 0xA9]. With cap=2 a naïve byte-count min
        // would write [0x61, 0xC3], which is invalid UTF-8 (orphaned leading byte).
        // The fixed code must write only [0x61] (1 byte) — the longest valid UTF-8 prefix.
        let mut buf = Vec::with_capacity(2);
        let mut arena = make_arena(&mut buf);
        let err = write_error_to_arena(Some(&mut arena), FfiErrorCode::Decode, "aé");
        assert_eq!(
            err.message_len, 1,
            "must stop before the 2-byte 'é', not mid-codepoint"
        );
        #[expect(unsafe_code, reason = "Test cleanup")]
        // SAFETY: Test cleanup.
        unsafe {
            buf.set_len(1)
        };
        assert_eq!(std::str::from_utf8(&buf).unwrap(), "a");
    }

    #[test]
    fn write_error_multibyte_fits_completely() {
        // "éàü" is 6 bytes; with cap=6 all three codepoints must be written intact.
        let mut buf = Vec::with_capacity(6);
        let mut arena = make_arena(&mut buf);
        let err = write_error_to_arena(Some(&mut arena), FfiErrorCode::Font, "éàü");
        assert_eq!(err.message_len, 6);
        #[expect(unsafe_code, reason = "Test cleanup")]
        // SAFETY: Test cleanup.
        unsafe {
            buf.set_len(6)
        };
        assert_eq!(std::str::from_utf8(&buf).unwrap(), "éàü");
    }

    #[test]
    fn write_error_four_byte_codepoint_truncated_cleanly() {
        // '𝄞' (MUSICAL SYMBOL G CLEF) is 4 bytes (U+1D11E). With cap=3, nothing should be
        // written — even 3 bytes would be an incomplete codepoint.
        let mut buf = Vec::with_capacity(3);
        let mut arena = make_arena(&mut buf);
        let err = write_error_to_arena(Some(&mut arena), FfiErrorCode::Render, "𝄞");
        assert_eq!(
            err.message_len, 0,
            "4-byte codepoint must not be written into a 3-byte buffer"
        );
    }
}
