//! Unified element struct passed across the FFI boundary.
//!
//! Tagged by `element_type` so one array can mix shape kinds (rectangles, text, future shapes).
//! All coordinates and sizes are in **document-space pixels** — Dart and Rust share the same units
//! end-to-end, no normalization step.
//!
//! Variable-length text lives in a *separate* shared UTF-8 buffer; each text element references
//! its slice via `text_offset` (byte offset) and `text_length` (byte length). Keeping the text
//! out of the struct means this struct stays fixed-size and trivially POD (plain-old-data) —
//! cheap to memcpy and layout-auditable at compile time.
//!
//! `width`/`height` are reused across shape kinds:
//!   - for rectangles: the bounding rect's width and height;
//!   - for text: `height` is the font em-box size (what callers call "font size"); `width` is 0
//!     (our current text renderer doesn't wrap inside a bounded box).
//!
//! `blur`, `outline_thickness` are `u32` (positive pixel sizes, no sub-pixel precision needed).
//! `rotation_deg` is `i32` (can be negative; Rust converts to radians internally).
//!
//! See the `size_of` assertion below for the exact layout — any drift from the Dart-side
//! `FfiElement` struct will fail the compile.

/// Discriminator constants for `FfiElement.element_type`. Kept as bare `u32` constants (not a Rust
/// `enum`) so the wire value is fixed and stable — `#[repr(C)] enum` would let Rust pick a
/// discriminant layout we don't want to bind to.
pub mod element_type {
    pub const RECTANGLE: u32 = 0;
    pub const TEXT: u32 = 1;
}

#[repr(C)]
pub struct FfiElement {
    /// Discriminator — one of the constants in [`element_type`].
    pub element_type: u32,
    // 4 bytes of implicit padding here to align the next `f64` to 8-byte boundary.
    pub x: f64,
    pub y: f64,
    /// Bounding-box width in pixels; 0 for text (unused).
    pub width: f64,
    /// Bounding-box height in pixels; font em-box size for text elements.
    pub height: f64,
    /// Rotation in degrees. Rust converts to radians at render time.
    pub rotation_deg: i32,
    pub fill_color_argb: u32,
    pub outline_color_argb: u32,
    /// Outline thickness in pixels (0 = no outline).
    pub outline_thickness: u32,
    /// Blur radius in pixels (0 = no blur).
    pub blur: u32,
    /// Byte offset into the shared text buffer; 0 when not a text element.
    pub text_offset: u32,
    /// Byte length in the shared text buffer; 0 when not a text element.
    pub text_length: u32,
    /// Generic shape-specific scalar in pixels — interpreted by each renderer:
    /// rectangle = corner radius, text = unused (always 0). Fits in the 4-byte trailing pad
    /// the previous layout already had, so total struct size stays 72 bytes.
    pub shape_param: u32,
}

// Freeze the layout: the Dart side has a matching runtime `sizeOf<FfiElement>() == 72` test, and
// the Rust compile-time asserts below catch drift immediately on rebuild.
const _: () = assert!(std::mem::size_of::<FfiElement>() == 72);
const _: () = assert!(std::mem::align_of::<FfiElement>() == 8);

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ffi_element_is_72_bytes() {
        assert_eq!(std::mem::size_of::<FfiElement>(), 72);
    }

    #[test]
    fn element_type_constants_are_stable() {
        assert_eq!(element_type::RECTANGLE, 0);
        assert_eq!(element_type::TEXT, 1);
    }
}
